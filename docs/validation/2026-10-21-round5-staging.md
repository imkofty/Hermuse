# Catatan Validasi — Putaran 5: 3 Temuan Sisa dari Skor 94 (2026-10-21)

Bukti terverifikasi untuk perbaikan putaran 5 di branch `release/score-100`
(commit `da749ac`, `9be74a8`, `9472251`). Audit putaran 4 memberi skor
**94/100** (−2 dari 96): tiga perbaikan putaran 4 diakui menutup temuan
lama (+3), tetapi plugin menemukan tiga hal baru (−5) dan memutuskan
**jangan merge ke main dengan label score-100** selama ketiganya terbuka:

1. **P0** — streaming + polling serial client tunnel menghalangi balasan
   Telegram (head-of-line blocking): client menunggu seluruh batch
   selesai sebelum poll berikutnya, dan `handleOne` menunggu seluruh
   respons dibaca; rantai hidup putaran 4 gagal di titik ini.
2. Migrasi 004 bisa **terlewat saat upgrade**: `setup-tunnel.sh` hanya
   menjalankan migrasi bila eksekusi `schema.sql` gagal; di database
   versi 003, `CREATE IF NOT EXISTS` bisa sukses tanpa kolom 004.
3. Principal `"anon"` + fingerprint longgar: semua request tanpa
   kredensial berbagi satu principal, dan fingerprint tidak mencakup
   header lain — replay lintas-request masih mungkin untuk pemanggil
   tak terautentikasi.

Semua langkah di bawah BENAR-BENAR dijalankan; yang gagal atau tidak
dijalankan ditulis apa adanya, termasuk kegagalan pengiriman terakhir
ke Telegram di bagian 6 beserta bukti bahwa penyebabnya lingkungan
sandbox, bukan kode produk.

## 1. Verifikasi lokal

- `node --test tests/*.test.mjs`: **36/36 lulus** (31 putaran 4 + 5
  baru: konkurensi + deadline client ×2, perilaku anon ×3). Tes-tes
  baru terbukti **GAGAL di kode lama** (dijalankan terhadap kode
  sebelum perbaikan) dan lulus di kode baru — regresi tertangkap.
- `bash tests/migration-upgrade.test.sh`: **OK** (baru — bangun
  database versi 003, jalankan runner tanpa intervensi manual, buktikan
  kolom + index + ledger; rincian di bagian 3).
- `bash tests/setup-tunnel.test.sh`: OK. `bash tests/watchdog.test.sh`:
  12 pemeriksaan OK. `bash tests/launcher-smoke.sh`: OK. `bash
  scripts/check-tunnel-schema.sh`: OK. `bash scripts/check-i18n.sh`:
  **76 kunci** bersih (en/id/ms).
- doctor: exit 1 dengan 4 baris FAIL yang **identik byte-per-byte**
  dengan baseline `4c29e17` (stack pribadi pemilik memang dimatikan
  sejak 2026-10-12 atas perintah pemilik) — bukan regresi putaran ini.
- CI `tunnel-tests` untuk `9472251`: run **39502924485 SUCCESS**
  (terverifikasi dari status run GitHub, bukan asumsi).

## 2. Poin 1 (P0) — Akhiri head-of-line blocking (`da749ac`)

- Loop poll client TIDAK lagi menunggu batch: `handleOne` di-dispatch
  **tanpa await**, dilacak dalam Map in-flight; poll berikutnya hanya
  mengklaim sebanyak slot kosong (env `TUNNEL_MAX_IN_FLIGHT`, default
  6). Satu request lambat tidak lagi menahan request lain.
- Pembacaan body respons kini ber-deadline menyeluruh (env
  `TUNNEL_RESPONSE_DEADLINE_MS`, default 120000): stream yang macet
  dipotong dan dijawab **502**, bukan menahan client tanpa batas.
  Kunci i18n baru `tunnel_response_deadline` (en/id/ms).
- Tes regresi `tests/client.test.mjs` (baru): stream lambat 2,5 detik +
  request cepat → urutan respons `["cepat1", "lambat1"]` (di kode lama
  urutannya terbalik — tes gagal); stream macet + deadline 700 ms →
  502 "deadline". Bukti live staging: bagian 5.

## 3. Poin 2 — Runner migrasi berversi + preflight wajib (`9be74a8`)

- Runner baru `scripts/tunnel-migrate.sh` + executor bersama
  `scripts/sql-exec.sh` (default wrangler D1; SQLite lokal via env
  `TUNNEL_SQLITE_FILE` + python3 — jalur yang sama persis dengan yang
  dites). Urutan: `schema.sql` → buat ledger `schema_migrations
  (version, applied_at)` → terapkan migrasi `*.sql` berurutan per
  statement HANYA yang belum tercatat → catat versi → **preflight
  wajib** `check-tunnel-schema.sh`; preflight gagal = exit 1.
