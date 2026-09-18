# 這次交付的修改

1. 大富翁：台灣島與魔法天空島增加側面、厚度、陰影；地塊增加立體底座，已建地產以小房子模型與原有等級顯示。路線、骰子、價格與勝負規則沿用原版。
2. 扭蛋機：原紅色和黑描邊保留，增加機身側面、球罩反光、膠囊明暗、轉把與落球視覺。修正落球的 Positioned 巢狀問題，以及離開畫面後存取已釋放動畫控制器的情況。
3. 城市：沿用現有建築貼圖、樓層與分類邏輯；屋頂新增程式繪製的小模型，配合不同屋頂高度定位，並預留上方空間。常見分類用便當、公車、袋子、手把、衣服、醫藥箱、書本等；自訂分類使用文字小招牌。
4. 固定收入：首頁當期收入旁提供「確認／取消本次」，取消可短暫復原；固定收支右上角可查看月份紀錄及再次復原。沒操作的收入依舊自動計入。首頁共用交易清單在後端成功後更新，其他統計沿用原有算法。

本次原有前端檔案只更動 6 個：

- lib/pages/playground_page.dart
- lib/pages/gacha_page.dart
- lib/widgets/iso_city_view.dart
- lib/pages/home_page.dart
- lib/pages/recurring_transactions_page.dart
- lib/main_app_shell.dart

新檔案為三個繪圖輔助元件、固定收入的 service／操作列／歷史頁、backend_update、針對性測試與本說明／手機教學。沒有升級 pubspec.yaml 或 pubspec.lock，也没有修改原本的伺服器位址、Android 權限、登入或其他頁面。

這是固定視角的 2.5D 視覺，使用 Flutter Canvas 畫出體積，沒有新增 3D 引擎或 3D 模型檔案。原有 Git 歷史不放在交付 ZIP；現有資產與其授權、原專案其他檔案均保留。

## 已做與尚未做的驗證

- 後端 17 項離線行為測試：全部通過。
- 新後端 Python 語法檢查、套用工具與既有 app.py 相容性檢查：通過。
- 修改／新增 Dart 檔案的括號、字串與本地 import 路徑結構檢查：通過。這不是 Dart 編譯器檢查。
- 與原始 ZIP 的逐檔比較：限定原檔更動範圍，原有素材、依賴與其餘檔案維持原樣。
- Flutter analyze、Flutter widget tests、APK 建置、真機版面與實際後端串接：尚未執行。交付環境缺少 Flutter／Android SDK，且無實體手機；下載 SDK 未成功。

`test/requested_changes_test.dart` 隨包提供，請依 ANDROID_PHONE_GUIDE_zh-TW.md 在有 Flutter 的電腦執行。後端功能要先由 5000 服務的負責人套用 backend_update；目前線上伺服器並未由這次作業更新。
