# 白菜記帳

按金額、點分類就記好一筆的 iOS 記帳 App。「白菜」取「百財」的諧音。

紀錄存在手機上，不用登入，App 也不連網路。設定頁有幾個連結會跳出去開 App Store 或瀏覽器，點了才會開。

## 現在的狀態

2026-11-25 改了方向。原本是講一句話由 AI 記帳、用問的查帳，現在改成手選金額與分類。聚光燈引導、小白菜、語音、Apple ID 綁定和雲端同步也一起拿掉。AI 版最後的 commit 是 `49444cc`，規格留在 [AI_FINANCE_SPEC.md](AI_FINANCE_SPEC.md)。

App 現在有三個分頁：

- 記帳：本月支出、還能花（沒訂預算時是「訂每月預算」）、每天的明細（最新在上）、底部一顆「記一筆」。
- 分析：這個月花了多少、花在哪一類、最大的三筆、最近幾個月。月初七天內，上個月的回顧會排在最上面。
- 設定，由上到下：
  - 記帳：常用分類、固定支出。
  - 一般：外觀（跟隨系統、淺色、深色）、觸覺回饋。
  - 資料：匯出資料、清除所有資料。
  - 關於：蔬菜家族的其他 app、隱私說明。
  - 頁尾：版本號（長按可以複製版本資訊），網站、Facebook、Instagram 的連結。

意見回饋、評分、分享、隱私權政策這幾列要等信箱、網址和 Apple ID 定了才會放。

App 外面還有主畫面小工具（還能花和「記一筆」）、鎖定畫面小工具，和 iOS 18 以上的控制中心按鈕。小工具沒有截圖，要上真機看。

## 固定支出和補大概的數字

固定支出分每月和每年，設一次，到那天打開 App 自動記一筆。還能花會先扣掉還沒到的每月固定，和每年一次的十二分之一。設定頁和「每月預算」都開得到。

連著超過 7 天沒記，分析頁會出現「補一個大概的數字」，打一個總數就好，記在「其他」，日期是那段最後一天，可以復原。

名字裡有「卡費」的支出分類，編輯畫面會提醒刷卡那天記過的不用再記。規則在 [docs/DECISIONS.md](docs/DECISIONS.md) 第 52 點。

## 常用分類

內建分類支出 67 個、收入 17 個。沒動過設定時，記一筆的畫面顯示最早的 16 個（支出 12、收入 4）。

記一筆的「分類」右邊有「編輯」，設定頁也有「常用分類」，兩邊開的是同一個畫面。可以做這些事：

- 勾選要顯示哪些，拖曳排順序。編輯分類的畫面也有「往前移一格」「往後移一格」。
- 新增自己的分類，或改內建分類的名字和圖示，名字 1 到 8 個字。
- 刪掉自己新增的分類。記過的紀錄還在，名字也照樣看得到。
- 恢復預設，只動目前切到的支出或收入那一邊。

取消勾選不會動到記過的紀錄，分析頁照樣列出那一類。

2026-11-25 畫面照 `E:\多米ios開發準則` 改過一輪，每一條的對照在 `.uiux/準則對照.md`。程式還沒上過 TestFlight，也沒在真機跑過，要準備的東西在 [docs/SETUP.md](docs/SETUP.md)。出 TestFlight 只能手動按，推到 `main` 不會出版。

| 想知道什麼 | 看哪裡 |
|---|---|
| 做了什麼、驗證到哪裡 | [docs/DEVELOPMENT_LOG.md](docs/DEVELOPMENT_LOG.md) |
| 自己決定了哪些做法 | [docs/DECISIONS.md](docs/DECISIONS.md) |
| 上了 TestFlight 要在手機上試什麼 | [docs/TESTFLIGHT_CHECKLIST.md](docs/TESTFLIGHT_CHECKLIST.md) |
| 分析頁為什麼這樣設計、數字怎麼算 | `.analytics/` |
| 畫面照準則改了哪些、哪些等多米定 | `.uiux/` |

## 目錄

