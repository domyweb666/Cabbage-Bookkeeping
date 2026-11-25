import Foundation

/// 畫面測試與示範用的假資料。三種使用者對應 .analytics/09-驗證/驗證計畫.md。
public enum DemoData: String, CaseIterable, Sendable {
    /// 剛開始用，資料不夠。
    case fresh
    /// 用了四個月，有平常範圍、有過門檻的觀察。
    case steady
    /// 中間空了一段才回來。
    case returning
    /// 用了四個月，也設了固定支出。
    case planned

    public func transactions(today: String, days: Days) -> [Txn] {
        switch self {
        case .fresh:
            return Self.fresh(today: today, days: days)
        case .steady, .planned:
            return Self.history(today: today, days: days, skipping: nil)
        case .returning:
            return Self.history(today: today, days: days, skipping: 4...16)
        }
    }

    public func budgets(today: String, days: Days) -> [Budget] {
        guard self == .steady || self == .planned else { return [] }
        let month = days.adding(months: -2, toMonthOf: today)
        return [Budget(month: month, amount: self == .planned ? 36000 : 24000, createdAt: days.date(of: month) ?? Date())]
    }

    /// 一項這個月記過了、兩項還沒到、一項一年一次。
    public func fixed(today: String, days: Days) -> [FixedExpense] {
        guard self == .planned else { return [] }
        let month = days.monthStart(of: today)
        func item(_ name: String, _ amount: Int, _ note: String, _ schedule: FixedSchedule, order: Int) -> FixedExpense {
            FixedExpense(
                fields: FixedFields(
                    amount: amount, categoryId: Categories.named(name).id, note: note, schedule: schedule
                ),
                startsOn: month,
                createdAt: (days.date(of: month) ?? Date(timeIntervalSince1970: 0)).addingTimeInterval(Double(order))
            )
        }
        return [
            item("停車", 1500, "停車月租", .monthly(day: 3), order: 1),
            item("運動", 1200, "健身房", .monthly(day: 28), order: 2),
            item("居住", 699, "網路", .monthly(day: 30), order: 3),
            item("保險", 12000, "車險", .yearly(month: 3, day: 15), order: 4),
        ]
    }

    private static func make(
        _ name: String, _ amount: Int, _ day: String, _ days: Days, note: String = "", oneOff: Bool = false, order: Int = 0
    ) -> Txn {
        let category = Categories.named(name)
        let base = days.date(of: day) ?? Date(timeIntervalSince1970: 0)
        return Txn(
            fields: TxnFields(
                type: category.kind, amount: amount, occurredOn: day, categoryId: category.id, note: note, isOneOff: oneOff
            ),
            createdAt: base.addingTimeInterval(Double(order) * 60),
            timeZone: days.timeZone.identifier
        )
    }

    private static func fresh(today: String, days: Days) -> [Txn] {
        // 都放在這個月，月初那幾天也不會跑到上個月去。
        let start = days.monthStart(of: today)
        func day(_ back: Int) -> String { max(start, days.adding(days: -back, to: today)) }
        return [
            make("飲食", 65, day(2), days, note: "早餐", order: 1),
            make("交通", 500, day(2), days, note: "加油", order: 2),
            make("交通", 4650, day(1), days, note: "機車維修", oneOff: true, order: 3),
            make("訂閱", 390, day(1), days, note: "影音月費", order: 4),
            make("飲食", 120, day(0), days, note: "便當", order: 5),
            make("購物", 1280, day(0), days, note: "外套", order: 6),
        ]
    }

    /// 三個完整的月份加上這個月。這個月的飲食刻意多一些，用來看觀察那一句。
    private static func history(today: String, days: Days, skipping: ClosedRange<Int>?) -> [Txn] {
        var rows: [Txn] = []
        for back in (0...3).reversed() {
            let month = days.adding(months: -back, toMonthOf: today)
            let last = back == 0 ? Days.number(of: today) : days.length(ofMonth: month)
            let prefix = String(month.prefix(8))
            for number in 1...max(1, last) {
                if back == 0, let skipping, skipping.contains(number) { continue }
                let day = prefix + String(format: "%02d", number)
                let lunch = back == 0 ? 190 : 110 + back * 5
                rows.append(make("飲食", lunch, day, days, note: "午餐", order: 1))
                if number % 2 == 0 { rows.append(make("飲食", back == 0 ? 160 : 90, day, days, note: "飲料", order: 2)) }
                if number % 3 == 0 { rows.append(make("交通", 100 + back * 5, day, days, order: 3)) }
                if number % 7 == 0 { rows.append(make("日用", 260 + back * 20, day, days, order: 4)) }
                if number == 1 { rows.append(make("居住", 9000, day, days, note: "房租", order: 5)) }
                if number == 5 { rows.append(make("薪水", 42000, day, days, order: 6)) }
                if number == 6 { rows.append(make("訂閱", 390, day, days, note: "影音月費", order: 7)) }
                if number == 12 { rows.append(make("購物", 800 + back * 150, day, days, order: 8)) }
                if back == 0, number == 18 {
                    rows.append(make("交通", 4650, day, days, note: "機車維修", oneOff: true, order: 9))
                }
            }
        }
        return rows
    }
}
