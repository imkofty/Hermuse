// Catch-all: browser -> D1 queue -> tunggu client lokal merespons
//
// Batas ukuran body: request raksasa ditolak 413 sebelum masuk antrean —
// dulu body dibaca utuh ke memori (arrayBuffer) dan diteruskan tanpa batas.
const MAX_BODY_BYTES = 6 * 1024 * 1024; // 6 MiB

export async function onRequest({ request, env }) {
  const url = new URL(request.url);
  const id = crypto.randomUUID();

  const headers = {};
  request.headers.forEach((v, k) => {
    const lk = k.toLowerCase();
    if (lk === "host" || lk === "connection" || lk === "content-length") return;
    headers[lk] = v;
  });

  let bodyB64 = null;
  if (request.body && request.method !== "GET" && request.method !== "HEAD") {
    const declared = parseInt(request.headers.get("content-length") || "0", 10);
    if (declared > MAX_BODY_BYTES)
      return new Response("request body too large", { status: 413 });
    const buf = await request.arrayBuffer();
    if (buf.byteLength > MAX_BODY_BYTES)
      return new Response("request body too large", { status: 413 });
    if (buf.byteLength > 0) {
      const bytes = new Uint8Array(buf);
      let bin = "";
      for (let i = 0; i < bytes.length; i += 32768) {
        bin += String.fromCharCode.apply(null, bytes.subarray(i, i + 32768));
      }
      bodyB64 = btoa(bin);
    }
  }

  await env.DB.prepare(
    "INSERT INTO tunnel_requests (id, method, path, headers, body, status, created_at) VALUES (?,?,?,?,?,'pending',?)"
  ).bind(id, request.method, url.pathname + url.search, JSON.stringify(headers), bodyB64, Date.now()).run();

  const deadline = Date.now() + 25000;
  while (Date.now() < deadline) {
    const row = await env.DB.prepare(
      "SELECT status_code, headers, body FROM tunnel_responses WHERE id=?"
    ).bind(id).first();
    if (row) {
      await env.DB.batch([
        env.DB.prepare("DELETE FROM tunnel_requests WHERE id=?").bind(id),
        env.DB.prepare("DELETE FROM tunnel_responses WHERE id=?").bind(id),
      ]);
      const resHeaders = new Headers(JSON.parse(row.headers || "{}"));
      let body = null;
      if (row.body) {
        const bin = atob(row.body);
        const bytes = new Uint8Array(bin.length);
        for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
        body = bytes.buffer;
      }
      return new Response(body, { status: row.status_code, headers: resHeaders });
    }
    await new Promise((r) => setTimeout(r, 400));
  }

  await env.DB.prepare("DELETE FROM tunnel_requests WHERE id=?").bind(id).run();
  return new Response("tunnel timeout (client offline?)", { status: 504 });
}
