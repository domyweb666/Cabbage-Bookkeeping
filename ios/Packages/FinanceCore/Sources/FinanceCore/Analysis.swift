import Foundation

// 分析頁的所有算法。定義與理由寫在 .analytics/05-指標字典-暫定.md，題目在 01-問題清單-暫定.md，兩邊要一起改。

/// 平常範圍：前幾個可以比的月份裡，同一段期間最少與最多各花多少。
public struct UsualRange: Hashable, Sendable {
    public let low: Int
    public let high: Int
    /// 用了幾個月來算。
    public let months: Int

    public init(low: Int, high: Int, months: Int) {
        self.low = low
        self.high = high
        self.months = months
    }
}

/// 這個月能不能跟平常比。
public enum Comparison: Hashable, Sendable {
    /// 這個月還沒有支出。
    case empty
    /// 有一段太長的空窗。空窗不當成零，直接不比。
    case gap(days: Int)
    /// 月初天數太少。
    case tooEarly
    /// 可以比的月份不夠，還差幾個月。
    case notEnough(monthsNeeded: Int)
    case ready(UsualRange)

    public var range: UsualRange? {
        if case .ready(let range) = self { return range }
        return nil
    }
}

/// 一個分類這個月的數字。
public struct CategoryLine: Identifiable, Hashable, Sendable {
    public let category: TxCategory
    /// 全部金額，含一次性。
    public let total: Int
    public let oneOff: Int
    public let count: Int
    /// 這個分類平常同期的範圍（不含一次性）。資料不夠就沒有。
    public let usual: UsualRange?

    public var id: UUID { category.id }
    public var routine: Int { total - oneOff }
}

/// 一個過了門檻的現象（觀察）。名字避開系統的 Observation 模組。分析頁一次最多說一個。
public struct SpendingNote: Hashable, Sendable {
    public let category: TxCategory
    public let amount: Int
    public let count: Int
    public let usual: UsualRange
}

public struct MonthTotal: Identifiable, Hashable, Sendable {
    public let month: String
    /// nil 代表這個月沒有任何紀錄，跟花了 0 元不一樣。
    public let expense: Int?
    public let isCurrent: Bool

    public var id: String { month }
}

public struct BudgetStatus: Hashable, Sendable {
    public let budget: Int
    /// 這個月記的，不含每年一次的固定支出。
    public let spent: Int
    /// 這個月還沒到的每月固定。
    public let pending: Int
    /// 每年一次的，這個月先留的十二分之一。
    public let yearlyShare: Int
    /// 這個月記了多少每年一次的固定支出。
    public let yearlyPaid: Int
    /// 含今天還剩幾天；看以前的月份時是 0。
    public let daysLeft: Int

    /// 先留給固定支出的。
    public var reserved: Int { pending + yearlyShare }
    public var left: Int { budget - spent - reserved }
    /// 剩下的錢分給剩下的天數。超過預算或月份已經結束就沒有。
    public var perDay: Int? { left > 0 && daysLeft > 0 ? left / daysLeft : nil }
}

public struct MonthReport: Hashable, Sendable {
    /// yyyy-MM-01
    public let month: String
    public let isCurrent: Bool
    /// 算到這個月的第幾天。
    public let throughDay: Int
    public let expense: Int
    public let oneOff: Int
    public let income: Int
    public let expenseCount: Int
    public let comparison: Comparison
    public let categories: [CategoryLine]
    public let observation: SpendingNote?
    public let biggest: [Txn]
    public let budget: BudgetStatus?
    /// 一段太長的空窗，可以補一個大概的數字。
    public let gapToFill: DayRange?

    /// 拿來跟平常比的數字：不含一次性。
    public var routine: Int { expense - oneOff }
}

public enum Analysis {
    // 門檻都是起點值（⚪），量到真的數字再改，改了要寫進指標字典的改版紀錄。
    /// 一個月至少幾筆支出才拿來當比較對象。
    public static let minRecords = 10
    /// 連續幾天以內沒有紀錄，還算正常。
    public static let maxGapDays = 7
    /// 這個月過了幾天才開始跟平常比。
    public static let compareFromDay = 7
    /// 這個月過了幾天才說觀察。
    public static let observeFromDay = 14
    /// 觀察要超出平常範圍邊緣的幾成。
    public static let observeRatio = 0.3
    /// 觀察至少要差多少錢。
    public static let observeAmount = 300
    /// 至少幾個月、最多幾個月拿來算平常範圍。
    public static let minBaselineMonths = 2
    public static let maxBaselineMonths = 3
    /// 往前找幾個月。
    public static let lookbackMonths = 6
    /// 列幾筆最大的支出。
    public static let biggestCount = 3

