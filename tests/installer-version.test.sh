#!/bin/bash
# Test penegakan versi pin installer: fungsi pkg_version + ensure_pkg
# DIEKSTRAK dari scripts/install.sh yang sebenarnya (bukan salinan), lalu
# dijalankan melawan npm stub yang mensimulasikan pemasangan paket.
# Skenario: belum terpasang / versi sudah cocok / upgrade / downgrade /
# npm memasang versi yang salah (installer wajib gagal, bukan diam).
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME/.npm-global/lib/node_modules" "$TMP/bin"
fail=0

# npm stub: "memasang" paket dengan menulis package.json versi dari arg
# terakhir (paket@versi). FAKE_NPM_VERSION menimpa versi hasil (simulasi
# registry yang memberi versi tak terduga).
cat > "$TMP/bin/npm" <<'EOF'
#!/bin/bash
for a in "$@"; do
  case "$a" in
    *@*) pkg="${a%@*}"; ver="${a##*@}" ;;
  esac
done
ver="${FAKE_NPM_VERSION:-$ver}"
d="$HOME/.npm-global/lib/node_modules/$pkg"
mkdir -p "$d"
printf '{"name":"%s","version":"%s"}\n' "$pkg" "$ver" > "$d/package.json"
echo "npm-stub installed $pkg@$ver"
EOF
chmod +x "$TMP/bin/npm"
# PATH: stub npm PALING DEPAN, tapi PATH asli dipertahankan — node di CI
# tinggal di toolcache setup-node, bukan /usr/bin; membuang PATH asli
# membuat pkg_version gagal diam-diam (node tidak ditemukan).
export PATH="$TMP/bin:$PATH"

# Ekstrak definisi fungsi asli dari installer (antara pkg_version() dan
# panggilan ensure_pkg pertama), lengkapi dengan log/warn + i18n asli.
{
  echo 'log() { printf "[install] %s\n" "$*"; }'
  echo 'warn() { printf "[install] %s\n" "$*" >&2; }'
  echo ". \"$ROOT/lib/i18n.sh\""
  sed -n '/^pkg_version()/,/^ensure_pkg "9router"/p' "$ROOT/scripts/install.sh" | sed '$d'
} > "$TMP/harness.sh"
grep -q 'ensure_pkg()' "$TMP/harness.sh" || { echo "FAIL: ekstraksi fungsi installer gagal"; exit 1; }

set_ver() { # $1 = versi yang "terpasang" untuk fakepkg (kosong = belum ada)
  local d="$HOME/.npm-global/lib/node_modules/fakepkg"
  rm -rf "$d"
  if [ -n "$1" ]; then
    mkdir -p "$d"
    printf '{"name":"fakepkg","version":"%s"}\n' "$1" > "$d/package.json"
  fi
}
run_case() { # $1 = deskripsi, $2 = versi awal, $3 = pin, $4 = exit diharapkan, $5 = FAKE_NPM_VERSION (opsional)
  set_ver "$2"
  local out code
  out="$(FAKE_NPM_VERSION="${5:-}" bash -c ". \"$TMP/harness.sh\"; ensure_pkg fakepkg \"$3\"" 2>&1)"
  code=$?
  if [ $code -ne "$4" ]; then
    echo "FAIL [$1]: exit $code, seharusnya $4. Output: $out"
    fail=1
  fi
}

run_case "belum terpasang" "" "1.2.3" 0
run_case "versi sudah cocok" "1.2.3" "1.2.3" 0
run_case "upgrade" "1.0.0" "1.2.3" 0
run_case "downgrade" "2.0.0" "1.2.3" 0
run_case "npm memberi versi salah" "" "1.2.3" 1 "9.9.9"

# Setelah upgrade, versi di disk harus persis pin.
set_ver "1.0.0"
bash -c ". \"$TMP/harness.sh\"; ensure_pkg fakepkg 1.2.3" >/dev/null 2>&1
got="$(node -e 'console.log(require(process.argv[1]).version)' "$HOME/.npm-global/lib/node_modules/fakepkg/package.json")"
[ "$got" = "1.2.3" ] || { echo "FAIL [versi akhir]: $got, seharusnya 1.2.3"; fail=1; }

if [ $fail -eq 0 ]; then
  echo "installer version test OK"
fi
exit $fail
