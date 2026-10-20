#!/bin/bash
# Test pemulihan otomatis watchdog.sh dengan stub PATH:
# perintah luar (curl, pgrep, ps) diganti shim yang perilakunya diatur
# env var, dan script restart diganti pencatat panggilan. Membuktikan:
#   1. Semua sehat        -> tidak ada restart.
#   2. 9Router HTTP 500   -> restart-9router dipanggil + tercatat di log.
#   3. Proses tunnel mati -> restart-tunnel dipanggil.
#   4. Gateway mati       -> start-gateway dipanggil.
#   5. Probe kesehatan gagal (proses client hidup tapi macet) -> restart-tunnel.
#   6. Kunci run dipegang proses lain -> watchdog keluar tanpa restart.
#   7. Probe sehat (nonce cocok + backend_ok) -> tidak ada restart.
#   8. Probe menjawab tapi backend mati -> restart-9router, BUKAN tunnel.
#   9. Edge menjawab 401 (gate) tapi probe tak terjawab -> restart-tunnel
#      (regresi putaran 3: 401 dari edge BUKAN bukti tunnel sehat).
#  10. Deployment publik (.tunnel-url ada) tapi .health-key HILANG ->
#      pemeriksaan tunnel GAGAL: baris ERROR keras di watchdog.log,
#      BUKAN lolos diam-diam (dan bukan restart — restart tak memperbaiki
#      konfigurasi). Regresi putaran 4.
#  11. Sama seperti 10 tapi .health-key ada namun KOSONG -> ERROR juga.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
APP="$TMP/app"
BIN="$TMP/bin"
mkdir -p "$APP" "$BIN"
fail=0

# --- Script restart stub: catat panggilan ---
for s in restart-9router.sh restart-tunnel.sh start-gateway.sh; do
  printf '#!/bin/bash\necho "%s" >> "%s/calls.log"\n' "$s" "$APP" > "$APP/$s"
  chmod +x "$APP/$s"
done
cp "$ROOT/watchdog.sh" "$APP/watchdog.sh"

# --- Shim curl: perilaku tergantung URL & env ---
# URL __tunnel-health -> badan probe sesuai MOCK_HEALTH (nonce diambil
# dari header -H yang dikirim watchdog, seperti client sungguhan).
# URL lain -> kode status seperti sebelumnya.
cat > "$BIN/curl" <<'EOF'
#!/bin/bash
nonce=""
prev=""
for a in "$@"; do
  if [ "$prev" = "-H" ]; then
    case "$a" in
      x-health-nonce:*) nonce="${a#x-health-nonce: }"; nonce="${nonce#x-health-nonce:}" ;;
    esac
  fi
  prev="$a"
  case "$a" in
    *__tunnel-health*)
      case "${MOCK_HEALTH:-ok}" in
        ok) printf '{"ok":true,"nonce":"%s","backend_ok":true,"backend_status":200}' "$nonce"; exit 0 ;;
        backend-down) printf '{"ok":true,"nonce":"%s","backend_ok":false,"backend_status":0}' "$nonce"; exit 0 ;;
        gate401) printf 'authentication required'; exit 0 ;;
        *) printf 'tunnel timeout (client offline?)'; exit 0 ;;
      esac
      ;;
    *127.0.0.1:20128*) echo "${MOCK_LOCAL_CODE:-200}"; exit 0 ;;
    http*) echo "${MOCK_PUBLIC_CODE:-200}"; exit 0 ;;
  esac
done
echo 200
EOF
# --- Shim pgrep: pola tunnel-client -> env MOCK_TUNNEL_PROC ---
cat > "$BIN/pgrep" <<'EOF'
#!/bin/bash
[ "${MOCK_TUNNEL_PROC:-alive}" = "alive" ] && exit 0 || exit 1
EOF
# --- Shim ps: baris gateway -> env MOCK_GW_PROC ---
cat > "$BIN/ps" <<'EOF'
#!/bin/bash
[ "${MOCK_GW_PROC:-alive}" = "alive" ] && echo "user 123 0.0 node hermes gateway run" || echo "user 1 0.0 init"
exit 0
EOF
chmod +x "$BIN/curl" "$BIN/pgrep" "$BIN/ps"

run_watchdog() {
  rm -f "$APP/calls.log" "$APP/watchdog.log"
  PATH="$BIN:/usr/bin:/bin" bash "$APP/watchdog.sh"
}
calls() { [ -f "$APP/calls.log" ] && cat "$APP/calls.log" || true; }
expect_calls() { # $1 = deskripsi, $2 = isi persis yang diharapkan (boleh kosong)
  local got
  got="$(calls)"
  if [ "$got" != "$2" ]; then
    echo "FAIL [$1]: panggilan restart = '$got', seharusnya '$2'"
    fail=1
  fi
}

