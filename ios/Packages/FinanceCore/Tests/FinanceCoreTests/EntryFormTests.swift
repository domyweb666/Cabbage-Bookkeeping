@testable import FinanceCore
import XCTest

final class EntryFormTests: XCTestCase {
    private let food = Categories.named("飲食")
    private let today = "2026-11-25"

    private func form(
        type: TxType = .expense, amount: Int = 0, day: String = "2026-11-25",
        categoryId: UUID? = nil, note: String = "", isOneOff: Bool = false
    ) -> EntryForm {
        EntryForm(
            type: type, amount: amount, occurredOn: day, categoryId: categoryId, note: note, isOneOff: isOneOff
        )
    }

    private func row(_ categoryId: UUID, type: TxType = .expense) -> Txn {
        Txn(
            fields: TxnFields(type: type, amount: 120, occurredOn: today, categoryId: categoryId, note: "便當"),
            createdAt: Date(timeIntervalSince1970: 1_000), timeZone: "Asia/Taipei"
        )
    }

    func testEveryFieldCountsAsTouched() {
        let opened = EntryForm(today: today)
        XCTAssertEqual(form(), opened, "什麼都沒動")
        XCTAssertEqual(form(note: "  "), opened, "空白不算")
        XCTAssertNotEqual(form(amount: 1), opened)
        XCTAssertNotEqual(form(day: "2026-11-24"), opened, "改日期算動過")
        XCTAssertNotEqual(form(categoryId: food.id), opened)
        XCTAssertNotEqual(form(note: "便當"), opened)
        XCTAssertNotEqual(form(isOneOff: true), opened, "勾一次性算動過")
        XCTAssertNotEqual(form(type: .income), opened)
    }

    func testNeedsAmountAndCategory() {
        XCTAssertNil(form().fields)
        XCTAssertNil(form(amount: 100).fields, "沒選分類不能記")
        XCTAssertNil(form(categoryId: food.id).fields, "沒填金額不能記")
        let fields = form(amount: 100, categoryId: food.id, note: " 便當 ").fields
        XCTAssertEqual(fields, TxnFields(type: .expense, amount: 100, occurredOn: today, categoryId: food.id, note: "便當"))
        XCTAssertEqual(form(type: .income, amount: 1, categoryId: food.id, isOneOff: true).fields?.isOneOff, false)
        XCTAssertEqual(form(note: String(repeating: "長", count: 101)).note.count, 100)
    }

    func testOpeningAnOldRecord() {
        let old = row(food.id)
        let opened = EntryForm(editing: old, book: CategoryBook())
        XCTAssertEqual(opened.fields, old.fields)
        XCTAssertEqual(form(amount: 120, categoryId: food.id, note: "便當"), opened, "沒動過")
    }

    func testUnknownCategoryHasToBePickedFirst() {
        let lost = row(UUID())
        let opened = EntryForm(editing: lost, book: CategoryBook())
        XCTAssertNil(opened.categoryId)
        XCTAssertNil(opened.fields, "要先選一個分類才能記下")
        XCTAssertEqual(form(amount: 120, note: "便當"), opened, "打開沒動，不算動過")

        let wrongSide = EntryForm(editing: row(food.id, type: .income), book: CategoryBook())
        XCTAssertNil(wrongSide.fields, "支出的分類不能記在收入")
    }

    func testHiddenAndDeletedCategoriesStaySelected() {
        let moment = Date(timeIntervalSince1970: 1_000)
        let cat = UUID()
        var book = CategoryBook()
        XCTAssertTrue(book.add("貓咪", icon: "pawprint.fill", kind: .expense, id: cat, at: moment))
        XCTAssertTrue(book.delete(cat, at: moment))
        XCTAssertTrue(book.hide(food.id))
        XCTAssertEqual(EntryForm(editing: row(cat), book: book).fields?.categoryId, cat)
        XCTAssertEqual(EntryForm(editing: row(food.id), book: book).fields?.categoryId, food.id)
    }
}
