import FinanceCore
import SwiftUI

@main
struct AIFinanceApp: App {
    @State private var model: TimelineViewModel
    @State private var speech = SpeechService()
    @State private var network = NetworkMonitor()

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
    }

    var body: some Scene {
        WindowGroup {
            TimelineView()
                .environment(model)
                .environment(speech)
                .tint(Theme.accent)
                .onAppear {
                    model.connectivityChanged(online: network.isOnline)
                    network.observe { online in model.connectivityChanged(online: online) }
                }
        }
    }
}
