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
#
# Putaran 5: selain keberadaan nama index, KOLOM kedua index
# idempotency kini ikut diverifikasi — index harus gabungan
# (idempotency_key, idem_principal). Database versi 003 punya index
# bernama sama tapi berkolom tunggal, dan cek nama saja meloloskannya
# (itulah celah yang membuat migrasi 004 terlewat saat upgrade).
# Executor SQL sama dengan runner migrasi (scripts/sql-exec.sh):
# wrangler D1, atau SQLite lokal bila TUNNEL_SQLITE_FILE ter-set.
set -uo pipefail

DB="${1:-}"
if [ -z "$DB" ]; then
  echo "usage: bash scripts/check-tunnel-schema.sh <nama-d1>" >&2
  exit 2
fi
if [ -n "${TUNNEL_SQLITE_FILE:-}" ]; then
  command -v python3 >/dev/null 2>&1 || { echo "python3 tidak ditemukan di PATH" >&2; exit 2; }
else
  command -v wrangler >/dev/null 2>&1 || { echo "wrangler tidak ditemukan di PATH" >&2; exit 2; }
  command -v node >/dev/null 2>&1 || { echo "node tidak ditemukan di PATH" >&2; exit 2; }
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SQL_DB="$DB"
# shellcheck source=sql-exec.sh
. "$ROOT/scripts/sql-exec.sh"

# Ambil daftar nama (kolom/tabel/index) dari satu query, satu per baris.
names() { # $1 = SQL "SELECT name FROM ..."
  sql_query "$1"
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

# Kolom index idempotency harus GABUNGAN (idempotency_key,
# idem_principal) — nama index yang sama dengan kolom tunggal adalah
# sisa versi 002/003 dan TIDAK lolos (putaran 5).
REQ_IDX_COLS="$(names "SELECT name FROM pragma_index_info('idx_tunnel_requests_idem')")"
RES_IDX_COLS="$(names "SELECT name FROM pragma_index_info('idx_tunnel_responses_idem')")"
need_idx() { # $1 = daftar kolom index terurut, $2 = nama index
  local joined
  joined="$(printf '%s\n' "$1" | paste -sd, -)"
  if [ "$joined" != "idempotency_key,idem_principal" ]; then
    echo "MISSING: $2 belum index gabungan (idempotency_key, idem_principal)  -> jalankan: wrangler d1 execute $DB --remote --file=$ROOT/tunnel/migrations/004-idempotency-principal.sql"
    missing=1
  fi
}
need_idx "$REQ_IDX_COLS" idx_tunnel_requests_idem
need_idx "$RES_IDX_COLS" idx_tunnel_responses_idem

if [ "$missing" -eq 0 ]; then
  echo "OK: skema tunnel lengkap (migrasi 001-004 terkonfirmasi) untuk D1 '$DB'."
else
  echo "Skema BELUM lengkap — fungsi tunnel akan error sampai migrasi di atas dijalankan BERURUTAN (001, lalu 002, lalu 003, lalu 004)." >&2
fi
exit "$missing"
