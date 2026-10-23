# Detailed usage

**Start with a computer, server, or NAS that can stay on, online, and awake.** Work runs on that host. It may differ from your work PC, but Codex must use the same ChatGPT account. Deploy only one monitor per account.

## Windows

Run `setup.cmd`. Setup checks CLI compatibility, authentication, and the 300-minute meter before copying the script into `%LOCALAPPDATA%\CodexQuotaHello` and registering the `CodexQuotaHello` scheduled task. A normal user account usually suffices; organizational policy may restrict task registration.

The first check starts in about a minute, repeats every five minutes, and also has a logon trigger. It uses an interactive user session: locking is fine, signing out stops execution. Setup does not change power settings or the machine-wide execution policy. `ExecutionPolicy Bypass` is scoped to the launched PowerShell process.

Manual commands:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\monitor.ps1 -Mode Check
powershell -NoProfile -ExecutionPolicy Bypass -File .\monitor.ps1 -Mode Run
powershell -NoProfile -ExecutionPolicy Bypass -File .\monitor.ps1 -Mode Setup -CodexPath "D:\Tools\Codex\codex.exe"
```

`Check` is read-only; `Run` may greet if eligible. To update, download the new release and run `setup.cmd` again. Existing state is retained.

## Linux and servers

Install Python 3.10+, Bash, and a Codex CLI build supporting your host architecture:

```bash
python3 --version
codex --version
codex login --device-auth
python3 monitor.py check
```

Device-code login may first need enabling in account security settings. If unavailable in your workspace, use another method in the [official authentication guide](https://learn.chatgpt.com/docs/auth). The CLI stores credentials; no password or API key goes into this project.

Install scheduled checks:

```bash
bash setup.sh             # Automatic choice
bash setup.sh --systemd   # Require a working systemd user session
bash setup.sh --cron      # Use the current user's cron
```

Programs go into `${XDG_DATA_HOME:-~/.local/share}/codex-quota-hello`. Default state is under `${XDG_STATE_HOME:-~/.local/state}/codex-quota-hello`. Set a project-specific persistent data path before installing if desired:

```bash
QUOTA_HELLO_DATA=/your/persistent/path bash setup.sh
```

Inspect a systemd installation with:

```bash
systemctl --user list-timers codex-quota-hello.timer
journalctl --user -u codex-quota-hello.service -n 30 --no-pager
```

User timers continuing after logout depend on lingering. For unattended operation, confirm `loginctl enable-linger "$USER"` is permitted and enabled, or use a running cron service. The server still needs normal Codex network access and user permissions.

The cron installer replaces only entries ending in `# codex-quota-hello` and preserves unrelated entries. Check `crontab -l` and your distribution's cron/crond daemon. The installer persists the current PATH and absolute executable locations for the minimal scheduled environment.

Foreground operation does not require a scheduler:

```bash
python3 monitor.py check       # Read-only
python3 monitor.py run         # One eligible check and greeting
python3 monitor.py watch       # Every five minutes; Ctrl+C to stop
python3 monitor.py status      # Local logs only
```

Put global arguments before the subcommand: `python3 monitor.py --codex /path/to/codex --data-dir /path/to/state check`. Python also works on Windows, but should not run as a second independent monitor alongside the PowerShell version.

Uninstall with `bash uninstall.sh`; program files, logs, state, and Codex authentication remain.

## NAS and Docker

A NAS is a device commonly kept online for storage and related services. File sharing alone does not provide an execution environment. Confirm Docker/container support and a matching amd64 or arm64 CPU. 32-bit ARM devices are outside the support target.

From a terminal or SSH session with Docker Compose:

```bash
docker compose build
docker compose run --rm quota-hello login --device-auth
docker compose run --rm quota-hello check
docker compose up -d
docker compose logs --tail=50 quota-hello
```

Complete device-code login in a browser. Credentials persist in `codex-auth`; state and logs persist in `quota-data`. Check successfully before starting the background service. No published port, Docker socket mount, or host networking is needed. Outbound access to Codex authentication and service endpoints is required.

`restart: unless-stopped` follows Docker restart policy when the daemon returns, so the NAS and Docker service must also start. Changing the Compose directory or project name may create a different set of volumes; retain the project name or explicitly migrate volumes when moving.

For a NAS with Docker commands or a container GUI but no Compose, the equivalent flow is:

```bash
docker build -t codex-quota-hello:local .
docker volume create codex-hello-auth
docker volume create codex-hello-data
docker run --rm -it -v codex-hello-auth:/home/node/.codex -v codex-hello-data:/data codex-quota-hello:local login --device-auth
docker run --rm -v codex-hello-auth:/home/node/.codex -v codex-hello-data:/data codex-quota-hello:local check
docker run -d --name codex-quota-hello --init --restart unless-stopped -v codex-hello-auth:/home/node/.codex -v codex-hello-data:/data codex-quota-hello:local watch
```

The image runs as `node`, normally UID 1000. Named volumes inherit the prepared directory ownership. With host-directory bind mounts, make both mounted directories writable by the container user. Keep the authentication directory private.

No prebuilt image is published by this project; build locally. The default `CODEX_VERSION` is pinned to `0.163.0`. Select another version you have verified with `CODEX_VERSION=<version> docker compose build --no-cache`; in PowerShell, set `$env:CODEX_VERSION` first.

For an update:

```bash
docker compose down
docker compose build --no-cache
docker compose up -d
```

Use `docker compose down` to stop and remove containers. **Do not add `-v` unless you intend to delete credentials and duplicate-prevention state.**

## Logs and decisions

| Decision | Meaning |
|---|---|
| `send` | Eligible; still does not send when `checkOnly=True` |
| `quota-in-use` | Current window has usage; wait |
| `already-attempted` | An attempt is already reserved |
| `weekly-limit` / `limit-reached` | A known allowance block |
| `missing-quota` / `unexpected-window` | Insufficient data or a non-300-minute window |
| `Greeting completed` | Greeting process returned the expected text successfully |
| `ERROR` | This check failed; consult troubleshooting |

Python logs rotate at 1 MiB with three backups. The original Windows log is append-only. Project logs do not retain the full upstream stderr stream. Codex may separately maintain its normal diagnostic data.

## Duplicate prevention and disconnects

A file lock prevents concurrent checks in one data directory. An `attempted` guard is written before a request; success changes it to `completed`. A successful guard lasts five hours after the response. Ambiguous delivery reserves five hours plus five minutes. Failed quota reads create no attempt record.

This is not a distributed lock across devices. Stop the old deployment before moving to another host and retain or migrate state. Uninstallation preserves state and authentication by default.
