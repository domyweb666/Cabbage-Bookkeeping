# Handoff: QC-0015 畫面六項與效能三項已併 main（PR #6），功能提議等多米選

> 更新：2026-11-26｜分支 main（7b92f47，PR #6 併進來的）
> 舊的交接檔備份在 .vibe/handoff/archive/（上一版 HANDOFF-2026-11-25-1740.md）

## 2026-11-27 TestFlight 0.2.0（6）正式廣告

- 多米給了 AdMob 編號（App ID ca-app-pub-7643759977011671~4296546530、橫幅 ca-app-pub-7643759977011671/5226484829），寫進 ios/project.yml，CI 45934597130 全綠，TestFlight run 45940036643 上傳（6）。註冊步驟在 docs/AdMob註冊指南.md；上架後要連商店、放 app-ads.txt、Google 審過廣告才穩定。

## 2026-11-27 TestFlight 0.2.0（5）

- 多米說先出 TestFlight：entry-home 快轉併進 main（3cd434d，含 features-1126、整晚、記一筆主頁、廣告），run 45932556496 上傳成功。這版沒有正式 AdMob 編號，不出廣告。
- 畫布加 L 區（L1 記一筆沒廣告、L2 明細＋橫幅、L3 分析＋橫幅），沒在畫布上看過。
- 多米問 App ID：AdMob 不用等上架，新增 app 選「未上架」就拿得到；上架後再連商店，審過正式廣告才穩定。等他給編號。

## entry-home（2026-11-26 晚上）

- 多米：記一筆要自己一頁、開 app 就能記。分支 entry-home 從 overnight-20261126-1104 開出（含整晚的修正，都還沒併 features-1126／main）。
- 分頁改四個：設定－記一筆－明細－分析，預設停在記一筆。記下後留在原地清回空白，填了才有「清空」。明細頁拿掉「記一筆」按鈕，改一筆仍是彈出視窗。小工具、控制中心改成切到記一筆分頁。
- 坑：分頁內的 NavigationStack 拿不到分頁列讓出的空間，數字鍵最下排被蓋，用 aboveTabBar 墊；藏起來的分頁 XCUITest 還找得到（accessibilityHidden 沒用），記一筆切走時整頁換成 Color.clear。
- CI 45832457147 全綠，截圖 02、05 看過。代價：12 個分類時格子只露兩排半，要捲。
- 廣告（2026-11-27 多米說照推薦做）：明細、分析頁底部 AdMob 橫幅，只要非個人化（npa=1），不跳追蹤詢問。程式在 ios/AIFinance/Features/Ads/AdBanner.swift。Debug 用 Google 測試編號；Info.plist 的 GADApplicationIdentifier 現在是測試 App ID、BaicaiBannerUnitID 空的，所以正式版／TestFlight 不出廣告，等多米給 AdMob 編號（docs/上架指南.md 最後一節第 13、14 項）。畫面測試預設不放廣告，-showAds 才放（截圖 93、94）。隱私權政策、上架指南的隱私標籤已改。CI 45911240297 全綠。
- 坑：藏起來的分頁在開 app 時就先要廣告會拿不到，改成分頁看得到才要（isCurrentPage）。

## features-1126（2026-11-26 下午，進行中）

- qc-0015 已跟 perf-1126 一起由 PR #6 併進 main。多米回了 7 題（DECISIONS 第 54 點），說「開工」。分支 features-1126 從 main 0c8de9f 開出。
- 四個子代理同時在做，各管各的檔，規則在 C:\Users\fcharlie\AppData\Local\Claude-Data\claude_pzs8sxrjxfjjc\side-session-notes\local_31ff1b8c-970b-4e50-9921-17f1dbc77d10\features-1126-共同規則.md：
  - 畫布：A–J 區分頁列換新（只動畫布）
  - P：改一筆收據照片＋記一筆掃發票 QR（EntrySheet、project.yml 相機權限、FinanceCore InvoiceQR、ReceiptInvoiceTests）
  - A：分析頁四種看法切換（一句話／還能花／月曆／圓餅）（Features/Analysis、Analysis.swift、AnalysisModesTests）
  - L：多帳本（K4 K5 標題旁切換、設定帳本清單）＋存錢目標自動算三處（資料層、LedgerView、Settings、小工具、LedgersSavingsTests）
- 2026-11-26 傍晚：四個都回來了，整合完提交、推上去，第一次 CI 是 45740455021（還沒編過，第一次一定會有編譯錯，照 log 修）。畫布第 14 版。各子代理「沒把握編過的地方」與待補清單記在共同規則檔尾的「整合待辦」。
- 原本的步驟：全部回來後：補共用檔（AnalysisView 插 SavingsCard 等，看各回報）、提交指定檔名、`git push -u origin features-1126`、`gh workflow run CI --ref features-1126`、看截圖 60、70、80 起。
- 之後：iCloud 共享帳本＋成員（資料層換 CKSyncEngine 或 Core Data，要多米在後台開 iCloud）。出 TestFlight 要多米說。

## QC-0015（2026-11-26）

- 改好、在 qc-0015：#115 常用分類拿掉排序（拖曳、編輯畫面的前後移都拿掉）；#116 #117 常用分類改四欄格子，點一下放進拿出，長按編輯；#123 #124 分頁列改自畫懸浮膠囊（DesignSystem/TabBar.swift，照豆帳），順序設定－記帳－分析；#126 備註欄筆圖示＋看分類問一句（Words.Entry.notePrompt）。
- 另一個會話看效能提的兩點已修：分析頁沒選中不建（切過去才算、onAppear 更新今天）。三頁常駐後藏起來那頁的提示條會重複，用環境值 isCurrentPage 關掉。
- CI：45725691549 紅（復原按鈕兩顆），修完重跑 45729408238，結果看下面「下一步」。截圖看過：常用分類淺色、深色、大字，記帳頁、記一筆備註。
- 功能與設計：.uiux/QC-0015-功能提議.md（#118 發票、#119 照片成員、#120 多帳本、#121 共享、#122 存錢目標、#125 分析頁），畫布第 13 版 K 區（K1–K17）。檔尾 7 個問題等多米。
- qc-0015 CI 45729408238 全綠。效能三項（分支 perf-1126，從 qc-0015 開出）CI 45730143189 全綠：LedgerModel 的 sections 改成紀錄變了才重排、report／recentMonths／monthlyRange／home 算過就記住，資料一變 changed() 清掉；記帳頁總額改用 homeFigures。效能清單第 4、5 項（開 app 在主執行緒解全部 JSON、publish 每次多讀一次 widget.json）沒做。
- 2026-11-26 多米說一起併：PR #6（perf-1126 → main）已併，main 是 7b92f47。還沒出 TestFlight、還沒真機試。
- 下一步：要出版就 `gh workflow run testflight.yml --ref main`（要多米說）；多米選完方案檔 7 題再動功能。畫布 A–J 區的分頁列還是舊樣子。

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
