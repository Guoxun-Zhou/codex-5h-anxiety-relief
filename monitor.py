#!/usr/bin/env python3
"""Codex quota-triggered greetings. Python standard library only."""
from __future__ import annotations

import argparse
import contextlib
import hashlib
import json
import logging
from logging.handlers import RotatingFileHandler
import math
import os
from pathlib import Path
import queue
import shutil
import signal
import subprocess
import sys
import threading
import time

VERSION = "1.0.0"
INTERVAL = 300
WINDOW_SECONDS = 18000
HELLO = "\u4f60\u597d"
LOG = logging.getLogger("codex-quota-hello")


class MonitorError(RuntimeError):
    pass


def default_data_dir() -> Path:
    if os.environ.get("QUOTA_HELLO_DATA"):
        return Path(os.environ["QUOTA_HELLO_DATA"]).expanduser().resolve()
    if os.name == "nt":
        return Path(os.environ.get("LOCALAPPDATA", Path.home() / "AppData/Local")) / "CodexQuotaHello"
    return Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "codex-quota-hello"


def configure_logging(root: Path) -> None:
    root.mkdir(parents=True, exist_ok=True)
    LOG.setLevel(logging.INFO)
    for handler in list(LOG.handlers):
        handler.close()
        LOG.removeHandler(handler)
    formatter = logging.Formatter("%(asctime)s %(levelname)s %(message)s")
    file_handler = RotatingFileHandler(root / "monitor.log", maxBytes=1048576, backupCount=3, encoding="utf-8")
    stream_handler = logging.StreamHandler(sys.stdout)
    for handler in (file_handler, stream_handler):
        handler.setFormatter(formatter)
        LOG.addHandler(handler)


def find_codex(explicit: str | None = None) -> str:
    candidates: list[str] = []
    if explicit:
        candidates.append(explicit)
    command = shutil.which("codex.exe" if os.name == "nt" else "codex")
    if command:
        candidates.append(command)
    if os.name == "nt":
        bundled = Path(os.environ.get("LOCALAPPDATA", "")) / "OpenAI/Codex/bin"
        if bundled.is_dir():
            candidates.extend(str(p) for p in sorted(bundled.glob("*/codex.exe"), key=lambda p: p.stat().st_mtime, reverse=True))
    for candidate in candidates:
        path = Path(candidate).expanduser()
        if path.is_file() and (os.name == "nt" or os.access(path, os.X_OK)):
            return str(path.resolve())
    raise MonitorError("Codex CLI not found. Install it first, or pass --codex /absolute/path/to/codex.")


def process_options() -> dict:
    if os.name == "nt":
        return {"creationflags": subprocess.CREATE_NO_WINDOW}
    return {"start_new_session": True}


def stop_process(process: subprocess.Popen) -> None:
    if process.poll() is not None:
        return
    with contextlib.suppress(OSError):
        if os.name == "nt":
            process.terminate()
        else:
            os.killpg(process.pid, signal.SIGTERM)
    try:
        process.wait(timeout=2)
    except subprocess.TimeoutExpired:
        with contextlib.suppress(OSError):
            if os.name == "nt":
                process.kill()
            else:
                os.killpg(process.pid, signal.SIGKILL)
        with contextlib.suppress(subprocess.TimeoutExpired):
            process.wait(timeout=2)


class CodexSession:
    def __init__(self, command: list[str], cwd: Path):
        self.process = subprocess.Popen(command, cwd=cwd, stdin=subprocess.PIPE,
                                        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                        text=True, encoding="utf-8", errors="replace",
                                        bufsize=1, **process_options())
        self.messages: queue.Queue = queue.Queue()
        self.sequence = 0
        self.readers = [threading.Thread(target=self._read_stdout, daemon=True),
                        threading.Thread(target=self._drain_stderr, daemon=True)]
        for reader in self.readers:
            reader.start()

    def _read_stdout(self) -> None:
        try:
            for line in self.process.stdout:
                try:
                    self.messages.put(json.loads(line))
                except (ValueError, TypeError):
                    continue
        finally:
            self.messages.put(None)

    def _drain_stderr(self) -> None:
        # Do not log the upstream stderr stream: it may include local context.
        for _ in self.process.stderr:
            pass

    def notify(self, method: str, params: dict) -> None:
        try:
            self.process.stdin.write(json.dumps({"method": method, "params": params}) + "\n")
            self.process.stdin.flush()
        except (OSError, ValueError) as error:
            raise MonitorError("Codex app-server connection closed.") from error

    def rpc(self, method: str, params: dict | None = None, timeout: float = 35) -> dict:
        self.sequence += 1
        expected = self.sequence
        payload = {"id": expected, "method": method, "params": params or {}}
        try:
            self.process.stdin.write(json.dumps(payload) + "\n")
            self.process.stdin.flush()
        except (OSError, ValueError) as error:
            raise MonitorError("Codex app-server connection closed.") from error
        deadline = time.monotonic() + timeout
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise MonitorError("Quota request timed out: " + method)
            try:
                message = self.messages.get(timeout=remaining)
            except queue.Empty as error:
                raise MonitorError("Quota request timed out: " + method) from error
            if message is None:
                raise MonitorError("Codex closed its connection: " + method)
            if isinstance(message, dict) and message.get("id") == expected:
                if message.get("error"):
                    code = message["error"].get("code", "unknown")
                    raise MonitorError(f"Codex request failed: {method}; code={code}")
                result = message.get("result")
                if not isinstance(result, dict):
                    raise MonitorError("Invalid response: " + method)
                return result

    def close(self) -> None:
        with contextlib.suppress(OSError, ValueError):
            self.process.stdin.close()
        stop_process(self.process)
        for reader in self.readers:
            reader.join(timeout=2)
        for stream in (self.process.stdout, self.process.stderr):
            with contextlib.suppress(OSError, ValueError):
                stream.close()


