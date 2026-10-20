#!/bin/bash
# doctor.sh — read-only health check for the Hermuse stack.
#
# Prints one line per assertion using a four-state vocabulary:
#   [ ok ]  — assertion holds
#   [FAIL]  — broken; line ends with "→ fix: <exact command>"
#   [warn]  — hygiene issue, not a broken stack (never affects exit code)
#   [SKIP]  — prerequisite absent (useful mid-install, not just when done)
#
# Exit code is 1 if and only if at least one FAIL exists.
# This script never restarts or modifies anything — it only reports.
#
# Test hooks (do not change default behavior; see spec §3 rev 6):
#   DOCTOR_DIR            directory for file assertions (default: repo root)
#   DOCTOR_NINEROUTER_PORT  port for the dashboard check (default: 20128)
#   DOCTOR_TUNNEL_URL     URL for the tunnel check (default: .tunnel-url file,
#                         trimmed, wins; TUNNEL_BASE_URL env is the fallback)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${DOCTOR_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"
NINEROUTER_PORT="${DOCTOR_NINEROUTER_PORT:-20128}"

n_ok=0
n_fail=0
n_warn=0
n_skip=0
a4_failed=0
n_gpids=0
gpid_one=""

emit() { # $1 = ok|FAIL|warn|SKIP, rest = message
  local state="$1"
  shift
  case "$state" in
    ok)   echo "[ ok ] $*" ; n_ok=$((n_ok + 1)) ;;
    FAIL) echo "[FAIL] $*" ; n_fail=$((n_fail + 1)) ;;
    warn) echo "[warn] $*" ; n_warn=$((n_warn + 1)) ;;
    SKIP) echo "[SKIP] $*" ; n_skip=$((n_skip + 1)) ;;
  esac
}

# Shared by assertions 6 and 7 so both agree on what "the gateway" is.
# Covers three observed launcher shapes:
#   run-hermes.sh:  <venv>/bin/python -c "..." gateway run      (adjacent)
#   normal install: hermes gateway run                          (adjacent)
#   provisioned:    python3 -I -c "...sys.argv = ['-c', 'gateway', 'run']..."
#                   (argv elements comma-separated inside the -c string)
# The '+' requires at least one separator (space, quote, or comma) — a bare
# "gatewayrun" must NOT match. The [g] trick keeps the pattern from matching
# its own pgrep invocation.
# Regression guard: scripts/doctor.test.sh pins all three shapes plus
# negative cases (gateway-watch.sh, start-gateway.sh, bare gatewayrun).
# Do not "simplify" this back to `gateway run` — the provisioned shape was
# missed by the adjacent-only variant on a live machine (spec rev 7).
gateway_pids() { pgrep -f "[g]ateway['\", ]+run" || true; }

http_code() { # $1 = url; prints the HTTP status, "000" when no response came back
  curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$1" || true
}

# --- 1. node >= 18 (authority: 9Router's engines field) ---
if command -v node >/dev/null 2>&1 \
  && node -e "process.exit(parseInt(process.versions.node.split('.')[0],10) >= 18 ? 0 : 1)" 2>/dev/null; then
  emit ok "node $(node -v) (>= 18)"
else
  emit FAIL "node >= 18 not found → fix: bash scripts/install.sh"
fi

# --- 2. hermes on PATH (no version gate) ---
if command -v hermes >/dev/null 2>&1; then
  emit ok "hermes on PATH ($(hermes --version 2>/dev/null | head -1))"
else
  emit FAIL "hermes not on PATH → fix: bash scripts/install.sh"
fi

# --- 3. 9router on PATH (no version gate) ---
if command -v 9router >/dev/null 2>&1; then
  emit ok "9router on PATH ($(9router --version 2>/dev/null | head -1))"
else
  emit FAIL "9router not on PATH → fix: bash scripts/install.sh"
fi

# --- 4. 9Router dashboard answers locally ---
code=$(http_code "http://127.0.0.1:${NINEROUTER_PORT}/dashboard")
if [ "$code" = "200" ] || [ "$code" = "307" ]; then
  emit ok "9Router dashboard responds (HTTP $code)"
else
  # "000"/empty = no HTTP response at all (nothing listening) — still FAIL here:
  # the local dashboard must answer; there is no grace for this one.
  emit FAIL "9Router dashboard not responding (got '${code:-000}') → fix: bash restart-9router.sh"
  a4_failed=1
fi

# --- 5. tunnel client process ---
if [ -n "$(pgrep -f "tunnel-client[.]mjs" || true)" ]; then
  emit ok "tunnel client running"
else
  emit FAIL "tunnel client not running → fix: bash restart-tunnel.sh"
fi

# --- 6. exactly one gateway process ---
gpids=$(gateway_pids)
if [ -z "$gpids" ]; then
  emit FAIL "gateway not running → fix: bash start-gateway.sh"
else
  n_gpids=$(printf '%s\n' "$gpids" | wc -l)
  if [ "$n_gpids" -eq 1 ]; then
    gpid_one="$gpids"
    emit ok "gateway running (pid $gpid_one)"
  else
    emit FAIL "gateway: $n_gpids candidate PIDs — ambiguous, needs a human (do not guess which to kill)"
  fi
fi

# --- 7. gateway heartbeat: pid matches, fresher than 120s ---
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}" # same default as run-hermes.sh / gateway-watch.sh
HB="$HERMES_HOME/state/gateway.heartbeat"
if [ "$n_gpids" -ne 1 ]; then
  emit SKIP "heartbeat not checked — ambiguous or missing gateway (see assertion 6)"
