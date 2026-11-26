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

    /// 等選中的動畫跑完再拍，不然格子是灰的。
    private func settledShot(_ name: String) {
        Thread.sleep(forTimeInterval: 1)
        shot(name)
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

    /// 空狀態的標題和說明可能被系統合成一句，所以用包含來找。
    private func shows(_ fragment: String, timeout: TimeInterval = 30) -> Bool {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", fragment))
            .firstMatch.waitForExistence(timeout: timeout)
    }

    /// 真的存進手機的測試：先把手機上的資料庫清空，跟別的測試不互相影響。
    private func launchOnDisk() {
        app.launchArguments.removeAll { $0 == "-memoryStore" }
        app.launchArguments.append("-wipeStore")
        app.launch()
        app.launchArguments.removeAll { $0 == "-wipeStore" }
    }

    /// 記一筆的分類卡捲到底。三排以外的格子要捲才會出現。
    private func scrollCategories() {
        let start = app.buttons["category_居住"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -200)))
    }

    /// 排在後面的分類格，看不到就先捲。
    private func lateCategory(_ name: String) -> XCUIElement {
        let cell = app.buttons["category_\(name)"]
        XCTAssertTrue(app.buttons["category_居住"].waitForExistence(timeout: 30))
        if !(cell.waitForExistence(timeout: 3) && cell.isHittable) { scrollCategories() }
        return cell
    }

    private func openCategoriesFromEntry() {
        scrollTo(app.buttons["editCategories"])
        app.buttons["editCategories"].tap()
        XCTAssertTrue(app.buttons["categoriesDone"].waitForExistence(timeout: 30))
    }

    private func openCategoriesFromSettings() {
        XCTAssertTrue(app.buttons["addButton"].waitForExistence(timeout: 30))
        app.buttons["tab_設定"].tap()
        XCTAssertTrue(app.buttons["categoriesRow"].waitForExistence(timeout: 30))
        app.buttons["categoriesRow"].tap()
        // CI 的模擬器忙的時候，剛換分頁的第一下會被吃掉（2026-11-25 碰過），還停在設定頁就再點一次。
        let first = app.buttons["pick_飲食"]
        if !first.waitForExistence(timeout: 10), app.buttons["categoriesRow"].exists {
            app.buttons["categoriesRow"].tap()
        }
        XCTAssertTrue(first.waitForExistence(timeout: 30))
    }

    private func clear(_ field: XCUIElement, characters: Int) {
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: characters))
    }

    private func openAnalysis() {
        app.buttons["tab_分析"].tap()
        XCTAssertTrue(any("analysisTotal").waitForExistence(timeout: 30))
    }

    /// 往下捲到看得到、按得到為止。
    private func scrollTo(_ element: XCUIElement) {
        for _ in 0..<6 where !(element.exists && element.isHittable) { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(element.exists, "捲到底還是找不到")
    }

    /// 從一個元件往下拖到螢幕底，跟把彈出的畫面滑掉一樣。
    private func dragDown(from element: XCUIElement) {
        let start = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95))
        start.press(forDuration: 0.1, thenDragTo: end)
    }

    private func disappears(_ element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    // MARK: - 記帳

    func testFirstEntryAndUndo() {
        launch()
        XCTAssertTrue(shows("還沒有紀錄"))
        shot("01-首次開啟")

        openEntry()
        XCTAssertFalse(app.buttons["entrySave"].isEnabled, "還沒填金額和分類不能記")
        shot("02-記一筆-空白")

        press("1", "8", "8")
        XCTAssertFalse(app.buttons["entrySave"].isEnabled, "還沒選分類不能記")
        app.buttons["category_飲食"].tap()
        XCTAssertTrue(app.buttons["entrySave"].isEnabled)
        settledShot("03-記一筆-填好")
        app.buttons["entrySave"].tap()

        XCTAssertTrue(wait("toastText", contains: "記好了。飲食這個月共 NT$188"))
        XCTAssertTrue(row("飲食", "NT$188").waitForExistence(timeout: 10))
        XCTAssertTrue(wait("monthTotal", contains: "NT$188"))
        shot("04-記好第一筆")

        app.buttons["undoButton"].tap()
        XCTAssertTrue(shows("還沒有紀錄"))
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

    /// 按一下刪一位，按住連刪。
    func testHoldBackspace() {
        launch()
        openEntry()
        press("1", "2", "3", "4", "5", "6", "7", "8")
        XCTAssertTrue(wait("entryAmount", contains: "12,345,678"))
        press("back")
        XCTAssertTrue(wait("entryAmount", contains: "1,234,567"))
        app.buttons["key_back"].press(forDuration: 4)
        XCTAssertEqual(any("entryAmount").label, "0", "按住要一路刪到零")
    }

    func testEditAndDelete() {
        launch(demo: "fresh")
        XCTAssertTrue(row("便當", "NT$120").waitForExistence(timeout: 30))
        shot("07-明細")
        row("便當", "NT$120").tap()
        XCTAssertTrue(app.buttons["entryDelete"].waitForExistence(timeout: 30))
        settledShot("08-修改")
        press("back", "back", "back")
        press("1", "5", "0")
        app.buttons["entrySave"].tap()
        XCTAssertTrue(row("便當", "NT$150").waitForExistence(timeout: 30))
        XCTAssertTrue(wait("monthTotal", contains: "NT$7,035"))

        row("便當", "NT$150").tap()
        XCTAssertTrue(app.buttons["entryDelete"].waitForExistence(timeout: 30))
        app.buttons["entryDelete"].tap()
        XCTAssertTrue(app.buttons["刪除這筆"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["刪除這筆"].firstMatch.tap()
        XCTAssertTrue(wait("toastText", contains: "已刪除「便當」"))
        XCTAssertTrue(wait("monthTotal", contains: "NT$6,885"))
        app.buttons["undoButton"].tap()
        XCTAssertTrue(wait("monthTotal", contains: "NT$7,035"), "復原後要回來")
    }

    /// 沒動過可以往下滑掉；勾了一次性就滑不掉，要按「取消」。
    func testTouchedEntryCannotBeSwipedAway() {
        launch()
        openEntry()
        dragDown(from: any("entryAmount"))
        XCTAssertTrue(disappears(app.buttons["entrySave"]), "沒動過可以滑掉")

        openEntry()
        scrollTo(app.buttons["entryOneOff"])
        app.buttons["entryOneOff"].tap()
        XCTAssertTrue(app.buttons["entryOneOff"].isSelected)
        dragDown(from: any("entryAmount"))
        XCTAssertFalse(disappears(app.buttons["entrySave"], timeout: 3), "勾了一次性就滑不掉")
        app.buttons["entryCancel"].tap()
        XCTAssertTrue(disappears(app.buttons["entrySave"]))
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
        XCTAssertTrue(wait("comparisonText", contains: "中間有幾天沒記，先不跟平常比。"))
        XCTAssertFalse(any("observationLink").exists)
        shot("15-分析-中間有空窗")
    }

    /// 補一個大概的數字，這個月就又能跟平常比；復原就回到空窗。
    func testFillTheGap() {
        launch(demo: "returning")
        openAnalysis()
        XCTAssertTrue(app.buttons["estimateButton"].waitForExistence(timeout: 30))
        app.buttons["estimateButton"].tap()
        let field = app.textFields["estimateAmount"]
        XCTAssertTrue(field.waitForExistence(timeout: 30))
        XCTAssertTrue(text(containing: "11/4 到 11/16 大概花了多少").exists)
        XCTAssertFalse(app.buttons["estimateSave"].isEnabled)
        field.tap()
        field.typeText("3000")
        shot("37-補大概的數字")
        app.buttons["estimateSave"].tap()
        XCTAssertTrue(wait("toastText", contains: "記好了。大概 NT$3,000"))
        XCTAssertTrue(wait("comparisonText", contains: "平常到 25 號是"))
        XCTAssertFalse(app.buttons["estimateButton"].exists)
        shot("38-分析-補完")
        app.buttons["tab_記帳"].tap()
        XCTAssertTrue(any("monthTotal").waitForExistence(timeout: 30))
        shot("39-明細-大概")
        app.buttons["undoButton"].firstMatch.tap()
        openAnalysis()
        XCTAssertTrue(wait("comparisonText", contains: "中間有幾天沒記"))
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
        XCTAssertTrue(wait("budgetButton", contains: "預算還剩 NT$2,995，每天 NT$499。"))
        app.buttons["tab_記帳"].tap()
        XCTAssertTrue(wait("monthTotal", contains: "還能花 NT$2,995"))
    }

    /// 沒訂預算時，記帳頁就有入口；訂預算的畫面連得到固定支出。
    func testBudgetFromLedger() {
        launch(demo: "fresh")
        XCTAssertTrue(app.buttons["homeBudgetButton"].waitForExistence(timeout: 30))
        shot("40-明細-還沒訂預算")
        app.buttons["homeBudgetButton"].tap()
        let field = app.textFields["budgetAmount"]
        XCTAssertTrue(field.waitForExistence(timeout: 30))
        field.tap()
        field.typeText("10000")
        shot("41-訂預算-固定支出那一列")
        scrollTo(app.buttons["budgetFixed"])
        app.buttons["budgetFixed"].tap()
        XCTAssertTrue(shows("還沒有固定支出"))
        shot("42-固定支出-空的")
        app.navigationBars["固定支出"].buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["budgetSave"].waitForExistence(timeout: 10))
        app.buttons["budgetSave"].tap()
        XCTAssertTrue(wait("monthTotal", contains: "還能花 NT$2,995"))
        XCTAssertFalse(app.buttons["homeBudgetButton"].exists)
    }

    // MARK: - 固定支出

    private func openFixed() {
        XCTAssertTrue(app.buttons["addButton"].waitForExistence(timeout: 30))
        app.buttons["tab_設定"].tap()
        XCTAssertTrue(app.buttons["fixedRow"].waitForExistence(timeout: 30))
        app.buttons["fixedRow"].tap()
        XCTAssertTrue(app.buttons["fixedAdd"].waitForExistence(timeout: 30))
    }

    func testPlannedFigures() {
        launch(demo: "planned")
        XCTAssertTrue(wait("toastText", contains: "記好了。停車月租 NT$1,500"), "到期的打開就記好")
        XCTAssertTrue(wait("monthTotal", contains: "NT$24,590"))
        XCTAssertTrue(wait("monthTotal", contains: "還能花 NT$8,511"))
        shot("43-明細-先扣固定支出")
        openAnalysis()
        XCTAssertTrue(wait("reservedText", contains: "已經先留 NT$2,899 給固定支出。"))
        shot("44-分析-先留固定支出")
    }

    /// 新增一項、今天到期的當場記；左滑刪掉可以復原。
    func testFixedAddDeleteAndUndo() {
        launch(demo: "planned")
        openFixed()
        XCTAssertTrue(app.buttons["fixed_車險"].waitForExistence(timeout: 30))
        shot("45-固定支出")

        app.buttons["fixedAdd"].tap()
        let amount = app.textFields["fixedAmount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 30))
        XCTAssertFalse(app.buttons["fixedSave"].isEnabled)
        amount.tap()
        amount.typeText("390")
        app.textFields["fixedName"].tap()
        app.textFields["fixedName"].typeText("影音\n")
        XCTAssertTrue(wait("fixedNext", contains: "下一次記在 2026 年 11 月 25 日。"))
        shot("46-新增固定支出")
        scrollTo(app.buttons["fixedCategory_訂閱"])
        app.buttons["fixedCategory_訂閱"].tap()
        settledShot("47-新增固定支出-填好")
        app.buttons["fixedSave"].tap()
        XCTAssertTrue(app.buttons["fixed_影音"].waitForExistence(timeout: 30))
        XCTAssertTrue(wait("toastText", contains: "記好了。影音 NT$390"))

        app.buttons["fixed_車險"].swipeLeft()
        let delete = app.buttons["刪除"].firstMatch
        if delete.waitForExistence(timeout: 3) { delete.tap() }
        XCTAssertTrue(wait("toastText", contains: "已刪除「車險」"))
        XCTAssertTrue(disappears(app.buttons["fixed_車險"]))
        app.buttons["undoButton"].firstMatch.tap()
        XCTAssertTrue(app.buttons["fixed_車險"].waitForExistence(timeout: 10), "復原後要回來")

        app.buttons["fixed_車險"].tap()
        XCTAssertTrue(app.textFields["fixedAmount"].waitForExistence(timeout: 30))
        settledShot("48-改固定支出-每年")
    }

    func testFixedSurvivesRelaunch() {
        launchOnDisk()
        openFixed()
        app.buttons["fixedAdd"].tap()
        let amount = app.textFields["fixedAmount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 30))
        amount.tap()
        amount.typeText("500")
        app.textFields["fixedName"].tap()
        app.textFields["fixedName"].typeText("水費\n")
        scrollTo(app.buttons["fixedCategory_居住"])
        app.buttons["fixedCategory_居住"].tap()
        app.buttons["fixedSave"].tap()
        XCTAssertTrue(app.buttons["fixed_水費"].waitForExistence(timeout: 30))

        app.terminate()
        app.launch()
        XCTAssertTrue(row("水費", "NT$500").waitForExistence(timeout: 30), "今天到期的記了一筆，重開還在")
        XCTAssertTrue(wait("monthTotal", contains: "NT$500"), "重開不會再記一次")
        openFixed()
        XCTAssertTrue(app.buttons["fixed_水費"].waitForExistence(timeout: 30))
    }

    private func shootFixed(_ prefix: String) {
        openFixed()
        XCTAssertTrue(app.buttons["fixedAdd"].exists)
        shot("\(prefix)-固定支出")
        app.buttons["fixedAdd"].tap()
        XCTAssertTrue(app.textFields["fixedAmount"].waitForExistence(timeout: 30))
        shot("\(prefix)-新增固定支出")
    }

    func testFixedInDark() {
        launch(demo: "planned", extra: ["-forceDark"])
        shootFixed("49-深色")
    }

    func testFixedInLargeText() {
        launch(
            demo: "planned", extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"]
        )
        shootFixed("50-大字")
    }

    // MARK: - 設定

    func testSettingsAndDeleteAll() {
        launch(demo: "fresh")
        XCTAssertTrue(app.buttons["addButton"].waitForExistence(timeout: 30))
        app.buttons["tab_設定"].tap()
        XCTAssertTrue(app.buttons["deleteAllButton"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.switches["觸覺回饋"].firstMatch.exists)
        XCTAssertTrue(app.buttons["familyRow"].exists)
        XCTAssertFalse(app.buttons["意見回饋"].exists, "信箱還沒定，不放這一列")
        shot("19-設定")

        any("appearanceRow").tap()
        XCTAssertTrue(app.buttons["深色"].waitForExistence(timeout: 10))
        app.buttons["深色"].tap()
        XCTAssertTrue(wait("appearanceRow", contains: "深色", timeout: 10))
        shot("28-設定-深色")
        any("appearanceRow").tap()
        XCTAssertTrue(app.buttons["跟隨系統"].waitForExistence(timeout: 10))
        app.buttons["跟隨系統"].tap()
        XCTAssertTrue(wait("appearanceRow", contains: "跟隨系統", timeout: 10))

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
        app.buttons["tab_記帳"].tap()
        XCTAssertTrue(shows("還沒有紀錄"))
    }

    /// 真的存進手機：整個關掉再開，紀錄還在。
    func testRecordsSurviveRelaunch() {
        launchOnDisk()
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

    // MARK: - 常用分類

    func testShowAndHideACategory() {
        launch()
        openEntry()
        press("8", "8")
        openCategoriesFromEntry()
        scrollTo(app.buttons["pick_早餐"])
        app.buttons["pick_早餐"].tap()
        app.buttons["categoriesDone"].tap()

        XCTAssertTrue(lateCategory("早餐").waitForExistence(timeout: 10), "勾了就要出現在格子")
        XCTAssertTrue(wait("entryAmount", contains: "88"), "按過的金額要還在")
        app.buttons["category_早餐"].tap()
        settledShot("29-記一筆-多一格")
        app.buttons["entrySave"].tap()
        XCTAssertTrue(row("早餐", "NT$88").waitForExistence(timeout: 30))

        openEntry()
        lateCategory("早餐").tap()
        press("5")
        XCTAssertTrue(app.buttons["entrySave"].isEnabled)
        openCategoriesFromEntry()
        scrollTo(app.buttons["pick_早餐"])
        app.buttons["pick_早餐"].tap()
        app.buttons["categoriesDone"].tap()
        XCTAssertTrue(app.buttons["category_居住"].waitForExistence(timeout: 10))
        scrollCategories()
        XCTAssertFalse(app.buttons["category_早餐"].exists, "取消勾選後格子就沒有")
        XCTAssertFalse(app.buttons["entrySave"].isEnabled, "選好的分類不顯示了，就當作還沒選")
        app.buttons["entryCancel"].tap()

        XCTAssertTrue(row("早餐", "NT$88").waitForExistence(timeout: 10), "記過的不受影響")
        row("早餐", "NT$88").tap()
        XCTAssertTrue(lateCategory("早餐").waitForExistence(timeout: 30), "改舊紀錄要看得到原本的分類")
        XCTAssertTrue(app.buttons["category_早餐"].isSelected)
    }

    /// 自己新增的分類：同名擋下、記一筆、重開還在、刪掉之後舊紀錄照樣有名字。
    func testCustomCategorySurvivesRelaunchAndDelete() {
        launchOnDisk()
        openEntry()
        openCategoriesFromEntry()
        scrollTo(app.buttons["newCategory"])
        app.buttons["newCategory"].tap()
        let name = app.textFields["categoryName"]
        XCTAssertTrue(name.waitForExistence(timeout: 30))
        XCTAssertFalse(app.buttons["categorySave"].isEnabled)
        name.tap()
        name.typeText("飲食")
        XCTAssertTrue(shows("已經有同名的分類", timeout: 10))
        XCTAssertFalse(app.buttons["categorySave"].isEnabled)
        shot("30-新增分類-同名")
        clear(name, characters: 2)
        name.typeText("貓咪")
        app.buttons["categorySave"].tap()
        XCTAssertTrue(app.buttons["categoriesDone"].waitForExistence(timeout: 10))
        app.buttons["categoriesDone"].tap()

        XCTAssertTrue(lateCategory("貓咪").waitForExistence(timeout: 10))
        press("1", "2", "0")
        app.buttons["category_貓咪"].tap()
        app.buttons["entrySave"].tap()
        XCTAssertTrue(row("貓咪", "NT$120").waitForExistence(timeout: 30))

        app.terminate()
        app.launch()
        XCTAssertTrue(row("貓咪", "NT$120").waitForExistence(timeout: 30), "重開之後紀錄和名字都要還在")
        openEntry()
        XCTAssertTrue(lateCategory("貓咪").waitForExistence(timeout: 10), "重開之後分類要還在")
        app.buttons["entryCancel"].tap()

        openCategoriesFromSettings()
        editCategory("貓咪")
        XCTAssertTrue(app.textFields["categoryName"].waitForExistence(timeout: 10))
        for _ in 0..<8 where !(app.buttons["categoryDelete"].exists && app.buttons["categoryDelete"].isHittable) { app.swipeUp() }
        app.buttons["categoryDelete"].tap()
        XCTAssertTrue(app.alerts.buttons["刪除這個分類"].waitForExistence(timeout: 10))
        app.alerts.buttons["刪除這個分類"].tap()
        app.buttons["tab_記帳"].tap()
        XCTAssertTrue(row("貓咪", "NT$120").waitForExistence(timeout: 10), "刪掉分類，記過的照樣看得到名字")
        openEntry()
        scrollCategories()
        XCTAssertFalse(app.buttons["category_貓咪"].exists)
    }

    /// 分類取名有「卡費」，提醒不要記兩次。
    func testCardBillHint() {
        launch()
        openEntry()
        openCategoriesFromEntry()
        scrollTo(app.buttons["newCategory"])
        app.buttons["newCategory"].tap()
        let name = app.textFields["categoryName"]
        XCTAssertTrue(name.waitForExistence(timeout: 30))
        name.tap()
        name.typeText("信用卡費")
        XCTAssertTrue(shows("繳卡費不用再記", timeout: 10))
        XCTAssertTrue(app.buttons["categorySave"].isEnabled, "提醒而已，照樣能存")
        shot("51-分類-卡費提示")
    }

    /// 改內建的名字，明細跟著變。常用分類不提供排序（QC-0015）。
    func testRename() {
        launch(demo: "fresh")
        openCategoriesFromSettings()
        editCategory("飲食")
        let name = app.textFields["categoryName"]
        XCTAssertTrue(name.waitForExistence(timeout: 30))
        name.tap()
        clear(name, characters: 2)
        name.typeText("吃飯")
        app.buttons["categorySave"].tap()
        XCTAssertTrue(app.buttons["pick_吃飯"].waitForExistence(timeout: 10))
        shot("31-常用分類-改過")

        app.buttons["tab_記帳"].tap()
        XCTAssertTrue(row("便當", "吃飯", "NT$120").waitForExistence(timeout: 10), "明細跟著改")
        openEntry()
        XCTAssertTrue(app.buttons["category_吃飯"].waitForExistence(timeout: 10))
        shot("32-記一筆-改過名字")
        app.buttons["entryCancel"].tap()
        openAnalysis()
        scrollTo(any("line_吃飯"))
    }

    /// 打到一半：往下滑、從左邊滑都走不掉，按「取消」才走，而且什麼都沒存。
    func testTouchedCategoryCannotBeSwipedAway() {
        launch()
        openEntry()
        openCategoriesFromEntry()
        scrollTo(app.buttons["newCategory"])
        app.buttons["newCategory"].tap()
        let name = app.textFields["categoryName"]
        XCTAssertTrue(name.waitForExistence(timeout: 30))
        name.tap()
        name.typeText("貓咪")
        shot("36-新增分類-打到一半")

        dragDown(from: app.navigationBars["新增分類"])
        XCTAssertFalse(disappears(name, timeout: 3), "打到一半不能往下滑掉")
        let left = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.3))
        left.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.3)))
        XCTAssertFalse(disappears(name, timeout: 3), "打到一半不能從左邊滑走")
        XCTAssertEqual(name.value as? String, "貓咪")

        app.buttons["categoryCancel"].tap()
        XCTAssertTrue(app.buttons["categoriesDone"].waitForExistence(timeout: 10))
        app.buttons["categoriesDone"].tap()
        XCTAssertTrue(app.buttons["category_居住"].waitForExistence(timeout: 10))
        scrollCategories()
        XCTAssertFalse(app.buttons["category_貓咪"].exists, "取消就不會新增")
    }

    /// 取消編輯：改的名字不算。
    func testCancelEditingKeepsEverything() {
        launch()
        openCategoriesFromSettings()
        editCategory("飲食")
        let name = app.textFields["categoryName"]
        XCTAssertTrue(name.waitForExistence(timeout: 30))
        name.tap()
        name.typeText("飯")
        app.buttons["categoryCancel"].tap()
        XCTAssertTrue(app.buttons["pick_飲食"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["pick_飲食飯"].exists)
    }

    /// 常用分類是格子：按住一格，選單裡的「編輯…」打開改名字的畫面。
    private func editCategory(_ name: String) {
        let cell = app.buttons["pick_\(name)"]
        scrollTo(cell)
        cell.press(forDuration: 1.0)
        let item = app.buttons["編輯\(name)"]
        XCTAssertTrue(item.waitForExistence(timeout: 10), "按住要跳出編輯選單")
        item.tap()
    }

    private func shootCategories(_ prefix: String) {
        openCategoriesFromSettings()
        shot("\(prefix)-常用分類-支出")
        editCategory("飲食")
        XCTAssertTrue(app.textFields["categoryName"].waitForExistence(timeout: 30))
        shot("\(prefix)-編輯分類")
        app.buttons["categoryCancel"].tap()
        XCTAssertTrue(app.buttons["pick_飲食"].waitForExistence(timeout: 10))
        app.segmentedControls.buttons["收入"].firstMatch.tap()
        XCTAssertTrue(app.buttons["pick_薪水"].waitForExistence(timeout: 10))
        shot("\(prefix)-常用分類-收入")
    }

    func testCategoriesInLight() {
        launch()
        shootCategories("33-淺色")
    }

    func testCategoriesInDark() {
        launch(extra: ["-forceDark"])
        shootCategories("34-深色")
    }

    func testCategoriesInLargeText() {
        launch(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"])
        shootCategories("35-大字")
    }

    // MARK: - 深色、大字

    func testDarkMode() {
        launch(demo: "steady", extra: ["-forceDark"])
        XCTAssertTrue(app.buttons["addButton"].waitForExistence(timeout: 30))
        shot("21-深色-明細")
        openEntry()
        app.buttons["category_飲食"].tap()
        settledShot("22-深色-記一筆")
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
