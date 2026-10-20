# Catatan Validasi — Putaran 6: Streaming Ujung-ke-Ujung + Bukti Hidup Telegram (2026-10-21)

Bukti terverifikasi untuk perbaikan putaran 6 di branch `release/score-100`
(commit `9aba137`). Audit putaran 5 memberi skor **97/100** (+3): ketiga
perbaikan putaran 4 dinyatakan tertutup. Sisa 3 poin menurut plugin:

1. **P1 — streaming belum ujung-ke-ujung (1 poin)**: client punya dua
   deadline yang bertabrakan — `LOCAL_TIMEOUT_MS=30000` membatalkan
   sinyal fetch padahal `RESPONSE_DEADLINE_MS=120000` mengatur body;
   client menumpuk seluruh body sebelum merespons (bukan relay
   per-chunk); ingress `WAIT_MS_DEFAULT=40000` menyerah 504.
   Acceptance: tes SSE berumur >30–40 detik pada konfigurasi DEFAULT
   tanpa mengubah setelan.
2. **P0 rilis (2 poin)**: balasan LLM Telegram belum diterima pemilik.
   Acceptance: ≥1 giliran LLM nyata dari pesan Telegram masuk sampai
   balasan BENAR-BENAR diterima di Telegram.
3. **Catatan rollout (tanpa poin)**: D1 asli sudah skema 004 tapi belum
   punya tabel `schema_migrations` — runner migrasi baru belum terbukti
   di database itu.

Semua langkah di bawah BENAR-BENAR dijalankan; yang tidak dijalankan
ditulis apa adanya di bagian akhir.

## 1. Verifikasi lokal

- `node --test tests/*.test.mjs`: **38/38 lulus** (36 putaran 5 + 2
  baru: stream SSE 45 detik pada konfigurasi default; assert
  `WAIT_MS_DEFAULT` ingress = 120000).
- **Bukti regresi**: tes stream baru dijalankan terhadap worktree kode
  lama (`ecda098`) dan **GAGAL tepat di 30.242 ms** — persis deadline
  lama yang ditunjuk plugin. Di kode baru tes yang sama lulus.
- `bash tests/migration-upgrade.test.sh`: OK. `bash
  tests/setup-tunnel.test.sh`: OK. `bash tests/watchdog.test.sh`: OK.
  `bash scripts/check-i18n.sh`: **76 kunci** bersih (en/id/ms) — putaran
  ini tidak menambah kunci.
- CI `tunnel-tests` untuk `9aba137`: **SUCCESS** (terverifikasi dari
  status run GitHub).

## 2. Poin 1 (P1) — Samakan deadline streaming (`9aba137`)

- Client kini memakai `AbortController` + timer header yang
  **di-clearTimeout begitu fetch resolve**: `TUNNEL_LOCAL_TIMEOUT_MS`
  sekarang HANYA membatasi penantian HEADER pertama. Body sesudahnya
  hanya diatur deadline menyeluruh `TUNNEL_RESPONSE_DEADLINE_MS`
  (default 120000) yang sudah ada sejak putaran 5 — tidak ada lagi dua
  deadline yang bertabrakan di tengah stream.
- `WAIT_MS_DEFAULT` di ingress Pages: 40000 → **120000** (override env
  `INGRESS_WAIT_MS` tetap tersedia). Komentar di
  `wrangler.toml.example` disesuaikan.
- **Uji stream panjang LIVE — LOLOS (acceptance plugin terpenuhi):**
  mock stream lambat (10 chunk × 5 detik, port lokal terpisah) di
  belakang client dengan setelan DEFAULT, ditembak lewat ingress
  PUBLIK: **HTTP 200, total 55,1 detik, 10/10 chunk diterima +
  `STREAM_END_MARKER` + `[DONE]`**. Stream berumur >40 detik kini
  selamat ujung-ke-ujung tanpa mengubah setelan apa pun.

## 3. Catatan rollout — Runner migrasi dijalankan ke D1 ASLI

- Langkah runner migrasi dieksekusi ke **database D1 produksi**
  (`tunnel-9router`) via helper REST (kredensial lewat jalur aman
  konektor, tidak pernah masuk env/argumen/log).
- Hasil: `schema.sql` 0 gagal; ledger **`schema_migrations` TERBENTUK**
  dan mencatat versi **001–004** (toleransi duplikat per statement
  bekerja pada database warisan pra-ledger: 2+1+1+4 statement
  terverifikasi/ditoleransi sesuai isi tiap migrasi).
