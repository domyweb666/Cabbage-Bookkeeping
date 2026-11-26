import Foundation

// 存錢：訂一個金額和日子，從開始那天起，這本帳記的收入減支出就是存下來的，不用另外按。
// 一本帳同時一個進行中的。

public struct SavingsGoal: Codable, Identifiable, Hashable, Sendable, LedgerOwned {
    public static let currentSchema = 1
    public static let maxNameLength = 12

    public let id: UUID
    /// 哪一本帳。nil 是「我的帳本」。
    public let ledgerId: UUID?
    /// 存來做什麼。可以是空的。
    public private(set) var name: String
    public private(set) var target: Int
    /// 從這天起算（yyyy-MM-dd），含這天。
    public let startsOn: String
    /// 在這天前存到（yyyy-MM-dd），含這天。
    public private(set) var endsOn: String
    public let createdAt: Date
    /// 不存了、或換了一個新的。
    public var deletedAt: Date?
    public let schemaVersion: Int

    public init(
        id: UUID = UUID(), ledgerId: UUID?, name: String, target: Int, startsOn: String, endsOn: String,
        createdAt: Date
    ) {
        self.id = id
        self.ledgerId = ledgerId
        self.name = Self.clean(name)
        self.target = target
        self.startsOn = startsOn
        self.endsOn = endsOn
        self.createdAt = createdAt
        self.deletedAt = nil
        self.schemaVersion = Self.currentSchema
    }

    /// 改名字、金額、日子。開始那天不變，存下來的照算。
    public func changed(name: String, target: Int, endsOn: String) -> SavingsGoal {
        var copy = self
        copy.name = Self.clean(name)
        copy.target = target
        copy.endsOn = endsOn
        return copy
    }

    public static func clean(_ name: String) -> String {
        String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxNameLength))
    }
}

/// 存到哪裡了。小工具也放一份，所以不帶名字（使用者打的字不進快照）。
public struct SavingsProgress: Codable, Hashable, Sendable {
    public let target: Int
    public let endsOn: String
    /// 收入減支出，小於 0 當 0。
    public let saved: Int
    /// 從開始那天起有沒有記過收入。沒有的話收入減支出一定是 0，先說怎麼開始算。
    public let hasIncome: Bool

    public init(target: Int, endsOn: String, saved: Int, hasIncome: Bool) {
        self.target = target
        self.endsOn = endsOn
        self.saved = max(0, saved)
        self.hasIncome = hasIncome
    }

    public var remaining: Int { max(0, target - saved) }
    public var isReached: Bool { target > 0 && saved >= target }
    /// 進度條用，0 到 1。
    public var fraction: Double { target > 0 ? min(1, Double(saved) / Double(target)) : 0 }

    /// 那天過了還沒存到。
    public func isOver(today: String) -> Bool { !isReached && today > endsOn }

    /// 還有幾個月。同一個月算 1；過了那天是 0。11/26 到 1/31 是 2。
    public func monthsLeft(today: String) -> Int {
        guard today <= endsOn else { return 0 }
        return max(1, Savings.monthIndex(endsOn) - Savings.monthIndex(today))
    }

    /// 接下來一個月要存多少才會到。存到了、過了那天、還沒有收入，都是 nil。
    public func monthly(today: String) -> Int? {
        guard hasIncome, !isReached else { return nil }
        let months = monthsLeft(today: today)
        guard months > 0 else { return nil }
        return (remaining + months - 1) / months
    }
}

public enum Savings {
    /// 這本帳進行中的那一個。好幾個的話（照理不會）用最新的。
    public static func active(in goals: [SavingsGoal], ledger: UUID) -> SavingsGoal? {
        goals.filter { $0.deletedAt == nil && $0.belongs(to: ledger) }.max { $0.createdAt < $1.createdAt }
    }