# 1. Semua sehat
MOCK_LOCAL_CODE=200 MOCK_TUNNEL_PROC=alive MOCK_GW_PROC=alive run_watchdog
expect_calls "semua sehat" ""

# 2. 9Router sakit (HTTP 500)
MOCK_LOCAL_CODE=500 MOCK_TUNNEL_PROC=alive MOCK_GW_PROC=alive run_watchdog
expect_calls "9router 500" "restart-9router.sh"
grep -q "watchdog restarted: 9router" "$APP/watchdog.log" || { echo "FAIL [9router 500]: watchdog.log tidak mencatat restart"; fail=1; }

# 3. Proses tunnel mati
MOCK_LOCAL_CODE=200 MOCK_TUNNEL_PROC=dead MOCK_GW_PROC=alive run_watchdog
expect_calls "tunnel mati" "restart-tunnel.sh"

# 4. Gateway mati
MOCK_LOCAL_CODE=200 MOCK_TUNNEL_PROC=alive MOCK_GW_PROC=dead run_watchdog
expect_calls "gateway mati" "start-gateway.sh"

# 5. Probe gagal padahal proses client hidup (client macet)
echo "https://tunnel.example" > "$APP/.tunnel-url"
echo "health-secret" > "$APP/.health-key"
MOCK_LOCAL_CODE=200 MOCK_TUNNEL_PROC=alive MOCK_GW_PROC=alive MOCK_HEALTH=stuck run_watchdog
expect_calls "probe macet" "restart-tunnel.sh"

# 7. Probe sehat penuh -> diam
MOCK_LOCAL_CODE=200 MOCK_TUNNEL_PROC=alive MOCK_GW_PROC=alive MOCK_HEALTH=ok run_watchdog
expect_calls "probe sehat" ""

# 8. Probe menjawab, backend mati -> restart 9Router saja
MOCK_LOCAL_CODE=200 MOCK_TUNNEL_PROC=alive MOCK_GW_PROC=alive MOCK_HEALTH=backend-down run_watchdog
expect_calls "probe backend mati" "restart-9router.sh"

# 9. Edge menjawab 401 (gate aktif) tapi probe tak sampai client -> restart tunnel
MOCK_LOCAL_CODE=200 MOCK_TUNNEL_PROC=alive MOCK_GW_PROC=alive MOCK_HEALTH=gate401 run_watchdog
expect_calls "gate 401 bukan sehat" "restart-tunnel.sh"
rm -f "$APP/.tunnel-url" "$APP/.health-key"

# 10. .tunnel-url ada, .health-key HILANG -> ERROR keras di log, tanpa restart
echo "https://tunnel.example" > "$APP/.tunnel-url"
MOCK_LOCAL_CODE=200 MOCK_TUNNEL_PROC=alive MOCK_GW_PROC=alive run_watchdog
expect_calls "health-key hilang: tanpa restart" ""
grep -q "watchdog ERROR: .health-key hilang/kosong" "$APP/watchdog.log" || { echo "FAIL [health-key hilang]: baris ERROR tidak ada di watchdog.log"; fail=1; }

# 11. .health-key ada tapi KOSONG -> ERROR juga
printf '' > "$APP/.health-key"
MOCK_LOCAL_CODE=200 MOCK_TUNNEL_PROC=alive MOCK_GW_PROC=alive run_watchdog
expect_calls "health-key kosong: tanpa restart" ""
grep -q "watchdog ERROR: .health-key hilang/kosong" "$APP/watchdog.log" || { echo "FAIL [health-key kosong]: baris ERROR tidak ada di watchdog.log"; fail=1; }

# Proses tunnel mati tetap di-restart walau .health-key hilang
# (kegagalan konfigurasi tidak memblokir pemulihan proses).
MOCK_LOCAL_CODE=200 MOCK_TUNNEL_PROC=dead MOCK_GW_PROC=alive run_watchdog
expect_calls "health-key hilang + proses mati" "restart-tunnel.sh"
rm -f "$APP/.tunnel-url" "$APP/.health-key"

# 6. Kunci dipegang proses lain -> keluar cepat, nol restart
( flock "$APP/.watchdog.lock" sleep 5 ) &
sleep 1
start_ts=$SECONDS
MOCK_LOCAL_CODE=500 MOCK_TUNNEL_PROC=dead MOCK_GW_PROC=dead run_watchdog
elapsed=$((SECONDS - start_ts))
expect_calls "kunci terpegang" ""
[ $elapsed -lt 4 ] || { echo "FAIL [kunci terpegang]: watchdog menunggu kunci ($elapsed dtk), seharusnya langsung keluar"; fail=1; }
wait

if [ $fail -eq 0 ]; then
  echo "watchdog test OK"
fi
exit $fail
