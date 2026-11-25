import FinanceCore
import Foundation
import SwiftData

// 本機儲存（SwiftData）。紀錄就這一份，所以每一次寫入失敗都要往外丟，不能吞掉。
// 每筆存成一段 JSON，升級時不用搬欄位。

@Model
final class StoredTxn {
    @Attribute(.unique) var id: UUID
    var payload: Data

    init(id: UUID, payload: Data) {
        self.id = id
        self.payload = payload
    }
}

@Model
final class StoredBudget {
    @Attribute(.unique) var id: UUID
    var payload: Data

    init(id: UUID, payload: Data) {
        self.id = id
        self.payload = payload
    }
}

@Model
final class StoredFixed {
    @Attribute(.unique) var id: UUID
    var payload: Data

    init(id: UUID, payload: Data) {
        self.id = id
        self.payload = payload
    }
}

/// 分類的設定整份存一列：改過的名字、自己新增的、顯示哪些、順序。
@Model
final class StoredCategoryBook {
    @Attribute(.unique) var id: UUID
    var payload: Data

    init(id: UUID, payload: Data) {
        self.id = id
        self.payload = payload
    }
}

final class LocalStore {
    private static let bookID = UUID(uuid: (0xBA, 0x1C, 0xA1, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, 0))

    private let container: ModelContainer
    private let context: ModelContext
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(inMemory: Bool) throws {
        // 有了 App Group，SwiftData 預設會改放到共用的資料夾。資料庫留在 App 自己這邊，小工具另外給一份快照。
        let config = ModelConfiguration("Baicai", isStoredInMemoryOnly: inMemory, groupContainer: .none)
        container = try ModelContainer(
            for: StoredTxn.self, StoredBudget.self, StoredCategoryBook.self, StoredFixed.self, configurations: config
        )
        context = ModelContext(container)
        context.autosaveEnabled = false
    }

    func transactions() throws -> [Txn] {
        try context.fetch(FetchDescriptor<StoredTxn>()).map { try decoder.decode(Txn.self, from: $0.payload) }
    }

    func budgets() throws -> [Budget] {
        try context.fetch(FetchDescriptor<StoredBudget>()).map { try decoder.decode(Budget.self, from: $0.payload) }
    }

    func fixedExpenses() throws -> [FixedExpense] {
        try context.fetch(FetchDescriptor<StoredFixed>())
            .map { try decoder.decode(FixedExpense.self, from: $0.payload) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// 沒存過就是預設的樣子。
    func categoryBook() throws -> CategoryBook {
        guard let row = try context.fetch(FetchDescriptor<StoredCategoryBook>()).first else { return CategoryBook() }
        return try decoder.decode(CategoryBook.self, from: row.payload).cleaned()
    }

    func save(_ book: CategoryBook) throws {
        let payload = try encoder.encode(book)
        if let row = try context.fetch(FetchDescriptor<StoredCategoryBook>()).first {
            row.payload = payload
        } else {
            context.insert(StoredCategoryBook(id: Self.bookID, payload: payload))
        }
        try commit()
    }

    func save(_ items: [Txn]) throws {
        for item in items { try upsert(item) }
        try commit()
    }

    func save(_ item: Txn) throws {
        try upsert(item)
        try commit()
    }

    func save(_ budget: Budget) throws {
        context.insert(StoredBudget(id: budget.id, payload: try encoder.encode(budget)))
        try commit()
    }

    func save(_ item: FixedExpense) throws {
        let payload = try encoder.encode(item)
        let id = item.id
        var query = FetchDescriptor<StoredFixed>(predicate: #Predicate<StoredFixed> { $0.id == id })
        query.fetchLimit = 1
        if let row = try context.fetch(query).first {
            row.payload = payload
        } else {
            context.insert(StoredFixed(id: id, payload: payload))
        }
        try commit()
    }

    func wipe() throws {
        do {
            try context.fetch(FetchDescriptor<StoredTxn>()).forEach { context.delete($0) }
            try context.fetch(FetchDescriptor<StoredBudget>()).forEach { context.delete($0) }
            try context.fetch(FetchDescriptor<StoredCategoryBook>()).forEach { context.delete($0) }
            try context.fetch(FetchDescriptor<StoredFixed>()).forEach { context.delete($0) }
        } catch {
            context.rollback()
            throw error
        }
        try commit()
    }

    private func upsert(_ item: Txn) throws {
        let payload = try encoder.encode(item)
        let id = item.id
        var query = FetchDescriptor<StoredTxn>(predicate: #Predicate<StoredTxn> { $0.id == id })
        query.fetchLimit = 1
        if let row = try context.fetch(query).first {
            row.payload = payload
        } else {
            context.insert(StoredTxn(id: id, payload: payload))
        }
    }

    private func commit() throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}
