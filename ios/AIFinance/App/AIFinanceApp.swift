import FinanceCore
import SwiftUI

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
        _model = State(initialValue: LedgerModel(store: store))
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let model {
                    RootView().environment(model)
                } else {
                    StoreErrorView()
                }
            }
            .tint(Theme.accent)
            .preferredColorScheme(AppConfig.current.forceDark ? .dark : nil)
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
                .tabItem { Label("記帳", systemImage: "list.bullet") }
            AnalysisView()
                .tabItem { Label("分析", systemImage: "chart.bar.fill") }
            SettingsView()
                .tabItem { Label("設定", systemImage: "gearshape.fill") }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.refreshToday() }
        }
    }
}

private struct StoreErrorView: View {
    var body: some View {
        VStack(spacing: Theme.Gap.item) {
            Text("打不開紀錄").font(.title3.weight(.semibold))
            Text("先把 App 整個關掉再開一次。手機空間不夠時也會這樣，清出空間後再試。紀錄還在，沒有被刪掉。")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(Theme.Gap.section)
    }
}
