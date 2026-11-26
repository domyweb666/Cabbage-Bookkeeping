import XCTest
@testable import FinanceCore

private let days = Days.taipei
private let epoch = Date(timeIntervalSince1970: 0)
private let trip = UUID()

private func tx(_ amount: Int, _ day: String, _ category: String = "飲食", ledger: UUID? = nil) -> Txn {
    let c = Categories.named(category)
    return Txn(
        fields: TxnFields(type: c.kind, amount: amount, occurredOn: day, categoryId: c.id),
        createdAt: epoch, timeZone: "Asia/Taipei", ledgerId: ledger
    )
}

final class LedgerTests: XCTestCase {
    /// 多帳本以前存的 JSON 沒有 ledgerId，要讀得開，而且算「我的帳本」。
    func testOldJSONWithoutLedgerIdIsTheMainLedger() throws {
        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(tx(100, "2026-11-01"))) as? [String: Any]
        )
        json["ledgerId"] = nil
        json["schemaVersion"] = 2
        let row = try JSONDecoder().decode(Txn.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(row.ledgerId)
        XCTAssertEqual(row.ledgerKey, Ledger.mainID)
        XCTAssertEqual(row.schemaVersion, 2, "讀舊的不改版本號")

        var budget = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(Budget(month: "2026-11-01", amount: 1, createdAt: epoch))
            ) as? [String: Any]
        )
        budget["ledgerId"] = nil
        let oldBudget = try JSONDecoder().decode(Budget.self, from: JSONSerialization.data(withJSONObject: budget))
        XCTAssertNil(oldBudget.ledgerId)
        XCTAssertTrue(oldBudget.belongs(to: Ledger.mainID))

        let item = FixedExpense(
            fields: FixedFields(amount: 1, categoryId: Categories.named("居住").id, schedule: .monthly(day: 1)),
            startsOn: "2026-11-01", createdAt: epoch
        )
        var fixed = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as? [String: Any])
        fixed["ledgerId"] = nil
        fixed["schemaVersion"] = 1
        let oldFixed = try JSONDecoder().decode(FixedExpense.self, from: JSONSerialization.data(withJSONObject: fixed))
        XCTAssertNil(oldFixed.ledgerId)
        XCTAssertEqual(oldFixed.ledgerKey, Ledger.mainID)
    }

    func testNewRecordsKeepTheirLedger() throws {
        let row = tx(100, "2026-11-01", ledger: trip)
        let back = try JSONDecoder().decode(Txn.self, from: JSONEncoder().encode(row))
        XCTAssertEqual(back.ledgerId, trip)
        XCTAssertEqual(back.schemaVersion, 3)
        var fields = row.fields
        fields.amount = 200
        XCTAssertEqual(row.applying(fields, at: epoch).ledgerId, trip, "改一筆不會換本")
    }

    func testFixedPostsIntoItsOwnLedger() {
        let item = FixedExpense(
            fields: FixedFields(amount: 500, categoryId: Categories.named("居住").id, schedule: .monthly(day: 5)),
            startsOn: "2026-11-01", createdAt: epoch, ledgerId: trip
        )
        let rows = FixedPlan.due(items: [item], transactions: [], today: "2026-11-05", days: days, now: epoch)
        XCTAssertEqual(rows.map(\.ledgerId), [trip])
    }

    func testMainLedgerIsAlwaysThereAndFirst() {
        let later = Ledger(name: "旅行", color: .blue, createdAt: Date(timeIntervalSince1970: 5))
        XCTAssertEqual(Ledgers.alive([]).map(\.id), [Ledger.mainID])
        XCTAssertEqual(Ledgers.alive([later]).map(\.name), ["我的帳本", "旅行"])
        let renamed = Ledger.main.renamed("日常", color: .green)
        XCTAssertEqual(Ledgers.alive([later, renamed]).map(\.name), ["日常", "旅行"])
        var gone = later
        gone.deletedAt = epoch
        XCTAssertEqual(Ledgers.alive([gone]).count, 1)
    }

    func testNames() {
        let other = Ledger(name: "  旅行  ", color: .blue, createdAt: epoch)
        XCTAssertEqual(other.name, "旅行")
        XCTAssertEqual(Ledgers.problem(with: " ", in: [other]), .empty)
        XCTAssertEqual(Ledgers.problem(with: "旅行", in: [other]), .duplicate)
        XCTAssertNil(Ledgers.problem(with: "旅行", in: [other], excluding: other.id))
        XCTAssertEqual(Ledgers.problem(with: "我的帳本", in: [other]), .duplicate)
        XCTAssertEqual(Ledgers.name(of: other.id, in: [other]), "旅行")
        XCTAssertEqual(Ledgers.name(of: UUID(), in: [other]), "我的帳本")
    }

    func testCSVSaysWhichLedger() {
        let other = Ledger(id: trip, name: "旅行", color: .blue, createdAt: epoch)
        let csv = CSVExport.make(
            transactions: [tx(1, "2026-11-01"), tx(2, "2026-11-02", ledger: trip)], book: CategoryBook(),
            ledgers: [other]
        )
        let lines = csv.components(separatedBy: "\r\n")
        XCTAssertTrue(lines[0].contains(",時區,帳本,編號,來源"))
        XCTAssertTrue(lines[1].contains(",Asia/Taipei,我的帳本,"))
        XCTAssertTrue(lines[2].contains(",Asia/Taipei,旅行,"))
    }

    func testSnapshotKeepsSavingsWithoutTheName() throws {
        let progress = SavingsProgress(target: 30000, endsOn: "2027-01-31", saved: 17600, hasIncome: true)
        let snapshot = WidgetSnapshot(today: "2026-11-26", transactions: [], budgets: [], fixed: [], savings: progress)
        let back = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(back.savings, progress)
        XCTAssertEqual(back.schemaVersion, 2)
    }
}

