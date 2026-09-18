# PAWPAY v4 — 先看這份

本次重設台灣與天空島的立體場景，並附上可獨立交給後端同學的固定收入安裝與診斷工具。

- 台灣：放大陸地，沿島內道路排列 28 個原有地點；房屋、屋頂和底座均在陸地內。
- 天空島：22 個原有地點分布於六座高低不同的浮島，跨島橋相連，中央有城堡和彩虹。
- 地名：預設分列顯示，旋轉時重新排位；可隱藏地名，或從「全部地點」查看完整資料。
- 玩家：縮小棋子、限制頭像在畫面內；跨島移動沿橋梁拱形走。
- 你已確認喜歡的 v3 扭蛋機、城市屋頂裝飾、既有遊戲規則、價格、登入與記帳流程維持原版。

## 直接在手機跑

解壓到 `C:\projects\pawpay_v4`，含 `pubspec.yaml` 的資料夾應是 `C:\projects\pawpay_v4\Pawpay`。
在 Windows **CMD** 逐行執行：

```bat
cd /d C:\projects\pawpay_v4\Pawpay
"C:\src\flutter\bin\flutter.bat" pub get
"C:\src\flutter\bin\flutter.bat" devices
"C:\src\flutter\bin\flutter.bat" run -d R5CY90BGHFL
```

ID 使用你先前成功連接的三星手機；如有不同，請換成 devices 列出的 ID。CMD 不要加 `&`；路徑不要放含中文的 OneDrive 或桌面。

## 固定收入 404 的關鍵一步

最新截圖的 `review_service_missing · HTTP 404` 表示目前連到的服務沒有提供確認端點。
**只換手機程式不會更新伺服器。** 請把 `backend_update` 整個資料夾交給管理 `120.126.16.227:5000` 的同學。
對方在實際 Flask 伺服器雙擊 `02_install_on_server.cmd`，選現行 `app.py`，套用後依原方式重啟。
再執行 `01_check_service.cmd`，確認 API 版本 2，才回手機按重試。詳見資料夾內的 README。

本次已交付後端所需程式與工具，但尚未在團隊伺服器部署或驗證 MySQL，不能宣稱線上 404 已消失。

## 文件與驗證

- `ANDROID_PHONE_GUIDE_zh-TW.html`：雙擊閱讀逐步教學。
- `CHANGES_V4_zh-TW.md`：本次範圍與測試結果。
- `backend_update/README_zh-TW.md`：伺服器安裝、重啟與 404 排解。

Dart 語法解析、模型落點與間距檢查通過；28 項 Python 離線測試通過。
Flutter 工具安裝過程因嘗試存取非專案所需的雲端環境資料而被自動審核阻擋，故未完成 Flutter 分析、Flutter 測試、APK 建置及真機測試。
預覽是相同模型的獨立渲染參考，不是手機截圖。
