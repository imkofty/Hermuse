#!/usr/bin/env bash
# Hermuse i18n helper — user-facing strings in 3 languages.
#
# Usage in a script (repo root assumed via SCRIPT_DIR):
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   . "$SCRIPT_DIR/lib/i18n.sh"          # root-level scripts
#   . "$SCRIPT_DIR/../lib/i18n.sh"       # scripts in scripts/
#
#   warn "$(t install_need_sudo)"
#   log "$(t install_have_node "$(node --version)")"
#
# Language: ${HERMUSE_LANG:-id} — one of: id (default, legacy behaviour),
# en, ms. Unknown values fall back to id.
#
# NOTE for translators: keep product names, commands and paths in English.
# Malay follows the repo's ms style guide: "anda", no Manglish particles,
# technical nouns (gateway, deploy, stack, folder, terminal, bot, secret)
# stay English. NEVER use these in ms strings: butuh (vulgar!), bisa
# (=racun), gampang, sulit, kamu/kalian, nggak.

t() {
    local key="$1"; shift || true
    local lang="${HERMUSE_LANG:-id}"
    case "$lang" in
        en|ms) ;;
        *) lang="id" ;;
    esac
    local fmt=""
    case "$lang" in
        en)
            case "$key" in
                install_debian_only) fmt="This script is for Debian/Ubuntu (needs apt-get). Install manually on other distros." ;;
                install_need_sudo)   fmt="The 'sudo' command is required — or run this script as root." ;;
                install_sudo_pw)     fmt="sudo is asking for a password, but this script is designed to be non-interactive." ;;
                install_enable_sudo) fmt="Enable passwordless sudo for this user, or run as root." ;;
                install_deps)        fmt="Installing base dependencies (git, curl, tar)..." ;;
                install_node)        fmt="Installing Node.js LTS via NodeSource..." ;;
                install_have_node)   fmt="Node.js already present: %s" ;;
                install_hermes)      fmt="Installing Hermes Agent..." ;;
                install_have_hermes) fmt="Hermes already present: %s" ;;
                install_version_ok)  fmt="%s version verified: %s" ;;
                install_align_version) fmt="%s is installed at version %s, but this installer pins %s — reinstalling to match..." ;;
                install_pkg_fresh)   fmt="Installing %s %s..." ;;
                install_version_bad) fmt="ERROR: %s version after install is %s, expected %s — aborting." ;;
                install_verify)      fmt="Verifying the Hermes installation..." ;;
                install_doctor_ok)   fmt="hermes doctor: OK" ;;
                install_doctor_warn) fmt="hermes doctor found issues — see the output above." ;;
                tunnel_usage)        fmt="Usage: %s <pages-project-name> <d1-name>" ;;
                tunnel_need_wrangler) fmt="wrangler is not installed (npm i -g wrangler)." ;;
                tunnel_need_node)    fmt="node is not installed." ;;
                tunnel_no_token)     fmt="CLOUDFLARE_API_TOKEN is not set; wrangler will use browser login if needed." ;;
                tunnel_key_exists)   fmt="Key already exists at %s — reusing the existing one." ;;
                tunnel_gen_key)      fmt="Generating new tunnel key..." ;;
                tunnel_mk_d1)        fmt="Creating D1 database '%s'..." ;;
                tunnel_d1_exists)    fmt="D1 '%s' already exists — skipping create." ;;
                tunnel_apply_schema) fmt="Applying schema.sql to D1..." ;;
                tunnel_d1_noid)      fmt="Failed to read the D1 database_id." ;;
                tunnel_wrangler_toml) fmt="wrangler.toml created for project '%s'." ;;
                tunnel_ensure_pages) fmt="Ensuring Pages project '%s' exists..." ;;
                tunnel_pages_exists) fmt="Pages project '%s' already exists — continuing." ;;
                tunnel_set_secret)   fmt="Setting TUNNEL_KEY as a Pages secret (production)..." ;;
                tunnel_deploy)       fmt="Deploying to Pages..." ;;
                tunnel_done)         fmt="Done! Tunnel URL: %s" ;;
                router_pw_warn)      fmt="WARNING: %s is missing — 9Router runs with the default password. Create the file (chmod 600) then restart." ;;
                router_pw_required_public) fmt="ERROR: %s is missing but a public tunnel is configured (.tunnel-url exists) — refusing to run 9Router with the default dashboard password. Create the file (chmod 600), or remove .tunnel-url for local-only use." ;;
                tunnel_apply_migrations) fmt="Applying migrations 001-003 in order (harmless on fresh databases)..." ;;
                tunnel_gen_health_key) fmt="Generating tunnel health key..." ;;
                tunnel_health_key_exists) fmt="Health key already exists: %s (kept)" ;;
                tunnel_gen_gate_pw)  fmt="Generating dashboard gate password..." ;;
                tunnel_gate_pw_file) fmt="Gate password saved to %s (chmod 600); set as Pages secrets GATE_PASSWORD + REQUIRE_GATE=1." ;;
                tunnel_gate_skipped) fmt="WARNING: SETUP_NO_GATE=1 — dashboard gate NOT set; the public tunnel URL will serve the dashboard without a password gate." ;;
                gw_no_pid)           fmt="No gateway PID (%s)" ;;
                gw_abort_multi)      fmt="ABORT: %s gateway PID candidates, not killing (ambiguous): %s" ;;
                gw_kill_fail)        fmt="FAILED: PID %s could not be killed" ;;
                gw_dryrun)           fmt="DRY_RUN: would run start-gateway.sh + verify Connected" ;;
                gw_restart_ok)       fmt="RESTART OK: gateway is alive again + Connected to Telegram (%s)" ;;
                gw_restart_fail)     fmt="RESTART FAILED: no 'Connected to Telegram' within 60s (%s)" ;;
                gw_abort_ambiguous)  fmt="ABORT: %s gateway PID candidates (ambiguous), left untouched: %s" ;;
                tunnel_env_missing)  fmt="TUNNEL_BASE_URL is not set. Example:" ;;
                tunnel_env_example)  fmt="  TUNNEL_BASE_URL=https://<your-project>.pages.dev node tunnel-client.mjs" ;;
                tunnel_env_alt)      fmt="  (or save the URL in a .tunnel-url file when run via start-pages-tunnel.sh)" ;;
                tunnel_key_unreadable) fmt="Cannot read key file: %s (create with: openssl rand -hex 32 > %s && chmod 600 %s)" ;;
                tunnel_key_empty)    fmt="Empty key in %s" ;;
                tunnel_local_not_loopback) fmt="TUNNEL_LOCAL must be a loopback URL (got: %s). Set TUNNEL_ALLOW_REMOTE_LOCAL=1 only if you really mean to forward elsewhere." ;;
                tunnel_response_too_large) fmt="Local response exceeds the %s MB cap" ;;
                cf_usage)            fmt="Usage: %s <tunnel-name> <hostname>" ;;
                cf_installing)       fmt="Installing cloudflared..." ;;
                cf_have)             fmt="cloudflared already present: %s" ;;
                cf_install_fail)     fmt="Failed to install cloudflared. Install manually: https://github.com/cloudflare/cloudflared/releases" ;;
                cf_unsupported_arch) fmt="Architecture %s is not supported." ;;
                cf_need_login)       fmt="Not logged in to Cloudflare — running 'cloudflared tunnel login'..." ;;
                cf_login_fail)       fmt="Cloudflare login failed." ;;
                cf_bad_hostname)     fmt="Invalid hostname: %s (example: 9router.example.com)" ;;
                cf_creating)         fmt="Creating tunnel '%s'..." ;;
                cf_exists)           fmt="Tunnel '%s' already exists — reusing it (id %s)." ;;
                cf_created)          fmt="Tunnel created: %s (id %s)" ;;
                cf_no_id)            fmt="Failed to determine the tunnel ID." ;;
                cf_no_cred)          fmt="Credentials file not found: %s" ;;
                cf_writing_config)   fmt="Writing config to %s..." ;;
                cf_routing_dns)      fmt="Creating DNS CNAME %s -> %s.cfargotunnel.com..." ;;
                cf_dns_exists)       fmt="DNS route failed — the record may already exist. Create the CNAME manually if needed." ;;
                cf_9router_warn)     fmt="9Router is not responding on 127.0.0.1:20128 — make sure it is running before using the tunnel." ;;
                cf_done)             fmt="Done! Public dashboard: https://%s" ;;
            esac
            ;;
        ms)
            case "$key" in
                install_debian_only) fmt="Skrip ini untuk Debian/Ubuntu (memerlukan apt-get). Pasang secara manual untuk distro lain." ;;
                install_need_sudo)   fmt="Perintah 'sudo' diperlukan — atau jalankan skrip ini sebagai root." ;;
                install_sudo_pw)     fmt="sudo meminta kata laluan, sedangkan skrip ini direka untuk tidak interaktif." ;;
                install_enable_sudo) fmt="Aktifkan passwordless sudo untuk pengguna ini, atau jalankan sebagai root." ;;
                install_deps)        fmt="Memasang kebergantungan asas (git, curl, tar)..." ;;
                install_node)        fmt="Memasang Node.js LTS melalui NodeSource..." ;;
                install_have_node)   fmt="Node.js telah dipasang: %s" ;;
                install_hermes)      fmt="Memasang Hermes Agent..." ;;
                install_have_hermes) fmt="Hermes telah dipasang: %s" ;;
                install_version_ok)  fmt="Versi %s disahkan: %s" ;;
                install_align_version) fmt="%s dipasang pada versi %s, tetapi pemasang ini menetapkan %s — memasang semula agar sepadan..." ;;
                install_pkg_fresh)   fmt="Memasang %s %s..." ;;
                install_version_bad) fmt="RALAT: versi %s selepas pemasangan ialah %s, sepatutnya %s — batal." ;;
                install_verify)      fmt="Mengesahkan pemasangan Hermes..." ;;
                install_doctor_ok)   fmt="hermes doctor: OK" ;;
                install_doctor_warn) fmt="hermes doctor menemui masalah — lihat output di atas." ;;
                tunnel_usage)        fmt="Penggunaan: %s <nama-projek-pages> <nama-d1>" ;;
                tunnel_need_wrangler) fmt="wrangler belum dipasang (npm i -g wrangler)." ;;
                tunnel_need_node)    fmt="node belum dipasang." ;;
                tunnel_no_token)     fmt="CLOUDFLARE_API_TOKEN tidak ditetapkan; wrangler akan menggunakan log masuk pelayar jika perlu." ;;
                tunnel_key_exists)   fmt="Kunci telah wujud di %s — guna yang sedia ada." ;;
                tunnel_gen_key)      fmt="Menjana kunci tunnel baharu..." ;;
                tunnel_mk_d1)        fmt="Mencipta pangkalan data D1 '%s'..." ;;
                tunnel_d1_exists)    fmt="D1 '%s' telah wujud — langkau create." ;;
                tunnel_apply_schema) fmt="Mengaplikasikan schema.sql pada D1..." ;;
                tunnel_d1_noid)      fmt="Gagal membaca database_id D1." ;;
                tunnel_wrangler_toml) fmt="wrangler.toml dicipta untuk projek '%s'." ;;
                tunnel_ensure_pages) fmt="Memastikan projek Pages '%s' wujud..." ;;
                tunnel_pages_exists) fmt="Pages project '%s' telah wujud — teruskan." ;;
                tunnel_set_secret)   fmt="Menetapkan TUNNEL_KEY sebagai secret Pages (production)..." ;;
                tunnel_deploy)       fmt="Deploy ke Pages..." ;;
                tunnel_done)         fmt="Siap! Tunnel URL: %s" ;;
                router_pw_warn)      fmt="AMARAN: %s tiada — 9Router berjalan dengan kata laluan lalai. Cipta fail tersebut (chmod 600) kemudian mulakan semula." ;;
                router_pw_required_public) fmt="RALAT: %s tiada tetapi tunnel awam telah dikonfigurasikan (.tunnel-url wujud) — 9Router tidak akan dimulakan dengan kata laluan papan pemuka lalai. Cipta fail tersebut (chmod 600), atau padam .tunnel-url untuk kegunaan setempat sahaja." ;;
                tunnel_apply_migrations) fmt="Menggunakan migrasi 001-003 mengikut urutan (selamat untuk pangkalan data baharu)..." ;;
                tunnel_gen_health_key) fmt="Menjana kunci kesihatan tunnel..." ;;
                tunnel_health_key_exists) fmt="Kunci kesihatan sudah wujud: %s (dikekalkan)" ;;
                tunnel_gen_gate_pw)  fmt="Menjana kata laluan get papan pemuka..." ;;
                tunnel_gate_pw_file) fmt="Kata laluan get disimpan ke %s (chmod 600); ditetapkan sebagai secret Pages GATE_PASSWORD + REQUIRE_GATE=1." ;;
                tunnel_gate_skipped) fmt="AMARAN: SETUP_NO_GATE=1 — get papan pemuka TIDAK ditetapkan; URL tunnel awam akan melayan papan pemuka tanpa get kata laluan." ;;
                gw_no_pid)           fmt="Tiada PID gateway (%s)" ;;
                gw_abort_multi)      fmt="ABORT: %s calon PID gateway, tidak dimatikan (ambiguous): %s" ;;
                gw_kill_fail)        fmt="GAGAL: PID %s tidak dapat dimatikan" ;;
                gw_dryrun)           fmt="DRY_RUN: akan menjalankan start-gateway.sh + sahkan Connected" ;;
                gw_restart_ok)       fmt="RESTART OK: gateway hidup semula + Connected to Telegram (%s)" ;;
                gw_restart_fail)     fmt="RESTART GAGAL: tiada 'Connected to Telegram' dalam 60 saat (%s)" ;;
                gw_abort_ambiguous)  fmt="ABORT: %s calon PID gateway (ambiguous), tidak disentuh: %s" ;;
                tunnel_env_missing)  fmt="TUNNEL_BASE_URL belum ditetapkan. Contoh:" ;;
                tunnel_env_example)  fmt="  TUNNEL_BASE_URL=https://<projek-anda>.pages.dev node tunnel-client.mjs" ;;
                tunnel_env_alt)      fmt="  (atau simpan URL dalam fail .tunnel-url jika dijalankan melalui start-pages-tunnel.sh)" ;;
                tunnel_key_unreadable) fmt="Tidak dapat membaca fail kunci: %s (cipta dengan: openssl rand -hex 32 > %s && chmod 600 %s)" ;;
                tunnel_key_empty)    fmt="Kunci kosong di %s" ;;
                tunnel_local_not_loopback) fmt="TUNNEL_LOCAL mestilah URL loopback (diberi: %s). Tetapkan TUNNEL_ALLOW_REMOTE_LOCAL=1 hanya jika anda memang mahu forward ke tempat lain." ;;
                tunnel_response_too_large) fmt="Respons lokal melebihi had %s MB" ;;
                cf_usage)            fmt="Penggunaan: %s <nama-tunnel> <hostname>" ;;
                cf_installing)       fmt="Memasang cloudflared..." ;;
                cf_have)             fmt="cloudflared telah dipasang: %s" ;;
                cf_install_fail)     fmt="Gagal memasang cloudflared. Pasang secara manual: https://github.com/cloudflare/cloudflared/releases" ;;
                cf_unsupported_arch) fmt="Seni bina %s tidak disokong." ;;
                cf_need_login)       fmt="Belum log masuk Cloudflare — menjalankan 'cloudflared tunnel login'..." ;;
                cf_login_fail)       fmt="Log masuk Cloudflare gagal." ;;
                cf_bad_hostname)     fmt="Hostname tidak sah: %s (contoh: 9router.contoh.com)" ;;
                cf_creating)         fmt="Mencipta tunnel '%s'..." ;;
                cf_exists)           fmt="Tunnel '%s' telah wujud — guna yang sedia ada (id %s)." ;;
                cf_created)          fmt="Tunnel dicipta: %s (id %s)" ;;
                cf_no_id)            fmt="Gagal mendapatkan tunnel ID." ;;
                cf_no_cred)          fmt="Fail kredensial tidak ditemui: %s" ;;
                cf_writing_config)   fmt="Menulis config ke %s..." ;;
                cf_routing_dns)      fmt="Mencipta DNS CNAME %s -> %s.cfargotunnel.com..." ;;
                cf_dns_exists)       fmt="DNS route gagal — rekod mungkin telah wujud. Cipta CNAME secara manual jika perlu." ;;
                cf_9router_warn)     fmt="9Router tidak menjawab di 127.0.0.1:20128 — pastikan ia berjalan sebelum menggunakan tunnel." ;;
                cf_done)             fmt="Siap! Dashboard awam: https://%s" ;;
            esac
            ;;
        *)
            case "$key" in
                install_debian_only) fmt="Script ini untuk Debian/Ubuntu (butuh apt-get). Install manual untuk distro lain." ;;
                install_need_sudo)   fmt="Butuh perintah 'sudo' — atau jalankan script ini sebagai root." ;;
                install_sudo_pw)     fmt="sudo meminta password, padahal script ini dirancang non-interaktif." ;;
                install_enable_sudo) fmt="Aktifkan passwordless sudo untuk user ini, atau jalankan sebagai root." ;;
                install_deps)        fmt="Menginstall dependensi dasar (git, curl, tar)..." ;;
                install_node)        fmt="Menginstall Node.js LTS via NodeSource..." ;;
                install_have_node)   fmt="Node.js sudah ada: %s" ;;
                install_hermes)      fmt="Menginstall Hermes Agent..." ;;
                install_have_hermes) fmt="Hermes sudah ada: %s" ;;
                install_version_ok)  fmt="Versi %s terverifikasi: %s" ;;
                install_align_version) fmt="%s terpasang versi %s, sedangkan installer mematok %s — memasang ulang agar cocok..." ;;
                install_pkg_fresh)   fmt="Memasang %s %s..." ;;
                install_version_bad) fmt="ERROR: versi %s setelah pemasangan adalah %s, seharusnya %s — batal." ;;
                install_verify)      fmt="Verifikasi instalasi Hermes..." ;;
                install_doctor_ok)   fmt="hermes doctor: OK" ;;
                install_doctor_warn) fmt="hermes doctor menemukan masalah — lihat output di atas." ;;
                tunnel_usage)        fmt="Pakai: %s <nama-pages-project> <nama-d1>" ;;
                tunnel_need_wrangler) fmt="wrangler belum terinstall (npm i -g wrangler)." ;;
                tunnel_need_node)    fmt="node belum terinstall." ;;
                tunnel_no_token)     fmt="CLOUDFLARE_API_TOKEN tidak di-set; wrangler akan pakai login browser bila perlu." ;;
                tunnel_key_exists)   fmt="Key sudah ada di %s — pakai yang lama." ;;
                tunnel_gen_key)      fmt="Generate tunnel key baru..." ;;
                tunnel_mk_d1)        fmt="Membuat D1 database '%s'..." ;;
                tunnel_d1_exists)    fmt="D1 '%s' sudah ada — lewati create." ;;
                tunnel_apply_schema) fmt="Menerapkan schema.sql ke D1..." ;;
                tunnel_d1_noid)      fmt="Gagal membaca database_id D1." ;;
                tunnel_wrangler_toml) fmt="wrangler.toml dibuat untuk project '%s'." ;;
                tunnel_ensure_pages) fmt="Memastikan Pages project '%s' ada..." ;;
                tunnel_pages_exists) fmt="Pages project '%s' sudah ada — lanjut." ;;
                tunnel_set_secret)   fmt="Menyetel TUNNEL_KEY sebagai Pages secret (production)..." ;;
                tunnel_deploy)       fmt="Deploy ke Pages..." ;;
                tunnel_done)         fmt="Selesai! Tunnel URL: %s" ;;
                router_pw_warn)      fmt="PERINGATAN: %s tidak ada — 9Router jalan dengan password default. Buat file-nya (chmod 600) lalu restart." ;;
                router_pw_required_public) fmt="ERROR: %s tidak ada tapi tunnel publik terkonfigurasi (.tunnel-url ada) — menolak menjalankan 9Router dengan password dashboard default. Buat file-nya (chmod 600), atau hapus .tunnel-url untuk pemakaian lokal saja." ;;
                tunnel_apply_migrations) fmt="Menerapkan migrasi 001-003 berurutan (aman untuk database baru)..." ;;
                tunnel_gen_health_key) fmt="Membuat kunci kesehatan tunnel..." ;;
                tunnel_health_key_exists) fmt="Kunci kesehatan sudah ada: %s (dipertahankan)" ;;
                tunnel_gen_gate_pw)  fmt="Membuat password gate dashboard..." ;;
                tunnel_gate_pw_file) fmt="Password gate disimpan ke %s (chmod 600); disetel sebagai Pages secret GATE_PASSWORD + REQUIRE_GATE=1." ;;
                tunnel_gate_skipped) fmt="PERINGATAN: SETUP_NO_GATE=1 — gate dashboard TIDAK disetel; URL tunnel publik akan melayani dashboard tanpa gate password." ;;
                gw_no_pid)           fmt="PID gateway tidak ada (%s)" ;;
                gw_abort_multi)      fmt="ABORT: %s kandidat PID gateway, tidak kill (ambiguous): %s" ;;
                gw_kill_fail)        fmt="GAGAL: PID %s tidak bisa di-kill" ;;
                gw_dryrun)           fmt="DRY_RUN: would run start-gateway.sh + verifikasi Connected" ;;
                gw_restart_ok)       fmt="RESTART OK: gateway hidup kembali + Connected to Telegram (%s)" ;;
                gw_restart_fail)     fmt="RESTART GAGAL: tidak ada 'Connected to Telegram' dalam 60 dtk (%s)" ;;
                gw_abort_ambiguous)  fmt="ABORT: %s kandidat PID gateway (ambiguous), tidak diapa-apakan: %s" ;;
                tunnel_env_missing)  fmt="TUNNEL_BASE_URL belum di-set. Contoh:" ;;
                tunnel_env_example)  fmt="  TUNNEL_BASE_URL=https://<project-kamu>.pages.dev node tunnel-client.mjs" ;;
                tunnel_env_alt)      fmt="  (atau simpan URL di file .tunnel-url bila dijalankan via start-pages-tunnel.sh)" ;;
                tunnel_key_unreadable) fmt="Tidak bisa baca key file: %s (buat dengan: openssl rand -hex 32 > %s && chmod 600 %s)" ;;
                tunnel_key_empty)    fmt="Key kosong di %s" ;;
                tunnel_local_not_loopback) fmt="TUNNEL_LOCAL harus berupa URL loopback (diberi: %s). Set TUNNEL_ALLOW_REMOTE_LOCAL=1 hanya bila memang sengaja forward ke tempat lain." ;;
                tunnel_response_too_large) fmt="Respons lokal melebihi batas %s MB" ;;
                cf_usage)            fmt="Pakai: %s <nama-tunnel> <hostname>" ;;
                cf_installing)       fmt="Menginstall cloudflared..." ;;
                cf_have)             fmt="cloudflared sudah ada: %s" ;;
                cf_install_fail)     fmt="Gagal menginstall cloudflared. Install manual: https://github.com/cloudflare/cloudflared/releases" ;;
                cf_unsupported_arch) fmt="Arsitektur %s tidak didukung." ;;
                cf_need_login)       fmt="Belum login Cloudflare — menjalankan 'cloudflared tunnel login'..." ;;
                cf_login_fail)       fmt="Login Cloudflare gagal." ;;
                cf_bad_hostname)     fmt="Hostname tidak valid: %s (contoh: 9router.contoh.com)" ;;
                cf_creating)         fmt="Membuat tunnel '%s'..." ;;
                cf_exists)           fmt="Tunnel '%s' sudah ada — pakai yang lama (id %s)." ;;
                cf_created)          fmt="Tunnel dibuat: %s (id %s)" ;;
                cf_no_id)            fmt="Gagal mendapatkan tunnel ID." ;;
                cf_no_cred)          fmt="File kredensial tidak ditemukan: %s" ;;
                cf_writing_config)    fmt="Menulis config ke %s..." ;;
                cf_routing_dns)      fmt="Membuat DNS CNAME %s -> %s.cfargotunnel.com..." ;;
                cf_dns_exists)       fmt="DNS route gagal — record mungkin sudah ada. Buat CNAME manual bila perlu." ;;
                cf_9router_warn)     fmt="9Router tidak merespons di 127.0.0.1:20128 — pastikan jalan sebelum pakai tunnel." ;;
                cf_done)             fmt="Selesai! Dashboard publik: https://%s" ;;
            esac
            ;;
    esac
    if [ -z "$fmt" ]; then
        printf 'i18n: unknown key %s\n' "$key" >&2
        return 1
    fi
    # shellcheck disable=SC2059
    printf "$fmt" "$@"
}
