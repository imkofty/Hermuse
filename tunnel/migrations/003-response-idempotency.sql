-- Migrasi 003: idempotency key ikut disimpan di tabel respons
-- (audit putaran 3, 2026-10-20).
--
-- Masalah yang diperbaiki: pemetaan idempotency-key -> hasil hanya hidup
-- di tunnel_requests, dan baris request DIHAPUS saat respons pertama
-- terkirim. Kiriman ulang dengan key yang sama SETELAH pengiriman sukses
-- tidak menemukan key apa pun -> request baru dibuat -> efek samping
-- (mis. chat completion berbayar) berjalan dua kali. Dengan kolom ini,
-- respond.js menyalin key dari baris request ke baris respons dalam satu
-- statement atomik, dan ingress melayani kiriman ulang langsung dari
-- baris respons selama masa simpan idempotency (default 24 jam).
--
-- Jalankan sekali, SETELAH 001 dan 002:
--   wrangler d1 execute <db-name> --remote --file=tunnel/migrations/003-response-idempotency.sql
--
-- Database baru TIDAK butuh file ini (schema.sql sudah memuat semuanya).
-- Bila kolom sudah ada, ALTER akan gagal dengan "duplicate column name" —
-- itu aman dan berarti migrasi sudah pernah diterapkan; abaikan baris itu.

ALTER TABLE tunnel_responses ADD COLUMN idempotency_key TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS idx_tunnel_responses_idem
  ON tunnel_responses(idempotency_key) WHERE idempotency_key IS NOT NULL;
