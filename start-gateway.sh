#!/bin/bash
# Start Telegram gateway Hermes secara detached (tetap jalan setelah shell ditutup).
# Log: gateway.log. Cek dengan: pgrep -f "gateway.*run"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
setsid nohup ./run-hermes.sh gateway run >> gateway.log 2>&1 < /dev/null &
echo "gateway starting, pid $!"
