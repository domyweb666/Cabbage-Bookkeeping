import XCTest

/// 分析頁四種看法：一句話、還能花、月曆、圓餅。各截一張，月曆和圓餅再截大字。
/// 截圖編號 70 起（features-1126 分給分析頁的號碼）。
final class AnalysisModesTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        // 跟主測試檔一樣固定今天是 11 月 25 日，數字每次都一樣。
        app.launchArguments = [
            "-memoryStore", "-slowToast", "-today", "2026-11-25",
            "-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW",
            // 開 app 不自動彈記一筆，直接切到分析。
            "-noAutoEntry",
        ]
    }

    // MARK: - 小工具（照抄主測試檔）

    private func launch(demo: String, extra: [String] = []) {
        app.launchArguments += ["-demo", demo]
        app.launchArguments += extra
        app.launch()
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

    /// 系統原生分頁列的「分析」。CI 的模擬器偶爾吃掉第一下，沒選中就再點，最多三次。
    private func openAnalysis() {
        let tab = app.tabBars.buttons["分析"]
        XCTAssertTrue(tab.waitForExistence(timeout: 30))
        for _ in 0..<3 {
            tab.tap()
            if tab.isSelected { break }
            Thread.sleep(forTimeInterval: 1)
        }
        XCTAssertTrue(any("analysisTotal").waitForExistence(timeout: 30))
    }

    /// 標題下面那一排。
    private func choose(_ title: String) {
        // 找不到那一排的名字時，退回用字找按鈕。
        let control = app.segmentedControls["analysisMode"]
        let button = control.waitForExistence(timeout: 30) ? control.buttons[title] : app.buttons[title].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 30))
        button.tap()
    }

    /// 往下捲到看得到、按得到為止。
    private func scrollTo(_ element: XCUIElement) {
        for _ in 0..<6 where !(element.exists && element.isHittable) { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(element.exists, "捲到底還是找不到")
    }

    private var largeText: [String] {
        ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"]
    }

    // MARK: - 四種看法

    func testFourModes() {
        launch(demo: "steady")
        openAnalysis()

        // 預設是一句話：最上面一句結論，下面是平常範圍。
        XCTAssertTrue(wait("comparisonText", contains: "平常到 25 號是"))
        shot("70-看法-一句話")

        choose("還能花")
        XCTAssertTrue(any("budgetHero").waitForExistence(timeout: 30))
        XCTAssertTrue(any("budgetDays").waitForExistence(timeout: 10))
        XCTAssertTrue(any("dailyAnswer").waitForExistence(timeout: 10))
        shot("71-看法-還能花")

        choose("月曆")
        XCTAssertTrue(wait("calendarAnswer", contains: "最多的一天是"))
        shot("72-看法-月曆")

        // 點一天看那天的紀錄。
        let day = app.buttons["calendarDay_20"]
        scrollTo(day)
        day.tap()
        XCTAssertTrue(app.buttons["daySheetDone"].waitForExistence(timeout: 30))
        shot("76-看法-月曆-點一天")
        app.buttons["daySheetDone"].tap()

        choose("圓餅")
        XCTAssertTrue(wait("pieAnswer", contains: "NT$"))
        shot("73-看法-圓餅")

        // 點一列進那一類的明細。
        let food = app.buttons["slice_飲食"]
        scrollTo(food)
        food.tap()
        XCTAssertTrue(any("categoryDetailHeader").waitForExistence(timeout: 30))
        app.navigationBars.buttons.firstMatch.tap()

        // 切月份之後看法不變。
        app.buttons["previousMonth"].tap()
        XCTAssertTrue(any("pieAnswer").waitForExistence(timeout: 30))
    }

    // MARK: - 大字

    func testCalendarLargeText() {
        launch(demo: "steady", extra: largeText)
        openAnalysis()
        choose("月曆")
        XCTAssertTrue(any("calendarAnswer").waitForExistence(timeout: 30))
        shot("74-看法-月曆-大字")
    }

    func testPieLargeText() {
        launch(demo: "steady", extra: largeText)
        openAnalysis()
        choose("圓餅")
        XCTAssertTrue(any("pieAnswer").waitForExistence(timeout: 30))
        shot("75-看法-圓餅-大字")
    }
}
