// Test keamanan & korektness tunnel (Pages Functions + D1 queue).
// Menjalankan file fungsi ASLI melawan SQLite sungguhan (node:sqlite)
// lewat FakeD1 — regresi untuk temuan audit 2026-10-20:
//   1. auth fail-open saat TUNNEL_KEY tidak ter-set di server
//   2. race double-processing klaim (SELECT lalu UPDATE terpisah)
//   3. respond dari bukan pemegang klaim / klaim basi
//   4. body request tanpa batas di [[path]]
// Jalankan: node --test tests/
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath, pathToFileURL } from "node:url";
import { dirname, join } from "node:path";
import { FakeD1 } from "./helpers/fake-d1.mjs";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const schema = readFileSync(join(root, "tunnel/schema.sql"), "utf8");
const poll = await import(pathToFileURL(join(root, "tunnel/pages-tunnel/functions/__tunnel/poll.js")));
const respond = await import(pathToFileURL(join(root, "tunnel/pages-tunnel/functions/__tunnel/respond.js")));
const result = await import(pathToFileURL(join(root, "tunnel/pages-tunnel/functions/__tunnel/result.js")));
const ingress = await import(pathToFileURL(join(root, "tunnel/pages-tunnel/functions/[[path]].js")));

const KEY = "test-secret";
function makeEnv(withKey = true) {
  return { DB: new FakeD1(schema), ...(withKey ? { TUNNEL_KEY: KEY } : {}) };
}
function postReq(body) {
  return new Request("https://tunnel.example/__tunnel/x", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body ?? {}),
  });
}
function seedPending(env, id, ageMs = 0) {
  env.DB.rawRun(
    "INSERT INTO tunnel_requests (id, method, path, headers, body, status, created_at) VALUES (?,?,?,?,?,'pending',?)",
    id, "GET", "/dashboard", "{}", null, Date.now() - ageMs
  );
}

test("poll menolak bila TUNNEL_KEY tidak ter-set di server (fail-closed)", async () => {
  const env = makeEnv(false);
  const res = await poll.onRequestPost({ request: postReq({}), env });
  assert.equal(res.status, 403);
});

test("respond menolak bila TUNNEL_KEY tidak ter-set di server (fail-closed)", async () => {
  const env = makeEnv(false);
  const res = await respond.onRequestPost({
    request: postReq({ id: "x", claim_token: "y", status_code: 200 }), env,
  });
  assert.equal(res.status, 403);
});

test("poll menolak key yang salah", async () => {
  const env = makeEnv();
  const res = await poll.onRequestPost({ request: postReq({ key: "salah" }), env });
  assert.equal(res.status, 403);
});

test("klaim atomik: dua poller tidak pernah menerima request yang sama", async () => {
  const env = makeEnv();
  seedPending(env, "r1"); seedPending(env, "r2"); seedPending(env, "r3");
  const a = await (await poll.onRequestPost({ request: postReq({ key: KEY, limit: 2 }), env })).json();
  const b = await (await poll.onRequestPost({ request: postReq({ key: KEY, limit: 2 }), env })).json();
  const idsA = a.requests.map((r) => r.id);
  const idsB = b.requests.map((r) => r.id);
  assert.equal(idsA.length, 2);
  assert.equal(idsB.length, 1);
  assert.deepEqual(idsA.filter((id) => idsB.includes(id)), []);
  // claim_token terbit & berbeda antar poller
  assert.ok(a.requests[0].claim_token);
  assert.notEqual(a.requests[0].claim_token, b.requests[0].claim_token);
});

test("respond hanya diterima dari pemegang klaim yang sah", async () => {
  const env = makeEnv();
  seedPending(env, "r1");
  const { requests } = await (await poll.onRequestPost({ request: postReq({ key: KEY, limit: 1 }), env })).json();
  assert.equal(requests.length, 1);
  const token = requests[0].claim_token;

  const wrong = await respond.onRequestPost({
    request: postReq({ key: KEY, id: "r1", claim_token: "token-orang-lain", status_code: 200, body: "eA==" }), env,
  });
  assert.equal(wrong.status, 409);

  const ok = await respond.onRequestPost({
    request: postReq({ key: KEY, id: "r1", claim_token: token, status_code: 200, headers: {}, body: "eA==" }), env,
  });
  assert.equal(ok.status, 200);
});

test("klaim basi direbut kembali setelah lease lewat; token lama ditolak", async () => {
  const env = makeEnv();
  seedPending(env, "r1");
  const first = await (await poll.onRequestPost({ request: postReq({ key: KEY, limit: 1 }), env })).json();
  const oldToken = first.requests[0].claim_token;
  // Paksa klaim jadi basi (melewati LEASE_MS 45 dtk)
  env.DB.rawRun("UPDATE tunnel_requests SET claimed_at=? WHERE id='r1'", Date.now() - 60000);
  const second = await (await poll.onRequestPost({ request: postReq({ key: KEY, limit: 1 }), env })).json();
  assert.equal(second.requests.length, 1);
  assert.equal(second.requests[0].id, "r1");
  assert.notEqual(second.requests[0].claim_token, oldToken);
  const stale = await respond.onRequestPost({
    request: postReq({ key: KEY, id: "r1", claim_token: oldToken, status_code: 200 }), env,
  });
  assert.equal(stale.status, 409);
});

