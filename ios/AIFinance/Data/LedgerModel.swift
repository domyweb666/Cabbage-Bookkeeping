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
/// 多帳本：手機上存的是全部帳本的（all 開頭的），畫面、合計、預算、固定支出、分析報表只看目前那一本，
/// 所以 transactions、budgets、fixed 都已經是目前那本的，其他畫面不用知道有幾本帳。
@MainActor
@Observable
final class LedgerModel {
    /// 目前那一本帳的紀錄（含刪掉的）。
    private(set) var transactions: [Txn] = []
    /// 目前那一本帳的預算。
    private(set) var budgets: [Budget] = []
    /// 目前那一本帳的固定支出，刪掉的也在裡面（以前的月份要用）。畫面列的是 activeFixed。
    private(set) var fixed: [FixedExpense] = []
    /// 還在用的帳本，「我的帳本」在最前面。
    private(set) var ledgerList: [Ledger] = [.main]
    /// 目前在哪一本。
    private(set) var currentLedgerId = Ledger.mainID
    /// 目前那本進行中的存錢，沒有就是 nil。
    private(set) var savingsGoal: SavingsGoal?
    /// 存到哪裡了。跟著紀錄重算。
    private(set) var savings: SavingsProgress?
    private(set) var toast: Toast?
    private(set) var today: String
    /// 紀錄、預算、固定支出、分類設定有一樣讀不出來就是 true：不列明細、不匯出、不開放寫入，免得顯示錯的或蓋掉還在的資料。
    private(set) var loadFailed = false
    /// 分類的名字、圖示、顯示哪些、順序。
    private(set) var book = CategoryBook()
    /// 明細的每一天。紀錄變了才重排，不在每次重畫時排（效能，2026-11-26）。
    private(set) var sections: [DaySection] = []

    // 全部帳本的資料。只在這個檔裡用，畫面拿上面那幾個。
    /// 全部帳本的紀錄。要被觀察：匯出鈕、帳本選單上的金額看的是它。
    private var allTransactions: [Txn] = []
    @ObservationIgnored private var allBudgets: [Budget] = []
    @ObservationIgnored private var allFixed: [FixedExpense] = []
    /// 存過的帳本，刪掉的也在。
    @ObservationIgnored private var savedLedgers: [Ledger] = []
    @ObservationIgnored private var allGoals: [SavingsGoal] = []
    /// 帳本選單上每本這個月花多少。紀錄變了就丟掉。
    @ObservationIgnored private var cachedLedgerTotals: [UUID: Int] = [:]

    @ObservationIgnored private let store: LocalStore
    @ObservationIgnored private(set) var days = Days.local
    /// 最後一次給小工具的。一樣就不再送。外層 nil 是還沒送過。
    @ObservationIgnored private var published: WidgetSnapshot??
    /// 算過的數字。紀錄、預算、固定支出、分類、今天有一樣變了就整個丟掉（changed()）。
    /// 一次重畫會問好幾次同一個月，資料沒變就不用每次從頭掃全部紀錄。
    @ObservationIgnored private var reports: [String: MonthReport] = [:]
    @ObservationIgnored private var cachedRecent: [MonthTotal]?
    @ObservationIgnored private var cachedRange: UsualRange??
    @ObservationIgnored private var cachedHome: HomeFigures?

    /// saved 是開 app 時在背景讀好的（AIFinanceApp.load）。讀失敗就是 failure，整個不給記。
    init(store: LocalStore, saved: Result<SavedData, any Error>) {
        self.store = store
        self.today = AppConfig.current.today ?? Days.local.day(of: Date())
        switch saved {
        case .success(let data):
            // 全部讀到才用。分類設定讀不出來時，自訂分類會被算成「其他」，明細和匯出都會錯。
            allTransactions = data.transactions
            allFixed = data.fixed
            allBudgets = data.budgets
            book = data.book
            savedLedgers = data.ledgers
            allGoals = data.goals
        case .failure:
            loadFailed = true
        }
        currentLedgerId = Preferences.currentLedger ?? Ledger.mainID
        changed()
        postFixed()
        publish()
    }

    func refreshToday() {
        days = Days.local
        today = AppConfig.current.today ?? days.day(of: Date())
        changed()
        postFixed()
        publish()
    }

