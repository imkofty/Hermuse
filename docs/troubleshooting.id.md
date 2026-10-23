# Troubleshooting

**Mulai dari sini:** `bash scripts/doctor.sh`. Setiap baris `[FAIL]`
diakhiri `→ fix: <perintah persis>` — jalankan itu dulu; halaman ini
menjelaskan alasan di balik perbaikan yang umum. Setiap entri berbentuk
Gejala → Diagnosis → Perbaikan, dan semua perintah bisa langsung
copy-paste.

Entri di sini hanya dari kegagalan yang benar-benar pernah terjadi —
tidak ada yang dikarang.

---

### 1. URL tunnel publik mengembalikan 502 / 503 / 504

Infrastruktur tunnel menjawab, tapi jalur terusannya ke mesin kamu gagal.

**Diagnosis:**
```bash
curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$(cat .tunnel-url)"
curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:20128/dashboard
```

**Perbaikan:**
- curl lokal mengembalikan `000` (tidak ada yang listen) → 9Router mati:
  `bash restart-9router.sh`
- curl lokal mengembalikan `200`/`307` (9Router sehat) → yang sakit tunnel
  client-nya: `bash restart-tunnel.sh`

---

### 2. Bot diam, tapi proses gateway masih hidup

Polling Telegram bisa macet sementara prosesnya masih ada — "proses hidup"
bukan berarti "gateway sehat".

**Diagnosis:**
```bash
bash scripts/doctor.sh   # assertion 7 melaporkan umur heartbeat / pid mismatch
# atau manual:
cat "$HERMES_HOME/state/gateway.heartbeat"
```

**Perbaikan:**
```bash
DRY_RUN=1 bash gateway-watch.sh   # menampilkan yang akan dilakukan, tanpa mengubah apa pun
bash gateway-watch.sh             # restart gateway kalau heartbeat basi
```

---

### 3. Dashboard redirect ke login terus-menerus

File password dashboard hilang atau tidak cocok dengan yang kamu ketik.

**Diagnosis:**
```bash
ls -l .dashboard-pw   # harus ada, 600
```

**Perbaikan:** tulis password yang benar ke `.dashboard-pw`
(`chmod 600 .dashboard-pw`), lalu `bash restart-9router.sh` agar dashboard
membaca ulang.

---

### 4. Bot tidak membalas user tertentu

Gateway bersifat default-deny: hanya ID Telegram numerik yang ada di
`TELEGRAM_ALLOWED_USERS` yang dibalas. "Bot diam untuk satu orang" hampir
pasti ini penyebabnya.

**Diagnosis:** cocokkan ID numerik user tersebut dengan
`TELEGRAM_ALLOWED_USERS` di file env gateway (`.hermes/.env`).

**Perbaikan:** tambahkan ID numeriknya ke `TELEGRAM_ALLOWED_USERS`, lalu
`bash start-gateway.sh` untuk restart gateway dengan allowlist baru.

---

### 5. `hermes: command not found` tepat setelah install.sh

`install.sh` menambahkan `~/.local/bin` ke `~/.bashrc`, tapi shell
non-login tidak me-load-nya.

**Diagnosis:**
```bash
command -v hermes      # kosong
ls ~/.local/bin/hermes # ada
```

**Perbaikan:**
```bash
export PATH="$HOME/.local/bin:$PATH"
```

---

### 6. `hermes doctor` melaporkan kegagalan

**Diagnosis:** baca output-nya. Kasus yang umum terlihat adalah auth
provider (kredensial model kedaluwarsa/dicabut).

**Perbaikan:** ulangi login model: `hermes setup --portal`

---

### 7. Auth wrangler gagal saat setup tunnel

**Diagnosis:** `wrangler whoami` — kalau error, berarti tidak ada auth
yang valid.

**Perbaikan:** pilih satu jalur auth:
- `wrangler login` (OAuth via browser), atau
- `CLOUDFLARE_API_TOKEN` sebagai env var sementara.

Jangan taruh token di `wrangler.toml`.

---

### 8. Port 20128 sudah dipakai

9Router basi (tidak tersupervisi) menguasai port, sehingga instance yang
tersupervisi tidak bisa bind.

**Diagnosis:**
```bash
curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:20128/dashboard
```
Kalau ada yang menjawab tapi prosesnya bukan yang tersupervisi, berarti
basi.

**Perbaikan:** `bash restart-9router.sh` — menghentikan proses basi dengan
aturan exact-PID lalu menjalankan instance tersupervisi. Jangan pernah
`pkill -f 9router` (mengenai terlalu banyak, termasuk shell kamu sendiri).

---

### 9. doctor bilang gateway hilang/ambigu, padahal gateway-nya jalan

Launcher gateway di mesin kamu memakai bentuk argv yang tidak dicakup pola
`pgrep` doctor. Kasus yang pernah terjadi: launcher venv hasil provisioning
melewatkan `sys.argv = ['-c', 'gateway', 'run']` — dipisah koma di dalam
string `-c`, bukan kata bersebelahan — sehingga pola awal yang hanya
mencakup kata bersebelahan gagal menemukannya.

**Diagnosis:**
```bash
pgrep -af "gateway" | head   # cari cmdline gateway yang asli
grep -n "gateway_pids" scripts/doctor.sh   # lihat pola yang dipakai doctor
```

**Perbaiki:** lebarkan kelas pemisah di `gateway_pids()` di
`scripts/doctor.sh` agar mencakup bentuk launcher kamu, lalu jalankan ulang
`bash scripts/doctor.test.sh` — semua test harus lolos sebelum commit.

---

*English version: [troubleshooting.md](troubleshooting.md) · Versi Bahasa Malaysia: [troubleshooting.ms.md](troubleshooting.ms.md) · Tiếng Việt: [troubleshooting.vi.md](troubleshooting.vi.md) · हिन्दी: [troubleshooting.hi.md](troubleshooting.hi.md) · 日本語: [troubleshooting.ja.md](troubleshooting.ja.md)*
