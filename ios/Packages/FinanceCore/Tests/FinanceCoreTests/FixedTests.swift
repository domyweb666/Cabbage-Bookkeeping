import XCTest
@testable import FinanceCore

private let days = Days.taipei
private let epoch = Date(timeIntervalSince1970: 0)

private func tx(
    _ amount: Int, _ day: String, _ category: String = "飲食", estimate: DayRange? = nil, fixed: FixedOrigin? = nil
) -> Txn {
    let c = Categories.named(category)
    return Txn(
        fields: TxnFields(type: c.kind, amount: amount, occurredOn: day, categoryId: c.id),
        createdAt: epoch, timeZone: "Asia/Taipei", fixed: fixed, estimate: estimate
    )
}

private func everyDay(_ month: String, through: Int, amount: Int, skipping: ClosedRange<Int>? = nil) -> [Txn] {
    (1...through).filter { !(skipping?.contains($0) ?? false) }
        .map { tx(amount, month + String(format: "-%02d", $0)) }
}

private func item(_ amount: Int, _ schedule: FixedSchedule, from start: String) -> FixedExpense {
    FixedExpense(
        fields: FixedFields(amount: amount, categoryId: Categories.named("居住").id, note: "房租", schedule: schedule),
        startsOn: start, createdAt: epoch
    )
}

private func due(_ items: [FixedExpense], _ rows: [Txn] = [], today: String) -> [Txn] {
    FixedPlan.due(items: items, transactions: rows, today: today, days: days, now: epoch)
}

private func report(
    _ rows: [Txn], month: String = "2026-11", today: String = "2026-11-25", budget: Int? = nil, fixed: [FixedExpense] = []
) -> MonthReport {
    Analysis.report(
        month: month + "-01", today: today, transactions: rows,
        budgets: budget.map { [Budget(month: "2026-01-01", amount: $0, createdAt: epoch)] } ?? [],
        book: CategoryBook(), days: days, fixed: fixed
    )
}

final class FixedPlanTests: XCTestCase {
    func testShortMonthsUseTheLastDay() {
        let schedule = FixedSchedule.monthly(day: 31)
        XCTAssertEqual(schedule.due(inMonthOf: "2026-02-10", days: days), "2026-02-28")
        XCTAssertEqual(schedule.due(inMonthOf: "2028-02-10", days: days), "2028-02-29")
        XCTAssertEqual(schedule.due(inMonthOf: "2026-11-01", days: days), "2026-11-30")
        XCTAssertNil(FixedSchedule.yearly(month: 3, day: 15).due(inMonthOf: "2026-11-01", days: days))
        XCTAssertEqual(FixedSchedule.yearly(month: 3, day: 15).due(inMonthOf: "2026-03-01", days: days), "2026-03-15")
    }

    func testRecordsEveryPeriodOnceOnItsOwnDay() {
        let rent = item(12000, .monthly(day: 5), from: "2026-09-06")
        let rows = due([rent], today: "2026-11-25")
        XCTAssertEqual(rows.map(\.occurredOn), ["2026-10-05", "2026-11-05"], "設定以前到期的不補，好幾個月沒開會補齊")
        XCTAssertEqual(rows.first?.note, "房租")
        XCTAssertEqual(rows.first?.isOneOff, false)
        XCTAssertTrue(due([rent], rows, today: "2026-11-25").isEmpty)
        XCTAssertTrue(due([rent], rows, today: "2026-12-04").isEmpty)
        XCTAssertEqual(due([rent], rows, today: "2026-12-05").map(\.occurredOn), ["2026-12-05"])
    }

    func testDeletedRecordDoesNotComeBack() {
        let rent = item(12000, .monthly(day: 5), from: "2026-11-01")
        var rows = due([rent], today: "2026-11-25")
        rows[0].deletedAt = epoch
        XCTAssertTrue(due([rent], rows, today: "2026-11-25").isEmpty)
    }

    func testYearlyIsRecordedOnceAYearAndNotCompared() {
        let car = item(12000, .yearly(month: 3, day: 15), from: "2025-03-15")
        let rows = due([car], today: "2026-11-25")
        XCTAssertEqual(rows.map(\.occurredOn), ["2025-03-15", "2026-03-15"])
        XCTAssertTrue(rows.allSatisfy(\.isOneOff))
    }

