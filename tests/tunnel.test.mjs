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
const heartbeat = await import(pathToFileURL(join(root, "tunnel/pages-tunnel/functions/__tunnel/heartbeat.js")));
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
  // Sejak putaran 5 dedup/replay hanya berlaku untuk principal
  // TERVERIFIKASI — tes ini memakai Authorization agar tetap menguji
  // perilaku dedup saat antre (anon diuji terpisah di bagian putaran 5).
  const mk = () => new Request("https://tunnel.example/v1/chat/completions", {
    method: "POST",
    headers: { "content-type": "application/json", "idempotency-key": "key-123", authorization: "Bearer kunci-tes" },
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

// --- Putaran 3 (audit lanjutan 2026-10-20) ---

test("batas payload = kapasitas D1: 1.350.000 byte lolos, 1.350.001 ditolak 413", async () => {
  const env = { ...makeEnv(), INGRESS_WAIT_MS: "200" };
  const mk = (n) => new Request("https://tunnel.example/upload", {
    method: "POST", headers: { "content-length": String(n) }, body: "x",
  });
  const atLimit = await ingress.onRequest({ request: mk(1350000), env });
  assert.notEqual(atLimit.status, 413); // masuk antrean (504: tak ada client)
  const overLimit = await ingress.onRequest({ request: mk(1350001), env });
  assert.equal(overLimit.status, 413);
});

test("respond menolak body Base64 melewati kapasitas D1 (413), tepat di batas lolos", async () => {
  const env = makeEnv();
  seedPending(env, "big1");
  const { requests } = await (await poll.onRequestPost({ request: postReq({ key: KEY, limit: 1 }), env })).json();
  const token = requests[0].claim_token;
  const over = await respond.onRequestPost({
    request: postReq({ key: KEY, id: "big1", claim_token: token, status_code: 200, body: "A".repeat(1800001) }), env,
  });
  assert.equal(over.status, 413);
  const atLimit = await respond.onRequestPost({
    request: postReq({ key: KEY, id: "big1", claim_token: token, status_code: 200, body: "A".repeat(1800000) }), env,
  });
  assert.equal(atLimit.status, 200);
});

test("idempotency SETELAH pengiriman: retry key sama dilayani dari respons, tanpa request baru", async () => {
  const env = { ...makeEnv(), INGRESS_WAIT_MS: "5000" };
  // Replay pasca-pengiriman sejak putaran 5 khusus principal
  // terverifikasi — tes ini membawa Authorization (perilaku anon:
  // selalu diproses segar, lihat bagian putaran 5).
  const mk = () => new Request("https://tunnel.example/v1/chat/completions", {
    method: "POST",
    headers: { "content-type": "application/json", "idempotency-key": "key-selesai", authorization: "Bearer kunci-tes" },
    body: JSON.stringify({ model: "x" }),
  });
  const p1 = ingress.onRequest({ request: mk(), env });
  await new Promise((r) => setTimeout(r, 300));
  const { requests } = await (await poll.onRequestPost({ request: postReq({ key: KEY, limit: 1 }), env })).json();
  assert.equal(requests.length, 1);
  await respond.onRequestPost({
    request: postReq({
      key: KEY, id: requests[0].id, claim_token: requests[0].claim_token,
      status_code: 200, headers: {}, body: Buffer.from("jawaban").toString("base64"),
    }), env,
  });
  const r1 = await p1;
  assert.equal(r1.status, 200);
  assert.equal(await r1.text(), "jawaban");
  // Baris request sudah terhapus oleh pengiriman pertama.
  assert.equal(Number(env.DB.raw("SELECT COUNT(*) AS n FROM tunnel_requests")[0].n), 0);
  // Retry SETELAH sukses: harus menerima jawaban yang sama TANPA
  // request baru (efek samping tidak boleh berulang).
  const r2 = await ingress.onRequest({ request: mk(), env });
  assert.equal(r2.status, 200);
  assert.equal(await r2.text(), "jawaban");
  assert.equal(Number(env.DB.raw("SELECT COUNT(*) AS n FROM tunnel_requests")[0].n), 0);
});

test("heartbeat memperpanjang lease: klaim yang diperpanjang tidak direbut poller lain", async () => {
  const env = makeEnv();
  seedPending(env, "h1");
  const { requests } = await (await poll.onRequestPost({ request: postReq({ key: KEY, limit: 1 }), env })).json();
  const token = requests[0].claim_token;
  // Umur klaim dibuat 40 dtk: melewati lease lama 30 dtk (dulu direbut),
  // belum melewati lease baru 45 dtk.
  env.DB.rawRun("UPDATE tunnel_requests SET claimed_at=? WHERE id='h1'", Date.now() - 40000);
  const hb = await heartbeat.onRequestPost({
    request: postReq({ key: KEY, id: "h1", claim_token: token }), env,
  });
  assert.equal(hb.status, 200);
  const row = env.DB.raw("SELECT claimed_at FROM tunnel_requests WHERE id='h1'")[0];
  assert.ok(Date.now() - Number(row.claimed_at) < 5000, "claimed_at harus segar setelah heartbeat");
  // Poller lain hanya boleh menerima request pending LAIN, bukan h1.
  seedPending(env, "h2");
  const other = await (await poll.onRequestPost({ request: postReq({ key: KEY, limit: 4 }), env })).json();
  assert.deepEqual(other.requests.map((r) => r.id), ["h2"]);
});

test("heartbeat token salah / klaim hilang -> 409 & fail-closed tanpa TUNNEL_KEY", async () => {
  const env = makeEnv();
  seedPending(env, "h1");
  const { requests } = await (await poll.onRequestPost({ request: postReq({ key: KEY, limit: 1 }), env })).json();
  const wrong = await heartbeat.onRequestPost({
    request: postReq({ key: KEY, id: "h1", claim_token: "bukan-tokennya" }), env,
  });
  assert.equal(wrong.status, 409);
  const noKey = await heartbeat.onRequestPost({
    request: postReq({ key: KEY, id: "h1", claim_token: requests[0].claim_token }),
    env: makeEnv(false),
  });
  assert.equal(noKey.status, 403);
});

test("health probe: tanpa/salah health-key -> 403; key benar -> request masuk antrean tunnel", async () => {
  const env = { ...makeEnv(), HEALTH_KEY: "health-secret", INGRESS_WAIT_MS: "300" };
  const noKey = await ingress.onRequest({
    request: new Request("https://tunnel.example/__tunnel-health"), env,
  });
  assert.equal(noKey.status, 403);
  const wrongKey = await ingress.onRequest({
    request: new Request("https://tunnel.example/__tunnel-health", {
      headers: { "x-tunnel-health-key": "salah" },
    }), env,
  });
  assert.equal(wrongKey.status, 403);
  const ok = await ingress.onRequest({
    request: new Request("https://tunnel.example/__tunnel-health", {
      headers: { "x-tunnel-health-key": "health-secret", "x-health-nonce": "n-1" },
    }), env,
  });
  assert.equal(ok.status, 504); // lolos auth -> menunggu client (tak ada client)
  const rows = env.DB.raw("SELECT path FROM tunnel_requests");
  assert.equal(rows.length, 1);
  assert.equal(rows[0].path, "/__tunnel-health");
  // HEALTH_KEY tidak ter-set di server = fail-closed juga.
  const envNoKey = { ...makeEnv(), INGRESS_WAIT_MS: "300" };
  const closed = await ingress.onRequest({
    request: new Request("https://tunnel.example/__tunnel-health", {
      headers: { "x-tunnel-health-key": "apapun" },
    }), env: envNoKey,
  });
  assert.equal(closed.status, 403);
});

// --- Putaran 4 (audit lanjutan 2026-10-20): idempotency terikat pemanggil ---

// Selesaikan satu request yang sedang antre: klaim via poll lalu respond.
async function completeNext(env, bodyText) {
  const { requests } = await (await poll.onRequestPost({ request: postReq({ key: KEY, limit: 1 }), env })).json();
  assert.equal(requests.length, 1);
  const rr = await respond.onRequestPost({
    request: postReq({
      key: KEY, id: requests[0].id, claim_token: requests[0].claim_token,
      status_code: 200, headers: {}, body: Buffer.from(bodyText).toString("base64"),
    }), env,
  });
  assert.equal(rr.status, 200);
  return requests[0];
}

const idemReq = (auth, key, payload) => new Request("https://tunnel.example/v1/chat/completions", {
  method: "POST",
  headers: {
    "content-type": "application/json",
    "idempotency-key": key,
    ...(auth ? { authorization: auth } : {}),
  },
  body: JSON.stringify(payload),
});

test("putaran 4 (a): replay pemanggil sama + request sama dilayani dari respons, backend tidak kena lagi", async () => {
  const env = { ...makeEnv(), INGRESS_WAIT_MS: "5000" };
  const auth = "Bearer kunci-pemanggil-A";
  const p1 = ingress.onRequest({ request: idemReq(auth, "key-r4", { model: "x" }), env });
  await new Promise((r) => setTimeout(r, 300));
  await completeNext(env, "jawaban-A");
  const r1 = await p1;
  assert.equal(r1.status, 200);
  assert.equal(await r1.text(), "jawaban-A");
  // Yang tersimpan adalah HASH principal — kredensial mentah tidak bocor ke DB.
  const stored = env.DB.raw("SELECT idem_principal, idem_fingerprint FROM tunnel_responses")[0];
  assert.ok(stored.idem_principal.startsWith("auth:"));
  assert.ok(!stored.idem_principal.includes("kunci-pemanggil-A"));
  assert.ok(stored.idem_fingerprint.includes("/v1/chat/completions"));
  // Retry identik: replay langsung, TIDAK ada request baru.
  const r2 = await ingress.onRequest({ request: idemReq(auth, "key-r4", { model: "x" }), env });
  assert.equal(r2.status, 200);
  assert.equal(await r2.text(), "jawaban-A");
  assert.equal(Number(env.DB.raw("SELECT COUNT(*) AS n FROM tunnel_requests")[0].n), 0);
});

test("putaran 4 (b): key sama, principal beda SETELAH pengiriman -> TIDAK replay, diproses baru", async () => {
  const env = { ...makeEnv(), INGRESS_WAIT_MS: "5000" };
  const pA = ingress.onRequest({ request: idemReq("Bearer kunci-A", "key-sama", { model: "x" }), env });
  await new Promise((r) => setTimeout(r, 300));
  await completeNext(env, "jawaban-A");
  assert.equal(await (await pA).text(), "jawaban-A");
  // Pemanggil B memakai key yang sama: TIDAK boleh menerima respons A.
  const pB = ingress.onRequest({ request: idemReq("Bearer kunci-B", "key-sama", { model: "x" }), env });
  await new Promise((r) => setTimeout(r, 300));
  assert.equal(Number(env.DB.raw("SELECT COUNT(*) AS n FROM tunnel_requests")[0].n), 1);
  await completeNext(env, "jawaban-B");
  const rB = await pB;
  assert.equal(rB.status, 200);
  assert.equal(await rB.text(), "jawaban-B");
});

test("putaran 4 (b2): key sama, principal beda SEDANG antre -> dua request terpisah", async () => {
  const env = { ...makeEnv(), INGRESS_WAIT_MS: "5000" };
  const pA = ingress.onRequest({ request: idemReq("Bearer kunci-A", "key-antre", { model: "x" }), env });
  await new Promise((r) => setTimeout(r, 300));
  const pB = ingress.onRequest({ request: idemReq("Bearer kunci-B", "key-antre", { model: "x" }), env });
  await new Promise((r) => setTimeout(r, 300));
  // B tidak menempel ke request A: dua baris antrean berbeda principal.
  const rows = env.DB.raw("SELECT idem_principal FROM tunnel_requests");
  assert.equal(rows.length, 2);
  assert.equal(new Set(rows.map((r) => r.idem_principal)).size, 2);
  const { requests } = await (await poll.onRequestPost({ request: postReq({ key: KEY, limit: 4 }), env })).json();
  assert.equal(requests.length, 2);
  for (const q of requests) {
    await respond.onRequestPost({
      request: postReq({
        key: KEY, id: q.id, claim_token: q.claim_token, status_code: 200,
        headers: {}, body: Buffer.from("ok").toString("base64"),
      }), env,
    });
  }
  assert.equal((await pA).status, 200);
  assert.equal((await pB).status, 200);
});

test("putaran 4 (c): key+principal sama, body beda -> 409 (saat antre & setelah pengiriman)", async () => {
  const env = { ...makeEnv(), INGRESS_WAIT_MS: "5000" };
  const auth = "Bearer kunci-A";
  const p1 = ingress.onRequest({ request: idemReq(auth, "key-konflik", { model: "x" }), env });
  await new Promise((r) => setTimeout(r, 300));
  // Masih antre, key+principal sama tapi payload beda -> 409 langsung.
  const inflight = await ingress.onRequest({ request: idemReq(auth, "key-konflik", { model: "LAIN" }), env });
  assert.equal(inflight.status, 409);
  assert.match(await inflight.text(), /idempotency key conflict/);
  await completeNext(env, "jawaban-1");
  assert.equal((await p1).status, 200);
  // Setelah pengiriman pun sama: payload beda dengan key yang sama -> 409,
  // BUKAN replay dan bukan request baru.
  const after = await ingress.onRequest({ request: idemReq(auth, "key-konflik", { model: "LAIN" }), env });
  assert.equal(after.status, 409);
  assert.equal(Number(env.DB.raw("SELECT COUNT(*) AS n FROM tunnel_requests")[0].n), 0);
  // Sedangkan retry yang benar-benar identik tetap replay.
  const replay = await ingress.onRequest({ request: idemReq(auth, "key-konflik", { model: "x" }), env });
  assert.equal(replay.status, 200);
  assert.equal(await replay.text(), "jawaban-1");
});

test("putaran 4: migrasi 004 di atas 001+002+003 — kolom principal/fingerprint + index unik gabungan", async () => {
  const db = new FakeD1(
    "CREATE TABLE tunnel_requests (id TEXT PRIMARY KEY, method TEXT, path TEXT, headers TEXT, body TEXT, status TEXT, created_at INTEGER);" +
    "CREATE TABLE tunnel_responses (id TEXT PRIMARY KEY, status_code INTEGER, headers TEXT, body TEXT, created_at INTEGER);"
  );
  const runMig = (file) => {
    const sql = readFileSync(join(root, file), "utf8").replace(/--.*$/gm, "");
    for (const stmt of sql.split(";")) {
      const clean = stmt.trim();
      if (clean) db.db.exec(clean);
    }
  };
  runMig("tunnel/migrations/001-claim-lease.sql");
  runMig("tunnel/migrations/002-idempotency-ratelimit.sql");
  runMig("tunnel/migrations/003-response-idempotency.sql");
  runMig("tunnel/migrations/004-idempotency-principal.sql");
  for (const tbl of ["tunnel_requests", "tunnel_responses"]) {
    const cols = db.raw(`PRAGMA table_info(${tbl})`).map((r) => r.name);
    assert.ok(cols.includes("idem_principal"), tbl + ": idem_principal hilang");
    assert.ok(cols.includes("idem_fingerprint"), tbl + ": idem_fingerprint hilang");
  }
  // Index unik kini GABUNGAN: key sama untuk dua principal berbeda sah,
  // key+principal yang sama tetap ditolak.
  db.rawRun("INSERT INTO tunnel_responses (id, idempotency_key, idem_principal) VALUES ('x1','k','auth:aaa')");
  db.rawRun("INSERT INTO tunnel_responses (id, idempotency_key, idem_principal) VALUES ('x2','k','auth:bbb')");
  assert.throws(() =>
    db.rawRun("INSERT INTO tunnel_responses (id, idempotency_key, idem_principal) VALUES ('x3','k','auth:aaa')"));
  assert.equal(db.raw("SELECT COUNT(*) AS n FROM tunnel_responses")[0].n, 2);
});

test("migrasi 003 di atas 001+002: kolom idempotency respons + index unik", async () => {
  const db = new FakeD1(
    "CREATE TABLE tunnel_requests (id TEXT PRIMARY KEY, method TEXT, path TEXT, headers TEXT, body TEXT, status TEXT, created_at INTEGER);" +
    "CREATE TABLE tunnel_responses (id TEXT PRIMARY KEY, status_code INTEGER, headers TEXT, body TEXT, created_at INTEGER);"
  );
  const runMig = (file) => {
    const sql = readFileSync(join(root, file), "utf8").replace(/--.*$/gm, "");
    for (const stmt of sql.split(";")) {
      const clean = stmt.trim();
      if (clean) db.db.exec(clean);
    }
  };
  runMig("tunnel/migrations/001-claim-lease.sql");
  runMig("tunnel/migrations/002-idempotency-ratelimit.sql");
  runMig("tunnel/migrations/003-response-idempotency.sql");
  const cols = db.raw("PRAGMA table_info(tunnel_responses)").map((r) => r.name);
  assert.ok(cols.includes("idempotency_key"));
  const idx = db.raw("SELECT name FROM sqlite_master WHERE type='index' AND name='idx_tunnel_responses_idem'");
  assert.equal(idx.length, 1);
});

// --- Putaran 5 (audit lanjutan 2026-10-21): replay hanya principal terverifikasi ---
// (b) replay principal auth & (c) 409 fingerprint beda untuk principal
// terverifikasi TIDAK berubah — dicakup tes putaran 4 (a) dan (c) di
// atas. Yang baru di sini: perilaku ANON.

test("putaran 5 (a): dua request ANON key+body sama -> backend dipanggil DUA kali, tidak ada replay", async () => {
  const env = { ...makeEnv(), INGRESS_WAIT_MS: "5000" };
  const p1 = ingress.onRequest({ request: idemReq(null, "key-anon", { model: "x" }), env });
  await new Promise((r) => setTimeout(r, 300));
  const q1 = await completeNext(env, "jawaban-anon-1");
  const r1 = await p1;
  assert.equal(r1.status, 200);
  assert.equal(await r1.text(), "jawaban-anon-1");
  // Respons anon tetap disimpan (result-fetch tidak berubah), tapi
  // principal tersimpannya NULL — tidak ada namespace replay anon.
  const stored = env.DB.raw("SELECT idem_principal FROM tunnel_responses")[0];
  assert.equal(stored.idem_principal, null);
  // Request kedua dengan key+body IDENTIK: dibuat baris antrean BARU
  // dan dijawab backend lagi — BUKAN replay jawaban pertama.
  const p2 = ingress.onRequest({ request: idemReq(null, "key-anon", { model: "x" }), env });
  await new Promise((r) => setTimeout(r, 300));
  assert.equal(Number(env.DB.raw("SELECT COUNT(*) AS n FROM tunnel_requests")[0].n), 1);
  const q2 = await completeNext(env, "jawaban-anon-2");
  assert.notEqual(q2.id, q1.id);
  const r2 = await p2;
  assert.equal(r2.status, 200);
  assert.equal(await r2.text(), "jawaban-anon-2");
});

test("putaran 5 (a2): dua request ANON bersamaan, key sama -> dua baris antrean terpisah", async () => {
  const env = { ...makeEnv(), INGRESS_WAIT_MS: "5000" };
  const p1 = ingress.onRequest({ request: idemReq(null, "key-anon-bersama", { model: "x" }), env });
  await new Promise((r) => setTimeout(r, 300));
  const p2 = ingress.onRequest({ request: idemReq(null, "key-anon-bersama", { model: "x" }), env });
  await new Promise((r) => setTimeout(r, 300));
  // Anon TIDAK menempel ke request yang sedang antre (berbeda dengan
  // principal terverifikasi): dua baris independen, dua pemrosesan.
  assert.equal(Number(env.DB.raw("SELECT COUNT(*) AS n FROM tunnel_requests")[0].n), 2);
  const { requests } = await (await poll.onRequestPost({ request: postReq({ key: KEY, limit: 4 }), env })).json();
  assert.equal(requests.length, 2);
  for (const q of requests) {
    await respond.onRequestPost({
      request: postReq({
        key: KEY, id: q.id, claim_token: q.claim_token, status_code: 200,
        headers: {}, body: Buffer.from("ok").toString("base64"),
      }), env,
    });
  }
  assert.equal((await p1).status, 200);
  assert.equal((await p2).status, 200);
});

test("putaran 5 (a3): ANON key sama, body beda -> BUKAN 409, diproses segar", async () => {
  const env = { ...makeEnv(), INGRESS_WAIT_MS: "5000" };
  const p1 = ingress.onRequest({ request: idemReq(null, "key-anon-beda", { model: "x" }), env });
  await new Promise((r) => setTimeout(r, 300));
  await completeNext(env, "jawaban-anon-x");
  assert.equal((await p1).status, 200);
  const p2 = ingress.onRequest({ request: idemReq(null, "key-anon-beda", { model: "LAIN" }), env });
  await new Promise((r) => setTimeout(r, 300));
  // 409 adalah perilaku principal terverifikasi; anon tidak punya
  // namespace untuk dikonflikkan — request-nya antre sebagai baru.
  assert.equal(Number(env.DB.raw("SELECT COUNT(*) AS n FROM tunnel_requests")[0].n), 1);
  await completeNext(env, "jawaban-anon-lain");
  const r2 = await p2;
  assert.equal(r2.status, 200);
  assert.equal(await r2.text(), "jawaban-anon-lain");
});

test("putaran 6: WAIT_MS_DEFAULT ingress = 120000 (selaras deadline baca body client)", () => {
  // Konstanta tidak diekspor fungsi, jadi nilai default dibuktikan
  // dari sumbernya langsung. Override env INGRESS_WAIT_MS tetap
  // dihormati — dibuktikan tes-tes lain di file ini yang semuanya
  // mengandalkan override bernilai kecil.
  const src = readFileSync(join(root, "tunnel/pages-tunnel/functions/[[path]].js"), "utf8");
  const m = src.match(/const WAIT_MS_DEFAULT = (\d+);/);
  assert.ok(m, "WAIT_MS_DEFAULT tidak ditemukan di [[path]].js");
  assert.equal(Number(m[1]), 120000);
});
