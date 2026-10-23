# Hermuse — セルフホスト型 AI エージェントスタック（Hermes + 9Router + Telegram）

![Hermuse banner](assets/banner.png)

[🇬🇧 English](README.md) · [🇮🇩 Indonesia](README.id.md) · [🇲🇾 Malaysia](README.ms.md) · [🇻🇳 Việt Nam](README.vi.md) · [🇮🇳 हिन्दी](README.hi.md) · 🇯🇵 **日本語**

[![Stars](https://img.shields.io/github/stars/imkofty/Hermuse?style=for-the-badge&logo=github&color=20808D)](https://github.com/imkofty/Hermuse/stargazers)
[![Forks](https://img.shields.io/github/forks/imkofty/Hermuse?style=for-the-badge&logo=github&color=4DD0E1)](https://github.com/imkofty/Hermuse/network/members)
[![Issues](https://img.shields.io/github/issues/imkofty/Hermuse?style=for-the-badge&logo=github&color=FFB454)](https://github.com/imkofty/Hermuse/issues)
[![License: MIT](https://img.shields.io/github/license/imkofty/Hermuse?style=for-the-badge&color=3FB950)](LICENSE)
[![doctor](https://github.com/imkofty/Hermuse/actions/workflows/doctor.yml/badge.svg)](https://github.com/imkofty/Hermuse/actions/workflows/doctor.yml)

[![Linux](https://img.shields.io/badge/OS-Linux-FCC624?style=for-the-badge&logo=linux&logoColor=black)](https://ubuntu.com/)
[![Node.js](https://img.shields.io/badge/node-%3E%3D18-339933?style=for-the-badge&logo=node.js&logoColor=white)](https://nodejs.org/)
[![Telegram](https://img.shields.io/badge/Telegram-Gateway-26A5E4?style=for-the-badge&logo=telegram&logoColor=white)](https://core.telegram.org/bots)
[![Cloudflare](https://img.shields.io/badge/Cloudflare-Tunnel-F68204?style=for-the-badge&logo=cloudflare&logoColor=white)](https://www.cloudflare.com/)
[![Bash](https://img.shields.io/badge/Bash-Scripts-4EAA25?style=for-the-badge&logo=gnu-bash&logoColor=white)]()

**Hermuse = Hermes + Muse。** Hermes Agent（Nous Research の AI
エージェント）と 9Router、Telegram ゲートウェイを自分のサーバーで動かすための
スクリプトとガイドです。Muse の VM で実際に動いているスタックの正確な
レプリカです。

**最終的な成果物:** 24 時間いつでもチャットできる、あなた専用の Telegram AI
ボットと、どのブラウザーからでも開けるモデルダッシュボードです。

## クイックスタート

必要なもの:

- Muse のような Linux VM（Ubuntu 22.04/24.04、2 vCPU / 4 GB RAM で十分です）
- 無料の Cloudflare アカウント（ダッシュボード用 tunnel のため）
- Telegram ボット（[@BotFather](https://t.me/BotFather) 経由で無料）

**初めての方へ。** 次の順番で進めてください:

1. `bash scripts/install.sh` — すべてをインストールします（依存関係、Hermes、9Router）
確認: `hermes --version` → バージョンが表示されます。`9router --version` → バージョンが表示されます
2. `hermes setup --portal` — モデルログイン。`hermes gateway setup` — Telegram ボットを接続します
確認: ボットに `/start` を送ります → 返信が来ます（あなたの Telegram 数値 ID がゲートウェイの許可リストに必要です）
3. `bash scripts/setup-tunnel.sh <pages-project-name> <d1-name>` — Cloudflare tunnel をインストールします
確認: `pgrep -f "tunnel-client[.]mjs"` → PID が表示されます
4. 下記の[正しい起動順序](#正しい起動順序)に従い、watchdog を cron に登録します
確認: `bash scripts/doctor.sh` → サマリーに `0 FAIL` と表示されます

操作スクリプトを直接使いたい方は、[ファイル構成](#ファイル構成)の表をご覧ください。

## 仕組み

```
Telegram (you)
   │ polling
   ▼
Hermes gateway  ──▶  model:
   (run-hermes.sh)        ├─▶ Nous (direct, via OAuth / API key)
                          └─▶ 9Router  (127.0.0.1:20128, OpenAI-compatible)

Browser (internet)
   │ plain HTTPS
   ▼
<your-project>.pages.dev  (Cloudflare Pages Functions)
   │ request/response queue
   ▼
D1  (tunnel_requests / tunnel_responses tables)
   ▲ ~20s HTTPS long-poll
   │
tunnel-client.mjs  (on your VM)
   │ forward
   ▼
9Router at 127.0.0.1:20128
```

**なぜ long-poll なのか。** `/__tunnel/poll` エンドポイントは、キューが空の
とき接続を約 20 秒保持してから応答します（リクエストが来れば即座に応答
します）。これがないと、400ms〜2.5s ごとのポーリングで Cloudflare Workers の
**無料枠 100k リクエスト/日**を数時間で使い切ってしまいます。long-poll に
より、アイドル時の使用量は約 4,300 リクエスト/日まで下がります。実装は
`tunnel/pages-tunnel/functions/__tunnel/poll.js` をご覧ください。

9Router は `127.0.0.1` にのみバインドします（安全で、外部に公開されません）。
ポーリング tunnel を使う理由は、元の VM のネットワークでは WebSocket、
QUIC/UDP、`cloudflared` の edge への接続がすべて失敗したためです。詳しくは
[失敗アーカイブ](docs/arsip-tunnel-gagal.md)をご覧ください。通常の VM /
ネットワークでは、普通の `cloudflared` の方がおそらく簡単です。

## ファイル構成

| ファイル | 役割 |
|---|---|
| `run-hermes.sh` | Hermes CLI を実行します。デフォルトでは `scripts/install.sh` がインストールした標準の `hermes` コマンドへ転送します。オプションの venv モード: `HERMES_VENV` と `HERMES_SRC` 環境変数を設定します（事前に検証され、不正なパスは明確なメッセージで即座に失敗します）。 |
| `start-gateway.sh` | Telegram ゲートウェイをデタッチで実行します（`setsid`+`nohup`）。 |
| `start-9router.sh` | 9Router スーパーバイザー: `127.0.0.1:20128` にバインドし、クラッシュ時に自動再起動します。ダッシュボードパスワードは `.dashboard-pw`（600）から読み取ります。 |
| `start-pages-tunnel.sh` | Tunnel クライアントのスーパーバイザー（`tunnel-client.mjs`）、自動再起動付き。 |
| `restart-9router.sh` | 古い 9Router プロセスを kill し（安全なパターン、自己 kill 防止）、スーパーバイザーをデタッチで起動します。 |
| `restart-tunnel.sh` | 古い tunnel クライアントを kill し、スーパーバイザーをデタッチで起動します。 |
| `watchdog.sh` | 9Router、tunnel クライアント、ゲートウェイを確認し、落ちたものを再起動します。cron 用です。 |
| `gateway-watch.sh` | Telegram ゲートウェイの停滞検知 watchdog: 「プロセスが生きているか」だけでなく、イベントループのハートビートとアダプターの活動で無言の停滞を検知します。cron 用（5 分ごと）。 |
| `tunnel-client.mjs` | ポーリングクライアント: Pages からキューを取得し、ローカルの 9Router へ転送し、レスポンスを返します。 |
| `tunnel/` | D1 スキーマ（`schema.sql`）+ Pages Functions + `wrangler.toml.example`。 |
| `scripts/install.sh` | ゼロからのインストール: 依存関係、Node.js LTS、Hermes、9Router。 |
| `scripts/setup-tunnel.sh` | Tunnel のセットアップ: キー生成 → D1 作成 → Pages デプロイ → シークレット設定。 |
| `scripts/setup-tunnel-cloudflared.sh` | 通常ネットワーク向けの代替 tunnel（`cloudflared`、サンドボックス以外）: バイナリのインストール、ログイン、tunnel 作成、DNS ルーティング、実行手順。 |
| `docs/arsip-tunnel-gagal.md` | アーカイブ: 元の VM ネットワークでの `cloudflared` と Tailscale の失敗（インドネシア語）。 |

## 正しい起動順序

この順番で実行します（一度で十分です。あとはスーパーバイザーと watchdog が
面倒を見ます）:

1. 最初に 9Router（デタッチのスーパーバイザー、自動再起動）:
   `bash restart-9router.sh`
確認: `curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:20128/dashboard` → `200` または `307` と表示されます（307 = ログインへのリダイレクトで、正常です）

2. Tunnel クライアント（`TUNNEL_BASE_URL` または `.tunnel-url` ファイルが必要です）:
   `export TUNNEL_BASE_URL='https://<your-project>.pages.dev'` の後、`bash restart-tunnel.sh`
確認: `pgrep -f "tunnel-client[.]mjs"` → PID が表示されます

3. Telegram ゲートウェイ（デタッチ）:
   `bash start-gateway.sh`
確認: `pgrep -f "[g]ateway['\", ]+run"` → PID がちょうど 1 つ表示されます

その後、ブラウザーで `https://<your-project>.pages.dev` を開くと、9Router
ダッシュボードが表示されるはずです。`504 tunnel timeout (client offline?)`
と表示される場合は、tunnel クライアントがまだ起動していません。

## Watchdog（5 分ごとの cron）

```bash
crontab -e
# add this line (adjust the path):
*/5 * * * * /path/to/Hermuse/watchdog.sh
```

watchdog は 3 つを確認します — 9Router（`/dashboard` への `curl`）、tunnel
クライアント（`pgrep tunnel-client[.]mjs`）、Telegram ゲートウェイ
（`gateway.*run`）— 落ちたものを `restart-*` スクリプトで再起動します。
すべて正常なときは静かで（ログを書きません）、実際に再起動したときだけ
ログを残します。

> cron 用の注意: tunnel URL はこのフォルダーの `.tunnel-url` ファイル
> （chmod 600）に保存してください。cron は対話セッションの環境変数を
> 継承しないためです:
> `echo -n 'https://<your-project>.pages.dev' > .tunnel-url && chmod 600 .tunnel-url`

## 停滞検知ゲートウェイ watchdog（任意ですが推奨）

上記の `watchdog.sh` は「プロセスが存在するか」しか確認しません。プロセスが
生きているのに Telegram のポーリングが止まると、すり抜けてしまいます。
`gateway-watch.sh` は 3 層でその隙間を埋めます:

1. ゲートウェイの PID がない → 即座に再起動。
2. イベントループのハートビート（`$HERMES_HOME/state/gateway.heartbeat`、
   ゲートウェイが自動で書き込みます）が 120 秒以上古い → 即座に再起動。
3. ハートビートは新しいが、`gateway.log` の Telegram アダプター活動が
   15 分間 0 → 疑わしいとしてマークし、2 回連続で確認できたら再起動。

絶対ルール: kill するのは候補 PID がちょうど 1 つのときだけです（曖昧さなし）。
9Router には決して触りません。実動作なしのドライラン:
`DRY_RUN=1 bash gateway-watch.sh`。

```bash
crontab -e
# add (can alternate with watchdog.sh):
*/5 * * * * /path/to/Hermuse/gateway-watch.sh
```

## 再起動後の自動起動

`scripts/start-all.sh` は、落ちている Hermuse コンポーネント（9Router、
tunnel クライアント、Telegram ゲートウェイ）を起動します。冪等で、動作中の
コンポーネントには触りません:

```bash
bash /path/to/Hermuse/scripts/start-all.sh
```

通常の Linux VPS で、再起動のたびに自動実行するには:

**方法 1 — cron の `@reboot`:**

```bash
crontab -e
# add:
@reboot sleep 30 && /path/to/Hermuse/scripts/start-all.sh >> /path/to/Hermuse/boot.log 2>&1
```

**方法 2 — systemd ユーザーユニット**（`~/.config/systemd/user/hermuse.service`）:

```ini
[Unit]
Description=Hermuse stack (9Router + tunnel + Telegram gateway)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/path/to/Hermuse/scripts/start-all.sh
RemainAfterExit=yes

[Install]
WantedBy=default.target
```

```bash
systemctl --user daemon-reload
systemctl --user enable --now hermuse.service
# to run without login: sudo loginctl enable-linger $USER
```

（どちらの例も通常の VPS / ネットワーク向けで、すべてのディストリビューション
でテストされたわけではありません。ご自分の環境に合わせて調整してください。
安全網として、5 分ごとの watchdog cron は引き続き推奨します。）

## ゼロからインストール

何もない状態から始める場合は、ここから:

```bash
bash scripts/install.sh        # dependencies + Node.js + Hermes + 9Router + hermes doctor
```
（パスワードなし `sudo` が必要です。なければ root で実行してください —
スクリプトはそうでなければ即座に失敗します）

次に、モデルプロバイダーと Telegram ゲートウェイのウィザード:

```bash
hermes setup --portal   # log in to Nous via OAuth (or: hermes model to pick a provider)
hermes gateway setup    # enter your Telegram bot token + numeric-ID allowlist
```

最後に、Cloudflare tunnel のセットアップ:

```bash
CLOUDFLARE_API_TOKEN='<token>' bash scripts/setup-tunnel.sh <pages-project-name> <d1-name>
```

（Cloudflare トークンは一時的にのみ使われ、どのファイルにも保存されません。）

## セキュリティ — 必ず読んでください

- シークレットファイルは**常に `chmod 600`** で、**決してコミットしません**:
  `.env`、`.tunnel-key`、`.tunnel-url`、`.dashboard-pw`、`wrangler.toml`
  （すべて `.gitignore` でカバーされています）。
- Telegram ゲートウェイ: **デフォルト拒否（default-deny）**です。
  `TELEGRAM_ALLOWED_USERS` にある数値 ID だけがボットを使えます
  （`TELEGRAM_BOT_TOKEN` と `TELEGRAM_ALLOWED_USERS` は `.env` にあります）。
- **9Router ダッシュボードパスワード:** `scripts/setup-tunnel.sh` が
  `.dashboard-pw`（600）を生成します。公開 tunnel が設定されているのに
  そのファイルがない、または空の場合、`start-9router.sh` は起動を拒否します。
  自分のパスワードにしたい場合は、中身を変更してください。
- ポート 20128 を無防備にインターネットへ公開しないでください。9Router は
  `127.0.0.1` にのみバインドします。
- Telegram ボットのトークンが漏れたら: @BotFather で `/revoke` し、`.env`
  のトークンを差し替えて、ゲートウェイを再起動してください。
- **認証情報のローテーション:** 手順は[認証情報ローテーションガイド](docs/key-rotation.md)
  をご覧ください（tunnel キー、ダッシュボードパスワード、ボットトークン）。
- **Tunnel の認証はフェイルクローズドです。** Pages Functions は、
  `TUNNEL_KEY` が Pages シークレットとして設定され、かつクライアントの
  キーと一致しない限り、すべての poll/respond 呼び出しを拒否します。
  シークレット未設定が「開いた tunnel」を意味することは、もうありません。
- **既存の tunnel データベースをアップグレードする場合:** 一度だけの
  マイグレーションを**順番に**実行してください。古いデータベースには
  最初の 1 つだけでなく、4 つすべてが必要です:
  `wrangler d1 execute <db-name> --remote --file=tunnel/migrations/001-claim-lease.sql`
  次に `002-idempotency-ratelimit.sql`、次に `003-response-idempotency.sql`、
  最後に `004-idempotency-principal.sql`
  （同じコマンドで `--file` が違うだけです）。新規インストールには不要です
  （schema.sql にすべて含まれています）。`scripts/setup-tunnel.sh` を
  再実行しても適用されます。適用後は `bash scripts/check-tunnel-schema.sh <db-name>`
  で確認してください。不足分があれば、正確な修正コマンドが表示されます。
- **ペイロードは D1 に保存できる量で上限が決まります。** D1 は 1 つの
  文字列 / BLOB / 行を 2,000,000 バイトに制限し、ボディは Base64 で
  運ばれるため、tunnel が受け付けるリクエスト / レスポンスのボディは
  生で 1,350,000 バイト（Base64 で 1,800,000 文字）までです。それより
  大きなペイロードは、データベース挿入の失敗ではなく、明確な 413 が
  返ります。
- **冪等性は呼び出し元に紐づきます。** 保存されたレスポンスが再生される
  のは、冪等性キー、呼び出し元の認証情報、正確なリクエストペイロードの
  すべてが一致するときだけです。同じキーを違うペイロードで再利用すると
  409 Conflict になり、他の呼び出し元のレスポンスがあなたに再生される
  ことは決してありません。
- **Watchdog のヘルスチェックは本物の tunnel を通ります。**
  `.health-key` ファイル（`scripts/setup-tunnel.sh` が作成します）が
  ある場合、watchdog と doctor は認証付き nonce プローブで公開 tunnel を
  エンドツーエンドに検証し、ローカルクライアントが応答します。edge の
  401/403 だけでは「正常」とは数えられません。`.tunnel-url` はあるのに
  `.health-key` がない、または空の場合、watchdog はハードエラーを
  ログに残して tunnel チェックを失敗させます。プローブを黙って
  スキップすることはありません。

## 補足

<details>
<summary><strong>元のネットワークで失敗したもの（アーカイブ）</strong></summary>

元の VM ネットワークでは、2 つの標準的なアプローチが**完全に失敗**しました:

- **Cloudflare Tunnel（`cloudflared`）** — QUIC/UDP がブロックされ、edge IP
  への TLS が傍受され、プロキシがポート 7844 への CONNECT を拒否しました。
- **Tailscale** — コントロールプレーンがネットワークを通れませんでした
  （MITM による HTTP 400）。

詳細とサニタイズ済みの設定例:
[docs/arsip-tunnel-gagal.md](docs/arsip-tunnel-gagal.md)（インドネシア語）。
通常の VM / ネットワークでは、どちらもおそらく最も簡単な方法です。

</details>

## ライセンス

MIT.
