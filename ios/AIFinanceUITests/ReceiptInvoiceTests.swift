import XCTest

/// 掃發票和收據照片。模擬器沒有相機，掃發票用啟動參數 -invoiceQR 塞一串當作掃到的內容。
final class ReceiptInvoiceTests: XCTestCase {
    private var app: XCUIApplication!

    /// 自己編的左邊 QR 碼：民國 115 年 10 月 20 日（上個月），總計額 0x6E = 110，第一個品名拿鐵。
    private static let invoiceQR = "AB12345678" + "1151020" + "1234" + "00000064" + "0000006E"
        + "00000000" + "12345678" + "ABCDEFGHIJKLMNOPQRSTUVWX" + ":**********:1:1:1:拿鐵:1:110"

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        // 跟主測試檔一樣固定今天是 11 月 25 日。
        app.launchArguments = [
            "-memoryStore", "-slowToast", "-today", "2026-11-25",
            "-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW",
            // 開 app 不自動彈記一筆，從明細開始，要記帳就按底部那顆。
            "-noAutoEntry",
        ]
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func any(_ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    private func wait(_ id: String, contains fragment: String, timeout: TimeInterval = 30) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS %@", fragment)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: any(id))
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func row(_ fragments: String...) -> XCUIElement {
        let format = fragments.map { _ in "label CONTAINS %@" }.joined(separator: " AND ")
        return app.buttons.containing(NSPredicate(format: format, argumentArray: fragments)).firstMatch
    }

    /// 記一筆是彈出視窗：點分頁列的「記一筆」，等「記下」出現。
    private func openEntry() {
        showLedger()
        let add = app.tabBars.buttons["記一筆"]
        XCTAssertTrue(add.waitForExistence(timeout: 30))
        add.tap()
        XCTAssertTrue(app.buttons["entrySave"].waitForExistence(timeout: 30))
    }

    /// 點系統原生分頁列的「明細」，沒選中就再點，最多三次。
    private func showLedger() {
        let tab = app.tabBars.buttons["明細"]
        XCTAssertTrue(tab.waitForExistence(timeout: 30))
        for _ in 0..<3 {
            tab.tap()
            if tab.isSelected { break }
            Thread.sleep(forTimeInterval: 1)
        }
    }

    private func disappears(_ element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    /// 掃一張 → 金額、日期、備註填好 → 記下 → 再掃同一張 → 提醒記過了。
    func testScanInvoiceTwice() {
        app.launchArguments += ["-invoiceQR", Self.invoiceQR]
        app.launch()

        openEntry()
        XCTAssertFalse(any("receiptAdd").exists, "新記一筆不放收據照片")
        XCTAssertTrue(app.buttons["scanInvoice"].exists)
        shot("60-記一筆-掃發票按鈕")

        app.buttons["scanInvoice"].tap()
        XCTAssertTrue(wait("entryAmount", contains: "110"), "金額填總計額")
        XCTAssertEqual(app.textFields["entryNote"].value as? String, "拿鐵", "備註空的才放第一個品名")
        XCTAssertFalse(app.buttons["entrySave"].isEnabled, "分類不猜，還要自己選")
        app.buttons["category_飲食"].tap()
        Thread.sleep(forTimeInterval: 1)
        shot("61-記一筆-掃到發票")
        app.buttons["entrySave"].tap()
        XCTAssertTrue(disappears(app.buttons["entrySave"]), "記下之後記一筆收起來")

        // 提示條在明細上。日期填的是上個月，提示才不會講「這個月共」。
        XCTAssertTrue(wait("toastText", contains: "記好了。飲食 NT$110"), "日期要填發票那天")

        // 再開一次記一筆（新的、空白的），再掃同一張。
        openEntry()
        XCTAssertFalse(any("entryAmount").label.contains("110"), "新開的記一筆金額是空的")
        app.buttons["scanInvoice"].tap()
        let alert = app.alerts["這張發票記過了"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        shot("62-掃發票-記過了")
        XCTAssertFalse(any("entryAmount").label.contains("110"), "還沒選之前不填")

        alert.buttons["取消"].tap()
        XCTAssertTrue(disappears(alert))
        XCTAssertFalse(any("entryAmount").label.contains("110"), "按取消就不填")

        app.buttons["scanInvoice"].tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        alert.buttons["還是要記"].tap()
        XCTAssertTrue(wait("entryAmount", contains: "110"), "還是要記就照樣填")
    }

    /// 改一筆才有收據照片那一排；記一筆沒有。
    func testReceiptStripInEdit() {
        app.launchArguments += ["-demo", "fresh"]
        app.launch()

        showLedger()
        XCTAssertTrue(row("便當", "NT$120").waitForExistence(timeout: 30))
        row("便當", "NT$120").tap()
        XCTAssertTrue(app.buttons["entryDelete"].waitForExistence(timeout: 30))
        XCTAssertFalse(app.buttons["scanInvoice"].exists, "改一筆不放掃發票")
        XCTAssertTrue(any("receiptAdd").waitForExistence(timeout: 10))
        XCTAssertFalse(any("receipt_1").exists, "還沒有照片")
        Thread.sleep(forTimeInterval: 1)
        shot("63-改一筆-收據照片空的")

        // 模擬器沒有相機，一按就是系統的選照片畫面。
        any("receiptAdd").tap()
        Thread.sleep(forTimeInterval: 3)
        shot("64-改一筆-選收據照片")
    }
}
