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

# 2b. Probe kesehatan UJUNG-KE-UJUNG terautentikasi (bila .tunnel-url
# DAN .health-key tersedia): proses client bisa HIDUP tapi macet — hanya
# request yang benar-benar melewati antrean tunnel yang membuktikannya.
# Probe mengirim GET /__tunnel-health dengan kunci kesehatan + nonce
# acak; yang menjawab adalah tunnel client itu sendiri (setelah mengecek
# backend lokal), membawa nonce yang sama + status backend.
#   - nonce cocok + backend_ok:true  -> sehat, tidak ada restart.
#   - nonce cocok + backend_ok:false -> tunnel hidup, backend sakit:
#     restart 9Router saja.
#   - selain itu (timeout/504/badan kosong/nonce beda) -> client macet
#     atau mati di tengah: restart tunnel.
# Kode 401/403 dari edge TIDAK lagi dianggap sehat (perbaikan putaran 3):
# dengan gate aktif, ingress menjawab 401 SEBELUM request masuk antrean,
# jadi 401 hanya membuktikan edge hidup — bukan tunnel.
# Putaran 4: .tunnel-url ADA tapi .health-key HILANG/KOSONG bukan lagi
# "probe dilewati diam-diam" — itu konfigurasi TIDAK SEHAT pada
# deployment publik: pemeriksaan tunnel dinyatakan GAGAL dengan baris
# ERROR keras di watchdog.log setiap run, sampai file-nya dibuat
# (scripts/setup-tunnel.sh atau manual — lihat README, bagian upgrade).
# Sehat diam-diam tanpa probe pada deployment publik tidak boleh terjadi
# lagi. (Restart proses mati di langkah 2 di atas tidak terpengaruh:
# yang gagal di sini adalah KONFIGURASI, dan restart tidak
# memperbaikinya — file kuncinya yang harus dibuat.)
# Probe dilewati juga bila client baru saja di-restart (beri waktu bangun).
if [ "$TUNNEL_RESTARTED" -eq 0 ] && [ -f "$D/.tunnel-url" ]; then
  TURL="$(tr -d '[:space:]' < "$D/.tunnel-url")"
  TURL="${TURL%/}"
  HKEY=""
  [ -f "$D/.health-key" ] && HKEY="$(tr -d '[:space:]' < "$D/.health-key")"
  if [ -z "$HKEY" ]; then
    echo "[$(date -u '+%F %H:%M:%S')] watchdog ERROR: .health-key hilang/kosong di $D/.health-key padahal deployment tunnel publik terdeteksi (.tunnel-url ada) — probe kesehatan tunnel NONAKTIF, tunnel dinyatakan TIDAK SEHAT (konfigurasi). Buat file-nya: bash scripts/setup-tunnel.sh, atau generate manual + setel secret HEALTH_KEY (lihat README)." >> "$D/watchdog.log"
  elif [ -n "$TURL" ]; then
    NONCE="wd-$(date +%s)-$$-${RANDOM:-0}"
    PBODY="$(curl -s -m 50 -H "x-tunnel-health-key: $HKEY" -H "x-health-nonce: $NONCE" "$TURL/__tunnel-health" 2>/dev/null)"
    case "$PBODY" in
      *"$NONCE"*)
        case "$PBODY" in
          *'"backend_ok":true'*|*'"backend_ok": true'*) : ;;  # sehat penuh
          *)
            bash "$D/restart-9router.sh" > /dev/null 2>&1
            RESTARTED="$RESTARTED 9router-backend"
            ;;
        esac
        ;;
      *)
        bash "$D/restart-tunnel.sh" > /dev/null 2>&1
        RESTARTED="$RESTARTED tunnel-probe"
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
