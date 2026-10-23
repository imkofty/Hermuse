# Panduan Rotasi Kredensial

Kapan harus rotasi: sebuah secret kemungkinan bocor (tidak sengaja dibagikan,
ter-commit ke repo, terlihat di layar), seseorang yang punya akses seharusnya
sudah tidak punya, atau sekadar terjadwal. Rotasi itu murah — lakukan saja
daripada diperdebatkan.

*English version: [key-rotation.md](key-rotation.md) · Versi Bahasa Malaysia: [key-rotation.ms.md](key-rotation.ms.md) · Tiếng Việt: [key-rotation.vi.md](key-rotation.vi.md) · हिन्दी: [key-rotation.hi.md](key-rotation.hi.md) · 日本語: [key-rotation.ja.md](key-rotation.ja.md)*

## Daftar secret-nya

| Secret | Tersimpan di | Dipakai oleh |
|---|---|---|
| Tunnel key | `~/.tunnel-key` (600) | `tunnel-client.mjs` ↔ Pages Functions (secret `TUNNEL_KEY`) |
| Password dashboard 9Router | `.dashboard-pw` di root repo (600) | `start-9router.sh` → 9Router |
| Token bot Telegram | `.env` di root repo (600) | Telegram gateway |
| Token API Cloudflare | **tidak di mana-mana — transient saja** | `wrangler` saat setup; tidak pernah disimpan |

Semuanya di-gitignore. Verifikasi sebelum setiap commit:
`git status --porcelain` tidak boleh menampilkan mereka.

## Aturan 0 — backup sebelum rotasi

```bash
mkdir -p ~/.hermuse-secret-backup && chmod 700 ~/.hermuse-secret-backup
BK=~/.hermuse-secret-backup/$(date -u +%F)
mkdir -p "$BK"
cp -p ~/.tunnel-key .env .dashboard-pw "$BK/" 2>/dev/null
chmod 600 "$BK"/*
```

Kalau ada yang salah, restore dari `$BK` lalu ulangi langkah restart yang
sesuai di bawah.

## 1. Rotasi tunnel key (`TUNNEL_KEY`)

Key harus sama di **dua** tempat: `~/.tunnel-key` lokal dan secret
`TUNNEL_KEY` di project Pages. Tidak sama = client dapat HTTP 403 di setiap
poll (ia retry dengan backoff, jadi perbaiki segera, tidak perlu panik).

```bash
# 1. Generate dan simpan key baru secara lokal
openssl rand -hex 32 > ~/.tunnel-key && chmod 600 ~/.tunnel-key

# 2. Cari nama Pages project (dari URL tunnel atau wrangler.toml)
PROJECT="$(basename "$(tr -d '[:space:]' < .tunnel-url)" .pages.dev)"
echo "project: $PROJECT"

# 3. Push key baru sebagai Pages secret (butuh wrangler login atau CLOUDFLARE_API_TOKEN)
printf '%s' "$(cat ~/.tunnel-key)" | wrangler pages secret put TUNNEL_KEY --project-name="$PROJECT"

# 4. Restart tunnel client agar memakai key baru
bash restart-tunnel.sh
```

**Verifikasi:**

```bash
sleep 10
curl -s -o /dev/null -w '%{http_code}\n' --max-time 10 "$(cat .tunnel-url)"
# harapan: 200 atau 307 (307 = redirect ke login dashboard, normal)
bash scripts/doctor.sh   # harapan: 0 FAIL
```

Buka URL tunnel publik di browser — dashboard 9Router harus tampil.

## 2. Rotasi password dashboard 9Router

```bash
# 1. Generate dan simpan password baru
openssl rand -base64 24 | tr -d '\n' > .dashboard-pw && chmod 600 .dashboard-pw

# 2. Restart 9Router agar memakai password baru
bash restart-9router.sh
```

**Verifikasi:**

```bash
sleep 8
curl -s -o /dev/null -w '%{http_code}\n' --max-time 10 http://127.0.0.1:20128/dashboard
# harapan: 200 atau 307
```

Lalu login di URL tunnel publik dengan password baru
(`cat .dashboard-pw` untuk menampilkannya saat dibutuhkan — jangan pernah
paste ke chat).

## 3. Rotasi token bot Telegram

```bash
# 1. Di Telegram, buka @BotFather → /revoke → pilih bot kamu → salin token BARU.
# 2. Backup dan update .env (ganti hanya nilai tokennya):
cp -p .env .env.bak && chmod 600 .env.bak
# edit .env dan set TELEGRAM_BOT_TOKEN=<token-baru>, atau jalankan:
python3 - <<'EOF'
import re
tok = input("paste token bot baru: ").strip()
p = ".env"
s = open(p).read()
s2 = re.sub(r"^TELEGRAM_BOT_TOKEN=.*$", "TELEGRAM_BOT_TOKEN=" + tok, s, flags=re.M)
open(p, "w").write(s2)
print("updated" if s2 != s else "TIDAK BERUBAH — cek nama key di .env")
EOF
chmod 600 .env

# 3. Restart gateway (aturan PID exact: kill hanya kalau tepat 1 kandidat)
PID=$(pgrep -f "[g]ateway.*run")
[ "$(printf '%s' "$PID" | wc -l)" = "1" ] && kill "$PID" || echo "tidak ada tepat 1 PID gateway — cek manual"
sleep 3
bash start-gateway.sh
```

**Verifikasi:** kirim `/start` ke bot kamu di Telegram → ia membalas. (Kalau
diam, penyebab umum adalah allowlist: numeric ID kamu harus ada di
`TELEGRAM_ALLOWED_USERS` di `.env`.)

## Pemeriksaan akhir

```bash
bash scripts/doctor.sh   # harapan: doctor: N ok, 0 FAIL, ...
```

## Rollback

```bash
BK=~/.hermuse-secret-backup/<tanggal>   # tanggal yang kamu pakai di Aturan 0
cp -p "$BK"/.tunnel-key ~/.
cp -p "$BK"/.env "$BK"/.dashboard-pw .
chmod 600 ~/.tunnel-key .env .dashboard-pw
# lalu ulangi separuh *remote* yang sudah kamu ubah:
#  - tunnel key: ulangi langkah 3 bagian 1 dengan key yang di-restore, lalu restart-tunnel.sh
#  - password dashboard: bash restart-9router.sh
#  - token bot: /revoke di @BotFather TIDAK bisa dibatalkan — token lama mati
#    selamanya. Pertahankan yang baru.
```

Catatan: token bot Telegram yang sudah di-revoke tidak bisa dikembalikan —
rollback hanya berlaku untuk tunnel key dan password dashboard.