test("round trip penuh: ingress -> poll -> respond -> pemanggil menerima respons", async () => {
  const env = makeEnv();
  const callPromise = ingress.onRequest({
    request: new Request("https://tunnel.example/dashboard", { method: "GET" }), env,
  });
  // Beri waktu ingress memasukkan request ke antrean
  await new Promise((r) => setTimeout(r, 300));
  const { requests } = await (await poll.onRequestPost({ request: postReq({ key: KEY, limit: 1 }), env })).json();
  assert.equal(requests.length, 1);
  assert.equal(requests[0].path, "/dashboard");
  const res = await respond.onRequestPost({
    request: postReq({
      key: KEY, id: requests[0].id, claim_token: requests[0].claim_token,
      status_code: 200, headers: { "content-type": "text/plain" },
      body: Buffer.from("halo dashboard").toString("base64"),
    }), env,
  });
  assert.equal(res.status, 200);
  const final = await callPromise;
  assert.equal(final.status, 200);
  assert.equal(await final.text(), "halo dashboard");
});

test("ingress menolak body yang melebihi batas (413)", async () => {
  const env = makeEnv();
  const res = await ingress.onRequest({
    request: new Request("https://tunnel.example/upload", {
      method: "POST",
      headers: { "content-length": String(7 * 1024 * 1024) },
      body: "x",
    }), env,
  });
  assert.equal(res.status, 413);
});

// --- Putaran 2 (audit lanjutan 2026-10-20) ---

test("klaim konkuren: 5 poller serentak, 25 request, tidak ada yang ganda", async () => {
  const env = makeEnv();
  for (let i = 0; i < 25; i++) seedPending(env, "c" + i);
  // Semua poller dimulai SEBELUM satu pun selesai (barrier Promise.all);
  // klaim yang tidak atomik akan membocorkan id yang sama ke >1 poller.
  const pollers = Array.from({ length: 5 }, () =>
    poll.onRequestPost({ request: postReq({ key: KEY, limit: 5 }), env }).then((r) => r.json()));
  const results = await Promise.all(pollers);
  const ids = results.flatMap((r) => r.requests.map((x) => x.id));
  assert.equal(ids.length, 25);
  assert.equal(new Set(ids).size, 25);
});

test("migrasi 001+002 di atas skema lama: kolom bertambah, data lama utuh", async () => {
  const oldSchema =
    "CREATE TABLE tunnel_requests (id TEXT PRIMARY KEY, method TEXT, path TEXT, headers TEXT, body TEXT, status TEXT, created_at INTEGER);" +
    "CREATE TABLE tunnel_responses (id TEXT PRIMARY KEY, status_code INTEGER, headers TEXT, body TEXT, created_at INTEGER);";
  const db = new FakeD1(oldSchema);
  db.rawRun(
    "INSERT INTO tunnel_requests (id, method, path, headers, body, status, created_at) VALUES ('old1','GET','/x','{}',NULL,'pending',?)",
    Date.now()
  );
  const runMig = (file) => {
    // Buang komentar dari SELURUH file dulu (komentar boleh mengandung
    // titik koma), baru potong per statement.
    const sql = readFileSync(join(root, file), "utf8").replace(/--.*$/gm, "");
    for (const stmt of sql.split(";")) {
      const clean = stmt.trim();
      if (clean) db.db.exec(clean);
    }
  };
  runMig("tunnel/migrations/001-claim-lease.sql");
  runMig("tunnel/migrations/002-idempotency-ratelimit.sql");
  const cols = db.raw("PRAGMA table_info(tunnel_requests)").map((r) => r.name);
  for (const c of ["claim_token", "claimed_at", "idempotency_key"])
    assert.ok(cols.includes(c), "kolom hilang: " + c);
  assert.equal(db.raw("SELECT id FROM tunnel_requests").length, 1);
  const tables = db.raw("SELECT name FROM sqlite_master WHERE type='table'").map((r) => r.name);
  assert.ok(tables.includes("tunnel_rate_limits"));
});

test("ingress menolak body streaming tanpa content-length yang melewati batas (413)", async () => {
  const env = makeEnv();
  const chunk = new Uint8Array(2 * 1024 * 1024).fill(120);
  let n = 0;
  const stream = new ReadableStream({
    pull(c) { if (++n <= 4) c.enqueue(chunk); else c.close(); },
  });
  const res = await ingress.onRequest({
    request: new Request("https://tunnel.example/upload", {
      method: "POST", body: stream, duplex: "half",
    }), env,
  });
  assert.equal(res.status, 413);
});

