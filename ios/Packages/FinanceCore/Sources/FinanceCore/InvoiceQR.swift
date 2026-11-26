import Foundation

/// 台灣電子發票證明聯左邊那個 QR 碼讀出來的內容。
///
/// 前 77 碼是固定欄位：發票號碼 10、開立日期 7（民國 yyyMMdd）、隨機碼 4、
/// 銷售額 8（十六進位）、總計額 8（十六進位）、買方統編 8、賣方統編 8、加密驗證 24。
/// 後面用冒號隔開：營業人自用區、這張 QR 的品目筆數、總品目筆數、中文編碼（0 Big5、1 UTF-8、2 Base64），
/// 接著每三格一組：品名、數量、單價。右邊那個 QR 碼以 ** 開頭，只裝品名，這裡不認。
public struct InvoiceQR: Hashable, Sendable {
    public struct Item: Hashable, Sendable {
        public let name: String
        public let quantity: String
        public let unitPrice: String
    }

    /// 字軌加號碼，例如 AB12345678。
    public let number: String
    /// 開立日期，換成西元 yyyy-MM-dd。
    public let day: String
    public let randomCode: String
    /// 未稅的銷售額（元）。
    public let salesAmount: Int
    /// 含稅的總計額（元），記帳用這個。
    public let total: Int
    public let buyerId: String
    public let sellerId: String
    /// 左邊 QR 碼裝得下的品項，可能是空的。
    public let items: [Item]

    /// 第一個品名，沒有就是 nil。
    public var firstItemName: String? { items.first?.name }

    static let fixedLength = 77

    /// 解不出來（不是左邊那個、長度不對、日期不存在）一律回傳 nil。
    public static func parse(_ text: String) -> InvoiceQR? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.hasPrefix("**") else { return nil }
        let chars = Array(trimmed)
        guard chars.count >= fixedLength, chars[0..<fixedLength].allSatisfy(\.isASCII) else { return nil }

        func field(_ start: Int, _ length: Int) -> String { String(chars[start..<(start + length)]) }

        let number = field(0, 10)
        guard number.prefix(2).allSatisfy({ $0.isUppercase && $0.isLetter }), isDigits(number.dropFirst(2)) else {
            return nil
        }
        guard let day = westernDay(field(10, 7)) else { return nil }
        let randomCode = field(17, 4)
        guard isDigits(randomCode[...]),
              let sales = Int(field(21, 8), radix: 16),
              let total = Int(field(29, 8), radix: 16)
        else { return nil }
        let buyer = field(37, 8)
        let seller = field(45, 8)
        guard isDigits(buyer[...]), isDigits(seller[...]) else { return nil }

        let rest = String(chars[fixedLength...])
        return InvoiceQR(
            number: number, day: day, randomCode: randomCode, salesAmount: sales, total: total,
            buyerId: buyer, sellerId: seller, items: items(in: rest)
        )
    }

    private static func isDigits(_ text: Substring) -> Bool {
        !text.isEmpty && text.allSatisfy { $0.isASCII && $0.isNumber }
    }

    /// 民國 yyyMMdd 換成西元 yyyy-MM-dd，日期不存在就是 nil。
    static func westernDay(_ text: String) -> String? {
        guard text.count == 7, isDigits(text[...]),
              let year = Int(text.prefix(3)),
              let month = Int(text.dropFirst(3).prefix(2)),
              let day = Int(text.suffix(2))
        else { return nil }
        let western = year + 1911
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let parts = DateComponents(year: western, month: month, day: day)
        guard parts.isValidDate(in: calendar) else { return nil }
        return String(format: "%04d-%02d-%02d", western, month, day)
    }

    /// 冒號後面那段。格式不對就當沒有品項，固定欄位照樣能用。
    static func items(in rest: String) -> [Item] {
        guard rest.hasPrefix(":") else { return [] }
        // 第一格是冒號前面的空字串。
        var fields = rest.split(separator: ":", omittingEmptySubsequences: false).dropFirst().map(String.init)
        // 營業人自用區、品目筆數、總品目筆數、中文編碼。
        guard fields.count >= 4 else { return [] }
        let encoding = fields[3]
        fields = Array(fields.dropFirst(4))
        if encoding == "2" {
            // Base64：後面整段是編過的，解開後一樣是冒號隔開。
            let joined = fields.joined(separator: ":")
            guard let data = Data(base64Encoded: joined), let decoded = String(data: data, encoding: .utf8) else {
                return []
            }
            fields = decoded.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        }
        var items: [Item] = []
        var i = 0
        while i + 2 < fields.count {
            let name = fields[i].trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                items.append(Item(
                    name: name,
                    quantity: fields[i + 1].trimmingCharacters(in: .whitespaces),
                    unitPrice: fields[i + 2].trimmingCharacters(in: .whitespaces)
                ))
            }
            i += 3
        }
        return items
    }
}
