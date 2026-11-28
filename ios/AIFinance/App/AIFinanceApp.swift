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
        // 廣告 SDK 先在背景準備，切到明細、分析時比較快出來。
        Ads.start()
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

/// 分頁列四格：設定、記一筆、明細、分析，系統原生分頁列，開 app 停在明細。
/// 記一筆那格是醒目的實心圓，點了彈出記一筆視窗，記下後切到明細（多米 2026-11-28）。
/// 開 app 也自動彈出來（2026-11-27），離開超過 5 分鐘再回來也會彈。
private struct RootView: View {
    @Environment(LedgerModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme

    @State private var page: Page = .ledger
    @State private var showEntry = false
    /// 什麼時候退到背景。離開夠久再回來，當作「重新打開」，自動彈記一筆。
    @State private var leftAt: Date?

    /// 離開多久回來算重新打開。短短切去別的 app 看一下再回來，不打斷正在看的頁面。
    private static let reopenAfter: TimeInterval = 5 * 60

    var body: some View {
        TabView(selection: selection) {
            SettingsView()
                .environment(\.isCurrentPage, page == .settings)
                .tabItem { Label(Words.Tab.settings, systemImage: "gearshape.fill") }
                .tag(Page.settings)
            // 不是一頁，選不到：點了只彈記一筆視窗，分頁停在原本那頁。
            Theme.background.ignoresSafeArea()
                .tabItem {
                    Label {
                        Text(Words.Tab.entry)
                    } icon: {
                        Image(uiImage: entryIcon)
                    }
                }
                .tag(Page.entry)
            LedgerView()
                .environment(\.isCurrentPage, page == .ledger)
                .tabItem { Label(Words.Tab.ledger, systemImage: "list.bullet") }
                .tag(Page.ledger)
            // 分析頁每次記帳都會重算報表，沒選中就不建，切過來才建（它的 onAppear 會順便更新今天）。
            Group {
                if page == .analysis {
                    AnalysisView()
                } else {
                    Theme.background.ignoresSafeArea()
                }
            }
            .environment(\.isCurrentPage, page == .analysis)
            .tabItem { Label(Words.Tab.analysis, systemImage: "chart.bar.fill") }
            .tag(Page.analysis)
        }
        .sheet(isPresented: $showEntry) {
            EntrySheet(mode: .new) { page = .ledger }
        }
        .onAppear {
            if AppConfig.current.autoEntry, !model.loadFailed { EntryRequest.shared.ask() }
            openEntryIfAsked()
        }
        .onChange(of: EntryRequest.shared.asked) { _, asked in
            if asked { openEntryIfAsked() }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                leftAt = Date()
            case .active:
                model.refreshToday()
                if let leftAt, Date().timeIntervalSince(leftAt) >= Self.reopenAfter,
                   AppConfig.current.autoEntry, !model.loadFailed {
                    EntryRequest.shared.ask()
                }
                leftAt = nil
            default:
                break
            }
        }
    }

    /// 點分頁列：記一筆那格只彈視窗，不切過去。
    private var selection: Binding<Page> {
        Binding {
            page
        } set: { picked in
            if picked == .entry {
                Haptics.selected()
                EntryRequest.shared.ask()
            } else {
                page = picked
            }
        }
    }

    /// 記一筆那格的圖：實心主色圓配加號，不跟著分頁列的灰色走，一眼看得到（照多米貼的參考圖）。
    /// 自己畫成點陣圖：給系統符號的話，分頁列會用符號自帶的多彩樣式重畫成綠色（2026-11-28 CI 截圖）。
    /// 淺色、深色各一張，照外觀挑。不用 UIImageAsset，它會把倍率弄丟、圖變三倍大。
    private static let entryIconLight = drawEntryIcon(
        UIColor(Theme.accent).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)), plus: .white)
    private static let entryIconDark = drawEntryIcon(
        UIColor(Theme.accent).resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark)),
        plus: UIColor(Theme.onAccent).resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark)))

    private var entryIcon: UIImage { colorScheme == .dark ? Self.entryIconDark : Self.entryIconLight }

    private static func drawEntryIcon(_ fill: UIColor, plus: UIColor) -> UIImage {
        let side: CGFloat = 26
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            fill.setFill()
            UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: side, height: side)).fill()
            let arm: CGFloat = 12
            let thick: CGFloat = 2.5
            let mid = side / 2
            plus.setFill()
            UIBezierPath(roundedRect: CGRect(x: mid - arm / 2, y: mid - thick / 2, width: arm, height: thick), cornerRadius: thick / 2).fill()
            UIBezierPath(roundedRect: CGRect(x: mid - thick / 2, y: mid - arm / 2, width: thick, height: arm), cornerRadius: thick / 2).fill()
        }
        return image.withRenderingMode(.alwaysOriginal)
    }

    /// 要開記一筆（開 app、小工具、控制中心、分頁列那格）。已經有別的畫面開著就不打斷，免得填到一半的不見。
    private func openEntryIfAsked() {
        let request = EntryRequest.shared
        guard request.asked else { return }
        request.asked = false
        guard !showEntry, !hasPresentedScreen else { return }
        model.refreshToday()
        showEntry = true
    }

    private var hasPresentedScreen: Bool {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .contains { $0.rootViewController?.presentedViewController != nil }
    }
}
