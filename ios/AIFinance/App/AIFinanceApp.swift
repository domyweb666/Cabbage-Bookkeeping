import FinanceCore
import SwiftUI
import UIKit
import VeggieKit

@main
struct AIFinanceApp: App {
    @State private var boot: Boot

    /// 開 app 的三個樣子：資料還在背景讀、讀好了、資料庫打不開。
    private enum Boot {
        case loading(LocalStore)
        case ready(LedgerModel)
        case failed
    }

    init() {
        let config = AppConfig.current
        // 紀錄存在這支手機上，這份資料庫打不開就不能假裝沒事繼續記。
        guard let store = try? LocalStore(inMemory: config.inMemory) else {
            _boot = State(initialValue: .failed)
            return
        }
        if let demo = config.demo {
            let days = Days.local
            let today = config.today ?? days.day(of: Date())
            try? store.save(demo.transactions(today: today, days: days))
            demo.budgets(today: today, days: days).forEach { try? store.save($0) }
            demo.fixed(today: today, days: days).forEach { try? store.save($0) }
        }
        // 畫面測試互不影響：設定從頭開始，要的話連手機上的資料庫也清掉。
        if config.inMemory { Preferences.forget() }
        if config.wipe { try? store.wipe() }
        // 紀錄多的時候解全部資料要一段時間，放背景讀，主執行緒先把畫面畫出來（效能清單第 4 項）。
        _boot = State(initialValue: .loading(store))
    }

    private func load(_ store: LocalStore) async {
        let reader = store.reader
        let saved = await Task.detached(priority: .userInitiated) {
            Result { try reader.readAll() }
        }.value
        boot = .ready(LedgerModel(store: store, saved: saved))
    }

    var body: some Scene {
        WindowGroup {
            Group {
                switch boot {
                case .ready(let model):
                    RootView()
                        .environment(model)
                case .loading(let store):
                    // 只有底色，一下子就換掉。不放「還沒有紀錄」，免得有紀錄的人先看到空的。
                    Theme.background.ignoresSafeArea()
                        .task { await load(store) }
                case .failed:
                    EmptyMessage(title: Words.Failure.storeTitle, message: Words.Failure.storeMessage)
                        .background(Theme.background.ignoresSafeArea())
                }
            }
            .onOpenURL { url in
                // 小工具按下去的網址。認得這一個，其他不理。還在讀資料時也先記著，畫面出來就開。
                if url.scheme == Shared.scheme, url.host() == Shared.entryHost {
                    EntryRequest.shared.ask()
                }
            }
            .tint(Theme.accent)
            // 設定頁選過的外觀。設在視窗上，彈出來的畫面也會一起變。
            .onAppear {
                let appearance = AppConfig.current.forceDark ? Appearance.dark : Appearance.stored
                appearance.apply()
            }
        }
    }
}

/// 三個分頁：設定、記帳、分析。分頁列自己畫（DesignSystem/TabBar.swift），三頁都留著，切過去狀態還在。
private struct RootView: View {
    @Environment(LedgerModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    @State private var page: Page = .ledger

    var body: some View {
        ZStack {
            tab(.settings) { SettingsView() }
            tab(.ledger) { LedgerView() }
            // 分析頁每次記帳都會重算報表，沒選中就不放進畫面，切過來才建（它的 onAppear 會順便更新今天）。
            if page == .analysis {
                tab(.analysis) { AnalysisView() }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { TabBar(page: $page) }
        .onAppear(perform: openEntryIfAsked)
        .onChange(of: EntryRequest.shared.asked) { _, asked in
            if asked { openEntryIfAsked() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.refreshToday() }
        }
    }

    /// 設定、記帳沒選中時藏起來、不給點、讀螢幕也略過，但不拆掉，記帳頁開著的畫面和捲動位置才留得住。
    private func tab(_ which: Page, @ViewBuilder content: () -> some View) -> some View {
        let isOn = page == which
        return content()
            .environment(\.isCurrentPage, isOn)
            .opacity(isOn ? 1 : 0)
            .allowsHitTesting(isOn)
            .accessibilityHidden(!isOn)
    }

    /// 小工具或控制中心要求記一筆。已經有別的畫面開著就不打斷，免得填到一半的不見。
    private func openEntryIfAsked() {
        let request = EntryRequest.shared
        guard request.asked else { return }
        request.asked = false
        guard !hasPresentedScreen else { return }
        page = .ledger
        request.pending = true
    }

    private var hasPresentedScreen: Bool {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .contains { $0.rootViewController?.presentedViewController != nil }
    }
}
