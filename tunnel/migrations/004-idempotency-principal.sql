-- Migrasi 004: idempotency terikat PEMANGGIL + sidik jari request
-- (audit putaran 4, 2026-10-20).
--
-- Masalah yang diperbaiki: lookup idempotency (putaran 3) hanya memakai
-- idempotency_key SAJA. Pemanggil B yang memakai key yang sama dengan
-- pemanggil A menerima respons A — kebocoran lintas pemanggil, karena
-- key idempotency bukan rahasia dan sering dipilih/ditebak pihak lain.
--
-- Perbaikan: ingress menurunkan "principal" dari kredensial pemanggil
-- (SHA-256 header Authorization; penanda eksplisit bila tanpa
-- kredensial — lihat [[path]].js) dan "fingerprint" request
-- (method + path + SHA-256 body mentah). Keduanya disimpan di baris
-- request saat enqueue, disalin atomik respond.js ke baris respons.
-- Replay hanya cocok bila key + principal + fingerprint SEMUA sama:
-- principal beda = request baru (respons orang lain tidak bocor),
-- fingerprint beda = 409 Conflict. Yang disimpan selalu HASH —
-- kredensial mentah tidak pernah masuk database.
--
-- Index unik parsial digabung menjadi (idempotency_key, principal):
-- key yang sama kini sah dipakai pemanggil berbeda secara bersamaan.
-- Baris LAMA (principal NULL) tidak pernah cocok dengan lookup baru —
-- kiriman ulang atas key pra-migrasi diperlakukan sebagai request baru
-- (aman: tidak ada replay lintas pemanggil dari data lama).
--
-- Jalankan sekali, SETELAH 001, 002, dan 003:
--   wrangler d1 execute <db-name> --remote --file=tunnel/migrations/004-idempotency-principal.sql
--
-- Database baru TIDAK butuh file ini (schema.sql sudah memuat semuanya).
-- Bila kolom sudah ada, ALTER akan gagal dengan "duplicate column name" —
-- itu aman dan berarti migrasi sudah pernah diterapkan; abaikan baris itu.

ALTER TABLE tunnel_requests ADD COLUMN idem_principal TEXT;
ALTER TABLE tunnel_requests ADD COLUMN idem_fingerprint TEXT;
ALTER TABLE tunnel_responses ADD COLUMN idem_principal TEXT;
ALTER TABLE tunnel_responses ADD COLUMN idem_fingerprint TEXT;

DROP INDEX IF EXISTS idx_tunnel_requests_idem;
CREATE UNIQUE INDEX IF NOT EXISTS idx_tunnel_requests_idem
  ON tunnel_requests(idempotency_key, idem_principal)
  WHERE idempotency_key IS NOT NULL;

DROP INDEX IF EXISTS idx_tunnel_responses_idem;
CREATE UNIQUE INDEX IF NOT EXISTS idx_tunnel_responses_idem
  ON tunnel_responses(idempotency_key, idem_principal)
  WHERE idempotency_key IS NOT NULL;
