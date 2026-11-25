import Foundation

// 固定支出：每月的（房租、電信）和每年一次的（保費、牌照稅）。
// 到那天自動記一筆，記好的那筆跟手動記的一樣可以改、可以刪。

/// 哪一天要記。日期超過那個月的天數，就用那個月的最後一天。
public enum FixedSchedule: Codable, Hashable, Sendable {
    case monthly(day: Int)
    case yearly(month: Int, day: Int)

    public var isYearly: Bool {
        if case .yearly = self { return true }
        return false
    }

    /// 某個月要記的那一天。每年一次的，不是那個月就沒有。
    public func due(inMonthOf day: String, days: Days) -> String? {
        let wanted: Int
        switch self {
        case .monthly(let number):
            wanted = number
        case .yearly(let month, let number):
            guard day.dropFirst(5).prefix(2) == String(format: "%02d", month) else { return nil }
            wanted = number
        }
        let number = min(max(1, wanted), days.length(ofMonth: day))
        return String(day.prefix(8)) + String(format: "%02d", number)
    }

    /// 一期記一次。每月的一期是 2026-11，每年的一期是 2026。
    func period(of due: String) -> String {
        String(due.prefix(isYearly ? 4 : 7))
    }
}

/// 使用者在固定支出畫面填的內容。
public struct FixedFields: Hashable, Sendable {
    public var amount: Int
    public var categoryId: UUID
    public var note: String
    public var schedule: FixedSchedule

    public init(amount: Int, categoryId: UUID, note: String = "", schedule: FixedSchedule) {
        self.amount = amount
        self.categoryId = categoryId
        self.note = String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(EntryForm.maxNoteLength))
        self.schedule = schedule
    }
}

/// 改金額之前的樣子。以前的月份照當時的金額算。
public struct FixedRevision: Codable, Hashable, Sendable {
    /// 從這天起換成新的金額。
    public let replacedOn: String
    public let amount: Int
}

public struct FixedExpense: Codable, Identifiable, Hashable, Sendable {
    public static let currentSchema = 1

    public let id: UUID
    public private(set) var amount: Int
    public private(set) var categoryId: UUID
    public private(set) var note: String
    public private(set) var schedule: FixedSchedule
    /// 設定的那天。年度的從這個月開始分攤。
    public let startsOn: String
    /// 從這天起到期的才自動記。換日子的時候會往後移，不回頭補記。
    public private(set) var postsFrom: String
    public let createdAt: Date
    /// 刪除的那天。記好的不動，之後不再記。
    public private(set) var endedOn: String?
    public private(set) var revisions: [FixedRevision]
    public let schemaVersion: Int

    public init(id: UUID = UUID(), fields: FixedFields, startsOn: String, createdAt: Date) {
        self.id = id
        self.amount = fields.amount
        self.categoryId = fields.categoryId
        self.note = fields.note
        self.schedule = fields.schedule
        self.startsOn = startsOn
        self.postsFrom = startsOn
        self.createdAt = createdAt
        self.endedOn = nil
        self.revisions = []
        self.schemaVersion = Self.currentSchema
    }

    public var fields: FixedFields {
        FixedFields(amount: amount, categoryId: categoryId, note: note, schedule: schedule)
    }

    /// 每月和每年之間不能換，要換就刪掉重設。
    public func applying(_ new: FixedFields, on day: String) -> FixedExpense {
        var copy = self
        if new.amount != amount {
            copy.revisions.append(FixedRevision(replacedOn: day, amount: amount))
        }
        copy.amount = new.amount
        copy.categoryId = new.categoryId
        copy.note = new.note
        if new.schedule.isYearly == schedule.isYearly, new.schedule != schedule {
            copy.schedule = new.schedule
            copy.postsFrom = max(postsFrom, day)
        }
        return copy
    }

    public func ended(on day: String) -> FixedExpense {
        var copy = self
        copy.endedOn = day
        return copy
    }

    /// 復原剛才的刪除。
    public func resumed() -> FixedExpense {
        var copy = self
        copy.endedOn = nil
        return copy
    }

    /// 那一天的金額。
    public func amount(on day: String) -> Int {
        revisions.first { $0.replacedOn > day }?.amount ?? amount
    }

    /// 每個月先留多少。每年一次的分 12 個月，除不盡就往上。
    public var monthlyShare: Int { Self.share(of: amount) }

