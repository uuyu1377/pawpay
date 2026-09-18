# PAWPAY v4：在你的 Android 手機測試更新

更新日期：2026-09-17。本次重設台灣與天空島，保留你已確認喜歡的扭蛋機；提供固定收入 404 的伺服器安裝與排解工具。

你的 Flutter 3.38.5、Android SDK 和三星手機連線已經成功，**不用重新安裝**。以下指令全部使用 Windows「命令提示字元（CMD）」；不要在指令前加 `&`。

已通過 28 項 Python 離線測試、Dart 語法解析與模型幾何檢查。Flutter 工具安裝流程因嘗試存取非專案所需的雲端環境資料而被自動審核阻擋，**未完成 Flutter 分析、Flutter 測試、APK 建置或真機測試**。你收到的是完整原始碼，請用已經安裝好的 Flutter 3.38.5 建置，不必升級套件。

## 1. 解壓縮到全英文路徑

1. 下載這次的 `Pawpay.zip`，舊專案先保留。
2. 在檔案總管建立 `C:\projects\pawpay_v4`。
3. 對 ZIP 按右鍵 →「全部解壓縮」，目的地選上面的資料夾。
4. 打開解壓縮後的 `Pawpay`，確認裡面有 `pubspec.yaml`、`lib`、`android`、`assets`。
5. 正確專案路徑應為 `C:\projects\pawpay_v4\Pawpay`。若解壓工具多包了一層，以含有 `pubspec.yaml` 的那層為準。

先前的建置錯誤來自 `OneDrive - 長庚大學\桌面` 這類含中文的路徑。這次直接使用上面的全英文路徑。專案內原有的 `lib.zip`、`assets.zip` 是舊備份，**不要解壓覆蓋新程式**。

## 2. 開啟 CMD 並下載依賴

按 Windows 開始選單，輸入「cmd」，開啟「命令提示字元」。逐行貼上：

```bat
cd /d C:\projects\pawpay_v4\Pawpay
"C:\src\flutter\bin\flutter.bat" pub get
```

看到 `Got dependencies!` 就可以繼續。「107 packages have newer versions incompatible with dependency constraints」是更新提示，不是建置錯誤，不必先升級套件。

若看見 `No pubspec.yaml file found`，請回第一步找正確資料夾。若找不到 `flutter.bat`，確認 SDK 是否仍在 `C:\src\flutter`。