def read_snapshot(executable: str, workspace: Path) -> tuple[str, dict]:
    session = CodexSession([executable, "app-server"], workspace)
    try:
        session.rpc("initialize", {"clientInfo": {"name": "codex_quota_hello", "title": "Codex Quota Hello", "version": VERSION}})
        session.notify("initialized", {})
        account = session.rpc("account/read", {"refreshToken": False}).get("account")
        if not isinstance(account, dict) or account.get("type") != "chatgpt":
            raise MonitorError("Sign in with your ChatGPT subscription account first: codex login")
        identity = account.get("id") or account.get("email")
        if not isinstance(identity, str) or not identity:
            raise MonitorError("Account identity unavailable; refusing to mix account state.")
        account_key = hashlib.sha256(identity.encode("utf-8")).hexdigest()
        limits = session.rpc("account/rateLimits/read")
        if limits.get("rateLimitsByLimitId") is not None:
            buckets = limits["rateLimitsByLimitId"]
            bucket = buckets.get("codex") if isinstance(buckets, dict) else None
        else:
            bucket = limits.get("rateLimits")
            if isinstance(bucket, dict) and bucket.get("limitId") not in (None, "codex"):
                bucket = None
        if not isinstance(bucket, dict):
            raise MonitorError("Codex usage meter unavailable.")
        return account_key, bucket
    finally:
        session.close()


def is_number(value) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def send_decision(bucket: dict, state: dict | None, now: int) -> str:
    primary = bucket.get("primary")
    if not isinstance(primary, dict) or not is_number(primary.get("usedPercent")) or not is_number(primary.get("windowDurationMins")):
        return "missing-quota"
    if primary["windowDurationMins"] != 300:
        return "unexpected-window"
    secondary = bucket.get("secondary")
    if isinstance(secondary, dict) and is_number(secondary.get("usedPercent")) and secondary["usedPercent"] >= 100:
        return "weekly-limit"
    if bucket.get("rateLimitReachedType"):
        return "limit-reached"
    if state and state["blockUntil"] > now:
        return "already-attempted"
    if primary["usedPercent"] != 0:
        return "quota-in-use"
    return "send"


