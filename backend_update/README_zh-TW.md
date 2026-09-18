# 固定收入確認／取消本次：後端更新

這是給目前運行 PAWPAY Flask 5000 服務的負責人使用的增補模組。Flutter 前端已接好，伺服器套用後即可使用。不是另一個獨立服務，不需要更改前端 API IP 或啟動新的埠。

## 版本依據與範圍

前端以這次 Pawpay.zip 為基礎。本模組依先前配套 Flask app.py 的 `recurring_transaction_runs`、`accounting_transactions` 和登入驗證介面製作；目前前端的 recurring_api_service.dart 與先前配套版本一致。因為無法確認線上 app.py 是否另有更新，交付增補模組與檢查式套用工具，避免用舊版整份後端覆蓋線上程式。

新增 `recurring_income_reviews` 資料表、3 個登入後使用的 API，以及 1 個公開的版本健康檢查。不改既有扣幣、發票、AI、匯率、固定支出或週期計算。收入取消時會刪除對應的當期 accounting_transactions 資料，並保存整列快照；原本 recurring_transaction_runs 的唯一紀錄保留。復原會使用相同交易 ID 還原原始欄位。

## 套用

1. 備份現行資料庫；保留現有啟動方式與 Python 環境。
2. 將此資料夾放到執行 Flask 的電腦。
3. `python apply_update.py --check 現行app.py的完整路徑`
4. 相容性檢查通過後：`python apply_update.py 現行app.py的完整路徑`
5. 檢查原位置的 `app.py.before_income_review_*.bak` 備份、新增的 `recurring_income_review.py`，及 app.py 啟動前的註冊呼叫。
6. 按原方式重啟 Flask。8000 的 FastAPI/MySQL 服務照常運行。
7. 在此資料夾執行 `python check_income_service.py http://127.0.0.1:5000`，確認 v2 已載入；非預設埠請替換。

工具只寫入檔案，不連線資料庫、不重啟或部署服務。第一次有效的 API 呼叫會建立新表；使用既有資料庫帳號，需具有建立新表的權限。安裝工具會拒絕缺少已知介面的後端版本。

已裝過 v1 也用相同步驟更新。註冊呼叫不會重複加入，但會替換增補模組；原模組另存為 `recurring_income_review.py.before_*.bak`。更新後仍須重啟實際執行的 Flask 服務。

## 確認目前服務版本

診斷程式僅送出唯讀 HTTP 請求，不需要 Token，也不讀寫記帳資料。它會區分新版 v2、只有舊版端點、未安裝、連到不同服務與網路失敗。v2 健康檢查成功只能證明程式已載入，不能證明資料庫已連線；接著需登入 App 驗證操作。

如在使用者電腦檢查團隊服務，可用 `python check_income_service.py http://120.126.16.227:5000`。無法連線時請先核對網路／服務是否啟動。這份交付未部署或驗證實際線上服務，最新截圖已顯示 review_service_missing · HTTP 404，表示 App 呼叫的確認端點没有在目前連線位址提供；請按下方 404 排解操作。

## API

三個記帳 API 使用現有 JWT 驗證。user_id 以登入 Token 為準，不接受指定其他帳號；健康檢查不含帳號、資料庫或憑證資訊。

| 方法／路徑 | 用途 |
|---|---|
| GET /api/recurring-income/health | 公開版本檢查；service=pawpay_recurring_income_review、api_version=2，不接觸資料庫 |
| POST /api/recurring-income/reviews | body: transaction_ids，最多 500 筆；回傳真實對應固定收入的 review 清單 |
| GET /api/recurring-income/history?month=YYYY-MM | 當月收入紀錄，包含取消的期次 |
| POST /api/recurring-income/{rule_id}/{scheduled_date}/review | body: action 與 expected_version；action 為 confirm/cancel/restore |

