# トラブルシューティング

**まずここから:** `bash scripts/doctor.sh` を実行してください。すべての
`[FAIL]` 行は `→ fix: <exact command>` で終わっています。まずそれを実行し、
このページではよくあるケースの背景を説明します。各項目は「症状 → 診断 →
修正」の形式で、すべてのコマンドはコピー＆ペーストで実行できます。

ここにある項目は、実際に観測された障害だけです。作り話は一切ありません。

---

### 1. 公開 tunnel URL が 502 / 503 / 504 を返す

tunnel のインフラは応答しましたが、あなたのマシンへの転送レッグが失敗
しました。

**診断:**
```bash
curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$(cat .tunnel-url)"
curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:20128/dashboard
```

**修正:**
- ローカルの curl が `000` を返す（何も待ち受けていない）→ 9Router が
  落ちています: `bash restart-9router.sh`
- ローカルの curl が `200`/`307` を返す（9Router は正常）→ 病んでいるのは
  tunnel クライアントです: `bash restart-tunnel.sh`

---

### 2. ボットが無言だが、ゲートウェイのプロセスは生きている

プロセスが存在したまま Telegram のポーリングが止まることがあります。
「プロセスが生きている」は「ゲートウェイが正常」ではありません。

**診断:**
```bash
bash scripts/doctor.sh   # assertion 7 reports heartbeat age / pid mismatch
# or manually:
cat "$HERMES_HOME/state/gateway.heartbeat"
```

**修正:**
```bash
DRY_RUN=1 bash gateway-watch.sh   # shows what it would do, changes nothing
bash gateway-watch.sh             # restarts the gateway on stale heartbeat
```

---

### 3. ダッシュボードがログインへ永遠にリダイレクトする

ダッシュボードのパスワードファイルがないか、入力しているものと一致して
いません。

**診断:**
```bash
ls -l .dashboard-pw   # must exist, 600
```

**修正:** 正しいパスワードを `.dashboard-pw` に書き込んでください
（`chmod 600 .dashboard-pw`）。その後 `bash restart-9router.sh` を実行し、
ダッシュボードに読み込ませます。

---

### 4. 特定のユーザーにだけボットが返信しない

ゲートウェイはデフォルト拒否です。`TELEGRAM_ALLOWED_USERS` にある数値の
Telegram ID だけが返信を受け取ります。「1 人にだけボットが無言」なのは、
ほぼ常にこれが原因です。

**診断:** ゲートウェイの環境ファイル（`.hermes/.env`）で、そのユーザーの
数値 ID を `TELEGRAM_ALLOWED_USERS` と照合してください。

**修正:** 数値 ID を `TELEGRAM_ALLOWED_USERS` に追加し、`bash start-gateway.sh`
でゲートウェイを再起動して新しい許可リストを反映させてください。

---

### 5. install.sh の直後に `hermes: command not found`

`install.sh` は `~/.local/bin` を `~/.bashrc` に追加しますが、非ログイン
シェルはそれを読み込みません。

**診断:**
```bash
command -v hermes      # empty
ls ~/.local/bin/hermes # exists
```

**修正:**
```bash
export PATH="$HOME/.local/bin:$PATH"
```

---

### 6. `hermes doctor` が失敗を報告する

**診断:** 出力を読んでください。よく観測されるケースはプロバイダー認証
（期限切れ / 失効したモデルの認証情報）です。

**修正:** モデルログインを再実行してください: `hermes setup --portal`

---

### 7. tunnel セットアップ中に wrangler の認証が失敗する

**診断:** `wrangler whoami` — エラーになる場合は、有効な認証が存在しません。

**修正:** 認証方法を 1 つ選んでください:
- `wrangler login`（ブラウザー OAuth）、または
- `CLOUDFLARE_API_TOKEN` を一時的な環境変数として使う。

トークンを `wrangler.toml` に書くことは決してしないでください。

---

### 8. ポート 20128 が既に使用中

古い（監視されていない）9Router がポートを占有していて、監視対象のものが
バインドできません。

**診断:**
```bash
curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:20128/dashboard
```
何かが応答するのに、そのプロセスが監視対象でない場合は、古いプロセスです。

**修正:** `bash restart-9router.sh` — 正確な PID ルールで古いプロセスを
止め、監視対象のインスタンスを起動します。`pkill -f 9router` は決して
使わないでください（マッチ範囲が広すぎて、自分のシェルまで含みます）。

---

### 9. doctor はゲートウェイがない / 曖昧だと言うが、実際は動いている

あなたのマシンのゲートウェイランチャーが、doctor の `pgrep` パターンが
カバーしない argv の形を使っています。観測されたケース: プロビジョニング
された venv ランチャーは `sys.argv = ['-c', 'gateway', 'run']` を渡します
（`-c` 文字列の中でカンマ区切りで、隣接した単語ではありません）。元の
隣接のみのパターンはこれを取りこぼしました。

**診断:**
```bash
pgrep -af "gateway" | head   # find the real gateway cmdline
grep -n "gateway_pids" scripts/doctor.sh   # see the pattern doctor uses
```

**修正:** `scripts/doctor.sh` の `gateway_pids()` の区切り文字クラスを
広げて、あなたのランチャーの形をカバーしてください。その後
`bash scripts/doctor.test.sh` を再実行してください — コミット前にすべての
テストが合格しなければなりません。

---

*Versi Bahasa Indonesia: [troubleshooting.id.md](troubleshooting.id.md) · Versi Bahasa Malaysia: [troubleshooting.ms.md](troubleshooting.ms.md) · Tiếng Việt: [troubleshooting.vi.md](troubleshooting.vi.md) · हिन्दी: [troubleshooting.hi.md](troubleshooting.hi.md) · 日本語: [troubleshooting.ja.md](troubleshooting.ja.md)*