    func testEndedItemStopsAndCanComeBack() {
        let rent = item(12000, .monthly(day: 5), from: "2026-11-01").ended(on: "2026-11-04")
        XCTAssertTrue(due([rent], today: "2026-12-25").isEmpty)
        XCTAssertEqual(due([rent.resumed()], today: "2026-11-25").count, 1)
    }

    func testChangingTheAmountKeepsEarlierPeriods() {
        var fields = item(12000, .monthly(day: 5), from: "2026-09-01").fields
        fields.amount = 13000
        let rent = item(12000, .monthly(day: 5), from: "2026-09-01").applying(fields, on: "2026-10-20")
        XCTAssertEqual(due([rent], today: "2026-11-25").map(\.amount), [12000, 12000, 13000])
    }

    func testChangingTheDayNeverLooksBack() {
        let rent = item(12000, .monthly(day: 28), from: "2026-09-01")
        let posted = due([rent], today: "2026-11-10")
        var fields = rent.fields
        fields.schedule = .monthly(day: 3)
        let moved = rent.applying(fields, on: "2026-11-10")
        XCTAssertTrue(due([moved], posted, today: "2026-11-10").isEmpty)
        XCTAssertEqual(moved.nextDue(from: "2026-11-10", days: days), "2026-12-03")

        fields.schedule = .yearly(month: 1, day: 1)
        XCTAssertEqual(rent.applying(fields, on: "2026-11-10").schedule, .monthly(day: 28), "每月不能換成每年")
    }

    func testNextDue() {
        XCTAssertEqual(item(1, .monthly(day: 5), from: "2026-11-05").nextDue(from: "2026-11-05", days: days), "2026-11-05")
        XCTAssertEqual(item(1, .monthly(day: 5), from: "2026-11-06").nextDue(from: "2026-11-06", days: days), "2026-12-05")
        XCTAssertEqual(
            item(1, .yearly(month: 3, day: 15), from: "2026-11-06").nextDue(from: "2026-11-06", days: days), "2027-03-15"
        )
    }

    func testCodable() throws {
        let car = item(12000, .yearly(month: 3, day: 15), from: "2026-11-01")
        XCTAssertEqual(try JSONDecoder().decode(FixedExpense.self, from: JSONEncoder().encode(car)), car)
        let row = due([item(1, .monthly(day: 1), from: "2026-11-01")], today: "2026-11-01")[0]
        XCTAssertEqual(try JSONDecoder().decode(Txn.self, from: JSONEncoder().encode(row)), row)
    }

    func testOldRecordsWithoutTheNewFieldsStillRead() throws {
        let row = tx(100, "2026-11-01")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(row)) as? [String: Any])
        json["fixed"] = nil
        json["estimate"] = nil
        json["schemaVersion"] = 1
        let old = try JSONDecoder().decode(Txn.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(old.amount, 100)
        XCTAssertNil(old.fixed)
        XCTAssertNil(old.estimate)
    }
}

final class LeftToSpendTests: XCTestCase {
    /// 研究對照裡的例子：3 號花了 6,500，5 號要繳房租，一年一次的保費。
    func testExample() {
        let fixed = [
            item(12000, .monthly(day: 5), from: "2026-11-01"),
            item(24000, .yearly(month: 12, day: 20), from: "2026-11-01"),
        ]
        let status = report([tx(6500, "2026-11-02")], today: "2026-11-03", budget: 30000, fixed: fixed).budget
        XCTAssertEqual(status?.pending, 12000)
        XCTAssertEqual(status?.yearlyShare, 2000)
        XCTAssertEqual(status?.left, 9500)
        XCTAssertEqual(status.flatMap(AnalysisText.reserved), "已經先留 NT$14,000 給固定支出。")
    }

    func testLeftDoesNotJumpWhenTheRentIsRecorded() {
        let rent = item(12000, .monthly(day: 5), from: "2026-11-01")
        let before = report([tx(6500, "2026-11-02")], today: "2026-11-04", budget: 30000, fixed: [rent]).budget
        let rows = [tx(6500, "2026-11-02")] + due([rent], today: "2026-11-05")
        let after = report(rows, today: "2026-11-05", budget: 30000, fixed: [rent]).budget
        XCTAssertEqual(before?.left, 11500)
        XCTAssertEqual(after?.left, 11500)
        XCTAssertEqual(after?.pending, 0)
    }

