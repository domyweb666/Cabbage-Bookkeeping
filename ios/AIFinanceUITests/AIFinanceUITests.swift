import XCTest

/// 畫面測試：用示範後端（-demoBackend）把主要流程實際點過一遍，每一步截圖。
/// 開發機沒有 Mac，這是每次推送後確認畫面真的跑得起來的方法。
final class AIFinanceUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-demoBackend", "-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW"]
    }

    private func launch(seeded: Bool = false) {
        if seeded { app.launchArguments.append("-demoSeed") }
        app.launch()
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private var input: XCUIElement { app.textFields["inputField"].firstMatch.exists ? app.textFields["inputField"] : app.textViews["inputField"] }

    private func type(_ text: String) {
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        input.typeText(text)
    }

    private func send() {
        app.buttons["sendButton"].tap()
    }

    private func text(containing fragment: String) -> XCUIElement {
        app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", fragment)).firstMatch
    }

    /// 時間軸上的一列（整列是一個按鈕，標籤含品項、分類、金額）。
    private func row(_ fragments: String...) -> XCUIElement {
        let format = fragments.map { _ in "label CONTAINS %@" }.joined(separator: " AND ")
        return app.buttons.containing(NSPredicate(format: format, argumentArray: fragments)).firstMatch
    }

    /// 頂部的本月支出是否等於指定金額。
    private func waitForMonthTotal(_ amount: String, timeout: TimeInterval = 10) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS %@", "本月支出 \(amount)，")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: app.buttons["monthTotal"])
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    // MARK: - 首次開啟到第一筆入帳

    func testFirstLaunchRecordsFirstEntry() {
        launch()
        XCTAssertTrue(app.staticTexts["講一句就記好了"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["麥當勞 188"].exists)
        shot("01-首次開啟")

        // 點範例句會填進輸入列。
        app.buttons["麥當勞 188"].tap()
        XCTAssertEqual(input.value as? String, "麥當勞 188")
        send()

        XCTAssertTrue(app.staticTexts["已記錄 NT$188"].waitForExistence(timeout: 10))
        XCTAssertTrue(row("麥當勞", "NT$188").waitForExistence(timeout: 5))
        XCTAssertTrue(waitForMonthTotal("NT$188"), "頂部本月支出應該更新")
        shot("02-第一筆入帳")
    }

    // MARK: - 連續記多筆、復原

    func testMultipleEntriesAndUndo() {
        launch()
        type("早餐 65，午餐便當 120")
        send()
        XCTAssertTrue(app.staticTexts["已記錄 2 筆，共 NT$185"].waitForExistence(timeout: 10))

        type("昨天加油 500")
        send()
        XCTAssertTrue(app.staticTexts["已記錄 NT$500"].waitForExistence(timeout: 10))
        XCTAssertTrue(waitForMonthTotal("NT$685"))
        // 新的一筆進來時清單會捲動，等它停下來再找標題。
        XCTAssertTrue(app.staticTexts["昨天"].waitForExistence(timeout: 10))
        XCTAssertTrue(row("加油", "NT$500").waitForExistence(timeout: 5))
        shot("03-連續記帳")

        app.buttons["undoButton"].tap()
        XCTAssertTrue(waitForMonthTotal("NT$185"), "復原後本月支出回到 185")
        XCTAssertFalse(row("加油").exists)
        shot("04-復原之後")
    }

    // MARK: - 確認卡

    func testLargeAmountNeedsConfirmation() {
        launch()
        type("買電腦 45000")
        send()

        XCTAssertTrue(app.buttons["confirmAll"].waitForExistence(timeout: 10))
        XCTAssertTrue(text(containing: "金額超過 10,000").exists)
        shot("05-確認卡")

        app.buttons["confirmAll"].tap()
        XCTAssertTrue(app.staticTexts["已記錄 NT$45,000"].waitForExistence(timeout: 10))
        XCTAssertTrue(waitForMonthTotal("NT$45,000"))
        shot("06-確認後入帳")
    }

    func testCancelledConfirmationRecordsNothing() {
        launch()
        type("薪水 52000")
        send()
        XCTAssertTrue(app.buttons["confirmCancel"].waitForExistence(timeout: 10))
        XCTAssertTrue(text(containing: "收入需要確認").exists)
        app.buttons["confirmCancel"].tap()
        XCTAssertTrue(app.staticTexts["講一句就記好了"].waitForExistence(timeout: 10), "取消後什麼都沒記")
        XCTAssertTrue(waitForMonthTotal("NT$0"))
    }

    // MARK: - 看不懂、提問

    func testUnclearInputKeepsTextAndShowsHint() {
        launch()
        type("午餐花了一些錢")
        send()
        XCTAssertTrue(text(containing: "要記多少錢").waitForExistence(timeout: 10))
        XCTAssertEqual(input.value as? String, "午餐花了一些錢", "原話要留在輸入列")
        shot("07-看不懂的提示")
    }

    func testQuestionShowsAnswerWithEvidence() {
        launch(seeded: true)
        XCTAssertTrue(row("機車維修").waitForExistence(timeout: 10))
        shot("08-有資料的時間軸")

        type("這個月花多少？")
        send()
        XCTAssertTrue(text(containing: "這個月到目前支出共 NT$7,005，一共 6 筆").waitForExistence(timeout: 10))
        shot("09-回答卡")

        app.buttons["evidenceButton"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["依據"].waitForExistence(timeout: 10))
        shot("10-依據清單")
    }

    // MARK: - 編輯、概覽、設定

    func testEditTransaction() {
        launch(seeded: true)
        XCTAssertTrue(row("便當", "NT$120").waitForExistence(timeout: 10))
        row("便當", "NT$120").tap()

        let amount = app.textFields["editorAmount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 10))
        shot("11-編輯畫面")
        // 金額靠右對齊，點最右邊讓游標停在數字後面。
        amount.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        amount.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3) + "150")
        app.buttons["editorSave"].tap()

        XCTAssertTrue(row("便當", "NT$150").waitForExistence(timeout: 10))
        XCTAssertTrue(waitForMonthTotal("NT$7,035"))
    }

    func testOverviewAndSettings() {
        launch(seeded: true)
        XCTAssertTrue(app.buttons["monthTotal"].waitForExistence(timeout: 10))
        app.buttons["monthTotal"].tap()
        XCTAssertTrue(app.staticTexts["扣掉一次性支出後的日常開銷"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["支出分類"].exists)
        shot("12-本月概覽")
        app.buttons["完成"].tap()

        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.switches["autoCommitToggle"].waitForExistence(timeout: 10))
        shot("13-設定")
        app.swipeUp()
        XCTAssertTrue(app.buttons["隱私說明"].waitForExistence(timeout: 5))
        app.buttons["隱私說明"].tap()
        XCTAssertTrue(app.staticTexts["會傳給 AI 服務的內容"].waitForExistence(timeout: 10))
        shot("14-隱私說明")
    }

    func testDarkModeScreens() {
        // 先切成深色再開 App，截圖才會是深色的。
        XCUIDevice.shared.appearance = .dark
        addTeardownBlock { XCUIDevice.shared.appearance = .light }
        launch(seeded: true)
        XCTAssertTrue(row("便當").waitForExistence(timeout: 10))
        shot("15-深色-主畫面")

        type("買電腦 45000")
        send()
        XCTAssertTrue(app.buttons["confirmAll"].waitForExistence(timeout: 10))
        shot("16-深色-確認卡")
        app.buttons["confirmCancel"].tap()

        app.buttons["monthTotal"].tap()
        XCTAssertTrue(app.staticTexts["支出分類"].waitForExistence(timeout: 10))
        shot("17-深色-概覽")
    }
}
