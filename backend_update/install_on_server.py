"""Interactive installer for the operator of the EXISTING Flask server.

No shell interpolation, service restart, database connection or credentials.
Run in the same Python environment used to operate the backend.
"""
import argparse
from pathlib import Path
import subprocess
import sys


def install(app_file, runner=subprocess.run):
    target = Path(app_file).expanduser().resolve()
    if not target.is_file() or target.name != 'app.py':
        raise ValueError('請選擇目前正在提供 5000 埠服務的 app.py，不是 Flutter 的 main.dart。')
    updater = Path(__file__).with_name('apply_update.py')
    command = [sys.executable, str(updater), str(target)]
    checked = runner(command + ['--check'], check=False)
    if checked.returncode:
        return checked.returncode
    return runner(command, check=False).returncode


def main():
    parser = argparse.ArgumentParser(description='在目前運行 Flask 的伺服器安裝固定收入確認功能')
    parser.add_argument('app_file', nargs='?', help='現行後端 app.py 的完整路徑')
    args = parser.parse_args()
    print('PAWPAY 固定收入確認：伺服器端安裝')
    print('請在目前運行 Flask 5000 的電腦操作。只在前端電腦執行，不會更新團隊伺服器。')
    print('工具先檢查相容性，再備份並更新 app.py；不會自動重啟服務。')
    value = args.app_file or input('貼上現行 app.py 完整路徑（可拖入檔案後按 Enter）：\n').strip().strip('"')
    try:
        code = install(value)
    except (OSError, ValueError) as error:
        print('未完成更新：' + str(error))
        return 1
    if code:
        print('安裝未完成，請依上方錯誤修正；尚不能回手機宣告功能已修好。')
        return code
    print('\n檔案已更新。接下來要用原本方式重新啟動這份 app.py 的 Flask 服務。')
    print('若原本用 python app.py：在原視窗 Ctrl+C，回原後端資料夾重新執行 python app.py。')
    print('若用服務管理器、Docker 或 Gunicorn：更新實際掛載/映像中的程式，再重啟原服務。')
    print('重啟後，在本更新包資料夾執行：')
    print('python check_income_service.py http://127.0.0.1:5000')
    print('再從手機能連線的電腦執行：')
    print('python check_income_service.py http://120.126.16.227:5000')
    print('兩邊均顯示 API 版本 2，才回 App 按重試，驗證確認／取消／復原。')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