    // MARK: - 給畫面用的資料

    var isEmpty: Bool { !transactions.contains { $0.deletedAt == nil } }

    func title(for day: String) -> String {
        days.sectionTitle(for: day, today: today)
    }

    func report(month: String) -> MonthReport {
        let key = days.monthStart(of: month)
        if let saved = reports[key] { return saved }
        let made = Analysis.report(
            month: key, today: today, transactions: transactions, budgets: budgets, book: book, days: days, fixed: fixed
        )
        reports[key] = made
        return made
    }

    /// 記帳頁的本月支出與還能花。只算這兩個數字，不算分析頁的比較。
    var home: HomeFigures {
        if let cachedHome { return cachedHome }
        let made = Analysis.homeFigures(today: today, transactions: transactions, budgets: budgets, fixed: fixed, days: days)
        cachedHome = made
        return made
    }

    var recentMonths: [MonthTotal] {
        if let cachedRecent { return cachedRecent }
        let made = Analysis.recentMonths(today: today, transactions: transactions, days: days)
        cachedRecent = made
        return made
    }

    var monthlyRange: UsualRange? {
        if let cachedRange { return cachedRange }
        let made = Analysis.monthlyRange(today: today, transactions: transactions, days: days, fixed: fixed)
        cachedRange = .some(made)
        return made
    }

    /// 紀錄、預算、固定支出、分類、帳本或今天變了就呼叫：挑出目前那本的，明細重排，算過的數字丟掉。
    private func changed() {
        ledgerList = Ledgers.alive(savedLedgers)
        // 上次那本被刪了（或資料壞了），回到第一本。
        if !ledgerList.contains(where: { $0.id == currentLedgerId }) {
            currentLedgerId = ledgerList.first?.id ?? Ledger.mainID
        }
        let current = currentLedgerId
        transactions = allTransactions.filter { $0.belongs(to: current) }
        budgets = allBudgets.filter { $0.belongs(to: current) }
        fixed = allFixed.filter { $0.belongs(to: current) }
        savingsGoal = Savings.active(in: allGoals, ledger: current)
        savings = savingsGoal.map { Savings.progress(of: $0, transactions: transactions) }
        cachedLedgerTotals = [:]
        sections = Timeline.sections(from: transactions)
        reports = [:]
        cachedRecent = nil
        cachedRange = nil
        cachedHome = nil
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
        let row = Txn(fields: fields, createdAt: Date(), timeZone: days.timeZone.identifier, ledgerId: currentLedgerId)
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
        let budget = Budget(
            month: days.monthStart(of: today), amount: amount, createdAt: Date(), ledgerId: currentLedgerId
        )
        do {
            try store.save(budget)
            allBudgets.append(budget)
            changed()
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
            createdAt: Date(), timeZone: days.timeZone.identifier, estimate: range, ledgerId: currentLedgerId
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
            changed()
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
            // 收據照片和掃過的發票號碼不在資料庫裡，一起清掉。
            try ReceiptPhotos.standard.eraseAll()
            try InvoiceLog.shared.eraseAll()
            allTransactions = []
            allBudgets = []
            allFixed = []
            savedLedgers = []
            allGoals = []
            currentLedgerId = Ledger.mainID
            loadFailed = false
            toast = nil
            removeExports()
            book = CategoryBook()
            changed()
            Preferences.reset()
            publish()
            return true
        } catch {
            return false
        }
    }

    /// 匯出 CSV，回傳暫存檔的位置。全部帳本一起匯出，每筆寫是哪一本。
    func exportCSV() throws -> URL {
        let csv = CSVExport.make(transactions: allTransactions, book: book, ledgers: savedLedgers)
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
        if let i = allTransactions.firstIndex(where: { $0.id == row.id }) {
            allTransactions[i] = row
        } else {
            allTransactions.append(row)
        }
        changed()
        publish()
        return true
    }