    func testYearlyPaymentDoesNotEatTheMonth() {
        let car = item(24000, .yearly(month: 11, day: 20), from: "2026-11-01")
        let rows = [tx(6500, "2026-11-02")] + due([car], today: "2026-11-25")
        let r = report(rows, budget: 30000, fixed: [car])
        XCTAssertEqual(r.expense, 30500, "總額照實算")
        XCTAssertEqual(r.budget?.left, 21500)
        XCTAssertEqual(r.budget.flatMap(AnalysisText.yearlyPaid), "其中一年一次的 NT$24,000，預算分 12 個月算。")
    }

    func testShareRoundsUpAndFollowsThePastAmount() {
        var fields = item(1000, .yearly(month: 3, day: 1), from: "2026-09-01").fields
        XCTAssertEqual(item(1000, .yearly(month: 3, day: 1), from: "2026-09-01").monthlyShare, 84)
        fields.amount = 12000
        let car = item(1000, .yearly(month: 3, day: 1), from: "2026-09-01").applying(fields, on: "2026-11-10")
        XCTAssertEqual(report([tx(1, "2026-10-01")], month: "2026-10", budget: 100, fixed: [car]).budget?.yearlyShare, 84)
        XCTAssertEqual(report([tx(1, "2026-11-01")], budget: 100, fixed: [car]).budget?.yearlyShare, 1000)
        XCTAssertEqual(report([tx(1, "2026-08-01")], month: "2026-08", budget: 100, fixed: [car]).budget?.yearlyShare, 0)
    }

    func testDeletedOrChangedItemsStopReserving() {
        let rent = item(12000, .monthly(day: 28), from: "2026-11-01")
        XCTAssertEqual(report([tx(1, "2026-11-01")], budget: 30000, fixed: [rent.ended(on: "2026-11-25")]).budget?.pending, 0)
        let car = item(24000, .yearly(month: 3, day: 1), from: "2026-10-01").ended(on: "2026-11-25")
        XCTAssertEqual(report([tx(1, "2026-11-01")], budget: 30000, fixed: [car]).budget?.yearlyShare, 0)
    }

    func testWordsWhenTheReservedPartIsTooMuch() {
        let rent = item(12000, .monthly(day: 28), from: "2026-11-01")
        let status = report([tx(9000, "2026-11-01")], budget: 20000, fixed: [rent]).budget
        XCTAssertEqual(status.map(AnalysisText.budget), "預算 NT$20,000，固定支出還差 NT$1,000。")
        XCTAssertEqual(status.map(AnalysisText.homeBudget), "預算 NT$20,000")
    }

    func testPastMonthHasNothingPending() {
        let rent = item(12000, .monthly(day: 28), from: "2026-10-01")
        XCTAssertEqual(report([tx(1, "2026-10-01")], month: "2026-10", budget: 30000, fixed: [rent]).budget?.pending, 0)
    }

    func testMonthlyRangeSpreadsTheYearlyOne() {
        let car = item(12000, .yearly(month: 10, day: 20), from: "2026-08-01")
        let rows = everyDay("2026-09", through: 30, amount: 100) + everyDay("2026-10", through: 31, amount: 100)
            + due([car], today: "2026-11-25")
        XCTAssertEqual(
            Analysis.monthlyRange(today: "2026-11-25", transactions: rows, days: days, fixed: [car]),
            UsualRange(low: 4000, high: 4100, months: 2)
        )
    }

    func testAutomaticRecordsAreNotRecordKeeping() {
        let items = (1...12).map { item(100, .monthly(day: $0 * 2), from: "2026-10-01") }
        let rows = due(items, today: "2026-11-25") + [tx(50, "2026-09-01")]
        XCTAssertEqual(Analysis.comparableMonths(before: "2026-11-01", transactions: rows, days: days), [])
        XCTAssertTrue(report(rows).biggest.isEmpty)
        XCTAssertEqual(report(rows).gapToFill, DayRange(from: "2026-11-01", to: "2026-11-24"))
    }

    func testPlannedDemo() {
        let today = "2026-11-25"
        let items = DemoData.planned.fixed(today: today, days: days)
        let rows = DemoData.planned.transactions(today: today, days: days)
        let all = rows + due(items, rows, today: today)
        let r = Analysis.report(
            month: today, today: today, transactions: all,
            budgets: DemoData.planned.budgets(today: today, days: days), book: CategoryBook(), days: days, fixed: items
        )
        XCTAssertEqual(r.expense, 24590)
        XCTAssertEqual(r.budget?.reserved, 2899)
        XCTAssertEqual(r.budget?.left, 8511)
    }
}

