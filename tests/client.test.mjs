// Test tunnel-client.mjs sebagai PROSES SUNGGUHAN melawan dua server stub:
//   - "Pages" stub: endpoint /__tunnel/poll & /__tunnel/respond in-memory.
//   - Backend stub: target lokal client (pengganti 9Router).
// Membuktikan temuan audit yang tidak bisa diuji dari fungsi Pages saja:
//   1. Redirect backend TIDAK diikuti (302 diteruskan apa adanya; server
//      tujuan redirect tidak pernah tersentuh) — regresi SSRF-via-redirect.
//   2. Backend yang menggantung kena timeout client -> pemanggil menerima
//      502 dari jalur error client, bukan menggantung selamanya.
//   3. Respons normal diteruskan utuh (status + body).
//   4. Putaran 5 — TIDAK ada head-of-line blocking: request cepat yang
//      masuk SETELAH request streaming lambat selesai lebih dulu.
//   5. Putaran 5 — deadline pembacaan body: stream yang macet di tengah
//      jalan dipotong oleh TUNNEL_RESPONSE_DEADLINE_MS -> 502, bukan
//      menggantung selamanya.
import { test } from "node:test";
import assert from "node:assert/strict";
import { createServer } from "node:http";
import { spawn } from "node:child_process";
import { mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");

function listen(server) {
  return new Promise((resolve) => server.listen(0, "127.0.0.1", () => resolve(server.address().port)));
}
function readJson(req) {
  return new Promise((resolve) => {
    let data = "";
    req.on("data", (c) => (data += c));
    req.on("end", () => { try { resolve(JSON.parse(data)); } catch { resolve({}); } });
  });
}
async function waitFor(fn, timeoutMs = 9000) {
  const start = Date.now();
  for (;;) {
    if (fn()) return;
    if (Date.now() - start > timeoutMs) throw new Error("waitFor timeout");
    await new Promise((r) => setTimeout(r, 100));
  }
}

test("tunnel-client: redirect tidak diikuti, timeout -> 502, respons normal utuh", { timeout: 20000 }, async () => {
  // --- Server penanda: TIDAK boleh tersentuh sama sekali ---
  let markerHits = 0;
  const marker = createServer((req, res) => { markerHits++; res.end("evil"); });
  const markerPort = await listen(marker);

  // --- Backend lokal stub ---
  const backend = createServer((req, res) => {
    if (req.url === "/ok") { res.writeHead(200, { "content-type": "text/plain" }); res.end("backend-ok"); }
    else if (req.url === "/redirect") { res.writeHead(302, { location: `http://127.0.0.1:${markerPort}/evil` }); res.end(); }
    else if (req.url === "/slow") { setTimeout(() => { if (!res.destroyed) res.end("terlambat"); }, 1500); }
    else { res.writeHead(404); res.end(); }
  });
  const backendPort = await listen(backend);

  // --- Pages stub ---
  const queue = [
    { id: "q1", method: "GET", path: "/ok", headers: "{}", body: null, claim_token: "tok" },
    { id: "q2", method: "GET", path: "/redirect", headers: "{}", body: null, claim_token: "tok" },
    { id: "q3", method: "GET", path: "/slow", headers: "{}", body: null, claim_token: "tok" },
  ];
  const responses = new Map();
  const pages = createServer(async (req, res) => {
    const body = await readJson(req);
    if (req.url === "/__tunnel/poll") {
      const out = queue.splice(0, queue.length);
      res.writeHead(200, { "content-type": "application/json" });
      res.end(JSON.stringify({ requests: out }));
    } else if (req.url === "/__tunnel/respond") {
      responses.set(body.id, body);
      res.writeHead(200, { "content-type": "application/json" });
      res.end(JSON.stringify({ ok: true }));
    } else { res.writeHead(404); res.end(); }
  });
  const pagesPort = await listen(pages);

  // --- Jalankan client sungguhan ---
  const tmp = mkdtempSync(join(tmpdir(), "hermuse-client-test-"));
  const keyFile = join(tmp, "key");
  writeFileSync(keyFile, "testkey");
  const child = spawn("node", [join(root, "tunnel-client.mjs")], {
    env: {
      ...process.env,
      TUNNEL_BASE_URL: `http://127.0.0.1:${pagesPort}`,
      TUNNEL_KEY_FILE: keyFile,
      TUNNEL_LOCAL: `http://127.0.0.1:${backendPort}`,
      TUNNEL_LOCAL_TIMEOUT_MS: "400",
      TUNNEL_POLL_MS: "50",
    },
    stdio: ["ignore", "pipe", "pipe"],
  });
  let stderr = "";
  child.stderr.on("data", (d) => (stderr += d));
  try {
    await waitFor(() => responses.size >= 3);
    const r1 = responses.get("q1");
    assert.equal(r1.status_code, 200);
    assert.equal(Buffer.from(r1.body, "base64").toString(), "backend-ok");
    const r2 = responses.get("q2");
    assert.equal(r2.status_code, 302); // diteruskan, BUKAN diikuti
    assert.equal(markerHits, 0);       // tujuan redirect tak tersentuh
    const r3 = responses.get("q3");
    assert.equal(r3.status_code, 502); // timeout backend -> jalur error client
  } finally {
    child.kill("SIGKILL");
    pages.close(); backend.close(); marker.close();
    rmSync(tmp, { recursive: true, force: true });
    if (responses.size < 3) throw new Error("client tidak menyelesaikan 3 request. stderr: " + stderr);
  }
});

// Stub Pages yang melayani antrean per-batch: poll ke-n menerima
// batch ke-n. Mencerminkan request yang TIBA BERURUTAN di antrean
// server (request cepat datang setelah request lambat diklaim).
function makeBatchPages(batches, responses, respondOrder) {
  let pollCount = 0;
  return createServer(async (req, res) => {
    const body = await readJson(req);
    if (req.url === "/__tunnel/poll") {
      const out = batches[pollCount] || [];
      pollCount++;
      res.writeHead(200, { "content-type": "application/json" });
      res.end(JSON.stringify({ requests: out }));
    } else if (req.url === "/__tunnel/respond") {
      responses.set(body.id, body);
      respondOrder.push(body.id);
      res.writeHead(200, { "content-type": "application/json" });
      res.end(JSON.stringify({ ok: true }));
    } else if (req.url === "/__tunnel/heartbeat") {
      res.writeHead(200, { "content-type": "application/json" });
      res.end(JSON.stringify({ ok: true }));
    } else { res.writeHead(404); res.end(); }
  });
}

test("tunnel-client putaran 5: request cepat tidak terhalang stream lambat (head-of-line)", { timeout: 20000 }, async () => {
  // Backend: /stream-lambat mengirim chunk pertama lalu menahan sisa
  // body 2,5 detik (streaming LLM sungguhan berperilaku begini);
  // /cepat menjawab seketika.
  const backend = createServer((req, res) => {
    if (req.url === "/stream-lambat") {
      res.writeHead(200, { "content-type": "text/plain" });
      res.write("bagian-");
      setTimeout(() => { if (!res.destroyed) { res.write("selesai"); res.end(); } }, 2500);
    } else if (req.url === "/cepat") {
      res.writeHead(200, { "content-type": "text/plain" });
      res.end("respons-cepat");
    } else { res.writeHead(404); res.end(); }
  });
  const backendPort = await listen(backend);

  // Antrean: poll pertama hanya berisi request lambat; request cepat
  // baru tiba di poll berikutnya. Dengan loop lama (await seluruh
  // batch sebelum poll lagi), request cepat bahkan belum DIKLAIM
  // sampai stream lambat selesai -> urutan respond pasti lambat dulu.
  const batches = [
    [{ id: "lambat1", method: "GET", path: "/stream-lambat", headers: "{}", body: null, claim_token: "tok-l" }],
    [{ id: "cepat1", method: "GET", path: "/cepat", headers: "{}", body: null, claim_token: "tok-c" }],
  ];
  const responses = new Map();
  const respondOrder = [];
  const pages = makeBatchPages(batches, responses, respondOrder);
  const pagesPort = await listen(pages);

  const tmp = mkdtempSync(join(tmpdir(), "hermuse-client-test3-"));
  const keyFile = join(tmp, "key");
  writeFileSync(keyFile, "testkey");
  const child = spawn("node", [join(root, "tunnel-client.mjs")], {
    env: {
      ...process.env,
      TUNNEL_BASE_URL: `http://127.0.0.1:${pagesPort}`,
      TUNNEL_KEY_FILE: keyFile,
      TUNNEL_LOCAL: `http://127.0.0.1:${backendPort}`,
      TUNNEL_LOCAL_TIMEOUT_MS: "10000",
      TUNNEL_POLL_MS: "50",
    },
    stdio: ["ignore", "pipe", "pipe"],
  });
  let stderr = "";
  child.stderr.on("data", (d) => (stderr += d));
  try {
    await waitFor(() => responses.size >= 2, 12000);
    // INTI: yang cepat selesai DULUAN walau masuk antrean belakangan.
    assert.deepEqual(respondOrder, ["cepat1", "lambat1"]);
    const cepat = responses.get("cepat1");
    assert.equal(cepat.status_code, 200);
    assert.equal(Buffer.from(cepat.body, "base64").toString(), "respons-cepat");
    // Stream lambat tetap diselesaikan utuh, tidak dibatalkan.
    const lambat = responses.get("lambat1");
    assert.equal(lambat.status_code, 200);
    assert.equal(Buffer.from(lambat.body, "base64").toString(), "bagian-selesai");
  } finally {
    child.kill("SIGKILL");
    pages.close(); backend.close();
    rmSync(tmp, { recursive: true, force: true });
    if (responses.size < 2) throw new Error("client tidak menyelesaikan 2 request. stderr: " + stderr);
  }
});

test("tunnel-client putaran 5: deadline body memotong stream macet -> 502, request lain tetap jalan", { timeout: 20000 }, async () => {
  // /stream-macet mengirim satu chunk lalu DIAM selamanya.
  const backend = createServer((req, res) => {
    if (req.url === "/stream-macet") {
      res.writeHead(200, { "content-type": "text/plain" });
      res.write("chunk-awal");
      // tidak pernah res.end()
    } else if (req.url === "/cepat") {
      res.writeHead(200, { "content-type": "text/plain" });
      res.end("respons-cepat");
    } else { res.writeHead(404); res.end(); }
  });
  const backendPort = await listen(backend);

  const batches = [
    [{ id: "macet1", method: "GET", path: "/stream-macet", headers: "{}", body: null, claim_token: "tok-m" }],
    [{ id: "cepat2", method: "GET", path: "/cepat", headers: "{}", body: null, claim_token: "tok-c2" }],
  ];
  const responses = new Map();
  const respondOrder = [];
  const pages = makeBatchPages(batches, responses, respondOrder);
  const pagesPort = await listen(pages);

  const tmp = mkdtempSync(join(tmpdir(), "hermuse-client-test4-"));
  const keyFile = join(tmp, "key");
  writeFileSync(keyFile, "testkey");
  const child = spawn("node", [join(root, "tunnel-client.mjs")], {
    env: {
      ...process.env,
      TUNNEL_BASE_URL: `http://127.0.0.1:${pagesPort}`,
      TUNNEL_KEY_FILE: keyFile,
      TUNNEL_LOCAL: `http://127.0.0.1:${backendPort}`,
      // Timeout fetch dibuat jauh lebih besar dari deadline body:
      // yang memotong stream macet HARUS deadline-nya, bukan timeout.
      TUNNEL_LOCAL_TIMEOUT_MS: "30000",
      TUNNEL_RESPONSE_DEADLINE_MS: "700",
      TUNNEL_POLL_MS: "50",
    },
    stdio: ["ignore", "pipe", "pipe"],
  });
  let stderr = "";
  child.stderr.on("data", (d) => (stderr += d));
  try {
    await waitFor(() => responses.size >= 2, 10000);
    const cepat = responses.get("cepat2");
    assert.equal(cepat.status_code, 200);
    // Stream macet dipotong deadline -> jalur error client (502)
    // dengan pesan deadline, BUKAN menggantung tanpa respons.
    const macet = responses.get("macet1");
    assert.equal(macet.status_code, 502);
    assert.match(Buffer.from(macet.body, "base64").toString(), /deadline/);
  } finally {
    child.kill("SIGKILL");
    pages.close();
    if (typeof backend.closeAllConnections === "function") backend.closeAllConnections();
    backend.close();
    rmSync(tmp, { recursive: true, force: true });
    if (responses.size < 2) throw new Error("client tidak menyelesaikan 2 request. stderr: " + stderr);
  }
});

test("tunnel-client: heartbeat selama backend lambat, health probe, cap respons D1", { timeout: 25000 }, async () => {
  // --- Backend stub: /v1/models (health), /slow-ok (1,2 dtk), /big (2 MB) ---
  let slowHits = 0;
  const backend = createServer((req, res) => {
    if (req.url === "/v1/models") { res.writeHead(200, { "content-type": "application/json" }); res.end("{}"); }
    else if (req.url === "/slow-ok") { slowHits++; setTimeout(() => { if (!res.destroyed) { res.writeHead(200); res.end("lambat-tapi-beres"); } }, 1200); }
    else if (req.url === "/big") { res.writeHead(200, { "content-type": "application/octet-stream" }); res.end(Buffer.alloc(2 * 1024 * 1024, 65)); }
    else { res.writeHead(404); res.end(); }
  });
  const backendPort = await listen(backend);

  // --- Pages stub dengan heartbeat ---
  const queue = [
    { id: "s1", method: "GET", path: "/slow-ok", headers: "{}", body: null, claim_token: "tok-s1" },
    { id: "h1", method: "GET", path: "/__tunnel-health", headers: JSON.stringify({ "x-health-nonce": "nonce-xyz" }), body: null, claim_token: "tok-h1" },
    { id: "b1", method: "GET", path: "/big", headers: "{}", body: null, claim_token: "tok-b1" },
  ];
  const responses = new Map();
  const heartbeats = [];
  const pages = createServer(async (req, res) => {
    const body = await readJson(req);
    if (req.url === "/__tunnel/poll") {
      const out = queue.splice(0, queue.length);
      res.writeHead(200, { "content-type": "application/json" });
      res.end(JSON.stringify({ requests: out }));
    } else if (req.url === "/__tunnel/respond") {
      responses.set(body.id, body);
      res.writeHead(200, { "content-type": "application/json" });
      res.end(JSON.stringify({ ok: true }));
    } else if (req.url === "/__tunnel/heartbeat") {
      heartbeats.push(body);
      res.writeHead(200, { "content-type": "application/json" });
      res.end(JSON.stringify({ ok: true }));
    } else { res.writeHead(404); res.end(); }
  });
  const pagesPort = await listen(pages);

  const tmp = mkdtempSync(join(tmpdir(), "hermuse-client-test2-"));
  const keyFile = join(tmp, "key");
  writeFileSync(keyFile, "testkey");
  const child = spawn("node", [join(root, "tunnel-client.mjs")], {
    env: {
      ...process.env,
      TUNNEL_BASE_URL: `http://127.0.0.1:${pagesPort}`,
      TUNNEL_KEY_FILE: keyFile,
      TUNNEL_LOCAL: `http://127.0.0.1:${backendPort}`,
      TUNNEL_LOCAL_TIMEOUT_MS: "5000",
      TUNNEL_HEARTBEAT_MS: "250",
      TUNNEL_POLL_MS: "50",
    },
    stdio: ["ignore", "pipe", "pipe"],
  });
  let stderr = "";
  child.stderr.on("data", (d) => (stderr += d));
  try {
    await waitFor(() => responses.size >= 3, 15000);
    // Heartbeat: request lambat 1,2 dtk dengan interval 250 mdtk harus
    // memicu beberapa perpanjangan lease untuk klaim yang sama.
    const hbS1 = heartbeats.filter((h) => h.id === "s1" && h.claim_token === "tok-s1");
    assert.ok(hbS1.length >= 2, `heartbeat s1 hanya ${hbS1.length}x`);
    assert.equal(slowHits, 1); // backend lambat dikerjakan tepat sekali
    const s1 = responses.get("s1");
    assert.equal(s1.status_code, 200);
    assert.equal(Buffer.from(s1.body, "base64").toString(), "lambat-tapi-beres");
    // Health probe: nonce ter-echo + backend_ok dari /v1/models backend.
    const h1 = responses.get("h1");
    assert.equal(h1.status_code, 200);
    const health = JSON.parse(Buffer.from(h1.body, "base64").toString());
    assert.equal(health.nonce, "nonce-xyz");
    assert.equal(health.backend_ok, true);
    assert.equal(health.backend_status, 200);
    // Respons backend 2 MB melewati kapasitas D1 -> 502, bukan dikirim.
    const b1 = responses.get("b1");
    assert.equal(b1.status_code, 502);
  } finally {
    child.kill("SIGKILL");
    pages.close(); backend.close();
    rmSync(tmp, { recursive: true, force: true });
    if (responses.size < 3) throw new Error("client tidak menyelesaikan 3 request. stderr: " + stderr);
  }
});

test("tunnel-client putaran 6: stream 45 dtk lolos pada timeout DEFAULT (header cepat, body lambat)", { timeout: 150000 }, async () => {
  // Backend SSE: header dikirim SEKETIKA, lalu body menetes 1 chunk
  // per detik selama 45 detik — pola streaming LLM sungguhan.
  // Cacat putaran 6 di kode lama: AbortSignal.timeout(LOCAL_TIMEOUT_MS)
  // (default 30000) tetap aktif selama body dibaca, jadi stream ini
  // dibatalkan di detik ke-30 -> 502, walau deadline body resmi
  // (TUNNEL_RESPONSE_DEADLINE_MS) 120000.
  const CHUNKS = 45;
  const expected = Array.from({ length: CHUNKS }, (_, i) => `data: chunk-${i + 1}\n\n`).join("");
  const backend = createServer((req, res) => {
    if (req.url === "/stream-panjang") {
      res.writeHead(200, { "content-type": "text/event-stream" });
      res.flushHeaders(); // header keluar sekarang; body menyusul pelan-pelan
      let i = 0;
      const iv = setInterval(() => {
        i++;
        if (res.destroyed) { clearInterval(iv); return; }
        res.write(`data: chunk-${i}\n\n`);
        if (i >= CHUNKS) { clearInterval(iv); res.end(); }
      }, 1000);
      res.on("close", () => clearInterval(iv));
    } else { res.writeHead(404); res.end(); }
  });
  const backendPort = await listen(backend);

  const batches = [
    [{ id: "sse1", method: "GET", path: "/stream-panjang", headers: "{}", body: null, claim_token: "tok-sse" }],
  ];
  const responses = new Map();
  const respondOrder = [];
  const pages = makeBatchPages(batches, responses, respondOrder);
  const pagesPort = await listen(pages);

  const tmp = mkdtempSync(join(tmpdir(), "hermuse-client-test6-"));
  const keyFile = join(tmp, "key");
  writeFileSync(keyFile, "testkey");
  // KONFIGURASI DEFAULT untuk kedua timeout: kedua env SENGAJA tidak
  // di-set (dan dibuang dari warisan process.env) — yang diuji adalah
  // perilaku bawaan produksi, bukan nilai kecil ala tes.
  const env = { ...process.env };
  delete env.TUNNEL_LOCAL_TIMEOUT_MS;
  delete env.TUNNEL_RESPONSE_DEADLINE_MS;
  Object.assign(env, {
    TUNNEL_BASE_URL: `http://127.0.0.1:${pagesPort}`,
    TUNNEL_KEY_FILE: keyFile,
    TUNNEL_LOCAL: `http://127.0.0.1:${backendPort}`,
    TUNNEL_POLL_MS: "50",
  });
  const startedAt = Date.now();
  const child = spawn("node", [join(root, "tunnel-client.mjs")], {
    env,
    stdio: ["ignore", "pipe", "pipe"],
  });
  let stderr = "";
  child.stderr.on("data", (d) => (stderr += d));
  try {
    await waitFor(() => responses.size >= 1, 100000);
    const elapsed = Date.now() - startedAt;
    const r = responses.get("sse1");
    // Stream utuh 45 dtk: melewati AMBANG 40 dtk (dan timeout lama 30
    // dtk) tanpa dibatalkan, body lengkap persis seperti dikirim.
    assert.ok(elapsed > 40000, `stream selesai terlalu cepat: ${elapsed}ms`);
    assert.equal(r.status_code, 200);
    assert.equal(Buffer.from(r.body, "base64").toString(), expected);
  } finally {
    child.kill("SIGKILL");
    pages.close();
    if (typeof backend.closeAllConnections === "function") backend.closeAllConnections();
    backend.close();
    rmSync(tmp, { recursive: true, force: true });
    if (responses.size < 1) throw new Error("client tidak menyelesaikan request SSE. stderr: " + stderr);
  }
});