test("timeout ingress tidak membatalkan request; hasil diambil via /__tunnel/result", async () => {
  const env = { ...makeEnv(), INGRESS_WAIT_MS: "600" };
  const res = await ingress.onRequest({
    request: new Request("https://tunnel.example/lambat", { method: "GET" }), env,
  });
  assert.equal(res.status, 504);
  const id = res.headers.get("x-tunnel-request-id");
  assert.ok(id);
  // Request masih hidup di antrean setelah pemanggil menyerah.
  assert.equal(Number(env.DB.raw("SELECT COUNT(*) AS n FROM tunnel_requests WHERE id=?", id)[0].n), 1);
  const before = await result.onRequestGet({
    request: new Request(`https://tunnel.example/__tunnel/result?id=${id}`), env,
  });
  assert.equal(before.status, 202);
  // Client lokal memprosesnya belakangan; hasilnya tetap terkirim.
  const { requests } = await (await poll.onRequestPost({ request: postReq({ key: KEY, limit: 1 }), env })).json();
  assert.equal(requests[0].id, id);
  const rr = await respond.onRequestPost({
    request: postReq({
      key: KEY, id, claim_token: requests[0].claim_token, status_code: 200,
      headers: { "content-type": "text/plain" },
      body: Buffer.from("hasil lambat").toString("base64"),
    }), env,
  });
  assert.equal(rr.status, 200);
  const after = await result.onRequestGet({
    request: new Request(`https://tunnel.example/__tunnel/result?id=${id}`), env,
  });
  assert.equal(after.status, 200);
  assert.equal(await after.text(), "hasil lambat");
});

test("idempotency-key: kiriman ulang tidak membuat request kedua", async () => {
  const env = { ...makeEnv(), INGRESS_WAIT_MS: "5000" };
  const mk = () => new Request("https://tunnel.example/v1/chat/completions", {
    method: "POST",
    headers: { "content-type": "application/json", "idempotency-key": "key-123" },
    body: JSON.stringify({ model: "x" }),
  });
  const p1 = ingress.onRequest({ request: mk(), env });
  await new Promise((r) => setTimeout(r, 300));
  const p2 = ingress.onRequest({ request: mk(), env });
  await new Promise((r) => setTimeout(r, 300));
  assert.equal(Number(env.DB.raw("SELECT COUNT(*) AS n FROM tunnel_requests")[0].n), 1);
  const { requests } = await (await poll.onRequestPost({ request: postReq({ key: KEY, limit: 4 }), env })).json();
  assert.equal(requests.length, 1);
  await respond.onRequestPost({
    request: postReq({
      key: KEY, id: requests[0].id, claim_token: requests[0].claim_token,
      status_code: 200, headers: {}, body: Buffer.from("ok").toString("base64"),
    }), env,
  });
  const [r1, r2] = await Promise.all([p1, p2]);
  assert.equal(r1.status, 200);
  assert.equal(r2.status, 200);
  assert.equal(await r1.text(), "ok");
  assert.equal(await r2.text(), "ok");
});

test("rate limit per IP: request ke-4 dalam semenit ditolak 429", async () => {
  const env = { ...makeEnv(), RATE_LIMIT_PER_MIN: "3", INGRESS_WAIT_MS: "200" };
  const mk = () => new Request("https://tunnel.example/dashboard", {
    method: "GET", headers: { "cf-connecting-ip": "1.2.3.4" },
  });
  for (let i = 0; i < 3; i++) {
    const res = await ingress.onRequest({ request: mk(), env });
    assert.equal(res.status, 504); // lolos rate limit; timeout karena tak ada client
  }
  const res4 = await ingress.onRequest({ request: mk(), env });
  assert.equal(res4.status, 429);
});

test("gate password: dashboard wajib Basic auth, /v1 tetap untuk API key", async () => {
  const env = { ...makeEnv(), GATE_PASSWORD: "s3cret", INGRESS_WAIT_MS: "200" };
  const noAuth = await ingress.onRequest({
    request: new Request("https://tunnel.example/dashboard"), env,
  });
  assert.equal(noAuth.status, 401);
  const badAuth = await ingress.onRequest({
    request: new Request("https://tunnel.example/dashboard", {
      headers: { authorization: "Basic " + Buffer.from("hermuse:salah").toString("base64") },
    }), env,
  });
  assert.equal(badAuth.status, 401);
  const okAuth = await ingress.onRequest({
    request: new Request("https://tunnel.example/dashboard", {
      headers: { authorization: "Basic " + Buffer.from("hermuse:s3cret").toString("base64") },
    }), env,
  });
  assert.equal(okAuth.status, 504); // lolos gate -> menunggu tunnel (tak ada client)
  const api = await ingress.onRequest({
    request: new Request("https://tunnel.example/v1/models"), env,
  });
  assert.equal(api.status, 504); // path API tidak kena gate
});

test("gate fail-closed: REQUIRE_GATE=1 tanpa GATE_PASSWORD -> 500", async () => {
  const env = { ...makeEnv(), REQUIRE_GATE: "1", INGRESS_WAIT_MS: "200" };
  const res = await ingress.onRequest({
    request: new Request("https://tunnel.example/dashboard"), env,
  });
  assert.equal(res.status, 500);
});

test("respond ke request yang tidak ada -> 409 (validasi atomik)", async () => {
  const env = makeEnv();
  const res = await respond.onRequestPost({
    request: postReq({ key: KEY, id: "tidak-ada", claim_token: "apapun", status_code: 200 }), env,
  });
  assert.equal(res.status, 409);
});
