import XCTest

/// 畫面測試：資料放記憶體，把主要流程實際點過一遍，每一步截圖。
/// 開發機沒有 Mac，這是每次推送後確認畫面真的跑得起來的方法。
final class AIFinanceUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        // 固定今天是 11 月 25 日，分析頁的數字每次都一樣。
        app.launchArguments = [
            "-memoryStore", "-slowToast", "-today", "2026-11-25",
            "-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW",
        ]
    }

    private func launch(demo: String? = nil, today: String? = nil, extra: [String] = []) {
        if let demo { app.launchArguments += ["-demo", demo] }
        if let today, let i = app.launchArguments.firstIndex(of: "-today") { app.launchArguments[i + 1] = today }
        app.launchArguments += extra
        app.launch()
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func text(containing fragment: String) -> XCUIElement {
        app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", fragment)).firstMatch
    }

    /// 明細上的一列（整列是一個按鈕，標籤含標題、分類、金額）。
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

    private func openEntry() {
        XCTAssertTrue(app.buttons["addButton"].waitForExistence(timeout: 30))
        app.buttons["addButton"].tap()
        XCTAssertTrue(app.buttons["entrySave"].waitForExistence(timeout: 30))
    }

    private func press(_ keys: String...) {
        for key in keys { app.buttons["key_\(key)"].tap() }
    }

    private func openAnalysis() {
        app.tabBars.buttons["分析"].tap()
        XCTAssertTrue(any("analysisTotal").waitForExistence(timeout: 30))
    }

    /// 往下捲到看得到、按得到為止。
    private func scrollTo(_ element: XCUIElement) {
        for _ in 0..<6 where !(element.exists && element.isHittable) { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(element.exists, "捲到底還是找不到")
    }

    // MARK: - 記帳

    func testFirstEntryAndUndo() {
        launch()
        XCTAssertTrue(app.staticTexts["還沒有紀錄"].waitForExistence(timeout: 30))
        shot("01-首次開啟")

        openEntry()
        XCTAssertFalse(app.buttons["entrySave"].isEnabled, "還沒填金額和分類不能記")
        shot("02-記一筆-空白")

        press("1", "8", "8")
        XCTAssertFalse(app.buttons["entrySave"].isEnabled, "還沒選分類不能記")
        app.buttons["category_飲食"].tap()
        XCTAssertTrue(app.buttons["entrySave"].isEnabled)
        shot("03-記一筆-填好")
        app.buttons["entrySave"].tap()

        XCTAssertTrue(wait("toastText", contains: "記好了。飲食這個月共 NT$188"))
        XCTAssertTrue(row("飲食", "NT$188").waitForExistence(timeout: 10))
        XCTAssertTrue(wait("monthTotal", contains: "NT$188"))
        shot("04-記好第一筆")

        app.buttons["undoButton"].tap()
        XCTAssertTrue(app.staticTexts["還沒有紀錄"].waitForExistence(timeout: 30))
    }

    func testIncomeAndNote() {
        launch()
        openEntry()
        app.buttons["收入"].tap()
        XCTAssertTrue(app.buttons["category_薪水"].waitForExistence(timeout: 10))
        press("4", "2", "00", "0")
        app.buttons["category_薪水"].tap()
        shot("05-記收入")
        app.buttons["entrySave"].tap()
        XCTAssertTrue(wait("toastText", contains: "記好了。薪水 NT$42,000"))
        XCTAssertTrue(wait("monthTotal", contains: "NT$0"), "收入不算進本月支出")

        openEntry()
        press("5", "00")
        app.buttons["key_back"].tap()
        app.buttons["category_交通"].tap()
        let note = app.textFields["entryNote"]
        note.tap()
        note.typeText("加油")
        shot("06-打備註")
        app.buttons["完成"].firstMatch.tap()
        XCTAssertTrue(app.buttons["entrySave"].waitForExistence(timeout: 10))
        app.buttons["entrySave"].tap()
        XCTAssertTrue(row("加油", "交通", "NT$50").waitForExistence(timeout: 10))
    }

    func testEditAndDelete() {
        launch(demo: "fresh")
        XCTAssertTrue(row("便當", "NT$120").waitForExistence(timeout: 30))
        shot("07-明細")
        row("便當", "NT$120").tap()
        XCTAssertTrue(app.buttons["entryDelete"].waitForExistence(timeout: 30))
        shot("08-修改")
        press("back", "back", "back")
        press("1", "5", "0")
        app.buttons["entrySave"].tap()
        XCTAssertTrue(row("便當", "NT$150").waitForExistence(timeout: 30))
        XCTAssertTrue(wait("monthTotal", contains: "NT$7,035"))

        row("便當", "NT$150").tap()
        XCTAssertTrue(app.buttons["entryDelete"].waitForExistence(timeout: 30))
        app.buttons["entryDelete"].tap()
        let confirm = app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "刪除", "entryDelete")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        confirm.tap()
        XCTAssertTrue(wait("toastText", contains: "已刪除「便當」"))
        XCTAssertTrue(wait("monthTotal", contains: "NT$6,885"))
        app.buttons["undoButton"].tap()
        XCTAssertTrue(wait("monthTotal", contains: "NT$7,035"), "復原後要回來")
    }

    // MARK: - 分析

    func testAnalysisWithoutEnoughData() {
        launch(demo: "fresh")
        openAnalysis()
        XCTAssertTrue(wait("comparisonText", contains: "再有 2 個記完整的月份"))
        XCTAssertFalse(any("observationLink").exists)
        shot("09-分析-資料不夠")
    }

    func testAnalysisWithObservation() {
        launch(demo: "steady")
        XCTAssertTrue(wait("monthTotal", contains: "NT$"))
        shot("10-明細-有預算")
        openAnalysis()
        XCTAssertTrue(wait("comparisonText", contains: "平常到 25 號是"))
        shot("11-分析-上半")

        scrollTo(any("observationLink"))
        XCTAssertTrue(wait("categoryAnswer", contains: "飲食到 25 號 NT$6,670"))
        shot("12-分析-分類")
        any("observationLink").tap()
        XCTAssertTrue(wait("categoryDetailHeader", contains: "37 筆，共 NT$6,670"))
        shot("13-分類明細")
        app.navigationBars.buttons.firstMatch.tap()

        scrollTo(any("biggestAnswer"))
        app.swipeUp()
        shot("14-分析-下半")
    }

    func testAnalysisAfterAGap() {
        launch(demo: "returning")
        openAnalysis()
        XCTAssertTrue(wait("comparisonText", contains: "中間有 13 天沒有紀錄，先不跟平常比。"))
        XCTAssertFalse(any("observationLink").exists)
        shot("15-分析-中間有空窗")
    }

    func testRecapAtTheStartOfTheMonth() {
        launch(demo: "steady", today: "2026-11-03")
        openAnalysis()
        XCTAssertTrue(any("recapCard").waitForExistence(timeout: 30))
        shot("16-分析-月初回顧")
        any("recapCard").tap()
        XCTAssertTrue(app.staticTexts["2026 年 10 月"].waitForExistence(timeout: 10))
        XCTAssertTrue(wait("comparisonText", contains: "平常一個月是"))
        shot("17-分析-上個月")
    }

    func testBudget() {
        launch(demo: "fresh")
        openAnalysis()
        any("budgetButton").tap()
        XCTAssertTrue(any("budgetHint").waitForExistence(timeout: 30))
        app.textFields["budgetAmount"].tap()
        app.textFields["budgetAmount"].typeText("10000")
        shot("18-訂預算")
        app.buttons["budgetSave"].tap()
        XCTAssertTrue(wait("budgetButton", contains: "預算還剩 NT$2,995，6 天，一天 NT$499。"))
        app.tabBars.buttons["記帳"].tap()
        XCTAssertTrue(wait("monthTotal", contains: "還能花 NT$2,995"))
    }

    // MARK: - 設定

    func testSettingsAndDeleteAll() {
        launch(demo: "fresh")
        XCTAssertTrue(app.buttons["addButton"].waitForExistence(timeout: 30))
        app.tabBars.buttons["設定"].tap()
        XCTAssertTrue(app.buttons["deleteAllButton"].waitForExistence(timeout: 30))
        shot("19-設定")
        app.buttons["隱私說明"].firstMatch.tap()
        XCTAssertTrue(text(containing: "都存在這支手機上").waitForExistence(timeout: 30))
        shot("20-隱私說明")
        app.navigationBars.buttons.firstMatch.tap()

        app.buttons["deleteAllButton"].tap()
        XCTAssertTrue(app.alerts.buttons["先匯出"].waitForExistence(timeout: 10))
        app.alerts.buttons["繼續"].tap()
        XCTAssertTrue(app.alerts.buttons["全部刪除"].waitForExistence(timeout: 10))
        app.alerts.buttons["全部刪除"].tap()
        XCTAssertTrue(app.alerts.buttons["好"].waitForExistence(timeout: 10))
        app.alerts.buttons["好"].tap()
        app.tabBars.buttons["記帳"].tap()
        XCTAssertTrue(app.staticTexts["還沒有紀錄"].waitForExistence(timeout: 30))
    }

    /// 真的存進手機：整個關掉再開，紀錄還在。
    func testRecordsSurviveRelaunch() {
        app.launchArguments.removeAll { $0 == "-memoryStore" }
        launch()
        openEntry()
        press("7", "7")
        app.buttons["category_娛樂"].tap()
        app.buttons["entrySave"].tap()
        XCTAssertTrue(row("娛樂", "NT$77").waitForExistence(timeout: 30))

        app.terminate()
        app.launch()
        XCTAssertTrue(row("娛樂", "NT$77").waitForExistence(timeout: 30), "重開之後紀錄要還在")
        XCTAssertTrue(wait("monthTotal", contains: "NT$77"))
    }

    // MARK: - 深色、大字

    func testDarkMode() {
        launch(demo: "steady", extra: ["-forceDark"])
        XCTAssertTrue(app.buttons["addButton"].waitForExistence(timeout: 30))
        shot("21-深色-明細")
        openEntry()
        app.buttons["category_飲食"].tap()
        shot("22-深色-記一筆")
        app.buttons["entryCancel"].tap()
        openAnalysis()
        shot("23-深色-分析")
        app.swipeUp()
        shot("24-深色-分析-下")
    }

    func testLargeText() {
        launch(demo: "steady", extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"])
        XCTAssertTrue(app.buttons["addButton"].waitForExistence(timeout: 30))
        shot("25-大字-明細")
        openEntry()
        press("1", "2")
        shot("26-大字-記一筆")
        app.buttons["entryCancel"].tap()
        openAnalysis()
        shot("27-大字-分析")
    }
}