final class EstimateTests: XCTestCase {
    private let gap = DayRange(from: "2026-11-04", to: "2026-11-16")
    private var baseline: [Txn] {
        everyDay("2026-08", through: 31, amount: 100) + everyDay("2026-09", through: 30, amount: 110)
            + everyDay("2026-10", through: 31, amount: 120)
    }

    func testFillingTheGapBringsTheComparisonBack() {
        let holes = baseline + everyDay("2026-11", through: 25, amount: 105, skipping: 4...16)
        XCTAssertEqual(report(holes).gapToFill, gap)
        let filled = report(holes + [tx(1365, "2026-11-16", "其他", estimate: gap)])
        XCTAssertNil(filled.gapToFill)
        XCTAssertEqual(filled.expense, 2625)
        XCTAssertTrue(AnalysisText.comparison(filled).hasPrefix("跟平常差不多"))
    }

    func testDeletingTheEstimateOpensTheGapAgain() {
        var rows = everyDay("2026-11", through: 25, amount: 105, skipping: 4...16)
            + [tx(1365, "2026-11-16", "其他", estimate: gap)]
        rows[rows.count - 1].deletedAt = epoch
        XCTAssertEqual(report(rows).gapToFill, gap)
    }

    func testFilledMonthCanBeABaselineAndIsSpreadByDay() {
        let rows = everyDay("2026-09", through: 30, amount: 100)
            + everyDay("2026-10", through: 31, amount: 100, skipping: 11...20)
            + [tx(1000, "2026-10-20", "其他", estimate: DayRange(from: "2026-10-11", to: "2026-10-20"))]
            + everyDay("2026-11", through: 15, amount: 100)
        XCTAssertEqual(
            report(rows, today: "2026-11-15").comparison, .ready(UsualRange(low: 1500, high: 1500, months: 2)),
            "11 到 15 號那五天照比例算"
        )
    }

    func testEstimateIsNeverOneOfTheBiggestNorAnObservation() {
        let rows = baseline + everyDay("2026-11", through: 25, amount: 105, skipping: 4...16)
            + [tx(90000, "2026-11-16", "飲食", estimate: gap)]
        let r = report(rows)
        XCTAssertFalse(r.biggest.contains { $0.estimate != nil })
        XCTAssertNil(r.observation)
        XCTAssertNil(r.categories.first?.usual)
        XCTAssertEqual(r.categories.reduce(0) { $0 + $1.total }, r.expense)
    }

    func testNoGapBeforeTheFirstRecordOrForToday() {
        XCTAssertNil(report([tx(1, "2026-11-20")]).gapToFill, "還沒開始用的日子不用補")
        XCTAssertNil(report([]).gapToFill)
        XCTAssertEqual(
            report(everyDay("2026-11", through: 10, amount: 1)).gapToFill, DayRange(from: "2026-11-11", to: "2026-11-24"),
            "今天還沒過完，不補"
        )
        XCTAssertNil(report(everyDay("2026-11", through: 17, amount: 1), today: "2026-11-24").gapToFill, "7 天以內不算空窗")
    }

    func testEditingMovesOrDropsTheEstimate() {
        let row = tx(1000, "2026-11-16", "其他", estimate: gap)
        var fields = row.fields
        fields.amount = 1200
        XCTAssertEqual(row.applying(fields, at: epoch).estimate, gap)
        fields.occurredOn = "2026-11-20"
        XCTAssertNil(row.applying(fields, at: epoch).estimate)
    }

    func testCSVSaysWhereItCameFrom() {
        let csv = CSVExport.make(
            transactions: [
                tx(1, "2026-11-01"),
                tx(2, "2026-11-02", estimate: DayRange(from: "2026-11-01", to: "2026-11-02")),
                tx(3, "2026-11-03", fixed: FixedOrigin(itemId: UUID(), period: "2026-11", isYearly: false)),
                tx(4, "2026-11-04", fixed: FixedOrigin(itemId: UUID(), period: "2026", isYearly: true)),
            ],
            book: CategoryBook()
        )
        let sources = csv.components(separatedBy: "\r\n").dropFirst().prefix(4).map { $0.components(separatedBy: ",").last ?? "" }
        XCTAssertEqual(sources, ["", "大概", "每月固定", "每年固定"])
    }

