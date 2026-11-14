import FinanceCore
import Foundation
import SwiftData

// 本機儲存（SwiftData）：顯示用的快取、離線待送佇列、最近的回答卡。
// 每筆資料存成一段 JSON，結構跟後端回來的一樣，升級時不用搬欄位。

@Model
final class CachedTxn {
    @Attribute(.unique) var id: UUID
    var payload: Data

    init(id: UUID, payload: Data) {
        self.id = id
        self.payload = payload
    }
}

@Model
final class StoredPending {
    @Attribute(.unique) var id: UUID
    var payload: Data

    init(id: UUID, payload: Data) {
        self.id = id
        self.payload = payload
    }
}

@Model
final class StoredAnswer {
    @Attribute(.unique) var id: UUID
    var payload: Data
    var createdAt: Date

    init(id: UUID, payload: Data, createdAt: Date) {
        self.id = id
        self.payload = payload
        self.createdAt = createdAt
    }
}

/// 回答卡：不寫入交易，最近 20 則保存在本機（規格 7.4）。
struct AnswerCard: Codable, Identifiable, Hashable {
    let id: UUID
    let question: String
    let answer: AskAnswer
    let createdAt: Date
}

@MainActor
final class LocalStore {
    static let maxAnswers = 20
    private static let categoriesKey = "cached_categories"

    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(inMemory: Bool) {
        let config = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        do {
            container = try ModelContainer(for: CachedTxn.self, StoredPending.self, StoredAnswer.self, configurations: config)
        } catch {
            // 本機資料庫打不開時退回記憶體模式，App 仍可使用，資料以伺服器為準。
            container = try! ModelContainer(
                for: CachedTxn.self, StoredPending.self, StoredAnswer.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        }
    }

    private func save() {
        try? context.save()
    }

    // MARK: - 交易快取

    func transactions() -> [Txn] {
        let rows = (try? context.fetch(FetchDescriptor<CachedTxn>())) ?? []
        return rows.compactMap { try? decoder.decode(Txn.self, from: $0.payload) }
    }

    func replaceTransactions(_ items: [Txn]) {
        try? context.delete(model: CachedTxn.self)
        for item in items {
            if let data = try? encoder.encode(item) { context.insert(CachedTxn(id: item.id, payload: data)) }
        }
        save()
    }

    func upsert(_ items: [Txn]) {
        let existing = (try? context.fetch(FetchDescriptor<CachedTxn>())) ?? []
        let byId = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for item in items {
            guard let data = try? encoder.encode(item) else { continue }
            if let row = byId[item.id] { row.payload = data } else { context.insert(CachedTxn(id: item.id, payload: data)) }
        }
        save()
    }

    func removeTransaction(_ id: UUID) {
        let rows = (try? context.fetch(FetchDescriptor<CachedTxn>())) ?? []
        rows.filter { $0.id == id }.forEach { context.delete($0) }
        save()
    }

    // MARK: - 分類快取

    func categories() -> [TxCategory] {
        guard let data = UserDefaults.standard.data(forKey: Self.categoriesKey) else { return [] }
        return (try? decoder.decode([TxCategory].self, from: data)) ?? []
    }

    func saveCategories(_ items: [TxCategory]) {
        if let data = try? encoder.encode(items) { UserDefaults.standard.set(data, forKey: Self.categoriesKey) }
    }

    // MARK: - 待送佇列

    func pending() -> [PendingEntry] {
        let rows = (try? context.fetch(FetchDescriptor<StoredPending>())) ?? []
        return rows.compactMap { try? decoder.decode(PendingEntry.self, from: $0.payload) }
            .sorted { $0.clientCreatedAt < $1.clientCreatedAt }
    }

    func savePending(_ entry: PendingEntry) {
        guard let data = try? encoder.encode(entry) else { return }
        let rows = (try? context.fetch(FetchDescriptor<StoredPending>())) ?? []
        if let row = rows.first(where: { $0.id == entry.id }) { row.payload = data } else {
            context.insert(StoredPending(id: entry.id, payload: data))
        }
        save()
    }

    func removePending(_ id: UUID) {
        let rows = (try? context.fetch(FetchDescriptor<StoredPending>())) ?? []
        rows.filter { $0.id == id }.forEach { context.delete($0) }
        save()
    }

    // MARK: - 回答卡

    func answers() -> [AnswerCard] {
        let rows = (try? context.fetch(FetchDescriptor<StoredAnswer>())) ?? []
        return rows.compactMap { try? decoder.decode(AnswerCard.self, from: $0.payload) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func addAnswer(_ card: AnswerCard) {
        guard let data = try? encoder.encode(card) else { return }
        context.insert(StoredAnswer(id: card.id, payload: data, createdAt: card.createdAt))
        let rows = ((try? context.fetch(FetchDescriptor<StoredAnswer>())) ?? []).sorted { $0.createdAt < $1.createdAt }
        rows.dropLast(Self.maxAnswers).forEach { context.delete($0) }
        save()
    }

    func removeAnswer(_ id: UUID) {
        let rows = (try? context.fetch(FetchDescriptor<StoredAnswer>())) ?? []
        rows.filter { $0.id == id }.forEach { context.delete($0) }
        save()
    }

    // MARK: - 全部清除

    func wipe() {
        try? context.delete(model: CachedTxn.self)
        try? context.delete(model: StoredPending.self)
        try? context.delete(model: StoredAnswer.self)
        UserDefaults.standard.removeObject(forKey: Self.categoriesKey)
        save()
    }
}
