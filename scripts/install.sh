#!/usr/bin/env bash
# Install otomatis: Hermes Agent + Node.js + 9Router di VM Linux (Debian/Ubuntu).
# Dijalankan sebagai user biasa (bukan root). Tidak butuh input interaktif
# kecuali saat login provider nanti (langkah manual setelah script selesai).
#
# Cara pakai:
#   bash scripts/install.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/i18n.sh
. "$SCRIPT_DIR/../lib/i18n.sh"

log() { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }

# --- Versi dependensi (di-pin agar instalasi bisa direproduksi) ---
# Naikkan versi lewat env var, mis. HERMUSE_9ROUTER_VERSION=0.6.0 bash scripts/install.sh
# Rollback = jalankan ulang installer dengan versi lama di env var yang sama.
NINE_ROUTER_VERSION="${HERMUSE_9ROUTER_VERSION:-0.5.104}"
WRANGLER_VERSION="${HERMUSE_WRANGLER_VERSION:-4.151.2}"

# --- 1. Cek OS ---
if ! command -v apt-get >/dev/null 2>&1; then
  warn "$(t install_debian_only)"
  exit 1
fi

# --- 1b. sudo harus non-interaktif (sesuai klaim script ini) ---
# Tanpa ini, `sudo apt-get` akan menggantung menunggu password di mesin
# fresh tanpa passwordless sudo — gagal cepat dengan pesan jelas.
if [ "$(id -u)" -ne 0 ]; then
  if ! command -v sudo >/dev/null 2>&1; then
    warn "$(t install_need_sudo)"
    exit 1
  fi
  if ! sudo -n true 2>/dev/null; then
    warn "$(t install_sudo_pw)"
    warn "$(t install_enable_sudo)"
    exit 1
  fi
fi

# --- 2. Dependensi dasar ---
log "$(t install_deps)"
sudo apt-get update -y
sudo apt-get install -y git curl tar ca-certificates

# --- 3. Node.js LTS (dibutuhkan 9Router via npm) ---
if ! command -v node >/dev/null 2>&1; then
  log "$(t install_node)"
  curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
  sudo apt-get install -y nodejs
else
  log "$(t install_have_node "$(node --version)")"
fi

# --- 4. Hermes Agent (installer resmi Nous Research) ---
if ! command -v hermes >/dev/null 2>&1; then
  log "$(t install_hermes)"
  curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash -s -- --skip-browser
  # shellcheck disable=SC1090
  source ~/.bashrc 2>/dev/null || true
  export PATH="$HOME/.local/bin:$PATH"
else
  log "$(t install_have_hermes "$(hermes --version 2>/dev/null || echo '?')")"
fi

# --- 5. 9Router (paket npm) ---
# Install ke $HOME/.npm-global agar konsisten dengan PATH di script lain
# (start-9router.sh, start-pages-tunnel.sh) dan tetap aman tanpa akses root.
if ! command -v 9router >/dev/null 2>&1; then
  log "$(t install_9router)"
  mkdir -p "$HOME/.npm-global"
  npm install -g --prefix "$HOME/.npm-global" "9router@$NINE_ROUTER_VERSION"
  export PATH="$HOME/.npm-global/bin:$PATH"
  # pastikan persisten untuk shell berikutnya
  grep -q '.npm-global/bin' ~/.bashrc 2>/dev/null || \
    echo 'export PATH="$HOME/.npm-global/bin:$PATH"' >> ~/.bashrc
else
  log "$(t install_have_9router "$(9router --version 2>/dev/null || echo '?')")"
fi

# --- 5b. Wrangler (CLI Cloudflare — prasyarat scripts/setup-tunnel.sh) ---
# Dulu setup-tunnel.sh menggantungkan wrangler yang belum tentu ada; sekarang
# installer yang menjamin keberadaannya, di prefix yang sama dengan 9Router.
if ! command -v wrangler >/dev/null 2>&1 && [ ! -x "$HOME/.npm-global/bin/wrangler" ]; then
  log "$(t install_wrangler)"
  mkdir -p "$HOME/.npm-global"
  npm install -g --prefix "$HOME/.npm-global" "wrangler@$WRANGLER_VERSION"
  export PATH="$HOME/.npm-global/bin:$PATH"
else
  log "$(t install_have_wrangler "$(wrangler --version 2>/dev/null || "$HOME/.npm-global/bin/wrangler" --version 2>/dev/null || echo '?')")"
fi

# --- 6. Verifikasi ---
log "$(t install_verify)"
export PATH="$HOME/.local/bin:$PATH"
if hermes doctor; then
  log "$(t install_doctor_ok)"
else
  warn "$(t install_doctor_warn)"
fi

cat << 'EOF'

============================================================
 Instalasi selesai. Langkah manual berikutnya:
  1. hermes setup --portal     # login provider model (OAuth)
     atau: hermes model        # pilih provider/model
  2. Buat bot Telegram via @BotFather, catat tokennya.
  3. Dapatkan numeric ID via @userinfobot.
  4. hermes gateway setup       # isi token bot + allowlist ID
  5. 9router -p 20128 -H 127.0.0.1 -n -l --skip-update
  6. hermes gateway run         # verifikasi "Connected to Telegram"
 Lihat README.md untuk detail tiap langkah.
============================================================
EOF
