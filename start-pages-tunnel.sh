#!/bin/bash
# Supervisor tunnel client: auto-restart kalau proses mati. Log: pages-tunnel.log
#
# URL tunnel diambil dari TUNNEL_BASE_URL, atau file .tunnel-url (chmod 600):
#   echo -n 'https://<project-kamu>.pages.dev' > .tunnel-url && chmod 600 .tunnel-url
export PATH="$HOME/.npm-global/bin:$PATH"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [ -z "${TUNNEL_BASE_URL:-}" ] && [ -f "$SCRIPT_DIR/.tunnel-url" ]; then
  export TUNNEL_BASE_URL="$(cat "$SCRIPT_DIR/.tunnel-url")"
fi
: "${TUNNEL_BASE_URL:?Set TUNNEL_BASE_URL atau buat file .tunnel-url dulu}"

while true; do
  echo "[$(date -u '+%H:%M:%S')] starting tunnel client..." >> pages-tunnel.log
  node tunnel-client.mjs >> pages-tunnel.log 2>&1
  echo "[$(date -u '+%H:%M:%S')] tunnel client exited (code $?), restarting in 5s..." >> pages-tunnel.log
  sleep 5
done
