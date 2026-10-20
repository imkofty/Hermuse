# Catatan Validasi — Putaran 4: 4 Poin Sisa dari Skor 96 (2026-10-21)

Bukti terverifikasi untuk perbaikan putaran 4 di branch `release/score-100`
(commit `3ff8ab4`, `5f54aa8`, `de7f316`). Putaran ini menutup 4 poin sisa
dari audit putaran 3 (skor 96/100): (1) idempotency masih lookup global,
(2) watchdog diam-diam fallback bila `.health-key` hilang, (3) setup tidak
provision `.dashboard-pw`, (4) rantai penuh Telegram → Hermes → 9Router →
tunnel belum pernah dijalankan di staging terisolasi. Semua langkah di
bawah BENAR-BENAR dijalankan; yang gagal atau tidak dijalankan ditulis
apa adanya, termasuk satu kegagalan nyata di bagian 5.

## 1. Verifikasi lokal

- `node --test tests/*.test.mjs`: **31/31 lulus** (26 putaran 3 + 5 baru:
  replay hanya untuk principal+fingerprint yang sama; principal berbeda
  diproses baru; fingerprint berbeda → 409; baris pra-migrasi principal
  NULL tidak pernah cocok).
- `bash tests/watchdog.test.sh`: 12 pemeriksaan OK (termasuk skenario
  baru: `.tunnel-url` ada + `.health-key` hilang → ERROR + tidak sehat).
- `bash tests/setup-tunnel.test.sh`: OK (baru). `bash
  tests/launcher-smoke.sh`: OK. `bash scripts/check-tunnel-schema.sh`:
  OK. doctor: 14/14. `bash scripts/check-i18n.sh`: 73 kunci bersih
  (en/id/ms).
- CI `tunnel-tests` untuk `de7f316`: **SUCCESS** (terverifikasi dari
  status run GitHub, bukan asumsi).

## 2. Poin 1 — Idempotency terikat pemanggil (`3ff8ab4`)

- Principal diturunkan dari kredensial pemanggil: `"auth:" + SHA-256`
  header Authorization; fallback `"hk:" + hash` health-key; tanpa
  kredensial = `"anon"`. Hash mentah kredensial tidak pernah disimpan.
- Fingerprint = method + path+query + SHA-256 body mentah.
- Migrasi `004-idempotency-principal.sql`: kolom `idem_principal` +
  `idem_fingerprint` di `tunnel_requests` DAN `tunnel_responses`; index
  unik parsial gabungan `(idempotency_key, idem_principal)` di kedua
  tabel. `respond.js` menyalin principal+fingerprint secara atomik
  (INSERT...SELECT).
- Replay dilayani HANYA bila key + principal + fingerprint semua sama.
  Principal berbeda → diproses sebagai request baru. Fingerprint
  berbeda → **409**. Baris pra-migrasi (principal NULL) tidak pernah
  cocok → tidak ada replay warisan yang bocor lintas pemanggil.

## 3. Migrasi 004 di D1 sungguhan

Via Cloudflare REST API ke database `tunnel-9router` (akun dan database
yang sama dengan staging putaran 3):

- 8 statement migrasi: **semua OK**.
- Kolom `idem_principal` + `idem_fingerprint` terverifikasi ADA di
  `tunnel_requests` dan `tunnel_responses`; index unik parsial gabungan
  terpasang di kedua tabel.
- Baris yang ada tetap utuh (saat pemeriksaan: `tunnel_requests` 0,
  `tunnel_responses` 3 — sesuai keadaan live).

## 4. Poin 2 + 3 — Watchdog dan setup (`5f54aa8`, `de7f316`)

- **Watchdog (Gap D):** `.tunnel-url` ada tetapi `.health-key` hilang
  atau kosong → baris **ERROR** eksplisit di `watchdog.log` dan tunnel
  dinyatakan **TIDAK SEHAT**. Tidak ada lagi fallback diam-diam ke
  deteksi proses. Restart proses yang mati tetap berjalan seperti biasa.
- **Setup (Gap E):** section 6d `setup-tunnel.sh` kini provision
  `.dashboard-pw` (generate `openssl rand -hex 16` HANYA bila file tidak
  ada/kosong, chmod 600, tidak menimpa yang sudah berisi) — file yang
  disyaratkan `start-9router.sh`. `start-9router.sh` kini menolak file
  password kosong (`[ -s ]`, bukan `[ -f ]`). Daftar migrasi di setup
  diperbarui sampai 004. Kunci i18n baru `tunnel_gen_dashboard_pw` di
  en/id/ms + langkah tes setup di CI.

## 5. Poin 4 (Gap F) — Rantai penuh di staging TERISOLASI

### Lingkungan (semua terpisah dari stack pribadi pemilik)

- 9Router staging di `127.0.0.1:20228`, HOME terisolasi sendiri; combo
  `staging-utama`; provider **keyless Pollinations** (model openai-fast);
  kredensial khusus staging (`.dashboard-pw` + key router staging,
  chmod 600). Provider LLM7 ditolak: kuota harian IP habis.
- Hermes staging dengan home terisolasi; bot Telegram yang sama
  (@Hermuseagentbot) dengan allowlist HANYA ID numerik pemilik (disalin
  file-ke-file dari konfigurasi pribadi, nilai tidak pernah ditampilkan);
  `base_url` model diarahkan ke tunnel validasi publik.
