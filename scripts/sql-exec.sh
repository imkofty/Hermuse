# shellcheck shell=bash
# Executor SQL bersama untuk skema/migrasi tunnel — DISOURCE (bukan
# dijalankan) oleh scripts/tunnel-migrate.sh dan
# scripts/check-tunnel-schema.sh.
#
# Dua jalur eksekusi, dipilih lewat environment:
#   - Default: wrangler D1 remote pada database bernama $SQL_DB
#     (jalur produksi yang dipakai setup-tunnel.sh).
#   - TUNNEL_SQLITE_FILE ter-set: python3 + sqlite3 pada file SQLite
#     lokal itu. Jalur ini membuat SELURUH logika migrasi &
#     preflight bisa dites lokal/CI tanpa Cloudflare (dipakai
#     tests/migration-upgrade.test.sh) — kode yang diuji persis kode
#     yang jalan di produksi, hanya transport SQL-nya yang berbeda.
#
# Fungsi (semua memakai $SQL_DB sebagai nama database wrangler):
#   sql_exec_file <file.sql>  jalankan seluruh isi file SQL.
#   sql_exec_stmt <sql>       jalankan SATU statement; nonzero bila gagal.
#   sql_query <sql>           cetak nilai kolom PERTAMA tiap baris,
#                             satu per baris (untuk query "SELECT name
#                             FROM ..." & pembacaan ledger).

sql_exec_file() {
  if [ -n "${TUNNEL_SQLITE_FILE:-}" ]; then
    SQL_FILE_PATH="$1" python3 -c '
import os, sqlite3, sys
db = sqlite3.connect(os.environ["TUNNEL_SQLITE_FILE"])
try:
    with open(os.environ["SQL_FILE_PATH"], encoding="utf-8") as f:
        db.executescript(f.read())
    db.commit()
except Exception as e:
    print(str(e), file=sys.stderr)
    sys.exit(1)
'
  else
    wrangler d1 execute "$SQL_DB" --remote --file="$1"
  fi
}

sql_exec_stmt() {
  if [ -n "${TUNNEL_SQLITE_FILE:-}" ]; then
    SQL_TEXT="$1" python3 -c '
import os, sqlite3, sys
db = sqlite3.connect(os.environ["TUNNEL_SQLITE_FILE"])
try:
    db.execute(os.environ["SQL_TEXT"])
    db.commit()
except Exception as e:
    print(str(e), file=sys.stderr)
    sys.exit(1)
'
  else
    wrangler d1 execute "$SQL_DB" --remote --command "$1"
  fi
}

sql_query() {
  if [ -n "${TUNNEL_SQLITE_FILE:-}" ]; then
    SQL_TEXT="$1" python3 -c '
import os, sqlite3, sys
db = sqlite3.connect(os.environ["TUNNEL_SQLITE_FILE"])
try:
    rows = db.execute(os.environ["SQL_TEXT"]).fetchall()
except Exception as e:
    print(str(e), file=sys.stderr)
    sys.exit(1)
for r in rows:
    print(r[0])
'
  else
    wrangler d1 execute "$SQL_DB" --remote --json --command "$1" 2>/dev/null \
      | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const j=JSON.parse(s);for(const r of (j[0]?.results||[])) console.log(Object.values(r)[0])}catch{}})'
  fi
}