```text
ios/
  AIFinance/              App 本體（SwiftUI）
    App/                  進入點、三個分頁、測試用的啟動參數
    Data/                 存進手機（SwiftData）、全部畫面共用的資料與動作、清掉外觀與觸覺的設定
    DesignSystem/         顏色、字級、間距、動作、震動、共用元件、畫面上的字（Words.swift）
    Features/Ledger/      記帳分頁
    Features/Entry/       記一筆、改一筆
    Features/Categories/  常用分類、新增與編輯分類
    Features/Fixed/       固定支出的清單、新增與修改
    Features/Analysis/    分析分頁、分類明細、每月預算、補大概的數字
    Features/Settings/    設定與隱私說明
    Resources/            圖示、隱私清單（PrivacyInfo.xcprivacy）
  BaicaiWidget/           小工具、鎖定畫面、控制中心按鈕
  Shared/                 App 和小工具共用的：快照、打開記一筆
  AIFinanceUITests/       畫面測試
  Packages/FinanceCore/   日期、金額、分類、固定支出、分析算法、分析頁文案、CSV，含單元測試
  project.yml             Xcode 專案設定（XcodeGen）
  ci/                     出 TestFlight 用的簽章與上傳腳本，不含任何金鑰
  .swiftlint.yml          擋裸數字、連網、直接震動的規則，CI 先跑不擋
.analytics/               分析頁的設計檔
.uiux/                    對多米 iOS 開發準則的對照、閘門紀錄
docs/                     設定指南、開發紀錄、決策、隱私文件草稿
design/                   App 圖示原稿（AppIcon.svg）、算顏色對比的 contrast.py
supabase/、eval/          AI 版的後端與評測，App 沒有用到
```

`supabase/` 和 `eval/` 多米 2026-11-25 說先留著。

## 相依的套件

App 用到一個外部套件：[VeggieKit](https://github.com/domyweb666/VeggieKit)，蔬菜家族設定頁的共用元件，公開 repo，版本鎖在 1.0.1，寫在 `ios/project.yml`。這個 App 給它的設定（名稱、slug、信箱、網址）在 `ios/AIFinance/DesignSystem/Veggie.swift`。

`DesignSystem/DomyTokens.swift` 是從 domy-design 1.6.0 整份複製的，不手改。

## 資料怎麼走

按「記下」之後，`LedgerModel` 把這筆交給 `LocalStore`，寫進手機上的 SwiftData。寫成功才會出現在畫面上；寫失敗就跳出提示，填好的內容留在畫面上。

分類的設定（顯示哪些、順序、改過的名字、自己新增的）整份存成 SwiftData 的一列，算法在 `FinanceCore/CategoryBook.swift`。一筆紀錄存的是分類的編號，名字和圖示都當場找，改名之後明細、分析和匯出一起變。編號找不到對應的分類時，算在「其他」（收入算在「其他收入」），金額照算。外觀和觸覺回饋由 VeggieKit 存在 UserDefaults。

刪除是先把那筆標成已刪除，明細、分析和匯出都不會算它，提示條上可以馬上復原。修改會把改之前的類型、金額、日期、分類和一次性留在同一筆裡。設定的「清除所有資料」才會把資料真的刪掉，分類、外觀、觸覺回饋也一起回到第一次打開的樣子。

小工具讀的是 App 放在 App Group 的一份快照（`Shared/WidgetBridge.swift`），裡面沒有備註，數字跟記帳頁同一套算法，換日換月自己算。按「清除所有資料」會一起清空。

首頁和分析頁的數字都是從紀錄當場算的，沒有另外存總數。算法在 `FinanceCore/Analysis.swift`，畫面上的句子在 `FinanceCore/AnalysisText.swift`，兩個檔各自對應 `.analytics/` 的設計檔，要改就一起改。

資料庫打不開時，App 會顯示「打不開紀錄」，不讓人繼續記。打得開、但紀錄或分類設定讀不出來時，記帳、修改、刪除、改分類都會停用。

## 在 Windows 上驗證

iOS 沒辦法在 Windows 上編譯，所以都靠 GitHub Actions。`build-mvp` 有開著的 PR，推上去就會自動跑 CI：FinanceCore 單元測試、SwiftLint（先當參考不擋）、編譯、把主要流程點一遍並截圖。

```bash
git push origin build-mvp
```

```bash
gh run list --workflow ci.yml --branch build-mvp --limit 3
```

```bash
gh run download <執行編號> -n ios-screenshots
```

截圖保留 14 天。畫面測試會把今天固定在 2026-11-25（月初回顧那個測試用 11-03），並用 `-demo fresh`、`-demo steady`、`-demo returning` 放進假資料，所以每次跑出來的數字都一樣。這幾個啟動參數列在 `ios/AIFinance/App/AppConfig.swift`，Debug 版才認，Release 版一律當沒看到。

`backend.yml` 只在併進 main 時有動到 `supabase/`、`eval/`，或手動執行時才跑。

## 改圖示

換掉 `design/AppIcon.svg` 之後，要重新產生 `ios/AIFinance/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png`：1024×1024、不能有透明通道。
