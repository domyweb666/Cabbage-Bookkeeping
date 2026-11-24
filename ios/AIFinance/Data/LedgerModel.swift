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

    @ObservationIgnored private let store: LocalStore
    @ObservationIgnored private(set) var days = Days.local

    private static let saveFailed = "沒有存成功，手機空間可能不夠。"

    init(store: LocalStore) {
        self.store = store
        self.today = AppConfig.current.today ?? Days.local.day(of: Date())
        do {
            transactions = try store.transactions()
            budgets = try store.budgets()
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
        Analysis.report(month: month, today: today, transactions: transactions, budgets: budgets, days: days)
    }

    var recentMonths: [MonthTotal] {
        Analysis.recentMonths(today: today, transactions: transactions, days: days)
    }

    var monthlyRange: UsualRange? {
        Analysis.monthlyRange(today: today, transactions: transactions, days: days)
    }

    /// 某個月某一類的支出，金額大的在前。
    func expenses(month: String, categoryId: UUID) -> [Txn] {
        let prefix = String(month.prefix(7))
        return transactions
            .filter { $0.deletedAt == nil && $0.categoryId == categoryId && $0.occurredOn.hasPrefix(prefix) }
            .sorted { $0.amount == $1.amount ? $0.createdAt > $1.createdAt : $0.amount > $1.amount }
    }

    // MARK: - 動作

    /// 新增一筆。成功回傳 true。
    func add(_ fields: TxnFields) -> Bool {
        let row = Txn(fields: fields, createdAt: Date(), timeZone: days.timeZone.identifier)
        guard write(row) else { return false }
        if let category = row.category {
            let total = Analysis.categoryTotal(category.id, month: row.occurredOn, transactions: transactions, days: days)
            let inThisMonth = row.occurredOn.hasPrefix(String(today.prefix(7)))
            // 補記以前月份的，不說「這個月共多少」。
            let message = inThisMonth || category.kind == .income
                ? AnalysisText.saved(category: category, amount: row.amount, monthTotal: total)
                : "記好了。\(category.name) \(Money.format(row.amount))"
            show(Toast(message: message, undo: .added(row)))
        }
        return true
    }

    func update(_ row: Txn, with fields: TxnFields) -> Bool {
        write(row.applying(fields, at: Date()))
    }

    func delete(_ row: Txn) {
        var gone = row
        gone.deletedAt = Date()
        if write(gone) {
            show(Toast(message: "已刪除「\(row.title)」", undo: .deleted(row)))
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
        let budget = Budget(month: days.monthStart(of: today), amount: amount, createdAt: Date())
        do {
            try store.save(budget)
            budgets.append(budget)
            return true
        } catch {
            show(Toast(message: Self.saveFailed))
            return false
        }
    }

    func deleteAll() -> Bool {
        do {
            try store.wipe()
            transactions = []
            budgets = []
            loadFailed = false
            toast = nil
            return true
        } catch {
            return false
        }
    }

    /// 匯出 CSV，回傳暫存檔的位置。
    func exportCSV() throws -> URL {
        let csv = CSVExport.make(transactions: transactions)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("白菜記帳_\(today).csv")
        try Data(csv.utf8).write(to: url, options: .atomic)
        return url
    }

    private func write(_ row: Txn) -> Bool {
        guard !loadFailed else {
            show(Toast(message: "紀錄讀不出來，先把 App 關掉再開一次。"))
            return false
        }
        do {
            try store.save(row)
        } catch {
            show(Toast(message: Self.saveFailed))
            return false
        }
        if let i = transactions.firstIndex(where: { $0.id == row.id }) {
            transactions[i] = row
        } else {
            transactions.append(row)
        }
        return true
    }

    private func show(_ toast: Toast) {
        self.toast = toast
        Task { [id = toast.id] in
            try? await Task.sleep(nanoseconds: AppConfig.current.toastSeconds * 1_000_000_000)
            if self.toast?.id == id { self.toast = nil }
        }
    }
}
