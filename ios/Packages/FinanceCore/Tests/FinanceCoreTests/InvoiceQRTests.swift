@testable import FinanceCore
import XCTest

final class InvoiceQRTests: XCTestCase {
    /// 自己編的左邊 QR 碼：民國 115 年 11 月 20 日，銷售額 100（0x64）、總計額 110（0x6E）。
    private let fixed = "AB12345678" + "1151120" + "1234" + "00000064" + "0000006E"
        + "00000000" + "12345678" + "ABCDEFGHIJKLMNOPQRSTUVWX"

    func testFixedPartIs77Long() {
        XCTAssertEqual(fixed.count, 77)
    }

    func testReadsFixedFields() throws {
        let invoice = try XCTUnwrap(InvoiceQR.parse(fixed))
        XCTAssertEqual(invoice.number, "AB12345678")
        XCTAssertEqual(invoice.day, "2026-11-20", "民國 115 年是 2026 年")
        XCTAssertEqual(invoice.randomCode, "1234")
        XCTAssertEqual(invoice.salesAmount, 100)
        XCTAssertEqual(invoice.total, 110, "總計額是十六進位")
        XCTAssertEqual(invoice.buyerId, "00000000")
        XCTAssertEqual(invoice.sellerId, "12345678")
        XCTAssertTrue(invoice.items.isEmpty, "沒有冒號後面那段就沒有品項")
        XCTAssertNil(invoice.firstItemName)
    }

    func testReadsItemsInUTF8() throws {
        let text = fixed + ":**********:2:2:1:拿鐵:1:65:可頌:1:45"
        let invoice = try XCTUnwrap(InvoiceQR.parse(text))
        XCTAssertEqual(invoice.items.count, 2)
        XCTAssertEqual(invoice.firstItemName, "拿鐵")
        XCTAssertEqual(invoice.items[1], InvoiceQR.Item(name: "可頌", quantity: "1", unitPrice: "45"))
    }

    func testReadsItemsInBase64() throws {
        let encoded = Data("便當:1:120".utf8).base64EncodedString()
        let invoice = try XCTUnwrap(InvoiceQR.parse(fixed + ":**********:1:1:2:" + encoded))
        XCTAssertEqual(invoice.firstItemName, "便當")
        XCTAssertEqual(invoice.items.first?.unitPrice, "120")
    }

    func testItemsAreOptional() throws {
        let invoice = try XCTUnwrap(InvoiceQR.parse(fixed + ":**********:0:0:1"))
        XCTAssertTrue(invoice.items.isEmpty)
        XCTAssertEqual(invoice.total, 110, "品項讀不出來，金額照樣有")
        XCTAssertEqual(InvoiceQR.parse(fixed + ":亂碼")?.total, 110)
    }

    func testIgnoresTheRightCode() {
        XCTAssertNil(InvoiceQR.parse("**:拿鐵:1:65:可頌:1:45"), "右邊那個只有品名")
    }

    func testRejectsBrokenCodes() {
        XCTAssertNil(InvoiceQR.parse(""))
        XCTAssertNil(InvoiceQR.parse("https://example.com"))
        XCTAssertNil(InvoiceQR.parse(String(fixed.dropLast())), "少一碼")
        XCTAssertNil(InvoiceQR.parse("ab" + fixed.dropFirst(2)), "字軌要大寫英文")
        XCTAssertNil(InvoiceQR.parse("AB1234567X" + fixed.dropFirst(10)), "號碼要數字")
        XCTAssertNil(InvoiceQR.parse(fixed.replacingOccurrences(of: "00000064", with: "0000006G")), "金額不是十六進位")
    }

    func testRejectsDaysThatDoNotExist() {
        XCTAssertNil(InvoiceQR.parse(fixed.replacingOccurrences(of: "1151120", with: "1151131")), "11 月沒有 31 日")
        XCTAssertNil(InvoiceQR.parse(fixed.replacingOccurrences(of: "1151120", with: "1151320")), "沒有 13 月")
        XCTAssertEqual(InvoiceQR.westernDay("1130229"), "2024-02-29", "閏年")
        XCTAssertNil(InvoiceQR.westernDay("1140229"))
    }

    func testTrimsWhitespace() {
        XCTAssertEqual(InvoiceQR.parse(" \(fixed)\n")?.number, "AB12345678")
    }
}
