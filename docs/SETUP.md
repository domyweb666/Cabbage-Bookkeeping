> 完整的上架步驟看 [上架指南.md](上架指南.md)。兩份寫法不同時，以那份為準。

# 上 TestFlight 要做的事

App 的資料都在手機上，沒有後端要設定。要準備的是 Apple 這邊的 App、一把 API 金鑰和發佈憑證。

金鑰一律不要貼進程式碼或聊天視窗，照下面的步驟放到 GitHub secrets。

## 1. 在 Apple 建好 App

- Certificates, Identifiers & Profiles：註冊 App ID `org.domyweb.baicai`。不用勾任何額外功能。
- App Store Connect：新增一個 App，Bundle ID 選上面那個，名稱「白菜記帳」。

## 2. 找出金鑰和憑證

簽章走手動（多米 2026-11-25 選的），跟人蔘修煉同一套、同一個 Apple 帳號，所以檔案和值都可以沿用：

- App Store Connect API 金鑰的 `.p8`，角色 App 管理（App Manager），加上 Key ID 和 Issuer ID。
- Apple Distribution 憑證的 `.p12` 和它的密碼。

檔案在你當初存的資料夾，不要放進 repo。

## 3. 放進 GitHub secrets

到 repo 的 Settings → Secrets and variables → Actions，加這六個：

| 名稱 | 內容 |
|---|---|
| `APPLE_DIST_P12_BASE64` | `.p12` 轉成 base64 |
| `APPLE_DIST_P12_PASSWORD` | `.p12` 的密碼 |
| `APPLE_TEAM_ID` | Apple Developer 的 Team ID（10 碼） |
| `ASC_KEY_ID` | API 金鑰的 Key ID |
| `ASC_ISSUER_ID` | 同一把金鑰的 Issuer ID |
| `ASC_KEY_P8_BASE64` | `.p8` 轉成 base64，貼原文也可以 |

轉檔和放 secret 的指令在 [上架指南.md](上架指南.md) 步驟 7。少任何一個，流程會紅，並列出缺哪幾個。

## 4. 建置並上傳

推到 `main` 不會出版。要出版的時候到 Actions → TestFlight → Run workflow，分支選 `main`，或跑：

```powershell
gh workflow run testflight.yml --ref main
```

只准 `main`，選別的分支會紅。

這條線還沒實際跑過。`project.yml` 搭手動簽章的寫法是第一次用，最可能卡在 archive 那一步。紅了照上架指南步驟 9 的表看，卡住就把紀錄貼給我。

上傳成功後，照 [TESTFLIGHT_CHECKLIST.md](TESTFLIGHT_CHECKLIST.md) 在手機上試。

## 簽章的程式在哪裡

| 檔案 | 做什麼 |
|---|---|
| `.github/workflows/testflight.yml` | 整條流程 |
| `ios/project.yml` | app 的 Release 設手動簽章，描述檔名 `Baicai CI App Store` |
| `ios/ci/require_ready.sh` | 擋分支和缺 secret |
| `ios/ci/select_xcode.sh` | 選正式版 Xcode 26 |
| `ios/ci/restore_asc_key.sh`、`import_dist_cert.sh` | 還原金鑰和憑證，先驗格式 |
| `ios/ci/asc_preflight.mjs` | 打包前問 Apple 金鑰、app 記錄、build 號 |
| `ios/ci/appstore_profile.mjs` | 申請描述檔，只動自己那一張 |
| `ios/ci/run_logged.sh` | 跑 xcodebuild，只印錯誤，遮掉名字和 ID |
| `ios/ci/cleanup_signing.sh` | 最後刪掉鑰匙圈和金鑰檔 |

發佈憑證一年到期一次，換新的時候更新 `APPLE_DIST_P12_BASE64` 和 `APPLE_DIST_P12_PASSWORD` 兩個 secret。

## 上架前還要準備

- 隱私權政策與使用條款：草稿在 `docs/PRIVACY_POLICY.md`、`docs/TERMS.md`，標「需作者補充」的地方要填，再放到公開網址。
- App Privacy 問卷：照現在的程式，選「不收集資料」。
