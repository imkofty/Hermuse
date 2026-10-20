#!/usr/bin/env bash
# Runner migrasi skema tunnel BERVERSI (putaran 5) — dipanggil
# setup-tunnel.sh; bisa juga dijalankan sendiri untuk upgrade manual:
#   bash scripts/tunnel-migrate.sh <nama-d1>
#
# Masalah yang ditutup (temuan audit putaran 4): setup lama hanya
# menjalankan migrasi bila eksekusi schema.sql GAGAL. Pada database
# versi 003, schema.sql justru SUKSES — semua CREATE ... IF NOT EXISTS
# menjadi no-op, termasuk index gabungan 004 yang namanya sudah ada
# (definisi lama) — sehingga kolom 004 tidak pernah terpasang dan
# setup selesai tanpa skema lengkap.
#
# Runner ini eksplisit & tercatat:
#   1. schema.sql diterapkan (ditoleransi bila gagal — database lama
#      memang bisa gagal di statement index gabungan; migrasi di
#      bawah menambalnya, dan preflight akhir yang memutuskan).
#   2. Tabel ledger schema_migrations (version + applied_at) dibuat.
#   3. File tunnel/migrations/*.sql diterapkan BERURUTAN, hanya yang
#      belum tercatat di ledger. Per statement: error "duplicate
#      column"/"already exists" ditoleransi (berarti bagian itu sudah
#      pernah diterapkan di database warisan tanpa ledger); error
#      lain menggagalkan runner. Versi dicatat SETELAH file-nya
#      selesai diterapkan.
#   4. PREFLIGHT WAJIB: scripts/check-tunnel-schema.sh harus exit 0.
#      Skema akhir tidak lengkap = runner GAGAL (exit 1) — setup
#      tidak boleh lagi "selesai" di atas skema setengah jadi.
#
# Executor SQL: wrangler D1 (default) atau SQLite lokal bila env
# TUNNEL_SQLITE_FILE ter-set — lihat scripts/sql-exec.sh. Jalur lokal
# itulah yang dijalankan tests/migration-upgrade.test.sh.
#
# Exit: 0 = skema lengkap & tercatat. 1 = migrasi/preflight gagal.
#       2 = prasyarat tidak terpenuhi.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/i18n.sh
. "$SCRIPT_DIR/../lib/i18n.sh"
# shellcheck source=sql-exec.sh
. "$SCRIPT_DIR/sql-exec.sh"

log() { printf '\033[1;32m[tunnel-setup]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[tunnel-setup]\033[0m %s\n' "$*" >&2; }

DB_NAME="${1:-}"
[ -n "$DB_NAME" ] || { echo "usage: bash scripts/tunnel-migrate.sh <nama-d1>" >&2; exit 2; }
SQL_DB="$DB_NAME"
TUNNEL_DIR="$SCRIPT_DIR/../tunnel"

if [ -n "${TUNNEL_SQLITE_FILE:-}" ]; then
  command -v python3 >/dev/null 2>&1 || { echo "python3 tidak ditemukan di PATH" >&2; exit 2; }
else
  command -v wrangler >/dev/null 2>&1 || { echo "wrangler tidak ditemukan di PATH" >&2; exit 2; }
  command -v node >/dev/null 2>&1 || { echo "node tidak ditemukan di PATH" >&2; exit 2; }
fi

# --- 1. Skema dasar (database baru dibuat dari sini) ---
log "$(t tunnel_apply_schema)"
sql_exec_file "$TUNNEL_DIR/schema.sql" \
  || warn "schema.sql tidak bersih di database ini — lanjut ke migrasi berversi (preflight akhir yang memutuskan)"

# --- 2. Ledger migrasi ---
sql_exec_stmt "CREATE TABLE IF NOT EXISTS schema_migrations (version TEXT PRIMARY KEY, applied_at INTEGER NOT NULL DEFAULT 0)" \
  || { echo "gagal membuat tabel schema_migrations" >&2; exit 1; }
APPLIED="$(sql_query "SELECT version FROM schema_migrations")"

# --- 3. Migrasi berurutan yang belum tercatat ---
log "$(t tunnel_apply_migrations)"
for mig in "$TUNNEL_DIR"/migrations/*.sql; do
  ver="$(basename "$mig" .sql)"
  if printf '%s\n' "$APPLIED" | grep -qx "$ver"; then
    continue # sudah tercatat di ledger — jangan diterapkan ulang
  fi
  log "$(t tunnel_apply_migration "$ver")"
  # Terapkan per statement: buang komentar -- dulu (komentar boleh
  # mengandung titik koma), lalu potong pada ';'. Statement kosong
  # dilewati. Error duplikat ditoleransi per statement (database
  # warisan pra-ledger), error lain fatal.
  while IFS= read -r stmt; do
    stmt="$(printf '%s' "$stmt" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [ -n "$stmt" ] || continue
    if ! out="$(sql_exec_stmt "$stmt" 2>&1)"; then
      case "$out" in
        *"duplicate column"*|*"already exists"*)
          warn "migration $ver: statement dilewati (sudah pernah diterapkan): $stmt"
          ;;
        *)
          echo "migration $ver GAGAL pada statement: $stmt" >&2
          printf '%s\n' "$out" >&2
          exit 1
          ;;
      esac
    fi
  done < <(sed 's/--.*$//' "$mig" | tr '\n' ' ' | tr ';' '\n')
  sql_exec_stmt "INSERT OR IGNORE INTO schema_migrations (version, applied_at) VALUES ('$ver', $(date +%s))" \
    || { echo "gagal mencatat migrasi $ver di schema_migrations" >&2; exit 1; }
done

# --- 4. Preflight skema WAJIB (gagal = gagal keras) ---
if ! bash "$SCRIPT_DIR/check-tunnel-schema.sh" "$DB_NAME"; then
  echo "$(t tunnel_schema_incomplete)" >&2
  exit 1
fi
exit 0
