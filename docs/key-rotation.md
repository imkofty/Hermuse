# Credential Rotation Guide

When to rotate: a secret may have leaked (shared by accident, committed to a
repo, seen on screen), someone with access should no longer have it, or simply
on a schedule. Rotation is cheap — do it rather than debate it.

*Versi Bahasa Indonesia: [key-rotation.id.md](key-rotation.id.md) · Versi Bahasa Malaysia: [key-rotation.ms.md](key-rotation.ms.md) · Tiếng Việt: [key-rotation.vi.md](key-rotation.vi.md) · हिन्दी: [key-rotation.hi.md](key-rotation.hi.md) · 日本語: [key-rotation.ja.md](key-rotation.ja.md)*

## What the secrets are

| Secret | Lives in | Used by |
|---|---|---|
| Tunnel key | `~/.tunnel-key` (600) | `tunnel-client.mjs` ↔ Pages Functions (`TUNNEL_KEY` secret) |
| 9Router dashboard password | `.dashboard-pw` in repo root (600) | `start-9router.sh` → 9Router |
| Telegram bot token | `.env` in repo root (600) | Telegram gateway |
| Cloudflare API token | **nowhere — transient only** | `wrangler` during setup; never stored |

All of the above are gitignored. Verify before every commit:
`git status --porcelain` must not list them.

## Rule 0 — back up before rotating

```bash
mkdir -p ~/.hermuse-secret-backup && chmod 700 ~/.hermuse-secret-backup
BK=~/.hermuse-secret-backup/$(date -u +%F)
mkdir -p "$BK"
cp -p ~/.tunnel-key .env .dashboard-pw "$BK/" 2>/dev/null
chmod 600 "$BK"/*
```

If anything goes wrong, restore from `$BK` and repeat the matching restart
step below.

## 1. Rotate the tunnel key (`TUNNEL_KEY`)

The key must match in **two** places: your local `~/.tunnel-key` and the
Pages project's `TUNNEL_KEY` secret. Mismatch = the client gets HTTP 403 on
every poll (it retries with backoff, so fix it promptly rather than panic).

```bash
# 1. Generate and save the new key locally
openssl rand -hex 32 > ~/.tunnel-key && chmod 600 ~/.tunnel-key

# 2. Find your Pages project name (from the tunnel URL or wrangler.toml)
PROJECT="$(basename "$(tr -d '[:space:]' < .tunnel-url)" .pages.dev)"
echo "project: $PROJECT"

# 3. Push the new key as the Pages secret (needs wrangler login or CLOUDFLARE_API_TOKEN)
printf '%s' "$(cat ~/.tunnel-key)" | wrangler pages secret put TUNNEL_KEY --project-name="$PROJECT"

# 4. Restart the tunnel client so it picks up the new key
bash restart-tunnel.sh
```

**Verify:**

```bash
sleep 10
curl -s -o /dev/null -w '%{http_code}\n' --max-time 10 "$(cat .tunnel-url)"
# expect 200 or 307 (307 = redirect to dashboard login, normal)
bash scripts/doctor.sh   # expect: 0 FAIL
```

Open the public tunnel URL in a browser — the 9Router dashboard should load.

## 2. Rotate the 9Router dashboard password

```bash
# 1. Generate and save a new password (no trailing newline issues: $(...) strips it)
openssl rand -base64 24 | tr -d '\n' > .dashboard-pw && chmod 600 .dashboard-pw

# 2. Restart 9Router so it picks up the new password
bash restart-9router.sh
```

**Verify:**

```bash
sleep 8
curl -s -o /dev/null -w '%{http_code}\n' --max-time 10 http://127.0.0.1:20128/dashboard
# expect 200 or 307
```

Then log in at the public tunnel URL with the new password
(`cat .dashboard-pw` to display it when you need it — never paste it into chat).

## 3. Rotate the Telegram bot token

```bash
# 1. In Telegram, open @BotFather → /revoke → select your bot → copy the NEW token.
# 2. Back up and update .env (replace only the token value):
cp -p .env .env.bak && chmod 600 .env.bak
# edit .env and set TELEGRAM_BOT_TOKEN=<new-token>, or run:
python3 - <<'EOF'
import re
tok = input("paste new bot token: ").strip()
p = ".env"
s = open(p).read()
s2 = re.sub(r"^TELEGRAM_BOT_TOKEN=.*$", "TELEGRAM_BOT_TOKEN=" + tok, s, flags=re.M)
open(p, "w").write(s2)
print("updated" if s2 != s else "NO CHANGE — check the key name in .env")
EOF
chmod 600 .env

# 3. Restart the gateway (exact-PID rule: kill only when exactly one candidate)
PID=$(pgrep -f "[g]ateway.*run")
[ "$(printf '%s' "$PID" | wc -l)" = "1" ] && kill "$PID" || echo "no single gateway PID — check manually"
sleep 3
bash start-gateway.sh
```

**Verify:** send `/start` to your bot in Telegram → it replies. (If silent,
the usual cause is the allowlist: your numeric ID must be in
`TELEGRAM_ALLOWED_USERS` in `.env`.)

## Final check

```bash
bash scripts/doctor.sh   # expect: doctor: N ok, 0 FAIL, ...
```

## Rollback

```bash
BK=~/.hermuse-secret-backup/<date>   # the date you used in Rule 0
cp -p "$BK"/.tunnel-key ~/.
cp -p "$BK"/.env "$BK"/.dashboard-pw .
chmod 600 ~/.tunnel-key .env .dashboard-pw
# then redo the *remote* half that you already changed:
#  - tunnel key: re-run step 3 of section 1 with the restored key, then restart-tunnel.sh
#  - dashboard password: bash restart-9router.sh
#  - bot token: @BotFather /revoke again is NOT possible — the old token is dead
#    forever. Keep the new one.
```

Note: a revoked Telegram bot token can never be restored — rollback only
applies to the tunnel key and dashboard password.
