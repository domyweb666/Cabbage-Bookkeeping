import XCTest
@testable import FinanceCore

final class MoneyTests: XCTestCase {
    func testGroupedAndFormat() {
        XCTAssertEqual(Money.grouped(0), "0")
        XCTAssertEqual(Money.grouped(188), "188")
        XCTAssertEqual(Money.grouped(1234), "1,234")
        XCTAssertEqual(Money.grouped(52000), "52,000")
        XCTAssertEqual(Money.grouped(1234567), "1,234,567")
        XCTAssertEqual(Money.format(3240), "NT$3,240")
        XCTAssertEqual(Money.signed(188, type: .expense), "-188")
        XCTAssertEqual(Money.signed(52000, type: .income), "+52,000")
    }

    func testParse() {
        XCTAssertEqual(Money.parse("188"), 188)
        XCTAssertEqual(Money.parse(" 1,280 "), 1280)
        XCTAssertEqual(Money.parse("１２０"), 120)
        XCTAssertEqual(Money.parse("52，000"), 52000)
        XCTAssertNil(Money.parse(""))
        XCTAssertNil(Money.parse("0"))
        XCTAssertNil(Money.parse("12.5"))
        XCTAssertNil(Money.parse("-5"))
        XCTAssertNil(Money.parse("三百"))
        XCTAssertNil(Money.parse("1234567890"))
    }
}

final class DaysTests: XCTestCase {
    let days = Days.taipei

    func testDayUsesTaipeiTimeZone() {
        let f = ISO8601DateFormatter()
        // UTC 16:30 已經是台北隔天 00:30。
        XCTAssertEqual(days.day(of: f.date(from: "2026-11-14T16:30:00Z")!), "2026-11-15")
        XCTAssertEqual(days.day(of: f.date(from: "2026-11-14T15:59:59Z")!), "2026-11-14")
    }

    func testAddingDaysAndMonths() {
        XCTAssertEqual(days.adding(days: -1, to: "2026-11-01"), "2026-10-31")
        XCTAssertEqual(days.adding(days: 1, to: "2026-12-31"), "2027-01-01")
        XCTAssertEqual(days.adding(days: -1, to: "2028-03-01"), "2028-02-29")
        XCTAssertEqual(days.monthStart(of: "2026-11-15"), "2026-11-01")
        XCTAssertEqual(days.adding(months: -1, toMonthOf: "2026-01-20"), "2025-12-01")
        XCTAssertEqual(days.adding(months: 1, toMonthOf: "2026-11-30"), "2026-12-01")
    }

    func testInvalidDayIsRejected() {
        XCTAssertNil(days.date(of: "2026-02-30"))
        XCTAssertNil(days.date(of: "昨天"))
    }

    func testTitles() {
        XCTAssertEqual(days.sectionTitle(for: "2026-11-15", today: "2026-11-15"), "今天")
        XCTAssertEqual(days.sectionTitle(for: "2026-11-14", today: "2026-11-15"), "昨天")
        XCTAssertEqual(days.sectionTitle(for: "2026-11-13", today: "2026-11-15"), "11 月 13 日 週五")
        XCTAssertEqual(days.sectionTitle(for: "2025-12-31", today: "2026-01-02"), "2025 年 12 月 31 日 週三")
        XCTAssertEqual(days.monthTitle(of: "2026-11-15"), "2026 年 11 月")
    }

    func testISO8601CarriesOffset() {
        let date = ISO8601DateFormatter().date(from: "2026-11-15T04:30:00Z")!
        XCTAssertEqual(days.iso8601(date), "2026-11-15T12:30:00+08:00")
    }
}

final class TimelineTests: XCTestCase {
    let food = UUID()

    func tx(_ amount: Int, _ day: String, type: TxType = .expense, created: String, deleted: Bool = false) -> Txn {
        Txn(id: UUID(), type: type, amount: amount, occurredOn: day, item: "x", categoryId: food,
            createdAt: created, deletedAt: deleted ? "2026-11-15T00:00:00Z" : nil)
    }

    func testSectionsAreOldestFirstWithDailyTotals() {
        let sections = Timeline.sections(from: [
            tx(450, "2026-11-15", created: "2026-11-15T12:00:00Z"),
            tx(65, "2026-11-15", created: "2026-11-15T01:00:00Z"),
            tx(500, "2026-11-14", created: "2026-11-15T02:00:00Z"),
            tx(52000, "2026-11-14", type: .income, created: "2026-11-14T02:00:00Z"),
            tx(999, "2026-11-15", created: "2026-11-15T03:00:00Z", deleted: true),
        ])
        XCTAssertEqual(sections.map(\.day), ["2026-11-14", "2026-11-15"])
        XCTAssertEqual(sections[1].items.map(\.amount), [65, 450])
        XCTAssertEqual(sections[1].expenseTotal, 515)
        XCTAssertEqual(sections[0].expenseTotal, 500)
        XCTAssertEqual(sections[0].incomeTotal, 52000)
    }