    /// 小工具看的那一份。讀不出來的時候給空的，免得它一直顯示舊的數字。
    private func publish() {
        let next = loadFailed
            ? nil
            : WidgetSnapshot(today: today, transactions: transactions, budgets: budgets, fixed: fixed, savings: savings)
        if let last = published, last == next { return }
        // 這次開 app 第一次送才去比檔案：上次關 app 前寫的可能一模一樣，就不用叫小工具重畫。
        // 之後只要跟自己記得的不一樣，檔案一定也不一樣（只有這裡在寫），直接寫。
        let firstTime = published == nil
        published = .some(next)
        WidgetBridge.publish(next, compareWithFile: firstTime)
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
        let item = FixedExpense(fields: fields, startsOn: today, createdAt: Date(), ledgerId: currentLedgerId)
        guard writeFixed(item) else { return false }
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
        if let i = allFixed.firstIndex(where: { $0.id == item.id }) {
            allFixed[i] = item
        } else {
            allFixed.append(item)
        }
        changed()
        publish()
        return true
    }

    /// 把到期的固定支出記下來，每一本帳的都記（記在各自那本）。一次全部存，存不成就一筆都不記，下次打開再試。
    private func postFixed() {
        guard !loadFailed else { return }
        let rows = FixedPlan.due(items: allFixed, transactions: allTransactions, today: today, days: days, now: Date())
        guard !rows.isEmpty else { return }
        do {
            try store.save(rows)
        } catch {
            fail(Words.Failure.saveToast)
            return
        }
        allTransactions += rows
        changed()
        publish()
        // 提示條只講目前這本的，別本的打開那本時明細裡就有。
        let names = rows.filter { $0.belongs(to: currentLedgerId) }.map { (title: title(of: $0), amount: $0.amount) }
        if let message = AnalysisText.posted(names) { show(Toast(message: message)) }
    }
}

// MARK: - 帳本

extension LedgerModel {
    var currentLedger: Ledger {
        ledgerList.first { $0.id == currentLedgerId } ?? ledgerList.first ?? .main
    }

    /// 全部帳本裡有沒有還在的紀錄（匯出用，匯出是全部帳本一起）。
    var hasAnyRecord: Bool { allTransactions.contains { $0.deletedAt == nil } }

    /// 只有一本時，記帳頁不出現換帳本那顆，畫面跟以前一樣。
    var hasManyLedgers: Bool { ledgerList.count > 1 }

    /// 那一本這個月花多少（帳本選單、帳本清單用）。
    func monthExpense(of ledger: UUID) -> Int {
        if let saved = cachedLedgerTotals[ledger] { return saved }
        let month = String(today.prefix(7))
        let total = allTransactions
            .filter { $0.deletedAt == nil && $0.type == .expense && $0.belongs(to: ledger) && $0.occurredOn.hasPrefix(month) }
            .reduce(0) { $0 + $1.amount }
        cachedLedgerTotals[ledger] = total
        return total
    }

    /// 那一本還有幾筆紀錄（刪帳本前的確認用）。
    func recordCount(of ledger: UUID) -> Int {
        allTransactions.filter { $0.deletedAt == nil && $0.belongs(to: ledger) }.count
    }

    func ledgerProblem(_ name: String, excluding id: UUID?) -> Ledgers.Problem? {
        Ledgers.problem(with: name, in: savedLedgers, excluding: id)
    }

    /// 換到另一本。月份、總額、明細、預算、固定支出、存錢、小工具一起換。
    func switchLedger(to id: UUID) {
        guard id != currentLedgerId, ledgerList.contains(where: { $0.id == id }) else { return }
        moveTo(id)
        changed()
        publish()
        Haptics.selected()
    }

    /// 新增一本並換過去。名字不能用或沒存成回傳 false。
    func addLedger(name: String, color: LedgerColor) -> Bool {
        guard !loadFailed, ledgerProblem(name, excluding: nil) == nil else { return false }
        let ledger = Ledger(name: name, color: color, createdAt: Date())
        do {
            try store.save(ledger)
        } catch {
            Haptics.failed()
            return false
        }
        upsertLedger(ledger)
        moveTo(ledger.id)
        changed()
        publish()
        Haptics.saved()
        return true
    }

    func updateLedger(_ ledger: Ledger, name: String, color: LedgerColor) -> Bool {
        guard !loadFailed, ledgerProblem(name, excluding: ledger.id) == nil else { return false }
        let next = ledger.renamed(name, color: color)
        do {
            try store.save(next)
        } catch {
            Haptics.failed()
            return false
        }
        upsertLedger(next)
        changed()
        Haptics.saved()
        return true
    }

