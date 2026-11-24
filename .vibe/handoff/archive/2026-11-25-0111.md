# Handoff: 白菜記帳改成手選金額分類的傳統記帳，分析頁照 analytics-book 重做

> 產出時間：2026-11-25 01:11
> 分支 build-mvp，PR #1，最後一個程式 commit 53b2627（已推）

## ✅ 這次完成了什麼

- 拿掉聚光燈引導、火柴人小白菜
- 拿掉 AI 解析、語音、問答、確認卡、離線佇列；App 不再連 Supabase，紀錄存手機（SwiftData）
- 三個分頁：記帳、分析、設定。記一筆＝按金額、點分類、記下；備註與「一次性」選填
- 分析頁四張卡（花了多少、花在哪一類、最大的三筆、最近幾個月）＋月初回顧＋每月預算
- `.analytics/` 設計檔（檔名帶 -暫定）、README 與 docs/ 改成現況
- CI 換 macos-26／Xcode 26；TestFlight secrets 剩四個
- commit 81b5bf6 的 CI 全綠：單元測試 33 個、畫面測試 12 個；27 張截圖逐張看過，挑出 5 個問題改在 53b2627

## 🚧 還沒做完 / 待決定

- 53b2627 的 CI 還沒看結果，改過的 5 個地方還沒看截圖
- `supabase/` 和 `eval/`：多米 2026-11-25 說先留著，不要刪、不要再問
- 多米要確認 `.analytics/` 的閘門 0、1、2（資料結構最好在上 TestFlight 前確認）；閘門 3、4 要真人
- 還沒做：TestFlight 上傳（secrets 沒給）、真機驗收、接 VeggieKit 與 domy-design、PR #1 併 main

## 📌 關鍵決策（這次定下來的）

- 資料只在手機、不連網路；自己定的小決定都在 docs/DECISIONS.md 第 27 到 36 點
- 分析：只跟自己平常比（前幾個月同期的最少到最多），空窗不當零，0 則通知，不用百分比、平均、紅色、連續天數
- 算法在 FinanceCore/Analysis.swift，改了要同步 .analytics/05

## 📂 下個會話最重要的檔案

- .analytics/閘門紀錄.md、.analytics/05-指標字典-暫定.md
- ios/AIFinance/Features/Entry/EntrySheet.swift、ios/AIFinance/Features/Analysis/AnalysisView.swift
- ios/AIFinanceUITests/AIFinanceUITests.swift
- docs/DECISIONS.md、docs/TESTFLIGHT_CHECKLIST.md

## ⏭️ 下一步從哪繼續

1. `gh run list -w CI -L 3` 找 53b2627（或之後）那次。沒有那一次的話，`gh workflow run CI --ref build-mvp` 或再推一次
2. 紅的話修；綠的話 `gh run download <編號> -n ios-screenshots`，看 06、11、12、14、23、26、27
3. 沒問題就向多米做收尾報告，問上面「待決定」

## 🧩 剩下的工作（工作包）

- [x] A：（45450035999 全綠）看 build-mvp 最新 push 的 CI（「次要文字加深…」那個 commit；排不到 Mac 機器就 gh run rerun）｜12 個畫面測試全過｜無｜無
- [x] B：（截圖看過，都對）看截圖確認 53b2627 的 5 個修正，加上這次 4 個（灰字加深、停用按鈕看得見、大字「這個月還沒過完」在條的下面、預算句「每天 NT$」一行放得下）｜看 02、06、11、12、14、22、23、26、27｜EntrySheet、AnalysisView｜依賴 A
- [ ] C：收尾報告給多米｜他收到待決定清單｜無｜依賴 B

- [x] D：整個 app 介面的 Design 畫布畫好了：https://claude.ai/artifact/443tfNbnKAAcyP23k5uAw7 （30 張，A 到 G 七區，照程式現況）。等多米看。四個小問題多米說要改，程式已改；同名合併沒做

- [x] E：畫布已同步四個小修

- [ ] F：UI 照準則改，程式寫完已推，等 CI（沒編譯過；沒把握處：CategoryPickerView 編輯模式常開、contentMargins、DomyPage、ContentUnavailableView）。對照表 .uiux/準則對照.md。待多米決定：slug baicai 與介紹、信箱、隱私權網址、Apple ID、刪一筆要不要先問、核心動作卡｜CI 綠、截圖看過｜ios/｜無
- [ ] H：分類與圖示加多（支出約 50、收入約 17，舊編號不變）、「常用分類」畫面可勾選、拖曳排序、自己取名（新增自訂、改內建名字圖示），存 SwiftData；分類查找改走 CategoryBook；找不到分類的紀錄不能漏算（多米 2026-11-25 分三則講的）｜CI 綠、截圖看過｜跟 F 同一個子代理在改｜F
- [ ] I：.analytics/02-04、05 補自訂分類（紀錄規格、邊界情況、改版紀錄）｜文件跟程式一致｜.analytics/｜H
- [ ] J：README、DECISIONS、TESTFLIGHT_CHECKLIST 補設定頁新列、常用分類、準則對照｜跟程式一致｜README.md、docs/｜F、H
- [ ] G：F 的 CI 綠了之後，畫布照新畫面更新｜同一個連結｜無｜依賴 F、E

## 🗑️ 雜訊（下次別重新討論）

- Bash 單一指令超過 8KB 會壞，這次撞三次，長內容一律 Write 成檔再跑
- 自己的型別叫 `Observation` 會跟系統模組撞名，已改 SpendingNote