    func testMonthExpenseIgnoresIncomeDeletedAndOtherMonths() {
        let total = Timeline.monthExpense(from: [
            tx(100, "2026-11-01", created: "a"),
            tx(200, "2026-11-30", created: "b"),
            tx(300, "2026-10-31", created: "c"),
            tx(400, "2026-11-10", type: .income, created: "d"),
            tx(500, "2026-11-10", created: "e", deleted: true),
        ], monthOf: "2026-11-15")
        XCTAssertEqual(total, 300)
    }

    func testBackupPromptShowsOnceAfterTwentyRecords() {
        XCTAssertFalse(BackupPrompt.shouldShow(transactionCount: 20, isLinked: false, alreadyShown: false))
        XCTAssertTrue(BackupPrompt.shouldShow(transactionCount: 21, isLinked: false, alreadyShown: false))
        XCTAssertFalse(BackupPrompt.shouldShow(transactionCount: 21, isLinked: true, alreadyShown: false))
        XCTAssertFalse(BackupPrompt.shouldShow(transactionCount: 99, isLinked: false, alreadyShown: true))
    }
}

final class PendingQueueTests: XCTestCase {
    func entry(_ text: String, at seconds: TimeInterval, state: PendingEntry.State = .waiting) -> PendingEntry {
        PendingEntry(rawText: text, source: "text", clientCreatedAt: Date(timeIntervalSince1970: seconds), state: state)
    }

    func testOfflineSendsNothing() {
        XCTAssertNil(PendingQueue.next(in: [entry("a", at: 1)], online: false))
    }

    func testSendsOldestFirstOneAtATime() {
        let a = entry("a", at: 1), b = entry("b", at: 2), c = entry("c", at: 3)
        XCTAssertEqual(PendingQueue.next(in: [c, a, b], online: true)?.rawText, "a")
        var sending = a
        sending.state = .sending
        XCTAssertNil(PendingQueue.next(in: [sending, b, c], online: true))
    }

    func testFailedEntriesAreSkippedUntilRetried() {
        let failed = entry("a", at: 1, state: .failed), b = entry("b", at: 2)
        XCTAssertEqual(PendingQueue.next(in: [failed, b], online: true)?.rawText, "b")
        XCTAssertEqual(PendingQueue.next(in: [PendingQueue.retried(failed), b], online: true)?.rawText, "a")
    }

    func testOutcomes() {
        var sending = entry("麥當勞 188", at: 1)
        sending.state = .sending
        XCTAssertNil(PendingQueue.apply(.delivered, to: sending))

        let offline = PendingQueue.apply(.networkFailure, to: sending)
        XCTAssertEqual(offline?.state, .waiting)
        XCTAssertEqual(offline?.id, sending.id)
        XCTAssertEqual(offline?.clientCreatedAt, sending.clientCreatedAt)

        let rejected = PendingQueue.apply(.rejected("今天的記帳次數已達上限"), to: sending)
        XCTAssertEqual(rejected?.state, .failed)
        XCTAssertEqual(rejected?.message, "今天的記帳次數已達上限")
        XCTAssertEqual(rejected?.rawText, "麥當勞 188")
    }

    func testRecoveryAfterRelaunch() {
        let recovered = PendingQueue.recovered([entry("a", at: 1, state: .sending), entry("b", at: 2, state: .failed)])
        XCTAssertEqual(recovered.map(\.state), [.waiting, .failed])
    }
}

final class CodingTests: XCTestCase {
    func decode<T: Decodable>(_ json: String) throws -> T {
        try JSONCoding.decoder().decode(T.self, from: Data(json.utf8))
    }

    func testCommittedResult() throws {
        let json = """
        {"success":true,"error":null,"request_id":"r1","data":{"result":"committed","entry_id":"E0000000-0000-0000-0000-000000000001",
        "transactions":[{"id":"A0000000-0000-0000-0000-000000000001","user_id":"B0000000-0000-0000-0000-000000000001",
        "entry_id":"E0000000-0000-0000-0000-000000000001","type":"expense","amount":188,"currency":"TWD",
        "occurred_on":"2026-11-15","item":"麥當勞","merchant":"麥當勞","category_id":"C0000000-0000-0000-0000-000000000001",
        "category_source":"ai","tags":["外食","速食"],"nature":"routine","payment_method":null,"note":null,
        "created_at":"2026-11-15T04:30:00+00:00","updated_at":"2026-11-15T04:30:00+00:00","deleted_at":null}]}}
        """
        let envelope: APIEnvelope<RecordResult> = try decode(json)
        guard case .committed(let txs)? = envelope.data else { return XCTFail("應該是 committed") }
        XCTAssertEqual(txs.count, 1)
        XCTAssertEqual(txs[0].amount, 188)
        XCTAssertEqual(txs[0].occurredOn, "2026-11-15")
        XCTAssertEqual(txs[0].nature, .routine)
        XCTAssertEqual(txs[0].tags, ["外食", "速食"])
        XCTAssertNil(txs[0].deletedAt)
    }

