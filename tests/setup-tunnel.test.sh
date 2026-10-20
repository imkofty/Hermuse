#!/bin/bash
# Test scripts/setup-tunnel.sh dengan wrangler stub (tanpa Cloudflare
# asli): membuktikan provisioning file lokal, khususnya putaran 4 —
#   1. Run pertama: .dashboard-pw DIBUAT (non-kosong, chmod 600),
#      bersama .health-key dan .gate-pw seperti sebelumnya.
#   2. Run kedua: .dashboard-pw yang sudah berisi TIDAK ditimpa.
#   3. .dashboard-pw dikosongkan -> run berikutnya meng-generate ulang.
# (start-9router.sh menolak boot tanpa .dashboard-pw yang berisi selama
# .tunnel-url ada — setup yang tidak memprovision-nya membuat instalasi
# bersih macet; regresi yang ditutup tes ini.)
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
APP="$TMP/app"
BIN="$TMP/bin"
HOME_TEST="$TMP/home"
mkdir -p "$APP" "$BIN" "$HOME_TEST"
fail=0

# Salin layout yang dibutuhkan setup (scripts/, lib/, tunnel/) ke temp
# agar file hasil setup tidak menyentuh repo asli.
cp -r "$ROOT/scripts" "$ROOT/lib" "$ROOT/tunnel" "$APP/"

# --- Stub wrangler: cukup untuk seluruh alur setup ---
cat > "$BIN/wrangler" <<'EOF'
#!/bin/bash
case "$1 $2" in
  "d1 list")
    printf 'tunnel-db-test\nb9851c52-9f6e-4dce-a9a9-683ed3a23181\n'
    ;;
  "d1 create"|"d1 execute")
    :
    ;;
  "pages secret")
    cat > /dev/null
    ;;
  "pages project"|"pages deploy")
    :
    ;;
esac
exit 0
EOF
chmod +x "$BIN/wrangler"

run_setup() {
  ( cd "$APP" && HOME="$HOME_TEST" PATH="$BIN:$PATH" \
      bash scripts/setup-tunnel.sh proj-test tunnel-db-test >/dev/null 2>&1 )
}

check() { # $1 = deskripsi, $2 = kondisi (0/1 hasil test -... )
  if [ "$2" -ne 0 ]; then
    echo "FAIL [$1]"
    fail=1
  fi
}

# 1. Run pertama membuat .dashboard-pw berisi + 600
run_setup
check "run pertama exit 0" $?
[ -s "$APP/.dashboard-pw" ]; check ".dashboard-pw terbuat & berisi" $?
[ "$(stat -c %a "$APP/.dashboard-pw")" = "600" ]; check ".dashboard-pw chmod 600" $?
[ -s "$APP/.health-key" ]; check ".health-key tetap dibuat" $?
[ -s "$APP/.gate-pw" ]; check ".gate-pw tetap dibuat" $?
C1="$(cat "$APP/.dashboard-pw")"

# 2. Run kedua TIDAK menimpa password yang sudah ada
run_setup
[ "$(cat "$APP/.dashboard-pw")" = "$C1" ]; check ".dashboard-pw tidak ditimpa" $?

# 3. File dikosongkan -> di-generate ulang
printf '' > "$APP/.dashboard-pw"
run_setup
[ -s "$APP/.dashboard-pw" ]; check ".dashboard-pw kosong di-generate ulang" $?
[ "$(stat -c %a "$APP/.dashboard-pw")" = "600" ]; check ".dashboard-pw hasil generate ulang chmod 600" $?

if [ $fail -eq 0 ]; then
  echo "setup-tunnel test OK"
fi
exit $fail
