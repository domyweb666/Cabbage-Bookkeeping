import XCTest
@testable import FinanceCore

// 分析頁四種看法要的數字（每天、這週跟上週、圓餅）和句子。

private let days = Days.taipei

private func spend(
    _ amount: Int, _ day: String, _ category: String = "飲食", estimate: DayRange? = nil, deleted: Bool = false
) -> Txn {
    let c = Categories.named(category)
    var row = Txn(
        fields: TxnFields(type: c.kind, amount: amount, occurredOn: day, categoryId: c.id),
        createdAt: Date(timeIntervalSince1970: 0), timeZone: "Asia/Taipei", estimate: estimate
    )
    if deleted { row.deletedAt = Date(timeIntervalSince1970: 1) }
    return row
}

private func line(_ name: String, _ total: Int) -> CategoryLine {
    CategoryLine(category: Categories.named(name), total: total, oneOff: 0, count: 1, usual: nil)
}

final class AnalysisModesTests: XCTestCase {
    // MARK: - 每天花多少

    func testDailyCoversTheWholeMonthAndSkipsFixedAndEstimates() {
        let fixedRow = FixedPlan.due(
            items: [FixedExpense(
                fields: FixedFields(amount: 8000, categoryId: Categories.named("居住").id, note: "房租", schedule: .monthly(day: 1)),
                startsOn: "2026-11-01", createdAt: Date(timeIntervalSince1970: 0)
            )],
            transactions: [], today: "2026-11-25", days: days, now: Date(timeIntervalSince1970: 0)
        )
        let rows = [
            spend(120, "2026-11-03"), spend(80, "2026-11-03", "交通"), spend(500, "2026-11-08"),
            spend(3000, "2026-11-20", estimate: DayRange(from: "2026-11-10", to: "2026-11-20")),
            spend(999, "2026-11-04", deleted: true), spend(40, "2026-10-31"),
        ] + fixedRow
        let daily = Analysis.daily(month: "2026-11-15", today: "2026-11-25", transactions: rows, days: days)

        XCTAssertEqual(daily.days.count, 30)
        XCTAssertEqual(daily.days.first?.day, "2026-11-01")
        XCTAssertEqual(daily.days[2].amount, 200)
        XCTAssertEqual(daily.days[2].count, 2)
        XCTAssertEqual(daily.days[3].amount, 0, "刪掉的不算")
        XCTAssertEqual(daily.days[19].amount, 0, "補的大概不畫")
        XCTAssertEqual(daily.hidden, 3000 + fixedRow.reduce(0) { $0 + $1.amount })
        XCTAssertFalse(daily.days[24].isFuture)
        XCTAssertTrue(daily.days[25].isFuture)
        XCTAssertEqual(daily.top?.day, "2026-11-08")
        XCTAssertEqual(AnalysisText.dailyAnswer(daily), "最多的一天是 11/8，NT$500。")
    }

    func testDailyTopPicksTheEarlierDayOnATie() {
        let rows = [spend(300, "2026-11-05"), spend(300, "2026-11-02")]
        let daily = Analysis.daily(month: "2026-11-01", today: "2026-11-25", transactions: rows, days: days)
        XCTAssertEqual(daily.top?.day, "2026-11-02")
        XCTAssertNil(Analysis.daily(month: "2026-11-01", today: "2026-11-25", transactions: [], days: days).top)
        XCTAssertNil(AnalysisText.dailyHidden(0))
    }

    func testLevelsSplitEvenly() {
        let rows = [spend(900, "2026-11-01"), spend(300, "2026-11-02"), spend(301, "2026-11-03"), spend(601, "2026-11-04"), spend(1, "2026-11-05")]
        let daily = Analysis.daily(month: "2026-11-01", today: "2026-11-25", transactions: rows, days: days)
        XCTAssertEqual(daily.days.prefix(6).map(daily.level(of:)), [3, 1, 2, 3, 1, 0])
    }

