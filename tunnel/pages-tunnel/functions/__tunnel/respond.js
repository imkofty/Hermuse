// Client lokal kirim response untuk sebuah request.
// - Auth FAIL-CLOSED: pola yang sama seperti poll.js — TUNNEL_KEY kosong
//   di server berarti semua ditolak (dulu lolos bila key request juga kosong).
// - Hanya PEMEGANG KLAIM yang boleh merespons: claim_token yang diterima
//   dari poll wajib cocok dengan token tersimpan di baris request. Ini
//   mencegah client lain (atau client dengan klaim basi setelah lease
//   direbut poller lain) menimpa response — dan membuat double-response
//   dari race lama tidak bisa terjadi.
export async function onRequestPost({ request, env }) {
  const { key, id, claim_token, status_code, headers, body } = await request.json().catch(() => ({}));
  if (!env.TUNNEL_KEY || !key || key !== env.TUNNEL_KEY || !id || !claim_token)
    return new Response("forbidden", { status: 403 });

  const row = await env.DB.prepare(
    "SELECT claim_token FROM tunnel_requests WHERE id=? AND status='claimed'"
  ).bind(id).first();
  if (!row || row.claim_token !== claim_token)
    return new Response("request not claimed by this client", { status: 409 });

  await env.DB.prepare(
    "INSERT OR REPLACE INTO tunnel_responses (id, status_code, headers, body, created_at) VALUES (?,?,?,?,?)"
  ).bind(id, status_code | 0, JSON.stringify(headers || {}), body || null, Date.now()).run();

  return Response.json({ ok: true });
}
