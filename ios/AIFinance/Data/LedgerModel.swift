import FinanceCore
import Foundation
import Observation

/// 底部的提示條：記好了、刪掉了、沒存成。
struct Toast: Identifiable, Equatable {
    enum Undo: Equatable {
        /// 復原剛記下的那筆：刪掉它。
        case added(Txn)
        /// 復原剛刪掉的那筆：放回來。
        case deleted(Txn)
    }

    let id = UUID()
    let message: String
    var undo: Undo?
}

/// 全部畫面共用的資料與動作。所有數字都從 transactions 當場算出來，不另外存總數。
@MainActor
@Observable
final class LedgerModel {
    private(set) var transactions: [Txn] = []
    private(set) var budgets: [Budget] = []
    private(set) var toast: Toast?
    private(set) var today: String
    /// 有紀錄讀不出來時不開放寫入，免得蓋掉還在的資料。
    private(set) var loadFailed = false
    /// 分類的名字、圖示、顯示哪些、順序。
    private(set) var book = CategoryBook()

    @ObservationIgnored private let store: LocalStore
    @ObservationIgnored private(set) var days = Days.local

    init(store: LocalStore) {
        self.store = store
        self.today = AppConfig.current.today ?? Days.local.day(of: Date())
        do {
            transactions = try store.transactions()
            budgets = try store.budgets()
            book = try store.categoryBook()
        } catch {
            loadFailed = true
        }
    }

    func refreshToday() {
        days = Days.local
        today = AppConfig.current.today ?? days.day(of: Date())
    }

    // MARK: - 給畫面用的資料

    var sections: [DaySection] { Timeline.sections(from: transactions) }
    var isEmpty: Bool { !transactions.contains { $0.deletedAt == nil } }

    func title(for day: String) -> String {
        days.sectionTitle(for: day, today: today)
    }

    func report(month: String) -> MonthReport {
        Analysis.report(month: month, today: today, transactions: transactions, budgets: budgets, book: book, days: days)
    }

    var recentMonths: [MonthTotal] {
        Analysis.recentMonths(today: today, transactions: transactions, days: days)
    }

    var monthlyRange: UsualRange? {
        Analysis.monthlyRange(today: today, transactions: transactions, days: days)
    }

    func category(of row: Txn) -> TxCategory { book.category(of: row) }
    func title(of row: Txn) -> String { book.title(of: row) }

    /// 某個月某一類的支出，金額大的在前。
    func expenses(month: String, categoryId: UUID) -> [Txn] {
        let prefix = String(month.prefix(7))
        return transactions
            .filter {
                $0.deletedAt == nil && $0.type == .expense && $0.occurredOn.hasPrefix(prefix)
                    && book.category(of: $0).id == categoryId
            }
            .sorted { $0.amount == $1.amount ? $0.createdAt > $1.createdAt : $0.amount > $1.amount }
    }

    // MARK: - 動作

    /// 新增一筆。成功回傳 true。
    func add(_ fields: TxnFields) -> Bool {
        let row = Txn(fields: fields, createdAt: Date(), timeZone: days.timeZone.identifier)
        guard write(row) else { return false }
        let category = book.category(of: row)
        let total = Analysis.categoryTotal(
            category.id, month: row.occurredOn, transactions: transactions, book: book, days: days
        )
        let inThisMonth = row.occurredOn.hasPrefix(String(today.prefix(7)))
        // 補記以前月份的，不說「這個月共多少」。
        let message = inThisMonth || category.kind == .income
            ? AnalysisText.saved(category: category, amount: row.amount, monthTotal: total)
            : Words.Ledger.savedEarlier(category, row.amount)
        show(Toast(message: message, undo: .added(row)))
        Haptics.saved()
        return true
    }

    func update(_ row: Txn, with fields: TxnFields) -> Bool {
        guard write(row.applying(fields, at: Date())) else { return false }
        Haptics.saved()
        return true
    }

    func delete(_ row: Txn) {
        var gone = row
        gone.deletedAt = Date()
        if write(gone) {
            Haptics.deleted()
            show(Toast(message: Words.Ledger.deleted(title(of: row)), undo: .deleted(row)))
        }
    }

    func undo(_ toast: Toast) {
        self.toast = nil
        switch toast.undo {
        case .added(let row):
            var gone = row
            gone.deletedAt = Date()
            _ = write(gone)
        case .deleted(let row):
            _ = write(row)
        case nil:
            break
        }
    }

    /// 訂這個月起的預算。0 代表不訂。
    func setBudget(_ amount: Int) -> Bool {
        guard !loadFailed else { return false }
        let budget = Budget(month: days.monthStart(of: today), amount: amount, createdAt: Date())
        do {
            try store.save(budget)
            budgets.append(budget)
            Haptics.saved()
            return true
        } catch {
            fail(Words.Failure.saveToast)
            return false
        }
    }

    // MARK: - 分類

    /// 改分類的設定。change 回傳 false 代表這個改法不行，什麼都不動。
    /// 先寫進手機，成功了畫面才變；沒存成回傳 false，由畫面跳出說明。
    func changeBook(_ change: (inout CategoryBook) -> Bool) -> Bool {
        guard !loadFailed else { return false }
        var next = book
        guard change(&next) else { return false }
        do {
            try store.save(next)
            book = next
            return true
        } catch {
            Haptics.failed()
            return false
        }
    }

    // MARK: - 全部資料

    func deleteAll() -> Bool {
        do {
            try store.wipe()
            transactions = []
            budgets = []
            loadFailed = false
            toast = nil
            removeExports()
            book = CategoryBook()
            Preferences.reset()
            return true
        } catch {
            return false
        }
    }

    /// 匯出 CSV，回傳暫存檔的位置。
    func exportCSV() throws -> URL {
        let csv = CSVExport.make(transactions: transactions, book: book)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(Words.Settings.exportName(today))
        try Data(csv.utf8).write(to: url, options: .atomic)
        return url
    }

    /// 之前匯出留下的暫存檔也一起刪。
    private func removeExports() {
        let files = FileManager.default
        let folder = files.temporaryDirectory
        let names = (try? files.contentsOfDirectory(atPath: folder.path)) ?? []
        for name in names where name.hasSuffix(".csv") {
            try? files.removeItem(at: folder.appendingPathComponent(name))
        }
    }

    private func write(_ row: Txn) -> Bool {
        guard !loadFailed else {
            fail(Words.Failure.loadToast)
            return false
        }
        do {
            try store.save(row)
        } catch {
            fail(Words.Failure.saveToast)
            return false
        }
        if let i = transactions.firstIndex(where: { $0.id == row.id }) {
            transactions[i] = row
        } else {
            transactions.append(row)
        }
        return true
    }

    /// 不能復原的一句話，例如「已複製版本資訊」。
    func notice(_ message: String) {
        show(Toast(message: message))
    }

    private func fail(_ message: String) {
        Haptics.failed()
        show(Toast(message: message))
    }

    private func show(_ toast: Toast) {
        self.toast = toast
        Task { [id = toast.id] in
            try? await Task.sleep(nanoseconds: AppConfig.current.toastSeconds * 1_000_000_000)
            if self.toast?.id == id { self.toast = nil }
        }
    }
}
