import XCTest
@testable import FinanceCore

private let days = Days.taipei

private func tx(
    _ amount: Int, _ day: String, _ category: String = "飲食", note: String = "", oneOff: Bool = false,
    at seconds: TimeInterval = 0, deleted: Bool = false
) -> Txn {
    let c = Categories.named(category)
    var row = Txn(
        fields: TxnFields(type: c.kind, amount: amount, occurredOn: day, categoryId: c.id, note: note, isOneOff: oneOff),
        createdAt: Date(timeIntervalSince1970: seconds), timeZone: "Asia/Taipei"
    )
    if deleted { row.deletedAt = Date(timeIntervalSince1970: 1) }
    return row
}

/// 一個月從 1 號到 through 號，每天一筆同金額。
private func everyDay(_ month: String, through: Int, amount: Int, _ category: String = "飲食", skipping: ClosedRange<Int>? = nil) -> [Txn] {
    (1...through).filter { !(skipping?.contains($0) ?? false) }
        .map { tx(amount, month + String(format: "-%02d", $0), category) }
}

private func report(_ rows: [Txn], month: String = "2026-11", today: String = "2026-11-25", budgets: [Budget] = []) -> MonthReport {
    Analysis.report(month: month + "-01", today: today, transactions: rows, budgets: budgets, book: CategoryBook(), days: days)
}

final class MoneyTests: XCTestCase {
    func testGroupedAndFormat() {
        XCTAssertEqual(Money.grouped(0), "0")
        XCTAssertEqual(Money.grouped(188), "188")
        XCTAssertEqual(Money.grouped(1234), "1,234")
        XCTAssertEqual(Money.grouped(1234567), "1,234,567")
        XCTAssertEqual(Money.format(3240), "NT$3,240")
        XCTAssertEqual(Money.listed(188, type: .expense), "188")
        XCTAssertEqual(Money.listed(52000, type: .income), "+52,000")
    }

    func testAmountPad() {
        var pad = AmountPad()
        pad.press("0")
        pad.press("00")
        XCTAssertEqual(pad.value, 0)
        pad.press("1")
        pad.press("8")
        pad.press("00")
        XCTAssertEqual(pad.value, 1800)
        pad.backspace()
        XCTAssertEqual(pad.value, 180)
        pad.press("x")
        XCTAssertEqual(pad.value, 180)
        for _ in 0..<10 { pad.press("9") }
        XCTAssertEqual(String(pad.value).count, AmountPad.maxDigits)
        for _ in 0..<10 { pad.backspace() }
        XCTAssertEqual(pad.value, 0)
    }
}

final class DaysTests: XCTestCase {
    func testDayUsesItsTimeZone() {
        let date = ISO8601DateFormatter().date(from: "2026-11-14T16:30:00Z")!
        XCTAssertEqual(days.day(of: date), "2026-11-15")
        XCTAssertEqual(Days(timeZone: TimeZone(identifier: "America/New_York")!).day(of: date), "2026-11-14")
    }

    func testAddingDaysAndMonths() {
        XCTAssertEqual(days.adding(days: -1, to: "2026-11-01"), "2026-10-31")
        XCTAssertEqual(days.adding(days: -1, to: "2028-03-01"), "2028-02-29")
        XCTAssertEqual(days.adding(months: -1, toMonthOf: "2026-01-20"), "2025-12-01")
        XCTAssertEqual(days.adding(months: 1, toMonthOf: "2026-11-30"), "2026-12-01")
        XCTAssertEqual(days.length(ofMonth: "2026-11-01"), 30)
        XCTAssertEqual(days.length(ofMonth: "2028-02-10"), 29)
    }

    func testTitles() {
        XCTAssertNil(days.date(of: "2026-02-30"))
        XCTAssertEqual(days.sectionTitle(for: "2026-11-15", today: "2026-11-15"), "今天")
        XCTAssertEqual(days.sectionTitle(for: "2026-11-14", today: "2026-11-15"), "昨天")
        XCTAssertEqual(days.sectionTitle(for: "2026-11-13", today: "2026-11-15"), "11 月 13 日 週五")
        XCTAssertEqual(days.sectionTitle(for: "2025-12-31", today: "2026-01-02"), "2025 年 12 月 31 日 週三")
        let labels = [
            days.sectionLabel(for: "2026-11-15", today: "2026-11-15"),
            days.sectionLabel(for: "2026-11-14", today: "2026-11-15"),
            days.sectionLabel(for: "2026-11-13", today: "2026-11-15"),
            days.sectionLabel(for: "2025-12-31", today: "2026-01-02"),
        ]
        XCTAssertEqual(labels.map(\.title), ["今天", "昨天", "11/13", "2025/12/31"])
        XCTAssertEqual(labels.map(\.detail), ["11/15 週日", "11/14 週六", "週五", "週三"])
        XCTAssertEqual(days.monthTitle(of: "2026-11-15"), "2026 年 11 月")
        XCTAssertEqual(Days.shortMonth(of: "2026-09-01"), "9 月")
    }
}

