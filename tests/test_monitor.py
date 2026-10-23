"""Offline regression tests. Never log in, send real greetings, or install jobs."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import MagicMock, patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("quota_monitor", ROOT / "monitor.py")
monitor = importlib.util.module_from_spec(spec)
spec.loader.exec_module(monitor)


def bucket(used=0, minutes=300, weekly=20):
    return {"primary": {"usedPercent": used, "windowDurationMins": minutes, "resetsAt": 20000},
            "secondary": {"usedPercent": weekly}}


class DecisionTests(unittest.TestCase):
    def test_decision_matrix(self):
        cases = [
            (bucket(), None, "send"),
            (bucket(1), None, "quota-in-use"),
            (bucket(0.01), None, "quota-in-use"),
            (bucket(-1), None, "quota-in-use"),
            (bucket(None), None, "missing-quota"),
            (bucket(True), None, "missing-quota"),
            (bucket(float("nan")), None, "missing-quota"),
            (bucket(float("inf")), None, "missing-quota"),
            ({}, None, "missing-quota"),
            (bucket(0, None), None, "missing-quota"),
            (bucket(0, 60), None, "unexpected-window"),
            (bucket(0, 300, 100), None, "weekly-limit"),
            (bucket(), {"blockUntil": 2000}, "already-attempted"),
            (bucket(), {"blockUntil": 1000}, "send"),
            (dict(bucket(), rateLimitReachedType="hard_limit"), None, "limit-reached"),
        ]
        for quota, state, expected in cases:
            with self.subTest(quota=quota, expected=expected):
                self.assertEqual(monitor.send_decision(quota, state, 1000), expected)


class WorkerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="codex-quota-unit-")
        self.root = Path(self.temp.name)
        self.state_path = self.root / "state-fixture.json"
        self.find = patch.object(monitor, "find_codex", return_value="fixture-codex")
        self.snapshot = patch.object(monitor, "read_snapshot", return_value=("fixture", bucket()))
        self.capability = patch.object(monitor, "check_capabilities")
        self.find.start()
        self.snapshot_mock = self.snapshot.start()
        self.capability_mock = self.capability.start()

    def tearDown(self):
        self.capability.stop()
        self.snapshot.stop()
        self.find.stop()
        self.temp.cleanup()

    def test_check_only_never_sends_or_writes_guard(self):
        with patch.object(monitor, "invoke_hello") as hello:
            self.assertEqual(monitor.run_once(self.root, check_only=True), "send")
            hello.assert_not_called()
            self.assertFalse(self.state_path.exists())

    def test_guard_is_written_before_greeting_and_survives_rounding(self):
        def verify_guard(*args):
            self.assertEqual(json.loads(self.state_path.read_text())["outcome"], "attempted")
        with patch.object(monitor, "invoke_hello", side_effect=verify_guard) as hello:
            self.assertEqual(monitor.run_once(self.root), "completed")
            self.assertEqual(monitor.run_once(self.root), "already-attempted")
            self.assertEqual(hello.call_count, 1)

    def test_ambiguous_failure_stays_blocked(self):
        with patch.object(monitor, "invoke_hello", side_effect=monitor.MonitorError("uncertain")) as hello:
            with self.assertRaises(monitor.MonitorError):
                monitor.run_once(self.root)
            self.assertEqual(monitor.run_once(self.root), "already-attempted")
            self.assertEqual(hello.call_count, 1)

    def test_offline_query_does_not_create_guard(self):
        self.snapshot_mock.side_effect = monitor.MonitorError("offline")
        with self.assertRaises(monitor.MonitorError):
            monitor.run_once(self.root)
        self.assertFalse(self.state_path.exists())

    def test_old_cli_does_not_reserve_a_window(self):
        self.capability_mock.side_effect = monitor.MonitorError("old CLI")
        with self.assertRaises(monitor.MonitorError):
            monitor.run_once(self.root)
        self.assertFalse(self.state_path.exists())

    def test_used_quota_never_sends(self):
        self.snapshot_mock.return_value = ("fixture", bucket(25))
        with patch.object(monitor, "invoke_hello") as hello:
            self.assertEqual(monitor.run_once(self.root), "quota-in-use")
            hello.assert_not_called()

    def test_corrupt_state_fails_closed(self):
        self.state_path.write_text("not JSON", encoding="utf-8")
        with patch.object(monitor, "invoke_hello") as hello:
            with self.assertRaises(monitor.MonitorError):
                monitor.run_once(self.root)
            hello.assert_not_called()

    def test_expired_guard_allows_new_window(self):
        monitor.write_state(self.state_path, {"blockUntil": 1, "outcome": "completed"})
        with patch.object(monitor, "invoke_hello") as hello:
            self.assertEqual(monitor.run_once(self.root), "completed")
            hello.assert_called_once()

    def test_success_guard_starts_after_response(self):
        with patch.object(monitor.time, "time", side_effect=[1000, 1020]), patch.object(monitor, "invoke_hello"):
            monitor.run_once(self.root)
        self.assertEqual(json.loads(self.state_path.read_text())["blockUntil"], 1020 + 18000)

    def test_another_process_cannot_enter_locked_check(self):
        self.root.mkdir(exist_ok=True)
        with monitor.FileLock(self.root / "running.lock"):
            self.assertEqual(monitor.run_once(self.root), "locked")
        self.snapshot_mock.assert_not_called()


class ProtocolTests(unittest.TestCase):
    def test_real_stdio_rpc_with_fixture_and_notifications(self):
        actual_session = monitor.CodexSession
        fixture = ROOT / "tests/fixtures/fake-app-server.py"
        with tempfile.TemporaryDirectory(prefix="codex-quota-rpc-") as temp:
            with patch.object(monitor, "CodexSession", side_effect=lambda command, cwd: actual_session([sys.executable, str(fixture)], cwd)):
                account_key, quota = monitor.read_snapshot("unused", Path(temp))
                self.assertEqual(len(account_key), 64)
                self.assertEqual(quota["primary"]["windowDurationMins"], 300)

    def test_greeting_forces_subscription_and_transmits_unicode(self):
        process = MagicMock()
        process.communicate.return_value = (monitor.HELLO + "\n", "")
        process.returncode = 0
        process.poll.return_value = 0
        with patch.object(monitor.subprocess, "Popen", return_value=process) as popen:
            monitor.invoke_hello("fixture-codex", ROOT)
        args = popen.call_args.args[0]
        self.assertIn("forced_login_method=chatgpt", args)
        self.assertIn("--ignore-user-config", args)
        self.assertIn("--ephemeral", args)
        self.assertIn("read-only", args)
        self.assertIn(monitor.HELLO, process.communicate.call_args.args[0])

    def test_unexpected_reply_is_not_marked_success(self):
        process = MagicMock()
        process.communicate.return_value = ("unexpected", "")
        process.returncode = 0
        process.poll.return_value = 0
        with patch.object(monitor.subprocess, "Popen", return_value=process):
            with self.assertRaises(monitor.MonitorError):
                monitor.invoke_hello("fixture-codex", ROOT)

    def test_unsupported_flags_are_rejected(self):
        result = subprocess.CompletedProcess([], 0, stdout="old flags")
        with patch.object(monitor.subprocess, "run", return_value=result):
            with self.assertRaises(monitor.MonitorError):
                monitor.check_capabilities("fixture-codex")


if __name__ == "__main__":
    unittest.main(verbosity=2)