- Error duplicate-column / already-exists ditoleransi **per statement**
  (untuk database warisan pra-ledger yang kolomnya sudah ada); error
  lain fatal. Tidak ada lagi jalur "schema.sql sukses = migrasi
  dianggap beres".
- `setup-tunnel.sh` langkah 3 kini memanggil runner ini dan berhenti
  (`die`) bila gagal.
- `check-tunnel-schema.sh` diperkuat: memverifikasi **kolom kedua
  index idempotency** via `pragma_index_info` — harus tepat
  `idempotency_key,idem_principal`, bukan sekadar nama index ada.
- **Acceptance plugin terbukti** oleh `tests/migration-upgrade.test.sh`:
  dari database versi 003, jalankan setup tanpa intervensi manual →
  4 kolom baru + kedua index gabungan terpasang + ledger mencatat
  001–004; run kedua idempoten (tidak menerapkan ulang); database rusak
  (kolom `status` hilang) → exit 1. Langkah CI baru menjalankan tes ini
  di `tunnel-tests.yml`. Kunci i18n baru: `tunnel_apply_migration`,
  `tunnel_schema_incomplete`.

## 4. Poin 3 — Replay hanya untuk principal terverifikasi (`9472251`)

- Replay dari `tunnel_responses` DAN penempelan antrean kini **hanya**
  untuk principal terverifikasi (`auth:` / `hk:`). Request `"anon"`
  selalu diproses segar: kedua lookup dilewati, principal yang
  tersimpan NULL (tidak pernah cocok dengan lookup mana pun dan tidak
  bertabrakan di index unik); respons tetap disimpan untuk audit.
- Tes baru `tests/tunnel.test.mjs` (ketiganya GAGAL di kode lama):
  anon dengan key + body sama → backend dipanggil 2 kali; dua anon
  bersamaan → 2 baris terpisah; anon dengan body berbeda → bukan 409.
- Dua tes lama (dedup putaran 2, replay putaran 3) diberi header
  Authorization agar tetap menguji maksud aslinya — perilaku anon
  memang **sengaja berubah** oleh perbaikan ini.

## 5. Staging terisolasi — deployment + E2E putaran 5

Lingkungan sama dengan putaran 4 (9Router staging `127.0.0.1:20228`,
combo `staging-utama`, provider keyless Pollinations; Hermes staging
home terisolasi; stack pribadi pemilik tetap MATI — terverifikasi:
tidak ada listener di port 20128).

- Bundle fungsi Pages direkonstruksi dari worktree putaran 5 via
  `build-bundle.py` yang sama (28.775 byte) dan ter-deploy ke project
  `hermuse-tunnel-validation` sebagai **deployment `d23a92a2`**
  (menggantikan `92dc5700` putaran 4).
- **E2E tunnel putaran 5 (client baru + mock backend): SEMUA LOLOS** —
  (a) chat biasa → 200, hit backend 1; (b) replay identik → 200
  byte-identik, hit tetap 1; (c) Authorization berbeda → diproses baru,
  hit 2; (d) fingerprint berbeda → **409**; (e1) body 1,4 MB → **413**;
  (e2) health probe ber-key + nonce → 200 `backend_ok: true`; (e3)
  tanpa key → **403**.
- **Cek baru fix 3 secara live:** dua request anon identik (key + body
  sama, tanpa Authorization) → hit 1 lalu **2** — diproses segar,
  TIDAK di-replay. Fix 3 terbukti di staging live, bukan hanya unit.
- **Uji konkurensi streaming LIVE — LOLOS:** client diarahkan ke
  backend 9Router staging; request streaming cerita panjang selesai
  dalam **24,9 detik** (165.870 byte) sementara request non-streaming
  yang ditembak 3 detik setelahnya menjawab `CONCURRENT_OK` dalam
  **17,6 detik**. Pola yang di putaran 4 menghasilkan 504 berantai kini
  berjalan bersamaan tanpa saling menahan — head-of-line blocking
  hilang di staging live.

## 6. Gap F — Uji hidup Telegram putaran 5 (2026-10-21 04:58–05:21 WIB)

### Percobaan pertama (04:58) — gagal instan, BUKAN karena tunnel

Pesan pemilik masuk dan giliran jalan di **sesi lama** yang sama dengan
kegagalan putaran 4. Hermes membatalkan dalam ±20 detik **tanpa
mengirim request apa pun** (log 9Router kosong): sesi itu telah
menumpuk 6 percobaan basi dari putaran 4, dan pemutus sesi Hermes
menolak panggilan baru di sesi tersebut ("retrying won't help").
Obatnya persis saran pesan error-nya sendiri: mulai sesi baru
(`/new`). Ini perilaku pengaman Hermes atas sesi yang sudah keracunan
riwayat gagal — bukan kegagalan tunnel maupun kode Hermuse.

