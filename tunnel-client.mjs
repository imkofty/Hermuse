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
//   TUNNEL_MAX_RESPONSE_MB  opsional — batas ukuran respons backend; nilai
//                                efektif selalu di-clamp ke kapasitas D1
//                                (lihat D1_SAFE_RESPONSE_BYTES di bawah).
//   TUNNEL_HEARTBEAT_MS opsional — interval perpanjangan lease klaim ke
//                                server selama backend bekerja, default
//                                10000. "0" menonaktifkan (tidak disarankan).
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
// - Putaran 3: klaim DIPERPANJANG lewat __tunnel/heartbeat selama
//   backend bekerja (lease server tidak lagi balapan dengan timeout
//   backend), dan batas respons di-clamp ke kapasitas simpan D1
//   (2.000.000 byte/baris; respons disimpan Base64).
import { readFileSync } from "node:fs";
import { t } from "./lib/i18n.mjs";

const BASE = (process.env.TUNNEL_BASE_URL || "").replace(/\/$/, "");
const KEY_FILE = process.env.TUNNEL_KEY_FILE || (process.env.HOME + "/.tunnel-key");
const LOCAL = process.env.TUNNEL_LOCAL || "http://127.0.0.1:20128";
const POLL_MS = parseInt(process.env.TUNNEL_POLL_MS || "400", 10);
const LOCAL_TIMEOUT_MS = parseInt(process.env.TUNNEL_LOCAL_TIMEOUT_MS || "30000", 10);
// Kapasitas simpan D1: satu string/BLOB/baris maksimal 2.000.000 byte, dan
// respons disimpan Base64 (mengembang 4/3). 1.350.000 byte mentah ->
// tepat 1.800.000 karakter Base64; sisanya ruang untuk header & kolom
// lain. Batas lama 32 MiB TIDAK PERNAH muat di D1 (temuan audit putaran
// 3) — karena itu nilai konfigurasi apa pun di-clamp ke angka ini.
const D1_SAFE_RESPONSE_BYTES = 1350000;
const MAX_RESPONSE_BYTES = Math.min(
  parseInt(process.env.TUNNEL_MAX_RESPONSE_MB || "32", 10) * 1024 * 1024,
  D1_SAFE_RESPONSE_BYTES
);
const HEARTBEAT_MS = parseInt(process.env.TUNNEL_HEARTBEAT_MS || "10000", 10);
const HEALTH_PATH = "/__tunnel-health";
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
      throw new Error(t("tunnel_response_too_large", (MAX_RESPONSE_BYTES / 1048576).toFixed(2)));
    }
    chunks.push(Buffer.from(value));
  }
  return Buffer.concat(chunks);
}

// Health probe (watchdog): request ke HEALTH_PATH TIDAK diteruskan apa
// adanya — client membuktikan dirinya hidup dengan mengecek backend
// lokal lalu menjawab lewat jalur respond biasa, membawa nonce yang
// dikirim prober. Prober memverifikasi nonce + backend_ok, jadi jawaban
// basi/cache/edge tidak bisa menyamar sebagai "tunnel sehat".
async function handleHealth(req) {
  const { id, claim_token, headers } = req;
  const reqHeaders = JSON.parse(headers || "{}");
  let backendStatus = 0;
  let backendOk = false;
  try {
    const br = await fetch(LOCAL + "/v1/models", {
      signal: AbortSignal.timeout(5000),
    });
    backendStatus = br.status;
    backendOk = br.status < 500;
    await br.arrayBuffer().catch(() => {});
  } catch { /* backend tak terjangkau: backendOk tetap false */ }
  await api("/__tunnel/respond", {
    id, claim_token,
    status_code: 200,
    headers: { "content-type": "application/json" },
    body: Buffer.from(JSON.stringify({
      ok: true,
      nonce: reqHeaders["x-health-nonce"] || null,
      backend_ok: backendOk,
      backend_status: backendStatus,
    })).toString("base64"),
  });
}

async function handleOne(req) {
  const { id, method, path, headers, body, claim_token } = req;
  if (path === HEALTH_PATH) {
    await handleHealth(req).catch(() => {});
    return;
  }
  // Heartbeat: perpanjang lease klaim selama backend masih bekerja, agar
  // poller lain tidak merebut request ini di tengah jalan (kerja ganda).
  // Lease server 45 dtk; heartbeat 10 dtk memberi ruang longgar. Bila
  // klaim tetap hilang (heartbeat 409), respond akhir juga ditolak 409 —
  // tidak ada efek ganda yang lolos.
  let hb = null;
  if (HEARTBEAT_MS > 0 && claim_token) {
    hb = setInterval(() => {
      api("/__tunnel/heartbeat", { id, claim_token }).catch(() => {});
    }, HEARTBEAT_MS);
    if (typeof hb.unref === "function") hb.unref();
  }
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
  } finally {
    if (hb) clearInterval(hb);
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
