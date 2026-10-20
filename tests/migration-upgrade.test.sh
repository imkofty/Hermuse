#!/bin/bash
# Test upgrade migrasi (putaran 5, FIX 2): database versi 003 yang
# dibuat SEBELUM ledger ada harus naik ke skema lengkap lewat jalur
# migrasi setup yang sebenarnya (scripts/tunnel-migrate.sh dengan
# executor SQLite lokal — TUNNEL_SQLITE_FILE, lihat
# scripts/sql-exec.sh), TANPA intervensi manual.
#
# Reproduksi celah putaran 4: pada DB 003, schema.sql lama SUKSES
# sebagai no-op (semua CREATE ... IF NOT EXISTS; index gabungan 004
# tertahan nama index lama berkolom tunggal) sehingga setup selesai
# tanpa kolom 004. Tes ini membangun DB 003 persis seperti itu, lalu
# membuktikan setelah runner jalan:
#   1. Kolom idem_principal + idem_fingerprint ada di tunnel_requests
#      DAN tunnel_responses.
#   2. Kedua index idempotency adalah index unik GABUNGAN
#      (idempotency_key, idem_principal) — bukan lagi kolom tunggal.
#   3. Ledger schema_migrations mencatat SEMUA versi (001-004).
#   4. Preflight scripts/check-tunnel-schema.sh (jalur executor yang
#      sama) exit 0.
#   5. Runner idempoten: run kedua exit 0 dan ledger tidak berubah.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
DB="$TMP/legacy-003.db"
fail=0
check() { # $1 = deskripsi, $2 = kondisi (exit code gaya test)
  if [ "$2" -ne 0 ]; then
    echo "FAIL [$1]"
    fail=1
  fi
}

# --- 1. Bangun database versi 003: skema pra-001 + migrasi 001-003 ---
python3 - "$DB" "$ROOT" <<'PY' || { echo "FAIL [bangun DB 003]"; exit 1; }
import sqlite3, sys
db_path, root = sys.argv[1], sys.argv[2]
db = sqlite3.connect(db_path)
# Skema tertua (pra-migrasi): hanya kolom dasar kedua tabel.
db.executescript(
    "CREATE TABLE tunnel_requests (id TEXT PRIMARY KEY, method TEXT, path TEXT,"
    " headers TEXT, body TEXT, status TEXT, created_at INTEGER);"
    "CREATE TABLE tunnel_responses (id TEXT PRIMARY KEY, status_code INTEGER,"
    " headers TEXT, body TEXT, created_at INTEGER);"
)
for mig in ("001-claim-lease", "002-idempotency-ratelimit", "003-response-idempotency"):
    with open(f"{root}/tunnel/migrations/{mig}.sql", encoding="utf-8") as f:
        db.executescript(f.read())
db.commit()
# Sanity: ini BENAR-BENAR DB 003 — kolom 004 belum ada, index masih
# berkolom tunggal (definisi 002/003).
cols = [r[1] for r in db.execute("PRAGMA table_info(tunnel_requests)")]
assert "idem_principal" not in cols, "DB awal bukan 003: idem_principal sudah ada"
idx = [r[2] for r in db.execute("PRAGMA index_info('idx_tunnel_requests_idem')")]
assert idx == ["idempotency_key"], f"DB awal bukan 003: index={idx}"
db.close()
PY

# --- 2. Jalankan jalur migrasi setup (tanpa intervensi manual) ---
TUNNEL_SQLITE_FILE="$DB" bash "$ROOT/scripts/tunnel-migrate.sh" db-lokal-test >/dev/null 2>&1
check "tunnel-migrate pada DB 003 exit 0" $?

# --- 3-5. Verifikasi hasil akhir ---
python3 - "$DB" <<'PY'
import sqlite3, sys
db = sqlite3.connect(sys.argv[1])
ok = True
def expect(cond, label):
    global ok
    if not cond:
        print("FAIL [" + label + "]")
        ok = False

for tbl in ("tunnel_requests", "tunnel_responses"):
    cols = [r[1] for r in db.execute(f"PRAGMA table_info({tbl})")]
    expect("idem_principal" in cols, f"{tbl}: idem_principal ada")
    expect("idem_fingerprint" in cols, f"{tbl}: idem_fingerprint ada")

for idx_name in ("idx_tunnel_requests_idem", "idx_tunnel_responses_idem"):
    cols = [r[2] for r in db.execute(f"PRAGMA index_info('{idx_name}')")]
    expect(cols == ["idempotency_key", "idem_principal"],
           f"{idx_name}: kolom gabungan (aktual: {cols})")
    uniq = [r[2] for r in db.execute("PRAGMA index_list('tunnel_requests')")] + \
           [r[2] for r in db.execute("PRAGMA index_list('tunnel_responses')")]
    expect(1 in uniq, "ada index unik terpasang")

versions = sorted(r[0] for r in db.execute("SELECT version FROM schema_migrations"))
expect(versions == ["001-claim-lease", "002-idempotency-ratelimit",
                    "003-response-idempotency", "004-idempotency-principal"],
       f"ledger mencatat semua versi (aktual: {versions})")
sys.exit(0 if ok else 1)
PY
check "kolom 004 + index gabungan + ledger lengkap" $?

TUNNEL_SQLITE_FILE="$DB" bash "$ROOT/scripts/check-tunnel-schema.sh" db-lokal-test >/dev/null 2>&1
check "preflight check-tunnel-schema exit 0" $?

TUNNEL_SQLITE_FILE="$DB" bash "$ROOT/scripts/tunnel-migrate.sh" db-lokal-test >/dev/null 2>&1
check "tunnel-migrate kedua (idempoten) exit 0" $?
n="$(python3 -c 'import sqlite3,sys; print(sqlite3.connect(sys.argv[1]).execute("SELECT COUNT(*) FROM schema_migrations").fetchone()[0])' "$DB")"
[ "$n" = "4" ]; check "ledger tetap 4 baris setelah run kedua" $?

if [ $fail -eq 0 ]; then
  echo "migration-upgrade test OK"
fi
exit $fail
