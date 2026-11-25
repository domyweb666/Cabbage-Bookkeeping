# Handoff: 固定支出、補大概的數字、小工具做完（spend-left，CI 綠），等多米建 App Group 與決定併不併

> 產出時間：2026-11-25 中午｜分支 spend-left（從 c8c07fc 開，沒開 PR）｜最後程式 commit 是「記一筆：點到露一半的分類格會捲進來」（已推）
> 舊的交接檔備份在 .vibe/handoff/archive/

## ✅ 這次完成了什麼

- 多米貼的記帳研究對照：`.uiux/研究對照-2026-11-25.md`。多米回「三件都做」（A 固定支出與還能花、B 補大概的數字、C 小工具與控制中心）
- FinanceCore：Fixed.swift、Home.swift、FixedTests.swift；畫面、資料層、小工具（BaicaiWidget、Shared）、簽章（兩個 App ID 兩張描述檔）、上架指南都寫完
- CI 45543399265 全綠：單元測試全過、29 個畫面測試全過、小工具有包進 app、App Group 沒警告。截圖 02、05、07、08、10、22、26、29、33、37 到 51 看過，都對（還能花 8,511 對得上單元測試）
- 層級改版（PR #3 已由另一個會話併 main，a53a8f7）截圖抓到的 7 個問題在同一包改了，看過新圖
- 之後只多一行：點到露一半的分類格捲進來（圖 29 的問題），CI 45546805188 全綠

## 🧩 剩下的工作（工作包）

- [x] M：CI 45546805188 全綠（29 個畫面測試），圖 29 的「早餐」整格看得到
- [x] O：畫布第 12 版已同步（改 33 張、新增 J 區 21 張；沒在畫布網頁上看過；沒畫：分析頁「一年一次…」那句、固定支出左滑刪除、新增選「每年」、新畫面的大字深色），README 已提交
- [x] Q：README、交接檔已提交，收尾報告已給多米，等他決定下面這些

## 🚧 待決定（都要多米）

- PR #4 已開（https://github.com/domyweb666/Cabbage-Bookkeeping/pull/4），Auto-fix 開著，等多米說併。多米 2026-11-25 下午說後台建好了（沒有用 API 核對過）。secret 有四個，還缺 APPLE_DIST_P12_BASE64、APPLE_DIST_P12_PASSWORD。這個交接檔 commit 在本機沒推，免得重跑 PR 的 CI。原本寫的是：併之前多米要先在後台做上架指南步驟 4：建 App Group `group.org.domyweb.baicai`；登記 `org.domyweb.baicai` 和 `org.domyweb.baicai.widget`，都勾 App Groups 並 Configure 選那個群組。出第一版前一定要做完
- `docs/不能改的字串.md` 過目（準則 7-4：Bundle ID、App Group、widget kind `org.domyweb.baicai.widget.left`、control kind `org.domyweb.baicai.control.add`、網址 `baicai://entry`）
- 準則 7-18 說鎖定畫面不放個人數值，這次照多米點的放了；鎖著時藏不藏要看真機與系統設定
- 研究對照第六段：第一個畫面的主角（建議「看」）、成功的感覺（多米自己寫）、候選表、付款方式（建議不做）、真人情境。閘門 1 沒過，A B C 是多米點名先做
- `.analytics/` 閘門 0、1、2；資料結構這次多了 fixed、estimate 兩欄，上 TestFlight 前確認
- 還有上架指南最後的 12 項與六個 secret

## 還沒驗證

- 小工具、鎖定畫面、控制中心沒有截圖，真機才看得到：控制中心冷啟動打不打得開記一筆、主畫面單色外觀、鎖定時遮不遮數字（都在 docs/TESTFLIGHT_CHECKLIST.md）
- 收入 4 類時分類白卡下面會空一塊（圖 05）：好處是切支出收入時日期不會跳，先維持
- 簽章那幾支 mjs 過 node --check，沒真的對 Apple 跑過

## 📌 關鍵決策

- 全寫在 docs/DECISIONS.md 第 52 點。重點：還能花 = 預算 − 這個月記的（年度不算）− 還沒到的每月固定 − 年度的十二分之一；自動記的不算有在記帳；資料庫不搬，小工具讀快照
- 多米定過、不要再問：左滑刪一筆不用先問；supabase/ 和 eval/ 先留著；TestFlight 手動簽章＋手動觸發

## 📂 下個會話最重要的檔案

- docs/DECISIONS.md（51、52）、docs/上架指南.md 步驟 4、.uiux/研究對照-2026-11-25.md
- ios/Packages/FinanceCore/Sources/FinanceCore/Fixed.swift、Home.swift
- ios/AIFinance/Features/Fixed/、ios/BaicaiWidget/LeftWidget.swift、ios/Shared/

## ⏭️ 下一步從哪繼續

1. `git status`、`gh run list -w CI -b spend-left -L 2`，照工作包 M、O、Q 做
2. 報告完等多米說併不併，併完出版用 `gh workflow run testflight.yml --ref main`

## 🗑️ 雜訊

- 自己的型別撞系統名：Observation、Timeline（小工具要寫 WidgetKit.Timeline）
- Bash 單一指令超過 8KB 會壞，長內容用 Write；提交指定檔名，不准 commit -a
- 推分支不會自己跑 CI，要 `gh workflow run CI --ref 分支`；同分支新的會取消舊的
