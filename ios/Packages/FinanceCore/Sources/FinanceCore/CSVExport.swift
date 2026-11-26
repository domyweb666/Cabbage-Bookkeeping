import Foundation

/// 匯出 CSV。開頭帶 BOM，Excel 直接開不會亂碼。
public enum CSVExport {
    /// 帳本放在時區後面：前面幾欄的位置不變，以前匯出的檔跟新的對得起來。
    public static let header = ["日期", "類型", "金額", "分類", "備註", "一次性", "記錄時間", "時區", "帳本", "編號", "來源"]

    public static func field(_ value: String) -> String {
        let needsQuote = value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r")
        // 開頭是 = + - @ 的欄位加上單引號，避免試算表把它當公式執行。
        let risky = value.first.map { "=+-@".contains($0) } ?? false
        let safe = risky ? "'" + value : value
        return needsQuote || risky ? "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : safe
    }

    /// 全部帳本的紀錄一起匯出，每筆寫是哪一本。ledgers 是存過的帳本（刪掉的也可以放），找不到算「我的帳本」。
    public static func make(transactions: [Txn], book: CategoryBook, ledgers: [Ledger] = []) -> String {
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
                    Ledgers.name(of: t.ledgerKey, in: ledgers),
                    t.id.uuidString,
                    AnalysisText.source(of: t) ?? "",
                ]
                return columns.map(field).joined(separator: ",")
            }
        return "\u{FEFF}" + ([header.joined(separator: ",")] + rows).joined(separator: "\r\n") + "\r\n"
    }
}
