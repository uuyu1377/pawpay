"""Offline behavioral tests using a SQLite DB-API adapter.

Runs the real store queries and mutations. MySQL-only DDL syntax/row locks are
adapted for SQLite; actual MySQL locking and deployed services still need QA.
Run: python -m unittest discover -s backend_update -p 'test_*.py' -v
"""
import ast
from datetime import date
from decimal import Decimal
import json
from pathlib import Path
import re
import sqlite3
import sys
import types
import unittest
from unittest.mock import patch

from recurring_income_review import IncomeReviewStore, ReviewError, json_value, month_bounds
from recurring_income_review import register_recurring_income_review
from apply_update import patched_source, MARKER


class Cursor:
    def __init__(self, connection):
        self.conn = connection
        self.raw = connection.raw.cursor()
        self.special = None

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.raw.close()

    def execute(self, sql, params=()):
        self.special = None
        if sql.startswith('SHOW COLUMNS FROM accounting_transactions'):
            self.special = [{'Field': row['name'], 'Extra': ''} for row in
                            self.conn.raw.execute('PRAGMA table_info(accounting_transactions)')]
            return
        sql = re.sub(r',\s*INDEX \w+ \([^)]*\)', '', sql)
        sql = re.sub(r'\) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4', ')', sql)
        sql = re.sub(r'\s+FOR UPDATE\b', '', sql)
        sql = sql.replace('INSERT IGNORE INTO', 'INSERT OR IGNORE INTO').replace('%s', '?')
        params = tuple(p.isoformat() if isinstance(p, date) else str(p) if isinstance(p, Decimal)
                       else p for p in params)
        return self.raw.execute(sql, params)

    @property
    def rowcount(self):
        return self.raw.rowcount

    def fetchall(self):
        return self.special if self.special is not None else [dict(r) for r in self.raw.fetchall()]

    def fetchone(self):
        row = self.raw.fetchone()
        return dict(row) if row is not None else None


class Connection:
    def __init__(self):
        self.raw = sqlite3.connect(':memory:')
        self.raw.row_factory = sqlite3.Row
        self.closed = False

    def cursor(self): return Cursor(self)
    def begin(self): self.raw.execute('BEGIN')
    def commit(self): self.raw.commit()
    def rollback(self): self.raw.rollback()
    def close(self): self.closed = True


