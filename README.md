# Hermuse — self-hosted AI agent stack (Hermes + 9Router + Telegram)

![Hermuse banner](assets/banner.png)

🇬🇧 **English** · [🇮🇩 Indonesia](README.id.md) · [🇲🇾 Malaysia](README.ms.md) · [🇻🇳 Việt Nam](README.vi.md) · [🇮🇳 हिन्दी](README.hi.md) · [🇯🇵 日本語](README.ja.md)

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

**Hermuse = Hermes + Muse.** Scripts and guides to run Hermes Agent (the AI
agent from Nous Research) + 9Router + a Telegram gateway on your own server —
an exact replica of the stack running on Muse's VM.

**End result:** your personal Telegram AI bot, online 24/7 and ready to chat
anytime, plus a model dashboard you can open from any browser.

## Quick start

What you need:

- A Linux VM like Muse's (Ubuntu 22.04/24.04; 2 vCPU / 4 GB RAM is enough)
- A free Cloudflare account (for the dashboard tunnel)
- A Telegram bot (free via [@BotFather](https://t.me/BotFather))

**New to all of this?** Follow these in order:

1. `bash scripts/install.sh` — installs everything (dependencies, Hermes, 9Router)
Verify: `hermes --version` → prints a version line; `9router --version` → prints a version
2. `hermes setup --portal` — model login; `hermes gateway setup` — connect your Telegram bot
Verify: send `/start` to your bot → it replies (your numeric Telegram ID must be in the gateway allowlist)
3. `bash scripts/setup-tunnel.sh <pages-project-name> <d1-name>` — install the Cloudflare tunnel
Verify: `pgrep -f "tunnel-client[.]mjs"` → prints a PID
4. Follow the [correct boot order](#correct-boot-order) below, then put the watchdog on cron
Verify: `bash scripts/doctor.sh` → summary shows `0 FAIL`

Already comfortable and want the operational scripts directly? See the
[file layout](#file-layout) table.

## How it works

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

**Why long-poll?** The `/__tunnel/poll` endpoint holds the connection for
~20 seconds when the queue is empty before responding (or responds immediately
when a request arrives). Without this, polling every 400ms–2.5s would burn
through Cloudflare Workers' **100k requests/day free-tier quota** in hours;
with long-poll, idle usage drops to ~4,300 requests/day. See
`tunnel/pages-tunnel/functions/__tunnel/poll.js` for the implementation.

9Router binds only to `127.0.0.1` (safe, never exposed). The polling tunnel is
used because on the original VM network, WebSocket, QUIC/UDP, and `cloudflared`
connections to the edge all failed — see the
[failure archive](docs/arsip-tunnel-gagal.md). On a normal VM/network, plain
`cloudflared` is probably simpler.

## File layout

| File | Role |
|---|---|
| `run-hermes.sh` | Runs the Hermes CLI. Default: forwards to the standard `hermes` command installed by `scripts/install.sh`. Optional venv mode: set `HERMES_VENV` + `HERMES_SRC` env vars (validated up front; invalid paths fail fast with a clear message). |
| `start-gateway.sh` | Runs the Telegram gateway detached (`setsid`+`nohup`). |
| `start-9router.sh` | 9Router supervisor: binds `127.0.0.1:20128`, auto-restarts on crash. Dashboard password is read from `.dashboard-pw` (600). |
| `start-pages-tunnel.sh` | Tunnel client supervisor (`tunnel-client.mjs`), auto-restart. |
| `restart-9router.sh` | Kills the old 9Router process (safe pattern, anti self-kill) + starts the supervisor detached. |
| `restart-tunnel.sh` | Kills the old tunnel client + starts the supervisor detached. |
| `watchdog.sh` | Checks 9Router, tunnel client, gateway; restarts whatever died. For cron. |
| `gateway-watch.sh` | Anti-stall watchdog for the Telegram gateway: detects silent stalls via event-loop heartbeat + adapter activity, not just "process alive". For cron (every 5 minutes). |
| `tunnel-client.mjs` | Polling client: pulls the queue from Pages, forwards to local 9Router, sends responses back. |
| `tunnel/` | D1 schema (`schema.sql`) + Pages Functions + `wrangler.toml.example`. |
| `scripts/install.sh` | From-scratch install: dependencies, Node.js LTS, Hermes, 9Router. |
| `scripts/setup-tunnel.sh` | Tunnel setup: generate key → create D1 → deploy Pages → set secret. |
| `scripts/setup-tunnel-cloudflared.sh` | Alternative tunnel via `cloudflared` for normal networks (not the sandbox): install binary, login, create tunnel, route DNS, run instructions. |
| `docs/arsip-tunnel-gagal.md` | Archive: `cloudflared` & Tailscale failures on the original VM network (in Indonesian). |

## Correct boot order

Run in order (once is enough; supervisors + watchdog handle the rest):

1. 9Router first (detached supervisor, auto-restart):
   `bash restart-9router.sh`
Verify: `curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:20128/dashboard` → prints `200` or `307` (307 = redirect to login, normal)

2. Tunnel client (needs `TUNNEL_BASE_URL` or a `.tunnel-url` file):
   `export TUNNEL_BASE_URL='https://<your-project>.pages.dev'` then `bash restart-tunnel.sh`
Verify: `pgrep -f "tunnel-client[.]mjs"` → prints a PID

3. Telegram gateway (detached):
   `bash start-gateway.sh`
Verify: `pgrep -f "[g]ateway['\", ]+run"` → prints exactly one PID

Then open `https://<your-project>.pages.dev` in a browser — the 9Router
dashboard should appear. If you get `504 tunnel timeout (client offline?)`,
the tunnel client isn't running yet.

## Watchdog (cron every 5 minutes)

```bash
crontab -e
# add this line (adjust the path):
*/5 * * * * /path/to/Hermuse/watchdog.sh
```

The watchdog checks three things — 9Router (`curl` to `/dashboard`), the
tunnel client (`pgrep tunnel-client[.]mjs`), the Telegram gateway
(`gateway.*run`) — and restarts whatever died via the `restart-*` scripts.
It stays silent (writes no log) when everything is healthy; it only logs when
it actually restarts something.

> For cron: store the tunnel URL in a `.tunnel-url` file (chmod 600) in this
> folder, since cron doesn't inherit your interactive environment variables:
> `echo -n 'https://<your-project>.pages.dev' > .tunnel-url && chmod 600 .tunnel-url`

## Anti-stall gateway watchdog (optional but recommended)

The `watchdog.sh` above only checks "process exists or not". If Telegram
polling stalls while the process is still alive, it slips through.
`gateway-watch.sh` closes that gap with three layers:

1. Gateway PID missing → restart immediately.
2. Event-loop heartbeat (`$HERMES_HOME/state/gateway.heartbeat`, written
   automatically by the gateway) stale >120s → restart immediately.
3. Heartbeat fresh but 0 Telegram adapter activity in `gateway.log`
   for 15 minutes → mark suspect, restart if confirmed on 2 consecutive runs.

Hard rule: only kill when there is exactly 1 candidate PID (no ambiguity).
Never touches 9Router. Dry-run with no real action:
`DRY_RUN=1 bash gateway-watch.sh`.

```bash
crontab -e
# add (can alternate with watchdog.sh):
*/5 * * * * /path/to/Hermuse/gateway-watch.sh
```

## Auto-start after reboot

`scripts/start-all.sh` starts any Hermuse component that is down (9Router,
tunnel client, Telegram gateway) — idempotent, running components are untouched:

```bash
bash /path/to/Hermuse/scripts/start-all.sh
```

To run it automatically on every VPS reboot, for a normal Linux VPS:

**Option 1 — cron `@reboot`:**

```bash
crontab -e
# add:
@reboot sleep 30 && /path/to/Hermuse/scripts/start-all.sh >> /path/to/Hermuse/boot.log 2>&1
```

**Option 2 — systemd user unit** (`~/.config/systemd/user/hermuse.service`):

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

(Both examples are for a normal VPS/network and haven't been tested on every
distro — adapt to your system. The 5-minute watchdog cron is still recommended
as a safety net.)

## Install from scratch

Starting with nothing? Begin here:

```bash
bash scripts/install.sh        # dependencies + Node.js + Hermes + 9Router + hermes doctor
```
(needs passwordless `sudo`, or run as root — the script fails fast otherwise)

Then the model provider & Telegram gateway wizards:

```bash
hermes setup --portal   # log in to Nous via OAuth (or: hermes model to pick a provider)
hermes gateway setup    # enter your Telegram bot token + numeric-ID allowlist
```

Finally, the Cloudflare tunnel setup:

```bash
CLOUDFLARE_API_TOKEN='<token>' bash scripts/setup-tunnel.sh <pages-project-name> <d1-name>
```

(The Cloudflare token is used transiently — it is not stored in any file.)

## Security — don't skip

- Secret files are **always `chmod 600`** and **never committed**:
  `.env`, `.tunnel-key`, `.tunnel-url`, `.dashboard-pw`, `wrangler.toml`
  (all covered by `.gitignore`).
- Telegram gateway: **default-deny**. Only numeric IDs in
  `TELEGRAM_ALLOWED_USERS` can use the bot (`TELEGRAM_BOT_TOKEN` +
  `TELEGRAM_ALLOWED_USERS` live in `.env`).
- **9Router dashboard password:** `scripts/setup-tunnel.sh` generates
  `.dashboard-pw` (600) for you, and `start-9router.sh` refuses to boot
  while a public tunnel is configured if that file is missing or empty.
  Change its contents if you want a password of your own.
- Don't expose port 20128 to the internet unprotected; 9Router binds to
  `127.0.0.1` only.
- If your Telegram bot token leaks: `/revoke` in @BotFather, replace it in
  `.env`, restart the gateway.
- **Rotating credentials?** Follow the step-by-step [credential rotation guide](docs/key-rotation.md) (tunnel key, dashboard password, bot token).
- **Tunnel auth fails closed.** The Pages functions reject every poll/respond
  call unless `TUNNEL_KEY` is set as a Pages secret AND matches the client's
  key — an unset secret no longer silently means "open tunnel".
- **Upgrading an existing tunnel database?** Run the one-time migrations
  **in order** — old databases need all four, not just the first:
  `wrangler d1 execute <db-name> --remote --file=tunnel/migrations/001-claim-lease.sql`
  then `002-idempotency-ratelimit.sql`, then `003-response-idempotency.sql`,
  then `004-idempotency-principal.sql`
  (same command, different `--file`). Fresh installs don't need them
  (schema.sql already includes everything), and re-running
  `scripts/setup-tunnel.sh` applies them for you. Verify afterwards with
  `bash scripts/check-tunnel-schema.sh <db-name>` — it prints the exact
  fix command for anything still missing.
- **Payloads are capped at what D1 can store.** D1 limits one
  string/BLOB/row to 2,000,000 bytes and bodies travel as Base64, so the
  tunnel accepts request/response bodies up to 1,350,000 raw bytes
  (1,800,000 Base64 chars); larger payloads get a clear 413 instead of a
  failed database insert.
- **Idempotency is bound to the caller.** A stored response is replayed
  only when the idempotency key, the caller's credential, and the exact
  request payload all match. Reusing a key with a different payload gets
  a 409 Conflict; another caller's response is never replayed to you.
- **Watchdog health checks traverse the real tunnel.** With a
  `.health-key` file (created by `scripts/setup-tunnel.sh`), the watchdog
  and doctor verify the public tunnel end-to-end with an authenticated
  nonce probe answered by the local client — an edge 401/403 alone no
  longer counts as "healthy". If `.tunnel-url` exists but `.health-key`
  is missing or empty, the watchdog logs a hard ERROR and fails the
  tunnel check instead of silently skipping the probe.

## Notes

<details>
<summary><strong>What failed on the original network (archive)</strong></summary>

On the original VM network, two standard approaches **failed completely**:

- **Cloudflare Tunnel (`cloudflared`)** — QUIC/UDP blocked, TLS to edge IPs
  intercepted, proxy refused CONNECT to port 7844.
- **Tailscale** — control plane couldn't get through the network (HTTP 400
  from MITM).

Details + sanitized config examples:
[docs/arsip-tunnel-gagal.md](docs/arsip-tunnel-gagal.md) (in Indonesian).
On a normal VM/network both are probably the easiest route.

</details>

## License

MIT.
