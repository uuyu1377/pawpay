"""Read-only HTTP check. No token, user data, DB credentials or writes required.

python check_income_service.py http://127.0.0.1:5000
python check_income_service.py http://120.126.16.227:5000
"""
import argparse
from datetime import date
import json
import urllib.error
import urllib.parse
import urllib.request


def get(url, opener=urllib.request.urlopen):
    request = urllib.request.Request(url, headers={'Accept': 'application/json'})
    try:
        with opener(request, timeout=8) as response:
            return response.status, response.read(64 * 1024).decode('utf-8', errors='replace')
    except urllib.error.HTTPError as error:
        return error.code, error.read(64 * 1024).decode('utf-8', errors='replace')


def diagnose(base_url, opener=urllib.request.urlopen):
    parsed = urllib.parse.urlsplit(base_url)
    if parsed.scheme not in {'http', 'https'} or not parsed.hostname or parsed.username or parsed.password:
        raise ValueError('請提供不含帳號密碼的 http://主機:埠 或 https://主機:埠')
    root = base_url.rstrip('/')
    status, body = get(root + '/api/recurring-income/health', opener)
    if status == 200:
        try:
            data = json.loads(body)
        except ValueError:
            data = {}
        if data.get('service') == 'pawpay_recurring_income_review':
            return 0, ('確認功能已安裝，API 版本：' + str(data.get('api_version')) +
                       '。請回 App 重試；此檢查不代表登入或資料庫已通過驗證。')
        return 1, 'HTTP 200，但內容不是固定收入服務。請檢查伺服器位址或反向代理設定。'
    if status in (404, 405):
        # Legacy V1 has no health route, but authenticates before opening a DB.
        legacy_status, legacy_body = get(root + '/api/recurring-income/history?month=' + date.today().strftime('%Y-%m'), opener)
        if legacy_status == 401:
            try:
                data = json.loads(legacy_body)
            except ValueError:
                data = {}
            if data.get('status') == 'error':
                return 0, '已偵測到需要登入的舊版確認介面。建議套用本次更新；若 App 顯示 401，請重新登入。'
        if legacy_status in (404, 405):
            return 2, '固定收入確認介面尚未安裝或尚未重啟。請在實際的 Flask 伺服器執行 apply_update.py，然後重啟 5000 埠服務。'
        return 1, f'舊版介面回應 HTTP {legacy_status}。請檢查伺服器紀錄與登入設定。'
    if status in (401, 403):
        return 1, f'HTTP {status}：連線被登入或代理規則阻擋，請專題管理者確認。'
    return 1, f'HTTP {status}：服務尚未正常回應，請檢查伺服器紀錄。'


def main():
    parser = argparse.ArgumentParser(description='檢查 PAWPAY 固定收入確認服務是否已安裝')
    parser.add_argument('base_url', help='例如 http://127.0.0.1:5000')
    args = parser.parse_args()
    try:
        code, message = diagnose(args.base_url)
    except (OSError, ValueError, urllib.error.URLError):
        code, message = 1, '連線未完成：請檢查位址、5000 埠服務與手機/電腦是否能存取該網路。'
    print(message)
    return code


if __name__ == '__main__':
    raise SystemExit(main())
