#!/usr/bin/env bash
set -euo pipefail
quota_config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
if command -v systemctl >/dev/null 2>&1; then
    systemctl --user disable --now codex-quota-hello.timer >/dev/null 2>&1 || true
    systemctl --user stop codex-quota-hello.service >/dev/null 2>&1 || true
fi
rm -f -- "$quota_config_dir/codex-quota-hello.timer" "$quota_config_dir/codex-quota-hello.service"
if command -v systemctl >/dev/null 2>&1; then systemctl --user daemon-reload >/dev/null 2>&1 || true; fi
if command -v crontab >/dev/null 2>&1; then
    quota_error_file="$(mktemp)"
    if quota_existing_cron="$(LC_ALL=C crontab -l 2>"$quota_error_file")"; then
        rm -f -- "$quota_error_file"
    elif grep -Eq '^(crontab: )?no crontab for ' "$quota_error_file"; then
        quota_existing_cron=''
        rm -f -- "$quota_error_file"
    else
        cat -- "$quota_error_file" >&2
        rm -f -- "$quota_error_file"
        echo 'Cannot read the existing crontab; refusing to replace it.' >&2
        exit 1
    fi
    printf '%s\n' "$quota_existing_cron" | sed '/# codex-quota-hello$/d' | crontab -
fi
echo 'Automatic checks removed. Program files, state, logs, and Codex login were kept.'
