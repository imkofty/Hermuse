// Test tunnel-client.mjs sebagai PROSES SUNGGUHAN melawan dua server stub:
//   - "Pages" stub: endpoint /__tunnel/poll & /__tunnel/respond in-memory.
//   - Backend stub: target lokal client (pengganti 9Router).
// Membuktikan temuan audit yang tidak bisa diuji dari fungsi Pages saja:
//   1. Redirect backend TIDAK diikuti (302 diteruskan apa adanya; server
//      tujuan redirect tidak pernah tersentuh) — regresi SSRF-via-redirect.
//   2. Backend yang menggantung kena timeout client -> pemanggil menerima
//      502 dari jalur error client, bukan menggantung selamanya.
//   3. Respons normal diteruskan utuh (status + body).
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