    // MARK: - 一個月的報告

    public static func report(
        month anyDay: String, today: String, transactions: [Txn], budgets: [Budget], book: CategoryBook, days: Days,
        fixed: [FixedExpense] = []
    ) -> MonthReport {
        let month = days.monthStart(of: anyDay)
        let isCurrent = month == days.monthStart(of: today)
        let throughDay = isCurrent ? Days.number(of: today) : days.length(ofMonth: month)
        let alive = transactions.filter { $0.deletedAt == nil }
        let rows = inMonth(month, alive)
        let expenses = rows.filter { $0.type == .expense }
        let expense = sum(expenses)

        let baseline = comparableMonths(before: month, transactions: alive, days: days)
        let baselineExpenses = baseline.map { m in
            // 這個月還沒過完，就拿以前同一天為止的金額比；過完了就整個月比整個月。
            inMonth(m, alive).filter {
                $0.type == .expense && !$0.isOneOff
                    && (!isCurrent || $0.estimate != nil || Days.number(of: $0.occurredOn) <= throughDay)
            }
        }
        let comparison = compare(
            rows: rows, expenses: expenses, isCurrent: isCurrent, throughDay: throughDay, baseline: baselineExpenses
        )
        let lines = categoryLines(
            expenses: expenses, baseline: comparison.range == nil ? [] : baselineExpenses, book: book
        )
        let budget = budgetStatus(
            month: month, today: today, expenses: expenses, transactions: transactions, budgets: budgets,
            fixed: fixed, days: days
        )

        return MonthReport(
            month: month,
            isCurrent: isCurrent,
            throughDay: throughDay,
            expense: expense,
            oneOff: sum(expenses.filter(\.isOneOff)),
            income: sum(rows.filter { $0.type == .income }),
            expenseCount: expenses.count,
            comparison: comparison,
            categories: lines,
            observation: observe(
                lines: lines, expenses: expenses, baseline: baselineExpenses, throughDay: throughDay, book: book
            ),
            biggest: biggest(of: expenses),
            budget: budget,
            gapToFill: gapToFill(
                rows: rows, month: month, isCurrent: isCurrent, throughDay: throughDay,
                firstDay: alive.filter { $0.fixed == nil }.map(\.occurredOn).min()
            )
        )
    }

    /// 記帳頁和小工具上的數字。跟 report 用同一套算法，少算比較的部分。
    public static func homeFigures(
        today: String, transactions: [Txn], budgets: [Budget], fixed: [FixedExpense], days: Days
    ) -> HomeFigures {
        let month = days.monthStart(of: today)
        let expenses = inMonth(month, transactions).filter { $0.deletedAt == nil && $0.type == .expense }
        return HomeFigures(
            expense: sum(expenses),
            budget: budgetStatus(
                month: month, today: today, expenses: expenses, transactions: transactions, budgets: budgets,
                fixed: fixed, days: days
            )
        )
    }

    /// 還能花 = 預算 − 這個月記的（每年一次的不算）− 還沒到的每月固定 − 每年一次的十二分之一。
    private static func budgetStatus(
        month: String, today: String, expenses: [Txn], transactions: [Txn], budgets: [Budget],
        fixed: [FixedExpense], days: Days
    ) -> BudgetStatus? {
        guard let amount = Budget.amount(for: month, in: budgets) else { return nil }
        let isCurrent = month == days.monthStart(of: today)
        let length = days.length(ofMonth: month)
        let lastDay = String(month.prefix(8)) + String(format: "%02d", length)
        let yearly = expenses.filter { $0.fixed?.isYearly == true }
        return BudgetStatus(
            budget: amount,
            spent: sum(expenses) - sum(yearly),
            pending: isCurrent
                ? FixedPlan.pending(items: fixed, transactions: transactions, today: today, days: days) : 0,
            yearlyShare: FixedPlan.yearlyShare(items: fixed, month: month, on: isCurrent ? today : lastDay),
            yearlyPaid: sum(yearly),
            daysLeft: isCurrent ? length - Days.number(of: today) + 1 : 0
        )
    }

    /// 最大的幾筆。大概的數字不是一筆花費，不列。
    private static func biggest(of expenses: [Txn]) -> [Txn] {
        guard handCount(expenses) >= minRecords else { return [] }
        return Array(
            expenses.filter { $0.estimate == nil }
                .sorted { $0.amount == $1.amount ? $0.createdAt > $1.createdAt : $0.amount > $1.amount }
                .prefix(biggestCount)
        )
    }