final class ModelTests: XCTestCase {
    func testEditKeepsTheOriginalValue() {
        let original = tx(120, "2026-11-15")
        var fields = original.fields
        fields.note = "午餐"
        XCTAssertTrue(original.applying(fields, at: Date()).revisions.isEmpty, "只改備註不影響數字，不用留舊值")

        fields.amount = 150
        let edited = original.applying(fields, at: Date())
        XCTAssertEqual(edited.amount, 150)
        XCTAssertEqual(edited.revisions.map(\.amount), [120])
        XCTAssertEqual(edited.id, original.id)
        XCTAssertEqual(edited.createdAt, original.createdAt)
    }

    func testIncomeIsNeverOneOff() {
        XCTAssertFalse(tx(1000, "2026-11-01", "薪水", oneOff: true).isOneOff)
        XCTAssertTrue(tx(1000, "2026-11-01", "交通", oneOff: true).isOneOff)
    }

    func testCodableRoundTrip() throws {
        let row = tx(188, "2026-11-25", note: "午餐").applying(
            TxnFields(type: .expense, amount: 200, occurredOn: "2026-11-24", categoryId: Categories.named("交通").id), at: Date(timeIntervalSince1970: 9)
        )
        let back = try JSONDecoder().decode(Txn.self, from: JSONEncoder().encode(row))
        XCTAssertEqual(back, row)
        XCTAssertEqual(back.schemaVersion, Txn.currentSchema)
    }

    func testTitleFallsBackToCategory() {
        XCTAssertEqual(CategoryBook().title(of: tx(1, "2026-11-01", "交通")), "交通")
        XCTAssertEqual(CategoryBook().title(of: tx(1, "2026-11-01", "交通", note: "加油")), "加油")
    }

    func testBudgetKeepsOldMonths() {
        let a = Budget(month: "2026-09-01", amount: 20000, createdAt: Date(timeIntervalSince1970: 1))
        let b = Budget(month: "2026-11-01", amount: 25000, createdAt: Date(timeIntervalSince1970: 2))
        let c = Budget(month: "2026-11-01", amount: 0, createdAt: Date(timeIntervalSince1970: 3))
        XCTAssertNil(Budget.amount(for: "2026-08-01", in: [a, b]))
        XCTAssertEqual(Budget.amount(for: "2026-10-01", in: [a, b]), 20000)
        XCTAssertEqual(Budget.amount(for: "2026-11-01", in: [b, a]), 25000)
        XCTAssertNil(Budget.amount(for: "2026-12-01", in: [a, b, c]), "改成 0 就是不訂")
    }
}

final class TimelineTests: XCTestCase {
    func testSectionsAreNewestFirstWithDailyTotals() {
        let sections = Timeline.sections(from: [
            tx(65, "2026-11-15", at: 1),
            tx(450, "2026-11-15", at: 2),
            tx(500, "2026-11-14", at: 3),
            tx(52000, "2026-11-14", "薪水", at: 4),
            tx(999, "2026-11-15", at: 5, deleted: true),
        ])
        XCTAssertEqual(sections.map(\.day), ["2026-11-15", "2026-11-14"])
        XCTAssertEqual(sections[0].items.map(\.amount), [450, 65])
        XCTAssertEqual(sections[0].expenseTotal, 515)
        XCTAssertEqual(sections[1].expenseTotal, 500)
        XCTAssertEqual(sections[1].incomeTotal, 52000)
    }
}

final class AnalysisTests: XCTestCase {
    /// 三個記完整的月份，每天 100。
    private var baseline: [Txn] {
        everyDay("2026-08", through: 31, amount: 100)
            + everyDay("2026-09", through: 30, amount: 110)
            + everyDay("2026-10", through: 31, amount: 120)
    }

