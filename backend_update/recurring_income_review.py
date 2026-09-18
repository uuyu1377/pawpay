"""PAWPAY fixed-income review extension for the existing Flask/MySQL backend.

Only accounting rows created by recurring_transaction_runs are eligible.
The run tombstone is retained on cancellation; process-due therefore cannot
recreate it. Registration adds routes; existing routes and credentials stay put.
"""
from datetime import date, datetime
from decimal import Decimal
import json
import re

API_VERSION = 2


class ReviewError(Exception):
    def __init__(self, message, status=409):
        super().__init__(message)
        self.status = status


def json_value(value):
    if isinstance(value, Decimal):
        return str(value)
    if isinstance(value, (date, datetime)):
        return value.isoformat()
    raise TypeError(f'Unsupported accounting value: {type(value).__name__}')


def public_review(row):
    return {
        'rule_id': int(row['rule_id']),
        'scheduled_date': str(row['scheduled_date'])[:10],
        'transaction_id': str(row['transaction_id']),
        'status': row['status'],
        'version': int(row['version']),
        'category_name': row.get('category_name') or '固定收入',
        'amount': str(row.get('amount') or '0'),
        'currency': row.get('currency') or 'TWD',
        'note': row.get('note') or '',
    }


def month_bounds(value):
    if not re.fullmatch(r'\d{4}-\d{2}', str(value or '')):
        raise ReviewError('月份格式必須是 YYYY-MM', 400)
    try:
        first = date.fromisoformat(value + '-01')
        end = date(first.year + (first.month == 12), first.month % 12 + 1, 1)
    except ValueError:
        raise ReviewError('月份無效', 400)
    return first, end


