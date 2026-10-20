// Client lokal kirim response untuk sebuah request.
// - Auth FAIL-CLOSED: pola yang sama seperti poll.js — TUNNEL_KEY kosong
//   di server berarti semua ditolak (dulu lolos bila key request juga kosong).
// - Hanya PEMEGANG KLAIM yang boleh merespons, dan validasi klaim +
//   penulisan respons kini SATU statement atomik (INSERT ... SELECT ...
//   WHERE EXISTS): tidak ada lagi jendela race antara "cek token" dan
//   "tulis respons" (temuan audit putaran 2 — sebelumnya SELECT lalu
//   INSERT OR REPLACE terpisah, sehingga klaim yang direbut poller lain
//   di antara keduanya tetap bisa ditimpa respons basi). Baris respons
//   hanya tertulis bila klaim masih sah pada saat statement berjalan;
//   jumlah baris berubah != 1 berarti klaim tidak sah -> 409.
export async function onRequestPost({ request, env }) {
  const { key, id, claim_token, status_code, headers, body } = await request.json().catch(() => ({}));
  if (!env.TUNNEL_KEY || !key || key !== env.TUNNEL_KEY || !id || !claim_token)
    return new Response("forbidden", { status: 403 });

  const res = await env.DB.prepare(
    "INSERT OR REPLACE INTO tunnel_responses (id, status_code, headers, body, created_at) " +
    "SELECT ?,?,?,?,? WHERE EXISTS (" +
    "  SELECT 1 FROM tunnel_requests WHERE id=? AND status='claimed' AND claim_token=?)"
  ).bind(id, status_code | 0, JSON.stringify(headers || {}), body || null, Date.now(), id, claim_token).run();

  if (!res.meta || res.meta.changes !== 1)
    return new Response("request not claimed by this client", { status: 409 });

  return Response.json({ ok: true });
}
