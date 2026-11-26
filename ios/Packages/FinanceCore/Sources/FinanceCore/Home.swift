import Foundation

/// 記帳頁和小工具上的兩個數字。
public struct HomeFigures: Hashable, Sendable {
    public let expense: Int
    public let budget: BudgetStatus?

    public init(expense: Int, budget: BudgetStatus?) {
        self.expense = expense
        self.budget = budget
    }

    /// 小工具上的標題與數字：有預算講還能花，沒有就講本月支出。
    public var label: String { budget.map(AnalysisText.homeBudgetLabel) ?? "本月支出" }
    public var amount: Int { budget.map(AnalysisText.homeBudgetAmount) ?? expense }
}

/// 給小工具的資料。存能重算的原料，換日、換月都由小工具自己算，不用等使用者打開 app。
/// 裡面沒有備註，也沒有這個月以外的明細。只放目前那一本帳的。
public struct WidgetSnapshot: Codable, Hashable, Sendable {
    /// 2：多了 savings（存錢）。
    public static let currentSchema = 2

    public let schemaVersion: Int
    private let rows: [Txn]
    private let budgets: [Budget]
    private let fixed: [FixedExpense]
    /// 目前那本帳進行中的存錢。沒有名字，只有數字。
    public let savings: SavingsProgress?

    public init(
        today: String, transactions: [Txn], budgets: [Budget], fixed: [FixedExpense],
        savings: SavingsProgress? = nil
    ) {
        let month = today.prefix(7)
        // 固定支出記過的期要帶著，小工具才不會重複算。每年一次的看到去年就夠。
        let lastYear = String(format: "%04d", (Int(today.prefix(4)) ?? 1) - 1)
        self.schemaVersion = Self.currentSchema
        self.rows = transactions
            .filter { row in
                let isThisMonth = row.deletedAt == nil && row.type == .expense && row.occurredOn.prefix(7) == month
                return isThisMonth || (row.fixed.map { $0.period >= lastYear } ?? false)
            }
            .map(\.withoutDetails)
        self.budgets = budgets
        self.fixed = fixed.map(\.withoutNote)
        self.savings = savings
    }

    /// 那一天要顯示的數字。還沒打開 app 記進去的固定支出也算。
    public func figures(today: String, days: Days) -> HomeFigures {
        let due = FixedPlan.due(
            items: fixed, transactions: rows, today: today, days: days, now: Date(timeIntervalSince1970: 0)
        )
        return Analysis.homeFigures(
            today: today, transactions: rows + due, budgets: budgets, fixed: fixed, days: days
        )
    }
}

private extension Txn {
    /// 拿掉備註、時間和改過的歷史，留下算數字要的。
    var withoutDetails: Txn {
        var plain = fields
        plain.note = ""
        var copy = Txn(
            id: id, fields: plain, createdAt: Date(timeIntervalSince1970: 0), timeZone: "", fixed: fixed,
            ledgerId: ledgerId
        )
        copy.deletedAt = deletedAt
        return copy
    }
}
