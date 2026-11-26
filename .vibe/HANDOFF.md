# Handoff: QC-0015（芹查第 1 場 12 筆）畫面改好在分支 qc-0015，功能提議等多米選

> 更新：2026-11-26｜分支 qc-0015（沒併 main）
> 舊的交接檔備份在 .vibe/handoff/archive/（上一版 HANDOFF-2026-11-25-1740.md）

## QC-0015（2026-11-26）

- 改好、在 qc-0015：#115 常用分類拿掉排序（拖曳、編輯畫面的前後移都拿掉）；#116 #117 常用分類改四欄格子，點一下放進拿出，長按編輯；#123 #124 分頁列改自畫懸浮膠囊（DesignSystem/TabBar.swift，照豆帳），順序設定－記帳－分析；#126 備註欄筆圖示＋看分類問一句（Words.Entry.notePrompt）。
- 另一個會話看效能提的兩點已修：分析頁沒選中不建（切過去才算、onAppear 更新今天）。三頁常駐後藏起來那頁的提示條會重複，用環境值 isCurrentPage 關掉。
- CI：45725691549 紅（復原按鈕兩顆），修完重跑 45729408238，結果看下面「下一步」。截圖看過：常用分類淺色、深色、大字，記帳頁、記一筆備註。
- 功能與設計：.uiux/QC-0015-功能提議.md（#118 發票、#119 照片成員、#120 多帳本、#121 共享、#122 存錢目標、#125 分析頁），畫布第 13 版 K 區（K1–K17）。檔尾 7 個問題等多米。
- 下一步：確認 45729408238 綠；多米點頭才併 main（PR 還沒開）；多米選完方案再動功能。畫布 A–J 區的分頁列還是舊樣子。

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

- TestFlight 0.2.0（4）2026-11-25 17:38 上傳成功（run 45586389270，main fa41da1）。PR #5：手感審查四條、驗金鑰補換行，紀錄在 `.uiux/審查紀錄.md`、DECISIONS 53。真機請裝（4），手感全部沒上真機驗過
- 第一版 TestFlight 0.2.0（3）2026-11-25 16:58 上傳成功（run 45580430436，main 4c26c5c）。第一次失敗是 API 金鑰貼上時換行不見，多米重放後過了。多米要在 App Store Connect 建內部測試群組、加自己（上架指南步驟 8），然後照 docs/TESTFLIGHT_CHECKLIST.md 在真機試
- `docs/不能改的字串.md` 過目（準則 7-4：Bundle ID、App Group、widget kind `org.domyweb.baicai.widget.left`、control kind `org.domyweb.baicai.control.add`、網址 `baicai://entry`）
- 準則 7-18 說鎖定畫面不放個人數值，這次照多米點的放了；鎖著時藏不藏要看真機與系統設定
- 研究對照第六段：第一個畫面的主角（建議「看」）、成功的感覺（多米自己寫）、候選表、付款方式（建議不做）、真人情境。閘門 1 沒過，A B C 是多米點名先做
- `.analytics/` 閘門 0、1、2；資料結構這次多了 fixed、estimate 兩欄，上 TestFlight 前確認
- 還有上架指南最後的 12 項

## 還沒驗證

- 小工具、鎖定畫面、控制中心沒有截圖，真機才看得到：控制中心冷啟動打不打得開記一筆、主畫面單色外觀、鎖定時遮不遮數字（都在 docs/TESTFLIGHT_CHECKLIST.md）
- 收入 4 類時分類白卡下面會空一塊（圖 05）：好處是切支出收入時日期不會跳，先維持
- 簽章整條已實際跑過（兩個 App ID、兩張描述檔、App Group、上傳都過）

## 📌 關鍵決策

- 全寫在 docs/DECISIONS.md 第 52 點。重點：還能花 = 預算 − 這個月記的（年度不算）− 還沒到的每月固定 − 年度的十二分之一；自動記的不算有在記帳；資料庫不搬，小工具讀快照
- 多米定過、不要再問：左滑刪一筆不用先問；supabase/ 和 eval/ 先留著；TestFlight 手動簽章＋手動觸發

## 📂 下個會話最重要的檔案

- docs/DECISIONS.md（51、52）、docs/上架指南.md 步驟 4、.uiux/研究對照-2026-11-25.md
- ios/Packages/FinanceCore/Sources/FinanceCore/Fixed.swift、Home.swift
- ios/AIFinance/Features/Fixed/、ios/BaicaiWidget/LeftWidget.swift、ios/Shared/

## ⏭️ 下一步從哪繼續

1. 等多米的真機回饋再改。之後出版一樣 `gh workflow run testflight.yml --ref main`，build 號用 run number 會自己加
2. testCategoriesInLargeText 偶爾會紅（點「常用分類」那一下沒反應），測試已改成還停在設定頁就再點一次。再紅就當真的查。併完的 main CI 是 45586383755，看一下綠不綠
3. 大字時設定頁 VeggieRow 的圖示（觸覺回饋、固定支出）比圖示欄寬，會貼到字，還沒改

## 🗑️ 雜訊

- 自己的型別撞系統名：Observation、Timeline（小工具要寫 WidgetKit.Timeline）
- Bash 單一指令超過 8KB 會壞，長內容用 Write；提交指定檔名，不准 commit -a
- 推分支不會自己跑 CI，要 `gh workflow run CI --ref 分支`；同分支新的會取消舊的
