# Penyelesaian Masalah

**Mula di sini:** `bash scripts/doctor.sh`. Setiap baris `[FAIL]` berakhir
dengan `→ fix: <perintah tepat>` — jalankannya dahulu; halaman ini
menerangkan rasional di sebalik pembaikan yang lazim. Setiap entri berbentuk
Gejala → Diagnosis → Pembaikan, dan setiap perintah boleh copy-paste.

Entri hanya datang daripada kegagalan yang diperhatikan — tiada apa di sini
yang direka.

---

### 1. URL tunnel awam mengembalikan 502 / 503 / 504

Infrastruktur tunnel menjawab, tetapi kaki pemajuan ke mesin anda gagal.

**Diagnosis:**
```bash
curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$(cat .tunnel-url)"
curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:20128/dashboard
```

**Pembaikan:**
- Curl tempatan mengembalikan `000` (tiada yang mendengar) → 9Router down:
  `bash restart-9router.sh`
- Curl tempatan mengembalikan `200`/`307` (9Router sihat) → tunnel client
  yang bermasalah: `bash restart-tunnel.sh`

---

### 2. Bot senyap, tetapi proses gateway hidup

Polling Telegram boleh stall sedangkan proses masih wujud — "proses hidup"
bukan "gateway sihat".

**Diagnosis:**
```bash
bash scripts/doctor.sh   # assertion 7 melaporkan usia heartbeat / ketidakpadanan pid
# atau secara manual:
cat "$HERMES_HOME/state/gateway.heartbeat"
```

**Pembaikan:**
```bash
DRY_RUN=1 bash gateway-watch.sh   # menunjukkan apa yang akan dilakukan, tidak mengubah apa-apa
bash gateway-watch.sh             # memulakan semula gateway jika heartbeat basi
```

---

### 3. Papan pemuka redirect ke log masuk selama-lamanya

Fail kata laluan papan pemuka tiada atau tidak sepadan dengan apa yang anda
taip.

**Diagnosis:**
```bash
ls -l .dashboard-pw   # mesti wujud, 600
```

**Pembaikan:** tulis kata laluan yang betul ke dalam `.dashboard-pw`
(`chmod 600 .dashboard-pw`), kemudian `bash restart-9router.sh` supaya papan
pemuka mengambilnya.

---

### 4. Bot tidak membalas pengguna tertentu

Gateway adalah default-deny: hanya ID Telegram numerik dalam
`TELEGRAM_ALLOWED_USERS` mendapat balasan. "Bot senyap untuk seorang"
hampir selalunya ini.

**Diagnosis:** semak ID numerik pengguna dengan `TELEGRAM_ALLOWED_USERS`
dalam fail env gateway (`.hermes/.env`).

**Pembaikan:** tambah ID numerik kepada `TELEGRAM_ALLOWED_USERS`, kemudian
`bash start-gateway.sh` untuk memulakan semula gateway dengan senarai
dibenarkan yang baharu.

---

### 5. `hermes: command not found` sejurus selepas install.sh

`install.sh` menambah `~/.local/bin` kepada `~/.bashrc`, tetapi shell
bukan-log masuk tidak mewarisinya.

**Diagnosis:**
```bash
command -v hermes      # kosong
ls ~/.local/bin/hermes # wujud
```

**Pembaikan:**
```bash
export PATH="$HOME/.local/bin:$PATH"
```

---

### 6. `hermes doctor` melaporkan kegagalan

**Diagnosis:** baca outputnya. Kes yang lazim diperhatikan ialah auth
pembekal (kredensial model tamat/dibatalkan).

**Pembaikan:** jalankan semula log masuk model: `hermes setup --portal`

---

### 7. Auth wrangler gagal semasa persediaan tunnel

**Diagnosis:** `wrangler whoami` — jika ia ralat, tiada auth yang sah.

**Pembaikan:** pilih satu laluan auth:
- `wrangler login` (OAuth pelayar), atau
- `CLOUDFLARE_API_TOKEN` sebagai pemboleh ubah env transient.

Jangan sesekali letakkan token dalam `wrangler.toml`.

---

### 8. Port 20128 telah digunakan

9Router basi (tidak diselia) memiliki port tersebut, jadi yang diselia tidak
dapat bind.

**Diagnosis:**
```bash
curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:20128/dashboard
```
Jika sesuatu menjawab tetapi prosesnya bukan yang diselia, ia basi.

**Pembaikan:** `bash restart-9router.sh` — ia menghentikan proses basi
menggunakan peraturan PID tepat dan memulakan instance yang diselia. Jangan
sesekali `pkill -f 9router` (ia sepadan terlalu luas, termasuk shell anda
sendiri).

---

### 9. doctor menyatakan gateway tiada/kabur, tetapi ia sebenarnya berjalan

Pelancar gateway pada mesin anda menggunakan bentuk argv yang tidak diliputi
pola `pgrep` doctor. Kes diperhatikan: pelancar venv yang diperuntukkan
menghantar `sys.argv = ['-c', 'gateway', 'run']` — dipisahkan koma di dalam
rentetan `-c`, bukan perkataan bersebelahan — yang tidak dikesan pola asal
yang hanya bersebelahan.

**Diagnosis:**
```bash
pgrep -af "gateway" | head   # cari cmdline gateway yang sebenar
grep -n "gateway_pids" scripts/doctor.sh   # lihat pola yang digunakan doctor
```

**Pembaikan:** lebarkan kelas pemisah dalam `gateway_pids()` di
`scripts/doctor.sh` untuk meliputi bentuk pelancar anda, kemudian jalankan
semula `bash scripts/doctor.test.sh` — semua ujian mesti lulus sebelum
commit.

---

*English version: [troubleshooting.md](troubleshooting.md) · Versi Bahasa Indonesia: [troubleshooting.id.md](troubleshooting.id.md) · Tiếng Việt: [troubleshooting.vi.md](troubleshooting.vi.md) · हिन्दी: [troubleshooting.hi.md](troubleshooting.hi.md) · 日本語: [troubleshooting.ja.md](troubleshooting.ja.md)*
