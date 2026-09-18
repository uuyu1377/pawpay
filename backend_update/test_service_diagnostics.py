import io
import json
from pathlib import Path
import sys
import tempfile
import types
import unittest
from unittest.mock import patch
import urllib.error

from check_income_service import diagnose
from recurring_income_review import register_recurring_income_review
from apply_update import main as install
import test_income_review as original_tests


class Reply(io.BytesIO):
    def __init__(self, body, status=200):
        super().__init__(json.dumps(body).encode())
        self.status = status


class DiagnosticsTests(unittest.TestCase):
    def test_v2_health_identifies_feature_without_private_data(self):
        seen = []
        def opener(request, timeout):
            seen.append(request)
            return Reply({'service': 'pawpay_recurring_income_review', 'api_version': 2})
        code, message = diagnose('http://example.test:5000', opener)
        self.assertEqual(code, 0)
        self.assertIn('2', message)
        self.assertEqual(seen[0].get_method(), 'GET')
        self.assertNotIn('Authorization', seen[0].headers)

    def test_missing_endpoints_report_install_and_restart(self):
        def opener(request, timeout):
            raise urllib.error.HTTPError(request.full_url, 404, '', {}, io.BytesIO(b'<html>404</html>'))
        code, message = diagnose('http://example.test:5000', opener)
        self.assertEqual(code, 2)
        self.assertIn('apply_update.py', message)

    def test_v1_is_not_misreported_as_missing(self):
        def opener(request, timeout):
            status = 404 if request.full_url.endswith('/health') else 401
            body = json.dumps({'status': 'error', 'message': '缺少登入 Token'}).encode()
            raise urllib.error.HTTPError(request.full_url, status, '', {}, io.BytesIO(body))
        self.assertEqual(diagnose('http://example.test:5000', opener)[0], 0)

    def test_unrelated_http_success_is_not_a_healthy_feature(self):
        self.assertEqual(diagnose('http://example.test', lambda *a, **k: Reply({'status': 'up'}))[0], 1)

    def test_credentials_in_url_are_rejected(self):
        with self.assertRaises(ValueError): diagnose('http://name:secret@example.test')

    def test_module_upgrade_preserves_original_app_functions_and_old_module(self):
        with tempfile.TemporaryDirectory() as tmp:
            app = Path(tmp) / 'app.py'
            app.write_text(original_tests.InstallerTests.SOURCE)
            old_module = Path(tmp) / 'recurring_income_review.py'
            old_module.write_text('# old extension\n')
            with patch.object(sys, 'argv', ['apply_update.py', str(app)]), patch('sys.stdout', io.StringIO()):
                install()
                first = app.read_bytes()
                install()
            self.assertEqual(app.read_bytes(), first)
            self.assertEqual(len(list(Path(tmp).glob('app.py.before_*.bak'))), 1)
            self.assertEqual(len(list(Path(tmp).glob('recurring_income_review.py.before_*.bak'))), 1)
            self.assertIn('API_VERSION = 2', old_module.read_text())


class EndpointTests(unittest.TestCase):
    def register(self, connection, auth):
        class Blueprint:
            def __init__(self, name, module): self.name = name; self.routes = {}
            def route(self, path):
                def decorate(fn): self.routes[path] = fn; return fn
                return decorate
            get = post = route
        class App:
            def __init__(self):
                self.blueprints = {}
                self.logger = types.SimpleNamespace(exception=lambda *a: None)
            def register_blueprint(self, bp): self.blueprints[bp.name] = bp
        fake = types.ModuleType('flask')
        fake.Blueprint = Blueprint
        fake.jsonify = lambda **values: values
        fake.request = types.SimpleNamespace(get_json=lambda silent: {}, args={})
        app = App()
        with patch.dict(sys.modules, {'flask': fake}):
            register_recurring_income_review(app, connection, auth, lambda cursor: None)
        return app.blueprints['pawpay_income_review'].routes

    def test_health_does_not_touch_auth_or_database(self):
        def never(): raise AssertionError('must not be called')
        routes = self.register(never, never)
        self.assertEqual(routes['/api/recurring-income/health']()['api_version'], 2)

    def test_database_failure_has_distinct_code_and_hides_internal_exception(self):
        def connection(): raise OSError('private credentials here')
        routes = self.register(connection, lambda: ('alice', None))
        result, status = routes['/api/recurring-income/reviews']()
        self.assertEqual(status, 503)
        self.assertEqual(result['code'], 'review_database_unavailable')
        self.assertNotIn('private', str(result))


if __name__ == '__main__':
    unittest.main()
