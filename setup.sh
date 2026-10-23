#!/usr/bin/env bash
set -euo pipefail
umask 077

quota_source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
quota_install_dir="${XDG_DATA_HOME:-$HOME/.local/share}/codex-quota-hello"
quota_state_dir="${QUOTA_HELLO_DATA:-${XDG_STATE_HOME:-$HOME/.local/state}/codex-quota-hello}"
quota_config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
quota_python="$(command -v python3 || true)"
quota_codex="$(command -v codex || true)"
quota_mode="${1:-auto}"

quota_read_cron() {
    local quota_error_file
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
        return 1
    fi
}

case "$quota_mode" in auto|--systemd|--cron) ;; *) echo 'Usage: bash setup.sh [--systemd|--cron]'; exit 1 ;; esac
if [[ -z "$quota_python" || -z "$quota_codex" ]]; then
    echo 'Install Python 3.10+ and Codex CLI first. See README.md / README.en.md.'
    exit 1
fi
"$quota_python" -c 'import sys; assert sys.version_info >= (3, 10), "Python 3.10+ required"'
echo 'Checking your ChatGPT login and five-hour usage meter (no greeting will be sent)...'
"$quota_python" "$quota_source_dir/monitor.py" --codex "$quota_codex" --data-dir "$quota_state_dir" check
mkdir -p -- "$quota_install_dir" "$quota_state_dir"
if [[ "$quota_source_dir" != "$quota_install_dir" ]]; then
    cp -- "$quota_source_dir/monitor.py" "$quota_install_dir/monitor.py"
fi

# Persist exact executable paths and PATH because scheduled environments are minimal.
"$quota_python" - "$quota_install_dir" "$quota_state_dir" "$quota_python" "$quota_codex" "$PATH" <<'PY'
import os, pathlib, shlex, sys
install, state, python, codex, path = sys.argv[1:]
command = [python, str(pathlib.Path(install) / 'monitor.py'), '--codex', codex, '--data-dir', state, 'run']
script = '#!/usr/bin/env bash\nset -euo pipefail\numask 077\nexport PATH=' + shlex.quote(path) + '\nexec ' + shlex.join(command) + '\n'
target = pathlib.Path(install) / 'run-once.sh'
target.write_text(script, encoding='utf-8')
target.chmod(0o700)
PY

quota_use_systemd=false
if command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1; then
    quota_use_systemd=true
fi
if [[ "$quota_mode" == '--cron' ]]; then quota_use_systemd=false; fi
if [[ "$quota_mode" == '--systemd' && "$quota_use_systemd" != true ]]; then
    echo 'A working systemd user session is required. Try --cron instead.'
    exit 1
fi

if [[ "$quota_use_systemd" == true ]]; then
    mkdir -p -- "$quota_config_dir"
    "$quota_python" - "$quota_config_dir" "$quota_install_dir" <<'PY'
import json, pathlib, sys
config, install = map(pathlib.Path, sys.argv[1:])
# Percent signs have special meaning in unit files; %% is a literal percent.
runner = json.dumps(str(install / 'run-once.sh'), ensure_ascii=False).replace('%', '%%')
(config / 'codex-quota-hello.service').write_text('[Unit]\nDescription=Codex quota hello check\n\n[Service]\nType=oneshot\nExecStart=/bin/bash ' + runner + '\nTimeoutStartSec=240\n', encoding='utf-8')
(config / 'codex-quota-hello.timer').write_text('[Unit]\nDescription=Check Codex quota every five minutes\n\n[Timer]\nOnStartupSec=60\nOnUnitActiveSec=5min\nUnit=codex-quota-hello.service\n\n[Install]\nWantedBy=timers.target\n', encoding='utf-8')
PY
    # Remove only this project's cron entry when switching scheduling methods.
    if command -v crontab >/dev/null 2>&1; then
        quota_read_cron
        printf '%s\n' "$quota_existing_cron" | sed '/# codex-quota-hello$/d' | crontab -
    fi
    systemctl --user daemon-reload
    systemctl --user enable --now codex-quota-hello.timer
    echo 'Installed systemd user timer. Check: systemctl --user list-timers codex-quota-hello.timer'
    echo 'To keep a user timer running after logout, enable lingering if permitted: loginctl enable-linger "$USER"'
else
    if ! command -v crontab >/dev/null 2>&1; then
        echo 'Neither a systemd user session nor crontab is available. Use Docker or install a scheduler.'
        exit 1
    fi
    if command -v systemctl >/dev/null 2>&1; then
        systemctl --user disable --now codex-quota-hello.timer >/dev/null 2>&1 || true
    fi
    quota_cron_line="$("$quota_python" - "$quota_install_dir" "$quota_state_dir" <<'PY'
import pathlib, shlex, sys
runner = shlex.quote(str(pathlib.Path(sys.argv[1]) / 'run-once.sh')).replace('%', r'\%')
log = shlex.quote(str(pathlib.Path(sys.argv[2]) / 'cron.log')).replace('%', r'\%')
print('*/5 * * * * /bin/bash ' + runner + ' >> ' + log + ' 2>&1 # codex-quota-hello')
PY
)"
    quota_read_cron
    { printf '%s\n' "$quota_existing_cron" | sed '/# codex-quota-hello$/d'; printf '%s\n' "$quota_cron_line"; } | crontab -
    echo 'Installed user cron entry (every five minutes). Make sure the cron daemon is running.'
fi
echo "Installed program: $quota_install_dir"
echo "State and logs: $quota_state_dir"
echo 'Keep the host powered on, awake, and connected to Codex.'
