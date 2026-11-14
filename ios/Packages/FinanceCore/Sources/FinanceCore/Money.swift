import Foundation

/// 金額一律是整數（新台幣元），不用浮點數。
public enum Money {
    /// 1234 → "1,234"。不依賴裝置語系。
    public static func grouped(_ amount: Int) -> String {
        let negative = amount < 0
        let digits = Array(String(abs(amount)))
        var out: [Character] = []
        for (i, ch) in digits.enumerated() {
            if i > 0 && (digits.count - i) % 3 == 0 { out.append(",") }
            out.append(ch)
        }
        return (negative ? "-" : "") + String(out)
    }

    /// 1234 → "NT$1,234"
    public static func format(_ amount: Int) -> String {
        "NT$" + grouped(amount)
    }

    /// 時間軸上帶正負號的寫法：支出 "-188"、收入 "+52,000"。
    public static func signed(_ amount: Int, type: TxType) -> String {
        (type == .expense ? "-" : "+") + grouped(amount)
    }

    /// 解析使用者在金額欄輸入的文字：接受全形數字、千分位、前後空白；其他一律拒絕。
    public static func parse(_ text: String) -> Int? {
        var digits = ""
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x30...0x39:
                digits.unicodeScalars.append(scalar)
            case 0xFF10...0xFF19:
                digits.unicodeScalars.append(Unicode.Scalar(scalar.value - 0xFEE0)!)
            case 0x2C, 0xFF0C, 0x20, 0x3000:
                continue
            default:
                return nil
            }
        }
        guard !digits.isEmpty, digits.count <= 9, let value = Int(digits), value > 0 else { return nil }
        return value
    }
}
