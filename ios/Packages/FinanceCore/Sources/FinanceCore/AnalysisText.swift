import Foundation

/// 分析相關的所有句子，編號對應 .analytics/06-08-畫面與文案-暫定.md 的字串表。
/// 主詞一律是錢、分類、這個月，不說「你」怎樣；不用百分比、不下評語。
public enum AnalysisText {
    /// 畫面與字串表都不准出現的字，單元測試會掃。
    public static let forbidden = [
        "只", "才", "僅", "竟然", "！", "應該", "必須", "記得", "別再", "加油", "放棄", "失敗",
        "平均", "%", "超支", "浪費", "節制", "好棒", "達成", "警告",
    ]

    private static func money(_ range: UsualRange) -> String {
        range.low == range.high
            ? Money.format(range.low)
            : "\(Money.format(range.low)) 到 \(Money.grouped(range.high))"
    }

    private static func monthName(_ report: MonthReport) -> String {
        report.isCurrent ? "這個月" : Days.shortMonth(of: report.month)
    }

    // MARK: - 花了多少（A）

    /// A1
    public static func totalTitle(_ report: MonthReport) -> String {
        "\(monthName(report))花了多少"
    }

    /// A2 跟平常比的那一句。
    public static func comparison(_ report: MonthReport) -> String {
        switch report.comparison {
        case .empty:
            return "還沒有支出紀錄。"
        case .tooEarly:
            return "月初先不比，\(Analysis.compareFromDay) 號開始跟平常比。"
        case .gap(let days):
            return "中間有 \(days) 天沒有紀錄，先不跟平常比。"
        case .notEnough(let needed):
            return "再有 \(needed) 個記完整的月份，就能跟平常比。"
        case .ready(let range):
            let period = report.isCurrent ? "平常到 \(report.throughDay) 號" : "平常一個月"
            let usual = "\(period)是 \(money(range))。"
            if report.routine > range.high {
                return "比平常多 \(Money.format(report.routine - range.high))。\(usual)"
            }
            if report.routine < range.low {
                return "比平常少 \(Money.format(range.low - report.routine))。\(usual)"
            }
            return "跟平常差不多。\(usual)"
        }
    }

    /// A3
    public static func oneOff(_ amount: Int) -> String {
        "其中一次性 \(Money.format(amount))，比較時不算。"
    }

    /// A4 預算那一行。
    public static func budget(_ status: BudgetStatus) -> String {
        if let perDay = status.perDay {
            return "預算還剩 \(Money.format(status.left))，每天 \(Money.format(perDay))。"
        }
        if status.left < 0 {
            return "預算 \(Money.format(status.budget))，多花了 \(Money.format(-status.left))。"
        }
        return "預算 \(Money.format(status.budget))，剩 \(Money.format(status.left))。"
    }

    /// A5 訂預算畫面上的一行。
    public static func budgetHint(_ range: UsualRange?) -> String {
        guard let range else { return "還看不出平常一個月花多少，可以先不訂。" }
        return "最近 \(range.months) 個月，一個月花 \(money(range))。"
    }

    // MARK: - 花去哪（B）

    /// B1
    public static let categoryTitle = "花在哪一類"

    /// B2 第一行直接講答案：有觀察說觀察，沒有就說最多的是哪一類。
    public static func categoryAnswer(_ report: MonthReport) -> String? {
        if let seen = report.observation {
            let period = report.isCurrent ? "到 \(report.throughDay) 號" : "這個月"
            let usual = report.isCurrent ? "平常同期" : "平常"
            return "\(seen.category.name)\(period) \(Money.format(seen.amount))，\(usual)是 \(money(seen.usual))。"
        }
        guard let top = report.categories.first else { return nil }
        return "最多的是\(top.category.name)，\(Money.format(top.total))。"
    }

    /// B3
    public static func observationLink(_ observation: SpendingNote) -> String {
        "看這 \(observation.count) 筆\(observation.category.name)"
    }

    /// B4 分類那一列下面的小字。
    public static func usual(_ line: CategoryLine, isCurrent: Bool) -> String? {
        guard let range = line.usual else { return nil }
        return "\(isCurrent ? "平常同期" : "平常") \(money(range))"
    }

    // MARK: - 最大的幾筆（C）

    /// C1
    public static let biggestTitle = "最大的三筆"

    /// C2 最大三筆佔了多少。
    public static func biggestAnswer(_ report: MonthReport) -> String {
        let total = report.biggest.reduce(0) { $0 + $1.amount }
        return "\(report.expenseCount) 筆裡，這 \(report.biggest.count) 筆共 \(Money.format(total))。"
    }

    // MARK: - 最近幾個月（D）

    /// D1
    public static let recentTitle = "最近幾個月"

    /// D2
    public static let recentCurrent = "這個月還沒過完"

    /// D3
    public static let recentMissing = "沒有紀錄"

    // MARK: - 月初回顧（E）

    /// E1
    public static func recapTitle(_ report: MonthReport) -> String {
        "\(Days.shortMonth(of: report.month))回顧"
    }

    /// E2 最多三個事實。
    public static func recapFacts(_ report: MonthReport) -> [String] {
        var facts = ["支出 \(Money.format(report.expense))，\(report.expenseCount) 筆。"]
        if let top = report.categories.first {
            facts.append("最多的是\(top.category.name)，\(Money.format(top.total))。")
        }
        if let status = report.budget {
            facts.append(budget(status))
        } else if report.comparison.range != nil {
            facts.append(comparison(report))
        }
        return facts
    }

    // MARK: - 記帳畫面上的一行（F）

    /// F1 記完一筆之後。
    public static func saved(category: TxCategory, amount: Int, monthTotal: Int) -> String {
        category.kind == .expense
            ? "記好了。\(category.name)這個月共 \(Money.format(monthTotal))"
            : "記好了。\(category.name) \(Money.format(amount))"
    }

    /// F2 首頁本月支出下面的小字。多花的時候不在首頁說，改顯示預算金額。
    public static func homeBudget(_ status: BudgetStatus) -> String {
        status.left >= 0 ? "還能花 \(Money.format(status.left))" : "預算 \(Money.format(status.budget))"
    }
}
