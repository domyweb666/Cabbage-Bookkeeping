import Foundation

/// 匯出 CSV（規格 7.7）。開頭帶 BOM，Excel 直接開不會亂碼。
public enum CSVExport {
    public static let header = ["日期", "類型", "金額", "品項", "分類", "商家", "標籤", "性質", "付款方式", "備註"]

    public static func field(_ value: String) -> String {
        let needsQuote = value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r")
        // 開頭是 = + - @ 的欄位加上單引號，避免試算表把它當公式執行。
        let risky = value.first.map { "=+-@".contains($0) } ?? false
        let safe = risky ? "'" + value : value
        return needsQuote || risky ? "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : safe
    }

    public static func make(transactions: [Txn], categories: [TxCategory]) -> String {
        let names = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.name) })
        let rows = transactions
            .filter { $0.deletedAt == nil }
            .sorted { ($0.occurredOn, $0.createdAt ?? "") < ($1.occurredOn, $1.createdAt ?? "") }
            .map { t in
                [
                    t.occurredOn,
                    t.type.label,
                    String(t.amount),
                    t.item,
                    names[t.categoryId] ?? "",
                    t.merchant ?? "",
                    t.tags.joined(separator: "、"),
                    t.nature?.label ?? "",
                    t.paymentMethod ?? "",
                    t.note ?? "",
                ].map(field).joined(separator: ",")
            }
        return "\u{FEFF}" + ([header.joined(separator: ",")] + rows).joined(separator: "\r\n") + "\r\n"
    }
}
