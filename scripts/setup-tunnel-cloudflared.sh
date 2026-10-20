#!/usr/bin/env bash
# Setup Cloudflare Tunnel (cloudflared) untuk JARINGAN NORMAL.
# JANGAN dipakai di sandbox/VM asal — di sana cloudflared diblokir total
# (UDP/QUIC mati, TLS ke edge di-MITM, proxy menolak CONNECT :7844).
# Arsip kegagalannya: docs/arsip-tunnel-gagal.md
#
# Prasyarat: akun Cloudflare gratis + zone DNS milikmu untuk <hostname>.
# Login Cloudflare butuh browser (interaktif) — script ini tidak full non-interaktif.
#
# Cara pakai:
#   bash scripts/setup-tunnel-cloudflared.sh <nama-tunnel> <hostname>
# Contoh:
#   bash scripts/setup-tunnel-cloudflared.sh 9router-kamu 9router.contoh.com
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/i18n.sh
. "$SCRIPT_DIR/../lib/i18n.sh"

log() { printf '\033[1;32m[cf-tunnel]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[cf-tunnel]\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31m[cf-tunnel]\033[0m %s\n' "$*" >&2; exit 1; }

NAME="${1:-}"; HOSTNAME="${2:-}"
[ -n "$NAME" ] && [ -n "$HOSTNAME" ] || die "$(t cf_usage "$0")"
[[ "$HOSTNAME" == *.* ]] || die "$(t cf_bad_hostname "$HOSTNAME")"

CLOUDFLARED_DIR="$HOME/.cloudflared"
BIN_DIR="$HOME/.local/bin"

# --- 1. Install cloudflared bila belum ada (binary statis, tanpa root) ---
if ! command -v cloudflared >/dev/null 2>&1; then
  log "$(t cf_installing)"
  case "$(uname -m)" in
    x86_64)        GOARCH="amd64" ;;
    aarch64|arm64) GOARCH="arm64" ;;
    *) die "$(t cf_unsupported_arch "$(uname -m)")" ;;
  esac
  mkdir -p "$BIN_DIR"
  curl -fsSL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${GOARCH}" \
    -o "$BIN_DIR/cloudflared" || die "$(t cf_install_fail)"
  chmod +x "$BIN_DIR/cloudflared"
  export PATH="$BIN_DIR:$PATH"
else
  log "$(t cf_have "$(cloudflared --version 2>/dev/null | head -1)")"
fi

# --- 2. Login Cloudflare (interaktif, via browser) ---
mkdir -p "$CLOUDFLARED_DIR"
if [ ! -f "$CLOUDFLARED_DIR/cert.pem" ]; then
  log "$(t cf_need_login)"
  cloudflared tunnel login || die "$(t cf_login_fail)"
fi

# --- 3. Buat tunnel (atau pakai yang sudah ada) ---
TUNNEL_ID="$(cloudflared tunnel list 2>/dev/null | awk -v n="$NAME" '$2 == n {print $1; exit}')"
if [ -n "$TUNNEL_ID" ]; then
  warn "$(t cf_exists "$NAME" "$TUNNEL_ID")"
else
  log "$(t cf_creating "$NAME")"
  CREATE_OUT="$(cloudflared tunnel create "$NAME" 2>&1)" || die "$(t cf_no_id)"
  TUNNEL_ID="$(printf '%s\n' "$CREATE_OUT" | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | head -1)"
  [ -n "$TUNNEL_ID" ] || die "$(t cf_no_id)"
  log "$(t cf_created "$NAME" "$TUNNEL_ID")"
fi

CRED="$CLOUDFLARED_DIR/${TUNNEL_ID}.json"
[ -f "$CRED" ] || die "$(t cf_no_cred "$CRED")"

# --- 4. Tulis config ---
CONFIG="$CLOUDFLARED_DIR/hermuse-${NAME}.yml"
log "$(t cf_writing_config "$CONFIG")"
cat > "$CONFIG" <<EOF
# Dibuat oleh Hermuse scripts/setup-tunnel-cloudflared.sh — HANYA jaringan normal.
tunnel: ${TUNNEL_ID}
credentials-file: ${CRED}
ingress:
  - hostname: ${HOSTNAME}
    service: http://127.0.0.1:20128
  - service: http_status:404
EOF
chmod 600 "$CONFIG"

# --- 5. Route DNS: CNAME <hostname> -> <tunnel-id>.cfargotunnel.com ---
log "$(t cf_routing_dns "$HOSTNAME" "$TUNNEL_ID")"
if ! cloudflared tunnel route dns "$TUNNEL_ID" "$HOSTNAME" >/dev/null 2>&1; then
  warn "$(t cf_dns_exists)"
fi

# --- 6. Peringatan bila 9Router belum jalan ---
if ! curl -s -m 8 -o /dev/null http://127.0.0.1:20128/dashboard; then
  warn "$(t cf_9router_warn)"
fi

log "$(t cf_done "$HOSTNAME")"

# Path binary cloudflared yang SEBENARNYA dipakai contoh systemd di bawah:
# bila cloudflared sudah terpasang dari sumber lain (mis. /usr/local/bin),
# ExecStart harus menunjuk ke sana — bukan selalu ke $BIN_DIR.
CLOUDFLARED_BIN="$(command -v cloudflared || echo "$BIN_DIR/cloudflared")"

cat << EOF

============================================================
 Selesai! Dashboard publik: https://$HOSTNAME

 Jalankan tunnel (foreground, biarkan terminal terbuka):
   cloudflared tunnel --config $CONFIG run

 Untuk jalan permanen (contoh systemd user):
   [Unit]
   Description=Hermuse cloudflared tunnel
   After=network-online.target
   [Service]
   ExecStart=$CLOUDFLARED_BIN tunnel --config $CONFIG run
   Restart=always
   [Install]
   WantedBy=default.target

 Bila 'route dns' gagal (record sudah ada / zone beda akun):
   buat manual CNAME $HOSTNAME -> ${TUNNEL_ID}.cfargotunnel.com
   di DNS zone Cloudflare milikmu.

 Catatan:
   - watchdog.sh / doctor.sh repo ini TIDAK memantau cloudflared
     (mereka dibuat untuk tunnel polling). Pantau prosesnya sendiri.
   - Jangan pakai script ini di sandbox/VM asal — cloudflared diblokir
     di sana (lihat docs/arsip-tunnel-gagal.md).
============================================================
EOF
