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
        /// 復原剛刪掉的固定支出：放回來。
        case fixedEnded(FixedExpense)
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
    /// 固定支出，刪掉的也在裡面（以前的月份要用）。畫面列的是 activeFixed。
    private(set) var fixed: [FixedExpense] = []
    private(set) var toast: Toast?
    private(set) var today: String
    /// 紀錄、預算、固定支出、分類設定有一樣讀不出來就是 true：不列明細、不匯出、不開放寫入，免得顯示錯的或蓋掉還在的資料。
    private(set) var loadFailed = false
    /// 分類的名字、圖示、顯示哪些、順序。
    private(set) var book = CategoryBook()

    @ObservationIgnored private let store: LocalStore
    @ObservationIgnored private(set) var days = Days.local
    /// 最後一次給小工具的。一樣就不再送。外層 nil 是還沒送過。
    @ObservationIgnored private var published: WidgetSnapshot??

    init(store: LocalStore) {
        self.store = store
        self.today = AppConfig.current.today ?? Days.local.day(of: Date())
        do {
            // 全部讀到才用。分類設定讀不出來時，自訂分類會被算成「其他」，明細和匯出都會錯。
            let savedRows = try store.transactions()
            let savedBudgets = try store.budgets()
            let savedFixed = try store.fixedExpenses()
            let savedBook = try store.categoryBook()
            transactions = savedRows
            fixed = savedFixed
            budgets = savedBudgets
            book = savedBook
        } catch {
            loadFailed = true
        }
        postFixed()
        publish()
    }

    func refreshToday() {
        days = Days.local
        today = AppConfig.current.today ?? days.day(of: Date())
        postFixed()
        publish()
    }

    // MARK: - 給畫面用的資料

    var sections: [DaySection] { Timeline.sections(from: transactions) }
    var isEmpty: Bool { !transactions.contains { $0.deletedAt == nil } }

    func title(for day: String) -> String {
        days.sectionTitle(for: day, today: today)
    }

    func report(month: String) -> MonthReport {
        Analysis.report(
            month: month, today: today, transactions: transactions, budgets: budgets, book: book, days: days, fixed: fixed
        )
    }

    var recentMonths: [MonthTotal] {
        Analysis.recentMonths(today: today, transactions: transactions, days: days)
    }

    var monthlyRange: UsualRange? {
        Analysis.monthlyRange(today: today, transactions: transactions, days: days, fixed: fixed)
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
        case .fixedEnded(let item):
            if writeFixed(item.resumed()) { postFixed() } else { fail(Words.Failure.saveToast) }
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
            publish()
            Haptics.saved()
            return true
        } catch {
            fail(Words.Failure.saveToast)
            return false
        }
    }

    /// 補一段空窗的大概。記在「其他」，日期是那一段的最後一天。
    func addEstimate(range: DayRange, amount: Int) -> Bool {
        let row = Txn(
            fields: TxnFields(
                type: .expense, amount: amount, occurredOn: range.to, categoryId: Categories.named(Words.Ledger.otherCategory).id
            ),
            createdAt: Date(), timeZone: days.timeZone.identifier, estimate: range
        )
        guard write(row) else { return false }
        show(Toast(message: Words.Analysis.savedEstimate(amount), undo: .added(row)))
        Haptics.saved()
        return true
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
            fixed = []
            loadFailed = false
            toast = nil
            removeExports()
            book = CategoryBook()
            Preferences.reset()
            publish()
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
        publish()
        return true
    }

    /// 小工具看的那一份。讀不出來的時候給空的，免得它一直顯示舊的數字。
    private func publish() {
        let next = loadFailed
            ? nil
            : WidgetSnapshot(today: today, transactions: transactions, budgets: budgets, fixed: fixed)
        if let last = published, last == next { return }
        published = .some(next)
        WidgetBridge.publish(next)
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

    // MARK: - 固定支出

    /// 還在用的。每月的照幾號排，每年的照月日排。
    func activeFixed(isYearly: Bool) -> [FixedExpense] {
        fixed.filter { $0.endedOn == nil && $0.schedule.isYearly == isYearly }
            .sorted { ($0.schedule.order, $0.createdAt) < ($1.schedule.order, $1.createdAt) }
    }

    var activeFixedCount: Int { fixed.filter { $0.endedOn == nil }.count }

    func category(of item: FixedExpense) -> TxCategory {
        let other = Categories.named(Words.Ledger.otherCategory)
        return book.find(item.categoryId) ?? book.find(other.id) ?? other
    }

    func title(of item: FixedExpense) -> String {
        item.note.isEmpty ? category(of: item).name : item.note
    }

    /// 下一次會記在哪天。這一期記過了就看下一期。
    func nextDue(of item: FixedExpense) -> String? {
        let posted = Set(transactions.compactMap { $0.fixed?.itemId == item.id ? $0.fixed?.period : nil })
        var day = today
        for _ in 0..<3 {
            guard let due = item.nextDue(from: day, days: days) else { return nil }
            if !posted.contains(String(due.prefix(item.schedule.isYearly ? 4 : 7))) { return due }
            day = days.adding(days: 1, to: due)
        }
        return nil
    }

    func addFixed(_ fields: FixedFields) -> Bool {
        guard writeFixed(FixedExpense(fields: fields, startsOn: today, createdAt: Date())) else { return false }
        Haptics.saved()
        // 到期日就是今天的，現在就記。
        postFixed()
        return true
    }

    func updateFixed(_ item: FixedExpense, with fields: FixedFields) -> Bool {
        guard writeFixed(item.applying(fields, on: today)) else { return false }
        Haptics.saved()
        postFixed()
        return true
    }

    /// 刪掉之後不再記，記過的不動。
    func endFixed(_ item: FixedExpense) {
        guard writeFixed(item.ended(on: today)) else {
            fail(loadFailed ? Words.Failure.loadToast : Words.Failure.saveToast)
            return
        }
        Haptics.deleted()
        show(Toast(message: Words.Ledger.deleted(title(of: item)), undo: .fixedEnded(item)))
    }

    private func writeFixed(_ item: FixedExpense) -> Bool {
        guard !loadFailed else { return false }
        do {
            try store.save(item)
        } catch {
            return false
        }
        if let i = fixed.firstIndex(where: { $0.id == item.id }) {
            fixed[i] = item
        } else {
            fixed.append(item)
        }
        publish()
        return true
    }

    /// 把到期的固定支出記下來。一次全部存，存不成就一筆都不記，下次打開再試。
    private func postFixed() {
        guard !loadFailed else { return }
        let rows = FixedPlan.due(items: fixed, transactions: transactions, today: today, days: days, now: Date())
        guard !rows.isEmpty else { return }
        do {
            try store.save(rows)
        } catch {
            fail(Words.Failure.saveToast)
            return
        }
        transactions += rows
        publish()
        let names = rows.map { (title: title(of: $0), amount: $0.amount) }
        if let message = AnalysisText.posted(names) { show(Toast(message: message)) }
    }
}

private extension FixedSchedule {
    /// 排序用。
    var order: Int {
        switch self {
        case .monthly(let day): return day
        case .yearly(let month, let day): return month * 100 + day
        }
    }
}