class ReviewTests(unittest.TestCase):
    def setUp(self):
        self.conn = Connection()
        self.db = self.conn.raw
        self.db.executescript('''
            CREATE TABLE accounting_categories (id INTEGER PRIMARY KEY, name TEXT);
            INSERT INTO accounting_categories VALUES (1, '薪水');
            CREATE TABLE accounting_transactions (
                id INTEGER PRIMARY KEY, user_id TEXT, amount TEXT, type TEXT,
                entry_method TEXT, note TEXT, date TEXT, category_id INTEGER, currency TEXT
            );
            CREATE TABLE recurring_transaction_runs (
                rule_id INTEGER, scheduled_date TEXT, transaction_id INTEGER,
                PRIMARY KEY (rule_id, scheduled_date)
            );
            CREATE TABLE recurring_transactions_app (id INTEGER PRIMARY KEY, next_run_date TEXT);
            INSERT INTO recurring_transactions_app VALUES (10, '2026-10-15');
            INSERT INTO accounting_transactions VALUES
                (100, 'alice', '30000.00', 'income', 'recurring', '月薪', '2026-09-15', 1, 'TWD'),
                (101, 'alice', '30000.00', 'income', 'manual', '固定收支：薪水', '2026-09-15', 1, 'TWD'),
                (102, 'bob', '40000.00', 'income', 'recurring', '他人薪資', '2026-09-15', 1, 'TWD'),
                (103, 'alice', '8000.00', 'expense', 'recurring', '房租', '2026-09-15', 1, 'TWD');
            INSERT INTO recurring_transaction_runs VALUES
                (10, '2026-09-15', 100), (20, '2026-09-15', 102), (30, '2026-09-15', 103);
        ''')
        self.store = IncomeReviewStore(self.conn)
        self.store.ensure_schema()
        self.store.index('alice', ['100', '101', '102', '103'])

    def apply(self, action, version=0, user='alice'):
        return self.store.apply(user, 10, '2026-09-15', action, version)

    def test_unchecked_income_already_counted_once(self):
        rows = self.store.index('alice', ['100'])
        self.assertEqual(rows[0]['status'], 'pending')
        self.assertEqual(self.db.execute('SELECT amount FROM accounting_transactions WHERE id=100').fetchone()[0], '30000.00')
        self.assertEqual(len(self.store.history('alice', '2026-09')), 1)

    def test_manual_notes_other_user_and_expense_never_match(self):
        self.assertEqual([r['transaction_id'] for r in self.store.index('alice', ['100', '101', '102', '103'])], ['100'])

    def test_confirm_does_not_insert_or_change_money(self):
        before = list(map(tuple, self.db.execute('SELECT * FROM accounting_transactions ORDER BY id')))
        row = self.apply('confirm')
        self.assertEqual((row['status'], row['version']), ('confirmed', 1))
        self.assertEqual(before, list(map(tuple, self.db.execute('SELECT * FROM accounting_transactions ORDER BY id'))))
        self.assertEqual(self.apply('confirm', 1)['version'], 1)

    def test_cancel_removes_only_this_period_and_keeps_run(self):
        self.apply('cancel')
        self.assertIsNone(self.db.execute('SELECT id FROM accounting_transactions WHERE id=100').fetchone())
        self.assertEqual(self.db.execute('SELECT COUNT(*) FROM accounting_transactions').fetchone()[0], 3)
        self.assertEqual(self.db.execute('SELECT transaction_id FROM recurring_transaction_runs WHERE rule_id=10').fetchone()[0], 100)
        self.assertEqual(self.db.execute('SELECT next_run_date FROM recurring_transactions_app WHERE id=10').fetchone()[0], '2026-10-15')

    def test_cancelled_occurrence_cannot_be_generated_again(self):
        self.apply('cancel')
        # Same UNIQUE insert used by the existing process-due implementation.
        c = self.db.execute("INSERT OR IGNORE INTO recurring_transaction_runs VALUES (10, '2026-09-15', NULL)")
        self.assertEqual(c.rowcount, 0)
        self.db.commit()
        self.assertEqual(self.store.history('alice', '2026-09')[0]['status'], 'cancelled')

    def test_restore_preserves_exact_row_and_confirmation(self):
        before = tuple(self.db.execute('SELECT * FROM accounting_transactions WHERE id=100').fetchone())
        self.apply('confirm')
        self.apply('cancel', 1)
        row = self.apply('restore', 2)
        self.assertEqual((row['status'], row['version']), ('confirmed', 3))
        self.assertEqual(tuple(self.db.execute('SELECT * FROM accounting_transactions WHERE id=100').fetchone()), before)
        self.apply('restore', 3)
        self.assertEqual(self.db.execute('SELECT COUNT(*) FROM accounting_transactions WHERE id=100').fetchone()[0], 1)

    def test_pending_can_cancel_restore_cancel(self):
        self.apply('cancel')
        self.assertEqual(self.apply('restore', 1)['status'], 'pending')
        self.assertEqual(self.apply('cancel', 2)['status'], 'cancelled')

    def test_stale_device_cannot_undo_newer_action(self):
        self.apply('cancel')
        with self.assertRaises(ReviewError) as cm: self.apply('confirm', 0)
        self.assertEqual(cm.exception.status, 409)
        self.assertIsNone(self.db.execute('SELECT id FROM accounting_transactions WHERE id=100').fetchone())

    def test_other_account_cannot_modify(self):
        with self.assertRaises(ReviewError) as cm: self.apply('cancel', user='bob')
        self.assertEqual(cm.exception.status, 404)
        self.assertIsNotNone(self.db.execute('SELECT id FROM accounting_transactions WHERE id=100').fetchone())

    def test_failed_delete_rolls_back_status_and_amount(self):
        self.db.execute("CREATE TRIGGER prevent_delete BEFORE DELETE ON accounting_transactions BEGIN SELECT RAISE(ABORT, 'simulated dependency'); END;")
        self.db.commit()
        with self.assertRaises(sqlite3.IntegrityError): self.apply('cancel')
        self.assertEqual(self.store.index('alice', ['100'])[0]['status'], 'pending')
        self.assertIsNotNone(self.db.execute('SELECT id FROM accounting_transactions WHERE id=100').fetchone())

    def test_failed_restore_does_not_lose_cancellation(self):
        self.apply('cancel')
        self.db.execute("INSERT INTO accounting_transactions VALUES (100, 'alice', '1', 'income', 'manual', 'id collision', '2026-09-16', 1, 'TWD')")
        self.db.commit()
        with self.assertRaises(sqlite3.IntegrityError): self.apply('restore', 1)
        self.assertEqual(self.store.history('alice', '2026-09')[0]['status'], 'cancelled')

    def test_deleted_or_changed_transaction_cannot_be_confirmed(self):
        self.db.execute("UPDATE accounting_transactions SET type='expense' WHERE id=100")
        self.db.commit()
        with self.assertRaises(ReviewError): self.apply('confirm')
        self.assertEqual(self.store.index('alice', ['100'])[0]['status'], 'pending')

    def test_bad_inputs_fail_without_writes(self):
        for bad in (['cancel'], None, 'delete'):
            with self.assertRaises(ReviewError): self.apply(bad)
        for bad in ('0', True, -1, None):
            with self.assertRaises(ReviewError): self.apply('cancel', bad)
        for ids in (['100 OR 1=1'], ['-1'], ['1'] * 501):
            with self.assertRaises(ReviewError): self.store.index('alice', ids)

    def test_calendar_and_decimal_snapshot(self):
        self.assertEqual(month_bounds('2026-12'), (date(2026, 12, 1), date(2027, 1, 1)))
        with self.assertRaises(ReviewError): month_bounds('2026-13')
        self.assertEqual(json.loads(json.dumps({'v': Decimal('12.3456')}, default=json_value))['v'], '12.3456')

    def test_route_requires_authenticated_user_before_db_access(self):
        class Blueprint:
            def __init__(self, name, module): self.name = name; self.routes = {}
            def route(self, path):
                def decorator(fn): self.routes[path] = fn; return fn
                return decorator
            post = get = route
        class App:
            blueprints = {}
            def register_blueprint(self, bp): self.blueprints[bp.name] = bp
        fake = types.ModuleType('flask')
        fake.Blueprint = Blueprint
        fake.jsonify = lambda **values: values
        fake.request = types.SimpleNamespace(get_json=lambda silent: {}, args={})
        calls = []
        app = App()
        with patch.dict(sys.modules, {'flask': fake}):
            register_recurring_income_review(app, lambda: calls.append('db'),
                lambda: (None, ({'status': 'error'}, 401)), lambda c: None)
            result = app.blueprints['pawpay_income_review'].routes['/api/recurring-income/reviews']()
        self.assertEqual(result[1], 401)
        self.assertEqual(calls, [])


class InstallerTests(unittest.TestCase):
    SOURCE = '''
def get_db_connection(): pass
def get_authenticated_user_id(): pass
def _ensure_app_extension_tables(c): pass
def process_due_recurring_transactions():
    return 'recurring_transaction_runs accounting_transactions accounting_categories entry_method'
if __name__ == '__main__':
    app.run(port=5000)
'''

    def test_registration_is_before_startup_and_idempotent(self):
        result = patched_source(self.SOURCE)
        self.assertLess(result.index(MARKER), result.index("if __name__"))
        self.assertEqual(patched_source(result), result)
        before = [ast.dump(n) for n in ast.parse(self.SOURCE).body if isinstance(n, ast.FunctionDef)]
        after = [ast.dump(n) for n in ast.parse(result).body if isinstance(n, ast.FunctionDef)]
        self.assertEqual(before, after)

    def test_unknown_backend_is_rejected(self):
        with self.assertRaises(ValueError): patched_source("print('different project')")


if __name__ == '__main__': unittest.main()