確認只改狀態；取消與復原在同一資料庫交易內完成。SQL 使用 user_id 條件與行鎖，版本不一致回 409，前端重新載入。退款、付款或真實銀行帳戶不在這個功能的操作範圍內；此功能處理 App 的記帳紀錄。

若已改過 accounting_transactions 結構或增加其他系統依賴，請先在測試資料庫驗證撤銷與復原。資料庫拒絕刪除／還原時，整筆操作 rollback，前端不會假裝成功。

前端 v2 會自動以每批 200 筆查詢，不需要放寬後端筆數上限。401／403 請重新登入；409 為版本衝突；`review_database_unavailable` 請查看資料庫連線或建表權限；其他 500 請查看伺服器日誌。用戶端只顯示診斷碼，不回傳內部 SQL 錯誤。

## 驗證

`python -m unittest discover -s . -p "test_*.py" -v`

28 項離線測試已通過，包含新增的健康檢查、診斷工具及增量安裝；使用 SQLite 的 DB-API 相容測試轉接層執行真實 store 查詢及資料變更。尚未在你們的 MySQL 實例測試行鎖、資料表關聯與線上整合。

若要移除本功能，先停止服務，還原對應的 app.py 備份再按原方式啟動。保留新表與原本 recurring_transaction_runs，避免失去取消紀錄；不要直接刪除資料表或用恢復整個舊資料庫來撤銷程式更新。

## 這次的 404：直接照這樣處理

**這包要交給實際管理 `120.126.16.227:5000` Flask 服務的同學。** 手機已經能打開 App，這一步不需要重裝 Flutter，也不是要在你的前端資料夾建立一個假的 app.py。

1. 把整包解壓到 Flask 伺服器。確認正在執行的原始後端 `app.py` 在哪個資料夾，並保留資料庫備份。
2. Windows：雙擊 `02_install_on_server.cmd`，貼上那份 `app.py` 的完整路徑，按 Enter。工具會先檢查相容性，通過後自動備份與套用。若 Python 用虛擬環境，先啟用原環境，再執行 `python install_on_server.py`。
3. Linux 或已開啟終端機：在更新包內執行 `python3 install_on_server.py /實際後端路徑/app.py`。
4. **重啟真正的 Flask 服務。** 若平常用 `python app.py`，到原本執行的終端機按 Ctrl+C，再在原資料夾用相同環境執行 `python app.py`。若使用 Docker、Gunicorn 或系統服務，依原部署方式更新容器／映像與重啟；不要另外開第二個 5000 埠服務。
5. 在伺服器更新包資料夾執行 `python check_income_service.py http://127.0.0.1:5000`。
6. 在原本能使用 App 的網路，雙擊 `01_check_service.cmd`，或執行 `python check_income_service.py http://120.126.16.227:5000`。
7. 都顯示 API 版本 2，再回手機按「重試」。使用一筆可辨識的測試收入驗證：未勾照常入帳、確認不重複加錢、取消只移除本期、復原還原同筆資料。

| 檢查結果 | 下一步 |
|---|---|
| 本機和對外都回 404 | 檢查是否改錯 app.py、漏了重啟，或重啟的是另一個程序。 |
| 本機版本 2、對外 404 | 檢查反向代理、容器映射，或對外網址是否導到另一份服務。 |
| 兩邊版本 2、App 仍 404 | 核對 App 的實際後端位址；本包仍沿用 `120.126.16.227:5000`。 |
| review_database_unavailable | API 已存在，接著檢查 MySQL 連線及建立新表的權限。 |
| 401／403 | API 已存在，但登入驗證未通過；先重新登入並檢查伺服器驗證設定。 |

也可在瀏覽器打開 `http://120.126.16.227:5000/api/recurring-income/health`。
正確 JSON 應包含 `service: pawpay_recurring_income_review` 與 `api_version: 2`。
健康檢查成功僅證明功能已載入，不代表資料庫操作已成功。

此交付沒有登入或變更團隊伺服器，無法從這裡完成線上部署。若不做第 2–6 步，只換手機 App，404 仍會存在。
