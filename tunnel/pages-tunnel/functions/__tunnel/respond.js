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
// - Batas ukuran D1 ditegakkan JUGA di server (putaran 3): D1 membatasi
//   satu string/BLOB/baris pada 2.000.000 byte. Body Base64 maksimal
//   1.800.000 karakter (= 1.350.000 byte mentah) dan JSON header maksimal
//   32.768 byte, sehingga total baris selalu di bawah batas walau client
//   lama/buggy mengirim lebih. Pelanggaran -> 413, tidak ditulis.
// - Idempotency key DISALIN dari baris request ke baris respons dalam
//   statement yang sama: pemetaan key -> hasil tetap hidup setelah baris
//   request dihapus saat pengiriman, jadi kiriman ulang dengan key yang
//   sama tidak mengulang efek samping (putaran 3; migrasi 003).
// - Putaran 4 (migrasi 004): principal + fingerprint request ikut
//   disalin dalam statement INSERT ... SELECT yang sama, sehingga
//   lookup replay di ingress bisa menuntut key + principal +
//   fingerprint semuanya cocok — respons tidak lagi bisa bocor ke
//   pemanggil lain yang memakai key yang sama.
const MAX_BODY_B64_CHARS = 1800000;
const MAX_HEADERS_BYTES = 32768;

export async function onRequestPost({ request, env }) {
  const { key, id, claim_token, status_code, headers, body } = await request.json().catch(() => ({}));
  if (!env.TUNNEL_KEY || !key || key !== env.TUNNEL_KEY || !id || !claim_token)
    return new Response("forbidden", { status: 403 });

  const headersJson = JSON.stringify(headers || {});
  if ((body && body.length > MAX_BODY_B64_CHARS) || headersJson.length > MAX_HEADERS_BYTES)
    return new Response("response payload exceeds D1 storage limit", { status: 413 });

  // Satu statement: baris respons hanya tertulis bila baris request
  // masih ter-klaim oleh token ini pada saat statement berjalan, dan
  // key+principal+fingerprint disalin dari baris request yang sama.
  const res = await env.DB.prepare(
    "INSERT OR REPLACE INTO tunnel_responses (id, status_code, headers, body, created_at, idempotency_key, idem_principal, idem_fingerprint) " +
    "SELECT ?,?,?,?,?, idempotency_key, idem_principal, idem_fingerprint " +
    "FROM tunnel_requests WHERE id=? AND status='claimed' AND claim_token=?"
  ).bind(id, status_code | 0, headersJson, body || null, Date.now(), id, claim_token).run();

  if (!res.meta || res.meta.changes !== 1)
    return new Response("request not claimed by this client", { status: 409 });

  return Response.json({ ok: true });
}