    static func share(of amount: Int) -> Int { (amount + 11) / 12 }

    /// 從某天起，下一次會記在哪天（含那天）。
    public func nextDue(from day: String, days: Days) -> String? {
        let from = max(day, postsFrom)
        var month = days.monthStart(of: from)
        for _ in 0...12 {
            if let due = schedule.due(inMonthOf: month, days: days), due >= from { return due }
            month = days.adding(months: 1, toMonthOf: month)
        }
        return nil
    }

    /// 某個月要不要算進分攤。刪除的那個月就不算了。
    func isActive(inMonthOf day: String) -> Bool {
        let month = day.prefix(7)
        guard startsOn.prefix(7) <= month else { return false }
        guard let endedOn else { return true }
        return endedOn.prefix(7) > month
    }

    /// 小工具用的：拿掉使用者打的字。
    var withoutNote: FixedExpense {
        var copy = self
        copy.note = ""
        return copy
    }
}

/// 一筆紀錄是哪一項固定支出記的。
public struct FixedOrigin: Codable, Hashable, Sendable {
    public let itemId: UUID
    /// 哪一期。同一期不會記第二次，刪掉那筆也不會再冒出來。
    public let period: String
    public let isYearly: Bool
}

/// 補一個大概的數字時，補的是哪幾天。頭尾都算。
public struct DayRange: Codable, Hashable, Sendable {
    public let from: String
    public let to: String

    public init(from: String, to: String) {
        self.from = from
        self.to = to
    }

    public func contains(_ day: String) -> Bool { from <= day && day <= to }
}

public enum FixedPlan {
    /// 到今天為止該記、還沒記的。每一筆的日期是到期那天，不是打開 app 那天。
    public static func due(
        items: [FixedExpense], transactions: [Txn], today: String, days: Days, now: Date
    ) -> [Txn] {
        items.filter { $0.endedOn == nil }.flatMap { item -> [Txn] in
            let posted = postedPeriods(of: item, in: transactions)
            var rows: [Txn] = []
            var month = days.monthStart(of: item.postsFrom)
            let last = days.monthStart(of: today)
            while month <= last {
                if let due = item.schedule.due(inMonthOf: month, days: days), due >= item.postsFrom, due <= today {
                    let period = item.schedule.period(of: due)
                    if !posted.contains(period) {
                        rows.append(item.record(on: due, period: period, now: now, days: days))
                    }
                }
                let next = days.adding(months: 1, toMonthOf: month)
                // 日期壞掉時 adding 會原樣回傳，不能一直繞。
                guard next > month else { break }
                month = next
            }
            return rows
        }
    }

    /// 這個月還沒到的每月固定。
    static func pending(
        items: [FixedExpense], transactions: [Txn], today: String, days: Days
    ) -> Int {
        items.filter { $0.endedOn == nil && !$0.schedule.isYearly }.reduce(0) { total, item in
            guard let due = item.schedule.due(inMonthOf: today, days: days), due > today, due >= item.postsFrom,
                  !postedPeriods(of: item, in: transactions).contains(item.schedule.period(of: due)) else {
                return total
            }
            return total + item.amount
        }
    }

    /// 每年一次的，這個月要先留的部分。
    static func yearlyShare(items: [FixedExpense], month: String, on day: String) -> Int {
        items.filter { $0.schedule.isYearly && $0.isActive(inMonthOf: month) }
            .reduce(0) { $0 + FixedExpense.share(of: $1.amount(on: day)) }
    }

    /// 記過的期。刪掉的也算，不然刪了又會跑回來。
    private static func postedPeriods(of item: FixedExpense, in transactions: [Txn]) -> Set<String> {
        Set(transactions.compactMap { $0.fixed?.itemId == item.id ? $0.fixed?.period : nil })
    }
}

private extension FixedExpense {
    func record(on due: String, period: String, now: Date, days: Days) -> Txn {
        Txn(
            fields: TxnFields(
                type: .expense, amount: amount(on: due), occurredOn: due, categoryId: categoryId, note: note,
                // 每年一次的不跟平常比。
                isOneOff: schedule.isYearly
            ),
            createdAt: now, timeZone: days.timeZone.identifier,
            fixed: FixedOrigin(itemId: id, period: period, isYearly: schedule.isYearly)
        )
    }
}
