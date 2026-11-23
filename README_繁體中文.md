# Cloud Photo Vault — Android + Google Drive 第一版

呢份係真實 **Flutter App 原始碼（MVP）**，唔係圖片模擬稿，但目前 **未編譯成 APK、未喺實機測試**。需要用 Flutter + Android Studio 建置，並且設定你自己 Google Cloud OAuth。

## 已寫好嘅功能

- Android 11 或以上使用
- Google 帳戶登入及 Drive 連接
- 掃描手機相片／影片
- 手動揀相、或者一次過備份新相
- 盡力喺背景定期備份（約每六個鐘排程一次，實際時間由 Android 決定）
- Wi-Fi only 設定
- 保留原始檔案，不壓縮
- 按拍攝年份／月份備份到 Google Drive 資料夾
- 記錄備份資料，避免重複上傳
- **確認 Google Drive 內檔案大小及 MD5 完全一致，先記錄備份成功**
- **清理前重新檢查手機原圖及 Google Drive 檔案**
- 經你確認，先呼叫 Android 官方系統介面將原圖移入垃圾桶（唔會直接永久刪除）

## 點樣繼續開發及安裝？

1. 喺 Windows / Mac / Linux 安裝 Flutter SDK 同 Android Studio。
2. 打開呢個 project 目錄，執行 `python3 scripts/setup_android.py`。
3. 再執行 `flutter pub get` 同 `flutter test`。
4. 去 Google Cloud Console 啟用 **Google Drive API**，建立 Android OAuth client（包名 `com.example.cloud_photo_vault` + Debug SHA-1），再建立 Web OAuth client。
5. 用真實 Android 手機測試：

```
flutter run --dart-define=GOOGLE_WEB_CLIENT_ID=你的WebClientID.apps.googleusercontent.com
```

6. 測試成功後，可用 `flutter build apk --debug --dart-define=GOOGLE_WEB_CLIENT_ID=...` 產生 APK。

詳細英文步驟同 Google 設定請睇 `README.md`。另有 `CODEX_HANDOFF.md`，可以交俾 Codex 直接繼續 Debug、編譯同打包。

## 安全提醒

首次一定用 **測試相片**，唔好直接用重要家庭相。Google Drive 同 Google Photos 係兩套獨立服務。相片被移到 Android 垃圾桶後，未必即刻釋放空間，亦可能影響其他正在同步嘅相簿服務。任何上架版本必須完成實機測試、OAuth 設定、安全及私隱審查。
