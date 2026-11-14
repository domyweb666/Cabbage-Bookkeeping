# 白菜記帳

講一句就入帳、用問的查帳的 iOS 記帳 App。「白菜」取「百財」的諧音。

打「麥當勞 188」就記好一筆，打「這個月外食花多少？」就得到答案，兩件事用同一個輸入列。規格在 [AI_FINANCE_SPEC.md](AI_FINANCE_SPEC.md)。

## 現在的狀態

程式照規格 Phase 0 到 5 寫完了。後端在 CI 上有完整測試，iOS 在 CI 上編譯並用示範後端跑過畫面測試。還沒接上真實的 Supabase 專案、AI 金鑰與 TestFlight，要做的事列在 [docs/SETUP.md](docs/SETUP.md)。

各階段的測試結果在 [docs/DEVELOPMENT_LOG.md](docs/DEVELOPMENT_LOG.md)，我自己決定的做法在 [docs/DECISIONS.md](docs/DECISIONS.md)，上了 TestFlight 之後要實測的項目在 [docs/TESTFLIGHT_CHECKLIST.md](docs/TESTFLIGHT_CHECKLIST.md)。

## 目錄

```text
ios/
  AIFinance/              App 本體（SwiftUI）
  AIFinanceUITests/       畫面測試
  Packages/FinanceCore/   只依賴 Foundation 的邏輯與單元測試
  project.yml             Xcode 專案設定（XcodeGen）
supabase/
  migrations/             資料表、RLS、查帳函式
  functions/record        記帳與確認
  functions/ask           查帳
  functions/_shared       AI 介面、入帳規則、查詢工具
  tests/                  後端測試
eval/                     108 句解析評測
docs/                     設定指南、開發紀錄、決策、隱私文件草稿
design/AppIcon.svg        App 圖示原稿
```

## 資料怎麼走

一句話送到後端的 `record`。後端先把原話存起來，再請 AI 判斷這是記帳、提問，還是看不懂。

記帳的話，AI 只回一份結構化的結果，不碰資料庫。要不要直接入帳由程式規則決定：金額要能在原話裡找到、在門檻以內、日期在七天內、分類在清單裡、不是收入。全部符合才寫入，並且可以復原；有任何一條不符合，就把草稿和原因回給 App，讓使用者在確認卡上修改。

提問的話，AI 只能呼叫四個查詢工具，數字全部由資料庫算。回答裡的金額如果在查詢結果裡找不到，後端會把回答換成查詢結果的制式摘要。

## 在 Windows 上開發

後端的規則測試不需要資料庫：

```bash
npx deno test supabase/tests/rules_test.ts
```

完整的後端測試需要本機 Supabase（要先開 Docker Desktop）：

```bash
npx supabase start
```

```bash
npx supabase status -o env > .env.local
```

```bash
npx deno test --allow-net --allow-env --allow-read --env-file=.env.local supabase/tests
```

iOS 沒辦法在 Windows 上編譯。推到 GitHub 之後，Actions 會在 macOS 上跑 FinanceCore 的單元測試、編譯 App、用示範後端把主要流程點過一遍並截圖。截圖在該次執行的 Artifacts 裡，名稱是 `ios-screenshots`。

## 改圖示

換掉 `design/AppIcon.svg` 之後，要重新產生 `ios/AIFinance/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png`：1024×1024、不能有透明通道。
