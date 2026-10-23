# 認証情報ローテーションガイド

ローテーションするタイミング: シークレットが漏れた可能性があるとき（誤って
共有した、リポジトリにコミットした、画面で見られた）、アクセス権を持つ人が
もう持つべきでないとき、あるいは単に定期スケジュールとして。ローテーションは
安くつきます。議論するより実行してください。

*Versi Bahasa Indonesia: [key-rotation.id.md](key-rotation.id.md) · Versi Bahasa Malaysia: [key-rotation.ms.md](key-rotation.ms.md) · Tiếng Việt: [key-rotation.vi.md](key-rotation.vi.md) · हिन्दी: [key-rotation.hi.md](key-rotation.hi.md) · 日本語: [key-rotation.ja.md](key-rotation.ja.md)*

## シークレットの種類

| シークレット | 保存場所 | 使用者 |
|---|---|---|
| Tunnel キー | `~/.tunnel-key`（600） | `tunnel-client.mjs` ↔ Pages Functions（`TUNNEL_KEY` シークレット） |
| 9Router ダッシュボードパスワード | リポジトリ直下の `.dashboard-pw`（600） | `start-9router.sh` → 9Router |
| Telegram ボットトークン | リポジトリ直下の `.env`（600） | Telegram ゲートウェイ |
| Cloudflare API トークン | **どこにも保存しません — 一時的にのみ使用** | セットアップ時の `wrangler`。保存されることはありません |

上記はすべて gitignore されています。コミット前に必ず確認してください:
`git status --porcelain` にこれらが表示されてはいけません。

## ルール 0 — ローテーション前にバックアップ

```bash
mkdir -p ~/.hermuse-secret-backup && chmod 700 ~/.hermuse-secret-backup
BK=~/.hermuse-secret-backup/$(date -u +%F)
mkdir -p "$BK"
cp -p ~/.tunnel-key .env .dashboard-pw "$BK/" 2>/dev/null
chmod 600 "$BK"/*
```

問題が起きたら、`$BK` から復元して、下記の該当する再起動手順を繰り返して
ください。

## 1. Tunnel キー（`TUNNEL_KEY`）のローテーション

キーは **2 か所**で一致しなければなりません: ローカルの `~/.tunnel-key` と、
Pages プロジェクトの `TUNNEL_KEY` シークレットです。不一致になると、クライアントは
ポーリングのたびに HTTP 403 を受け取ります（バックオフ付きで再試行するので、
慌てず速やかに直してください）。

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

**確認:**

```bash
sleep 10
curl -s -o /dev/null -w '%{http_code}\n' --max-time 10 "$(cat .tunnel-url)"
# expect 200 or 307 (307 = redirect to dashboard login, normal)
bash scripts/doctor.sh   # expect: 0 FAIL
```

公開 tunnel URL をブラウザーで開いてください。9Router ダッシュボードが
読み込まれるはずです。

## 2. 9Router ダッシュボードパスワードのローテーション

```bash
# 1. Generate and save a new password (no trailing newline issues: $(...) strips it)
openssl rand -base64 24 | tr -d '\n' > .dashboard-pw && chmod 600 .dashboard-pw

# 2. Restart 9Router so it picks up the new password
bash restart-9router.sh
```

**確認:**

```bash
sleep 8
curl -s -o /dev/null -w '%{http_code}\n' --max-time 10 http://127.0.0.1:20128/dashboard
# expect 200 or 307
```

その後、新しいパスワードで公開 tunnel URL にログインしてください
（必要なときに `cat .dashboard-pw` で表示できます — チャットに貼ることは
決してしないでください）。

## 3. Telegram ボットトークンのローテーション

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

**確認:** Telegram でボットに `/start` を送ってください → 返信が来ます。
（返信がない場合、よくある原因は許可リストです。あなたの数値 ID が `.env` の
`TELEGRAM_ALLOWED_USERS` に必要です。）

## 最終確認

```bash
bash scripts/doctor.sh   # expect: doctor: N ok, 0 FAIL, ...
```

## ロールバック

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

注意: 失効した Telegram ボットトークンは二度と復元できません。ロールバックが
可能なのは tunnel キーとダッシュボードパスワードだけです。
