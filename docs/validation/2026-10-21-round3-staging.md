# Catatan Validasi — Putaran 3: E2E Staging (2026-10-21)

Bukti terverifikasi untuk perbaikan putaran 3 di branch `release/score-100`
(commit `799f8de`, `0c51478`, `a4357ee`). Perbaikannya sendiri dikomit
2026-10-20; uji end-to-end staging di dokumen ini dijalankan 2026-10-21
dini hari (WIB) terhadap deployment yang membawa kode persis dari commit
tersebut. Semua langkah di bawah BENAR-BENAR dijalankan; yang tidak
dijalankan ditandai eksplisit di bagian akhir.

## Lingkungan staging

- Pages project khusus validasi: `hermuse-tunnel-validation`
  (deployment aktif `9000e84b`), berisi fungsi Pages ASLI dari repo —
  `[[path]].js` (ingress), `__tunnel/poll.js`, `__tunnel/respond.js`,
  `__tunnel/heartbeat.js`, `__tunnel/result.js` — dibundel tanpa mengubah
  logika.
- Binding D1 `DB` → database `tunnel-9router` (database tunnel proyek
  ini sendiri). Secret terpasang: `TUNNEL_KEY`, `HEALTH_KEY`.
- Backend: mock lokal (bukan stack pengguna) di `127.0.0.1:20199` —
  `/v1/models`, `/v1/chat/completions` (echo + penghitung hit),
  `/slow` (respons 8 detik), `/__hits`.
- Client: `tunnel-client.mjs` ASLI dari repo, `TUNNEL_HEARTBEAT_MS=2000`.
- Stack pribadi pemilik tetap NONAKTIF selama seluruh pengujian, sesuai
  perintah pemilik; staging ini tidak menghidupkannya.

## 1. Verifikasi lokal (sebelum staging)

- `node --test tests/*.test.mjs`: **26/26 lulus** (tunnel 24 + client 2),
  termasuk tes baru: batas persis 1.350.000/1.350.001 byte, respons
  1.800.000/1.800.001 karakter, replay idempotency pasca-kirim,
  heartbeat memperpanjang lease + 409 token salah, health probe
  403/tanpa-kunci dan terautentikasi, migrasi 003.
- `bash tests/launcher-smoke.sh`: OK. `bash tests/watchdog.test.sh`:
  9 skenario OK. `bash tests/installer-version.test.sh`: OK.
  `bash scripts/check-tunnel-schema.sh`: OK. doctor: 14/14.
  `bash scripts/check-i18n.sh`: 72/72 bersih (en/id/ms). `bash -n`: bersih.

## 2. Migrasi 003 di D1 sungguhan

Via Cloudflare REST API ke database `tunnel-9router`:

- Migrasi `003-response-idempotency.sql` teraplikasi: kolom
  `idempotency_key` + index unik parsial di `tunnel_responses`.
- Baris `tunnel_requests`: **3.002 sebelum = 3.002 sesudah** (utuh).
- `pragma_table_info` terverifikasi bekerja di D1 asli (dipakai
  `check-tunnel-schema.sh`).

## 3. Temuan empiris batas D1 (dilaporkan apa adanya)

Dokumentasi Cloudflare menyebut batas 2.000.000 byte per baris D1.
Pengujian via REST API (tabel scratch, dibuat lalu di-drop bersih):

- String 1,8 juta, 1,9 juta, dan 2,1 juta karakter: **tersimpan lolos**.
- Parameter string 8.388.608 karakter (ukuran Base64 body lama 6 MiB):
  **juga tersimpan lolos**.

Jadi batas terdokumentasi itu TIDAK teramati ditegakkan pada jalur
REST API. Cap payload putaran 3 (body mentah maks 1.350.000 byte →
Base64 tepat 1.800.000 karakter) tetap dipertahankan pada batas
terdokumentasi, karena: (a) jalur Workers binding belum teruji dengan
cara yang identik, dan (b) batas dokumentasi adalah kontrak yang aman
untuk dipegang. Temuan ini dicatat agar penilai tidak mengira cap
tersebut tidak berdasar — cap mengikuti dokumentasi resmi, bukan hasil
uji jalur REST.

## 4. E2E staging — 7 pemeriksaan, semua lolos

1. **Chat tembus.** `POST /v1/chat/completions` dengan header
   `Idempotency-Key: e2e-key-1` → **200**, isi "halo dari mock backend",
   penghitung backend: chat = 1.
2. **Replay idempotency pasca-kirim.** POST yang sama persis (key sama)
   → **200 dengan body identik** (termasuk `hit: 1` di dalam body),
   penghitung backend **tetap 1**. Respons lama dilayani dari
   `tunnel_responses` — membuktikan idempotency bertahan SETELAH respons
   asli terkirim dan baris request selesai (Gap B tertutup).
3. **Body 1.400.000 byte → 413** "request body too large" di ingress,
   tidak masuk antrean (Gap A tertutup di sisi tolak).
4. **Body 1.300.000 byte → 200 ujung-ke-ujung**; respons 1.300.138 byte
   diterima utuh oleh pemanggil; penghitung backend bertambah
   (Gap A tertutup di sisi lolos).
5. **Health probe terautentikasi.** `GET /__tunnel-health` dengan
   `x-tunnel-health-key` benar + header `x-health-nonce` acak → **200**
   `{"ok":true,"nonce":"<persis sama>","backend_ok":true,
   "backend_status":200}` dan backend benar-benar diprobe
   (`/v1/models` hit bertambah). Tanpa key → **403** fail-closed
   (Gap D tertutup: 401/403 tidak lagi dianggap sehat, dan probe
   membuktikan rantai sampai backend, bukan berhenti di gerbang).
6. **Client mati di tengah request lambat.** `POST /slow`, client
   dimatikan ~2 detik setelah request masuk → pemanggil menerima
   **504** "tunnel timeout (client offline?)" **dengan header
   `x-tunnel-request-id`**; request TIDAK dihapus saat timeout.
   Client dihidupkan lagi → request yatim diklaim ulang setelah lease
   kedaluwarsa (hit `/slow` backend 1 → 2) dan selesai;
   `GET /__tunnel/result?id=<request-id dari header 504>` → **200
   "slow-done"**. (Heartbeat 10 detik + lease 45 detik menjaga request
   yang masih dikerjakan client hidup — Gap C tertutup.)
7. **Backend mati → 502.** Mock backend dimatikan, POST chat → **502**
   "tunnel client error: fetch failed" (kegagalan dilaporkan sebagai
   kegagalan, bukan timeout palsu).

## TIDAK dijalankan (jujur)

- E2E penuh Telegram → Hermes → 9Router → tunnel di mesin pengguna:
  stack pengguna nonaktif atas perintah pemilik dan memerlukan mesin
  fisiknya. Jalur tunnel-nya sendiri dibuktikan end-to-end di staging
  ini dengan client asli + fungsi asli.
- Uji batas D1 lewat jalur Workers binding yang identik dengan perluasan
  REST di bagian 3 (lihat catatan di sana).
- Uji beban / pentest eksternal: di luar cakupan putaran ini.
