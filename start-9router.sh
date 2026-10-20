#!/bin/bash
# Supervisor 9Router: bind ke localhost saja (127.0.0.1:20128),
# auto-restart kalau proses crash. Log: 9router.log
#
# Password dashboard dibaca dari file 600 (JANGAN tulis password di script!):
#   echo -n 'password-baru' > .dashboard-pw && chmod 600 .dashboard-pw
export PATH="$HOME/.npm-global/bin:$PATH"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/i18n.sh
. "$SCRIPT_DIR/lib/i18n.sh"
cd "$SCRIPT_DIR"

DASHBOARD_PW_FILE="${DASHBOARD_PW_FILE:-$SCRIPT_DIR/.dashboard-pw}"
if [ -f "$DASHBOARD_PW_FILE" ]; then
  export INITIAL_PASSWORD="$(cat "$DASHBOARD_PW_FILE")"
else
  echo "$(t router_pw_warn "$DASHBOARD_PW_FILE")" >&2
fi

while true; do
  echo "[$(date -u '+%H:%M:%S')] starting 9router..." >> 9router.log
  9router -p 20128 -H 127.0.0.1 -n -l --skip-update >> 9router.log 2>&1
  echo "[$(date -u '+%H:%M:%S')] 9router exited (code $?), restarting in 5s..." >> 9router.log
  sleep 5
done
