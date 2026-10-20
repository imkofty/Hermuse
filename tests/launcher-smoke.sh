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

if [ $fail -eq 0 ]; then
  echo "launcher smoke OK"
fi
exit $fail