    // MARK: - 這週跟上週

    func testWeekdayStartsOnSunday() {
        XCTAssertEqual(days.weekday(of: "2026-11-22"), 0)
        XCTAssertEqual(days.weekday(of: "2026-11-26"), 4)
        XCTAssertEqual(days.weekday(of: "2026-11-28"), 6)
    }

    func testWeekComparesTheSameDays() throws {
        let rows = [
            spend(1000, "2026-11-23"), spend(1140, "2026-11-26"), spend(500, "2026-11-27"),
            spend(2000, "2026-11-15"), spend(860, "2026-11-19"), spend(700, "2026-11-20"),
        ]
        let week = try XCTUnwrap(Analysis.weekComparison(today: "2026-11-26", transactions: rows, days: days))
        XCTAssertEqual(week.thisWeek, DayRange(from: "2026-11-22", to: "2026-11-26"))
        XCTAssertEqual(week.lastWeek, DayRange(from: "2026-11-15", to: "2026-11-19"))
        XCTAssertEqual(week.thisAmount, 2140)
        XCTAssertEqual(week.lastAmount, 2860)
        XCTAssertEqual(
            AnalysisText.week(week, todayName: Days.weekdayNames[4]), "這週到週四 NT$2,140，比上週同幾天少 NT$720。"
        )
        XCTAssertEqual(AnalysisText.weekLabel(week.lastWeek, isThisWeek: false), "上週 11/15 到 11/19")
    }

    func testWeekCrossesMonthsAndNeedsLastWeek() {
        // 12/2 是週三，這週從 11/29 開始。
        let rows = [spend(100, "2026-11-30"), spend(100, "2026-11-23")]
        let week = Analysis.weekComparison(today: "2026-12-02", transactions: rows, days: days)
        XCTAssertEqual(week?.thisWeek.from, "2026-11-29")
        XCTAssertEqual(week.map { AnalysisText.week($0, todayName: "三") }, "這週到週三 NT$100，跟上週同幾天一樣。")
        XCTAssertNil(Analysis.weekComparison(today: "2026-11-26", transactions: [spend(100, "2026-11-24")], days: days))
    }

    // MARK: - 圓餅

    func testPercentsAlwaysAddUpTo100() {
        XCTAssertEqual(Analysis.percents(of: [1, 1, 1]), [34, 33, 33])
        XCTAssertEqual(Analysis.percents(of: [8000, 5420, 2180, 1560, 1480]), [43, 29, 12, 8, 8])
        XCTAssertEqual(Analysis.percents(of: [5]), [100])
        XCTAssertEqual(Analysis.percents(of: [0, 0]), [0, 0])
        for amounts in [[7, 3, 1], [999, 1], [10, 20, 30, 40, 50, 60, 70]] {
            XCTAssertEqual(Analysis.percents(of: amounts).reduce(0, +), 100)
        }
    }

    func testSmallCategoriesMergeIntoOneSlice() {
        let lines = [
            line("居住", 8000), line("飲食", 5420), line("交通", 2180), line("購物", 1560), line("娛樂", 900),
            line("醫療", 400), line("其他", 180),
        ]
        let slices = Analysis.slices(of: lines)
        XCTAssertEqual(slices.count, 6)
        XCTAssertEqual(slices.prefix(5).map { $0.category?.name }, ["居住", "飲食", "交通", "購物", "娛樂"])
        XCTAssertNil(slices[5].category)
        XCTAssertEqual(slices[5].amount, 580)
        XCTAssertEqual(slices[5].merged, 2)
        XCTAssertEqual(slices.reduce(0) { $0 + $1.amount }, lines.reduce(0) { $0 + $1.total })
        XCTAssertEqual(slices.reduce(0) { $0 + $1.percent }, 100)
        XCTAssertEqual(AnalysisText.restSlice(2), "其餘 2 類")
    }

