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

/// 一本帳一列。刪掉的也留著（deletedAt），紀錄才找得到自己屬於哪一本。
@Model
final class StoredLedger {
    @Attribute(.unique) var id: UUID
    var payload: Data

    init(id: UUID, payload: Data) {
        self.id = id
        self.payload = payload
    }
}

/// 存錢一個一列。換一個新的時，舊的標上 deletedAt 留著。
@Model
final class StoredSavings {
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
            for: StoredTxn.self, StoredBudget.self, StoredCategoryBook.self, StoredFixed.self,
            StoredLedger.self, StoredSavings.self, configurations: config
        )
        context = ModelContext(container)
        context.autosaveEnabled = false
    }

    /// 開 app 時讀全部用。拿去背景跑，自己開一個 context，不佔主執行緒。
    var reader: StoreReader { StoreReader(container: container) }

    func transactions() throws -> [Txn] { try StoreReader.transactions(context, decoder) }
    func budgets() throws -> [Budget] { try StoreReader.budgets(context, decoder) }
    func fixedExpenses() throws -> [FixedExpense] { try StoreReader.fixedExpenses(context, decoder) }
    /// 存過的帳本，刪掉的也在。沒存過「我的帳本」的話這裡沒有它，由 Ledgers.alive 補上。
    func ledgers() throws -> [Ledger] { try StoreReader.ledgers(context, decoder) }
    func savingsGoals() throws -> [SavingsGoal] { try StoreReader.savingsGoals(context, decoder) }

    func save(_ ledger: Ledger) throws {
        try upsert(ledger)
        try commit()
    }

    /// 存錢：要換新的時，舊的（標好 deletedAt）跟新的一起存，存不成就兩個都不動。
    func save(_ goals: [SavingsGoal]) throws {
        for goal in goals { try upsert(goal) }
        try commit()
    }

    /// 刪一本帳：帳本、那本的紀錄、固定支出、存錢一次存，存不成就全部不動。
    func removeLedger(_ ledger: Ledger, rows: [Txn], fixed: [FixedExpense], goals: [SavingsGoal]) throws {
        do {
            try upsert(ledger)
            for row in rows { try upsert(row) }
            for item in fixed { try upsert(item) }
            for goal in goals { try upsert(goal) }
        } catch {
            context.rollback()
            throw error
        }
        try commit()
    }

    /// 沒存過就是預設的樣子。
    func categoryBook() throws -> CategoryBook { try StoreReader.categoryBook(context, decoder) }

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
        try upsert(item)
        try commit()
    }

    func wipe() throws {
        do {
            try context.fetch(FetchDescriptor<StoredTxn>()).forEach { context.delete($0) }
            try context.fetch(FetchDescriptor<StoredBudget>()).forEach { context.delete($0) }
            try context.fetch(FetchDescriptor<StoredCategoryBook>()).forEach { context.delete($0) }
            try context.fetch(FetchDescriptor<StoredFixed>()).forEach { context.delete($0) }
            try context.fetch(FetchDescriptor<StoredLedger>()).forEach { context.delete($0) }
            try context.fetch(FetchDescriptor<StoredSavings>()).forEach { context.delete($0) }
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

    private func upsert(_ item: FixedExpense) throws {
        let payload = try encoder.encode(item)
        let id = item.id
        var query = FetchDescriptor<StoredFixed>(predicate: #Predicate<StoredFixed> { $0.id == id })
        query.fetchLimit = 1
        if let row = try context.fetch(query).first {
            row.payload = payload
        } else {
            context.insert(StoredFixed(id: id, payload: payload))
        }
    }

    private func upsert(_ ledger: Ledger) throws {
        let payload = try encoder.encode(ledger)
        let id = ledger.id
        var query = FetchDescriptor<StoredLedger>(predicate: #Predicate<StoredLedger> { $0.id == id })
        query.fetchLimit = 1
        if let row = try context.fetch(query).first {
            row.payload = payload
        } else {
            context.insert(StoredLedger(id: id, payload: payload))
        }
    }

    private func upsert(_ goal: SavingsGoal) throws {
        let payload = try encoder.encode(goal)
        let id = goal.id
        var query = FetchDescriptor<StoredSavings>(predicate: #Predicate<StoredSavings> { $0.id == id })
        query.fetchLimit = 1
        if let row = try context.fetch(query).first {
            row.payload = payload
        } else {
            context.insert(StoredSavings(id: id, payload: payload))
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

/// 開 app 時一次讀到的全部資料。
struct SavedData: @unchecked Sendable {
    var transactions: [Txn]
    var budgets: [Budget]
    var fixed: [FixedExpense]
    var book: CategoryBook
    var ledgers: [Ledger]
    var goals: [SavingsGoal]
}

/// 只讀不寫。ModelContainer 可以跨執行緒，context 不行，所以每次讀都在呼叫的那條執行緒上新開一個。
struct StoreReader: @unchecked Sendable {
    let container: ModelContainer

    func readAll() throws -> SavedData {
        let context = ModelContext(container)
        let decoder = JSONDecoder()
        return SavedData(
            transactions: try Self.transactions(context, decoder),
            budgets: try Self.budgets(context, decoder),
            fixed: try Self.fixedExpenses(context, decoder),
            book: try Self.categoryBook(context, decoder),
            ledgers: try Self.ledgers(context, decoder),
            goals: try Self.savingsGoals(context, decoder)
        )
    }

    static func transactions(_ context: ModelContext, _ decoder: JSONDecoder) throws -> [Txn] {
        try context.fetch(FetchDescriptor<StoredTxn>()).map { try decoder.decode(Txn.self, from: $0.payload) }
    }

    static func budgets(_ context: ModelContext, _ decoder: JSONDecoder) throws -> [Budget] {
        try context.fetch(FetchDescriptor<StoredBudget>()).map { try decoder.decode(Budget.self, from: $0.payload) }
    }

    static func fixedExpenses(_ context: ModelContext, _ decoder: JSONDecoder) throws -> [FixedExpense] {
        try context.fetch(FetchDescriptor<StoredFixed>())
            .map { try decoder.decode(FixedExpense.self, from: $0.payload) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    static func ledgers(_ context: ModelContext, _ decoder: JSONDecoder) throws -> [Ledger] {
        try context.fetch(FetchDescriptor<StoredLedger>()).map { try decoder.decode(Ledger.self, from: $0.payload) }
    }

    static func savingsGoals(_ context: ModelContext, _ decoder: JSONDecoder) throws -> [SavingsGoal] {
        try context.fetch(FetchDescriptor<StoredSavings>())
            .map { try decoder.decode(SavingsGoal.self, from: $0.payload) }
    }

    static func categoryBook(_ context: ModelContext, _ decoder: JSONDecoder) throws -> CategoryBook {
        guard let row = try context.fetch(FetchDescriptor<StoredCategoryBook>()).first else { return CategoryBook() }
        return try decoder.decode(CategoryBook.self, from: row.payload).cleaned()
    }
}