    /// 最近幾個月的支出，舊的在前。第一筆紀錄以前的月份不列。
    public static func recentMonths(today: String, transactions: [Txn], days: Days) -> [MonthTotal] {
        let alive = transactions.filter { $0.deletedAt == nil }
        guard let first = alive.map(\.occurredOn).min() else { return [] }
        let current = days.monthStart(of: today)
        let firstMonth = days.monthStart(of: first)
        return (0..<lookbackMonths).reversed().compactMap { back in
            let month = days.adding(months: -back, toMonthOf: current)
            guard month >= firstMonth else { return nil }
            let rows = inMonth(month, alive)
            return MonthTotal(
                month: month,
                expense: rows.isEmpty ? nil : sum(rows.filter { $0.type == .expense }),
                isCurrent: month == current
            )
        }
    }

    /// 訂預算時給的參考：最近幾個可以比的月份，整個月花多少（含一次性，因為預算也含）。
    /// 每年一次的固定支出不整筆算，改加每個月先留的那一份，跟還能花的算法一致。
    public static func monthlyRange(
        today: String, transactions: [Txn], days: Days, fixed: [FixedExpense] = []
    ) -> UsualRange? {
        let alive = transactions.filter { $0.deletedAt == nil }
        let months = comparableMonths(before: days.monthStart(of: today), transactions: alive, days: days)
        guard months.count >= minBaselineMonths else { return nil }
        let share = FixedPlan.yearlyShare(items: fixed, month: today, on: today)
        return range(months.map { month in
            share + sum(inMonth(month, alive).filter { $0.type == .expense && $0.fixed?.isYearly != true })
        })
    }

    /// 某個分類這個月到目前為止的金額（記完一筆之後那一行用）。
    public static func categoryTotal(
        _ categoryId: UUID, month anyDay: String, transactions: [Txn], book: CategoryBook, days: Days
    ) -> Int {
        sum(inMonth(days.monthStart(of: anyDay), transactions).filter {
            $0.deletedAt == nil && book.category(of: $0).id == categoryId
        })
    }

    // MARK: - 可以拿來比的月份

    /// 往前找可以比的月份：支出筆數夠、中間沒有太長的空窗。
    static func comparableMonths(before month: String, transactions: [Txn], days: Days) -> [String] {
        var found: [String] = []
        for back in 1...lookbackMonths where found.count < maxBaselineMonths {
            let m = days.adding(months: -back, toMonthOf: month)
            let rows = inMonth(m, transactions)
            guard handCount(rows.filter { $0.type == .expense }) >= minRecords,
                  longestGap(rows, through: days.length(ofMonth: m)) <= maxGapDays else { continue }
            found.append(m)
        }
        return found
    }

    /// 從一號到指定那天，最長連續幾天沒有紀錄。月初還沒開始記、記到一半停掉都算。
    /// 自動記的不算有在記帳；補過大概的那幾天算。
    static func longestGap(_ rows: [Txn], through day: Int) -> Int {
        let recorded = recordedDays(rows)
        var longest = 0
        var run = 0
        for d in stride(from: 1, through: day, by: 1) {
            run = recorded.contains(d) ? 0 : run + 1
            longest = max(longest, run)
        }
        return longest
    }

    private static func recordedDays(_ rows: [Txn]) -> Set<Int> {
        var recorded = Set<Int>()
        for row in rows where row.fixed == nil {
            recorded.insert(Days.number(of: row.occurredOn))
            if let estimate = row.estimate {
                recorded.formUnion(coveredDays(estimate))
            }
        }
        return recorded
    }

    private static func coveredDays(_ range: DayRange) -> Set<Int> {
        let from = Days.number(of: range.from)
        let to = Days.number(of: range.to)
        return from <= to ? Set(from...to) : []
    }

    /// 自己記的有幾筆。大概的數字抵那幾天，一天算一筆。
    private static func handCount(_ expenses: [Txn]) -> Int {
        expenses.reduce(0) { count, row in
            guard row.fixed == nil else { return count }
            return count + (row.estimate.map { coveredDays($0).count } ?? 1)
        }
    }

