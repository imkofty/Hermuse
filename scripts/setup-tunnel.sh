#!/usr/bin/env bash
# Setup Cloudflare polling tunnel: Pages project + D1 + secret + deploy + key lokal.
# Prasyarat: wrangler login ATAU CLOUDFLARE_API_TOKEN di environment.
# Token Cloudflare dipakai transient saja — tidak disimpan di file mana pun.
#
# Cara pakai:
#   bash scripts/setup-tunnel.sh <nama-pages-project> <nama-d1>
# Contoh:
#   bash scripts/setup-tunnel.sh 9router-tunnel-kamu tunnel-9router
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/i18n.sh
. "$SCRIPT_DIR/../lib/i18n.sh"

log() { printf '\033[1;32m[tunnel-setup]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[tunnel-setup]\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31m[tunnel-setup]\033[0m %s\n' "$*" >&2; exit 1; }

PROJECT="${1:-}"; DB_NAME="${2:-}"
[ -n "$PROJECT" ] && [ -n "$DB_NAME" ] || die "$(t tunnel_usage "$0")"

command -v wrangler >/dev/null 2>&1 || die "$(t tunnel_need_wrangler)"
command -v node >/dev/null 2>&1 || die "$(t tunnel_need_node)"
[ -n "${CLOUDFLARE_API_TOKEN:-}" ] || warn "$(t tunnel_no_token)"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TUNNEL_DIR="$SCRIPT_DIR/../tunnel"
PAGES_DIR="$TUNNEL_DIR/pages-tunnel"
KEY_FILE="$HOME/.tunnel-key"

# --- 1. Generate tunnel key (disimpan 600, tidak pernah di-commit) ---
if [ -f "$KEY_FILE" ]; then
  warn "$(t tunnel_key_exists "$KEY_FILE")"
else
  log "$(t tunnel_gen_key)"
  openssl rand -hex 32 > "$KEY_FILE"
  chmod 600 "$KEY_FILE"
fi
TUNNEL_KEY="$(cat "$KEY_FILE")"

# --- 2. Buat D1 database ---
log "$(t tunnel_mk_d1 "$DB_NAME")"
if ! wrangler d1 list 2>/dev/null | grep -q "$DB_NAME"; then
  wrangler d1 create "$DB_NAME"
else
  warn "$(t tunnel_d1_exists "$DB_NAME")"
fi

# --- 3. Terapkan skema + migrasi berversi (ledger) ---
# Seluruh logika ada di scripts/tunnel-migrate.sh: schema.sql, lalu
# migrasi 001 -> 004 BERURUTAN yang belum tercatat di ledger
# schema_migrations, lalu PREFLIGHT skema wajib. Pendekatan lama
# (migrasi hanya jalan bila schema.sql gagal) terbukti melewatkan
# migrasi 004 pada database versi 003 — schema.sql di sana SUKSES
# sebagai no-op — jadi kegagalan runner di sini menggagalkan setup.
bash "$SCRIPT_DIR/tunnel-migrate.sh" "$DB_NAME" || die "$(t tunnel_schema_incomplete)"

# --- 4. Siapkan wrangler.toml dari template ---
DB_ID="$(wrangler d1 list 2>/dev/null | grep -A1 "$DB_NAME" | grep -oE '[0-9a-f-]{36}' | head -1)"
[ -n "$DB_ID" ] || die "$(t tunnel_d1_noid)"
sed -e "s/^name = .*/name = \"$PROJECT\"/" \
    -e "s/^database_name = .*/database_name = \"$DB_NAME\"/" \
    -e "s/^database_id = .*/database_id = \"$DB_ID\"/" \
    "$PAGES_DIR/wrangler.toml.example" > "$PAGES_DIR/wrangler.toml"
log "$(t tunnel_wrangler_toml "$PROJECT")"

# --- 5. Buat Pages project bila belum ada ---
log "$(t tunnel_ensure_pages "$PROJECT")"
wrangler pages project create "$PROJECT" --production-branch=main 2>/dev/null \
  || warn "$(t tunnel_pages_exists "$PROJECT")"

# --- 6. Set TUNNEL_KEY sebagai Pages secret ---
log "$(t tunnel_set_secret)"
printf '%s' "$TUNNEL_KEY" | wrangler pages secret put TUNNEL_KEY --project-name="$PROJECT"

