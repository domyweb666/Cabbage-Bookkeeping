# 白菜記帳

按金額、點分類就記好一筆的 iOS 記帳 App。「白菜」取「百財」的諧音。

紀錄存在手機上，不用登入，App 也不連網路。

## 現在的狀態

2026-11-25 改了方向。原本是講一句話由 AI 記帳、用問的查帳，現在改成手選金額與分類。聚光燈引導、小白菜、語音、Apple ID 綁定和雲端同步也一起拿掉。AI 版最後的 commit 是 `49444cc`，規格留在 [AI_FINANCE_SPEC.md](AI_FINANCE_SPEC.md)。

App 現在有三個分頁：

- 記帳：本月支出、每天的明細（最新在上）、底部一顆「記一筆」。
- 分析：這個月花了多少、花在哪一類、最大的三筆、最近幾個月。月初七天內，上個月的回顧會排在最上面。
- 設定：匯出、清除所有資料、隱私說明、版本。

程式還沒上過 TestFlight，要準備的東西在 [docs/SETUP.md](docs/SETUP.md)。

| 想知道什麼 | 看哪裡 |
|---|---|
| 做了什麼、驗證到哪裡 | [docs/DEVELOPMENT_LOG.md](docs/DEVELOPMENT_LOG.md) |
| 自己決定了哪些做法 | [docs/DECISIONS.md](docs/DECISIONS.md) |
| 上了 TestFlight 要在手機上試什麼 | [docs/TESTFLIGHT_CHECKLIST.md](docs/TESTFLIGHT_CHECKLIST.md) |
| 分析頁為什麼這樣設計、數字怎麼算 | `.analytics/` |

## 目錄

```text
ios/
  AIFinance/              App 本體（SwiftUI）
    App/                  進入點、三個分頁、測試用的啟動參數
    Data/                 存進手機（SwiftData）、全部畫面共用的資料與動作
    DesignSystem/         顏色、字級、間距
    Features/Ledger/      記帳分頁
    Features/Entry/       記一筆、改一筆
    Features/Analysis/    分析分頁、分類明細、每月預算
    Features/Settings/    設定與隱私說明
  AIFinanceUITests/       畫面測試
  Packages/FinanceCore/   日期、金額、分析算法、文案、CSV，含單元測試
  project.yml             Xcode 專案設定（XcodeGen）
.analytics/               分析頁的設計檔
docs/                     設定指南、開發紀錄、決策、隱私文件草稿
design/AppIcon.svg        App 圖示原稿
supabase/、eval/          AI 版的後端與評測，App 沒有用到
```

`supabase/` 和 `eval/` 要不要刪還沒決定。

## 資料怎麼走

按「記下」之後，`LedgerModel` 把這筆交給 `LocalStore`，寫進手機上的 SwiftData。寫成功才會出現在畫面上；寫失敗就跳出提示，填好的內容留在畫面上。

刪除是先把那筆標成已刪除，明細、分析和匯出都不會算它，提示條上可以馬上復原。修改會把改之前的類型、金額、日期、分類和一次性留在同一筆裡。設定的「清除所有資料」才會把資料真的刪掉。

首頁和分析頁的數字都是從紀錄當場算的，沒有另外存總數。算法在 `FinanceCore/Analysis.swift`，畫面上的句子在 `FinanceCore/AnalysisText.swift`，兩個檔各自對應 `.analytics/` 的設計檔，要改就一起改。

資料庫打不開時，App 會顯示「打不開紀錄」，不讓人繼續記。

## 在 Windows 上驗證

iOS 沒辦法在 Windows 上編譯，所以都靠 GitHub Actions。`build-mvp` 有開著的 PR，推上去就會自動跑 CI：FinanceCore 單元測試、編譯、把主要流程點一遍並截圖。

```bash
git push origin build-mvp
```

```bash
gh run list --workflow ci.yml --branch build-mvp --limit 3
```

```bash
gh run download <執行編號> -n ios-screenshots
```

截圖保留 14 天。畫面測試會把今天固定在 2026-11-25（月初回顧那個測試用 11-03），並用 `-demo fresh`、`-demo steady`、`-demo returning` 放進假資料，所以每次跑出來的數字都一樣。這幾個啟動參數列在 `ios/AIFinance/App/AppConfig.swift`，平常打開 App 不會用到。

`backend.yml` 只在併進 main 時有動到 `supabase/`、`eval/`，或手動執行時才跑。

## 改圖示

換掉 `design/AppIcon.svg` 之後，要重新產生 `ios/AIFinance/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png`：1024×1024、不能有透明通道。
