import FinanceCore
import Foundation

/// 後端回來的錯誤。message 都是可以直接給使用者看的繁體中文。
enum BackendError: Error, Equatable {
    /// 連不上（離線、逾時）。
    case network
    /// 伺服器回了錯誤。
    case server(code: String, message: String)

    var message: String {
        switch self {
        case .network: return "現在連不上網路，請稍後再試。"
        case .server(_, let message): return message
        }
    }

    var isNetwork: Bool { self == .network }
}

/// 手動新增或修改一筆交易時送出的欄位。
struct TxnFields: Encodable {
    var type: TxType
    var amount: Int
    var occurredOn: String
    var item: String
    var merchant: String?
    var categoryId: UUID
    var categorySource: String
    var tags: [String]
    var nature: Nature?
    var note: String?

    enum CodingKeys: String, CodingKey {
        case type, amount, occurredOn, item, merchant, categoryId, categorySource, tags, nature, note
    }

    // 空值也要明確送出 null，否則清空商家、備註不會生效。
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(type, forKey: .type)
        try c.encode(amount, forKey: .amount)
        try c.encode(occurredOn, forKey: .occurredOn)
        try c.encode(item, forKey: .item)
        try c.encode(merchant, forKey: .merchant)
        try c.encode(categoryId, forKey: .categoryId)
        try c.encode(categorySource, forKey: .categorySource)
        try c.encode(tags, forKey: .tags)
        try c.encode(nature, forKey: .nature)
        try c.encode(note, forKey: .note)
    }
}

/// App 跟後端之間的所有往來。畫面不直接用它，一律經 Repository。
protocol Backend: AnyObject {
    /// 是否已綁定 Apple ID。
    var isLinked: Bool { get async }
    /// 示範模式（沒有設定後端）時為 true。
    var isDemo: Bool { get }

    /// 確保已登入；第一次開啟時自動匿名登入。
    func ensureSession() async throws

    func record(entryId: UUID, rawText: String, source: String, clientCreatedAt: String) async throws -> RecordResult
    func confirm(entryId: UUID, drafts: [Draft]) async throws -> RecordResult
    func cancelConfirm(entryId: UUID) async throws
    func ask(question: String) async throws -> AskAnswer

    func fetchCategories() async throws -> [TxCategory]
    func fetchTransactions() async throws -> [Txn]
    func createTransaction(_ fields: TxnFields) async throws -> Txn
    func updateTransaction(id: UUID, fields: TxnFields) async throws -> Txn
    func setDeleted(id: UUID, deleted: Bool) async throws
    func fetchRawText(entryId: UUID) async throws -> String?

    func monthlyOverview(monthOf day: String) async throws -> MonthlyOverview
    func fetchProfile() async throws -> Profile
    func updateProfile(_ profile: Profile) async throws

    func deleteAllData() async throws
    func linkApple(idToken: String, rawNonce: String) async throws
}