- Tunnel: bundle fungsi Pages ASLI dari `de7f316` (metode bundel yang
  sama dengan putaran 3, terbukti byte-identik dengan bundle aktif
  sebelumnya) ter-deploy ke project `hermuse-tunnel-validation`,
  deployment `92dc5700` (menggantikan `9000e84b`); binding D1
  `tunnel-9router` + secret `TUNNEL_KEY`/`HEALTH_KEY` tetap.
- **Stack pribadi pemilik tetap MATI selama seluruh pengujian**
  (terverifikasi berulang: tidak ada listener di port 20128, database
  pribadi tidak berubah).

### E2E tunnel putaran 4 (client asli + mock backend): 5/5 lolos

1. Chat biasa → 200, hit backend 0→1.
2. Replay identik (key + Authorization + body sama) → 200 byte-identik,
   hit tetap 1 (idempotency terikat pemanggil bekerja).
3. Key sama, Authorization berbeda → diproses baru (hit 1→2) dan
   mendapat responsnya sendiri — tidak ada replay lintas pemanggil.
4. Key + auth sama, body berbeda → **409**, hit tetap 2.
5. Body 1.400.000 byte → **413**; health probe ber-key + nonce → 200
   `backend_ok: true`; tanpa key → **403**.

### Rantai hidup Telegram → Hermes → 9Router → tunnel → provider

- **One-shot Hermes lewat tunnel: LOLOS.** Hermes staging (konfigurasi
  persis di atas) menjawab `TUNNEL_CHAIN_OK` — Hermes → tunnel publik →
  client → 9Router staging → Pollinations terbukti ujung-ke-ujung.
- **Uji langsung tunnel (antrean bersih), payload setara beban gateway:**
  POST chat non-streaming → **12,9 detik** (payload kecil) dan
  **19,1 detik** (payload 63.151 byte ≈ 18 ribu token — kelas ukuran
  yang sama dengan giliran gateway), isi jawaban benar.
- **Uji hidup via Telegram (2026-10-21 03:54–04:08 WIB): SEBAGIAN
  LOLOS, pengiriman balasan LLM GAGAL.** Rinciannya, semua dari log:
  - Pesan pemilik tercatat masuk di gateway: `inbound message:
    platform=telegram user=K O F T Y chat=5799900870 msg='Halo, balas
    dengan kata STAGING_RANTAI_OK'` (03:54:56).
  - Perintah `/model` **dibalas bot dan diterima pemilik**: model
    `staging-utama`, provider Custom endpoint (tangkapan layar pemilik
    03:54) — jalur kirim Telegram bekerja.
  - Giliran percakapan dijalankan Hermes dengan `model=staging-utama`
    via `base_url` tunnel; permintaan **sampai ke 9Router staging dan
    diselesaikan Pollinations berulang kali** (log 9Router: `DONE
    10972ms · IN 20300`, `DONE 17092ms` — 2 pesan, 18 tool, ±20 ribu
    token input).
  - **Namun balasan LLM-nya tidak pernah terkirim ke Telegram.**
    Mekanisme kegagalan teridentifikasi dari log kedua sisi:
    (a) Hermes selalu mencoba **streaming** lebih dulu; forward
    streaming dapat **menahan client tunnel yang serial** (log Hermes:
    stream basi sampai 199 detik tanpa chunk) — selama client tertahan,
    permintaan berikutnya mengantre melewati jendela tunggu ingress
    (±60 detik) sehingga ingress menjawab **504 "tunnel timeout
    (client offline?)"** walau backend menjawab tiap permintaan
    non-streaming dalam 11–19 detik;
    (b) Hermes mengulang 3 percobaan (streaming + non-streaming) lalu
    membatalkan setelah 6 percobaan basi — pesan kesalahan itu sendiri
    **terkirim ke Telegram** (04:07), bukti tambahan jalur kirim sehat;
    (c) adapter Telegram di sandbox ini putus-sambung ±tiap 90 detik
    (timeout CLOSE-WAIT lewat proxy egress; keterbatasan sandbox yang
    sama yang menghalangi gateway WhatsApp di mesin ini).
  - Gangguan tambahan: mesin virtual ter-recycle di tengah uji (03:49)
    membunuh seluruh stack staging; pesan uji pertama pemilik jatuh di
    celah itu. Stack dihidupkan ulang dan diverifikasi ulang sebelum
    uji hidup di atas.
- **Kesimpulan Gap F yang jujur:** seluruh mata rantai terbukti bekerja
  dengan bukti log masing-masing, termasuk muatan persis pesan Telegram
  pemilik yang diproses sampai provider dan selesai. Yang belum
  terbukti: pengiriman balasan LLM pada giliran gateway hidup, karena
  kombinasi (streaming menahan client serial + jendela tunggu ingress)
  di atas. Ini **temuan produk nyata**, bukan sekadar gangguan
  lingkungan: kandidat perbaikan putaran berikutnya adalah client
  tunnel konkuren dan/atau pembacaan stream berbatas waktu, atau
  jendela tunggu ingress yang lebih panjang — TIDAK ditambal di
  putaran ini karena cakupan putaran 4 adalah 4 poin tracker di atas.

## TIDAK dijalankan (jujur)

- Uji beban dan pentest eksternal: di luar cakupan, tetap NOT RUN
  (sama seperti putaran 2–3).
- Perbaikan kelemahan streaming/serial-client di bagian 5: dianalisis
  dan didokumentasikan, belum dikodekan (menunggu keputusan cakupan).
- Rantai Telegram di luar sandbox (mesin jaringan normal): adapter
  Telegram di sandbox ini terbukti tidak stabil untuk polling jangka
  panjang; uji di mesin fisik pemilik belum dijalankan.