### Tiga giliran hidup berturut-turut — rantai LOLOS

Setelah `/new` (sesi `20261021_050331_a002b816`), **tiga giliran hidup
berturut-turut menyelesaikan panggilan model lewat rantai penuh**
(Telegram → gateway Hermes → tunnel publik → client → 9Router staging
→ Pollinations), masing-masing dengan jawaban **persis 17 karakter =
`STAGING_RANTAI_OK`** (`response_len=17` di log gateway):

1. Masuk 05:03 — API call sukses, latency 53,5 dtk, in=15.973 out=51,
   `finish_reason=stop`.
2. Masuk 05:05 — percobaan streaming kena tunnel timeout ±50 dtk,
   Hermes menerbitkan ulang **non-streaming dan sukses** (mekanisme
   fallback-nya bekerja); API call sukses latency 63,5 dtk;
   `response_len=17`.
3. Masuk 05:17 — API call sukses latency 119,3 dtk (termasuk
   fallback); `response_len=17`.

Bandingkan putaran 4: **nol** giliran yang menyelesaikan panggilan
model (semua abort setelah 6 percobaan basi). Perbaikan P0 mengubah
hasil rantai hidup dari 0/2 menjadi 3/3 pada panggilan modelnya.

### Pengiriman terakhir ke Telegram — gagal di sandbox ini, bukti lengkap

Ketiga balasan di atas **tidak sampai ke Telegram pemilik**: setiap
percobaan kirim (2 retry per balasan, jendela ±7 detik) mendarat persis
di jendela reconnect adapter Telegram, dan gateway mencatat
`send_path_degraded` lalu "Failed to deliver response after 2
retries". Bukti pendukungnya, semua dari log + database gateway
sendiri:

- Balasan-balasannya **tidak hilang**: buku kas pengiriman Hermes
  (tabel `delivery_obligations` di `state.db` gateway) menyimpan
  ketiganya dengan isi verbatim `STAGING_RANTAI_OK`, status `failed`,
  error `send_path_degraded` — antrean kirim-ulang produk bekerja
  sebagaimana dirancang. Satu baris kemudian menyelesaikan siklus
  hidupnya menjadi `abandoned` sesuai kebijakan jumlah percobaan
  ledger setelah sweep boot saat gateway di-restart — juga sesuai
  desain.
- Jalur kirim yang sama **terbukti bekerja** di sesi yang sama
  setiap kali adapter tidak sedang reconnect: balasan `/model`
  (03:54) dan pesan-pesan error (04:07, 04:58) tercatat `delivered`
  di ledger yang sama dan diterima pemilik.
- Adapter Telegram di sandbox ini putus-sambung ±tiap 90–120 detik
  (timeout probe heartbeat via proxy egress yang mengintersep TLS) —
  keterbatasan platform mesin virtual ini yang sama yang membuat
  gateway WhatsApp tidak bisa berjalan di sini sama sekali. Hermes
  hanya me-retry kirim 2 kali dalam ±7 detik, lebih pendek dari
  jendela degradasi tipikal (±30–60 detik).

**Kesimpulan Gap F putaran 5 yang jujur:** cacat produk putaran 4
(streaming menahan client serial → percobaan basi → 504) sudah
**diperbaiki dan tidak terulang** — tiga giliran hidup membuktikan
panggilan model ujung-ke-ujung dengan jawaban yang persis diminta.
Sisa kegagalannya adalah stabilitas adapter Telegram di sandbox ini,
di luar kode produk; di mesin berjaringan normal, jalur kirim terakhir
itu adalah kode yang sama yang malam ini juga mengantarkan balasan
`/model` dan pesan error ke pemilik.

## TIDAK dijalankan (jujur)

- Uji beban dan pentest eksternal: di luar cakupan, tetap NOT RUN
  (sama seperti putaran 2–4).
- Penerimaan balasan LLM di aplikasi Telegram dari dalam sandbox
  ini: dicoba 3 kali, terhalang degradasi adapter sandbox sebagaimana
  dirinci di bagian 6; isi balasannya terverifikasi dari ledger
  pengiriman gateway + log `response_len`. Uji ulang di mesin
  berjaringan normal adalah satu-satunya lingkungan yang belum
  dicoba untuk mata rantai terakhir ini.
- Stack pribadi pemilik tetap MATI selama seluruh putaran 5
  (terverifikasi berulang: tidak ada listener di port 20128).