    func testOneExtraCategoryIsNotMerged() {
        let lines = (1...6).map { line(["居住", "飲食", "交通", "購物", "娛樂", "醫療"][$0 - 1], 100 * (7 - $0)) }
        let slices = Analysis.slices(of: lines)
        XCTAssertEqual(slices.count, 6)
        XCTAssertTrue(slices.allSatisfy { $0.category != nil && $0.merged == 1 })
        XCTAssertEqual(Analysis.slices(of: lines, top: 99).count, 6)
        XCTAssertTrue(Analysis.slices(of: []).isEmpty)
    }

    // MARK: - 句子

    func testHeadlineAndBudgetSentences() {
        let rows = DemoData.steady.transactions(today: "2026-11-25", days: days)
        let budgets = DemoData.steady.budgets(today: "2026-11-25", days: days)
        let r = Analysis.report(
            month: "2026-11-01", today: "2026-11-25", transactions: rows, budgets: budgets, book: CategoryBook(), days: days
        )
        XCTAssertTrue(AnalysisText.headline(r).hasPrefix("這個月"))
        XCTAssertTrue(AnalysisText.headlineDetail(r)?.contains("平常到 25 號是") ?? false)
        let status = BudgetStatus(budget: 22000, spent: 18640, pending: 849, yearlyShare: 0, yearlyPaid: 0, daysLeft: 5)
        XCTAssertEqual(AnalysisText.budgetDays(status), "剩 5 天，每天 NT$502。")
        XCTAssertEqual(AnalysisText.budgetDetail(status), "預算 NT$22,000，花了 NT$18,640，已經先留 NT$849 給固定支出。")

        let empty = Analysis.report(
            month: "2026-11-01", today: "2026-11-25", transactions: [], budgets: [], book: CategoryBook(), days: days
        )
        XCTAssertEqual(AnalysisText.headline(empty), "這個月還沒有支出紀錄。")
        XCTAssertNil(AnalysisText.headlineDetail(empty))
    }

    /// 新的句子也掃一遍禁用字。
    func testNoForbiddenWordsInModes() {
        var lines = [
            AnalysisText.dailyTitle, AnalysisText.calendarTitle, AnalysisText.calendarLow, AnalysisText.calendarHigh,
            AnalysisText.weekTitle, AnalysisText.restSlice(3),
        ]
        for today in ["2026-11-03", "2026-11-16", "2026-11-25", "2026-11-30"] {
            for kind in DemoData.allCases {
                let rows = kind.transactions(today: today, days: days)
                for limit in [1000, 20000, 90000] {
                    let budget = Budget(month: "2026-08-01", amount: limit, createdAt: Date())
                    for month in ["2026-10-01", "2026-11-01"] {
                        let r = Analysis.report(
                            month: month, today: today, transactions: rows, budgets: [budget], book: CategoryBook(), days: days
                        )
                        lines.append(AnalysisText.headline(r))
                        lines += [AnalysisText.headlineDetail(r)].compactMap { $0 }
                        if let status = r.budget { lines += [AnalysisText.budgetDays(status), AnalysisText.budgetDetail(status)] }
                        let daily = Analysis.daily(month: month, today: today, transactions: rows, days: days)
                        lines += [AnalysisText.dailyAnswer(daily), AnalysisText.dailyHidden(daily.hidden)].compactMap { $0 }
                    }
                }
                if let week = Analysis.weekComparison(today: today, transactions: rows, days: days) {
                    lines.append(AnalysisText.week(week, todayName: Days.weekdayNames[days.weekday(of: today)]))
                    lines.append(AnalysisText.weekLabel(week.thisWeek, isThisWeek: true))
                }
            }
        }
        for line in Set(lines) {
            for word in AnalysisText.forbidden {
                XCTAssertFalse(line.contains(word), "「\(line)」裡有禁用字「\(word)」")
            }
        }
    }
}
