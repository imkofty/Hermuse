# Hermuse — self-hosted AI agent stack (Hermes + 9Router + Telegram)

![Hermuse banner](assets/banner.png)

[🇬🇧 English](README.md) · 🇮🇩 **Indonesia** · [🇲🇾 Malaysia](README.ms.md)

[![Stars](https://img.shields.io/github/stars/imkofty/Hermuse?style=for-the-badge&logo=github&color=20808D)](https://github.com/imkofty/Hermuse/stargazers)
[![Forks](https://img.shields.io/github/forks/imkofty/Hermuse?style=for-the-badge&logo=github&color=4DD0E1)](https://github.com/imkofty/Hermuse/network/members)
[![Issues](https://img.shields.io/github/issues/imkofty/Hermuse?style=for-the-badge&logo=github&color=FFB454)](https://github.com/imkofty/Hermuse/issues)
[![License: MIT](https://img.shields.io/github/license/imkofty/Hermuse?style=for-the-badge&color=3FB950)](LICENSE)
[![doctor](https://github.com/imkofty/Hermuse/actions/workflows/doctor.yml/badge.svg)](https://github.com/imkofty/Hermuse/actions/workflows/doctor.yml)

[![Linux](https://img.shields.io/badge/OS-Linux-FCC624?style=for-the-badge&logo=linux&logoColor=black)](https://ubuntu.com/)
[![Node.js](https://img.shields.io/badge/node-%3E%3D18-339933?style=for-the-badge&logo=node.js&logoColor=white)](https://nodejs.org/)
[![Telegram](https://img.shields.io/badge/Telegram-Gateway-26A5E4?style=for-the-badge&logo=telegram&logoColor=white)](https://core.telegram.org/bots)
[![Cloudflare](https://img.shields.io/badge/Cloudflare-Tunnel-F68204?style=for-the-badge&logo=cloudflare&logoColor=white)](https://www.cloudflare.com/)
[![Bash](https://img.shields.io/badge/Bash-Scripts-4EAA25?style=for-the-badge&logo=gnu-bash&logoColor=white)]()

**Hermuse = Hermes + Muse.** Repo ini berisi script dan panduan untuk
menjalankan Hermes Agent (AI agent dari Nous Research) + 9Router + Telegram
gateway di server sendiri — replika persis dari stack yang berjalan di VM Muse.

**Hasil akhirnya:** bot Telegram AI pribadi yang online 24/7 dan bisa kamu chat
kapan saja, plus dashboard model yang bisa dibuka dari browser.

## Mulai dari sini

Yang kamu butuhkan:

- VM Linux seperti VM Muse (Ubuntu 22.04/24.04; 2 vCPU / 4 GB RAM cukup)
- Akun Cloudflare gratis (untuk tunnel dashboard)
- Bot Telegram (bikin gratis via [@BotFather](https://t.me/BotFather))

**Belum pernah install apa-apa?** Ikuti urutan ini:

1. `bash scripts/install.sh` — install otomatis semuanya (dependensi, Hermes, 9Router)
Verify: `hermes --version` → mencetak baris versi; `9router --version` → mencetak versi
2. `hermes setup --portal` — login model; `hermes gateway setup` — sambungkan bot Telegram
Verify: kirim `/start` ke bot kamu → bot membalas (ID Telegram numerik kamu harus ada di allowlist gateway)
3. `bash scripts/setup-tunnel.sh <nama-pages-project> <nama-d1>` — pasang tunnel Cloudflare
Verify: `pgrep -f "tunnel-client[.]mjs"` → mencetak PID
4. Ikuti [urutan boot yang benar](#urutan-boot-yang-benar) di bawah, lalu pasang watchdog di cron
Verify: `bash scripts/doctor.sh` → ringkasan menunjukkan `0 FAIL`

Sudah paham dan mau langsung pakai script operasionalnya? Lihat tabel
[layout file](#layout-file).

## Cara kerja

```
Telegram (kamu)
   │ polling
   ▼
Hermes gateway  ──▶  model:
   (run-hermes.sh)        ├─▶ Nous (langsung, via OAuth / API key)
                          └─▶ 9Router  (127.0.0.1:20128, OpenAI-compatible)

Browser (internet)
   │ HTTPS biasa
   ▼
<project-kamu>.pages.dev  (Cloudflare Pages Functions)
   │ antrean request/response
   ▼
D1  (tabel tunnel_requests / tunnel_responses)
   ▲ long-poll HTTPS ~20 detik
   │
tunnel-client.mjs  (di VM)
   │ forward
   ▼
9Router di 127.0.0.1:20128
```

**Kenapa long-poll?** Endpoint `/__tunnel/poll` menahan koneksi sampai
~20 detik saat antrean kosong, baru merespons (atau langsung merespons kalau
ada request masuk). Tanpa ini, polling tiap 400ms–2,5 detik bisa menghabiskan
jatah **100 ribu request/hari Cloudflare Workers free tier** dalam hitungan
jam; dengan long-poll, pemakaian idle turun ke ~4.300 request/hari. Lihat
`tunnel/pages-tunnel/functions/__tunnel/poll.js` untuk implementasinya.

9Router hanya di-bind ke `127.0.0.1` (aman, tidak terekspos). Tunnel polling
dipakai karena di jaringan VM asal WebSocket, QUIC/UDP, dan koneksi
`cloudflared` ke edge semuanya gagal — lihat
[arsip kegagalan](docs/arsip-tunnel-gagal.md). Di VM/jaringan normal,
`cloudflared` biasa kemungkinan justru lebih sederhana.

## Layout file

| File | Peran |
|---|---|
| `run-hermes.sh` | Menjalankan Hermes CLI. Default: meneruskan ke perintah `hermes` standar hasil `scripts/install.sh`. Mode venv opsional: set env `HERMES_VENV` + `HERMES_SRC` (divalidasi di awal; path tidak valid gagal cepat dengan pesan jelas). |
| `start-gateway.sh` | Menjalankan Telegram gateway detached (`setsid`+`nohup`). |
| `start-9router.sh` | Supervisor 9Router: bind `127.0.0.1:20128`, auto-restart saat crash. Password dashboard dibaca dari file `.dashboard-pw` (600). |
| `start-pages-tunnel.sh` | Supervisor tunnel client (`tunnel-client.mjs`), auto-restart. |
| `restart-9router.sh` | Kill proses 9Router lama (pola aman, anti self-kill) + jalankan supervisor detached. |
| `restart-tunnel.sh` | Kill tunnel client lama + jalankan supervisor detached. |
| `watchdog.sh` | Cek 9Router, tunnel client, gateway; restart yang mati. Untuk cron. |
| `gateway-watch.sh` | Watchdog anti-stall gateway Telegram: deteksi macet diam-diam via heartbeat event-loop + aktivitas adapter, bukan cuma cek proses hidup. Untuk cron (tiap 5 menit). |
| `tunnel-client.mjs` | Client polling: ambil antrean dari Pages, forward ke 9Router lokal, kirim respons balik. |
| `tunnel/` | Skema D1 (`schema.sql`) + Pages Functions + `wrangler.toml.example`. |
| `scripts/install.sh` | Install dari nol: dependensi, Node.js LTS, Hermes, 9Router. |
| `scripts/setup-tunnel.sh` | Setup tunnel: generate key → buat D1 → deploy Pages → set secret. |
| `docs/arsip-tunnel-gagal.md` | Arsip: `cloudflared` & Tailscale yang gagal di jaringan VM asal. |

## Urutan boot yang benar

Jalankan berurutan (cukup sekali; supervisor + watchdog yang menjaga sisanya):

1. 9Router dulu (supervisor detached, auto-restart):
   `bash restart-9router.sh`
Verify: `curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:20128/dashboard` → mencetak `200` atau `307` (307 = redirect ke login, normal)

2. Tunnel client (butuh `TUNNEL_BASE_URL` atau file `.tunnel-url`):
   `export TUNNEL_BASE_URL='https://<project-kamu>.pages.dev'` lalu `bash restart-tunnel.sh`
Verify: `pgrep -f "tunnel-client[.]mjs"` → mencetak PID

3. Telegram gateway (detached):
   `bash start-gateway.sh`
Verify: `pgrep -f "[g]ateway['\", ]+run"` → mencetak tepat satu PID

Lalu buka `https://<project-kamu>.pages.dev` di browser — dashboard 9Router
harus muncul. Kalau dapat `504 tunnel timeout (client offline?)`, berarti
tunnel client belum jalan.

## Watchdog (cron tiap 5 menit)

```bash
crontab -e
# tambahkan baris ini (sesuaikan path):
*/5 * * * * /path/ke/Hermuse/watchdog.sh
```

Watchdog mengecek tiga hal — 9Router (`curl` ke `/dashboard`), tunnel client
(`pgrep tunnel-client[.]mjs`), gateway Telegram (`gateway.*run`) — dan
me-restart yang mati via script `restart-*`. Ia diam (tidak menulis log) kalau
semua sehat; hanya mencatat saat benar-benar me-restart.

> Untuk cron: simpan URL tunnel di file `.tunnel-url` (chmod 600) di folder
> ini, karena cron tidak mewarisi environment variable interaktif:
> `echo -n 'https://<project-kamu>.pages.dev' > .tunnel-url && chmod 600 .tunnel-url`

## Watchdog anti-stall gateway (opsional tapi disarankan)

`watchdog.sh` di atas hanya mengecek "proses ada/tidak". Kalau polling Telegram
macet padahal proses masih hidup, ia lolos dari deteksi. `gateway-watch.sh`
menutup lubang itu dengan tiga lapis cek:

1. PID gateway tidak ada → restart langsung.
2. Heartbeat event-loop (`$HERMES_HOME/state/gateway.heartbeat`, ditulis
   otomatis oleh gateway) basi >120 detik → restart langsung.
3. Heartbeat segar tapi 0 aktivitas adapter Telegram di `gateway.log`
   selama 15 menit → tandai suspect, restart kalau terkonfirmasi
   2 run beruntun.

Aturan keras: hanya kill kalau tepat 1 kandidat PID (tidak ambigu).
Tidak menyentuh 9Router sama sekali. Untuk uji coba tanpa aksi nyata:
`DRY_RUN=1 bash gateway-watch.sh`.

```bash
crontab -e
# tambahkan (selang-seling dengan watchdog.sh juga boleh):
*/5 * * * * /path/ke/Hermuse/gateway-watch.sh
```

## Auto-start setelah reboot

`scripts/start-all.sh` menyalakan semua komponen Hermuse yang mati (9Router,
tunnel client, Telegram gateway) — idempoten, yang sudah jalan tidak disentuh:

```bash
bash /path/ke/Hermuse/scripts/start-all.sh
```

Agar otomatis jalan setiap VPS reboot, contoh untuk VPS Linux normal:

**Opsi 1 — cron `@reboot`:**

```bash
crontab -e
# tambahkan:
@reboot sleep 30 && /path/ke/Hermuse/scripts/start-all.sh >> /path/ke/Hermuse/boot.log 2>&1
```

**Opsi 2 — systemd user unit** (`~/.config/systemd/user/hermuse.service`):

```ini
[Unit]
Description=Hermuse stack (9Router + tunnel + Telegram gateway)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/path/ke/Hermuse/scripts/start-all.sh
RemainAfterExit=yes

[Install]
WantedBy=default.target
```

```bash
systemctl --user daemon-reload
systemctl --user enable --now hermuse.service
# agar jalan tanpa login: sudo loginctl enable-linger $USER
```

(Kedua contoh di atas untuk VPS/jaringan normal dan belum diuji di semua
distro — sesuaikan dengan sistem masing-masing. Watchdog cron tiap 5 menit
tetap disarankan sebagai jaring pengaman.)

## Install dari nol

Belum punya apa-apa? Mulai dari sini:

```bash
bash scripts/install.sh        # dependensi + Node.js + Hermes + 9Router + hermes doctor
```
(butuh `sudo` tanpa password, atau jalankan sebagai root — script-nya langsung berhenti kalau tidak)

Lalu setup provider model & Telegram gateway (wizard):

```bash
hermes setup --portal   # login Nous via OAuth (atau: hermes model untuk pilih provider)
hermes gateway setup    # isi token bot Telegram + allowlist numeric ID
```

Terakhir, setup tunnel Cloudflare-nya:

```bash
CLOUDFLARE_API_TOKEN='<token>' bash scripts/setup-tunnel.sh <nama-pages-project> <nama-d1>
```

(Token Cloudflare dipakai transient saja — tidak disimpan di file mana pun.)

## Keamanan — jangan dilewatkan

- File berisi secret **selalu `chmod 600`** dan **tidak pernah di-commit**:
  `.env`, `.tunnel-key`, `.tunnel-url`, `.dashboard-pw`, `wrangler.toml`
  (sudah tercakup di `.gitignore`).
- Telegram gateway: **default-deny**. Hanya numeric ID di
  `TELEGRAM_ALLOWED_USERS` yang bisa memakai bot (`TELEGRAM_BOT_TOKEN` +
  `TELEGRAM_ALLOWED_USERS` di `.env`).
- **Password dashboard 9Router:** `scripts/setup-tunnel.sh` membuatkan
  `.dashboard-pw` (600) untukmu, dan `start-9router.sh` menolak jalan
  selama tunnel publik terkonfigurasi bila file itu tidak ada atau
  kosong. Ganti isinya bila ingin password sendiri.
- Jangan expose port 20128 ke internet tanpa proteksi; 9Router di-bind ke
  `127.0.0.1` saja.
- Kalau token bot Telegram bocor: `/revoke` di @BotFather, ganti di `.env`,
  restart gateway.
- **Mau rotasi kredensial?** Ikuti [panduan rotasi kredensial](docs/key-rotation.id.md) langkah-demi-langkah (tunnel key, password dashboard, token bot).
- **Auth tunnel fail-closed.** Fungsi Pages menolak semua panggilan poll/respond
  kecuali `TUNNEL_KEY` ter-set sebagai Pages secret DAN cocok dengan key
  client — secret kosong tidak lagi berarti "tunnel terbuka".
- **Upgrade database tunnel yang sudah ada?** Jalankan migrasi sekali jalan
  ini **berurutan** — database lama butuh keempatnya, bukan cuma yang pertama:
  `wrangler d1 execute <db-name> --remote --file=tunnel/migrations/001-claim-lease.sql`
  lalu `002-idempotency-ratelimit.sql`, lalu `003-response-idempotency.sql`,
  lalu `004-idempotency-principal.sql`
  (perintah sama, beda `--file`). Instalasi baru tidak memerlukannya
  (schema.sql sudah memuat semuanya), dan menjalankan ulang
  `scripts/setup-tunnel.sh` menerapkannya untukmu. Verifikasi sesudahnya
  dengan `bash scripts/check-tunnel-schema.sh <db-name>` — skrip itu
  mencetak perintah perbaikan yang persis untuk yang masih kurang.
- **Payload dibatasi sesuai kapasitas simpan D1.** D1 membatasi satu
  string/BLOB/baris pada 2.000.000 byte dan body berjalan sebagai Base64,
  jadi tunnel menerima body request/respons s/d 1.350.000 byte mentah
  (1.800.000 karakter Base64); payload lebih besar menerima 413 yang
  jelas, bukan insert database yang gagal diam-diam.
- **Idempotency terikat ke pemanggil.** Respons yang tersimpan hanya
  dilayani ulang bila key idempotency, kredensial pemanggil, dan payload
  request persis semuanya cocok. Key yang sama dengan payload berbeda
  menerima 409 Conflict; respons pemanggil lain tidak pernah dilayani
  ke kamu.
- **Cek kesehatan watchdog melewati tunnel sungguhan.** Dengan file
  `.health-key` (dibuat `scripts/setup-tunnel.sh`), watchdog dan doctor
  memverifikasi tunnel publik ujung-ke-ujung memakai probe nonce
  terautentikasi yang dijawab client lokal — 401/403 dari edge saja
  tidak lagi dihitung "sehat". Bila `.tunnel-url` ada tapi `.health-key`
  tidak ada atau kosong, watchdog menulis ERROR keras dan menyatakan
  pemeriksaan tunnel GAGAL, bukan melewati probe diam-diam.

## Catatan

<details>
<summary><strong>Yang gagal di jaringan asal (arsip)</strong></summary>

Di jaringan VM asal, dua pendekatan standar **gagal total**:

- **Cloudflare Tunnel (`cloudflared`)** — QUIC/UDP diblokir, TLS ke edge IP
  di-intercept, proxy menolak CONNECT ke port 7844.
- **Tailscale** — control plane gagal menembus jaringan (HTTP 400 akibat MITM).

Detail + contoh config yang disanitasi:
[docs/arsip-tunnel-gagal.md](docs/arsip-tunnel-gagal.md).
Di VM/jaringan normal keduanya kemungkinan justru cara termudah.

</details>

## Lisensi

MIT.