    func testNeedsConfirmResult() throws {
        let json = """
        {"result":"needs_confirm","entry_id":"E0000000-0000-0000-0000-000000000001","drafts":[{"type":"expense","amount":45000,
        "occurred_on":"2026-11-15","item":"電腦","merchant":null,"category_id":null,"category_name":null,"category_source":"ai",
        "tags":[],"nature":"one_off","payment_method":null,"reasons":["金額超過 10,000","分類不確定"]}]}
        """
        guard case .needsConfirm(let drafts) = try decode(json) as RecordResult else { return XCTFail("應該是 needs_confirm") }
        XCTAssertEqual(drafts[0].reasons, ["金額超過 10,000", "分類不確定"])
        XCTAssertEqual(drafts[0].nature, .oneOff)
        XCTAssertEqual(drafts[0].problems(today: "2026-11-15"), ["需要選分類"])
    }

    func testAnswerUnclearAndError() throws {
        let answer = """
        {"result":"answer","entry_id":"E0000000-0000-0000-0000-000000000001","answer":"11 月到目前外食共 NT$3,240，一共 18 筆。",
        "evidence":[{"tool":"sum_transactions","filters":{"tags":["外食"]},"count":2,"total":3240,
        "transaction_ids":["A0000000-0000-0000-0000-000000000001","A0000000-0000-0000-0000-000000000002"]},
        {"tool":"list_transactions","filters":{},"count":1,"total":100,"transaction_ids":["A0000000-0000-0000-0000-000000000001"]}]}
        """
        guard case .answer(let a) = try decode(answer) as RecordResult else { return XCTFail("應該是 answer") }
        XCTAssertEqual(a.evidence[0].total, 3240)
        XCTAssertEqual(a.evidenceCount, 2)

        guard case .unclear(let message) = try decode(#"{"result":"unclear","entry_id":"x","message":"要記多少錢？"}"#) as RecordResult
        else { return XCTFail("應該是 unclear") }
        XCTAssertEqual(message, "要記多少錢？")

        let failed: APIEnvelope<RecordResult> = try decode(
            #"{"success":false,"data":null,"error":{"code":"daily_limit","message":"今天的記帳次數已達上限"},"request_id":"r"}"#
        )
        XCTAssertFalse(failed.success)
        XCTAssertEqual(failed.error?.code, "daily_limit")
    }

    func testDraftEncodesSnakeCaseForConfirm() throws {
        let draft = Draft(type: .expense, amount: 120, occurredOn: "2026-11-15", item: "午餐", categoryId: UUID())
        let data = try JSONCoding.encoder().encode(draft)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["occurred_on"] as? String, "2026-11-15")
        XCTAssertNotNil(object["category_id"])
        XCTAssertNil(object["id"])
    }

    func testOverview() throws {
        let json = """
        {"month":"2026-11","total_expense":5000,"total_income":52000,"routine_expense":350,"one_off_expense":4650,
        "transaction_count":4,"by_category":[{"category_id":"C0000000-0000-0000-0000-000000000001","name":"交通",
        "icon":"car.fill","total":4650,"count":1}]}
        """
        let overview: MonthlyOverview = try decode(json)
        XCTAssertEqual(overview.routineExpense, 350)
        XCTAssertEqual(overview.byCategory.first?.name, "交通")
    }
}

final class CSVTests: XCTestCase {
    func testExport() {
        let food = TxCategory(id: UUID(), name: "飲食", kind: .expense, icon: "fork.knife", sortOrder: 1)
        let rows = [
            Txn(id: UUID(), type: .expense, amount: 450, occurredOn: "2026-11-15", item: "火鍋, 兩人", merchant: "鼎王",
                categoryId: food.id, tags: ["外食", "聚餐"], nature: .routine, note: "他說\"好吃\"", createdAt: "b"),
            Txn(id: UUID(), type: .expense, amount: 65, occurredOn: "2026-11-14", item: "=SUM(A1)", categoryId: food.id, createdAt: "a"),
            Txn(id: UUID(), type: .expense, amount: 1, occurredOn: "2026-11-13", item: "已刪除", categoryId: food.id,
                createdAt: "a", deletedAt: "x"),
        ]
        let csv = CSVExport.make(transactions: rows, categories: [food])
        let lines = csv.components(separatedBy: "\r\n")
        XCTAssertTrue(csv.hasPrefix("\u{FEFF}日期,類型,金額"))
        XCTAssertEqual(lines.count, 4)
        XCTAssertEqual(lines[1], "2026-11-14,支出,65,\"'=SUM(A1)\",飲食,,,,,")
        XCTAssertEqual(lines[2], "2026-11-15,支出,450,\"火鍋, 兩人\",飲食,鼎王,外食、聚餐,日常,,\"他說\"\"好吃\"\"\"")
    }
}
