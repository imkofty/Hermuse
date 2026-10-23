# Panduan Putaran Kredensial

Bila perlu putar: sesuatu secret mungkin telah bocor (tidak sengaja dikongsi,
ter-commit ke repo, terlihat pada skrin), seseorang yang mempunyai akses
sepatutnya sudah tiada, atau sekadar berjadual. Putaran itu murah — lakukannya
sahaja daripada diperdebatkan.

*English version: [key-rotation.md](key-rotation.md) · Versi Bahasa Indonesia: [key-rotation.id.md](key-rotation.id.md) · Tiếng Việt: [key-rotation.vi.md](key-rotation.vi.md) · हिन्दी: [key-rotation.hi.md](key-rotation.hi.md) · 日本語: [key-rotation.ja.md](key-rotation.ja.md)*

## Senarai secret

| Secret | Tersimpan di | Digunakan oleh |
|---|---|---|
| Tunnel key | `~/.tunnel-key` (600) | `tunnel-client.mjs` ↔ Pages Functions (secret `TUNNEL_KEY`) |
| Kata laluan dashboard 9Router | `.dashboard-pw` di root repo (600) | `start-9router.sh` → 9Router |
| Token bot Telegram | `.env` di root repo (600) | Telegram gateway |
| Token API Cloudflare | **tiada di mana-mana — transient sahaja** | `wrangler` semasa setup; tidak pernah disimpan |

Semuanya di-gitignore. Sahkan sebelum setiap commit:
`git status --porcelain` tidak boleh memaparkan mereka.

## Peraturan 0 — backup sebelum putaran

```bash
mkdir -p ~/.hermuse-secret-backup && chmod 700 ~/.hermuse-secret-backup
BK=~/.hermuse-secret-backup/$(date -u +%F)
mkdir -p "$BK"
cp -p ~/.tunnel-key .env .dashboard-pw "$BK/" 2>/dev/null
chmod 600 "$BK"/*
```

Jika ada yang tidak kena, restore daripada `$BK` kemudian ulangi langkah
restart yang sepadan di bawah.

## 1. Putaran tunnel key (`TUNNEL_KEY`)

Key mesti sama di **dua** tempat: `~/.tunnel-key` tempatan dan secret
`TUNNEL_KEY` di projek Pages. Tidak sama = client dapat HTTP 403 pada setiap
poll (ia retry dengan backoff, jadi betulkan segera, tidak perlu panik).

```bash
# 1. Jana dan simpan key baharu secara tempatan
openssl rand -hex 32 > ~/.tunnel-key && chmod 600 ~/.tunnel-key

# 2. Cari nama projek Pages (daripada URL tunnel atau wrangler.toml)
PROJECT="$(basename "$(tr -d '[:space:]' < .tunnel-url)" .pages.dev)"
echo "project: $PROJECT"

# 3. Push key baharu sebagai Pages secret (perlu wrangler login atau CLOUDFLARE_API_TOKEN)
printf '%s' "$(cat ~/.tunnel-key)" | wrangler pages secret put TUNNEL_KEY --project-name="$PROJECT"

# 4. Restart tunnel client supaya memakai key baharu
bash restart-tunnel.sh
```

**Pengesahan:**

```bash
sleep 10
curl -s -o /dev/null -w '%{http_code}\n' --max-time 10 "$(cat .tunnel-url)"
# jangkaan: 200 atau 307 (307 = redirect ke log masuk dashboard, normal)
bash scripts/doctor.sh   # jangkaan: 0 FAIL
```

Buka URL tunnel awam dalam pelayar — dashboard 9Router sepatutnya terpapar.

## 2. Putaran kata laluan dashboard 9Router

```bash
# 1. Jana dan simpan kata laluan baharu
openssl rand -base64 24 | tr -d '\n' > .dashboard-pw && chmod 600 .dashboard-pw

# 2. Restart 9Router supaya memakai kata laluan baharu
bash restart-9router.sh
```

**Pengesahan:**

```bash
sleep 8
curl -s -o /dev/null -w '%{http_code}\n' --max-time 10 http://127.0.0.1:20128/dashboard
# jangkaan: 200 atau 307
```

Kemudian log masuk di URL tunnel awam dengan kata laluan baharu
(`cat .dashboard-pw` untuk memaparkannya bila perlu — jangan sekali-kali
paste ke chat).

## 3. Putaran token bot Telegram

```bash
# 1. Di Telegram, buka @BotFather → /revoke → pilih bot anda → salin token BAHARU.
# 2. Backup dan kemas kini .env (tukar hanya nilai token):
cp -p .env .env.bak && chmod 600 .env.bak
# edit .env dan set TELEGRAM_BOT_TOKEN=<token-baharu>, atau jalankan:
python3 - <<'EOF'
import re
tok = input("paste token bot baharu: ").strip()
p = ".env"
s = open(p).read()
s2 = re.sub(r"^TELEGRAM_BOT_TOKEN=.*$", "TELEGRAM_BOT_TOKEN=" + tok, s, flags=re.M)
open(p, "w").write(s2)
print("updated" if s2 != s else "TIADA PERUBAHAN — semak nama key dalam .env")
EOF
chmod 600 .env

# 3. Restart gateway (peraturan PID exact: kill hanya bila tepat 1 calon)
PID=$(pgrep -f "[g]ateway.*run")
[ "$(printf '%s' "$PID" | wc -l)" = "1" ] && kill "$PID" || echo "tiada tepat 1 PID gateway — semak manual"
sleep 3
bash start-gateway.sh
```

**Pengesahan:** hantar `/start` kepada bot anda di Telegram → ia membalas.
(Jika senyap, punca lazim ialah allowlist: ID numerik anda mesti ada dalam
`TELEGRAM_ALLOWED_USERS` di `.env`.)

## Pemeriksaan akhir

```bash
bash scripts/doctor.sh   # jangkaan: doctor: N ok, 0 FAIL, ...
```

## Rollback

```bash
BK=~/.hermuse-secret-backup/<tarikh>   # tarikh yang anda guna dalam Peraturan 0
cp -p "$BK"/.tunnel-key ~/.
cp -p "$BK"/.env "$BK"/.dashboard-pw .
chmod 600 ~/.tunnel-key .env .dashboard-pw
# kemudian ulangi separuh *remote* yang telah anda ubah:
#  - tunnel key: ulangi langkah 3 bahagian 1 dengan key yang di-restore, kemudian restart-tunnel.sh
#  - kata laluan dashboard: bash restart-9router.sh
#  - token bot: /revoke di @BotFather TIDAK boleh dibatalkan — token lama mati
#    selama-lamanya. Kekalkan yang baharu.
```

Nota: token bot Telegram yang telah di-revoke tidak boleh dikembalikan —
rollback hanya terpakai untuk tunnel key dan kata laluan dashboard.
