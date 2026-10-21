#!/bin/bash
# Test negatif scripts/check-i18n.sh (validasi per runtime):
# checker harus GAGAL bila satu definisi hilang di SATU runtime saja
# (definisi runtime lain tidak boleh menutupinya), bila jumlah
# placeholder %s menyimpang dari referensi en, atau bila ada nilai
# kosong — dan LULUS pada salinan utuh.
#
# Setiap skenario menyalin checker + lib ke direktori temp, plus
# fixture pemakaian yang menyebut SEMUA kunci terdefinisi di tiap lib
# (fixture dibuat dari lib itu sendiri), supaya setiap kunci terhitung
# terpakai oleh runtime-nya masing-masing.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0

build_tree() { # $1 = direktori tujuan
  mkdir -p "$1/scripts" "$1/lib" "$1/fixtures"
  cp "$ROOT/scripts/check-i18n.sh" "$1/scripts/"
  cp "$ROOT/lib/i18n.sh" "$ROOT/lib/i18n.mjs" "$1/lib/"
  sed -nE 's/^[[:space:]]*([a-z][a-z_0-9]*)\)[[:space:]]*fmt=.*/\1/p' "$1/lib/i18n.sh" \
    | sort -u | while read -r k; do printf 't %s\n' "$k"; done > "$1/fixtures/usage.sh"
  sed -nE 's/^[[:space:]]*([a-z][a-z_0-9]*):[[:space:]]*".*/\1/p' "$1/lib/i18n.mjs" \
    | sort -u | while read -r k; do printf 't("%s");\n' "$k"; done > "$1/fixtures/usage.mjs"
}

# $1 = dir, $2 = ok|fail, $3 = label, $4 = pola wajib di output (grep -F), $5 = pola kedua (opsional)
expect() {
  local dir="$1" want="$2" label="$3" pat="$4" pat2="${5:-}"
  local out rc ok=1
  out="$(cd "$dir" && bash scripts/check-i18n.sh 2>&1)"; rc=$?
  if [ "$want" = "ok" ] && [ "$rc" -ne 0 ]; then ok=0; fi
  if [ "$want" = "fail" ] && [ "$rc" -eq 0 ]; then ok=0; fi
  printf '%s' "$out" | grep -qF "$pat" || ok=0
  if [ -n "$pat2" ]; then printf '%s' "$out" | grep -qF "$pat2" || ok=0; fi
  if [ "$ok" -eq 1 ]; then
    echo "PASS: $label"
  else
    echo "FAIL: $label (exit=$rc, mau=$want)"
    printf '%s\n' "$out" | sed 's/^/    /'
    fail=1
  fi
}

# 1) salinan utuh harus lulus, dengan laporan per runtime
build_tree "$TMP/utuh"
expect "$TMP/utuh" ok "salinan utuh lulus" "i18n check OK" "[mjs]"

# 2) hapus SATU definisi vi di lib JS saja — kunci yang sama tetap ada
#    di lib bash, jadi checker lama (gabungan) akan lolos; yang baru
#    wajib gagal di runtime mjs
build_tree "$TMP/mjs-vi-del"
sed -i '/^  vi: {/,/^  },/ { /tunnel_key_empty:/d }' "$TMP/mjs-vi-del/lib/i18n.mjs"
expect "$TMP/mjs-vi-del" fail "definisi vi hilang di lib JS saja -> gagal" \
  "FAIL [mjs]: key 'tunnel_key_empty' missing translation for: vi"

# 3) hapus SATU definisi hi di lib bash saja — kunci yang sama tetap
#    ada di lib JS; wajib gagal di runtime sh
build_tree "$TMP/sh-hi-del"
sed -i '/^        hi)$/,/^            esac$/ { /tunnel_key_empty)/d }' "$TMP/sh-hi-del/lib/i18n.sh"
expect "$TMP/sh-hi-del" fail "definisi hi hilang di lib bash saja -> gagal" \
  "FAIL [sh]: key 'tunnel_key_empty' missing translation for: hi"

# 4) kurangi satu placeholder di nilai id lib bash -> gagal integritas
build_tree "$TMP/sh-parity"
sed -i 's/Node\.js sudah ada: %s/Node.js sudah ada:/' "$TMP/sh-parity/lib/i18n.sh"
expect "$TMP/sh-parity" fail "jumlah placeholder id menyimpang dari en -> gagal" \
  "FAIL [sh]: key 'install_have_node' [id] has 0 %s placeholder(s), en has 1"

# 5) kosongkan satu nilai ms di lib JS -> gagal integritas
build_tree "$TMP/mjs-empty"
sed -i 's/tunnel_key_empty: "Kunci kosong di %s",/tunnel_key_empty: "",/' "$TMP/mjs-empty/lib/i18n.mjs"
expect "$TMP/mjs-empty" fail "nilai ms kosong di lib JS -> gagal" \
  "FAIL [mjs]: key 'tunnel_key_empty' [ms] has an empty value"

if [ "$fail" -eq 1 ]; then
  echo "i18n-check.test: FAILED" >&2
  exit 1
fi
echo "i18n-check.test: OK (5 skenario)"
