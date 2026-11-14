# 接上真實服務要做的事

程式都寫好了，現在 App 跑的是示範模式。要變成真的能用，需要下面四組設定。每一步做完都可以單獨驗證。

金鑰一律不要貼進程式碼或聊天視窗，照下面的指令放到 Supabase secrets 或 GitHub secrets。

## 1. Supabase 專案

到 Supabase 開一個專案（區域選東京或新加坡），記下 Project ref（網址裡 `https://<ref>.supabase.co` 的那段）。

在本機專案根目錄執行：

```bash
npx supabase login
```

```bash
npx supabase link --project-ref <你的 ref>
```

```bash
npx supabase db push
```

`db push` 會建好六張表、RLS、查帳函式和 12 個系統分類。

接著到 Supabase 後台 Authentication 的登入方式設定：

- 打開 Anonymous sign-ins。
- 打開 Manual linking（綁定 Apple ID 要用）。
- Apple 這個 provider 先不用開，等第 4 步。

## 2. AI 金鑰與 Edge Function

到 Anthropic Console 產生一把 API key，然後：

```bash
npx supabase secrets set AI_PROVIDER=anthropic AI_API_KEY=<你的金鑰> AI_MODEL_RECORD=claude-haiku-5-5 AI_MODEL_ASK=claude-sonnet-5-5 AUTO_COMMIT_MAX=10000 DAILY_LIMIT_RECORD=100 DAILY_LIMIT_ASK=30
```

```bash
npx supabase functions deploy record
```

```bash
npx supabase functions deploy ask
```

`SUPABASE_URL`、`SUPABASE_ANON_KEY`、`SUPABASE_SERVICE_ROLE_KEY` 這三個 Supabase 會自動提供給 Edge Function，不用設。

驗證：設好環境變數後跑冒煙測試，八項都打勾就代表雲端的記帳與查帳是通的。

```bash
SUPABASE_URL=https://<ref>.supabase.co SUPABASE_ANON_KEY=<anon key> npx deno run --allow-net --allow-env supabase/tests/smoke.ts
```

冒煙測試裡「ask：數字來自資料庫」那一項寫死了假供應商的回答格式，接上真實模型後這項可能不過，其他七項要過。

### 量真實模型的正確率

```bash
AI_PROVIDER=anthropic AI_API_KEY=<你的金鑰> AI_MODEL_RECORD=claude-haiku-5-5 npx deno run --allow-env --allow-read --allow-write --allow-net eval/run_eval.ts
```

會對 108 句各發一次請求，印出規格 1.5 的五項指標和沒過的句子。這一步會花 API 費用，金額很小。

## 3. GitHub secrets（TestFlight 用）

到 repo 的 Settings → Secrets and variables → Actions，加這六個：

| 名稱 | 內容 |
|---|---|
| `SUPABASE_HOST` | `<ref>.supabase.co`，不要帶 `https://` |
| `SUPABASE_ANON_KEY` | Supabase 的 anon key |
| `APPLE_TEAM_ID` | Apple Developer 的 Team ID（10 碼） |
| `ASC_KEY_ID` | App Store Connect API Key 的 Key ID |
| `ASC_ISSUER_ID` | 同一把金鑰的 Issuer ID |
| `ASC_KEY_P8_BASE64` | `.p8` 檔的 base64 |

App Store Connect API Key 在 App Store Connect 的「使用者與存取權限 → 整合」產生，角色選 App 管理。`.p8` 只能下載一次。

在 Windows 上把 `.p8` 轉成 base64：

```bash
base64 -w 0 AuthKey_XXXXXXXXXX.p8
```

另外要先在 Apple 這邊建好兩樣東西：

- Certificates, Identifiers & Profiles 裡註冊 App ID `org.domyweb.baicai`，勾選 Sign In with Apple。
- App Store Connect 裡新增一個 App，Bundle ID 選上面那個，名稱「白菜記帳」。

六個 secrets 齊了之後，推到 main 或到 Actions 手動執行「TestFlight」這個 workflow，就會建置並上傳。缺任何一個時 workflow 會直接略過，不會報錯。

簽章用的是 Xcode 的自動簽章加 API Key，沒有另外匯出憑證。這條線還沒實際跑過，第一次執行如果卡在簽章，把 workflow 的紀錄貼給我。

## 4. Apple 登入（綁定備份用）

Supabase 後台 Authentication 裡打開 Apple provider，Client IDs 填 `org.domyweb.baicai`。原生 App 只需要這一欄，Secret Key 那幾欄是網頁登入才要。

設好之後，在 TestFlight 版的設定頁按「透過 Apple 繼續」，成功會顯示「已綁定 Apple ID」。

## 上架前還要準備

- 隱私權政策與使用條款：草稿在 `docs/PRIVACY_POLICY.md`、`docs/TERMS.md`，裡面標「需作者補充」的地方要填，然後放到一個公開網址。
- App Privacy 問卷：會收集的資料是使用者內容（記帳文字）和識別碼（帳號 ID），用途是 App 功能，不用於追蹤。
- 麥克風與語音辨識的用途說明已經寫在 App 設定裡。
