# Troubleshooting

**Start here:** `bash scripts/doctor.sh`. Every `[FAIL]` line ends with
`→ fix: <exact command>` — run it first; this page explains the reasoning
behind the common ones. Each entry is Symptom → Diagnose → Fix, and every
command is copy-paste runnable.

Entries come only from observed failures — nothing here is invented.

---

### 1. Public tunnel URL returns 502 / 503 / 504

The tunnel infrastructure answered, but the forward leg to your machine
failed.

**Diagnose:**
```bash
curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$(cat .tunnel-url)"
curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:20128/dashboard
```

**Fix:**
- Local curl returns `000` (nothing listening) → 9Router is down:
  `bash restart-9router.sh`
- Local curl returns `200`/`307` (9Router healthy) → the tunnel client is the
  sick one: `bash restart-tunnel.sh`

---

### 2. Bot is silent, but the gateway process is alive

Telegram polling can stall while the process still exists — "process alive"
is not "gateway healthy".

**Diagnose:**
```bash
bash scripts/doctor.sh   # assertion 7 reports heartbeat age / pid mismatch
# or manually:
cat "$HERMES_HOME/state/gateway.heartbeat"
```

**Fix:**
```bash
DRY_RUN=1 bash gateway-watch.sh   # shows what it would do, changes nothing
bash gateway-watch.sh             # restarts the gateway on stale heartbeat
```

---

### 3. Dashboard redirects to login forever

The dashboard password file is missing or doesn't match what you're typing.

**Diagnose:**
```bash
ls -l .dashboard-pw   # must exist, 600
```

**Fix:** write the correct password into `.dashboard-pw`
(`chmod 600 .dashboard-pw`), then `bash restart-9router.sh` so the dashboard
picks it up.

---

### 4. Bot doesn't reply to a specific user

The gateway is default-deny: only numeric Telegram IDs in
`TELEGRAM_ALLOWED_USERS` get replies. "Bot is silent for one person" is
almost always this.

**Diagnose:** check the user's numeric ID against `TELEGRAM_ALLOWED_USERS`
in the gateway env file (`.hermes/.env`).

**Fix:** add the numeric ID to `TELEGRAM_ALLOWED_USERS`, then
`bash start-gateway.sh` to restart the gateway with the new allowlist.

---

### 5. `hermes: command not found` right after install.sh

`install.sh` appends `~/.local/bin` to `~/.bashrc`, but non-login shells
don't source it.

**Diagnose:**
```bash
command -v hermes      # empty
ls ~/.local/bin/hermes # exists
```

**Fix:**
```bash
export PATH="$HOME/.local/bin:$PATH"
```

---

### 6. `hermes doctor` reports failures

**Diagnose:** read its output. The commonly observed case is provider auth
(expired/revoked model credentials).

**Fix:** re-run the model login: `hermes setup --portal`

---

### 7. wrangler auth fails during tunnel setup

**Diagnose:** `wrangler whoami` — if it errors, no valid auth is present.

**Fix:** pick one auth path:
- `wrangler login` (browser OAuth), or
- `CLOUDFLARE_API_TOKEN` as a transient env var.

Never put the token in `wrangler.toml`.

---

### 8. Port 20128 already in use

A stale (unsupervised) 9Router owns the port, so the supervised one can't
bind.

**Diagnose:**
```bash
curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:20128/dashboard
```
If something answers but the process isn't the supervised one, it's stale.

**Fix:** `bash restart-9router.sh` — it stops the stale process using
exact-PID rules and starts the supervised instance. Never `pkill -f 9router`
(it matches too broadly, including your own shell).

---

### 9. doctor says the gateway is missing/ambiguous, but it's actually running

The gateway launcher on your machine uses an argv shape the doctor's
`pgrep` pattern doesn't cover. Observed case: the provisioned venv launcher
passes `sys.argv = ['-c', 'gateway', 'run']` — comma-separated inside the
`-c` string, not adjacent words — which the original adjacent-only pattern
missed.

**Diagnose:**
```bash
pgrep -af "gateway" | head   # find the real gateway cmdline
grep -n "gateway_pids" scripts/doctor.sh   # see the pattern doctor uses
```

**Fix:** widen the separator class in `gateway_pids()` in
`scripts/doctor.sh` to cover your launcher's shape, then re-run
`bash scripts/doctor.test.sh` — all tests must pass before committing.

---

*Versi Bahasa Indonesia: [troubleshooting.id.md](troubleshooting.id.md) · Versi Bahasa Malaysia: [troubleshooting.ms.md](troubleshooting.ms.md) · Tiếng Việt: [troubleshooting.vi.md](troubleshooting.vi.md) · हिन्दी: [troubleshooting.hi.md](troubleshooting.hi.md) · 日本語: [troubleshooting.ja.md](troubleshooting.ja.md)*
