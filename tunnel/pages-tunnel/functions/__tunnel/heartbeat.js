// Perpanjangan lease klaim: client lokal memanggil ini berkala (default
// tiap 10 dtk) selama backend masih memproses request yang diklaimnya,
// supaya klaim tidak direbut poller lain di tengah jalan (kerja ganda).
//
// - Auth FAIL-CLOSED: pola yang sama seperti poll.js/respond.js —
//   TUNNEL_KEY kosong di server berarti semua ditolak.
// - Hanya pemegang klaim yang sah yang bisa memperpanjang: UPDATE dibatasi
//   id + status 'claimed' + claim_token. Klaim yang sudah direbut/dijawab
//   tidak berubah -> changes != 1 -> 409, dan client tahu klaimnya hilang
//   (respond-nya nanti juga akan ditolak 409 oleh respond.js).
export async function onRequestPost({ request, env }) {
  const { key, id, claim_token } = await request.json().catch(() => ({}));
  if (!env.TUNNEL_KEY || !key || key !== env.TUNNEL_KEY || !id || !claim_token)
    return new Response("forbidden", { status: 403 });

  const res = await env.DB.prepare(
    "UPDATE tunnel_requests SET claimed_at=? " +
    "WHERE id=? AND status='claimed' AND claim_token=?"
  ).bind(Date.now(), id, claim_token).run();

  if (!res.meta || res.meta.changes !== 1)
    return new Response("request not claimed by this client", { status: 409 });

  return Response.json({ ok: true });
}
