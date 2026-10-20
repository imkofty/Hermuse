-- Migrasi 001: kolom klaim atomik + lease untuk tunnel_requests.
-- Untuk database yang dibuat dari schema.sql versi lama (tanpa claim_token).
--
-- Jalankan sekali:
--   wrangler d1 execute <db-name> --remote --file=tunnel/migrations/001-claim-lease.sql
--
-- Database baru TIDAK butuh file ini (schema.sql sudah memuat kolomnya).
-- Bila kolom sudah ada, ALTER akan gagal dengan "duplicate column name" —
-- itu aman dan berarti migrasi sudah pernah diterapkan; abaikan baris itu.

ALTER TABLE tunnel_requests ADD COLUMN claim_token TEXT;
ALTER TABLE tunnel_requests ADD COLUMN claimed_at INTEGER;
CREATE INDEX IF NOT EXISTS idx_tunnel_requests_status
  ON tunnel_requests(status, created_at);