    func testTotalsIgnoreDeletedAndOtherMonths() {
        let r = report([
            tx(100, "2026-11-01"), tx(300, "2026-10-31"), tx(400, "2026-11-10", "薪水"),
            tx(500, "2026-11-10", deleted: true), tx(900, "2026-11-11", "交通", oneOff: true),
        ])
        XCTAssertEqual(r.expense, 1000)
        XCTAssertEqual(r.oneOff, 900)
        XCTAssertEqual(r.routine, 100)
        XCTAssertEqual(r.income, 400)
        XCTAssertEqual(r.expenseCount, 2)
    }

    func testComparesWithTheSamePartOfEarlierMonths() {
        let r = report(baseline + everyDay("2026-11", through: 25, amount: 105))
        XCTAssertEqual(r.comparison, .ready(UsualRange(low: 2500, high: 3000, months: 3)), "算到 25 號，不是整個月")
        XCTAssertEqual(AnalysisText.comparison(r), "跟平常差不多。平常到 25 號是 NT$2,500 到 3,000。")
    }

    func testPastMonthComparesWholeMonths() {
        let r = report(baseline + everyDay("2026-07", through: 31, amount: 200) + [tx(1, "2026-11-01")], month: "2026-10")
        XCTAssertFalse(r.isCurrent)
        XCTAssertEqual(r.throughDay, 31)
        XCTAssertEqual(r.comparison, .ready(UsualRange(low: 3100, high: 6200, months: 3)))
        XCTAssertEqual(AnalysisText.comparison(r), "跟平常差不多。平常一個月是 NT$3,100 到 6,200。")
    }

    func testOneOffIsLeftOutOfTheComparison() {
        let r = report(baseline + everyDay("2026-11", through: 25, amount: 105) + [tx(40000, "2026-11-20", "購物", oneOff: true)])
        XCTAssertEqual(r.expense, 42625)
        XCTAssertEqual(r.routine, 2625)
        XCTAssertTrue(AnalysisText.comparison(r).hasPrefix("跟平常差不多"))
    }

    func testGapIsNotZero() {
        let r = report(baseline + everyDay("2026-11", through: 25, amount: 105, skipping: 4...16))
        XCTAssertEqual(r.comparison, .gap(days: 13))
        XCTAssertNil(r.observation)
        XCTAssertNil(r.categories.first?.usual)
        XCTAssertEqual(AnalysisText.comparison(r), "中間有幾天沒記，先不跟平常比。")
        XCTAssertEqual(r.gapToFill, DayRange(from: "2026-11-04", to: "2026-11-16"))
    }

    func testMonthsWithGapsOrFewRecordsAreNotABaseline() {
        let rows = everyDay("2026-08", through: 31, amount: 100)
            + everyDay("2026-09", through: 30, amount: 1, skipping: 10...20)
            + everyDay("2026-10", through: 5, amount: 1)
        XCTAssertEqual(Analysis.comparableMonths(before: "2026-11-01", transactions: rows, days: days), ["2026-08-01"])
        XCTAssertEqual(report(rows + everyDay("2026-11", through: 25, amount: 1)).comparison, .notEnough(monthsNeeded: 1))
    }

    func testEarlyInTheMonthAndEmpty() {
        XCTAssertEqual(report(baseline + everyDay("2026-11", through: 6, amount: 1), today: "2026-11-06").comparison, .tooEarly)
        XCTAssertNotEqual(report(baseline + everyDay("2026-11", through: 7, amount: 1), today: "2026-11-07").comparison, .tooEarly)
        XCTAssertEqual(report(baseline).comparison, .empty)
    }

    func testEditingOrDeletingOldRecordsRecalculates() {
        var rows = baseline + everyDay("2026-11", through: 25, amount: 105)
        let i = rows.firstIndex { $0.occurredOn == "2026-10-03" }!
        rows[i].deletedAt = Date()
        XCTAssertEqual(report(rows).comparison.range?.high, 2880)
    }

    func testObservationNeedsEveryThreshold() {
        let high = everyDay("2026-11", through: 25, amount: 200)
        let seen = report(baseline + high).observation
        XCTAssertEqual(seen?.category.name, "飲食")
        XCTAssertEqual(seen?.amount, 5000)
        XCTAssertEqual(seen?.count, 25)
        XCTAssertEqual(
            AnalysisText.categoryAnswer(report(baseline + high)),
            "飲食到 25 號 NT$5,000，平常同期是 NT$2,500 到 3,000。"
        )

        // 超出不到三成。
        XCTAssertNil(report(baseline + everyDay("2026-11", through: 25, amount: 140)).observation)
        // 月中以前不說。
        XCTAssertNil(report(baseline + everyDay("2026-11", through: 13, amount: 300), today: "2026-11-13").observation)
        // 筆數不夠，一大筆也不算規律。
        let shopping = [tx(500, "2026-08-10", "購物"), tx(500, "2026-09-10", "購物"), tx(500, "2026-10-10", "購物")]
        XCTAssertNil(report(
            baseline + shopping + everyDay("2026-11", through: 25, amount: 105) + [tx(9000, "2026-11-10", "購物")]
        ).observation)
    }

