# Troubleshooting

First confirm the host stays on, connected, and awake. Windows also requires its user session to stay signed in. Prefer read-only `Check` / `check` instead of sending repeated real greetings.

| Symptom | What to check |
|---|---|
| Codex not found | Run `codex --version` as the same user. Use `-CodexPath` on Windows or `--codex` with Python for custom locations |
| Not authenticated with ChatGPT | Run `codex login`, using `--device-auth` on headless hosts. An API key is separately billed and does not serve this purpose |
| Old CLI | `codex exec --help` must include `--ignore-user-config` and `--ephemeral`; update Codex |
| `quota-in-use` | Normal waiting: the current window has usage |
| `already-attempted` | A duplicate-prevention guard exists, possibly after uncertain delivery; wait |
| `missing-quota` | Complete quota data is unavailable; retry a read-only check later |
| `unexpected-window` | The meter is not 300 minutes; this project skips plans without that window |
| `weekly-limit` / `limit-reached` | A known allowance block prevents the greeting |
| `Quota request timed out` | Check DNS, connectivity, proxies, and service access; no greeting guard is created at this stage |
| `Greeting timed out` / `Greeting failed` | Delivery may have happened. The guard remains for at least five hours; do not delete it to force retries |
| `Unexpected greeting output` | A request ran but did not return exactly “你好”; the guard remains |
| Corrupt state | Stop the monitor and back up the file first. If resetting local state, first ensure at least five hours have passed since any possible request |
| Manual runs work, scheduling fails | Check the Windows session, task history, systemd lingering, cron daemon, and executable paths |
| Node not found | Linux setup preserves PATH. Reinstall scheduled checks after changing Node or Codex locations |
| NAS login disappears | Preserve the mount at `/home/node/.codex`; retain the Compose project name and authentication volume |
| Container permission errors | Use named volumes or make bind mounts writable by the container user, normally UID 1000 |
| ARM NAS cannot build | Verify arm64 and official Codex package support. 32-bit ARM is outside the support target |

## Windows

Run `status.cmd`, or inspect `CodexQuotaHello` in Task Scheduler. Authentication alone does not mean the task was registered: setup must print `Installed`. Organizational policy can prevent registration.

Power settings are not changed by setup. Locking the screen differs from signing out. After a reboot, the original Windows task waits for the user to sign in.

## Linux

```bash
python3 monitor.py check
systemctl --user list-timers codex-quota-hello.timer
journalctl --user -u codex-quota-hello.service -n 30 --no-pager
crontab -l
```

Use one scheduling method. Setup removes this project's other scheduling entry while preserving unrelated jobs. Cron service names vary by distribution, commonly `cron` or `crond`.

## Docker

```bash
docker compose ps
docker compose logs --tail=50 quota-hello
docker compose run --rm quota-hello check
```

Builds need access to container package sources and npm; runtime needs Codex connectivity. A host proxy listening only on `127.0.0.1` usually cannot be reached through that same address inside a container. Configure a reachable proxy according to your network. This project does not alter proxies or firewalls.

## Reporting an issue

Include OS, architecture, deployment method, CLI version, Python/Docker versions, and relevant **redacted error lines**. Do not attach credentials, tokens, full home directories, container volumes, or unreviewed logs. Use the repository's issue template.
