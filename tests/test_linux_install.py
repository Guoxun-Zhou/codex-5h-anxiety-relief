"""Linux installer tests using fake Codex and fake schedulers, never real jobs."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipIf(os.name == "nt", "Linux shell integration")
class LinuxInstallTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="quota installer ")
        self.root = Path(self.temp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ["PATH"],
                        XDG_CONFIG_HOME=str(self.root / "config"), XDG_DATA_HOME=str(self.root / "data"),
                        XDG_STATE_HOME=str(self.root / "state"), QUOTA_HELLO_DATA=str(self.root / "quota state"),
                        QUOTA_TEST_CRONTAB=str(self.root / "crontab"), QUOTA_TEST_SYSTEMD="0")
        self.stub("codex", (ROOT / "tests/fixtures/fake-app-server.py").read_text())
        self.stub("crontab", '''import os, pathlib, sys
p = pathlib.Path(os.environ['QUOTA_TEST_CRONTAB'])
if '-l' in sys.argv:
    if os.environ.get('QUOTA_TEST_CRON_ERROR'):
        print('permission denied', file=sys.stderr); sys.exit(2)
    if not p.exists():
        print('no crontab for fixture', file=sys.stderr); sys.exit(1)
    print(p.read_text(), end='')
else:
    p.write_text(sys.stdin.read())
''')
        self.stub("systemctl", '''import os, sys
sys.exit(0 if os.environ['QUOTA_TEST_SYSTEMD'] == '1' else 1)
''')
        (self.root / "crontab").write_text("0 9 * * * echo unrelated-job\n")

    def stub(self, name, body):
        target = self.bin / name
        target.write_text("#!/usr/bin/env python3\n" + body, encoding="utf-8")
        target.chmod(0o700)

    def run_script(self, script, *args):
        result = subprocess.run(["bash", str(ROOT / script), *args], env=self.env,
                                capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def tearDown(self):
        self.temp.cleanup()

    def test_cron_install_update_and_uninstall_preserve_other_jobs(self):
        self.run_script("setup.sh", "--cron")
        self.run_script("setup.sh", "--cron")
        cron = (self.root / "crontab").read_text()
        self.assertEqual(cron.count("# codex-quota-hello"), 1)
        self.assertIn("unrelated-job", cron)
        self.assertIn("*/5 * * * *", cron)
        runner = self.root / "data/codex-quota-hello/run-once.sh"
        self.assertTrue(runner.exists())
        self.run_script("uninstall.sh")
        self.assertNotIn("# codex-quota-hello", (self.root / "crontab").read_text())
        self.assertIn("unrelated-job", (self.root / "crontab").read_text())
        self.assertTrue(runner.exists())

    def test_systemd_generates_quoted_units_then_removes_them(self):
        self.env["QUOTA_TEST_SYSTEMD"] = "1"
        self.run_script("setup.sh", "--systemd")
        config = self.root / "config/systemd/user"
        service = (config / "codex-quota-hello.service").read_text()
        timer = (config / "codex-quota-hello.timer").read_text()
        self.assertIn('ExecStart=/bin/bash "', service)
        self.assertIn("OnUnitActiveSec=5min", timer)
        self.run_script("uninstall.sh")
        self.assertFalse((config / "codex-quota-hello.timer").exists())
        self.assertFalse((config / "codex-quota-hello.service").exists())

    def test_crontab_read_failure_never_overwrites_unrelated_jobs(self):
        self.env['QUOTA_TEST_CRON_ERROR'] = '1'
        before = (self.root / 'crontab').read_text()
        for script in ('setup.sh', 'uninstall.sh'):
            result = subprocess.run(['bash', str(ROOT / script), '--cron'] if script == 'setup.sh' else ['bash', str(ROOT / script)],
                                    env=self.env, capture_output=True, text=True, timeout=30)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('refusing to replace', result.stderr)
            self.assertEqual((self.root / 'crontab').read_text(), before)


if __name__ == "__main__":
    unittest.main(verbosity=2)