- Preflight cermin `check-tunnel-schema.sh` terhadap D1 asli: **SEMUA
  OK** — semua tabel ada, kolom 001–004 lengkap, kedua index gabungan
  tepat `idempotency_key,idem_principal` (via pragma_index_info),
  ledger ada.
- Data utuh: `tunnel_requests` 0 baris, `tunnel_responses` 7 baris —
  tidak ada yang hilang atau berubah.

## 4. Staging terisolasi — deployment + E2E putaran 6

Lingkungan sama dengan putaran 4–5 (9Router staging `127.0.0.1:20228`,
combo `staging-utama`, provider keyless Pollinations; Hermes staging
home terisolasi; stack pribadi pemilik tetap MATI — terverifikasi:
tidak ada listener di port 20128).

- Bundle fungsi Pages direkonstruksi dari `9aba137` via
  `build-bundle.py` yang sama (29.498 byte) dan ter-deploy ke project
  `hermuse-tunnel-validation` sebagai **deployment `639397bf`**
  (menggantikan `d23a92a2` putaran 5).
- **E2E tunnel putaran 6: SEMUA LOLOS** — (a) chat biasa → 200, hit
  backend 1; (b) replay identik → 200 byte-identik, hit tetap 1;
  (c) Authorization berbeda → diproses baru, hit 2; (d) fingerprint
  berbeda → **409**; (e1) body 1,4 MB → **413**; (e2) health probe
  ber-key + nonce → 200 `backend_ok: true`; (e3) tanpa key → **403**.
  Cek anon terpisah: key + body sama tanpa Authorization → hit 3 lalu
  **4** (diproses segar, tidak di-replay — perilaku putaran 5 utuh).
- Rantai ke backend nyata terverifikasi lewat ingress publik: GET
  `/v1/models` mengembalikan model `staging-utama`.

## 5. Gap F — Uji hidup Telegram putaran 6 (2026-10-21 06:32–06:34 WIB) — LOLOS PENUH

Konteks jujur: mesin virtual ini sempat di-recycle platform ±06:23 WIB
(semua proses mati SIGKILL, pola rutin mesin ini). Stack staging
dihidupkan ulang dari nol dan diverifikasi per mata rantai SEBELUM uji
(9Router staging 200; client tunnel polling; gateway PID 2327 adapter
Telegram "Connected (polling mode)" + perintah bot teregistrasi;
ingress publik → model terbaca).

Lalu pemilik mengirim SATU pesan persis `Halo, balas dengan kata
STAGING_RANTAI_OK` ke bot (tanpa `/new` — sesi sehat
`20261021_050331_a002b816`):

1. **06:32:56** — pesan tercatat inbound di log gateway (platform
   telegram, chat pemilik).
2. **06:33:30** — giliran berjalan: model `staging-utama`, **1
   panggilan API** lewat rantai penuh (Telegram → gateway → tunnel
   publik → client → 9Router staging → Pollinations).
3. **06:33:44** — giliran selesai `finish_reason=stop`,
   `response_len=17` (persis `STAGING_RANTAI_OK`); gateway mencatat
   `Sending response (17 chars)`.
4. **Terkirim beneran**: buku kas pengiriman Hermes
   (`delivery_obligations`) mencatat baris isi `STAGING_RANTAI_OK`
   dengan status **`delivered`**, `attempts=0`, `last_error=None` —
   tanpa satu pun `send_path_degraded`. Pemilik mengonfirmasi
   penerimaan di aplikasi Telegram-nya (screenshot 06:33).

**Acceptance P0 plugin terpenuhi**: ≥1 giliran LLM nyata dari pesan
Telegram masuk sampai balasan benar-benar diterima di Telegram —
dibuktikan tiga lapis (log gateway, ledger pengiriman, konfirmasi
pemilik). Mata rantai terakhir yang di putaran 5 terhalang degradasi
adapter sandbox kali ini bersih pada percobaan pertama.

## TIDAK dijalankan (jujur)

- Uji beban dan pentest eksternal: di luar cakupan, tetap NOT RUN
  (sama seperti putaran 2–5).
- Uji hidup di mesin berjaringan normal di luar sandbox: tidak
  dijalankan — tetapi acceptance-nya (balasan diterima di Telegram)
  kali ini sudah tercapai dari dalam sandbox, lihat bagian 5.
- Stack pribadi pemilik tetap MATI selama seluruh putaran 6
  (terverifikasi berulang: tidak ada listener di port 20128).
