#!/usr/bin/env bash
# Preflight skema tunnel: pastikan D1 sudah menjalankan SEMUA migrasi.
#
# Fungsi tunnel gagal dengan cara yang membingungkan bila skema lama
# belum dimigrasi (kolom klaim tidak ada -> poll error; kolom
# idempotency respons tidak ada -> respond error). Skrip ini memeriksa
# tabel/kolom/index yang dibutuhkan kode saat ini dan mencetak perintah
# perbaikan yang persis untuk yang kurang.
#
# Cara pakai:
#   bash scripts/check-tunnel-schema.sh <nama-d1>
# Exit 0 = skema lengkap. Exit 1 = ada yang kurang. Exit 2 = prasyarat
# (argumen/wrangler/node) tidak terpenuhi.
set -uo pipefail

DB="${1:-}"
if [ -z "$DB" ]; then
  echo "usage: bash scripts/check-tunnel-schema.sh <nama-d1>" >&2
  exit 2
fi
command -v wrangler >/dev/null 2>&1 || { echo "wrangler tidak ditemukan di PATH" >&2; exit 2; }
command -v node >/dev/null 2>&1 || { echo "node tidak ditemukan di PATH" >&2; exit 2; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Ambil daftar nama (kolom/tabel/index) dari satu query, satu per baris.
names() { # $1 = SQL
  wrangler d1 execute "$DB" --remote --json --command "$1" 2>/dev/null \
    | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const j=JSON.parse(s);for(const r of (j[0]?.results||[])) console.log(r.name)}catch{}})'
}

REQ_COLS="$(names "SELECT name FROM pragma_table_info('tunnel_requests')")"
RES_COLS="$(names "SELECT name FROM pragma_table_info('tunnel_responses')")"
OBJECTS="$(names "SELECT name FROM sqlite_master WHERE type IN ('table','index')")"

missing=0
need() { # $1 = daftar, $2 = nama, $3 = file perbaikan (relatif ke tunnel/)
  if ! printf '%s\n' "$1" | grep -qx "$2"; then
    echo "MISSING: $2  -> jalankan: wrangler d1 execute $DB --remote --file=$ROOT/tunnel/$3"
    missing=1
  fi
}

need "$OBJECTS"  tunnel_requests          schema.sql
need "$OBJECTS"  tunnel_responses         schema.sql
need "$OBJECTS"  tunnel_rate_limits       migrations/002-idempotency-ratelimit.sql
need "$REQ_COLS" claim_token              migrations/001-claim-lease.sql
need "$REQ_COLS" claimed_at               migrations/001-claim-lease.sql
need "$REQ_COLS" idempotency_key          migrations/002-idempotency-ratelimit.sql
need "$RES_COLS" idempotency_key          migrations/003-response-idempotency.sql
need "$REQ_COLS" idem_principal           migrations/004-idempotency-principal.sql
need "$REQ_COLS" idem_fingerprint         migrations/004-idempotency-principal.sql
need "$RES_COLS" idem_principal           migrations/004-idempotency-principal.sql
need "$RES_COLS" idem_fingerprint         migrations/004-idempotency-principal.sql
need "$OBJECTS"  idx_tunnel_requests_idem  migrations/002-idempotency-ratelimit.sql
need "$OBJECTS"  idx_tunnel_responses_idem migrations/003-response-idempotency.sql

if [ "$missing" -eq 0 ]; then
  echo "OK: skema tunnel lengkap (migrasi 001-004 terkonfirmasi) untuk D1 '$DB'."
else
  echo "Skema BELUM lengkap — fungsi tunnel akan error sampai migrasi di atas dijalankan BERURUTAN (001, lalu 002, lalu 003, lalu 004)." >&2
fi
exit "$missing"
