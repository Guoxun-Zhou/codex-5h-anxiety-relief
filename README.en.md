# codex5小时重置焦虑缓解剂

**Codex 5-Hour Reset Anxiety Relief**

> **Prerequisite: you need a computer, server, or NAS that can stay powered on, connected to the internet, and awake.**
> This tool runs on your own host. It cannot send a scheduled greeting while that host is offline. Windows uses Task Scheduler, Linux uses systemd or cron, and Docker is recommended for NAS devices. **A NAS must support Docker or a suitable Linux runtime; a file-sharing-only NAS cannot run this project.**

[简体中文](README.md) · [Usage guide](docs/USAGE.en.md) · [Troubleshooting](docs/TROUBLESHOOTING.en.md) · [Publish to GitHub](docs/PUBLISH.en.md)

[![CI](https://github.com/Guoxun-Zhou/codex-5h-anxiety-relief/actions/workflows/ci.yml/badge.svg)](https://github.com/Guoxun-Zhou/codex-5h-anxiety-relief/actions/workflows/ci.yml)

Windows · Linux · Server · Docker / NAS · Python standard library · MIT

A small tool that sends a single “你好” through Codex CLI when the five-hour allowance reports 100% remaining.

A Windows user has verified that, in their account environment, a Codex CLI request starts a new five-hour timer. This project schedules that small request on an always-on device, so some of the time until the next reset may have elapsed before the user starts work.

**It does not add allowance, shorten the server's five-hour window, or remove weekly limits.** Greetings count as normal usage. Timer behavior depends on your account and the service. This is an independent community project, not an OpenAI product.

## Choose a deployment

| Host | Recommended method | Requirements |
|---|---|---|
| Windows PC | Double-click `setup.cmd` | Current Codex CLI; Windows PowerShell 5.1; no Python needed |
| Linux PC / server | `bash setup.sh` | Python 3.10+, Bash, Codex, and a working systemd user session or cron daemon |
| Windows server | Windows or Python method | A suitable user session and Task Scheduler; verify your server configuration |
| Docker-capable NAS / Linux server | Docker Compose | Docker Engine, Compose, and a supported 64-bit architecture |
| File-sharing-only NAS | Cannot run directly | Another host capable of running the program is needed |

Codex must support the host CPU architecture. The Docker route targets amd64 and arm64; 32-bit ARM NAS devices are outside the support target. A native macOS installer is not included.

## Quick start

### Windows

1. Install or update the [official Codex CLI](https://developers.openai.com/codex/cli/), or use a Codex desktop installation that includes the CLI.
2. Download and **fully extract** the project, then double-click `setup.cmd`. Sign in with the same ChatGPT account you use for work if prompted.
3. After `Installed` appears, the first background check starts in about a minute, with subsequent checks every five minutes.

Keep that Windows user signed in and the PC awake and online. Locking the screen or switching off the display is fine. Signing out, sleeping, or powering off stops execution. After a reboot, sign back in to resume. The Codex desktop window does not need to remain open.

| File | Action |
|---|---|
| `setup.cmd` | Install or update the scheduled task |
| `check-only.cmd` | Read quota only; **never send a greeting** |
| `status.cmd` | Show task status and recent logs |
| `uninstall.cmd` | Stop and remove the task; retain data and login |

### Linux / servers

Install Python 3.10+ and Codex CLI, then run in the project directory:

```bash
codex login --device-auth
python3 monitor.py check
bash setup.sh
```

`check` only reads quota. The installer prefers a working systemd user timer and otherwise installs a cron entry for the current user. For headless login, follow the [official device-code authentication instructions](https://learn.chatgpt.com/docs/auth).

To keep a systemd user timer running after logout, enable lingering if permitted: `loginctl enable-linger "$USER"`. Alternatively choose `bash setup.sh --cron`; its cron daemon must be running.

Uninstall with `bash uninstall.sh`. Program files, state, logs, and Codex credentials are retained.

### NAS / Docker

Copy the complete project onto a NAS or server with Docker Compose, enter its directory, then run:

```bash
docker compose build
docker compose run --rm quota-hello login --device-auth
docker compose run --rm quota-hello check
docker compose up -d
```

Use the same ChatGPT subscription account. Python and Codex CLI are included in the image, so they are not required on the host. The first build downloads dependencies. View logs with `docker compose logs --tail=50 quota-hello`; stop with `docker compose down`.

The `codex-auth` volume holds official CLI credentials; `quota-data` holds local state and logs. Retain both across container rebuilds to preserve authentication and duplicate prevention. **Do not upload their contents to GitHub.** See the [detailed NAS guide](docs/USAGE.en.md#nas-and-docker) for deployment and permissions.

## How it works

1. Every five minutes, read `account/rateLimits/read` through the official App Server protocol. This read does not invoke a model.
2. Select the `codex` meter and require a 300-minute window with reported usage of zero, without a known weekly-limit block.
3. **Persist the duplicate-prevention guard before sending anything.** The greeting uses ChatGPT authentication, an ephemeral session, a read-only sandbox, and low reasoning effort.
4. After success, wait at least five hours before another attempt, even if a very small greeting still rounds to 100% remaining.

See the [official quota interface](https://learn.chatgpt.com/docs/app-server) and [non-interactive CLI documentation](https://learn.chatgpt.com/docs/non-interactive-mode).

## Limits to understand

- Failed quota reads, missing data, and unexpected windows do not trigger a greeting. Later checks retry after connectivity returns.
- If a request has started and then times out or loses power, delivery is uncertain. The guard stays for at least five hours, so that opportunity may be missed.
- Reported 100% does not prove absolutely zero usage. Starting work on another device at the same time may overlap with one extra greeting.
- **Deploy only one monitor per account.** Independent hosts cannot share duplicate-prevention state automatically.
- Greetings count toward applicable five-hour and weekly limits. The tool neither buys credits nor redeems rate-limit resets.
- Docker still requires an awake, online host; it is not a hosted scheduling service.

## Data and privacy

Authentication is handled by your official Codex CLI. This project does not copy or upload credential files and has no third-party collection endpoint. Codex still communicates with OpenAI during normal login and requests.

| Method | Project data directory |
|---|---|
| Windows | `%LOCALAPPDATA%\CodexQuotaHello` |
| Linux default | `${XDG_STATE_HOME:-~/.local/state}/codex-quota-hello` |
| Docker | `quota-data` volume, mounted at `/data` |

Logs contain quota, decisions, and errors. State filenames use a SHA-256 digest of an account identifier; these remain local runtime data. Do not publish the runtime directory. `.gitignore` and the publication manifest exclude it.

## Development and testing

The previously verified Windows implementation is retained. Linux and Docker use a Python standard-library implementation. Run offline tests with:

```bash
python3 -m unittest discover -s tests -p 'test_*.py' -v
```

Run Windows PowerShell regression checks with:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\run-tests.ps1
```

Tests use fake accounts, fake Codex, and fake schedulers. They never send a real greeting or register a real job. GitHub CI includes Windows/Linux tests and a Docker build check. See [TESTING.md](docs/TESTING.md) for the local verification record and remaining limits.

## Publishing and contributing

For the initial publication, `publish-to-github.cmd` creates a public `codex-5h-anxiety-relief` repository after GitHub authentication. It requires Git and GitHub CLI and publishes only the manifest-listed source and documentation. Read the [publishing guide](docs/PUBLISH.en.md) first.

[Changelog](CHANGELOG.md) · [Contributing](CONTRIBUTING.md) · [Security and privacy](SECURITY.md) · [MIT license](LICENSE)
