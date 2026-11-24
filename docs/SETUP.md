> 完整的上架步驟看 [上架指南.md](上架指南.md)。兩份寫法不同時，以那份為準。

# 上 TestFlight 要做的事

App 的資料都在手機上，沒有後端要設定。要準備的是 Apple 這邊的 App 和一把 API 金鑰。

金鑰一律不要貼進程式碼或聊天視窗，照下面的步驟放到 GitHub secrets。

## 1. 在 Apple 建好 App

- Certificates, Identifiers & Profiles：註冊 App ID `org.domyweb.baicai`。不用勾任何額外功能。
- App Store Connect：新增一個 App，Bundle ID 選上面那個，名稱「白菜記帳」。

## 2. 產生 App Store Connect API 金鑰

在 App Store Connect 的「使用者與存取權限 → 整合」產生。`.p8` 只能下載一次，先存好。

角色選管理（Admin）。這條線用 Xcode 自動簽章，多米的另一個專案實際試過，App 管理的金鑰在匯出時會被擋下來，回「Cloud signing permission error」。

在 Windows 上（Git Bash）把 `.p8` 轉成 base64：

```bash
base64 -w 0 AuthKey_XXXXXXXXXX.p8
```

## 3. 放進 GitHub secrets

到 repo 的 Settings → Secrets and variables → Actions，加這四個：

| 名稱 | 內容 |
|---|---|
| `APPLE_TEAM_ID` | Apple Developer 的 Team ID（10 碼） |
| `ASC_KEY_ID` | API 金鑰的 Key ID |
| `ASC_ISSUER_ID` | 同一把金鑰的 Issuer ID |
| `ASC_KEY_P8_BASE64` | 上一步轉出來的那串，不要貼 `.p8` 原文 |

少任何一個，TestFlight 這個 workflow 會直接略過，不會報錯。

## 4. 建置並上傳

把 `build-mvp` 併進 `main` 就會自動建置上傳。`main` 上目前還沒有這個 workflow 檔，要併進去之後，Actions 頁面才有手動執行的按鈕。

這條線還沒實際跑過。第一次可能卡在下面兩個地方：

- Apple 要求用 iOS 26 SDK 建置，兩個 workflow 都改用 `macos-26` 加 Xcode 26。TestFlight 那條還沒實際跑過。
- 自動簽章每跑一次會向 Apple 多要一張開發憑證，累積到帳號上限就會失敗，同一個帳號的其他專案也會受影響。解法是改成手動簽章。

卡住就把 workflow 的紀錄貼給我。

上傳成功後，照 [TESTFLIGHT_CHECKLIST.md](TESTFLIGHT_CHECKLIST.md) 在手機上試。

## 上架前還要準備

- 隱私權政策與使用條款：草稿在 `docs/PRIVACY_POLICY.md`、`docs/TERMS.md`，標「需作者補充」的地方要填，再放到公開網址。
- App Privacy 問卷：照現在的程式，選「不收集資料」。