final class SavingsTests: XCTestCase {
    private func goal(_ target: Int = 30000, ledger: UUID? = nil) -> SavingsGoal {
        SavingsGoal(
            ledgerId: ledger, name: "日本", target: target, startsOn: "2026-11-10", endsOn: "2027-01-31",
            createdAt: epoch
        )
    }

    func testIncomeMinusExpenseFromTheStartDay() {
        let rows = [
            tx(50000, "2026-11-05", "薪水"),  // 開始以前，不算
            tx(40000, "2026-11-10", "薪水"),
            tx(12000, "2026-11-12", "居住"),
            tx(10400, "2026-11-20"),
            tx(999, "2026-11-20", ledger: trip),  // 別本，不算
        ]
        var deleted = tx(5000, "2026-11-21")
        deleted.deletedAt = epoch
        let p = Savings.progress(of: goal(), transactions: rows + [deleted])
        XCTAssertEqual(p.saved, 17600)
        XCTAssertEqual(p.remaining, 12400)
        XCTAssertTrue(p.hasIncome)
        XCTAssertEqual(p.monthsLeft(today: "2026-11-26"), 2)
        XCTAssertEqual(p.monthly(today: "2026-11-26"), 6200)
        XCTAssertEqual(SavingsText.headline(p, today: "2026-11-26"), "還差 NT$12,400。")
        XCTAssertEqual(SavingsText.plan(p, today: "2026-11-26"), "接下來 2 個月，一個月存 NT$6,200 就到。")
        XCTAssertEqual(SavingsText.short(p, today: "2026-11-26"), "還差 12,400")
        XCTAssertEqual(SavingsText.deadline(p), "1/31 前 NT$30,000")
        XCTAssertEqual(SavingsText.barTitle(p), "1/31 前存到 NT$30,000")
    }

    func testSpendingMoreThanEarningCountsAsZero() {
        let p = Savings.progress(of: goal(), transactions: [tx(1000, "2026-11-11", "薪水"), tx(3000, "2026-11-12")])
        XCTAssertEqual(p.saved, 0)
        XCTAssertEqual(p.fraction, 0)
    }

    func testNoIncomeYetSaysHowToStart() {
        let p = Savings.progress(of: goal(), transactions: [tx(300, "2026-11-12")])
        XCTAssertFalse(p.hasIncome)
        XCTAssertEqual(SavingsText.headline(p, today: "2026-11-26"), "記一筆收入就會開始算。")
        XCTAssertNil(SavingsText.plan(p, today: "2026-11-26"))
    }

    func testFixedExpensesAutoPostedCount() {
        let rent = FixedOrigin(itemId: UUID(), period: "2026-12", isYearly: false)
        let c = Categories.named("居住")
        let posted = Txn(
            fields: TxnFields(type: .expense, amount: 12000, occurredOn: "2026-12-05", categoryId: c.id),
            createdAt: epoch, timeZone: "Asia/Taipei", fixed: rent
        )
        let p = Savings.progress(of: goal(), transactions: [tx(40000, "2026-11-10", "薪水"), posted])
        XCTAssertEqual(p.saved, 28000)
    }

