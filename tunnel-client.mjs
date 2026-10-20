// Tunnel client: poll Pages -> forward ke 9Router lokal -> kirim response balik.
// Murni HTTPS polling (untuk jaringan yang memblokir WebSocket/QUIC).
//
// Konfigurasi via environment:
//   TUNNEL_BASE_URL   wajib   — URL Pages project, mis. https://<project-kamu>.pages.dev
//   TUNNEL_KEY_FILE   opsional — file berisi tunnel key, default ~/.tunnel-key (permission 600)
//   TUNNEL_LOCAL      opsional — target lokal, default http://127.0.0.1:20128.
//                                Wajib loopback; alamat lain ditolak kecuali
//                                TUNNEL_ALLOW_REMOTE_LOCAL=1 (opt-in sadar risiko).
//   TUNNEL_POLL_MS    opsional — jeda tambahan antar long-poll saat antrean kosong,
//                                default 400. Sejak server pakai long-poll (~20 detik
//                                menahan koneksi), nilai ini BUKAN interval polling
//                                utama — hanya jeda singkat sebelum poll berikutnya.
//   TUNNEL_LOCAL_TIMEOUT_MS opsional — timeout forward ke backend lokal, default 30000.
//   TUNNEL_MAX_RESPONSE_MB  opsional — batas ukuran respons backend, default 32.
//
// Keamanan (audit 2026-10-20):
// - Redirect backend TIDAK diikuti (redirect: "manual"): respons 3xx diteruskan
//   apa adanya ke pemanggil lewat tunnel. Dulu fetch mengikuti redirect secara
//   default — backend (atau siapa pun yang bisa membuatnya redirect) dapat
//   membelokkan fetch ke port/host lain di mesin ini.
// - Semua fetch punya timeout eksplisit; respons dibaca streaming dengan
//   batas ukuran — backend yang menggantung atau membanjiri tidak lagi
//   menahan/memenuhi memori client tanpa batas.
// - respond membawa claim_token dari poll: hanya pemegang klaim yang
//   responsnya diterima server (lihat functions/__tunnel/respond.js).
import { readFileSync } from "node:fs";
import { t } from "./lib/i18n.mjs";

const BASE = (process.env.TUNNEL_BASE_URL || "").replace(/\/$/, "");
const KEY_FILE = process.env.TUNNEL_KEY_FILE || (process.env.HOME + "/.tunnel-key");
const LOCAL = process.env.TUNNEL_LOCAL || "http://127.0.0.1:20128";
const POLL_MS = parseInt(process.env.TUNNEL_POLL_MS || "400", 10);
const LOCAL_TIMEOUT_MS = parseInt(process.env.TUNNEL_LOCAL_TIMEOUT_MS || "30000", 10);
const MAX_RESPONSE_BYTES = parseInt(process.env.TUNNEL_MAX_RESPONSE_MB || "32", 10) * 1024 * 1024;
const POLL_TIMEOUT_MS = 45000;   // server menahan long-poll ~20 dtk; beri ruang jaringan
const RESPOND_TIMEOUT_MS = 15000;

if (!BASE) {
  console.error(t("tunnel_env_missing"));
  console.error(t("tunnel_env_example"));
  console.error(t("tunnel_env_alt"));
  process.exit(1);
}

let LOCAL_URL;
try {
  LOCAL_URL = new URL(LOCAL);
} catch {
  console.error(t("tunnel_local_not_loopback", LOCAL));
  process.exit(1);
}
const LOOPBACK_HOSTS = new Set(["127.0.0.1", "localhost", "::1", "[::1]"]);
if (!LOOPBACK_HOSTS.has(LOCAL_URL.hostname) && process.env.TUNNEL_ALLOW_REMOTE_LOCAL !== "1") {
  console.error(t("tunnel_local_not_loopback", LOCAL));
  process.exit(1);
}

let KEY;
try {
  KEY = readFileSync(KEY_FILE, "utf8").trim();
} catch {
  console.error(t("tunnel_key_unreadable", KEY_FILE, KEY_FILE, KEY_FILE));
  process.exit(1);
}
if (!KEY) {
  console.error(t("tunnel_key_empty", KEY_FILE));
  process.exit(1);
}

async function api(path, body, timeoutMs = RESPOND_TIMEOUT_MS) {
  const r = await fetch(BASE + path, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ key: KEY, ...body }),
    signal: AbortSignal.timeout(timeoutMs),
  });
  if (!r.ok) throw new Error(`tunnel api ${path}: ${r.status}`);
  return r.json();
}

// Baca body respons secara streaming dengan batas keras — jangan pernah
// menampung respons tak terbatas di memori (dulu: arrayBuffer() utuh).
async function readCapped(r) {
  if (!r.body) return Buffer.alloc(0);
  const reader = r.body.getReader();
  const chunks = [];
  let total = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > MAX_RESPONSE_BYTES) {
      await reader.cancel().catch(() => {});
      throw new Error(t("tunnel_response_too_large", String(MAX_RESPONSE_BYTES / 1048576)));
    }
    chunks.push(Buffer.from(value));
  }
  return Buffer.concat(chunks);
}

async function handleOne(req) {
  const { id, method, path, headers, body, claim_token } = req;
  try {
    const h = { ...JSON.parse(headers || "{}") };
    delete h["host"];
    const init = {
      method, headers: h,
      redirect: "manual",
      signal: AbortSignal.timeout(LOCAL_TIMEOUT_MS),
    };
    if (body && method !== "GET" && method !== "HEAD") init.body = Buffer.from(body, "base64");
    const r = await fetch(LOCAL + path, init);
    const buf = await readCapped(r);
    const resHeaders = {};
    r.headers.forEach((v, k) => { resHeaders[k] = v; });
    await api("/__tunnel/respond", {
      id, claim_token, status_code: r.status, headers: resHeaders,
      body: buf.length ? buf.toString("base64") : null,
    });
  } catch (e) {
    await api("/__tunnel/respond", {
      id, claim_token,
      status_code: 502,
      headers: { "content-type": "text/plain" },
      body: Buffer.from("tunnel client error: " + e.message).toString("base64"),
    }).catch(() => {});
  }
}

console.log("tunnel client ->", BASE, "->", LOCAL);
let fails = 0;
for (;;) {
  try {
    const { requests } = await api("/__tunnel/poll", { limit: 6 }, POLL_TIMEOUT_MS);
    fails = 0;
    if (requests && requests.length) {
      await Promise.all(requests.map(handleOne));
    } else {
      await new Promise((r) => setTimeout(r, POLL_MS));
    }
  } catch (e) {
    fails++;
    console.error("poll error:", e.message);
    await new Promise((r) => setTimeout(r, Math.min(1000 * fails, 10000)));
  }
}
