import FinanceCore

// 分析頁四種看法的字。有數字的句子在 FinanceCore/AnalysisText.swift 的 H 到 K。

extension Words {
    enum AnalysisModes {
        /// 切換那一排的名字，讀螢幕的人聽得到。
        static let picker = "分析的看法"
        static let sentence = "一句話"
        static let budget = "還能花"
        static let calendar = "月曆"
        static let pie = "圓餅"

        static let changeBudget = "改每月預算"
        static let pieTitle = "各類佔多少"

        /// 圓餅的佔比。只在圓餅這個看法出現（多米 2026-11-26 要的，.analytics/06-08 有記）。
        static func percent(_ value: Int) -> String { "\(value)%" }

        static let showTop = "小的合在一起"

        /// 讀螢幕的人聽到的：11/8，NT$1,980，3 筆。
        static func day(_ day: DaySpend) -> String {
            if day.isFuture { return "\(Days.slash(day.day))，還沒到" }
            if day.amount == 0 { return "\(Days.slash(day.day))，沒有支出" }
            return "\(Days.slash(day.day))，\(Money.format(day.amount))，\(day.count) 筆"
        }

        static func slice(name: String, amount: Int, percent: Int) -> String {
            "\(name)，\(Money.format(amount))，\(percent)%"
        }

        static func weekBar(label: String, amount: Int) -> String { "\(label)，\(Money.format(amount))" }

        static func weekday(_ name: String) -> String { "週\(name)" }

        static let dayEmptyTitle = "這天沒有紀錄"
        static let dayEmptyMessage = "記一筆時把日期改成這天，就會出現在這裡。"

        static func dayHeader(count: Int, total: Int) -> String {
            "\(count) 筆，支出共 \(Money.format(total))"
        }
    }
}
