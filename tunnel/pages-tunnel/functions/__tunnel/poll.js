// Client lokal long-poll: tahan koneksi s/d ~20 detik sampai ada request antri.
// Menghemat request Pages: dari 1 poll/2.5 dtk (~35rb/hari) menjadi ~1 poll/20 dtk
// (~4.3rb/hari) saat idle. Client langsung poll ulang begitu dapat item.
//
// Keamanan & korektness (audit 2026-10-20):
// - Auth FAIL-CLOSED: TUNNEL_KEY wajib ter-set di server. Dulu cek
//   `key !== env.TUNNEL_KEY` LOLOS bila keduanya kosong (undefined ===
//   undefined) — tunnel tanpa secret terpasang berarti terbuka untuk siapa
//   pun yang bisa menebak endpoint __tunnel. Sekarang secret kosong di
//   server = semua request ditolak, sebelum perbandingan kredensial.
// - Klaim ATOMIK: satu statement UPDATE ... WHERE status='pending' ...
//   RETURNING. Baris yang dikembalikan dijamin milik poller ini. Dulu
//   SELECT-then-UPDATE terpisah membiarkan dua poller menerima request
//   yang sama (double processing) karena hasil SELECT dikembalikan tanpa
//   memeriksa baris mana yang benar-benar berubah statusnya.
// - Lease: klaim membawa claim_token + claimed_at. Klaim yang lebih tua
//   dari LEASE_MS (client mati sebelum respond) direbut kembali ke
//   'pending' agar request-nya tidak hilang selamanya.
// - Putaran 3: lease TIDAK lagi balapan dengan durasi kerja backend.
//   Client yang hidup memperpanjang klaimnya lewat __tunnel/heartbeat
//   (tiap 10 dtk) selama backend masih bekerja, jadi LEASE_MS (45 dtk)
//   hanya berlaku sebagai batas mati: klaim direbut hanya bila
//   perpanjangan berhenti — artinya client benar-benar mati/macet.
//   Tanpa heartbeat, lease 30 dtk vs timeout backend 30 dtk nyaris sama
//   sehingga poller lain bisa merebut request yang SEDANG dikerjakan
//   (kerja ganda). Hasil yang tetap terlambat karena client mati bisa
//   diambil pemanggil lewat GET /__tunnel/result?id=<id>.
// - Masa simpan respons: respons biasa 120 dtk; respons yang membawa
//   idempotency_key disimpan s/d IDEMPOTENCY_TTL_MS (default 24 jam)
//   agar kiriman ulang dengan key yang sama tetap menemukan hasilnya
//   walau baris request sudah dihapus (lihat [[path]].js & respond.js).
const LEASE_MS = 45000;
const RESPONSE_TTL_MS = 120000;
const IDEMPOTENCY_TTL_MS_DEFAULT = 86400000; // 24 jam

export async function onRequestPost({ request, env }) {
  const { key, limit } = await request.json().catch(() => ({}));
  if (!env.TUNNEL_KEY || !key || key !== env.TUNNEL_KEY)
    return new Response("forbidden", { status: 403 });

  const now = Date.now();
  const idemTtl = parseInt(env.IDEMPOTENCY_TTL_MS || "0", 10) || IDEMPOTENCY_TTL_MS_DEFAULT;
  await env.DB.batch([
    env.DB.prepare("DELETE FROM tunnel_requests WHERE created_at < ?").bind(now - 120000),
    env.DB.prepare(
      "DELETE FROM tunnel_responses WHERE created_at < ? AND idempotency_key IS NULL"
    ).bind(now - RESPONSE_TTL_MS),
    env.DB.prepare("DELETE FROM tunnel_responses WHERE created_at < ?").bind(now - idemTtl),
    env.DB.prepare(
      "UPDATE tunnel_requests SET status='pending', claim_token=NULL, claimed_at=NULL " +
      "WHERE status='claimed' AND claimed_at < ?"
    ).bind(now - LEASE_MS),
    env.DB.prepare("DELETE FROM tunnel_rate_limits WHERE window_start < ?").bind(now - 3600000),
  ]);

  const n = Math.min(Math.max(parseInt(limit) || 4, 1), 8);
  const claimToken = crypto.randomUUID();
  const deadline = Date.now() + 20000; // hold ~20 dtk (di bawah batas wajar eksekusi Function)
  for (;;) {
    const rows = await env.DB.prepare(
      `UPDATE tunnel_requests
          SET status='claimed', claim_token=?, claimed_at=?
        WHERE id IN (
          SELECT id FROM tunnel_requests
           WHERE status='pending'
           ORDER BY created_at ASC
           LIMIT ?
        )
        RETURNING id, method, path, headers, body`
    ).bind(claimToken, Date.now(), n).all();

    if (rows.results.length > 0) {
      return Response.json({
        requests: rows.results.map((r) => ({ ...r, claim_token: claimToken })),
      });
    }
    if (Date.now() >= deadline) return Response.json({ requests: [] });
    await new Promise((r) => setTimeout(r, 1000));
  }
}