    /// 最長的一段空窗。開始用之前的日子不算，今天還沒過完也不算。
    private static func gapToFill(
        rows: [Txn], month: String, isCurrent: Bool, throughDay: Int, firstDay: String?
    ) -> DayRange? {
        guard let firstDay, longestGap(rows, through: throughDay) > maxGapDays else { return nil }
        let prefix = String(month.prefix(8))
        guard firstDay.prefix(7) <= month.prefix(7) else { return nil }
        let start = firstDay.hasPrefix(prefix) ? Days.number(of: firstDay) + 1 : 1
        let last = isCurrent ? throughDay - 1 : throughDay
        let recorded = recordedDays(rows)
        var best: (from: Int, length: Int) = (0, 0)
        var length = 0
        for day in stride(from: start, through: last, by: 1) {
            length = recorded.contains(day) ? 0 : length + 1
            if length > best.length { best = (day - length + 1, length) }
        }
        guard best.length >= maxGapDays else { return nil }
        func text(_ day: Int) -> String { prefix + String(format: "%02d", day) }
        return DayRange(from: text(best.from), to: text(best.from + best.length - 1))
    }

    private static func compare(
        rows: [Txn], expenses: [Txn], isCurrent: Bool, throughDay: Int, baseline: [[Txn]]
    ) -> Comparison {
        if expenses.isEmpty { return .empty }
        // 剛開始用的人先看到還差多少資料，不先看到空窗。
        if baseline.count < minBaselineMonths { return .notEnough(monthsNeeded: minBaselineMonths - baseline.count) }
        if isCurrent && throughDay < compareFromDay { return .tooEarly }
        let gap = longestGap(rows, through: throughDay)
        if gap > maxGapDays { return .gap(days: gap) }
        let cutoff = isCurrent ? throughDay : nil
        return .ready(range(baseline.map { month in month.reduce(0) { $0 + $1.amount(throughDay: cutoff) } }))
    }

    // MARK: - 分類與觀察

    private static func categoryLines(expenses: [Txn], baseline: [[Txn]], book: CategoryBook) -> [CategoryLine] {
        // 找不到分類的算在「其他」，不能漏掉。
        Dictionary(grouping: expenses) { book.category(of: $0) }.map { category, items -> CategoryLine in
            // 大概的數字不知道花在哪，不拿來說這一類平常多少。
            let past = baseline.map { month in
                month.filter { $0.estimate == nil && book.category(of: $0).id == category.id }
            }
            let hasEstimate = items.contains { $0.estimate != nil }
            // 至少兩個月真的有這一類，才有「平常」可言。
            let usual = !hasEstimate && past.filter { !$0.isEmpty }.count >= minBaselineMonths
                ? range(past.map { sum($0) }) : nil
            return CategoryLine(
                category: category, total: sum(items), oneOff: sum(items.filter(\.isOneOff)),
                count: items.count, usual: usual
            )
        }
        .sorted { $0.total == $1.total ? $0.category.name < $1.category.name : $0.total > $1.total }
    }

    private static func observe(
        lines: [CategoryLine], expenses: [Txn], baseline: [[Txn]], throughDay: Int, book: CategoryBook
    ) -> SpendingNote? {
        guard throughDay >= observeFromDay else { return nil }
        let candidates = lines.compactMap { line -> (SpendingNote, Int)? in
            guard let usual = line.usual else { return nil }
            let count = expenses.filter { book.category(of: $0).id == line.id && !$0.isOneOff }.count
            let pastCount = baseline.reduce(0) { total, month in
                total + month.filter { $0.estimate == nil && book.category(of: $0).id == line.id }.count
            }
            guard count >= minRecords, pastCount >= minRecords else { return nil }
            let edge = line.routine > usual.high ? usual.high : usual.low
            let difference = abs(line.routine - edge)
            guard line.routine > usual.high || line.routine < usual.low,
                  difference >= observeAmount,
                  Double(difference) >= Double(edge) * observeRatio else { return nil }
            return (
                SpendingNote(category: line.category, amount: line.routine, count: count, usual: usual),
                difference
            )
        }
        return candidates.max { $0.1 < $1.1 }?.0
    }

    // MARK: - 小工具

    private static func inMonth(_ month: String, _ transactions: [Txn]) -> [Txn] {
        let prefix = String(month.prefix(7))
        return transactions.filter { $0.occurredOn.hasPrefix(prefix) }
    }

    private static func sum(_ rows: [Txn]) -> Int {
        rows.reduce(0) { $0 + $1.amount }
    }

    private static func range(_ values: [Int]) -> UsualRange {
        UsualRange(low: values.min() ?? 0, high: values.max() ?? 0, months: values.count)
    }
}
