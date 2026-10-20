// Catch-all: browser -> D1 queue -> tunggu client lokal merespons
//
// Pengerasan (audit 2026-10-20, dua putaran):
// - Body dibaca STREAMING dengan batas keras 6 MiB: chunk yang membuat
//   total melewati batas langsung menghentikan pembacaan -> 413. Dulu
//   jalur tanpa Content-Length tetap membaca seluruh body via
//   arrayBuffer() ke memori sebelum penolakan.
// - Masa tunggu pemanggil default 120 dtk (putaran 6; sebelumnya
//   40 dtk) — selaras deadline keseluruhan baca body di client
//   (TUNNEL_RESPONSE_DEADLINE_MS, default 120 dtk), jadi stream
//   panjang yang sah tidak lagi dipotong ingress di tengah jalan.
//   Lease klaim 45 dtk (poll.js) diperpanjang client lewat heartbeat
//   selama backend bekerja: request yang client-nya mati di tengah
//   jalan masih sempat direbut & dijawab poller lain SEBELUM
//   pemanggil menyerah. (Bisa diatur via env INGRESS_WAIT_MS,
//   terutama untuk pengujian.)
// - Timeout TIDAK lagi menghapus request: pemanggil menerima 504 +
//   header `x-tunnel-request-id`, dan hasil akhir yang selesai
//   belakangan bisa diambil lewat GET /__tunnel/result?id=<id> selama
//   masa simpan antrean (120 dtk, dibersihkan poll berkala). Baris
//   respons juga TIDAK dihapus saat pengiriman pertama — pengiriman
//   ulang (idempotent replay) dan pengambilan hasil memakai baris yang
//   sama sampai masa simpannya habis.
// - Idempotency: header `idempotency-key` (atau `x-idempotency-key`)
//   pada request berside-effect — kiriman ulang dengan key yang sama
//   TIDAK membuat request kedua; pemanggil menunggu hasil request
//   pertama (kolom idempotency_key + index unik parsial di schema).
// - Rate limit per IP: jendela tetap 60 dtk, default 120 request/menit
//   (env RATE_LIMIT_PER_MIN; "0" = nonaktif) -> 429.
// - Gate password untuk halaman non-API (dashboard): bila env
//   GATE_PASSWORD ter-set, semua path SELAIN /v1/* dan /__tunnel/*
//   wajib HTTP Basic auth (user dari env GATE_USER, default "hermuse").
//   Bila env REQUIRE_GATE=1 tapi GATE_PASSWORD kosong -> 500
//   (fail-closed: lebih baik tidak melayani daripada dashboard terbuka).
//
// Pengerasan putaran 3 (audit lanjutan 2026-10-20):
// - Batas body DITURUNKAN ke kapasitas simpan D1 yang sebenarnya: D1
//   membatasi satu string/BLOB/baris pada 2.000.000 byte, sedangkan body
//   disimpan Base64 (mengembang 4/3). Batas lama 6 MiB mentah (~8 MB
//   Base64) dan respons client 32 MiB (~42,7 MB Base64) TIDAK PERNAH
//   muat di D1 — insert-nya pasti gagal di produksi. Sekarang: body
//   mentah maks 1.350.000 byte -> Base64 tepat 1.800.000 karakter, JSON
//   header maks 32.768 byte; total baris selalu < 2.000.000 byte.
// - Idempotency SETELAH pengiriman: kiriman ulang dengan key yang sama
//   kini dicek juga ke tunnel_responses (key disalin respond.js ke baris
//   respons; masa simpan default 24 jam). Dulu key hanya dicari di
//   tunnel_requests, yang barisnya dihapus saat pengiriman pertama —
//   retry setelah sukses membuat request BARU dan efek samping ganda.
// - Health probe terautentikasi: GET /__tunnel-health memakai header
//   x-tunnel-health-key (secret HEALTH_KEY, dibandingkan timing-safe).
//   Request-nya tetap melewati antrean tunnel seperti request biasa dan
//   dijawab tunnel-client.mjs dengan nonce + status backend, jadi
//   watchdog bisa membuktikan jalur ujung-ke-ujung benar-benar hidup —
//   bukan sekadar "ada yang menjawab 401 di edge" seperti sebelumnya.
// - Observability: setiap respons membawa header x-tunnel-request-id
//   (korelasi pemanggil <-> log), dan ingress menulis log terstruktur
//   satu baris JSON per request selesai/timeout.
//
// Pengerasan putaran 4 (audit lanjutan 2026-10-20):
// - Idempotency TERIKAT PEMANGGIL: lookup putaran 3 hanya memakai
//   idempotency_key, jadi pemanggil B yang memakai key yang sama dengan
//   pemanggil A menerima respons A (kebocoran lintas pemanggil — key
//   idempotency bukan rahasia). Kini setiap enqueue menyimpan
//   "principal" (identitas pemanggil yang diturunkan dari kredensial,
//   lihat derivePrincipal) + "fingerprint" request (method + path +
//   SHA-256 body mentah). Replay hanya cocok bila key DAN principal
//   DAN fingerprint semuanya sama:
//     key sama, principal beda -> TIDAK replay; request diproses baru.
//     key+principal sama, fingerprint beda -> 409 Conflict (key dipakai
//       ulang untuk request yang berbeda oleh pemanggil yang sama).
//   respond.js menyalin ketiganya atomik ke baris respons (migrasi 004).
//
// Pengerasan putaran 5 (audit lanjutan 2026-10-21):
// - Replay idempotency HANYA untuk principal TERVERTIFIKASI ("auth:"
//   atau "hk:"). Principal "anon" (tanpa Authorization & tanpa
//   health-key) tidak bisa membedakan satu pemanggil dari pemanggil
//   lain, jadi melayani replay untuknya berarti dua pemanggil anonim
//   berbeda berbagi namespace idempotency — pemanggil kedua menerima
//   respons pemanggil pertama. Kini request anon SELALU diproses
//   segar: kedua lookup replay dilewati, dan baris request-nya
//   menyimpan principal NULL (tidak pernah cocok dengan lookup
//   replay mana pun + tidak bertabrakan di index unik gabungan,
//   sehingga dua request anon bersamaan pun independen). Respons
//   anon tetap disimpan seperti biasa (result-fetch & masa simpan
//   tidak berubah) — hanya tidak pernah dipakai sebagai replay.
//   Perilaku principal terverifikasi (replay + 409 fingerprint beda)
//   tidak berubah dari putaran 4.
//
// Pengerasan putaran 6 (audit lanjutan 2026-10-21):
// - WAIT_MS_DEFAULT 40 dtk -> 120 dtk: masa tunggu ingress kini
//   selaras deadline keseluruhan client (120 dtk). Di putaran 5
//   streaming sudah lolos dari head-of-line blocking di client,
//   tapi pemanggil di ingress tetap menyerah (504) di 40 dtk —
//   stream ujung-ke-ujung yang sah berumur >40 dtk tidak pernah
//   sampai ke pemanggil sebagai respons utuh.
const MAX_BODY_BYTES = 1350000; // -> Base64 1.800.000 char; + header < 2.000.000 byte/baris D1
const MAX_HEADERS_BYTES = 32768;
const WAIT_MS_DEFAULT = 120000;
const HEALTH_PATH = "/__tunnel-health";

