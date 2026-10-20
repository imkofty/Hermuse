#!/bin/bash
# Test scripts/check-tunnel-schema.sh dengan wrangler stub:
# shim menjawab --command dengan JSON sesuai MOCK_SCHEMA.
#   full -> semua tabel/kolom/index ada  => exit 0
#   old  -> skema pra-migrasi (serba kurang) => exit 1 + menyebut migrasi
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/bin"
mkdir -p "$BIN"
fail=0

cat > "$BIN/wrangler" <<'EOF'
#!/bin/bash
cmd=""
prev=""
for a in "$@"; do
  [ "$prev" = "--command" ] && cmd="$a"
  prev="$a"
done
emit() { printf '[{"results":[%s],"success":true}]' "$1"; }
if [ "${MOCK_SCHEMA:-full}" = "full" ]; then
  case "$cmd" in
    *pragma_index_info*idx_tunnel_requests_idem*)  emit '{"name":"idempotency_key"},{"name":"idem_principal"}' ;;
    *pragma_index_info*idx_tunnel_responses_idem*) emit '{"name":"idempotency_key"},{"name":"idem_principal"}' ;;
    *tunnel_requests*)  emit '{"name":"id"},{"name":"claim_token"},{"name":"claimed_at"},{"name":"idempotency_key"},{"name":"idem_principal"},{"name":"idem_fingerprint"}' ;;
    *tunnel_responses*) emit '{"name":"id"},{"name":"idempotency_key"},{"name":"idem_principal"},{"name":"idem_fingerprint"}' ;;
    *sqlite_master*)    emit '{"name":"tunnel_requests"},{"name":"tunnel_responses"},{"name":"tunnel_rate_limits"},{"name":"idx_tunnel_requests_idem"},{"name":"idx_tunnel_responses_idem"}' ;;
    *) emit '' ;;
  esac
else
  case "$cmd" in
    *pragma_index_info*) emit '{"name":"idempotency_key"}' ;;
    *tunnel_requests*)  emit '{"name":"id"}' ;;
    *tunnel_responses*) emit '{"name":"id"}' ;;
    *sqlite_master*)    emit '{"name":"tunnel_requests"},{"name":"tunnel_responses"}' ;;
    *) emit '' ;;
  esac
fi
exit 0
EOF
chmod +x "$BIN/wrangler"

# PATH di semua pemanggilan di bawah: stub wrangler PALING DEPAN, tapi
# PATH asli dipertahankan — node di CI tinggal di toolcache setup-node,
# bukan /usr/bin; membuang PATH asli membuat skrip exit 2 ("node tidak
# ditemukan") padahal skripnya benar (pola bug yang sama dengan fix
# installer-version di putaran 2).

# 1. Skema lengkap -> exit 0 + pesan OK
out="$(MOCK_SCHEMA=full PATH="$BIN:$PATH" bash "$ROOT/scripts/check-tunnel-schema.sh" mydb 2>&1)"
rc=$?
[ $rc -eq 0 ] || { echo "FAIL [skema lengkap]: exit=$rc, seharusnya 0. Output: $out"; fail=1; }
printf '%s' "$out" | grep -q "^OK:" || { echo "FAIL [skema lengkap]: pesan OK tidak ada. Output: $out"; fail=1; }

# 2. Skema lama -> exit 1 + menunjuk migrasi yang kurang
out="$(MOCK_SCHEMA=old PATH="$BIN:$PATH" bash "$ROOT/scripts/check-tunnel-schema.sh" mydb 2>&1)"
rc=$?
[ $rc -eq 1 ] || { echo "FAIL [skema lama]: exit=$rc, seharusnya 1. Output: $out"; fail=1; }
printf '%s' "$out" | grep -q "001-claim-lease.sql" || { echo "FAIL [skema lama]: tidak menyebut migrasi 001. Output: $out"; fail=1; }
printf '%s' "$out" | grep -q "003-response-idempotency.sql" || { echo "FAIL [skema lama]: tidak menyebut migrasi 003. Output: $out"; fail=1; }
printf '%s' "$out" | grep -q "004-idempotency-principal.sql" || { echo "FAIL [skema lama]: tidak menyebut migrasi 004. Output: $out"; fail=1; }

# 3. Tanpa argumen -> exit 2
PATH="$BIN:$PATH" bash "$ROOT/scripts/check-tunnel-schema.sh" >/dev/null 2>&1
[ $? -eq 2 ] || { echo "FAIL [tanpa argumen]: exit harus 2"; fail=1; }

if [ $fail -eq 0 ]; then
  echo "schema-check test OK"
fi
exit $fail