class IncomeReviewStore:
    def __init__(self, connection):
        self.conn = connection

    def ensure_schema(self):
        # DDL must complete before begin(): MySQL CREATE TABLE may commit.
        with self.conn.cursor() as c:
            c.execute("""
                CREATE TABLE IF NOT EXISTS recurring_income_reviews (
                    rule_id BIGINT NOT NULL,
                    scheduled_date DATE NOT NULL,
                    user_id VARCHAR(64) NOT NULL,
                    transaction_id BIGINT NOT NULL,
                    status VARCHAR(16) NOT NULL DEFAULT 'pending',
                    previous_status VARCHAR(16) NOT NULL DEFAULT 'pending',
                    version INT NOT NULL DEFAULT 0,
                    snapshot LONGTEXT NULL,
                    category_name VARCHAR(120) NOT NULL,
                    amount DECIMAL(18,4) NOT NULL,
                    currency VARCHAR(8) NOT NULL DEFAULT 'TWD',
                    note TEXT NULL,
                    PRIMARY KEY (rule_id, scheduled_date),
                    INDEX idx_rir_user_tx (user_id, transaction_id),
                    INDEX idx_rir_user_month (user_id, scheduled_date)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
            """)
        self.conn.commit()

    def _discover(self, c, user_id):
        # Use the actual run -> transaction relationship, never a note/amount
        # heuristic. Historical income still works after a rule is edited.
        c.execute("""
            INSERT IGNORE INTO recurring_income_reviews
                (rule_id, scheduled_date, user_id, transaction_id,
                 category_name, amount, currency, note)
            SELECT r.rule_id, r.scheduled_date, t.user_id, t.id,
                   COALESCE(cat.name, '固定收入'), t.amount,
                   COALESCE(t.currency, 'TWD'), t.note
            FROM recurring_transaction_runs r
            JOIN accounting_transactions t ON t.id = r.transaction_id
            LEFT JOIN accounting_categories cat ON cat.id = t.category_id
            WHERE t.user_id = %s AND t.type = 'income'
              AND t.entry_method = 'recurring'
        """, (user_id,))

    def index(self, user_id, transaction_ids):
        if not isinstance(transaction_ids, list) or len(transaction_ids) > 500:
            raise ReviewError('交易清單無效', 400)
        ids = []
        for value in transaction_ids:
            if not re.fullmatch(r'[1-9]\d{0,18}', str(value)):
                raise ReviewError('交易編號無效', 400)
            ids.append(int(value))
        if not ids:
            return []
        try:
            self.conn.begin()
            with self.conn.cursor() as c:
                self._discover(c, user_id)
                placeholders = ','.join(['%s'] * len(ids))
                c.execute(f"""
                    SELECT * FROM recurring_income_reviews
                    WHERE user_id = %s AND transaction_id IN ({placeholders})
                """, (user_id, *ids))
                rows = c.fetchall()
            self.conn.commit()
            return [public_review(row) for row in rows]
        except Exception:
            self.conn.rollback()
            raise

    def history(self, user_id, month):
        first, end = month_bounds(month)
        try:
            self.conn.begin()
            with self.conn.cursor() as c:
                self._discover(c, user_id)
                c.execute("""
                    SELECT * FROM recurring_income_reviews
                    WHERE user_id = %s AND scheduled_date >= %s AND scheduled_date < %s
                    ORDER BY scheduled_date DESC, rule_id
                """, (user_id, first, end))
                rows = c.fetchall()
            self.conn.commit()
            return [public_review(row) for row in rows]
        except Exception:
            self.conn.rollback()
            raise

    def apply(self, user_id, rule_id, scheduled_date, action, expected_version):
        if not isinstance(action, str) or action not in {'confirm', 'cancel', 'restore'}:
            raise ReviewError('操作無效', 400)
        if type(expected_version) is not int or expected_version < 0:
            raise ReviewError('缺少有效版本，請重新載入', 400)
        try:
            scheduled = date.fromisoformat(scheduled_date)
        except (ValueError, TypeError):
            raise ReviewError('日期無效', 400)
        try:
            self.conn.begin()
            with self.conn.cursor() as c:
                c.execute("""
                    SELECT * FROM recurring_income_reviews
                    WHERE rule_id = %s AND scheduled_date = %s AND user_id = %s
                    FOR UPDATE
                """, (rule_id, scheduled, user_id))
                row = c.fetchone()
                if not row:
                    raise ReviewError('找不到這筆固定收入，請重新載入', 404)
                state = row['status']
                if expected_version != int(row['version']):
                    raise ReviewError('這筆收入已在其他地方更新，請重新載入')
                if action == 'confirm' and state == 'cancelled':
                    raise ReviewError('這一期已取消，請先復原')
                target = {'confirm': 'confirmed', 'cancel': 'cancelled',
                          'restore': row['previous_status']}[action]
                if action == 'restore' and state != 'cancelled':
                    # A second restore must never insert a second transaction.
                    return self._finish(row)
                if state == target:
                    return self._finish(row)

                if action in {'confirm', 'cancel'}:
                    c.execute("""
                        SELECT * FROM accounting_transactions
                        WHERE id = %s AND user_id = %s FOR UPDATE
                    """, (row['transaction_id'], user_id))
                    tx = c.fetchone()
                    if not tx or tx['type'] != 'income' or tx['entry_method'] != 'recurring':
                        raise ReviewError('原始收入已刪除或變更，請重新載入')
                    if action == 'cancel':
                        snapshot = json.dumps(tx, default=json_value, ensure_ascii=False)
                        c.execute("""
                            DELETE FROM accounting_transactions WHERE id = %s AND user_id = %s
                        """, (row['transaction_id'], user_id))
                        if c.rowcount != 1:
                            raise ReviewError('撤銷未完成，請重新載入')
                        c.execute("""
                            UPDATE recurring_income_reviews
                            SET snapshot = %s, previous_status = %s, amount = %s,
                                currency = %s, note = %s
                            WHERE rule_id = %s AND scheduled_date = %s AND user_id = %s
                        """, (snapshot, state, tx['amount'], tx.get('currency') or 'TWD',
                              tx.get('note'), rule_id, scheduled, user_id))
                else:
                    snapshot = json.loads(row['snapshot'] or '{}')
                    if (str(snapshot.get('user_id')) != str(user_id)
                            or str(snapshot.get('id')) != str(row['transaction_id'])
                            or snapshot.get('type') != 'income'
                            or snapshot.get('entry_method') != 'recurring'):
                        raise ReviewError('復原資料不完整，請聯絡專題管理者')
                    c.execute('SHOW COLUMNS FROM accounting_transactions')
                    fields = {f['Field'] for f in c.fetchall()
                              if 'GENERATED' not in str(f.get('Extra', '')).upper()}
                    # Identifiers come from SHOW COLUMNS; values stay parameterized.
                    columns = [key for key in snapshot if key in fields]
                    if not {'id', 'user_id', 'amount', 'type', 'entry_method'}.issubset(columns):
                        raise ReviewError('資料表結構已變更，暫時無法復原')
                    names = ','.join('`' + key.replace('`', '``') + '`' for key in columns)
                    placeholders = ','.join(['%s'] * len(columns))
                    c.execute(f'INSERT INTO accounting_transactions ({names}) VALUES ({placeholders})',
                              tuple(snapshot[key] for key in columns))

                c.execute("""
                    UPDATE recurring_income_reviews SET status = %s, version = version + 1
                    WHERE rule_id = %s AND scheduled_date = %s AND user_id = %s
                """, (target, rule_id, scheduled, user_id))
                c.execute("""
                    SELECT * FROM recurring_income_reviews
                    WHERE rule_id = %s AND scheduled_date = %s AND user_id = %s
                """, (rule_id, scheduled, user_id))
                result = public_review(c.fetchone())
            self.conn.commit()
            return result
        except Exception:
            self.conn.rollback()
            raise

    def _finish(self, row):
        self.conn.commit()
        return public_review(row)


