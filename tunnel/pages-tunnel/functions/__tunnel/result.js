// Ambil hasil akhir sebuah request tunnel berdasarkan id-nya.
// Pasangan dari ingress ([[path]].js): bila pemanggil menerima 504
// (client lokal lambat/offline sesaat), request TIDAK dibatalkan —
// respons yang selesai belakangan tersimpan s/d masa simpan antrean
// (120 dtk, dibersihkan poll berkala) dan bisa diambil di sini:
//
//   GET /__tunnel/result?id=<id-dari-header-x-tunnel-request-id>
//
// Id adalah UUID acak yang hanya diketahui pemanggil asal — kepemilikan
// id adalah kredensialnya (pola yang sama seperti link "unlisted").
// Endpoint ini memang tidak memakai TUNNEL_KEY: pemanggil publik tidak
// memegang key itu; key hanya untuk client lokal (poll/respond).
export async function onRequestGet({ request, env }) {
  const url = new URL(request.url);
  const id = url.searchParams.get("id");
  if (!id) return new Response("missing id", { status: 400 });

  const row = await env.DB.prepare(
    "SELECT status_code, headers, body FROM tunnel_responses WHERE id=?"
  ).bind(id).first();
  if (row) {
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

  const pending = await env.DB.prepare(
    "SELECT id FROM tunnel_requests WHERE id=?"
  ).bind(id).first();
  if (pending) return Response.json({ status: "pending" }, { status: 202 });

  return new Response("unknown or expired request id", { status: 404 });
}
