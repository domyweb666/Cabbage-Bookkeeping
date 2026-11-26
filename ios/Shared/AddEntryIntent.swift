import AppIntents
import Observation

/// 從 App 外面要求打開「記一筆」。
/// asked 由 RootView 接：沒有別的畫面開著就切到記一筆分頁。
@MainActor
@Observable
final class EntryRequest {
    static let shared = EntryRequest()

    var asked = false

    private init() {}

    func ask() { asked = true }
}

/// 控制中心的「記一筆」。會打開 App 的動作要同時編進 App 和小工具，按了才會正常打開。
struct AddEntryIntent: AppIntent {
    static let title: LocalizedStringResource = "記一筆"
    static let description = IntentDescription("打開白菜記帳，直接記一筆。")
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        EntryRequest.shared.ask()
        return .result()
    }
}
