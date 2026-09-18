from pathlib import Path
import tempfile
import types
import unittest
from install_on_server import install


class InteractiveInstallerTests(unittest.TestCase):
    def test_failed_compatibility_check_never_runs_write_step(self):
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / 'app.py'
            app.write_text('# different backend')
            calls = []
            def runner(command, check):
                calls.append(command)
                return types.SimpleNamespace(returncode=1)
            self.assertEqual(install(app, runner), 1)
            self.assertEqual(len(calls), 1)
            self.assertEqual(calls[0][-1], '--check')
            self.assertEqual(app.read_text(), '# different backend')

    def test_path_with_spaces_is_one_argument_and_not_shell_code(self):
        with tempfile.TemporaryDirectory(prefix='backend test ') as directory:
            app = Path(directory) / 'app.py'
            app.touch()
            calls = []
            def runner(command, check):
                calls.append(command)
                return types.SimpleNamespace(returncode=0)
            self.assertEqual(install(app, runner), 0)
            self.assertEqual(len(calls), 2)
            self.assertEqual(calls[1][-1], str(app.resolve()))

    def test_flutter_file_is_rejected(self):
        with self.assertRaises(ValueError):
            install('lib/main.dart')


if __name__ == '__main__':
    unittest.main()
