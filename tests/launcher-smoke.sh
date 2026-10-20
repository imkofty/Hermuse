#!/bin/bash
# Smoke test launcher — membuktikan startup dari clone segar:
#   1. Semua script entry-point EXECUTABLE sebagaimana tersimpan di git
#      (regresi audit putaran 2: run-hermes.sh tersimpan 100644 sehingga
#      clone baru di Linux gagal "Permission denied" saat start-gateway.sh
#      memanggil ./run-hermes.sh secara langsung).
#   2. Tanpa perintah `hermes` terpasang, ./run-hermes.sh gagal CEPAT
#      dengan pesan jelas — bukan Permission denied, bukan menggantung.
#   3. Dengan `hermes` di PATH, argumen diteruskan apa adanya
#      (membuktikan wiring start-gateway.sh -> run-hermes.sh -> hermes).
#   4. start-9router.sh fail-closed: .tunnel-url ada tapi .dashboard-pw
#      hilang ATAU kosong -> exit 1 (putaran 3 + 4).
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
fail=0

for f in run-hermes.sh start-gateway.sh start-9router.sh start-pages-tunnel.sh watchdog.sh restart-9router.sh; do
  if [ ! -x "./$f" ]; then
    echo "FAIL: $f tidak executable di checkout ini"
    fail=1
  fi
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# 2. PATH & HOME kosong dari hermes -> pesan jelas, exit non-zero
out="$(PATH="$TMP" HOME="$TMP" ./run-hermes.sh gateway run 2>&1)"
code=$?
if [ $code -eq 0 ]; then
  echo "FAIL: run-hermes.sh exit 0 padahal hermes tidak terpasang"
  fail=1
fi
case "$out" in
  *"tidak ditemukan"*) : ;;
  *) echo "FAIL: pesan error tidak jelas: $out"; fail=1 ;;
esac

# 3. Stub hermes menerima argumen persis
mkdir -p "$TMP/bin"
printf '#!/bin/sh\necho "STUB-HERMES args: $@"\n' > "$TMP/bin/hermes"
chmod +x "$TMP/bin/hermes"
out="$(PATH="$TMP/bin" HOME="$TMP" ./run-hermes.sh gateway run 2>&1)"
case "$out" in
  *"STUB-HERMES args: gateway run"*) : ;;
  *) echo "FAIL: argumen tidak diteruskan ke hermes: $out"; fail=1 ;;
esac

# 4. start-9router.sh fail-closed (putaran 3+4): dengan .tunnel-url ada,
#    .dashboard-pw HILANG -> exit 1; .dashboard-pw KOSONG -> exit 1 juga
#    (dulu file kosong lolos dan 9Router jalan dengan password kosong).
#    Layout disalin ke temp agar file penanda tidak menyentuh repo asli.
APP="$TMP/app"
mkdir -p "$APP/lib"
cp "$ROOT/start-9router.sh" "$APP/start-9router.sh"
cp "$ROOT/lib/i18n.sh" "$APP/lib/i18n.sh"
echo "https://tunnel.example" > "$APP/.tunnel-url"
out="$(cd "$APP" && HOME="$TMP" timeout 5 bash ./start-9router.sh 2>&1)"
code=$?
if [ $code -ne 1 ]; then
  echo "FAIL: start-9router.sh tanpa .dashboard-pw exit=$code, seharusnya 1. Output: $out"
  fail=1
fi
printf '' > "$APP/.dashboard-pw"
out="$(cd "$APP" && HOME="$TMP" timeout 5 bash ./start-9router.sh 2>&1)"
code=$?
if [ $code -ne 1 ]; then
  echo "FAIL: start-9router.sh dengan .dashboard-pw KOSONG exit=$code, seharusnya 1. Output: $out"
  fail=1
fi
case "$out" in
  *"dashboard-pw"*) : ;;
  *) echo "FAIL: pesan penolakan tidak menyebut .dashboard-pw: $out"; fail=1 ;;
esac

if [ $fail -eq 0 ]; then
  echo "launcher smoke OK"
fi
exit $fail
