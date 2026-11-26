import XCTest

/// 多帳本與存錢的畫面測試：資料放記憶體，截圖編號從 80 起。
/// helper 照主測試檔抄（那邊是 private），改那邊不影響這裡。
final class LedgersSavingsTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [
            "-memoryStore", "-slowToast", "-today", "2026-11-25",
            "-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW",
        ]
    }

    private func launch(demo: String? = nil, extra: [String] = []) {
        if let demo { app.launchArguments += ["-demo", demo] }
        app.launchArguments += extra
        app.launch()
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func settledShot(_ name: String) {
        Thread.sleep(forTimeInterval: 1)
        shot(name)
    }

    private func row(_ fragments: String...) -> XCUIElement {
        let format = fragments.map { _ in "label CONTAINS %@" }.joined(separator: " AND ")
        return app.buttons.containing(NSPredicate(format: format, argumentArray: fragments)).firstMatch
    }

    private func any(_ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    private func wait(_ id: String, contains fragment: String, timeout: TimeInterval = 30) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS %@", fragment)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: any(id))
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func shows(_ fragment: String, timeout: TimeInterval = 30) -> Bool {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", fragment))
            .firstMatch.waitForExistence(timeout: timeout)
    }

    private func disappears(_ element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func press(_ keys: String...) {
        for key in keys { app.buttons["key_\(key)"].tap() }
    }

    /// 記一筆支出或收入。
    private func record(_ keys: [String], category: String, income: Bool = false) {
        XCTAssertTrue(app.buttons["addButton"].waitForExistence(timeout: 30))
        app.buttons["addButton"].tap()
        XCTAssertTrue(app.buttons["entrySave"].waitForExistence(timeout: 30))
        if income {
            app.buttons["收入"].tap()
            XCTAssertTrue(app.buttons["category_\(category)"].waitForExistence(timeout: 10))
        }
        for key in keys { press(key) }
        app.buttons["category_\(category)"].tap()
        app.buttons["entrySave"].tap()
    }

    /// 選單裡的一本（標題開頭是帳本名，後面可能接這個月的金額）。
    private func menuItem(_ name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
    }

    private func openLedgers() {
        XCTAssertTrue(app.buttons["addButton"].waitForExistence(timeout: 30))
        app.buttons["tab_設定"].tap()
        let entry = app.buttons["ledgersRow"]
        XCTAssertTrue(entry.waitForExistence(timeout: 30))
        entry.tap()
        // CI 的模擬器忙的時候，剛換分頁的第一下會被吃掉，還停在設定頁就再點一次。
        let add = app.buttons["ledgerAdd"]
        if !add.waitForExistence(timeout: 10), entry.exists { entry.tap() }
        XCTAssertTrue(add.waitForExistence(timeout: 30))
    }

    /// 在帳本清單新增一本，建好會換過去。
    private func addLedger(_ name: String, shotName: String? = nil) {
        app.buttons["ledgerAdd"].tap()
        let field = app.textFields["ledgerName"]
        XCTAssertTrue(field.waitForExistence(timeout: 30))
        XCTAssertFalse(app.buttons["ledgerSave"].isEnabled, "沒有名字不能建")
        field.tap()
        field.typeText(name)
        if let shotName { settledShot(shotName) }
        app.buttons["ledgerSave"].tap()
        XCTAssertTrue(any("ledgerRow_\(name)").waitForExistence(timeout: 30))
    }

    // MARK: - 多帳本

    /// 只有一本時記帳頁跟以前一樣；新增第二本、換過去、記的只在那本；換回來看不到。
    func testSecondLedgerKeepsItsOwnRecords() {
        launch()
        record(["1", "8", "8"], category: "飲食")
        XCTAssertTrue(row("飲食", "NT$188").waitForExistence(timeout: 30))
        XCTAssertFalse(app.buttons["ledgerChip"].exists, "只有一本時不出現換帳本")
        XCTAssertFalse(any("savingsBar").exists, "沒在存錢時沒有那一條")

        openLedgers()
        XCTAssertTrue(any("ledgerRow_我的帳本").waitForExistence(timeout: 30))
        shot("80-帳本清單-一本")
        addLedger("旅行", shotName: "81-新增帳本")
        XCTAssertTrue(any("ledgerRow_我的帳本").exists)
        shot("82-帳本清單-兩本")

        app.buttons["tab_記帳"].tap()
        XCTAssertTrue(app.buttons["ledgerChip"].waitForExistence(timeout: 30))
        XCTAssertTrue(wait("ledgerChip", contains: "旅行"))
        XCTAssertTrue(shows("還沒有紀錄"), "新的一本是空的")
        XCTAssertFalse(row("飲食", "NT$188").exists)
        shot("83-新帳本-空的")

        record(["5", "00"], category: "交通")
        XCTAssertTrue(row("交通", "NT$500").waitForExistence(timeout: 30))
        XCTAssertTrue(wait("monthTotal", contains: "NT$500"))
        XCTAssertFalse(row("飲食", "NT$188").exists, "別本的紀錄不出現")

        app.buttons["ledgerChip"].tap()
        let main = menuItem("我的帳本")
        XCTAssertTrue(main.waitForExistence(timeout: 10))
        settledShot("84-帳本選單")
        main.tap()
        XCTAssertTrue(wait("ledgerChip", contains: "我的帳本"))
        XCTAssertTrue(row("飲食", "NT$188").waitForExistence(timeout: 30))
        XCTAssertTrue(wait("monthTotal", contains: "NT$188"))
        XCTAssertTrue(disappears(row("交通", "NT$500")), "換回來看不到旅行那本的")
    }

    // MARK: - 存錢

    /// 從設定開始存錢；還沒有收入時說怎麼開始算；記一筆收入後記帳頁那一條跟著變。
    func testSavingsGoalFollowsIncome() {
        launch()
        XCTAssertTrue(app.buttons["addButton"].waitForExistence(timeout: 30))
        app.buttons["tab_設定"].tap()
        let entry = app.buttons["savingsRow"]
        XCTAssertTrue(entry.waitForExistence(timeout: 30))
        XCTAssertTrue(wait("savingsRow", contains: "還沒開始"))
        entry.tap()
        let start = any("savingsStart")
        if !start.waitForExistence(timeout: 10), entry.exists { entry.tap() }
        XCTAssertTrue(start.waitForExistence(timeout: 30))
        start.tap()

        let amount = app.textFields["savingsAmount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 30))
        XCTAssertFalse(app.buttons["savingsSave"].isEnabled, "沒有金額不能開始")
        amount.tap()
        amount.typeText("30000")
        XCTAssertTrue(wait("savingsPreview", contains: "就到"))
        shot("85-開始存錢")
        app.buttons["savingsSave"].tap()
        XCTAssertTrue(wait("savingsHeadline", contains: "記一筆收入就會開始算"))
        shot("86-存錢頁-還沒有收入")

        app.buttons["tab_記帳"].tap()
        XCTAssertTrue(wait("savingsBar", contains: "記一筆收入就會開始算"))

        record(["5", "00", "0"], category: "薪水", income: true)
        XCTAssertTrue(wait("savingsBar", contains: "還差 NT$25,000"), "記了收入，那一條跟著變")
        shot("87-記帳頁-存錢那一條")

        any("savingsBar").tap()
        XCTAssertTrue(wait("savingsHeadline", contains: "還差 NT$25,000"))
        XCTAssertTrue(any("savingsPlan").exists)
        shot("88-存錢頁")
        app.buttons["savingsDone"].tap()
        XCTAssertTrue(app.buttons["addButton"].waitForExistence(timeout: 30))
    }

    // MARK: - 深色、大字

    func testLedgerMenuInDark() {
        launch(demo: "steady", extra: ["-forceDark"])
        openLedgers()
        addLedger("工作室")
        shot("89-深色-帳本清單")
        app.buttons["tab_記帳"].tap()
        XCTAssertTrue(app.buttons["ledgerChip"].waitForExistence(timeout: 30))
        app.buttons["ledgerChip"].tap()
        XCTAssertTrue(menuItem("我的帳本").waitForExistence(timeout: 10))
        settledShot("90-深色-帳本選單")
    }

    func testLedgersInLargeText() {
        launch(demo: "steady", extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"])
        openLedgers()
        addLedger("旅行")
        shot("91-大字-帳本清單")
        app.buttons["tab_記帳"].tap()
        XCTAssertTrue(app.buttons["ledgerChip"].waitForExistence(timeout: 30))
        shot("92-大字-記帳頁換帳本")
    }
}
