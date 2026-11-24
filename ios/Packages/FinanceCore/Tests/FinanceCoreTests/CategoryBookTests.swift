@testable import FinanceCore
import XCTest

final class CategoryBookTests: XCTestCase {
    private let food = Categories.named("飲食")
    private let breakfast = Categories.named("早餐")
    private let catID = UUID(uuidString: "00000000-0000-4000-8000-00000000C001")!
    private let moment = Date(timeIntervalSince1970: 1_000)

    private func names(_ book: CategoryBook, _ kind: TxType = .expense) -> [String] {
        book.shown(of: kind).map(\.name)
    }

    /// 加了一個自訂分類「貓咪」的本子。
    private func withCat() -> CategoryBook {
        var book = CategoryBook()
        XCTAssertTrue(book.add(" 貓咪 ", icon: "pawprint.fill", kind: .expense, id: catID, at: moment))
        return book
    }

    private func row(_ amount: Int, _ categoryId: UUID, day: String = "2026-11-20", type: TxType = .expense) -> Txn {
        Txn(
            fields: TxnFields(type: type, amount: amount, occurredOn: day, categoryId: categoryId),
            createdAt: moment, timeZone: "Asia/Taipei"
        )
    }

    func testDefaultShowsTheOriginalOnes() {
        let book = CategoryBook()
        XCTAssertEqual(names(book), ["飲食", "交通", "購物", "日用", "居住", "娛樂", "醫療", "學習", "訂閱", "旅行", "人情", "其他"])
        XCTAssertEqual(names(book, .income), ["薪水", "獎金", "投資", "其他收入"])
        XCTAssertTrue(book.isStandard(.expense))
        XCTAssertFalse(book.hiddenGroups(.expense).flatMap(\.items).contains(food))
        XCTAssertTrue(book.hiddenGroups(.expense).flatMap(\.items).contains(breakfast))
    }

    func testShowAppendsAndHideKeepsAtLeastOne() {
        var book = CategoryBook()
        book.show(breakfast.id)
        book.show(breakfast.id)
        XCTAssertEqual(names(book).suffix(2), ["其他", "早餐"])
        XCTAssertFalse(book.isStandard(.expense))
        XCTAssertTrue(book.isStandard(.income), "動支出不影響收入")

        for category in book.shown(of: .income).dropFirst() { XCTAssertTrue(book.hide(category.id)) }
        XCTAssertFalse(book.hide(Categories.named("薪水").id), "最後一個拿不掉")
        XCTAssertEqual(names(book, .income), ["薪水"])
    }

    func testMoveMatchesOnMove() {
        var book = CategoryBook()
        book.move(.income, from: IndexSet(integer: 0), to: 3)
        XCTAssertEqual(names(book, .income), ["獎金", "投資", "薪水", "其他收入"])
        book.move(.income, from: IndexSet(integer: 3), to: 0)
        XCTAssertEqual(names(book, .income), ["其他收入", "獎金", "投資", "薪水"])
        book.move(.income, from: IndexSet([1, 3]), to: 1)
        XCTAssertEqual(names(book, .income), ["其他收入", "獎金", "薪水", "投資"])
        book.move(.income, from: IndexSet(integer: 99), to: 0)
        XCTAssertEqual(names(book, .income), ["其他收入", "獎金", "薪水", "投資"], "超出範圍就不動")
    }

    func testShiftStopsAtTheEnds() {
        var book = CategoryBook()
        XCTAssertFalse(book.shift(food.id, by: -1))
        XCTAssertTrue(book.shift(food.id, by: 1))
        XCTAssertEqual(names(book).prefix(2), ["交通", "飲食"])
        XCTAssertFalse(book.canShift(Categories.named("其他").id, by: 1))
        XCTAssertFalse(book.shift(breakfast.id, by: 1), "沒顯示的不能移")
    }