function timingSafeEqual(a, b) {
  if (typeof a !== "string" || typeof b !== "string" || a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

async function sha256Hex(data) {
  const buf = await crypto.subtle.digest("SHA-256", data);
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

// Principal = identitas pemanggil untuk mengikat idempotency, diturunkan
// dari kredensial yang DIBAWA request ini — bukan dari key idempotency
// (key bukan rahasia dan bebas dipilih pemanggil):
//   - Header Authorization (kredensial API yang diteruskan ke backend;
//     pada path dashboard isinya kredensial gate Basic) -> "auth:"+hash.
//   - Tanpa Authorization tapi membawa x-tunnel-health-key -> "hk:"+hash.
//   - Tanpa kredensial apa pun -> penanda eksplisit "anon": principal
//     TAK terverifikasi. Sejak putaran 5, "anon" tidak pernah dilayani
//     replay (pemanggil anonim tidak bisa dibedakan satu sama lain —
//     berbagi namespace replay = kebocoran); request-nya selalu
//     diproses segar dan principal yang DISIMPAN adalah NULL, yang
//     tidak pernah cocok dengan lookup replay mana pun.
// Yang disimpan SELALU hash SHA-256 hex — kredensial mentah tidak pernah
// ditulis ke database.
async function derivePrincipal(request) {
  const enc = new TextEncoder();
  const authz = request.headers.get("authorization");
  if (authz) return "auth:" + (await sha256Hex(enc.encode(authz)));
  const hk = request.headers.get("x-tunnel-health-key");
  if (hk) return "hk:" + (await sha256Hex(enc.encode(hk)));
  return "anon";
}

async function readBodyCapped(request) {
  // Jalur streaming: berhenti SEGERA saat batas terlampaui.
  if (request.body && typeof request.body.getReader === "function") {
    const reader = request.body.getReader();
    const chunks = [];
    let total = 0;
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      total += value.byteLength;
      if (total > MAX_BODY_BYTES) {
        await reader.cancel().catch(() => {});
        return { tooLarge: true };
      }
      chunks.push(value);
    }
    const bytes = new Uint8Array(total);
    let off = 0;
    for (const c of chunks) { bytes.set(c, off); off += c.byteLength; }
    return { bytes };
  }
  const buf = await request.arrayBuffer();
  if (buf.byteLength > MAX_BODY_BYTES) return { tooLarge: true };
  return { bytes: new Uint8Array(buf) };
}

function deliver(row, id) {
  const resHeaders = new Headers(JSON.parse(row.headers || "{}"));
  if (id) resHeaders.set("x-tunnel-request-id", id);
  let body = null;
  if (row.body) {
    const bin = atob(row.body);
    const bytes = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
    body = bytes.buffer;
  }
  return new Response(body, { status: row.status_code, headers: resHeaders });
}

export async function onRequest({ request, env }) {
  const url = new URL(request.url);
  const startedAt = Date.now();

  // --- Health probe: autentikasi kuncinya sendiri, bebas gate Basic ---
  // (jalur ini tetap masuk antrean tunnel; yang menjawab adalah client
  // lokal, jadi 200 di sini membuktikan seluruh jalur hidup).
  const isHealth = url.pathname === HEALTH_PATH;
  if (isHealth) {
    const hk = request.headers.get("x-tunnel-health-key") || "";
    if (!env.HEALTH_KEY || !timingSafeEqual(hk, env.HEALTH_KEY))
      return new Response("forbidden", { status: 403 });
  }

  // --- Gate password (hanya path non-API) ---
  const isApi = url.pathname.startsWith("/v1/") || url.pathname.startsWith("/__tunnel/");
  if (!isApi && !isHealth) {
    if (env.REQUIRE_GATE === "1" && !env.GATE_PASSWORD)
      return new Response("gate required but GATE_PASSWORD is not configured", { status: 500 });
    if (env.GATE_PASSWORD) {
      let ok = false;
      const auth = request.headers.get("authorization") || "";
      const sp = auth.indexOf(" ");
      if (sp > 0 && auth.slice(0, sp) === "Basic") {
        try {
          const decoded = atob(auth.slice(sp + 1));
          const sep = decoded.indexOf(":");
          if (sep >= 0) {
            ok = timingSafeEqual(decoded.slice(0, sep), env.GATE_USER || "hermuse") &&
                 timingSafeEqual(decoded.slice(sep + 1), env.GATE_PASSWORD);
          }
        } catch { ok = false; }
      }
      if (!ok)
        return new Response("authentication required", {
          status: 401,
          headers: { "www-authenticate": 'Basic realm="hermuse"' },
        });
    }
  }

  // --- Rate limit per IP (jendela tetap 60 detik) ---
  const rlLimit = env.RATE_LIMIT_PER_MIN === undefined
    ? 120 : parseInt(env.RATE_LIMIT_PER_MIN, 10);
  if (rlLimit > 0) {
    const ip = request.headers.get("cf-connecting-ip") || "unknown";
    const windowStart = Math.floor(Date.now() / 60000) * 60000;
    const row = await env.DB.prepare(
      "INSERT INTO tunnel_rate_limits (ip, window_start, count) VALUES (?,?,1) " +
      "ON CONFLICT(ip, window_start) DO UPDATE SET count = count + 1 RETURNING count"
    ).bind(ip, windowStart).first();
    if (row && row.count > rlLimit)
      return new Response("rate limit exceeded", { status: 429, headers: { "retry-after": "60" } });
  }

  // --- Body (streaming, berbatas) ---
  const headers = {};
  request.headers.forEach((v, k) => {
    const lk = k.toLowerCase();
    if (lk === "host" || lk === "connection" || lk === "content-length") return;
    headers[lk] = v;
  });

  let bodyB64 = null;
  let rawBody = new Uint8Array(0); // disimpan untuk fingerprint idempotency
  if (request.body && request.method !== "GET" && request.method !== "HEAD") {
    const declared = parseInt(request.headers.get("content-length") || "0", 10);
    if (declared > MAX_BODY_BYTES)
      return new Response("request body too large", { status: 413 });
    const { bytes, tooLarge } = await readBodyCapped(request);
    if (tooLarge)
      return new Response("request body too large", { status: 413 });
    rawBody = bytes;
    if (bytes.byteLength > 0) {
      let bin = "";
      for (let i = 0; i < bytes.length; i += 32768) {
        bin += String.fromCharCode.apply(null, bytes.subarray(i, i + 32768));
      }
      bodyB64 = btoa(bin);
    }
  }

  // Header ikut disimpan sebagai JSON di baris D1 yang sama — batasi
  // ukurannya agar total baris tidak melewati batas D1 (lihat konstanta).
  if (JSON.stringify(headers).length > MAX_HEADERS_BYTES)
    return new Response("request headers too large", { status: 413 });

  // --- Enqueue (idempotency terikat pemanggil, putaran 4; replay
  // hanya untuk principal terverifikasi, putaran 5) ---
  const idemKey = request.headers.get("idempotency-key") ||
                  request.headers.get("x-idempotency-key");
  let id = crypto.randomUUID();
  let enqueued = false;
  if (idemKey) {
    // Principal + fingerprint dihitung dari request INI; replay hanya
    // sah bila keduanya cocok dengan yang tersimpan (lihat komentar
    // derivePrincipal). Baris lama pra-migrasi 004 (principal NULL)
    // tidak pernah cocok -> diperlakukan sebagai request baru.
    const principal = await derivePrincipal(request);
    const fingerprint = request.method + "\n" + (url.pathname + url.search) +
                        "\n" + (await sha256Hex(rawBody));
    const conflict = () => {
      console.log(JSON.stringify({
        ev: "ingress_idem_conflict", method: request.method,
        path: url.pathname, status: 409, ms: Date.now() - startedAt,
      }));
      return new Response(
        "idempotency key conflict: this key was already used with a different request payload",
        { status: 409 }
      );
    };
    // Putaran 5: replay HANYA untuk principal terverifikasi.
    // "anon" tidak membawa kredensial apa pun yang membedakan satu
    // pemanggil dari pemanggil lain — melayani replay untuknya akan
    // membocorkan respons pemanggil pertama ke pemanggil anonim
    // berikutnya yang memakai key sama. Request anon selalu diproses
    // segar; principal yang disimpan NULL (tidak pernah cocok dengan
    // lookup replay, dan tidak bertabrakan di index unik gabungan
    // sehingga request anon bersamaan pun tetap independen).
    const verified = principal.startsWith("auth:") || principal.startsWith("hk:");
    if (!verified) {
      await env.DB.prepare(
        "INSERT INTO tunnel_requests (id, method, path, headers, body, status, created_at, idempotency_key, idem_principal, idem_fingerprint) " +
        "VALUES (?,?,?,?,?,'pending',?,?,?,?)"
      ).bind(id, request.method, url.pathname + url.search, JSON.stringify(headers),
             bodyB64, Date.now(), idemKey, null, fingerprint).run();
      enqueued = true;
    } else {
      // Replay SETELAH pengiriman pertama: hasilnya sudah ada di
      // tunnel_responses (key+principal+fingerprint tersalin di sana)
      // walau baris request-nya sudah dihapus — layani langsung, JANGAN
      // buat request baru. Key sama tapi principal BEDA tidak menemukan
      // baris apa pun di sini: respons pemanggil lain tidak bocor.
      const prior = await env.DB.prepare(
        "SELECT id, status_code, headers, body, idem_fingerprint FROM tunnel_responses " +
        "WHERE idempotency_key=? AND idem_principal=?"
      ).bind(idemKey, principal).first();
      if (prior) {
        if (prior.idem_fingerprint !== fingerprint) return conflict();
        console.log(JSON.stringify({
          ev: "ingress_replay", id: prior.id, method: request.method,
          path: url.pathname, status: prior.status_code,
          ms: Date.now() - startedAt,
        }));
        return deliver(prior, prior.id);
      }
      const existing = await env.DB.prepare(
        "SELECT id, idem_fingerprint FROM tunnel_requests " +
        "WHERE idempotency_key=? AND idem_principal=?"
      ).bind(idemKey, principal).first();
      if (existing) {
        if (existing.idem_fingerprint !== fingerprint) return conflict();
        id = existing.id; // kiriman ulang: tunggu hasil request pertama
        enqueued = true;
      }
      if (!enqueued) {
        try {
          await env.DB.prepare(
            "INSERT INTO tunnel_requests (id, method, path, headers, body, status, created_at, idempotency_key, idem_principal, idem_fingerprint) " +
            "VALUES (?,?,?,?,?,'pending',?,?,?,?)"
          ).bind(id, request.method, url.pathname + url.search, JSON.stringify(headers),
                 bodyB64, Date.now(), idemKey, principal, fingerprint).run();
          enqueued = true;
        } catch {
          // Race: key+principal yang sama keburu dimasukkan request lain
          // (index unik gabungan) — pakai punyanya, dengan cek fingerprint.
          const row = await env.DB.prepare(
            "SELECT id, idem_fingerprint FROM tunnel_requests " +
            "WHERE idempotency_key=? AND idem_principal=?"
          ).bind(idemKey, principal).first();
          if (!row) throw new Error("enqueue failed");
          if (row.idem_fingerprint !== fingerprint) return conflict();
          id = row.id;
          enqueued = true;
        }
      }
    }
  }
  if (!enqueued) {
    await env.DB.prepare(
      "INSERT INTO tunnel_requests (id, method, path, headers, body, status, created_at, idempotency_key) " +
      "VALUES (?,?,?,?,?,'pending',?,?)"
    ).bind(id, request.method, url.pathname + url.search, JSON.stringify(headers),
           bodyB64, Date.now(), null).run();
  }

  // --- Tunggu respons ---
  const waitMs = parseInt(env.INGRESS_WAIT_MS || "0", 10) || WAIT_MS_DEFAULT;
  const deadline = Date.now() + waitMs;
  while (Date.now() < deadline) {
    const row = await env.DB.prepare(
      "SELECT status_code, headers, body FROM tunnel_responses WHERE id=?"
    ).bind(id).first();
    if (row) {
      // Hanya baris request yang dihapus; baris respons bertahan s/d
      // masa simpan antrean agar replay/result-fetch tetap bisa membacanya.
      await env.DB.prepare("DELETE FROM tunnel_requests WHERE id=?").bind(id).run();
      console.log(JSON.stringify({
        ev: "ingress", id, method: request.method, path: url.pathname,
        status: row.status_code, ms: Date.now() - startedAt,
      }));
      return deliver(row, id);
    }
    await new Promise((r) => setTimeout(r, 400));
  }

  // Request SENGAJA tidak dihapus: client mungkin masih memprosesnya.
  // Hasil akhirnya bisa diambil lewat /__tunnel/result?id=<id>.
  console.log(JSON.stringify({
    ev: "ingress_timeout", id, method: request.method, path: url.pathname,
    status: 504, ms: Date.now() - startedAt,
  }));
  return new Response("tunnel timeout (client offline?)", {
    status: 504,
    headers: { "x-tunnel-request-id": id },
  });
}
