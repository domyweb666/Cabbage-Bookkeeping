import Foundation

/// 時間軸上的一天：交易由舊到新，最新的在最下面（靠近輸入列）。
public struct DaySection: Identifiable, Hashable, Sendable {
    public let day: String
    public let items: [Txn]
    public let expenseTotal: Int
    public let incomeTotal: Int

    public var id: String { day }
}

public enum Timeline {
    /// 依日期分組並計算每日小計。已刪除的交易不列入。
    public static func sections(from transactions: [Txn]) -> [DaySection] {
        let alive = transactions.filter { $0.deletedAt == nil }
        let grouped = Dictionary(grouping: alive, by: \.occurredOn)
        return grouped.keys.sorted().map { day in
            let items = grouped[day]!.sorted { a, b in
                let ta = a.createdAt ?? ""
                let tb = b.createdAt ?? ""
                return ta == tb ? a.id.uuidString < b.id.uuidString : ta < tb
            }
            return DaySection(
                day: day,
                items: items,
                expenseTotal: items.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount },
                incomeTotal: items.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
            )
        }
    }

    /// 某個月的支出總額（頂部顯示用；正式數字以後端的 monthly_overview 為準）。
    public static func monthExpense(from transactions: [Txn], monthOf day: String) -> Int {
        let prefix = String(day.prefix(7))
        return transactions
            .filter { $0.deletedAt == nil && $0.type == .expense && $0.occurredOn.hasPrefix(prefix) }
            .reduce(0) { $0 + $1.amount }
    }
}

/// 尚未綁定且已記超過 20 筆時，提示一次備份，之後不再打擾（規格 8.3）。
public enum BackupPrompt {
    public static let threshold = 20

    public static func shouldShow(transactionCount: Int, isLinked: Bool, alreadyShown: Bool) -> Bool {
        !isLinked && !alreadyShown && transactionCount > threshold
    }
}