class FileLock:
    def __init__(self, path: Path):
        self.path = path
        self.handle = None

    def __enter__(self):
        self.handle = self.path.open("a+b")
        try:
            if os.name == "nt":
                import msvcrt
                if self.path.stat().st_size == 0:
                    self.handle.write(b"0")
                    self.handle.flush()
                self.handle.seek(0)
                msvcrt.locking(self.handle.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                import fcntl
                fcntl.flock(self.handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            self.handle.close()
            self.handle = None
            raise
        return self

    def __exit__(self, *args):
        if self.handle is not None:
            self.handle.close()


def write_state(path: Path, value: dict) -> None:
    temporary = path.with_suffix(".json.tmp")
    temporary.write_text(json.dumps(value, indent=2), encoding="utf-8")
    os.replace(temporary, path)


def load_state(path: Path) -> dict | None:
    if not path.exists():
        return None
    try:
        state = json.loads(path.read_text(encoding="utf-8-sig"))
        if not isinstance(state, dict) or not is_number(state.get("blockUntil")) or state["blockUntil"] <= 0:
            raise ValueError("invalid guard")
        return state
    except (ValueError, OSError) as error:
        raise MonitorError("Invalid state file; refusing to send. Check the troubleshooting guide.") from error


def check_capabilities(executable: str) -> None:
    try:
        result = subprocess.run([executable, "exec", "--help"], capture_output=True, text=True,
                                encoding="utf-8", errors="replace", timeout=15, **process_options())
    except subprocess.TimeoutExpired as error:
        raise MonitorError("Codex version check timed out.") from error
    if result.returncode or any(flag not in result.stdout for flag in ("--ignore-user-config", "--ephemeral")):
        raise MonitorError("Update Codex: --ignore-user-config and --ephemeral are required.")


def invoke_hello(executable: str, workspace: Path) -> None:
    arguments = [executable, "exec", "--ignore-user-config", "--skip-git-repo-check", "--ephemeral",
                 "--sandbox", "read-only", "-c", "approval_policy=never", "-c", "forced_login_method=chatgpt",
                 "-c", "model_reasoning_effort=low", "-c", "project_doc_max_bytes=0", "-"]
    process = subprocess.Popen(arguments, cwd=workspace, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, text=True, encoding="utf-8", errors="replace", **process_options())
    try:
        output, _ = process.communicate(f"Reply with exactly these two characters: {HELLO}. Do not use tools or inspect files.\n", timeout=120)
        if process.returncode:
            raise MonitorError(f"Greeting failed; exit={process.returncode}. Retry remains blocked for this window.")
        if output.strip() != HELLO:
            raise MonitorError("Unexpected greeting output. Retry remains blocked for this window.")
    except subprocess.TimeoutExpired as error:
        raise MonitorError("Greeting timed out; it may have arrived. Retry remains blocked for this window.") from error
    finally:
        stop_process(process)
        for stream in (process.stdin, process.stdout, process.stderr):
            with contextlib.suppress(OSError, ValueError):
                stream.close()


def run_once(root: Path, explicit: str | None = None, check_only: bool = False) -> str:
    root.mkdir(parents=True, exist_ok=True)
    workspace = root / "empty-workspace"
    workspace.mkdir(exist_ok=True)
    lock = FileLock(root / "running.lock")
    try:
        lock.__enter__()
    except OSError:
        LOG.info("A check is already running, or the lock is unavailable; skipped.")
        return "locked"
    try:
        executable = find_codex(explicit)
        account_key, bucket = read_snapshot(executable, workspace)
        state_path = root / f"state-{account_key}.json"
        state = load_state(state_path)
        now = int(time.time())
        decision = send_decision(bucket, state, now)
        primary = bucket.get("primary")
        if not isinstance(primary, dict):
            primary = {}
        used = primary.get("usedPercent")
        remaining = max(0, min(100, 100 - used)) if is_number(used) else "unknown"
        LOG.info("remaining=%s%%; resetEpoch=%s; decision=%s; checkOnly=%s", remaining, primary.get("resetsAt", "unknown"), decision, check_only)
        if check_only or decision != "send":
            return decision
        check_capabilities(executable)
        state = {"attemptAt": now, "blockUntil": now + WINDOW_SECONDS + INTERVAL, "outcome": "attempted"}
        write_state(state_path, state)
        invoke_hello(executable, workspace)
        state.update(outcome="completed", blockUntil=int(time.time()) + WINDOW_SECONDS)
        write_state(state_path, state)
        LOG.info("Greeting completed. No further greeting attempt for at least five hours.")
        return "completed"
    finally:
        lock.__exit__()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Codex 5-hour reset anxiety relief")
    parser.add_argument("--version", action="version", version=VERSION)
    parser.add_argument("--data-dir", type=Path, default=default_data_dir())
    parser.add_argument("--codex", help="Absolute path to the Codex executable")
    subcommands = parser.add_subparsers(dest="command", required=True)
    subcommands.add_parser("check", help="Read quota only; never send a greeting")
    subcommands.add_parser("run", help="Check once and greet if eligible")
    watch = subcommands.add_parser("watch", help="Keep checking in the foreground (for Docker or services)")
    watch.add_argument("--interval", type=int, default=INTERVAL)
    login = subcommands.add_parser("login", help="Run the official Codex login interactively")
    login.add_argument("--device-auth", action="store_true")
    subcommands.add_parser("status", help="Show local logs without contacting Codex")
    args = parser.parse_args(argv)
    root = args.data_dir.expanduser().resolve()
    if os.name != "nt":
        os.umask(0o077)
    configure_logging(root)
    try:
        if args.command == "login":
            command = [find_codex(args.codex), "login"]
            if args.device_auth:
                command.append("--device-auth")
            return subprocess.call(command)
        if args.command == "status":
            path = root / "monitor.log"
            if path.exists():
                for line in path.read_text(encoding="utf-8").splitlines()[-15:]:
                    print(line)
            return 0
        if args.command == "watch":
            if args.interval < 60:
                raise MonitorError("The check interval must be at least 60 seconds.")
            stopped = threading.Event()
            for signum in (signal.SIGINT, signal.SIGTERM):
                signal.signal(signum, lambda *_: stopped.set())
            while not stopped.is_set():
                started = time.monotonic()
                try:
                    run_once(root, args.codex)
                except (MonitorError, OSError) as error:
                    LOG.error("%s", error)
                stopped.wait(max(1, args.interval - (time.monotonic() - started)))
            return 0
        decision = run_once(root, args.codex, check_only=args.command == "check")
        if args.command == "check" and decision in ("missing-quota", "unexpected-window", "locked"):
            return 1
        return 0
    except (MonitorError, OSError) as error:
        LOG.error("%s", error)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
