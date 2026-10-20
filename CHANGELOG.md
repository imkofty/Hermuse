# Changelog

Semua perubahan penting di repo ini dicatat di sini, format ala Keep a Changelog.

## Kandidat update berikutnya
- Script autopanen: panen endpoint AI gratisan (OpenAI-compatible) secara berkala dan daftarkan otomatis sebagai provider 9Router. Arsitektur routing: **hasil panen sebagai jalur utama, Nous sebagai fallback** (kebalik dari asumsi awal).
- `hermuse-doctor`: script cek kesehatan all-in-one.
- Installer satu baris.

## [Unreleased]

### Putaran 2 (audit lanjutan 2026-10-20, skor 61 -> 78 -> putaran ini)
- **Release blocker P0 ditutup**: semua script entry-point kini tersimpan executable (100755) di git — clone segar di Linux tidak lagi gagal "Permission denied" saat `start-gateway.sh` memanggil `./run-hermes.sh`. `tests/launcher-smoke.sh` membuktikannya dari checkout apa adanya. CI `tunnel-tests` kini jalan di SEMUA branch push + PR (sebelumnya hanya `main`, branch rilis tidak pernah ter-CI), ditambah langkah smoke launcher, tes watchdog, dan tes installer.
- **respond atomik**: validasi klaim + tulis respons = satu statement `INSERT ... SELECT ... WHERE EXISTS` (menutup jendela race SELECT->INSERT putaran 1). Lease klaim 30 dtk kini lebih pendek dari masa tunggu ingress 40 dtk; timeout ingress TIDAK membatalkan request — pemanggil menerima 504 + `x-tunnel-request-id` dan hasil akhir diambil via `GET /__tunnel/result?id=...`.
- **Idempotency & proteksi publik**: header `idempotency-key` mencegah request ganda berside-effect (migrasi 002: kolom + index unik parsial); rate limit per IP di ingress (default 120/menit, `RATE_LIMIT_PER_MIN`); gate HTTP Basic opsional untuk dashboard (`GATE_PASSWORD`/`GATE_USER`, `REQUIRE_GATE=1` tanpa password = 500 fail-closed); body ingress kini dibaca streaming berbatas (jalur tanpa Content-Length tidak lagi ditampung utuh di memori).
- **Installer menegakkan pin versi**: versi terpasang 9Router & Wrangler diverifikasi terhadap pin (package.json) — beda versi dipasang ulang persis pin (upgrade/downgrade), hasil akhir dicek ulang, tak cocok = gagal jelas. Dites oleh `tests/installer-version.test.sh` (mengekstrak fungsi asli installer).
- **Watchdog**: kunci `flock` anti-run-tumpang-tindih + cek ujung-ke-ujung URL publik (`.tunnel-url`) untuk client hidup-tapi-macet. Dites oleh `tests/watchdog.test.sh` (6 skenario).
- **Tes client sungguhan** `tests/client.test.mjs`: client dijalankan sebagai proses melawan server stub — redirect backend terbukti TIDAK diikuti, timeout backend -> 502, respons normal utuh. Total suite: 18 tes Node + 3 tes shell, semua lulus; i18n 65/65 bersih di 3 bahasa.

### Keamanan (audit menyeluruh 2026-10-20)
- **Tunnel auth FAIL-CLOSED** (`functions/__tunnel/poll.js`, `respond.js`): `TUNNEL_KEY` yang tidak ter-set di server kini menolak SEMUA request. Sebelumnya cek `key !== env.TUNNEL_KEY` lolos bila key request dan secret server sama-sama kosong — tunnel tanpa secret berarti terbuka.
- **Klaim antrean ATOMIK + lease** (`poll.js`, `schema.sql`, `migrations/001-claim-lease.sql`): klaim kini satu statement `UPDATE ... RETURNING` dengan `claim_token` + `claimed_at`. Menghilangkan race double-processing (dua poller menerima request yang sama) dan request yatim (klaim basi >45 dtk direbut kembali ke pending). `respond.js` hanya menerima respons dari pemegang klaim yang sah (token cocok), selain itu 409.
- **tunnel-client.mjs**: redirect backend tidak lagi diikuti (`redirect: "manual"` — respons 3xx diteruskan apa adanya, menutup jalur belok ke port/host lain); semua fetch ber-timeout eksplisit; respons backend dibaca streaming dengan batas 32 MB (dulu `arrayBuffer()` tanpa batas); `TUNNEL_LOCAL` wajib loopback kecuali opt-in `TUNNEL_ALLOW_REMOTE_LOCAL=1`; body request di ingress dibatasi 6 MB (lebih dari itu 413).
- **Test suite tunnel** (`tests/`, workflow CI `tunnel-tests.yml`): fungsi Pages ASLI dijalankan melawan SQLite sungguhan — regresi fail-closed, klaim atomik dua poller, lease/reclaim, round trip penuh, dan batas body. Plus cek sintaks shell & kelengkapan i18n di CI yang sama.
- `AGENTS.md`: token bot Telegram sebaiknya dimasukkan user langsung ke `.env` lokal, bukan lewat chat; bila terpaksa lewat chat, tulis segera dan jangan pernah di-echo.