    func testReachedAndOver() {
        let done = Savings.progress(of: goal(1000), transactions: [tx(5000, "2026-11-11", "薪水")])
        XCTAssertTrue(done.isReached)
        XCTAssertEqual(done.saved, 5000)
        XCTAssertEqual(done.fraction, 1)
        XCTAssertNil(done.monthly(today: "2026-11-26"))
        XCTAssertEqual(SavingsText.headline(done, today: "2026-11-26"), "存到 NT$1,000 了。")
        XCTAssertNil(SavingsText.plan(done, today: "2026-11-26"))

        let short = Savings.progress(of: goal(), transactions: [tx(5000, "2026-11-11", "薪水")])
        XCTAssertTrue(short.isOver(today: "2027-02-01"))
        XCTAssertEqual(short.monthsLeft(today: "2027-02-01"), 0)
        XCTAssertEqual(SavingsText.headline(short, today: "2027-02-01"), "1/31 到了，存了 NT$5,000。")
        XCTAssertNil(SavingsText.plan(short, today: "2027-02-01"))
    }

    func testLastMonthAndPreview() {
        let p = SavingsProgress(target: 3000, endsOn: "2026-11-30", saved: 1000, hasIncome: true)
        XCTAssertEqual(p.monthsLeft(today: "2026-11-26"), 1)
        XCTAssertEqual(SavingsText.plan(p, today: "2026-11-26"), "這個月再存 NT$2,000 就到。")
        XCTAssertEqual(
            SavingsText.preview(target: 30000, today: "2026-11-26", endsOn: "2027-04-30"), "一個月存 NT$6,000 就到。"
        )
        XCTAssertEqual(Savings.monthlyPlan(target: 10, today: "2026-11-26", endsOn: "2027-01-31"), 5)
        XCTAssertEqual(Savings.monthlyPlan(target: 11, today: "2026-11-26", endsOn: "2027-01-31"), 6, "除不盡往上")
    }

    func testOneActiveGoalPerLedger() {
        var old = goal()
        old.deletedAt = epoch
        let main = SavingsGoal(
            ledgerId: Ledger.mainID, name: "", target: 1, startsOn: "2026-11-01", endsOn: "2026-12-01",
            createdAt: Date(timeIntervalSince1970: 9)
        )
        let other = goal(ledger: trip)
        XCTAssertEqual(Savings.active(in: [old, main, other], ledger: Ledger.mainID), main)
        XCTAssertEqual(Savings.active(in: [old, main, other], ledger: trip), other)
        XCTAssertNil(Savings.active(in: [old], ledger: Ledger.mainID))
    }

    func testCodableAndWords() throws {
        let g = goal().changed(name: "  沖繩  ", target: 20000, endsOn: "2027-03-31")
        XCTAssertEqual(g.name, "沖繩")
        XCTAssertEqual(g.startsOn, "2026-11-10")
        XCTAssertEqual(try JSONDecoder().decode(SavingsGoal.self, from: JSONEncoder().encode(g)), g)

        let states = [
            SavingsProgress(target: 30000, endsOn: "2027-01-31", saved: 17600, hasIncome: true),
            SavingsProgress(target: 30000, endsOn: "2027-01-31", saved: 0, hasIncome: false),
            SavingsProgress(target: 3000, endsOn: "2027-01-31", saved: 3000, hasIncome: true),
            SavingsProgress(target: 3000, endsOn: "2026-11-01", saved: 30, hasIncome: true),
            SavingsProgress(target: 3000, endsOn: "2026-11-30", saved: 30, hasIncome: true),
        ]
        var lines = [SavingsText.needsIncome, SavingsText.howItWorks, SavingsText.title]
        for p in states {
            lines += [
                SavingsText.headline(p, today: "2026-11-26"), SavingsText.short(p, today: "2026-11-26"),
                SavingsText.saved(p), SavingsText.deadline(p), SavingsText.barTitle(p),
                SavingsText.widgetDeadline(p), SavingsText.spoken(p, today: "2026-11-26"),
            ]
            if let plan = SavingsText.plan(p, today: "2026-11-26") { lines.append(plan) }
        }
        for line in lines {
            for word in AnalysisText.forbidden {
                XCTAssertFalse(line.contains(word), "「\(line)」裡有禁用字「\(word)」")
            }
        }
    }
}
