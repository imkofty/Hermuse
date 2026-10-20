-- Migrasi 002: idempotency key + tabel rate limit (audit putaran 2, 2026-10-20).
-- Untuk database yang dibuat dari schema.sql versi sebelumnya.
--
-- Jalankan sekali:
--   wrangler d1 execute <db-name> --remote --file=tunnel/migrations/002-idempotency-ratelimit.sql
--
-- Database baru TIDAK butuh file ini (schema.sql sudah memuat semuanya).
-- Bila kolom sudah ada, ALTER akan gagal dengan "duplicate column name" —
-- itu aman dan berarti migrasi sudah pernah diterapkan; abaikan baris itu.

ALTER TABLE tunnel_requests ADD COLUMN idempotency_key TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS idx_tunnel_requests_idem
  ON tunnel_requests(idempotency_key) WHERE idempotency_key IS NOT NULL;
CREATE TABLE IF NOT EXISTS tunnel_rate_limits (
  ip           TEXT,
  window_start INTEGER,
  count        INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (ip, window_start)
);