    func testEditMovesAtTheSameTime() {
        var book = CategoryBook()
        XCTAssertTrue(book.edit(food.id, name: "吃飯", icon: food.icon, moved: 2))
        XCTAssertEqual(names(book).prefix(3), ["交通", "購物", "吃飯"])
        XCTAssertTrue(book.edit(food.id, name: "飲食", icon: food.icon, moved: -99))
        XCTAssertEqual(book, CategoryBook(), "移到頭就停，改回原樣就跟沒動過一樣")
        XCTAssertFalse(book.edit(food.id, name: "交通", icon: food.icon, moved: 1))
        XCTAssertEqual(book, CategoryBook(), "名字不能用就整份不動")
    }

    func testNameRules() {
        let book = withCat()
        XCTAssertEqual(book.problem(with: "  ", kind: .expense), .empty)
        XCTAssertEqual(book.problem(with: "一二三四五六七八九", kind: .expense), .tooLong)
        XCTAssertNil(book.problem(with: "一二三四五六七八", kind: .expense))
        XCTAssertEqual(book.problem(with: " 飲食 ", kind: .expense), .duplicate)
        XCTAssertEqual(book.problem(with: "早餐", kind: .expense), .duplicate, "沒勾的內建分類也算還在用")
        XCTAssertEqual(book.problem(with: "貓咪", kind: .expense), .duplicate)
        XCTAssertNil(book.problem(with: "貓咪", kind: .income), "另一邊可以同名")
        XCTAssertNil(book.problem(with: "貓咪", kind: .expense, excluding: catID), "跟自己同名不算")
    }

    func testRenameBuiltInAndRestore() {
        var book = CategoryBook()
        XCTAssertTrue(book.edit(food.id, name: "吃飯", icon: "cart.fill"))
        XCTAssertEqual(book.find(food.id)?.name, "吃飯")
        XCTAssertEqual(book.find(food.id)?.icon, "cart.fill")
        XCTAssertEqual(book.find(food.id)?.number, 1, "編號不變")
        XCTAssertTrue(book.isRenamed(food.id))
        XCTAssertEqual(book.title(of: row(10, food.id)), "吃飯")
        XCTAssertFalse(book.edit(breakfast.id, name: "吃飯", icon: "cart.fill"), "不能跟改過的名字同名")
        XCTAssertEqual(book.problem(with: "飲食", kind: .expense), .duplicate, "原名留著，恢復時才不會撞名")

        XCTAssertTrue(book.edit(food.id, name: "飲食", icon: food.icon))
        XCTAssertFalse(book.isRenamed(food.id), "改回原樣就不留覆蓋")
        XCTAssertTrue(book.edit(food.id, name: "飯", icon: food.icon))
        book.restoreOriginal(food.id)
        XCTAssertEqual(book.find(food.id), food)
    }

    func testCustomCategoryLifecycle() throws {
        var book = withCat()
        XCTAssertEqual(names(book).last, "貓咪")
        XCTAssertTrue(book.isCustom(catID))
        XCTAssertTrue(book.edit(catID, name: "毛孩", icon: "hare.fill"))
        XCTAssertEqual(book.find(catID)?.name, "毛孩")

        XCTAssertFalse(book.delete(food.id, at: moment), "內建的不能刪")
        XCTAssertTrue(book.delete(catID, at: moment))
        XCTAssertFalse(names(book).contains("毛孩"))
        XCTAssertFalse(book.hiddenGroups(.expense).flatMap(\.items).contains { $0.id == catID })
        XCTAssertEqual(book.title(of: row(10, catID)), "毛孩", "記過的照樣看得到名字")
        XCTAssertNil(book.problem(with: "毛孩", kind: .expense), "刪掉的名字可以再用")
        book.show(catID)
        XCTAssertFalse(book.isShown(catID), "刪掉的不能再顯示")

        let back = try JSONDecoder().decode(CategoryBook.self, from: JSONEncoder().encode(book))
        XCTAssertEqual(back, book)
        XCTAssertEqual(back.schemaVersion, 1)
    }

    func testTheLastShownCustomCannotBeDeleted() {
        var book = withCat()
        for category in book.shown(of: .expense) where category.id != catID { XCTAssertTrue(book.hide(category.id)) }
        XCTAssertFalse(book.delete(catID, at: moment))
        XCTAssertFalse(book.isDeleted(catID))
    }