    /// 刪一本帳：那本的紀錄、固定支出、存錢跟著刪（留在手機上、不再顯示，跟刪單筆一樣）。
    /// 最後一本不能刪。一次存，存不成就全部不動。
    func deleteLedger(_ ledger: Ledger) -> Bool {
        guard !loadFailed, ledgerList.count > 1, ledgerList.contains(where: { $0.id == ledger.id }) else { return false }
        let now = Date()
        var gone = ledger
        gone.deletedAt = now
        let rows = allTransactions.filter { $0.deletedAt == nil && $0.belongs(to: ledger.id) }.map { row -> Txn in
            var copy = row
            copy.deletedAt = now
            return copy
        }
        let items = allFixed.filter { $0.endedOn == nil && $0.belongs(to: ledger.id) }.map { $0.ended(on: today) }
        let goals = allGoals.filter { $0.deletedAt == nil && $0.belongs(to: ledger.id) }.map { goal -> SavingsGoal in
            var copy = goal
            copy.deletedAt = now
            return copy
        }
        do {
            try store.removeLedger(gone, rows: rows, fixed: items, goals: goals)
        } catch {
            fail(Words.Failure.saveToast)
            return false
        }
        upsertLedger(gone)
        let rowsById = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        allTransactions = allTransactions.map { rowsById[$0.id] ?? $0 }
        let itemsById = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        allFixed = allFixed.map { itemsById[$0.id] ?? $0 }
        let goalsById = Dictionary(uniqueKeysWithValues: goals.map { ($0.id, $0) })
        allGoals = allGoals.map { goalsById[$0.id] ?? $0 }
        if currentLedgerId == ledger.id {
            moveTo(ledgerList.first { $0.id != ledger.id }?.id ?? Ledger.mainID)
        }
        changed()
        publish()
        Haptics.deleted()
        show(Toast(message: Words.Ledger.deleted(ledger.name)))
        return true
    }

    private func moveTo(_ id: UUID) {
        currentLedgerId = id
        Preferences.currentLedger = id
        // 上一本的「復原」不帶到這本來。
        toast = nil
    }

    private func upsertLedger(_ ledger: Ledger) {
        if let i = savedLedgers.firstIndex(where: { $0.id == ledger.id }) {
            savedLedgers[i] = ledger
        } else {
            savedLedgers.append(ledger)
        }
    }
}

// MARK: - 存錢

extension LedgerModel {
    /// 在目前這本開始存錢，從今天起算。這本原本有一個進行中的，就換成新的。
    func startSavings(name: String, target: Int, endsOn: String) -> Bool {
        guard !loadFailed, target > 0 else { return false }
        var changes: [SavingsGoal] = []
        if var old = savingsGoal {
            old.deletedAt = Date()
            changes.append(old)
        }
        changes.append(SavingsGoal(
            ledgerId: currentLedgerId, name: name, target: target, startsOn: today, endsOn: endsOn, createdAt: Date()
        ))
        return writeGoals(changes)
    }

    /// 改名字、金額、日子。開始那天不變。
    func updateSavings(_ goal: SavingsGoal, name: String, target: Int, endsOn: String) -> Bool {
        guard !loadFailed, target > 0 else { return false }
        return writeGoals([goal.changed(name: name, target: target, endsOn: endsOn)])
    }

    /// 不存了。紀錄不動。
    func stopSavings(_ goal: SavingsGoal) -> Bool {
        guard !loadFailed else { return false }
        var gone = goal
        gone.deletedAt = Date()
        do {
            try store.save([gone])
        } catch {
            Haptics.failed()
            return false
        }
        upsertGoal(gone)
        changed()
        publish()
        Haptics.deleted()
        return true
    }

    private func writeGoals(_ goals: [SavingsGoal]) -> Bool {
        do {
            try store.save(goals)
        } catch {
            Haptics.failed()
            return false
        }
        for goal in goals { upsertGoal(goal) }
        changed()
        publish()
        Haptics.saved()
        return true
    }

    private func upsertGoal(_ goal: SavingsGoal) {
        if let i = allGoals.firstIndex(where: { $0.id == goal.id }) {
            allGoals[i] = goal
        } else {
            allGoals.append(goal)
        }
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