elif [ ! -r "$HB" ]; then
  emit FAIL "heartbeat file missing/unreadable ($HB) → fix: bash gateway-watch.sh"
else
  rc=0
  # exit 0 = fresh; 2 = unparseable timestamp; 3 = pid mismatch; 4 = stale; 1 = unreadable JSON
  HB_PID="$gpid_one" HB_FILE="$HB" node -e '
    const fs = require("fs");
    const hb = JSON.parse(fs.readFileSync(process.env.HB_FILE, "utf8"));
    if (Number.isNaN(Date.parse(hb.updated_at))) process.exit(2);
    if (String(hb.pid) !== String(process.env.HB_PID)) process.exit(3);
    const age = (Date.now() - Date.parse(hb.updated_at)) / 1000;
    if (!(age >= 0 && age < 120)) process.exit(4);
  ' 2>/dev/null || rc=$?
  case "$rc" in
    0) emit ok "gateway heartbeat fresh (pid $gpid_one, < 120s)" ;;
    3) emit FAIL "heartbeat pid does not match live gateway pid → fix: bash gateway-watch.sh" ;;
    *) emit FAIL "heartbeat stale/unparseable ($HB) → fix: bash gateway-watch.sh" ;;
  esac
fi

# --- 8/9/10. sensitive files exist with 600 ---
check_600() { # $1 = path, $2 = label
  local f="$1" label="$2" perms
  if [ ! -e "$f" ]; then
    emit SKIP "$label not present (not configured yet)"
  else
    perms=$(stat -c %a "$f")
    if [ "$perms" = "600" ]; then
      emit ok "$label present with 600 permissions"
    else
      emit warn "$label has permissions $perms, expected 600"
    fi
  fi
}
check_600 "$REPO_DIR/.env" ".env"
check_600 "$REPO_DIR/.tunnel-url" ".tunnel-url"
check_600 "$REPO_DIR/.dashboard-pw" ".dashboard-pw"

# --- 11. public tunnel URL reachable ---
turl="${DOCTOR_TUNNEL_URL:-}"
if [ -z "$turl" ] && [ -f "$REPO_DIR/.tunnel-url" ]; then
  turl=$(tr -d '[:space:]' < "$REPO_DIR/.tunnel-url")
fi
if [ -z "$turl" ]; then
  turl="${TUNNEL_BASE_URL:-}"
fi
if [ -z "$turl" ]; then
  emit SKIP "tunnel URL not configured (no .tunnel-url, no TUNNEL_BASE_URL)"
elif [ -f "$REPO_DIR/.health-key" ]; then
  # Probe terautentikasi (putaran 3): satu-satunya cek yang membuktikan
  # jalur tunnel benar-benar meneruskan — nonce harus kembali dari
  # client lokal dan backend harus ok. Selaras dengan watchdog.sh.
  hkey=$(tr -d '[:space:]' < "$REPO_DIR/.health-key")
  nonce="doctor-$(date +%s)-$$"
  pbody=$(curl -s -m 50 -H "x-tunnel-health-key: $hkey" -H "x-health-nonce: $nonce" "${turl%/}/__tunnel-health" 2>/dev/null || true)
  case "$pbody" in
    *"$nonce"*)
      case "$pbody" in
        *'"backend_ok":true'*|*'"backend_ok": true'*)
          emit ok "tunnel health probe passed (client + backend, nonce verified)" ;;
        *)
          emit FAIL "tunnel health probe: client answered but backend is down → fix: bash restart-9router.sh" ;;
      esac
      ;;
    *)
      emit FAIL "tunnel health probe failed (client not answering through the tunnel) → fix: bash restart-tunnel.sh" ;;
  esac
else
  code=$(http_code "$turl")
  if [ "$code" = "000" ] || [ -z "$code" ]; then
    emit warn "cannot reach $turl: network issue or wrong URL?"
  elif [ "$code" = "200" ]; then
    emit ok "tunnel URL reachable (HTTP 200)"
  elif [ "$code" = "401" ] || [ "$code" = "403" ]; then
    # Gate/edge menjawab BUKAN bukti tunnel meneruskan request (ingress
    # bisa menolak sebelum antrean). Tanpa .health-key, doctor tidak
    # bisa memverifikasi jalur forwarding — laporkan apa adanya.
    emit warn "tunnel URL answered HTTP $code (gated) — forwarding NOT verified; add .health-key (scripts/setup-tunnel.sh) for the real probe"
  elif [ "$code" = "502" ] || [ "$code" = "503" ] || [ "$code" = "504" ]; then
    # Tunnel infra answered but the forward leg failed (tunnel-client
    # responds 502 when 9Router is down). Pick the single fix command
    # from state so the line keeps the "→ fix: <exact command>" shape.
    if [ "$a4_failed" -eq 1 ]; then
      emit FAIL "tunnel URL returned HTTP $code (tunnel alive, backend failed) → fix: bash restart-9router.sh"
    else
      emit FAIL "tunnel URL returned HTTP $code (tunnel alive, backend failed) → fix: bash restart-tunnel.sh"
    fi
  else
    emit FAIL "tunnel URL returned HTTP $code → fix: bash restart-tunnel.sh"
  fi
fi

# Visible boundary of v1 scope: a marker, not a check. Do not attach checks here.
emit SKIP "Cloudflare-side checks (local-only v1)"

echo "doctor: $n_ok ok, $n_fail FAIL, $n_warn warn, $n_skip skip"
[ "$n_fail" -eq 0 ]
