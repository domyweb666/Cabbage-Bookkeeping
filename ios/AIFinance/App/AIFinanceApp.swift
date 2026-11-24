import FinanceCore
import SwiftUI
import VeggieKit

@main
struct AIFinanceApp: App {
    @State private var model: LedgerModel?

    init() {
        let config = AppConfig.current
        // 紀錄存在這支手機上，這份資料庫打不開就不能假裝沒事繼續記。
        guard let store = try? LocalStore(inMemory: config.inMemory) else {
            _model = State(initialValue: nil)
            return
        }
        if let demo = config.demo {
            let days = Days.local
            let today = config.today ?? days.day(of: Date())
            try? store.save(demo.transactions(today: today, days: days))
            demo.budgets(today: today, days: days).forEach { try? store.save($0) }
        }
        // 畫面測試互不影響：設定從頭開始，要的話連手機上的資料庫也清掉。
        if config.inMemory { Preferences.forget() }
        if config.wipe { try? store.wipe() }
        _model = State(initialValue: LedgerModel(store: store))
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let model {
                    RootView().environment(model)
                } else {
                    EmptyMessage(title: Words.Failure.storeTitle, message: Words.Failure.storeMessage)
                        .background(Theme.background.ignoresSafeArea())
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

/// 三個分頁：記帳、分析、設定。
private struct RootView: View {
    @Environment(LedgerModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            LedgerView()
                .tabItem { Label(Words.Tab.ledger, systemImage: "list.bullet") }
            AnalysisView()
                .tabItem { Label(Words.Tab.analysis, systemImage: "chart.bar.fill") }
            SettingsView()
                .tabItem { Label(Words.Tab.settings, systemImage: "gearshape.fill") }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.refreshToday() }
        }
    }
}
