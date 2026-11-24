import Foundation

/// 明細上的一天。
public struct DaySection: Identifiable, Hashable, Sendable {
    public let day: String
    public let items: [Txn]
    public let expenseTotal: Int
    public let incomeTotal: Int

    public var id: String { day }
}

public enum Timeline {
    /// 依日期分組並算每日小計，最新的在最上面。已刪除的不列入。
    public static func sections(from transactions: [Txn]) -> [DaySection] {
        let alive = transactions.filter { $0.deletedAt == nil }
        let grouped = Dictionary(grouping: alive, by: \.occurredOn)
        return grouped.keys.sorted(by: >).map { day in
            let items = grouped[day]!.sorted { a, b in
                a.createdAt == b.createdAt ? a.id.uuidString > b.id.uuidString : a.createdAt > b.createdAt
            }
            return DaySection(
                day: day,
                items: items,
                expenseTotal: items.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount },
                incomeTotal: items.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
            )
        }
    }
}

/// 記帳鍵盤上的金額。只收整數，最多八位。
public struct AmountPad: Hashable, Sendable {
    public static let maxDigits = 8

    public private(set) var value: Int

    public init(value: Int = 0) {
        self.value = value
    }

    /// 按數字鍵（"0" 到 "9"、"00"）。超過位數就不理會。
    public mutating func press(_ key: String) {
        guard !key.isEmpty, key.allSatisfy({ $0.isASCII && $0.isNumber }) else { return }
        let text = value == 0 ? key : String(value) + key
        guard let next = Int(text), String(next).count <= Self.maxDigits else { return }
        value = next
    }

    public mutating func backspace() {
        value /= 10
    }
}
