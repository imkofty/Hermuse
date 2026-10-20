#!/bin/bash
# Watchdog: pastikan 9Router, tunnel client, dan Telegram gateway tetap jalan.
# Dijalankan via cron tiap 5 menit:
#   */5 * * * * /path/ke/Hermuse/watchdog.sh
#
# (Untuk cron: simpan URL tunnel di file .tunnel-url (chmod 600) di folder ini,
#  karena cron tidak mewarisi environment variable interaktif.)
D="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESTARTED=""

# Kunci run: dua watchdog tidak boleh tumpang tindih (run cron yang lambat
# + run manual bisa me-restart komponen yang sama dua kali). Run kedua
# langsung keluar. Tanpa flock di sistem, lewati kunci ini.
if command -v flock >/dev/null 2>&1; then
  exec 9>"$D/.watchdog.lock"
  flock -n 9 || exit 0
fi

# 1. 9Router (127.0.0.1:20128) — cek KODE STATUS HTTP dashboard, bukan
# sekadar koneksi: curl tanpa -f/cek status tetap exit 0 pada respons
# 4xx/5xx, yang dulu membuat 9Router setengah mati terlihat "sehat".
HTTP_CODE="$(curl -s -m 8 -o /dev/null -w '%{http_code}' http://127.0.0.1:20128/dashboard 2>/dev/null || echo 000)"
case "$HTTP_CODE" in
  200|301|302|303|307|308) : ;;  # sehat (200, atau redirect ke login = normal)
  *)
    bash "$D/restart-9router.sh" > /dev/null 2>&1
    RESTARTED="$RESTARTED 9router"
    ;;
esac

# 2. Tunnel client (proses node tunnel-client.mjs)
# Pola "[.]" = exact match, agar tidak ikut cocok dengan tunnel client lain
# (mis. tunnel-client-hermesum.mjs) di setup multi-tunnel.
TUNNEL_RESTARTED=0
if ! pgrep -f "tunnel-client[.]mjs" > /dev/null 2>&1; then
  bash "$D/restart-tunnel.sh" > /dev/null 2>&1
  RESTARTED="$RESTARTED tunnel"
  TUNNEL_RESTARTED=1
fi

# 2b. Cek ujung-ke-ujung lewat URL publik (bila .tunnel-url tersedia):
# proses client bisa HIDUP tapi macet — hanya jalur publik yang
# membuktikan tunnel benar-benar meneruskan request. 401/403 = sehat
# (gate/auth di ujung sana menjawab = tunnel bekerja). Kode 000/5xx
# dengan client yang baru saja di-restart dilewati (beri waktu bangun).
if [ "$TUNNEL_RESTARTED" -eq 0 ] && [ -f "$D/.tunnel-url" ]; then
  TURL="$(tr -d '[:space:]' < "$D/.tunnel-url")"
  TURL="${TURL%/}"
  if [ -n "$TURL" ]; then
    PCODE="$(curl -s -m 10 -o /dev/null -w '%{http_code}' "$TURL/dashboard" 2>/dev/null || echo 000)"
    case "$PCODE" in
      200|301|302|303|307|308|401|403) : ;;  # sehat / ter-gate = tunnel meneruskan
      *)
        bash "$D/restart-tunnel.sh" > /dev/null 2>&1
        RESTARTED="$RESTARTED tunnel-public"
        ;;
    esac
  fi
fi

# 3. Telegram gateway (hermes gateway run)
if ! ps aux | grep "[g]ateway.*run" > /dev/null 2>&1; then
  bash "$D/start-gateway.sh" > /dev/null 2>&1
  RESTARTED="$RESTARTED gateway"
fi

if [ -n "$RESTARTED" ]; then
  echo "[$(date -u '+%F %H:%M:%S')] watchdog restarted:$RESTARTED" >> "$D/watchdog.log"
fi
