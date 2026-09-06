#!/usr/bin/env python3
"""フォントだけの更新、再実行、起動中の更新拒否を確認する。"""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).with_name('apply-orca-settings.py')


class OrcaSettingsTest(unittest.TestCase):
    def test_partial_update_and_running_app(self):
        with tempfile.TemporaryDirectory(prefix='orca-test-') as directory:
            root = Path(directory)
            profile = root / 'profiles' / 'local-default'
            profile.mkdir(parents=True)
            (root / 'orca-profile-index.json').write_text(json.dumps({
                'activeProfileId': 'local-default', 'profiles': [{'id': 'local-default'}]}))
            state = {'settings': {'terminalFontFamily': 'Moralerspace Neon',
                                 'terminalFontSize': 20, 'theme': 'light'},
                     'privateValue': 'do-not-print', 'sessions': ['keep-session']}
            data_file = profile / 'orca-data.json'
            data_file.write_text(json.dumps(state))
            config = root / 'settings.json'
            config.write_text(json.dumps({'terminalFontFamily': 'Moralerspace Neon HW', 'terminalFontSize': 21}))

            def run(*args):
                result = subprocess.run(['python3', str(SCRIPT), str(config), *args],
                                        env={**os.environ, 'ORCA_USER_DATA_PATH': directory},
                                        capture_output=True, text=True, timeout=10)
                self.assertNotIn('do-not-print', result.stdout + result.stderr)
                return result

            result = run()
            self.assertEqual(result.returncode, 0, result.stderr)
            state['settings'].update({'terminalFontFamily': 'Moralerspace Neon HW', 'terminalFontSize': 21})
            self.assertEqual(json.loads(data_file.read_text()), state)
            stamp = data_file.stat().st_mtime_ns
            self.assertEqual(run().returncode, 0)
            self.assertEqual(data_file.stat().st_mtime_ns, stamp)

            # 起動中に管理値が変わっても、保存ファイルを上書きしない。
            (root / 'orca-runtime.json').write_text(json.dumps({'pid': os.getpid()}))
            self.assertEqual(run().returncode, 0)
            config.write_text(json.dumps({'terminalFontFamily': 'different-font', 'terminalFontSize': 21}))
            self.assertNotEqual(run().returncode, 0)
            self.assertEqual(run('--allow-skip').returncode, 0)
            self.assertEqual(json.loads(data_file.read_text()), state)
            self.assertEqual(data_file.stat().st_mtime_ns, stamp)


if __name__ == '__main__':
    unittest.main()
