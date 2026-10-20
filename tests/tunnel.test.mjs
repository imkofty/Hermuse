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
