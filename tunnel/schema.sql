-- Skema D1 untuk tunnel polling.
-- Jalankan sekali: wrangler d1 execute <db-name> --file=schema.sql
-- (atau --remote bila database sudah ada di Cloudflare)
--
-- Database LAMA (dibuat sebelum klaim atomik ada): jalankan migrasi
-- BERURUTAN — 001-claim-lease.sql, lalu 002-idempotency-ratelimit.sql,
-- lalu 003-response-idempotency.sql, lalu 004-idempotency-principal.sql.
-- Lihat bagian upgrade di README.

CREATE TABLE IF NOT EXISTS tunnel_requests (
  id         TEXT PRIMARY KEY,
  method     TEXT,
  path       TEXT,
  headers    TEXT,
  body       TEXT,
  status     TEXT,
  created_at INTEGER,
  claim_token TEXT,
  claimed_at  INTEGER,
  idempotency_key TEXT,
  idem_principal TEXT,
  idem_fingerprint TEXT
);

CREATE INDEX IF NOT EXISTS idx_tunnel_requests_status
  ON tunnel_requests(status, created_at);

-- Idempotency: satu key = maksimal satu request PER PEMANGGIL dalam
-- antrean (principal = hash kredensial pemanggil, lihat [[path]].js;
-- putaran 4 — sebelumnya key saja, sehingga respons bisa bocor ke
-- pemanggil lain yang memakai key yang sama).
CREATE UNIQUE INDEX IF NOT EXISTS idx_tunnel_requests_idem
  ON tunnel_requests(idempotency_key, idem_principal)
  WHERE idempotency_key IS NOT NULL;

CREATE TABLE IF NOT EXISTS tunnel_responses (
  id          TEXT PRIMARY KEY,
  status_code INTEGER,
  headers     TEXT,
  body        TEXT,
  created_at  INTEGER,
  idempotency_key TEXT,
  idem_principal TEXT,
  idem_fingerprint TEXT
);

-- Idempotency SETELAH pengiriman: key + principal + fingerprint disalin
-- dari request ke respons (respond.js), sehingga kiriman ulang dengan
-- key yang sama tetap menemukan hasilnya walau baris request sudah
-- dihapus — HANYA untuk pemanggil yang sama dan request yang sama.
CREATE UNIQUE INDEX IF NOT EXISTS idx_tunnel_responses_idem
  ON tunnel_responses(idempotency_key, idem_principal)
  WHERE idempotency_key IS NOT NULL;

-- Rate limit ingress publik: jendela tetap 60 detik per IP.
CREATE TABLE IF NOT EXISTS tunnel_rate_limits (
  ip           TEXT,
  window_start INTEGER,
  count        INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (ip, window_start)
);