    /// 從開始那天到目標那天，這本帳記的收入減支出。固定支出自動記的、補的大概都算。
    public static func progress(of goal: SavingsGoal, transactions: [Txn]) -> SavingsProgress {
        let rows = transactions.filter {
            $0.deletedAt == nil && $0.belongs(to: goal.ledgerKey)
                && $0.occurredOn >= goal.startsOn && $0.occurredOn <= goal.endsOn
        }
        let income = rows.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
        let expense = rows.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
        return SavingsProgress(
            target: goal.target, endsOn: goal.endsOn, saved: income - expense,
            hasIncome: rows.contains { $0.type == .income }
        )
    }

    /// 開始存錢的畫面上那一句用：從今天起到那天，一個月要存多少。
    public static func monthlyPlan(target: Int, today: String, endsOn: String) -> Int? {
        SavingsProgress(target: target, endsOn: endsOn, saved: 0, hasIncome: true).monthly(today: today)
    }

    /// 2026-11-26 → 2026 × 12 + 11
    static func monthIndex(_ day: String) -> Int {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        return parts.count >= 2 ? parts[0] * 12 + parts[1] : 0
    }
}

/// 存錢的句子。不寫百分比，不用「達成」。
public enum SavingsText {
    public static let title = "存錢"
    public static let needsIncome = "記一筆收入就會開始算。"
    public static let howItWorks = "從今天起，記的收入減掉支出，就是存下來的。"

    /// 第一行：還差多少，或結果。
    public static func headline(_ p: SavingsProgress, today: String) -> String {
        if p.isReached { return "存到 \(Money.format(p.target)) 了。" }
        if p.isOver(today: today) { return "\(Days.slash(p.endsOn)) 到了，存了 \(Money.format(p.saved))。" }
        if !p.hasIncome { return needsIncome }
        return "還差 \(Money.format(p.remaining))。"
    }

    /// 第二句：一個月存多少就到。沒有要講的就是 nil。
    public static func plan(_ p: SavingsProgress, today: String) -> String? {
        guard let monthly = p.monthly(today: today) else { return nil }
        let months = p.monthsLeft(today: today)
        if months == 1 { return "這個月再存 \(Money.format(monthly)) 就到。" }
        return "接下來 \(months) 個月，一個月存 \(Money.format(monthly)) 就到。"
    }

    /// 開始存錢的畫面：還沒存，從今天起算。
    public static func preview(target: Int, today: String, endsOn: String) -> String? {
        guard target > 0, let monthly = Savings.monthlyPlan(target: target, today: today, endsOn: endsOn) else {
            return nil
        }
        return "一個月存 \(Money.format(monthly)) 就到。"
    }

    /// 「已經存 NT$17,600」
    public static func saved(_ p: SavingsProgress) -> String { "已經存 \(Money.format(p.saved))" }

    /// 「1/31 前 NT$30,000」
    public static func deadline(_ p: SavingsProgress) -> String {
        "\(Days.slash(p.endsOn)) 前 \(Money.format(p.target))"
    }

    /// 記帳頁那一條的左邊：「1/31 前存到 NT$30,000」
    public static func barTitle(_ p: SavingsProgress) -> String {
        "\(Days.slash(p.endsOn)) 前存到 \(Money.format(p.target))"
    }

    /// 記帳頁那一條的右邊、小工具的大字：「還差 12,400」或結果。
    public static func short(_ p: SavingsProgress, today: String) -> String {
        if p.isReached { return "存到了" }
        if p.isOver(today: today) { return "存了 \(Money.grouped(p.saved))" }
        if !p.hasIncome { return "記收入就開始算" }
        return "還差 \(Money.grouped(p.remaining))"
    }

    /// 小工具下面那一行：「1/31 前 30,000」
    public static func widgetDeadline(_ p: SavingsProgress) -> String {
        "\(Days.slash(p.endsOn)) 前 \(Money.grouped(p.target))"
    }

    /// 讀螢幕念的一整句。
    public static func spoken(_ p: SavingsProgress, today: String) -> String {
        "\(title)，\(headline(p, today: today))\(deadline(p))"
    }
}