    func testObservationAlsoSpeaksUpWhenSpendingIsLower() {
        XCTAssertEqual(report(baseline + everyDay("2026-11", through: 25, amount: 50)).observation?.amount, 1250)
    }

    func testBudget() {
        let budget = Budget(month: "2026-11-01", amount: 20000, createdAt: Date())
        let r = report([tx(15800, "2026-11-01")], budgets: [budget])
        XCTAssertEqual(r.budget?.left, 4200)
        XCTAssertEqual(r.budget?.daysLeft, 6, "25 號到 30 號，今天也算")
        XCTAssertEqual(r.budget?.perDay, 700)
        XCTAssertEqual(AnalysisText.budget(r.budget!), "預算還剩 NT$4,200，每天 NT$700。")
        XCTAssertEqual(AnalysisText.homeBudget(r.budget!), "還能花 NT$4,200")

        let over = report([tx(21000, "2026-11-01")], budgets: [budget])
        XCTAssertNil(over.budget?.perDay)
        XCTAssertEqual(AnalysisText.budget(over.budget!), "預算 NT$20,000，多花了 NT$1,000。")
        XCTAssertEqual(AnalysisText.homeBudget(over.budget!), "預算 NT$20,000")
        XCTAssertEqual(AnalysisText.homeBudgetLabel(over.budget!), "預算")
        XCTAssertEqual(AnalysisText.homeBudgetAmount(over.budget!), 20000)
        XCTAssertNil(report([tx(1, "2026-10-01")], month: "2026-10", budgets: [budget]).budget, "訂之前的月份沒有預算")
    }

    func testBiggestNeedsEnoughRecords() {
        XCTAssertTrue(report(everyDay("2026-11", through: 9, amount: 100)).biggest.isEmpty)
        let r = report(everyDay("2026-11", through: 10, amount: 100) + [tx(900, "2026-11-03", "購物")])
        XCTAssertEqual(r.biggest.map(\.amount), [900, 100, 100])
    }

    func testRecentMonthsSeparatesNoRecordFromZero() {
        let months = Analysis.recentMonths(
            today: "2026-11-25", transactions: [tx(100, "2026-08-02"), tx(50, "2026-11-01"), tx(1, "2026-10-01", "薪水")], days: days
        )
        XCTAssertEqual(months.map(\.month), ["2026-08-01", "2026-09-01", "2026-10-01", "2026-11-01"])
        XCTAssertEqual(months.map(\.expense), [100, nil, 0, 50])
        XCTAssertEqual(months.map(\.isCurrent), [false, false, false, true])
        XCTAssertTrue(Analysis.recentMonths(today: "2026-11-25", transactions: [], days: days).isEmpty)
    }

    func testMonthlyRangeForBudget() {
        XCTAssertEqual(
            Analysis.monthlyRange(today: "2026-11-25", transactions: baseline, days: days),
            UsualRange(low: 3100, high: 3720, months: 3)
        )
        XCTAssertNil(Analysis.monthlyRange(today: "2026-11-25", transactions: [], days: days))
    }

    func testSameNumberEverywhere() {
        let rows = DemoData.steady.transactions(today: "2026-11-25", days: days)
        let r = report(rows)
        XCTAssertEqual(r.categories.reduce(0) { $0 + $1.total }, r.expense)
        XCTAssertEqual(Analysis.recentMonths(today: "2026-11-25", transactions: rows, days: days).last?.expense, r.expense)
        let food = Categories.named("飲食").id
        XCTAssertEqual(
            Analysis.categoryTotal(food, month: "2026-11-25", transactions: rows, book: CategoryBook(), days: days),
            r.categories.first { $0.id == food }?.total
        )
        XCTAssertEqual(
            Timeline.sections(from: rows).filter { $0.day.hasPrefix("2026-11") }.reduce(0) { $0 + $1.expenseTotal }, r.expense
        )
    }
}