    func testEditingAnOldRecordShowsItsHiddenCategory() {
        var book = withCat()
        XCTAssertTrue(book.hide(food.id))
        XCTAssertFalse(book.choices(.expense).contains(food))
        XCTAssertEqual(book.choices(.expense, keeping: food.id).last, food)
        XCTAssertFalse(book.choices(.income, keeping: food.id).contains(food))
        XCTAssertTrue(book.delete(catID, at: moment))
        XCTAssertEqual(book.choices(.expense, keeping: catID).last?.name, "貓咪", "已刪掉的也要補上")
        XCTAssertNil(book.selection(food.id, kind: .expense))
        XCTAssertEqual(book.selection(food.id, kind: .expense, keeping: food.id), food.id)
    }

    func testResetKeepsCustomCategories() {
        var book = withCat()
        book.show(breakfast.id)
        XCTAssertTrue(book.shift(food.id, by: 1))
        XCTAssertTrue(book.edit(food.id, name: "吃飯", icon: food.icon))
        XCTAssertTrue(book.hide(Categories.named("獎金").id))
        book.reset(.expense)
        XCTAssertEqual(names(book), names(CategoryBook()))
        XCTAssertTrue(book.isStandard(.expense))
        XCTAssertFalse(book.isShown(catID))
        XCTAssertEqual(book.hiddenGroups(.expense).first?.items.map(\.name), ["貓咪"], "自己新增的還在，變成沒勾")
        XCTAssertFalse(book.isStandard(.income), "收入那邊不動")
    }

    func testCleanedDropsUnknownAndWrongIDs() throws {
        let good = food.id.uuidString
        let json = """
        {"schemaVersion":1,"customs":[],"overrides":[],
         "shownExpense":["\(good)","\(good)","\(UUID().uuidString)","\(Categories.named("薪水").id.uuidString)"],
         "shownIncome":["\(UUID().uuidString)"]}
        """
        let book = try JSONDecoder().decode(CategoryBook.self, from: Data(json.utf8)).cleaned()
        XCTAssertEqual(names(book), ["飲食"])
        XCTAssertEqual(names(book, .income), names(CategoryBook(), .income))
        XCTAssertEqual(CategoryBook().cleaned(), CategoryBook())
    }

    func testUnknownCategoryCountsAsOther() {
        let book = CategoryBook()
        let lost = row(300, UUID())
        XCTAssertEqual(book.title(of: lost), "其他")
        XCTAssertEqual(book.category(of: row(1, UUID(), type: .income)).name, "其他收入")

        let rows = [lost, row(200, Categories.named("其他").id), row(500, food.id)]
        let report = Analysis.report(
            month: "2026-11-01", today: "2026-11-25", transactions: rows, budgets: [], book: book, days: .taipei
        )
        XCTAssertEqual(report.expense, 1000)
        XCTAssertEqual(report.categories.reduce(0) { $0 + $1.total }, 1000, "不能漏算")
        XCTAssertEqual(report.categories.first { $0.category.name == "其他" }?.total, 500)
        XCTAssertEqual(
            Analysis.categoryTotal(
                Categories.named("其他").id, month: "2026-11-01", transactions: rows, book: book, days: .taipei
            ), 500
        )
        XCTAssertTrue(CSVExport.make(transactions: [lost], book: book).contains(",300,其他,"))
    }

    func testNamesFollowEverywhere() {
        var book = withCat()
        XCTAssertTrue(book.edit(catID, name: "毛孩", icon: "hare.fill"))
        let rows = [row(700, catID)]
        let report = Analysis.report(
            month: "2026-11-01", today: "2026-11-25", transactions: rows, budgets: [], book: book, days: .taipei
        )
        XCTAssertEqual(report.categories.map(\.category.name), ["毛孩"])
        XCTAssertTrue(CSVExport.make(transactions: rows, book: book).contains(",700,毛孩,"))
    }
}