Android Studio 也可以：選 `File → Open`，開啟 `C:\projects\pawpay_v4\Pawpay`，SDK 路徑保持 `C:\src\flutter`。請開整份 Flutter 專案的根目錄。[Flutter 官方說明](https://docs.flutter.dev/tools/android-studio)

## 3. 連接你的三星手機

1. 使用上次成功的 USB 傳輸線接上手機與電腦。
2. 解鎖手機，確認「開發人員選項 → USB 偵錯」已開啟。
3. 若跳出「允許 USB 偵錯」，確認是自己的電腦後按允許。
4. 在同一個 CMD 執行：

```bat
"C:\src\flutter\bin\flutter.bat" devices
```

先前成功辨識到的手機是 `SM A1760`，ID 為 `R5CY90BGHFL`。仍看到它就可以繼續；如果 ID 不同，下一步改用新 ID。[Android 真機連線說明](https://developer.android.com/studio/run/device)

如果又顯示「已遭自動封鎖程式封鎖」，這是三星 Auto Blocker 的限制。在自己的手機「設定 → 安全性與隱私權 → 自動封鎖程式」調整後再開 USB 偵錯；選單名稱依版本略有差異。測試結束、不再需要 USB 偵錯時，可關閉偵錯並恢復自動封鎖。[Samsung 官方說明](https://www.samsung.com/tw/support/mobile-devices/protect-your-galaxy-device-with-the-new-auto-blocker-feature/)

## 4. 建置並安裝到手機

保持手機連線，在專案根目錄的 CMD 執行：

```bat
"C:\src\flutter\bin\flutter.bat" run -d R5CY90BGHFL
```

新資料夾需要重新建置，可能花幾分鐘。`Running Gradle task 'assembleDebug'` 表示正在建置；完成後手機會自動開啟 App。

也附了 `run_on_phone.cmd`：雙擊會先下載依賴，再執行 Flutter；有多個裝置時，依提示選 Android 手機。手動指令較方便保留完整錯誤訊息。

若沿用舊資料夾且有舊建置快取問題，先停止執行中的 App，再執行以下指令；全新解壓通常不需 clean：

```bat
"C:\src\flutter\bin\flutter.bat" clean
"C:\src\flutter\bin\flutter.bat" pub get
"C:\src\flutter\bin\flutter.bat" run -d R5CY90BGHFL
```

## 5. 測試重設後的兩張地圖

1. 選台灣：房屋應落在島內道路上，中央看得到低山、湖泊、田地與樹木。
2. 單指左右拖曳旋轉、上下拖曳調整角度；雙指縮放。雙擊或按「重設視角」回到預設。
3. 原有地名預設分列顯示，點名稱或房屋，下方顯示所有者、等級、地價與租金。
4. 名稱旁圖示可隱藏地名；下方「全部地點」保留完整清單。放大後超出畫面的地點可透過清單選取或回正。
5. 正常擲骰測試移動與多人同格，確認頭像仍在畫面內。
6. 再選天空島：應看見六座浮島、跨島橋、中央城堡和彩虹，建築是圓塔而非台灣小屋。
7. 確認地名、走格順序和原本事件相同；跨島時棋子沿橋梁拱形移動。

遊戲地形為原創三維網格，保留柔和的玩具風格。地圖位置是棋盤顯示配置，並非精確地理座標；既有地名與遊戲規則未修改。模型都包含在專案內，不需下載外部 3D 素材。

## 6. 扭蛋機與城市

你已確認喜歡的貓耳立體扭蛋機沿用 v3，整份頁面、模型和動畫程式未變更。城市屋頂分類裝飾也保留。本次更新只重設兩張大富翁地圖與整理固定收入的後端安裝工具。

## 7. 固定收入：更新實際運行的後端

**這一步與安裝手機 App 分開。** 確認／取消／復原需要原本的 Flask 5000 服務安裝 `backend_update`。在自己電腦解壓前端，不會更新團隊伺服器。

最新截圖已顯示 **review_service_missing · HTTP 404**，目前連到的服務沒有提供確認端點。只重新下載手機 App 仍會遇到相同錯誤；請後端同學在實際伺服器安裝並重啟。這裡沒有線上部署權限，亦未完成你們伺服器的連線驗證。

若伺服器由同學管理，將 **Pawpay_Backend_Update.zip** 或專案內整個 `backend_update` 資料夾交給對方。Windows 可雙擊 `02_install_on_server.cmd`，貼上現行後端 app.py 路徑，工具會先檢查再備份安裝；務必接著重啟服務。完整說明在 README_zh-TW.md。以下在執行 Flask 的電腦、原本的 Python 環境進行；`C:\your_backend\app.py` 必須換成現行後端的真實位置：

```bat
cd /d C:\projects\pawpay_v4\Pawpay\backend_update
python apply_update.py --check "C:\your_backend\app.py"
python apply_update.py "C:\your_backend\app.py"
```

檢查通過後才執行實際更新；先保留資料庫備份。工具會備份原始 `app.py`；已有舊版增補模組時也會備份。它只更新必要檔案，不會自動啟動服務。

依原有方式**重新啟動 Flask 5000**，再於伺服器執行：

```bat
python check_income_service.py http://127.0.0.1:5000
```

再從原本能連到 App 的網路，雙擊更新包內的 `01_check_service.cmd`，確認對外網址也回 API 版本 2。本機成功但對外 404，通常是代理／容器或啟動檔路徑不一致，需要後端同學檢查。

看到 v2 服務已啟用，代表更新已載入。這項檢查不登入、不讀寫記帳資料，也不檢查 MySQL；完整驗證仍要登入 App 測試收入操作。若顯示舊版，確認有重啟實際執行的服務；若顯示未安裝，核對更新的 `app.py` 是否就是線上啟動的那份。

前端沿用 `lib/config/backend_config.dart` 的 `120.126.16.227`、5000／8000 埠與 `androidEmulator = false`，沒有改連線位址。8000 服務照原本方式運作。

## 8. 測試固定收入與辨識錯誤

1. 重新登入 App，建立今天到期、容易辨識的一筆測試固定收入。
2. 回首頁等資料載入。即使沒按確認，也應照原機制自動入帳一次。
3. 按勾勾「確認」，總額不應再增加。
4. 按「取消本次」，只移除這一期；下期規則仍保留。
5. 按「復原」恢復同一筆收入。若提示消失，可從「固定收支」右上角的歷史入口選月份，找到已取消的期次。
6. 關閉重開 App，取消的期次不應再次自動產生。

原有固定收入是在啟動 App／回首頁時請後端補登，沒有新增手機背景常駐服務。

若看到錯誤，點「查看原因」，依診斷碼處理：

| 提示／診斷 | 處理方式 |
|---|---|
| 固定收入確認服務尚未啟用／review_service_missing | 依第 7 步安裝後端並重啟，確認 IP 與埠正確 |
| 請重新登入／review_login_required | 登出後使用原方式登入，再回首頁 |
| review_account_changed | 重新載入目前帳號資料 |
| review_connection_failed | 確認手機網路與 5000 服務可連線 |
| review_database_unavailable | 請後端負責人檢查 MySQL 連線及建立資料表的權限 |
| review_server_error | 請後端負責人查看同時間日誌 |
| review_conflict | 收入狀態已變更，重試取得最新版本 |
| review_invalid_request／review_invalid_data／review_invalid_response | 前後端資料不一致，確認兩邊都使用本版 |

保留診斷碼與 HTTP 狀態，這比「暫時無法載入」更能定位問題。App 不會把失敗的確認／取消假裝成功。

## 9. 可執行的檢查與 APK

在前端根目錄執行：

```bat
cd /d C:\projects\pawpay_v4\Pawpay
"C:\src\flutter\bin\flutter.bat" analyze
"C:\src\flutter\bin\flutter.bat" test test/requested_changes_test.dart test/board_and_income_v2_test.dart test/paw_gacha_3d_test.dart test/board_v4_test.dart
```

Flutter 測試涵蓋地圖手勢、地點清單、標籤間距及固定收入操作／錯誤。測試已附在專案，但交付環境尚未執行。原專案可能有既有的分析提醒；遇到失敗請保留最前面的具體 `error`。

後端離線測試不需連線資料庫：

```bat
python -m unittest discover -s backend_update -p "test_*.py" -v
```

28 項測試包含互動安裝工具、確認／取消／復原、跨帳號隔離、版本衝突、回滾、安裝工具與服務診斷。SQL 透過 SQLite 相容轉接層測試，不能取代 MySQL 行鎖及整合驗證。

產生可另行安裝的測試 APK：

```bat
"C:\src\flutter\bin\flutter.bat" build apk --debug
```

成功後檔案在 `build\app\outputs\flutter-apk\app-debug.apk`。本版沒有調整正式簽章或上架設定。[Flutter Android 建置說明](https://docs.flutter.dev/deployment/android)

## 常見建置狀況

| 狀況 | 處理 |
|---|---|
| 「這個時候不應有 &」 | CMD 指令不要加 `&`，照本教學的完整路徑執行 |
| project path contains non-ASCII characters | 回第 1 步，移到全英文路徑，不要放中文桌面／OneDrive 路徑 |
| 套件有新版，但 Got dependencies! 成功 | 繼續建置，不必為此升級依賴 |
| 手機 unauthorized | 解鎖手機，接受自己的電腦之 USB 偵錯授權 |
| 只看到 Windows／Chrome | 確認 USB 偵錯及資料傳輸線，再執行 devices |
| 簽章不相容 | 保留資料，核對是否使用不同電腦的 debug 簽章，不要直接移除舊 App |
| App 開得起來，但登入／交易失敗 | 確認原有 Firebase 設定、5000 與 8000 服務正常 |
| 磁碟的空間不足 | 先在舊專案根目錄執行 flutter clean 清除可重建的 build 快取，並清理 C 槽或將不用的影片／ZIP 移到其他磁碟；確認 C 槽與專案所在磁碟都有空間後再建置。不要刪 lib、assets 或 android 原始碼 |
| BUILD FAILED | 保留 What went wrong 與最前面的具體錯誤；最後一句 exit code 1 無法定位原因 |

需要重新檢查工具鏈時執行 `"C:\src\flutter\bin\flutter.bat" doctor -v`。你之前已全部通過，先依本教學更新專案即可。[Flutter Android 環境設定](https://docs.flutter.dev/platform-integration/android/setup)

常用指令核對：[Flutter CLI 官方參考](https://docs.flutter.dev/reference/flutter-cli)。
