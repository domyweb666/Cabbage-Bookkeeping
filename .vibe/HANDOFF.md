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

- [ ] A：看 53b2627 的 CI｜12 個畫面測試全過｜無｜無
- [ ] B：看截圖確認 5 個修正（灰色範圍條、狀態列不疊字、備註欄不貼鍵盤、大字不擠、預算句）｜截圖正確｜EntrySheet、AnalysisView｜依賴 A
- [ ] C：收尾報告給多米｜他收到待決定清單｜無｜依賴 B

- [ ] D：用 Claude Design 畫整個 app 介面（多米 2026-11-25 要的）｜一張畫布含全部畫面｜不改程式｜無。已派子代理畫，標題「白菜記帳介面」；沒看到畫布連結就用 Artifact list 找，找不到就重派

## 🗑️ 雜訊（下次別重新討論）

- Bash 單一指令超過 8KB 會壞，這次撞三次，長內容一律 Write 成檔再跑
- 自己的型別叫 `Observation` 會跟系統模組撞名，已改 SpendingNote
