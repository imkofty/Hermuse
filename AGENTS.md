# AGENTS.md — operating manual for Muse

You are **Muse**, the AI assistant. This file is your operating manual for the
Hermuse repo. Read it immediately after cloning, before running anything. It
is written for you specifically — not for a human installer. For the full
human documentation, see `README.md` (English) / `README.id.md` (Indonesian).

## What this stack is

Hermuse is a self-hosted kit: **Hermes Agent** (a Telegram bot gateway, the
user-facing piece) + **9Router** (a local OpenAI-compatible model router on
`127.0.0.1:20128`, the model backend). A Cloudflare Pages + D1 polling tunnel
exposes the local 9Router dashboard publicly. Two watchdog scripts keep the
pieces alive via cron. The typical user flow: the user hands this repo to you,
and you clone and execute — no human runs the installer by hand.

## Execution order

Run these in order. After each step, verify it before moving on (the
`Verify:` blocks in `README.md` show the exact check).

1. `bash scripts/install.sh` — non-interactive, idempotent. Installs node
   deps, Hermes CLI, and 9Router. Needs passwordless `sudo` or root
   (the script fails fast with a clear message otherwise).
2. Model login: `hermes setup --portal` — **this IS the model-login step**
   (OAuth via the Nous portal in the browser). To use a different provider
   instead, run `hermes model` and pick one.
3. The user creates a Telegram bot via @BotFather themselves. Prefer the
   user typing the token straight into the local `.env` file themselves
   (chmod 600) so it never travels through chat logs. If the token is
   handed over via chat anyway: write it to `.env` immediately, never
   echo it back, never log or commit it.
4. `hermes gateway setup` — needs the bot token and the user's numeric
   Telegram ID (ask the user for both).
5. `bash scripts/setup-tunnel.sh <pages-project-name> <d1-name>` — provisions
   the Cloudflare tunnel (generates key → creates D1 → deploys Pages → sets
   the secret). Needs the Cloudflare auth choice (ask the user).
6. Boot order:
   - `bash restart-9router.sh`
   - `bash restart-tunnel.sh` — needs `TUNNEL_BASE_URL` env or a `.tunnel-url`
     file (chmod 600) in the repo root; cron cannot see interactive env vars,
     so prefer the file.
   - `bash start-gateway.sh`
7. Watchdog on cron (every 5 minutes):
   `*/5 * * * * /path/to/Hermuse/watchdog.sh`
   and (recommended)
   `*/5 * * * * /path/to/Hermuse/gateway-watch.sh`
   `gateway-watch.sh` confirms before restarting; dry-run with
   `DRY_RUN=1 bash gateway-watch.sh`.

## Ask the user — never guess these

Ask the user via chat for each of the following. Do not invent, default, or
reuse values from elsewhere:
1. Telegram bot token (from @BotFather — the user creates the bot).
   Preferred: the user enters it into the local `.env` themselves. If it
   arrives via chat, store it immediately and never repeat it back.
2. The user's numeric Telegram ID (gateway allowlist is default-deny).
3. Cloudflare Pages project name for the tunnel.
4. Cloudflare D1 database name for the tunnel.
5. Cloudflare auth choice: `wrangler login` (browser OAuth) vs
   `CLOUDFLARE_API_TOKEN` (transient env var, never stored).

## Secrets rules

- `chmod 600` on `.env`, `.tunnel-key`, `.tunnel-url`, `.dashboard-pw`.
  Never commit any of them (all are gitignored — verify with
  `git status --porcelain` before every commit).
- `wrangler.toml` stays gitignored (it holds account-specific project/D1 IDs)
  but it is **not** a secret file. Never put `CLOUDFLARE_API_TOKEN` in it —
  use `wrangler secret put` or the env var, transient only.

## Gotchas

- Never `pkill -f` broadly. The `restart-*` scripts encode the exact-PID
  rules; use them instead of inventing your own kill commands.
- 9Router binds `127.0.0.1` only. It is reachable publicly solely through
  the tunnel client — there is no direct public port.
- The Telegram gateway is default-deny: only numeric IDs in
  `TELEGRAM_ALLOWED_USERS` get replies. "Bot is silent" almost always means
  the user isn't allowlisted.
- `install.sh` appends `~/.local/bin` to `~/.bashrc`, but non-login shells
  don't source it — if `hermes: command not found` after install, the fix is
  `export PATH="$HOME/.local/bin:$PATH"`.
- Verify every step before moving on. A failure three steps later is almost
  always an unverified earlier step.

## Final verification

Run `bash scripts/doctor.sh` and fix every `[FAIL]` line (each ends with
`→ fix: <exact command>`). Exit code is 1 iff at least one FAIL exists.
`[warn]` is hygiene only; `[SKIP]` means "not configured yet" — doctor is
useful mid-install, not just on a finished stack.