# --- 6b. Health key: kunci probe kesehatan watchdog (file 600 di root
# repo, sejajar .tunnel-url; TIDAK pernah di-commit — lihat .gitignore).
# Server menolak probe tanpa kunci ini (fail-closed), dan watchdog
# hanya menganggap tunnel sehat bila probe ini dijawab client lokal.
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
HEALTH_KEY_FILE="$REPO_ROOT/.health-key"
if [ -f "$HEALTH_KEY_FILE" ]; then
  warn "$(t tunnel_health_key_exists "$HEALTH_KEY_FILE")"
else
  log "$(t tunnel_gen_health_key)"
  openssl rand -hex 32 > "$HEALTH_KEY_FILE"
  chmod 600 "$HEALTH_KEY_FILE"
fi
printf '%s' "$(cat "$HEALTH_KEY_FILE")" | wrangler pages secret put HEALTH_KEY --project-name="$PROJECT"

# --- 6c. Gate dashboard: default FAIL-CLOSED untuk deployment publik.
# Password gate dibuatkan, disimpan 600 di root repo (.gate-pw), dan
# dipasang sebagai Pages secret GATE_PASSWORD + REQUIRE_GATE=1 —
# tanpa ini, siapa pun yang tahu URL tunnel bisa membuka dashboard.
# Opt-out sadar risiko: SETUP_NO_GATE=1 (dengan peringatan keras).
GATE_PW_FILE="$REPO_ROOT/.gate-pw"
if [ "${SETUP_NO_GATE:-}" = "1" ]; then
  warn "$(t tunnel_gate_skipped)"
else
  if [ ! -f "$GATE_PW_FILE" ]; then
    log "$(t tunnel_gen_gate_pw)"
    openssl rand -hex 16 > "$GATE_PW_FILE"
    chmod 600 "$GATE_PW_FILE"
  fi
  printf '%s' "$(cat "$GATE_PW_FILE")" | wrangler pages secret put GATE_PASSWORD --project-name="$PROJECT"
  printf '1' | wrangler pages secret put REQUIRE_GATE --project-name="$PROJECT"
  log "$(t tunnel_gate_pw_file "$GATE_PW_FILE")"
fi

# --- 6d. Password dashboard 9Router (.dashboard-pw di root repo, 600,
# TIDAK pernah di-commit — lihat .gitignore). start-9router.sh MENOLAK
# boot bila .tunnel-url ada tapi .dashboard-pw tidak ada/kosong
# (fail-closed putaran 3+4), jadi setup WAJIB memprovision-nya —
# sebelum ini instalasi bersih macet persis di langkah itu. Pola sama
# seperti .gate-pw: generate acak kuat hanya bila belum ada isinya;
# file yang sudah berisi TIDAK pernah ditimpa.
DASH_PW_FILE="$REPO_ROOT/.dashboard-pw"
if [ ! -s "$DASH_PW_FILE" ]; then
  log "$(t tunnel_gen_dashboard_pw)"
  openssl rand -hex 16 > "$DASH_PW_FILE"
  chmod 600 "$DASH_PW_FILE"
fi

# --- 7. Deploy Pages Functions ---
log "$(t tunnel_deploy)"
(cd "$PAGES_DIR" && wrangler pages deploy . --project-name="$PROJECT")

BASE_URL="https://${PROJECT}.pages.dev"
log "$(t tunnel_done "$BASE_URL")"

cat << EOF

============================================================
 Selesai! Tunnel URL: $BASE_URL

 Langkah berikutnya (dari root repo ini):
  1. Pastikan 9Router jalan:  bash restart-9router.sh
  2. Simpan URL tunnel: echo -n '$BASE_URL' > .tunnel-url && chmod 600 .tunnel-url
  3. Jalankan tunnel client: bash restart-tunnel.sh
     (atau manual: TUNNEL_BASE_URL=$BASE_URL TUNNEL_KEY_FILE=$KEY_FILE node tunnel-client.mjs)
  4. Jalankan gateway Telegram: bash start-gateway.sh
  5. Pasang watchdog di cron: */5 * * * * $REPO_ROOT/watchdog.sh
     (probe kesehatannya memakai .health-key yang dibuat setup ini)
  6. Dashboard publik ter-gate password: kata sandinya di $GATE_PW_FILE
     (user Basic auth default: hermuse). Ganti dari file itu bila perlu.
  7. Password dashboard 9Router dibuatkan di $DASH_PW_FILE (chmod 600) —
     dibaca start-9router.sh; tanpa file ini 9Router menolak jalan
     selama .tunnel-url ada. Ganti isinya bila ingin password sendiri.
============================================================
EOF
