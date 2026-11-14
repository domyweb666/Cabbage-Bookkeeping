import FinanceCore
import SwiftUI

@main
struct AIFinanceApp: App {
    @State private var model: TimelineViewModel
    @State private var speech = SpeechService()
    @State private var network = NetworkMonitor()
    @State private var coach: CoachController

    init() {
        let config = AppConfig.current
        let backend: Backend
        if let supabase = config.supabase {
            backend = SupabaseBackend(baseURL: supabase.url, anonKey: supabase.anonKey)
        } else {
            // 沒有設定雲端時用示範後端，App 仍然可以操作。
            backend = MockBackend(seeded: config.seedDemoData)
        }
        let store = LocalStore(inMemory: config.supabase == nil)
        _model = State(initialValue: TimelineViewModel(
            transactionRepository: TransactionRepository(backend: backend, store: store),
            entryRepository: EntryRepository(backend: backend, store: store)
        ))
        _coach = State(initialValue: CoachController())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(coach)
                .environment(model)
                .environment(speech)
                .tint(Theme.accent)
                .preferredColorScheme(AppConfig.current.forceDark ? .dark : nil)
                .onAppear {
                    model.connectivityChanged(online: network.isOnline)
                    network.observe { online in model.connectivityChanged(online: online) }
                }
        }
    }
}

/// 主畫面加上聚光燈引導的遮罩。遮罩 0.25 秒淡入淡出。
private struct RootView: View {
    @Environment(CoachController.self) private var coach

    var body: some View {
        TimelineView()
            .overlay {
                if coach.isActive {
                    CoachOverlay().transition(.opacity)
                }
            }
            .animation(.easeOut(duration: CoachStyle.fadeSeconds), value: coach.isActive)
    }
}
