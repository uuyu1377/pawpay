r"""Install this additive extension into the user's CURRENT Flask app.py.

Usage: python apply_update.py C:\path\to\my_backend_project\app.py
The installer checks the known recurring schema/functions, backs up app.py,
adds a registration call before its main guard, and copies the module beside it.
"""
import argparse
import ast
import hashlib
from pathlib import Path
import re
import shutil
import sys

MARKER = '# PAWPAY_RECURRING_INCOME_REVIEW_V1'
REGISTRATION = '''
# PAWPAY_RECURRING_INCOME_REVIEW_V1
from recurring_income_review import register_recurring_income_review
register_recurring_income_review(
    app, get_db_connection, get_authenticated_user_id, _ensure_app_extension_tables,
)

'''


def patched_source(source):
    tree = ast.parse(source)
    functions = {n.name for n in tree.body if isinstance(n, ast.FunctionDef)}
    required = {'get_db_connection', 'get_authenticated_user_id',
                '_ensure_app_extension_tables', 'process_due_recurring_transactions'}
    missing = required - functions
    if missing:
        raise ValueError('這份後端版本不相容，缺少：' + ', '.join(sorted(missing)))
    for name in ('recurring_transaction_runs', 'accounting_transactions',
                 'accounting_categories', 'entry_method'):
        if name not in source:
            raise ValueError('後端資料表結構不相容：' + name)
    if MARKER in source:
        return source
    main = next((n for n in tree.body if isinstance(n, ast.If)
                 and isinstance(n.test, ast.Compare)
                 and isinstance(n.test.left, ast.Name) and n.test.left.id == '__name__'
                 and len(n.test.ops) == 1 and isinstance(n.test.ops[0], ast.Eq)
                 and isinstance(n.test.comparators[0], ast.Constant)
                 and n.test.comparators[0].value == '__main__'), None)
    if main is None:
        raise ValueError('找不到 app.py 的啟動區塊，未修改檔案。')
    lines = source.splitlines(keepends=True)
    result = ''.join(lines[:main.lineno - 1]) + REGISTRATION + ''.join(lines[main.lineno - 1:])
    ast.parse(result)
    return result


def main():
    parser = argparse.ArgumentParser(description='PAWPAY 固定收入確認功能更新')
    parser.add_argument('app_file', type=Path)
    parser.add_argument('--check', action='store_true', help='只檢查相容性，不寫入')
    args = parser.parse_args()
    target = args.app_file.resolve()
    if not target.is_file() or target.name != 'app.py':
        raise ValueError('請指定現有 Flask 後端的 app.py 完整路徑')
    raw = target.read_bytes()
    source = raw.decode('utf-8-sig')
    patched = patched_source(source)
    if args.check:
        print('相容性檢查通過。尚未修改任何檔案。')
        return
    extension = Path(__file__).with_name('recurring_income_review.py')
    ast.parse(extension.read_text(encoding='utf-8'))
    installed_extension = target.with_name(extension.name)
    if (installed_extension.exists() and extension.resolve() != installed_extension.resolve()
            and installed_extension.read_bytes() != extension.read_bytes()):
        old_extension = installed_extension.read_bytes()
        old_digest = hashlib.sha256(old_extension).hexdigest()[:12]
        module_backup = installed_extension.with_name(extension.name + '.before_' + old_digest + '.bak')
        if not module_backup.exists():
            module_backup.write_bytes(old_extension)
    digest = hashlib.sha256(raw).hexdigest()[:12]
    backup = target.with_name('app.py.before_income_review_' + digest + '.bak')
    if patched != source:
        if not backup.exists():
            backup.write_bytes(raw)
        # Match the existing file's line endings without touching other source.
        newline = '\r\n' if b'\r\n' in raw else '\n'
        normalized = patched.replace('\r\n', '\n').replace('\r', '\n')
        staged = target.with_name('app.py.income_review.tmp')
        staged.write_bytes(normalized.replace('\n', newline).encode('utf-8'))
        # Copy the dependency before making the registration visible.
        if extension.resolve() != target.with_name(extension.name).resolve():
            shutil.copy2(extension, target.with_name(extension.name))
        staged.replace(target)
    elif extension.resolve() != target.with_name(extension.name).resolve():
        shutil.copy2(extension, target.with_name(extension.name))
    print('更新完成：' + str(target))
    print('請重新啟動 5000 埠的 Flask 後端；8000 埠服務維持原本版本。')
    print('重啟後檢查：python check_income_service.py http://127.0.0.1:5000')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, SyntaxError) as e:
        print('未完成更新：' + str(e), file=sys.stderr)
        sys.exit(1)
