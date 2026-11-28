import XCTest

/// 畫面測試：資料放記憶體，把主要流程實際點過一遍，每一步截圖。
/// 開發機沒有 Mac，這是每次推送後確認畫面真的跑得起來的方法。
final class AIFinanceUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        // 固定今天是 11 月 25 日，分析頁的數字每次都一樣。
        // -noAutoEntry：開 app 不自動彈記一筆，每條測試從明細開始，要記帳就按明細頁底部那顆。
        // 自動彈出另外由 testLaunchOpensEntry 驗。
        app.launchArguments = [
            "-memoryStore", "-slowToast", "-today", "2026-11-25",
            "-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW",
            "-noAutoEntry",
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

    /// 系統原生分頁列的一顆（設定、記一筆、明細、分析）。
    private func tab(_ label: String) -> XCUIElement {
        app.tabBars.buttons[label]
    }

    /// 點分頁列的一頁。CI 的模擬器偶爾吃掉第一下，沒選中就再點，最多三次。
    private func showTab(_ label: String) {
        let button = tab(label)
        XCTAssertTrue(button.waitForExistence(timeout: 30))
        for _ in 0..<3 {
            button.tap()
            if button.isSelected { break }
            Thread.sleep(forTimeInterval: 1)
        }
    }

    /// 月份、總額卡、每天的明細在「明細」分頁。
    private func showLedger() {
        showTab("明細")
    }

    /// 記一筆是彈出視窗：點分頁列的「記一筆」，等「記下」出現。
    private func openEntry() {
        showLedger()
        let add = app.tabBars.buttons["記一筆"]
        XCTAssertTrue(add.waitForExistence(timeout: 30))
        add.tap()
        XCTAssertTrue(app.buttons["entrySave"].waitForExistence(timeout: 30))
    }

    /// 按「取消」關掉記一筆，什麼都不記。填了東西也是直接關（只有往下滑會被擋）。
    private func cancelEntry() {
        app.buttons["entryCancel"].tap()
        XCTAssertTrue(disappears(app.buttons["entrySave"]), "按取消要關掉記一筆")
    }

    /// 按「記下」之後視窗收起來，回到明細。
    private func entryClosed() {
        XCTAssertTrue(disappears(app.buttons["entrySave"]), "記下之後記一筆要收起來")
        XCTAssertTrue(app.buttons["monthTitle"].waitForExistence(timeout: 10), "收起來後回到明細")
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
        let anchor = app.buttons["category_居住"]
        // 居住已經捲出畫面，就是已經在底了。
        guard anchor.exists, anchor.isHittable else { return }
        let start = anchor.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
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
        showTab("設定")
        let row = app.buttons["categoriesRow"]
        XCTAssertTrue(row.waitForExistence(timeout: 30))
        // 大字時一列很高，「常用分類」可能被擠到分頁列後面，點下去其實點到分頁列（testCategoriesInLargeText 偶爾紅的原因）。
        // 先捲到按得到，再點；CI 的模擬器忙的時候剛換分頁的第一下也會被吃掉，還停在設定頁就再點，最多三次。
        let first = app.buttons["pick_飲食"]
        scrollTo(row)
        // 保險起見自己比位置：這一列的中間要在分頁列上面。
        let bar = app.tabBars.firstMatch
        for _ in 0..<4 where bar.exists && row.frame.midY > bar.frame.minY - 12 { app.swipeUp(velocity: .slow) }
        for _ in 0..<3 {
            if first.exists { break }
            // 已經推進常用分類頁、只是還在載入時，設定那一列還在但被蓋住、點不到，這時只等不點（2026-11-26 CI 45818119916）。
            guard waitHittable(row, timeout: 5) else { break }
            row.tap()
            if first.waitForExistence(timeout: 10) { break }
        }
        XCTAssertTrue(first.waitForExistence(timeout: 30))
    }

    private func waitHittable(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func clear(_ field: XCUIElement, characters: Int) {
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: characters))
    }

    private func openAnalysis() {
        showTab("分析")
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
        XCTAssertTrue(app.buttons["entryCancel"].exists, "彈出視窗要有取消")
        shot("02-記一筆-空白")

        press("1", "8", "8")
        XCTAssertFalse(app.buttons["entrySave"].isEnabled, "還沒選分類不能記")
        app.buttons["category_飲食"].tap()
        XCTAssertTrue(app.buttons["entrySave"].isEnabled)
        settledShot("03-記一筆-填好")
        app.buttons["entrySave"].tap()

        // 視窗收起來，提示條（含復原）出現在明細上。
        entryClosed()
        XCTAssertTrue(wait("toastText", contains: "記好了。飲食這個月共 NT$188"))
        XCTAssertTrue(row("飲食", "NT$188").waitForExistence(timeout: 10))
        XCTAssertTrue(wait("monthTotal", contains: "NT$188"))
        shot("04-記好第一筆")

        XCTAssertTrue(app.buttons["undoButton"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["undoButton"].firstMatch.tap()
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
        entryClosed()
        XCTAssertTrue(wait("toastText", contains: "記好了。薪水 NT$42,000"))
        XCTAssertTrue(wait("monthTotal", contains: "NT$0"), "收入不算進本月支出")

        // 再開一次是新的視窗，回到支出。
        openEntry()
        XCTAssertTrue(app.buttons["category_交通"].waitForExistence(timeout: 10), "新開的記一筆預設是支出")
        press("5", "00")
        app.buttons["key_back"].tap()
        app.buttons["category_交通"].tap()
        let note = app.textFields["entryNote"]
        note.tap()
        // 鍵盤升起來、還沒打字的樣子：備註欄要看得到、版面不跳（2026-11-27 改回彈出視窗的原因之一）。
        settledShot("98-記一筆-備註鍵盤")
        note.typeText("加油")
        shot("06-打備註")
        app.buttons["完成"].firstMatch.tap()
        XCTAssertTrue(app.buttons["entrySave"].waitForExistence(timeout: 10))
        app.buttons["entrySave"].tap()
        entryClosed()
        XCTAssertTrue(wait("toastText", contains: "記好了。交通"))
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
        showLedger()
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

    /// 記一筆：沒動過可以往下滑掉；勾了一次性就滑不掉，要按「取消」。
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
        cancelEntry()
    }

    /// 填了金額和分類再按「取消」：視窗關掉，什麼都沒記；再開是空白的。
    func testCancelEntryRecordsNothing() {
        launch()
        openEntry()
        press("4", "5")
        app.buttons["category_飲食"].tap()
        XCTAssertTrue(app.buttons["entrySave"].isEnabled)
        cancelEntry()
        XCTAssertTrue(shows("還沒有紀錄"), "取消不會記下任何東西")
        XCTAssertFalse(any("toastText").exists, "取消不出提示條")

        openEntry()
        XCTAssertEqual(any("entryAmount").label, "0", "再開是空白的")
        XCTAssertFalse(app.buttons["entrySave"].isEnabled)
    }

    /// 開 app 自己彈出記一筆（不帶 -noAutoEntry）；記下後收起來，提示條和復原在明細上。
    func testLaunchOpensEntry() {
        app.launchArguments.removeAll { $0 == "-noAutoEntry" }
        launch()
        XCTAssertTrue(app.buttons["entrySave"].waitForExistence(timeout: 30), "開 app 要自己彈出記一筆")
        XCTAssertTrue(app.buttons["entryCancel"].exists)
        settledShot("96-開app-自動彈出記一筆")

        press("6", "0")
        app.buttons["category_飲食"].tap()
        app.buttons["entrySave"].tap()
        entryClosed()
        XCTAssertTrue(tab("明細").isSelected, "收起來後停在明細")
        XCTAssertTrue(wait("toastText", contains: "記好了。飲食這個月共 NT$60"))
        XCTAssertTrue(row("飲食", "NT$60").waitForExistence(timeout: 10))
        app.buttons["undoButton"].firstMatch.tap()
        XCTAssertTrue(shows("還沒有紀錄"))
    }

    /// 帶 -noAutoEntry 開 app：停在明細，不彈記一筆；分頁列四格設定、記一筆、明細、分析。
    func testNoAutoEntryStaysOnLedger() {
        launch()
        XCTAssertTrue(app.buttons["monthTitle"].waitForExistence(timeout: 30))
        XCTAssertFalse(app.buttons["entrySave"].waitForExistence(timeout: 5), "帶 -noAutoEntry 不自動彈出")
        XCTAssertTrue(tab("明細").isSelected, "開 app 停在明細")
        XCTAssertEqual(app.tabBars.buttons.count, 4, "分頁列四格")
        XCTAssertTrue(tab("設定").exists)
        XCTAssertTrue(tab("記一筆").exists)
        XCTAssertTrue(tab("分析").exists)
        shot("99-分頁列-記一筆醒目")
    }

    /// 在設定頁點分頁列的記一筆：彈出視窗、分頁不切過去；記下後回到明細。
    func testEntryTabFromSettingsLandsOnLedger() {
        launch()
        showTab("設定")
        tab("記一筆").tap()
        XCTAssertTrue(app.buttons["entrySave"].waitForExistence(timeout: 30), "點記一筆要彈出視窗")
        XCTAssertFalse(app.tabBars.firstMatch.isHittable, "記一筆視窗蓋住分頁列")
        press("6", "0")
        app.buttons["category_飲食"].tap()
        app.buttons["entrySave"].tap()
        entryClosed()
        XCTAssertTrue(tab("明細").isSelected, "記下後切到明細")
        XCTAssertTrue(row("飲食", "NT$60").waitForExistence(timeout: 10))
    }

    /// 點明細左上的月份跳月曆，看得到某一天的每一筆和總共。
    func testMonthTitleOpensDayLookup() {
        launch(demo: "steady")
        let title = app.buttons["monthTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 30))
        title.tap()
        XCTAssertTrue(app.buttons["dayLookupDone"].waitForExistence(timeout: 30), "要跳出查某一天")
        XCTAssertTrue(wait("dayLookupHeader", contains: "筆"), "今天有紀錄，標題寫幾筆、花多少")
        shot("100-查某一天-今天")
        // 點月曆上的 24 號（標籤依語系不同，找含「24」的那顆）。
        let day24 = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "24")).firstMatch
        if day24.waitForExistence(timeout: 5) {
            day24.tap()
            XCTAssertTrue(wait("dayLookupHeader", contains: "筆"), "24 號也有紀錄")
            shot("101-查某一天-點24號")
        }
        app.buttons["dayLookupDone"].tap()
        XCTAssertTrue(disappears(app.buttons["dayLookupDone"]))
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
        showLedger()
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

        // 捲到最底：最後一張卡要整個露出來，不被分頁列和廣告位蓋住（2026-11-27 懸浮分頁列改回原生的原因）。
        for _ in 0..<4 { app.swipeUp() }
        Thread.sleep(forTimeInterval: 1)
        shot("97-分析-捲到底")
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
        showLedger()
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
        showLedger()
        XCTAssertTrue(wait("monthTotal", contains: "還能花 NT$2,995"))
    }

    /// 沒訂預算時，明細頁就有入口；訂預算的畫面連得到固定支出。
    func testBudgetFromLedger() {
        launch(demo: "fresh")
        showLedger()
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
        showTab("設定")
        XCTAssertTrue(app.buttons["fixedRow"].waitForExistence(timeout: 30))
        app.buttons["fixedRow"].tap()
        XCTAssertTrue(app.buttons["fixedAdd"].waitForExistence(timeout: 30))
    }

    func testPlannedFigures() {
        launch(demo: "planned")
        XCTAssertTrue(wait("toastText", contains: "記好了。停車月租 NT$1,500"), "到期的打開就記好")
        showLedger()
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
        showLedger()
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
        showTab("設定")
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
        showLedger()
        XCTAssertTrue(shows("還沒有紀錄"))
    }

    /// 真的存進手機：整個關掉再開，紀錄還在。
    func testRecordsSurviveRelaunch() {
        launchOnDisk()
        openEntry()
        press("7", "7")
        app.buttons["category_娛樂"].tap()
        app.buttons["entrySave"].tap()
        entryClosed()
        XCTAssertTrue(row("娛樂", "NT$77").waitForExistence(timeout: 30))

        app.terminate()
        app.launch()
        showLedger()
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
        entryClosed()
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
        // 金額還在，按「取消」放掉這筆，回明細看舊紀錄。
        cancelEntry()

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
        entryClosed()
        XCTAssertTrue(row("貓咪", "NT$120").waitForExistence(timeout: 30))

        app.terminate()
        app.launch()
        showLedger()
        XCTAssertTrue(row("貓咪", "NT$120").waitForExistence(timeout: 30), "重開之後紀錄和名字都要還在")
        openEntry()
        XCTAssertTrue(lateCategory("貓咪").waitForExistence(timeout: 10), "重開之後分類要還在")
        cancelEntry()

        openCategoriesFromSettings()
        editCategory("貓咪")
        XCTAssertTrue(app.textFields["categoryName"].waitForExistence(timeout: 10))
        for _ in 0..<8 where !(app.buttons["categoryDelete"].exists && app.buttons["categoryDelete"].isHittable) { app.swipeUp() }
        app.buttons["categoryDelete"].tap()
        XCTAssertTrue(app.alerts.buttons["刪除這個分類"].waitForExistence(timeout: 10))
        app.alerts.buttons["刪除這個分類"].tap()
        showLedger()
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

        showLedger()
        XCTAssertTrue(row("便當", "吃飯", "NT$120").waitForExistence(timeout: 10), "明細跟著改")
        openEntry()
        XCTAssertTrue(app.buttons["category_吃飯"].waitForExistence(timeout: 10))
        shot("32-記一筆-改過名字")
        cancelEntry()
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
        showLedger()
        XCTAssertTrue(any("monthTotal").waitForExistence(timeout: 30))
        shot("21-深色-明細")
        openEntry()
        app.buttons["category_飲食"].tap()
        settledShot("22-深色-記一筆")
        cancelEntry()
        openAnalysis()
        shot("23-深色-分析")
        app.swipeUp()
        shot("24-深色-分析-下")
    }

    func testLargeText() {
        launch(demo: "steady", extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"])
        showLedger()
        XCTAssertTrue(any("monthTotal").waitForExistence(timeout: 30))
        shot("25-大字-明細")
        openEntry()
        press("1", "2")
        shot("26-大字-記一筆")
        cancelEntry()
        openAnalysis()
        shot("27-大字-分析")
    }

    // MARK: - 廣告

    /// 帶 -showAds 才放廣告（Debug 版是 Google 的測試廣告）。CI 的網路不一定拿得到，拿不到就只拍沒有廣告的樣子，不算失敗。
    func testAdBannerOnLedgerAndAnalysis() {
        launch(demo: "steady", extra: ["-showAds"])
        showLedger()
        _ = any("adBanner").waitForExistence(timeout: 20)
        Thread.sleep(forTimeInterval: 5)
        shot("93-廣告-明細")
        // 記一筆不放廣告。視窗蓋在明細上，底下明細的廣告還在畫面樹裡，所以用截圖看，不用 exists 判斷。
        openEntry()
        Thread.sleep(forTimeInterval: 3)
        shot("95-廣告-記一筆沒有")
        cancelEntry()
        showTab("分析")
        Thread.sleep(forTimeInterval: 8)
        shot("94-廣告-分析")
    }
}