    func testWordsHaveNoForbiddenOnes() {
        let status = BudgetStatus(budget: 100, spent: 10, pending: 200, yearlyShare: 5, yearlyPaid: 60, daysLeft: 3)
        let lines = [
            AnalysisText.budget(status), AnalysisText.reserved(status), AnalysisText.yearlyPaid(status),
            AnalysisText.estimateLink, AnalysisText.estimateTitle(gap), AnalysisText.share(100),
            AnalysisText.schedule(.monthly(day: 5)), AnalysisText.schedule(.yearly(month: 3, day: 15)),
            AnalysisText.nextDue("2026-11-05"), AnalysisText.posted([("房租", 1)]), AnalysisText.posted([("房租", 1), ("網路", 2)]),
        ].compactMap { $0 }
        for line in lines {
            for word in AnalysisText.forbidden {
                XCTAssertFalse(line.contains(word), "「\(line)」裡有禁用字「\(word)」")
            }
        }
        XCTAssertEqual(AnalysisText.estimateTitle(gap), "11/4 到 11/16 大概花了多少")
        XCTAssertEqual(AnalysisText.nextDue("2026-12-05"), "下一次記在 2026 年 12 月 5 日。")
        XCTAssertEqual(AnalysisText.posted([("房租", 12000)]), "記好了。房租 NT$12,000")
        XCTAssertEqual(AnalysisText.posted([("房租", 12000), ("網路", 699)]), "記好了 2 筆固定支出，共 NT$12,699")
    }
}

final class WidgetSnapshotTests: XCTestCase {
    private let rent = item(12000, .monthly(day: 5), from: "2026-11-01")
    private let budgets = [Budget(month: "2026-11-01", amount: 30000, createdAt: epoch)]

    func testSameNumbersAsTheApp() throws {
        let rows = [tx(6500, "2026-11-02"), tx(900, "2026-10-02"), tx(50000, "2026-11-02", "薪水")]
        let snapshot = WidgetSnapshot(today: "2026-11-03", transactions: rows, budgets: budgets, fixed: [rent])
        let back = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(snapshot))
        let figures = back.figures(today: "2026-11-03", days: days)
        XCTAssertEqual(figures.expense, 6500)
        XCTAssertEqual(figures.label, "還能花")
        XCTAssertEqual(figures.amount, 11500)
    }

    func testDayAndMonthRollOverWithoutOpeningTheApp() {
        let snapshot = WidgetSnapshot(
            today: "2026-11-03", transactions: [tx(6500, "2026-11-02")], budgets: budgets, fixed: [rent]
        )
        let onRentDay = snapshot.figures(today: "2026-11-05", days: days)
        XCTAssertEqual(onRentDay.expense, 18500, "房租那天自己算進去")
        XCTAssertEqual(onRentDay.amount, 11500)
        let nextMonth = snapshot.figures(today: "2026-12-01", days: days)
        XCTAssertEqual(nextMonth.expense, 0)
        XCTAssertEqual(nextMonth.amount, 18000)
    }

    func testPostedRentIsNotCountedTwice() {
        let rows = due([rent], today: "2026-11-05")
        let snapshot = WidgetSnapshot(today: "2026-11-05", transactions: rows, budgets: budgets, fixed: [rent])
        XCTAssertEqual(snapshot.figures(today: "2026-11-06", days: days).expense, 12000)
        var gone = rows
        gone[0].deletedAt = epoch
        let afterDelete = WidgetSnapshot(today: "2026-11-05", transactions: gone, budgets: budgets, fixed: [rent])
        XCTAssertEqual(afterDelete.figures(today: "2026-11-06", days: days).expense, 0)
    }

    func testNoBudgetShowsTheMonthAndNoNotesLeak() throws {
        var fields = tx(100, "2026-11-02").fields
        fields.note = "秘密"
        let row = Txn(fields: fields, createdAt: epoch, timeZone: "Asia/Taipei")
        let snapshot = WidgetSnapshot(today: "2026-11-03", transactions: [row], budgets: [], fixed: [rent])
        XCTAssertEqual(snapshot.figures(today: "2026-11-03", days: days).label, "本月支出")
        let json = try XCTUnwrap(String(data: JSONEncoder().encode(snapshot), encoding: .utf8))
        XCTAssertFalse(json.contains("秘密"))
        XCTAssertFalse(json.contains("房租"))
    }
}