def register_recurring_income_review(app, get_db_connection,
                                    get_authenticated_user_id,
                                    ensure_base_tables):
    """Call before app.run(), using the existing app's four objects."""
    from flask import Blueprint, jsonify, request
    if 'pawpay_income_review' in app.blueprints:
        return
    bp = Blueprint('pawpay_income_review', __name__)

    @bp.get('/api/recurring-income/health')
    def health():
        # Public capability check only. No user information or DB access.
        return jsonify(status='success', service='pawpay_recurring_income_review',
                       api_version=API_VERSION, requires_login=True)

    def run(operation):
        user_id, error = get_authenticated_user_id()
        if error is not None:
            return error
        if not user_id:
            return jsonify(status='error', message='請先登入'), 401
        conn = None
        phase = 'connect'
        try:
            conn = get_db_connection()
            phase = 'schema'
            with conn.cursor() as c:
                ensure_base_tables(c)
            conn.commit()
            store = IncomeReviewStore(conn)
            store.ensure_schema()
            phase = 'operation'
            result = operation(store, str(user_id))
            return jsonify(status='success', **result)
        except ReviewError as e:
            return jsonify(status='error', message=str(e),
                           code='review_conflict' if e.status == 409 else 'review_request_error'), e.status
        except Exception:
            if conn is not None:
                conn.rollback()
            app.logger.exception('Fixed income review failed')
            return jsonify(status='error', message='固定收入更新失敗，請稍後重試',
                           code='review_database_unavailable' if phase in {'connect', 'schema'}
                           else 'review_operation_failed'), 503 if phase == 'connect' else 500
        finally:
            if conn is not None:
                conn.close()

    @bp.post('/api/recurring-income/reviews')
    def index():
        data = request.get_json(silent=True) or {}
        if not isinstance(data, dict):
            return jsonify(status='error', message='請求格式無效'), 400
        return run(lambda store, user: {'reviews': store.index(user, data.get('transaction_ids', []))})

    @bp.get('/api/recurring-income/history')
    def history():
        month = request.args.get('month', date.today().strftime('%Y-%m'))
        return run(lambda store, user: {'reviews': store.history(user, month)})

    @bp.post('/api/recurring-income/<int:rule_id>/<scheduled_date>/review')
    def review(rule_id, scheduled_date):
        data = request.get_json(silent=True) or {}
        if not isinstance(data, dict):
            return jsonify(status='error', message='請求格式無效'), 400
        return run(lambda store, user: {'review': store.apply(
            user, rule_id, scheduled_date, data.get('action'), data.get('expected_version'))})

    app.register_blueprint(bp)
