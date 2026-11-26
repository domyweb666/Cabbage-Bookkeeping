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

// MARK: - 分析頁的看法（2026-11-26）

// 分析頁可以選四種看法：一句話、還能花、月曆、圓餅。一句話和還能花用上面的 report，
// 這裡是另外三種要的數字：每天花多少、這週跟上週、各類佔多少。定義寫在 .analytics/05 的 M9 到 M11。

/// 某一天花了多少。固定支出和補的大概不算在裡面。
public struct DaySpend: Identifiable, Hashable, Sendable {
    /// yyyy-MM-dd
    public let day: String
    public let amount: Int
    public let count: Int
    /// 這個月還沒到的日子。
    public let isFuture: Bool

    public var id: String { day }
    public var number: Int { Days.number(of: day) }
}

/// 一個月每天花多少（M9）。
public struct DailySpending: Hashable, Sendable {
    /// 1 號到月底，一天一個。
    public let days: [DaySpend]
    /// 沒畫進每天的：固定支出和補的大概。
    public let hidden: Int

    /// 越深花越多，分幾級（不含 0）。
    public static let levels = 3

    public var maxAmount: Int { days.map(\.amount).max() ?? 0 }

    /// 花最多的那一天，一樣多取前面那天。一天都沒花就沒有。
    public var top: DaySpend? {
        var best: DaySpend?
        for day in days where day.amount > (best?.amount ?? 0) { best = day }
        return best
    }

    /// 0 是沒花，1 到 levels 照跟最多那天比，切成等分。
    public func level(of day: DaySpend) -> Int {
        let most = maxAmount
        guard day.amount > 0, most > 0 else { return 0 }
        let raw = Int((Double(day.amount) * Double(Self.levels) / Double(most)).rounded(.up))
        return min(Self.levels, max(1, raw))
    }
}

/// 這週到今天，跟上週同幾天比（M10）。一週從週日開始，跟月曆一樣。
public struct WeekComparison: Hashable, Sendable {
    public let thisWeek: DayRange
    public let lastWeek: DayRange
    public let thisAmount: Int
    public let lastAmount: Int
}

/// 圓餅的一塊（M11）。
public struct PieSlice: Identifiable, Hashable, Sendable {
    /// 小的合成一塊時是 nil。
    public let category: TxCategory?
    public let amount: Int
    /// 0 到 100 的整數，全部加起來剛好 100。
    public let percent: Int
    /// 合起來的有幾類；一般的一塊是 1。
    public let merged: Int

    public var id: String { category?.id.uuidString ?? "rest" }
}

extension Analysis {
    /// 圓餅最多單獨畫幾類，其他合成一塊。
    public static let pieTop = 5

    /// 每天花多少。固定支出不畫，不然房租那天永遠最深；補的大概不知道是哪一天花的，也不畫。
    public static func daily(month anyDay: String, today: String, transactions: [Txn], days: Days) -> DailySpending {
        let month = days.monthStart(of: anyDay)
        let prefix = String(month.prefix(8))
        let expenses = inMonth(month, transactions).filter { $0.deletedAt == nil && $0.type == .expense }
        let drawn = expenses.filter { $0.fixed == nil && $0.estimate == nil }
        let byDay = Dictionary(grouping: drawn, by: \.occurredOn)
        let list = (1...max(1, days.length(ofMonth: month))).map { number -> DaySpend in
            let day = prefix + String(format: "%02d", number)
            let rows = byDay[day] ?? []
            return DaySpend(day: day, amount: sum(rows), count: rows.count, isFuture: day > today)
        }
        return DailySpending(days: list, hidden: sum(expenses) - sum(drawn))
    }

    /// 這週（週日到今天）跟上週同幾天。上週一筆自己記的都沒有就不比，免得拿空的一週來比。
    /// 固定支出和補的大概不算，跟每天花多少一樣。
    public static func weekComparison(today: String, transactions: [Txn], days: Days) -> WeekComparison? {
        let start = days.adding(days: -days.weekday(of: today), to: today)
        let lastStart = days.adding(days: -7, to: start)
        let lastEnd = days.adding(days: -7, to: today)
        let rows = transactions.filter {
            $0.deletedAt == nil && $0.type == .expense && $0.fixed == nil && $0.estimate == nil
        }
        let thisRows = rows.filter { $0.occurredOn >= start && $0.occurredOn <= today }
        let lastRows = rows.filter { $0.occurredOn >= lastStart && $0.occurredOn <= lastEnd }
        guard !lastRows.isEmpty else { return nil }
        return WeekComparison(
            thisWeek: DayRange(from: start, to: today),
            lastWeek: DayRange(from: lastStart, to: lastEnd),
            thisAmount: sum(thisRows),
            lastAmount: sum(lastRows)
        )
    }

    /// 圓餅：用 report 的分類金額（M4），前 pieTop 類各一塊，其他合成一塊。只多一類時不合，直接畫出來。
    public static func slices(of lines: [CategoryLine], top: Int = Analysis.pieTop) -> [PieSlice] {
        let shown = lines.filter { $0.total > 0 }
        let total = shown.reduce(0) { $0 + $1.total }
        guard total > 0 else { return [] }
        let keep = shown.count - 1 > top ? Array(shown.prefix(top)) : shown
        let rest = shown.dropFirst(keep.count)
        var amounts = keep.map(\.total)
        if !rest.isEmpty { amounts.append(rest.reduce(0) { $0 + $1.total }) }
        let percents = percents(of: amounts)
        var result = keep.enumerated().map { i, line in
            PieSlice(category: line.category, amount: line.total, percent: percents[i], merged: 1)
        }
        if !rest.isEmpty {
            result.append(PieSlice(category: nil, amount: amounts[keep.count], percent: percents[keep.count], merged: rest.count))
        }
        return result
    }

    /// 換成整數百分比，加起來剛好 100：先捨去，差的照餘數大的補，一樣大補前面的。
    static func percents(of amounts: [Int]) -> [Int] {
        let total = amounts.reduce(0, +)
        guard total > 0 else { return amounts.map { _ in 0 } }
        var result = amounts.map { $0 * 100 / total }
        let short = 100 - result.reduce(0, +)
        let order = amounts.indices.sorted { a, b in
            let ra = amounts[a] * 100 % total
            let rb = amounts[b] * 100 % total
            return ra == rb ? a < b : ra > rb
        }
        for i in order.prefix(short) { result[i] += 1 }
        return result
    }
}

extension Days {
    /// 月曆上一排的星期，從週日開始。
    public static let weekdayNames = ["日", "一", "二", "三", "四", "五", "六"]

    /// 那一天是星期幾：0 是週日，6 是週六。
    public func weekday(of day: String) -> Int {
        guard let date = date(of: day) else { return 0 }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return (calendar.component(.weekday, from: date) + 6) % 7
    }
}
