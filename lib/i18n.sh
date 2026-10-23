#!/usr/bin/env bash
# Hermuse i18n helper — user-facing strings in 6 languages.
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
# en, ms, vi, hi, ja. Unknown values fall back to id.
#
# NOTE for translators: keep product names, commands and paths in English.
# Malay follows the repo's ms style guide: "anda", no Manglish particles,
# technical nouns (gateway, deploy, stack, folder, terminal, bot, secret)
# stay English. NEVER use these in ms strings: butuh (vulgar!), bisa
# (=racun), gampang, sulit, kamu/kalian, nggak.
# Japanese follows the Microsoft/JTF style guides: desu/masu (polite)
# style for message bodies, "...shite kudasai" for user actions,
# "~dekimasen" for "cannot ...", katakana loanwords with the long-vowel
# mark (server -> sābā), and full-width punctuation.

t() {
    local key="$1"; shift || true
    local lang="${HERMUSE_LANG:-id}"
    case "$lang" in
        en|ms|vi|hi|ja) ;;
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
                router_pw_warn)      fmt="WARNING: %s is missing or empty — 9Router runs with the default password. Create the file (chmod 600) then restart." ;;
                router_pw_required_public) fmt="ERROR: %s is missing or empty but a public tunnel is configured (.tunnel-url exists) — refusing to run 9Router with the default dashboard password. Create the file (chmod 600), or remove .tunnel-url for local-only use." ;;
                tunnel_apply_migrations) fmt="Applying migrations 001-004 in order (harmless on fresh databases)..." ;;
                tunnel_apply_migration) fmt="Applying migration %s (not yet recorded in schema_migrations)..." ;;
                tunnel_schema_incomplete) fmt="Tunnel schema is still incomplete after migrations — aborting setup." ;;
                tunnel_gen_health_key) fmt="Generating tunnel health key..." ;;
                tunnel_health_key_exists) fmt="Health key already exists: %s (kept)" ;;
                tunnel_gen_gate_pw)  fmt="Generating dashboard gate password..." ;;
                tunnel_gen_dashboard_pw) fmt="Generating 9Router dashboard password (.dashboard-pw)..." ;;
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
                router_pw_warn)      fmt="AMARAN: %s tiada atau kosong — 9Router berjalan dengan kata laluan lalai. Cipta fail tersebut (chmod 600) kemudian mulakan semula." ;;
                router_pw_required_public) fmt="RALAT: %s tiada atau kosong tetapi tunnel awam telah dikonfigurasikan (.tunnel-url wujud) — 9Router tidak akan dimulakan dengan kata laluan papan pemuka lalai. Cipta fail tersebut (chmod 600), atau padam .tunnel-url untuk kegunaan setempat sahaja." ;;
                tunnel_apply_migrations) fmt="Menggunakan migrasi 001-004 mengikut urutan (selamat untuk pangkalan data baharu)..." ;;
                tunnel_apply_migration) fmt="Menggunakan migrasi %s (belum direkodkan dalam schema_migrations)..." ;;
                tunnel_schema_incomplete) fmt="Skema tunnel masih belum lengkap selepas migrasi — setup dibatalkan." ;;
                tunnel_gen_health_key) fmt="Menjana kunci kesihatan tunnel..." ;;
                tunnel_health_key_exists) fmt="Kunci kesihatan sudah wujud: %s (dikekalkan)" ;;
                tunnel_gen_gate_pw)  fmt="Menjana kata laluan get papan pemuka..." ;;
                tunnel_gen_dashboard_pw) fmt="Menjana kata laluan papan pemuka 9Router (.dashboard-pw)..." ;;
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
        vi)
            case "$key" in
                install_debian_only)       fmt="Script này dành cho Debian/Ubuntu (cần apt-get). Hãy cài đặt thủ công trên các bản phân phối khác." ;;
                install_need_sudo)         fmt="Cần lệnh 'sudo' — hoặc chạy script này với quyền root." ;;
                install_sudo_pw)           fmt="sudo đang yêu cầu mật khẩu, nhưng script này được thiết kế để chạy không tương tác." ;;
                install_enable_sudo)       fmt="Hãy bật sudo không cần mật khẩu cho người dùng này, hoặc chạy với quyền root." ;;
                install_deps)              fmt="Đang cài đặt các gói phụ thuộc cơ bản (git, curl, tar)..." ;;
                install_node)              fmt="Đang cài đặt Node.js LTS qua NodeSource..." ;;
                install_have_node)         fmt="Node.js đã có sẵn: %s" ;;
                install_hermes)            fmt="Đang cài đặt Hermes Agent..." ;;
                install_have_hermes)       fmt="Hermes đã có sẵn: %s" ;;
                install_version_ok)        fmt="Phiên bản %s đã xác minh: %s" ;;
                install_align_version)     fmt="%s đang ở phiên bản %s, nhưng trình cài đặt này cố định %s — đang cài lại cho khớp..." ;;
                install_pkg_fresh)         fmt="Đang cài đặt %s %s..." ;;
                install_version_bad)       fmt="LỖI: phiên bản %s sau khi cài là %s, trong khi yêu cầu %s — hủy bỏ." ;;
                install_verify)            fmt="Đang xác minh bản cài đặt Hermes..." ;;
                install_doctor_ok)         fmt="hermes doctor: OK" ;;
                install_doctor_warn)       fmt="hermes doctor phát hiện vấn đề — xem kết quả ở trên." ;;
                tunnel_usage)              fmt="Cách dùng: %s <pages-project-name> <d1-name>" ;;
                tunnel_need_wrangler)      fmt="wrangler chưa được cài đặt (npm i -g wrangler)." ;;
                tunnel_need_node)          fmt="node chưa được cài đặt." ;;
                tunnel_no_token)           fmt="CLOUDFLARE_API_TOKEN chưa được đặt; wrangler sẽ dùng đăng nhập trình duyệt nếu cần." ;;
                tunnel_key_exists)         fmt="Key đã tồn tại tại %s — dùng lại key hiện có." ;;
                tunnel_gen_key)            fmt="Đang tạo tunnel key mới..." ;;
                tunnel_mk_d1)              fmt="Đang tạo cơ sở dữ liệu D1 '%s'..." ;;
                tunnel_d1_exists)          fmt="D1 '%s' đã tồn tại — bỏ qua bước tạo." ;;
                tunnel_apply_schema)       fmt="Đang áp dụng schema.sql vào D1..." ;;
                tunnel_d1_noid)            fmt="Không đọc được database_id của D1." ;;
                tunnel_wrangler_toml)      fmt="Đã tạo wrangler.toml cho project '%s'." ;;
                tunnel_ensure_pages)       fmt="Đang đảm bảo Pages project '%s' tồn tại..." ;;
                tunnel_pages_exists)       fmt="Pages project '%s' đã tồn tại — tiếp tục." ;;
                tunnel_set_secret)         fmt="Đang đặt TUNNEL_KEY làm Pages secret (production)..." ;;
                tunnel_deploy)             fmt="Đang deploy lên Pages..." ;;
                tunnel_done)               fmt="Xong! Tunnel URL: %s" ;;
                router_pw_warn)            fmt="CẢNH BÁO: %s bị thiếu hoặc trống — 9Router đang chạy với mật khẩu mặc định. Hãy tạo file (chmod 600) rồi khởi động lại." ;;
                router_pw_required_public) fmt="LỖI: %s bị thiếu hoặc trống nhưng tunnel công khai đã được cấu hình (.tunnel-url tồn tại) — từ chối chạy 9Router với mật khẩu dashboard mặc định. Hãy tạo file (chmod 600), hoặc xóa .tunnel-url nếu chỉ dùng nội bộ." ;;
                tunnel_apply_migrations)   fmt="Đang áp dụng các migration 001-004 theo thứ tự (an toàn trên cơ sở dữ liệu mới)..." ;;
                tunnel_apply_migration)    fmt="Đang áp dụng migration %s (chưa được ghi trong schema_migrations)..." ;;
                tunnel_schema_incomplete)  fmt="Schema tunnel vẫn chưa hoàn chỉnh sau migration — hủy bỏ thiết lập." ;;
                tunnel_gen_health_key)     fmt="Đang tạo tunnel health key..." ;;
                tunnel_health_key_exists)  fmt="Health key đã tồn tại: %s (giữ nguyên)" ;;
                tunnel_gen_gate_pw)        fmt="Đang tạo mật khẩu gate dashboard..." ;;
                tunnel_gen_dashboard_pw)   fmt="Đang tạo mật khẩu dashboard 9Router (.dashboard-pw)..." ;;
                tunnel_gate_pw_file)       fmt="Mật khẩu gate đã lưu vào %s (chmod 600); đặt làm Pages secret GATE_PASSWORD + REQUIRE_GATE=1." ;;
                tunnel_gate_skipped)       fmt="CẢNH BÁO: SETUP_NO_GATE=1 — gate dashboard KHÔNG được đặt; URL tunnel công khai sẽ phục vụ dashboard mà không có gate mật khẩu." ;;
                gw_no_pid)                 fmt="Không có gateway PID (%s)" ;;
                gw_abort_multi)            fmt="HỦY: %s ứng viên gateway PID, không kill (không rõ ràng): %s" ;;
                gw_kill_fail)              fmt="THẤT BẠI: không kill được PID %s" ;;
                gw_dryrun)                 fmt="DRY_RUN: would run start-gateway.sh + verify Connected" ;;
                gw_restart_ok)             fmt="RESTART OK: gateway đã sống lại + Connected to Telegram (%s)" ;;
                gw_restart_fail)           fmt="RESTART THẤT BẠI: không có 'Connected to Telegram' trong 60 giây (%s)" ;;
                gw_abort_ambiguous)        fmt="HỦY: %s ứng viên gateway PID (không rõ ràng), giữ nguyên không đụng vào: %s" ;;
                tunnel_env_missing)        fmt="TUNNEL_BASE_URL chưa được đặt. Ví dụ:" ;;
                tunnel_env_example)        fmt="  TUNNEL_BASE_URL=https://<project-cua-ban>.pages.dev node tunnel-client.mjs" ;;
                tunnel_env_alt)            fmt="  (hoặc lưu URL vào file .tunnel-url khi chạy qua start-pages-tunnel.sh)" ;;
                tunnel_key_unreadable)     fmt="Không đọc được file key: %s (tạo bằng: openssl rand -hex 32 > %s && chmod 600 %s)" ;;
                tunnel_key_empty)          fmt="Key trống trong %s" ;;
                tunnel_local_not_loopback) fmt="TUNNEL_LOCAL phải là URL loopback (nhận được: %s). Chỉ đặt TUNNEL_ALLOW_REMOTE_LOCAL=1 khi bạn thực sự muốn forward đến nơi khác." ;;
                tunnel_response_too_large) fmt="Phản hồi cục bộ vượt quá giới hạn %s MB" ;;
                cf_usage)                  fmt="Cách dùng: %s <tunnel-name> <hostname>" ;;
                cf_installing)             fmt="Đang cài đặt cloudflared..." ;;
                cf_have)                   fmt="cloudflared đã có sẵn: %s" ;;
                cf_install_fail)           fmt="Cài đặt cloudflared thất bại. Cài thủ công: https://github.com/cloudflare/cloudflared/releases" ;;
                cf_unsupported_arch)       fmt="Kiến trúc %s không được hỗ trợ." ;;
                cf_need_login)             fmt="Chưa đăng nhập Cloudflare — đang chạy 'cloudflared tunnel login'..." ;;
                cf_login_fail)             fmt="Đăng nhập Cloudflare thất bại." ;;
                cf_bad_hostname)           fmt="Hostname không hợp lệ: %s (ví dụ: 9router.example.com)" ;;
                cf_creating)               fmt="Đang tạo tunnel '%s'..." ;;
                cf_exists)                 fmt="Tunnel '%s' đã tồn tại — dùng lại (id %s)." ;;
                cf_created)                fmt="Đã tạo tunnel: %s (id %s)" ;;
                cf_no_id)                  fmt="Không xác định được tunnel ID." ;;
                cf_no_cred)                fmt="Không tìm thấy file credentials: %s" ;;
                cf_writing_config)         fmt="Đang ghi config vào %s..." ;;
                cf_routing_dns)            fmt="Đang tạo DNS CNAME %s -> %s.cfargotunnel.com..." ;;
                cf_dns_exists)             fmt="DNS route thất bại — bản ghi có thể đã tồn tại. Hãy tạo CNAME thủ công nếu cần." ;;
                cf_9router_warn)           fmt="9Router không phản hồi tại 127.0.0.1:20128 — hãy chắc chắn nó đang chạy trước khi dùng tunnel." ;;
                cf_done)                   fmt="Xong! Dashboard công khai: https://%s" ;;
            esac
            ;;
        hi)
            case "$key" in
                install_debian_only)       fmt="यह स्क्रिप्ट Debian/Ubuntu के लिए है (apt-get आवश्यक है)। अन्य डिस्ट्रो पर मैन्युअल रूप से इंस्टॉल करें।" ;;
                install_need_sudo)         fmt="'sudo' कमांड आवश्यक है — या इस स्क्रिप्ट को root के रूप में चलाएं।" ;;
                install_sudo_pw)           fmt="sudo पासवर्ड मांग रहा है, लेकिन यह स्क्रिप्ट गैर-इंटरैक्टिव चलने के लिए बनाई गई है।" ;;
                install_enable_sudo)       fmt="इस उपयोगकर्ता के लिए पासवर्ड-रहित sudo सक्षम करें, या root के रूप में चलाएं।" ;;
                install_deps)              fmt="आधार निर्भरताएं इंस्टॉल हो रही हैं (git, curl, tar)..." ;;
                install_node)              fmt="NodeSource के माध्यम से Node.js LTS इंस्टॉल हो रहा है..." ;;
                install_have_node)         fmt="Node.js पहले से मौजूद है: %s" ;;
                install_hermes)            fmt="Hermes Agent इंस्टॉल हो रहा है..." ;;
                install_have_hermes)       fmt="Hermes पहले से मौजूद है: %s" ;;
                install_version_ok)        fmt="%s का संस्करण सत्यापित: %s" ;;
                install_align_version)     fmt="%s संस्करण %s पर इंस्टॉल है, लेकिन यह इंस्टॉलर %s को पिन करता है — मिलान के लिए फिर से इंस्टॉल हो रहा है..." ;;
                install_pkg_fresh)         fmt="%s %s इंस्टॉल हो रहा है..." ;;
                install_version_bad)       fmt="त्रुटि: इंस्टॉल के बाद %s का संस्करण %s है, अपेक्षित %s था — रद्द किया जा रहा है।" ;;
                install_verify)            fmt="Hermes इंस्टॉलेशन सत्यापित हो रहा है..." ;;
                install_doctor_ok)         fmt="hermes doctor: OK" ;;
                install_doctor_warn)       fmt="hermes doctor को समस्याएं मिलीं — ऊपर दिया आउटपुट देखें।" ;;
                tunnel_usage)              fmt="उपयोग: %s <pages-project-name> <d1-name>" ;;
                tunnel_need_wrangler)      fmt="wrangler इंस्टॉल नहीं है (npm i -g wrangler)।" ;;
                tunnel_need_node)          fmt="node इंस्टॉल नहीं है।" ;;
                tunnel_no_token)           fmt="CLOUDFLARE_API_TOKEN सेट नहीं है; ज़रूरत पड़ने पर wrangler ब्राउज़र लॉगिन का उपयोग करेगा।" ;;
                tunnel_key_exists)         fmt="Key पहले से %s पर मौजूद है — मौजूदा key का ही उपयोग होगा।" ;;
                tunnel_gen_key)            fmt="नई tunnel key बनाई जा रही है..." ;;
                tunnel_mk_d1)              fmt="D1 डेटाबेस '%s' बनाया जा रहा है..." ;;
                tunnel_d1_exists)          fmt="D1 '%s' पहले से मौजूद है — बनाना छोड़ा गया।" ;;
                tunnel_apply_schema)       fmt="schema.sql को D1 पर लागू किया जा रहा है..." ;;
                tunnel_d1_noid)            fmt="D1 का database_id पढ़ने में विफल।" ;;
                tunnel_wrangler_toml)      fmt="Project '%s' के लिए wrangler.toml बनाया गया।" ;;
                tunnel_ensure_pages)       fmt="सुनिश्चित किया जा रहा है कि Pages project '%s' मौजूद है..." ;;
                tunnel_pages_exists)       fmt="Pages project '%s' पहले से मौजूद है — जारी है।" ;;
                tunnel_set_secret)         fmt="TUNNEL_KEY को Pages secret (production) के रूप में सेट किया जा रहा है..." ;;
                tunnel_deploy)             fmt="Pages पर deploy हो रहा है..." ;;
                tunnel_done)               fmt="हो गया! Tunnel URL: %s" ;;
                router_pw_warn)            fmt="चेतावनी: %s गायब या खाली है — 9Router डिफ़ॉल्ट पासवर्ड के साथ चल रहा है। फ़ाइल बनाएं (chmod 600) फिर रीस्टार्ट करें।" ;;
                router_pw_required_public) fmt="त्रुटि: %s गायब या खाली है लेकिन सार्वजनिक tunnel कॉन्फ़िगर है (.tunnel-url मौजूद है) — 9Router को डिफ़ॉल्ट dashboard पासवर्ड के साथ चलाने से इनकार। फ़ाइल बनाएं (chmod 600), या केवल स्थानीय उपयोग के लिए .tunnel-url हटा दें।" ;;
                tunnel_apply_migrations)   fmt="Migration 001-004 क्रम से लागू हो रहे हैं (नए डेटाबेस पर हानिरहित)..." ;;
                tunnel_apply_migration)    fmt="Migration %s लागू हो रहा है (schema_migrations में अभी दर्ज नहीं)..." ;;
                tunnel_schema_incomplete)  fmt="Migration के बाद भी tunnel schema अधूरा है — सेटअप रद्द किया जा रहा है।" ;;
                tunnel_gen_health_key)     fmt="Tunnel health key बनाई जा रही है..." ;;
                tunnel_health_key_exists)  fmt="Health key पहले से मौजूद है: %s (बनाए रखा गया)" ;;
                tunnel_gen_gate_pw)        fmt="Dashboard gate पासवर्ड बनाया जा रहा है..." ;;
                tunnel_gen_dashboard_pw)   fmt="9Router dashboard पासवर्ड (.dashboard-pw) बनाया जा रहा है..." ;;
                tunnel_gate_pw_file)       fmt="Gate पासवर्ड %s में सहेजा गया (chmod 600); Pages secret के रूप में GATE_PASSWORD + REQUIRE_GATE=1 सेट करें।" ;;
                tunnel_gate_skipped)       fmt="चेतावनी: SETUP_NO_GATE=1 — dashboard gate सेट नहीं है; सार्वजनिक tunnel URL बिना पासवर्ड gate के dashboard दिखाएगा।" ;;
                gw_no_pid)                 fmt="कोई gateway PID नहीं (%s)" ;;
                gw_abort_multi)            fmt="रद्द: %s gateway PID उम्मीदवार, kill नहीं किया जा रहा (अस्पष्ट): %s" ;;
                gw_kill_fail)              fmt="विफल: PID %s को kill नहीं किया जा सका" ;;
                gw_dryrun)                 fmt="DRY_RUN: would run start-gateway.sh + verify Connected" ;;
                gw_restart_ok)             fmt="RESTART OK: gateway फिर से चालू है + Telegram से Connected (%s)" ;;
                gw_restart_fail)           fmt="RESTART विफल: 60 सेकंड में 'Connected to Telegram' नहीं मिला (%s)" ;;
                gw_abort_ambiguous)        fmt="रद्द: %s gateway PID उम्मीदवार (अस्पष्ट), उन्हें छुआ नहीं गया: %s" ;;
                tunnel_env_missing)        fmt="TUNNEL_BASE_URL सेट नहीं है। उदाहरण:" ;;
                tunnel_env_example)        fmt="  TUNNEL_BASE_URL=https://<aapka-project>.pages.dev node tunnel-client.mjs" ;;
                tunnel_env_alt)            fmt="  (या start-pages-tunnel.sh से चलाने पर URL को .tunnel-url फ़ाइल में सहेजें)" ;;
                tunnel_key_unreadable)     fmt="Key फ़ाइल नहीं पढ़ी जा सकी: %s (इससे बनाएं: openssl rand -hex 32 > %s && chmod 600 %s)" ;;
                tunnel_key_empty)          fmt="%s में key खाली है" ;;
                tunnel_local_not_loopback) fmt="TUNNEL_LOCAL एक loopback URL होना चाहिए (मिला: %s)। TUNNEL_ALLOW_REMOTE_LOCAL=1 केवल तभी सेट करें जब आप सचमुच कहीं और forward करना चाहते हों।" ;;
                tunnel_response_too_large) fmt="स्थानीय प्रतिक्रिया %s MB की सीमा से अधिक है" ;;
                cf_usage)                  fmt="उपयोग: %s <tunnel-name> <hostname>" ;;
                cf_installing)             fmt="cloudflared इंस्टॉल हो रहा है..." ;;
                cf_have)                   fmt="cloudflared पहले से मौजूद है: %s" ;;
                cf_install_fail)           fmt="cloudflared इंस्टॉल करने में विफल। मैन्युअल रूप से इंस्टॉल करें: https://github.com/cloudflare/cloudflared/releases" ;;
                cf_unsupported_arch)       fmt="आर्किटेक्चर %s समर्थित नहीं है।" ;;
                cf_need_login)             fmt="Cloudflare में लॉगिन नहीं है — 'cloudflared tunnel login' चलाया जा रहा है..." ;;
                cf_login_fail)             fmt="Cloudflare लॉगिन विफल।" ;;
                cf_bad_hostname)           fmt="अमान्य hostname: %s (उदाहरण: 9router.example.com)" ;;
                cf_creating)               fmt="Tunnel '%s' बनाया जा रहा है..." ;;
                cf_exists)                 fmt="Tunnel '%s' पहले से मौजूद है — उसी का उपयोग होगा (id %s)।" ;;
                cf_created)                fmt="Tunnel बनाया गया: %s (id %s)" ;;
                cf_no_id)                  fmt="Tunnel ID निर्धारित करने में विफल।" ;;
                cf_no_cred)                fmt="Credentials फ़ाइल नहीं मिली: %s" ;;
                cf_writing_config)         fmt="Config %s में लिखा जा रहा है..." ;;
                cf_routing_dns)            fmt="DNS CNAME %s -> %s.cfargotunnel.com बनाया जा रहा है..." ;;
                cf_dns_exists)             fmt="DNS route विफल — रिकॉर्ड पहले से मौजूद हो सकता है। ज़रूरत हो तो CNAME मैन्युअल रूप से बनाएं।" ;;
                cf_9router_warn)           fmt="9Router 127.0.0.1:20128 पर जवाब नहीं दे रहा — tunnel का उपयोग करने से पहले सुनिश्चित करें कि वह चल रहा है।" ;;
                cf_done)                   fmt="हो गया! सार्वजनिक dashboard: https://%s" ;;
            esac
            ;;
        ja)
            case "$key" in
                install_debian_only) fmt="このスクリプトは Debian/Ubuntu 用です（apt-get が必要です）。他のディストリビューションでは手動でインストールしてください。" ;;
                install_need_sudo) fmt="'sudo' コマンドが必要です。または root としてこのスクリプトを実行してください。" ;;
                install_sudo_pw) fmt="sudo がパスワードを求めていますが、このスクリプトは非対話型で動作するよう設計されています。" ;;
                install_enable_sudo) fmt="このユーザーにパスワードなし sudo を有効にするか、root として実行してください。" ;;
                install_deps) fmt="基本依存パッケージ（git、curl、tar）をインストールしています..." ;;
                install_node) fmt="NodeSource 経由で Node.js LTS をインストールしています..." ;;
                install_have_node) fmt="Node.js はすでにインストールされています: %s" ;;
                install_hermes) fmt="Hermes Agent をインストールしています..." ;;
                install_have_hermes) fmt="Hermes はすでにインストールされています: %s" ;;
                install_version_ok) fmt="%s のバージョンを確認しました: %s" ;;
                install_align_version) fmt="%s はバージョン %s でインストールされていますが、このインストーラーは %s に固定しています — 合わせて再インストールしています..." ;;
                install_pkg_fresh) fmt="%s %s をインストールしています..." ;;
                install_version_bad) fmt="エラー: インストール後の %s のバージョンは %s ですが、想定は %s です — 中止します。" ;;
                install_verify) fmt="Hermes のインストールを検証しています..." ;;
                install_doctor_ok) fmt="hermes doctor: OK" ;;
                install_doctor_warn) fmt="hermes doctor で問題が見つかりました — 上の出力を確認してください。" ;;
                tunnel_usage) fmt="使い方: %s <pages-project-name> <d1-name>" ;;
                tunnel_need_wrangler) fmt="wrangler がインストールされていません（npm i -g wrangler）。" ;;
                tunnel_need_node) fmt="node がインストールされていません。" ;;
                tunnel_no_token) fmt="CLOUDFLARE_API_TOKEN が設定されていません。必要に応じて wrangler がブラウザーログインを使用します。" ;;
                tunnel_key_exists) fmt="キーはすでに %s に存在します — 既存のものを再利用します。" ;;
                tunnel_gen_key) fmt="新しい tunnel キーを生成しています..." ;;
                tunnel_mk_d1) fmt="D1 データベース '%s' を作成しています..." ;;
                tunnel_d1_exists) fmt="D1 '%s' はすでに存在します — 作成をスキップします。" ;;
                tunnel_apply_schema) fmt="schema.sql を D1 に適用しています..." ;;
                tunnel_d1_noid) fmt="D1 の database_id を読み取れませんでした。" ;;
                tunnel_wrangler_toml) fmt="プロジェクト '%s' の wrangler.toml を作成しました。" ;;
                tunnel_ensure_pages) fmt="Pages プロジェクト '%s' が存在することを確認しています..." ;;
                tunnel_pages_exists) fmt="Pages プロジェクト '%s' はすでに存在します — 続行します。" ;;
                tunnel_set_secret) fmt="TUNNEL_KEY を Pages のシークレットとして設定しています（production）..." ;;
                tunnel_deploy) fmt="Pages へデプロイしています..." ;;
                tunnel_done) fmt="完了しました！Tunnel URL: %s" ;;
                router_pw_warn) fmt="警告: %s が存在しないか空です — 9Router はデフォルトパスワードで動作します。ファイルを作成し（chmod 600）、再起動してください。" ;;
                router_pw_required_public) fmt="エラー: %s が存在しないか空ですが、公開 tunnel が設定されています（.tunnel-url が存在します）— デフォルトのダッシュボードパスワードで 9Router を実行することは拒否します。ファイルを作成するか（chmod 600）、ローカル専用にする場合は .tunnel-url を削除してください。" ;;
                tunnel_apply_migrations) fmt="マイグレーション 001-004 を順番に適用しています（新規データベースでも無害です）..." ;;
                tunnel_apply_migration) fmt="マイグレーション %s を適用しています（schema_migrations に未記録）..." ;;
                tunnel_schema_incomplete) fmt="マイグレーション後も tunnel スキーマが不完全です — セットアップを中止します。" ;;
                tunnel_gen_health_key) fmt="tunnel ヘルスキーを生成しています..." ;;
                tunnel_health_key_exists) fmt="ヘルスキーはすでに存在します: %s（保持します）" ;;
                tunnel_gen_gate_pw) fmt="ダッシュボード用ゲートパスワードを生成しています..." ;;
                tunnel_gen_dashboard_pw) fmt="9Router ダッシュボードパスワード（.dashboard-pw）を生成しています..." ;;
                tunnel_gate_pw_file) fmt="ゲートパスワードを %s に保存しました（chmod 600）。Pages シークレット GATE_PASSWORD と REQUIRE_GATE=1 を設定してください。" ;;
                tunnel_gate_skipped) fmt="警告: SETUP_NO_GATE=1 — ダッシュボードゲートは設定されていません。公開 tunnel URL はパスワードゲートなしでダッシュボードを提供します。" ;;
                gw_no_pid) fmt="ゲートウェイの PID がありません（%s）" ;;
                gw_abort_multi) fmt="中止: ゲートウェイ PID 候補が %s 件あります。曖昧なため kill しません: %s" ;;
                gw_kill_fail) fmt="失敗: PID %s を kill できませんでした" ;;
                gw_dryrun) fmt="DRY_RUN: start-gateway.sh を実行し、Connected を確認します" ;;
                gw_restart_ok) fmt="再起動 OK: ゲートウェイは復旧し、Telegram に接続しました（%s）" ;;
                gw_restart_fail) fmt="再起動失敗: 60 秒以内に 'Connected to Telegram' が確認できませんでした（%s）" ;;
                gw_abort_ambiguous) fmt="中止: ゲートウェイ PID 候補が %s 件あります（曖昧）。手を付けていません: %s" ;;
                tunnel_env_missing) fmt="TUNNEL_BASE_URL が設定されていません。例:" ;;
                tunnel_env_example) fmt="  TUNNEL_BASE_URL=https://<あなたのプロジェクト>.pages.dev node tunnel-client.mjs" ;;
                tunnel_env_alt) fmt="  （または start-pages-tunnel.sh 経由で実行する場合は、URL を .tunnel-url ファイルに保存してください）" ;;
                tunnel_key_unreadable) fmt="キーファイルを読み取れません: %s（作成方法: openssl rand -hex 32 > %s && chmod 600 %s）" ;;
                tunnel_key_empty) fmt="%s のキーが空です" ;;
                tunnel_local_not_loopback) fmt="TUNNEL_LOCAL は loopback URL でなければなりません（取得値: %s）。本当に別の場所へ転送する場合のみ TUNNEL_ALLOW_REMOTE_LOCAL=1 を設定してください。" ;;
                tunnel_response_too_large) fmt="ローカルレスポンスが上限 %s MB を超えています" ;;
                cf_usage) fmt="使い方: %s <tunnel-name> <hostname>" ;;
                cf_installing) fmt="cloudflared をインストールしています..." ;;
                cf_have) fmt="cloudflared はすでにインストールされています: %s" ;;
                cf_install_fail) fmt="cloudflared のインストールに失敗しました。手動でインストールしてください: https://github.com/cloudflare/cloudflared/releases" ;;
                cf_unsupported_arch) fmt="アーキテクチャ %s はサポートされていません。" ;;
                cf_need_login) fmt="Cloudflare にログインしていません — 'cloudflared tunnel login' を実行しています..." ;;
                cf_login_fail) fmt="Cloudflare へのログインに失敗しました。" ;;
                cf_bad_hostname) fmt="無効なホスト名です: %s（例: 9router.example.com）" ;;
                cf_creating) fmt="tunnel '%s' を作成しています..." ;;
                cf_exists) fmt="Tunnel '%s' はすでに存在します — 再利用します（id %s）。" ;;
                cf_created) fmt="Tunnel を作成しました: %s（id %s）" ;;
                cf_no_id) fmt="tunnel ID を特定できませんでした。" ;;
                cf_no_cred) fmt="認証情報ファイルが見つかりません: %s" ;;
                cf_writing_config) fmt="設定を %s に書き込んでいます..." ;;
                cf_routing_dns) fmt="DNS CNAME %s -> %s.cfargotunnel.com を作成しています..." ;;
                cf_dns_exists) fmt="DNS ルートの作成に失敗しました — レコードがすでに存在する可能性があります。必要に応じて CNAME を手動で作成してください。" ;;
                cf_9router_warn) fmt="9Router が 127.0.0.1:20128 で応答していません — tunnel を使う前に起動していることを確認してください。" ;;
                cf_done) fmt="完了しました！公開ダッシュボード: https://%s" ;;
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
                router_pw_warn)      fmt="PERINGATAN: %s tidak ada atau kosong — 9Router jalan dengan password default. Buat file-nya (chmod 600) lalu restart." ;;
                router_pw_required_public) fmt="ERROR: %s tidak ada atau kosong tapi tunnel publik terkonfigurasi (.tunnel-url ada) — menolak menjalankan 9Router dengan password dashboard default. Buat file-nya (chmod 600), atau hapus .tunnel-url untuk pemakaian lokal saja." ;;
                tunnel_apply_migrations) fmt="Menerapkan migrasi 001-004 berurutan (aman untuk database baru)..." ;;
                tunnel_apply_migration) fmt="Menjalankan migrasi %s (belum tercatat di schema_migrations)..." ;;
                tunnel_schema_incomplete) fmt="Skema tunnel masih belum lengkap setelah migrasi — setup dibatalkan." ;;
                tunnel_gen_health_key) fmt="Membuat kunci kesehatan tunnel..." ;;
                tunnel_health_key_exists) fmt="Kunci kesehatan sudah ada: %s (dipertahankan)" ;;
                tunnel_gen_gate_pw)  fmt="Membuat password gate dashboard..." ;;
                tunnel_gen_dashboard_pw) fmt="Membuat password dashboard 9Router (.dashboard-pw)..." ;;
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
