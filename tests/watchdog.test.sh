#!/bin/bash
# Test pemulihan otomatis watchdog.sh dengan stub PATH:
# perintah luar (curl, pgrep, ps) diganti shim yang perilakunya diatur
# env var, dan script restart diganti pencatat panggilan. Membuktikan:
#   1. Semua sehat        -> tidak ada restart.
#   2. 9Router HTTP 500   -> restart-9router dipanggil + tercatat di log.
#   3. Proses tunnel mati -> restart-tunnel dipanggil.
#   4. Gateway mati       -> start-gateway dipanggil.
#   5. URL publik 502 (proses client hidup tapi macet) -> restart-tunnel.
#   6. Kunci run dipegang proses lain -> watchdog keluar tanpa restart.
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

# --- Shim curl: kode status tergantung URL & env ---
cat > "$BIN/curl" <<'EOF'
#!/bin/bash
for a in "$@"; do
  case "$a" in
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

# 5. URL publik 502 padahal proses client hidup
echo "https://tunnel.example" > "$APP/.tunnel-url"
MOCK_LOCAL_CODE=200 MOCK_TUNNEL_PROC=alive MOCK_GW_PROC=alive MOCK_PUBLIC_CODE=502 run_watchdog
expect_calls "publik 502" "restart-tunnel.sh"
rm -f "$APP/.tunnel-url"

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
