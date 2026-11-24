import Foundation

/// 匯出 CSV。開頭帶 BOM，Excel 直接開不會亂碼。
public enum CSVExport {
    public static let header = ["日期", "類型", "金額", "分類", "備註", "一次性", "記錄時間", "時區", "編號"]

    public static func field(_ value: String) -> String {
        let needsQuote = value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r")
        // 開頭是 = + - @ 的欄位加上單引號，避免試算表把它當公式執行。
        let risky = value.first.map { "=+-@".contains($0) } ?? false
        let safe = risky ? "'" + value : value
        return needsQuote || risky ? "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : safe
    }

    public static func make(transactions: [Txn], book: CategoryBook) -> String {
        let formatter = ISO8601DateFormatter()
        let rows = transactions
            .filter { $0.deletedAt == nil }
            .sorted { ($0.occurredOn, $0.createdAt) < ($1.occurredOn, $1.createdAt) }
            .map { t -> String in
                let columns: [String] = [
                    t.occurredOn,
                    t.type.label,
                    String(t.amount),
                    book.category(of: t).name,
                    t.note,
                    t.isOneOff ? "是" : "",
                    formatter.string(from: t.createdAt),
                    t.timeZone,
                    t.id.uuidString,
                ]
                return columns.map(field).joined(separator: ",")
            }
        return "\u{FEFF}" + ([header.joined(separator: ",")] + rows).joined(separator: "\r\n") + "\r\n"
    }
}
