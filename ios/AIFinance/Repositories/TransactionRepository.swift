import FinanceCore
import Foundation

/// 交易的讀寫。畫面只跟 Repository 講話，不直接碰後端或本機資料庫（規格第 12 節第 5 條）。
@MainActor
final class TransactionRepository {
    private let backend: Backend
    private let store: LocalStore

    init(backend: Backend, store: LocalStore) {
        self.backend = backend
        self.store = store
    }

    var isDemo: Bool { backend.isDemo }

    // MARK: - 本機快取（離線也能看）

    func cachedTransactions() -> [Txn] { store.transactions() }
    func cachedCategories() -> [TxCategory] { store.categories() }

    /// 連線時與伺服器比對更新。
    func refresh() async throws -> (transactions: [Txn], categories: [TxCategory]) {
        try await backend.ensureSession()
        async let remoteCategories = backend.fetchCategories()
        async let remoteTransactions = backend.fetchTransactions()
        let (categories, transactions) = try await (remoteCategories, remoteTransactions)
        store.saveCategories(categories)
        store.replaceTransactions(transactions)
        return (transactions, categories)
    }

    /// 記帳或確認後由伺服器回來的新交易，放進快取。
    func absorb(_ items: [Txn]) {
        store.upsert(items)
    }

    // MARK: - 編輯、刪除、復原

    func create(_ fields: TxnFields) async throws -> Txn {
        let row = try await backend.createTransaction(fields)
        store.upsert([row])
        return row
    }

    func update(id: UUID, fields: TxnFields) async throws -> Txn {
        let row = try await backend.updateTransaction(id: id, fields: fields)
        store.upsert([row])
        return row
    }

    /// 軟刪除。
    func delete(_ id: UUID) async throws {
        try await backend.setDeleted(id: id, deleted: true)
        store.removeTransaction(id)
    }

    /// 復原軟刪除。
    func restore(_ item: Txn) async throws {
        try await backend.setDeleted(id: item.id, deleted: false)
        store.upsert([item])
    }

    func rawText(entryId: UUID) async -> String? {
        try? await backend.fetchRawText(entryId: entryId)
    }

    // MARK: - 概覽與設定

    func overview(monthOf day: String) async throws -> MonthlyOverview {
        try await backend.monthlyOverview(monthOf: day)
    }

    func profile() async throws -> Profile {
        try await backend.fetchProfile()
    }

    func updateProfile(_ profile: Profile) async throws {
        try await backend.updateProfile(profile)
    }

    var isLinked: Bool {
        get async { await backend.isLinked }
    }

    /// 用 Apple ID 備份。回傳 true 代表換成了原本就綁著這個 Apple ID 的帳號，
    /// 這時手機上的快取已經清空，呼叫端要重新同步。
    func linkApple(idToken: String, rawNonce: String, allowSwitch: Bool) async throws -> Bool {
        let switched = try await backend.linkApple(idToken: idToken, rawNonce: rawNonce, allowSwitch: allowSwitch)
        if switched { store.wipe() }
        return switched
    }

    /// 匯出 CSV，回傳暫存檔的位置（交給系統的分享面板）。
    func exportCSV() async throws -> URL {
        let transactions = try await backend.fetchTransactions()
        let categories = try await backend.fetchCategories()
        let csv = CSVExport.make(transactions: transactions, categories: categories)
        let name = "白菜記帳_\(Days.taipei.day(of: Date())).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try Data(csv.utf8).write(to: url, options: .atomic)
        return url
    }

    /// 刪除伺服器與本機的所有資料。
    func deleteAll() async throws {
        try await backend.deleteAllData()
        store.wipe()
    }
}