### Diperbaiki (audit 2026-10-20)
- **`run-hermes.sh` ditulis ulang**: mode default kini memakai perintah `hermes` standar hasil installer. Mode venv menjadi opt-in eksplisit (`HERMES_VENV` + `HERMES_SRC`, keduanya di-export — dulu `HERMES_SRC` tidak pernah di-export sehingga Python `KeyError`, dan path default masih berisi placeholder `<INSTALL_ID>`/`<ENV_ID>`). Path invalid kini gagal cepat dengan pesan jelas.
- `scripts/install.sh`: versi 9Router & Wrangler di-pin (bisa dioverride/di-rollback via `HERMUSE_9ROUTER_VERSION` / `HERMUSE_WRANGLER_VERSION`); Wrangler kini dipasang oleh installer (prasyarat `setup-tunnel.sh` yang dulu tidak dijamin ada).
- `watchdog.sh`: cek kesehatan 9Router kini memvalidasi KODE STATUS HTTP dashboard (200/3xx = sehat) — `curl` polos exit 0 juga pada respons error sehingga 9Router setengah mati dulu terlihat sehat.
- `scripts/setup-tunnel-cloudflared.sh`: contoh systemd kini memakai path binary cloudflared yang benar-benar terpasang (`command -v`), bukan selalu mengasumsikan `~/.local/bin`.

### Ditambahkan
- `scripts/check-i18n.sh` + workflow CI `.github/workflows/i18n.yml` — setiap key yang dipakai via `t()` wajib punya terjemahan lengkap di ketiga bahasa (en/id/ms); build gagal kalau ada key yang hilang, key yang didefinisikan tapi tak dipakai hanya jadi warning.
- `scripts/setup-tunnel-cloudflared.sh` — setup Cloudflare Tunnel (cloudflared) untuk JARINGAN NORMAL: install binary bila belum ada, tunnel login/create, tulis config, route DNS CNAME `<hostname>` -> `<tunnel-id>.cfargotunnel.com`, plus instruksi run (foreground + contoh systemd). Bukan untuk sandbox/VM asal (cloudflared diblokir di sana — lihat docs/arsip-tunnel-gagal.md).
- `docs/key-rotation.md` (+ versi `.id`/`.ms`) — panduan rotasi kredensial trilingual langkah-demi-langkah: rotasi `TUNNEL_KEY` (generate baru → `wrangler pages secret put` → `restart-tunnel.sh`), rotasi password dashboard 9Router (`.dashboard-pw` baru → `restart-9router.sh`), rotasi token bot Telegram (`/revoke` di @BotFather → update `.env` → restart gateway). Setiap bagian mencakup backup sebelum rotasi, perintah copy-paste, verifikasi sesudahnya, dan prosedur rollback.
- `gateway-watch.sh` — watchdog anti-stall untuk Telegram gateway: 3 lapis deteksi (PID hilang, heartbeat event-loop basi, 0 aktivitas adapter Telegram 15 menit dengan konfirmasi 2 run), aturan keras hanya kill kalau tepat 1 kandidat PID, mode `DRY_RUN=1`, tidak menyentuh 9Router. Section dokumentasi di README.
- Section "Watchdog anti-stall gateway" di README + `gateway-watch.sh` di tabel layout file.
- `LICENSE` (MIT) — repo publik akhirnya punya lisensi biar orang berani fork/kontribusi.
- `scripts/start-all.sh` — starter idempoten semua komponen Hermuse (9Router, tunnel client, Telegram gateway); yang sudah jalan nggak disentuh. Siap dipanggil dari `@reboot` cron / systemd.
- Section "Auto-start" di README — contoh `@reboot` cron dan systemd user unit.
- `CHANGELOG.md` ini sendiri.

### Diperbaiki
- `restart-tunnel.sh`: supervisor `start-pages-tunnel.sh` ikut dibunuh sebelum restart — sebelumnya hanya client-nya yang dibunuh sehingga supervisor lama bisa menghidupkan client ganda.
- README: contoh `pgrep` di verifikasi & section watchdog diselaraskan ke pola exact `tunnel-client[.]mjs` (sebelumnya masih pola lama).
- README: diagram arsitektur "polling tiap ~400ms" → "long-poll ~20 detik", plus paragraf penjelasan kenapa long-poll ada (hemat jatah 100k request/hari Workers free tier).
- README: verifikasi `curl /dashboard` "harus 200" → "harus 200/307" (9Router balikin 307 redirect ke login, itu normal).
- `scripts/install.sh`: 9Router diinstall ke `$HOME/.npm-global` (konsisten sama PATH di script lain, aman tanpa root) + PATH dipersisten ke `~/.bashrc`.
- `scripts/install.sh`: flag manual `9router` disamakan dengan `start-9router.sh` (tambah `-l`).
- `restart-tunnel.sh`: pola kill dipersempit jadi exact `tunnel-client[.]mjs` — nggak ikut ngebunuh tunnel client lain di setup multi-tunnel.
- `tunnel-client.mjs`: komentar `TUNNEL_POLL_MS` diperjelas (sejak long-poll, ini cuma jeda tambahan antar long-poll, bukan interval polling utama).
- `watchdog.sh`: pola `pgrep` di-escape (`tunnel-client[.]mjs`) biar exact.
- `.gitignore`: tambah pola `.tunnel-key*` (varian key multi-tunnel nggak lolos ke-commit).