final class DemoDataTests: XCTestCase {
    func testThreeKindsOfUsersReachTheStateTheyStandFor() {
        let today = "2026-11-25"
        func make(_ kind: DemoData) -> MonthReport {
            report(kind.transactions(today: today, days: days), budgets: kind.budgets(today: today, days: days))
        }
        XCTAssertEqual(make(.fresh).expense, 7005)
        XCTAssertEqual(make(.fresh).comparison, .notEnough(monthsNeeded: 2))
        XCTAssertNotNil(make(.steady).comparison.range)
        XCTAssertEqual(make(.steady).observation?.category.name, "飲食")
        XCTAssertNotNil(make(.steady).budget)
        XCTAssertEqual(make(.returning).comparison, .gap(days: 13))
    }

    func testDemoNeverRecordsTheFuture() {
        for today in ["2026-11-01", "2026-11-02", "2028-02-29", "2026-12-31"] {
            for kind in DemoData.allCases {
                XCTAssertTrue(kind.transactions(today: today, days: days).allSatisfy { $0.occurredOn <= today })
            }
        }
    }
}

final class AnalysisTextTests: XCTestCase {
    /// 把各種狀態能講出來的句子全部收集起來掃禁用字。
    func testNoForbiddenWords() {
        var lines: [String] = [
            AnalysisText.categoryTitle, AnalysisText.biggestTitle, AnalysisText.recentTitle, AnalysisText.recentCurrent,
            AnalysisText.recentMissing, AnalysisText.budgetHint(nil), AnalysisText.oneOff(100),
            AnalysisText.budgetHint(UsualRange(low: 1, high: 2, months: 3)),
        ]
        for today in ["2026-11-03", "2026-11-08", "2026-11-16", "2026-11-25", "2026-11-30"] {
            for kind in DemoData.allCases {
                let rows = kind.transactions(today: today, days: days)
                for limit in [1000, 20000, 90000] {
                    let budget = Budget(month: "2026-08-01", amount: limit, createdAt: Date())
                    for month in ["2026-10", "2026-11", "2026-12"] {
                        let r = report(rows, month: month, today: today, budgets: [budget])
                        lines += [AnalysisText.totalTitle(r), AnalysisText.comparison(r), AnalysisText.recapTitle(r)]
                        lines += AnalysisText.recapFacts(r)
                        lines += [AnalysisText.categoryAnswer(r), r.observation.map(AnalysisText.observationLink)].compactMap { $0 }
                        lines += r.categories.compactMap { AnalysisText.usual($0, isCurrent: r.isCurrent) }
                        lines.append(AnalysisText.biggestAnswer(r))
                        if let status = r.budget { lines += [AnalysisText.budget(status), AnalysisText.homeBudget(status)] }
                    }
                }
            }
        }
        lines += Categories.all.map { AnalysisText.saved(category: $0, amount: 10, monthTotal: 20) }
        for line in Set(lines) {
            for word in AnalysisText.forbidden {
                XCTAssertFalse(line.contains(word), "「\(line)」裡有禁用字「\(word)」")
            }
        }
    }

    func testRecapHasAtMostThreeFacts() {
        let rows = DemoData.steady.transactions(today: "2026-11-25", days: days)
        let r = report(rows, month: "2026-10", today: "2026-11-03")
        XCTAssertLessThanOrEqual(AnalysisText.recapFacts(r).count, 3)
        XCTAssertEqual(AnalysisText.recapTitle(r), "10 月回顧")
    }

    func testSavedLine() {
        XCTAssertEqual(
            AnalysisText.saved(category: Categories.named("飲食"), amount: 188, monthTotal: 3388), "記好了。飲食這個月共 NT$3,388"
        )
        XCTAssertEqual(AnalysisText.saved(category: Categories.named("薪水"), amount: 42000, monthTotal: 0), "記好了。薪水 NT$42,000")
    }
}

final class CSVTests: XCTestCase {
    func testExport() {
        let rows = [
            tx(450, "2026-11-15", note: "火鍋, 他說\"好吃\""),
            tx(65, "2026-11-14", "交通", note: "=SUM(A1)", oneOff: true),
            tx(1, "2026-11-13", deleted: true),
        ]
        let csv = CSVExport.make(transactions: rows, book: CategoryBook())
        let lines = csv.components(separatedBy: "\r\n")
        XCTAssertTrue(csv.hasPrefix("\u{FEFF}日期,類型,金額"))
        XCTAssertEqual(lines.count, 4)
        XCTAssertTrue(lines[1].hasPrefix("2026-11-14,支出,65,交通,\"'=SUM(A1)\",是,1970-01-01T00:00:00Z,Asia/Taipei,"))
        XCTAssertTrue(lines[2].hasPrefix("2026-11-15,支出,450,飲食,\"火鍋, 他說\"\"好吃\"\"\",,"))
    }
}
