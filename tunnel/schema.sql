-- Skema D1 untuk tunnel polling.
-- Jalankan sekali: wrangler d1 execute <db-name> --file=schema.sql
-- (atau --remote bila database sudah ada di Cloudflare)
--
-- Database LAMA (dibuat sebelum klaim atomik ada): jalankan juga
-- tunnel/migrations/001-claim-lease.sql untuk menambah kolom klaim.

CREATE TABLE IF NOT EXISTS tunnel_requests (
  id         TEXT PRIMARY KEY,
  method     TEXT,
  path       TEXT,
  headers    TEXT,
  body       TEXT,
  status     TEXT,
  created_at INTEGER,
  claim_token TEXT,
  claimed_at  INTEGER
);

CREATE INDEX IF NOT EXISTS idx_tunnel_requests_status
  ON tunnel_requests(status, created_at);

CREATE TABLE IF NOT EXISTS tunnel_responses (
  id          TEXT PRIMARY KEY,
  status_code INTEGER,
  headers     TEXT,
  body        TEXT,
  created_at  INTEGER
);
