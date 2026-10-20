#!/bin/bash
# Restart 9Router (supervisor loop): bunuh sisa proses, jalankan supervisor detached.
# NOTE: pola "/start-9router.sh" (dengan slash) tidak match "restart-9router.sh",
# jadi script ini aman dari self-kill.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
kill $(ps aux | grep "[9]router -p" | awk '{print $2}') 2>/dev/null
pkill -f "/start-9router.sh" 2>/dev/null
sleep 3
setsid nohup bash "$SCRIPT_DIR/start-9router.sh" < /dev/null > /dev/null 2>&1 &
echo "9router supervisor started"
