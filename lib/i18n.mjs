// Hermuse i18n helper (Node) — mirrors lib/i18n.sh for tunnel-client.mjs.
// Language: process.env.HERMUSE_LANG — one of: id (default, legacy
// behaviour), en, ms. Unknown values fall back to id.
//
// Malay follows the repo's ms style guide: "anda", no Manglish particles,
// technical nouns stay English. NEVER use in ms strings: butuh (vulgar!),
// bisa (=racun), gampang, sulit, kamu/kalian, nggak.

const STRINGS = {
  en: {
    tunnel_env_missing: "TUNNEL_BASE_URL is not set. Example:",
    tunnel_env_example: "  TUNNEL_BASE_URL=https://<your-project>.pages.dev node tunnel-client.mjs",
    tunnel_env_alt: "  (or save the URL in a .tunnel-url file when run via start-pages-tunnel.sh)",
    tunnel_key_unreadable: "Cannot read key file: %s (create with: openssl rand -hex 32 > %s && chmod 600 %s)",
    tunnel_key_empty: "Empty key in %s",
    tunnel_local_not_loopback: "TUNNEL_LOCAL must be a loopback URL (got: %s). Set TUNNEL_ALLOW_REMOTE_LOCAL=1 only if you really mean to forward elsewhere.",
    tunnel_response_too_large: "Local response exceeds the %s MB cap",
    tunnel_response_deadline: "Local response read exceeded the %s ms deadline",
  },
  ms: {
    tunnel_env_missing: "TUNNEL_BASE_URL belum ditetapkan. Contoh:",
    tunnel_env_example: "  TUNNEL_BASE_URL=https://<projek-anda>.pages.dev node tunnel-client.mjs",
    tunnel_env_alt: "  (atau simpan URL dalam fail .tunnel-url jika dijalankan melalui start-pages-tunnel.sh)",
    tunnel_key_unreadable: "Tidak dapat membaca fail kunci: %s (cipta dengan: openssl rand -hex 32 > %s && chmod 600 %s)",
    tunnel_key_empty: "Kunci kosong di %s",
    tunnel_local_not_loopback: "TUNNEL_LOCAL mestilah URL loopback (diberi: %s). Tetapkan TUNNEL_ALLOW_REMOTE_LOCAL=1 hanya jika anda memang mahu forward ke tempat lain.",
    tunnel_response_too_large: "Respons lokal melebihi had %s MB",
    tunnel_response_deadline: "Pembacaan respons lokal melebihi deadline %s ms",
  },
  id: {
    tunnel_env_missing: "TUNNEL_BASE_URL belum di-set. Contoh:",
    tunnel_env_example: "  TUNNEL_BASE_URL=https://<project-kamu>.pages.dev node tunnel-client.mjs",
    tunnel_env_alt: "  (atau simpan URL di file .tunnel-url bila dijalankan via start-pages-tunnel.sh)",
    tunnel_key_unreadable: "Tidak bisa baca key file: %s (buat dengan: openssl rand -hex 32 > %s && chmod 600 %s)",
    tunnel_key_empty: "Key kosong di %s",
    tunnel_local_not_loopback: "TUNNEL_LOCAL harus berupa URL loopback (diberi: %s). Set TUNNEL_ALLOW_REMOTE_LOCAL=1 hanya bila memang sengaja forward ke tempat lain.",
    tunnel_response_too_large: "Respons lokal melebihi batas %s MB",
    tunnel_response_deadline: "Pembacaan respons lokal melewati deadline %s ms",
  },
};

export function t(key, ...args) {
  let lang = process.env.HERMUSE_LANG || "id";
  if (!STRINGS[lang]) lang = "id";
  let fmt = STRINGS[lang][key];
  if (fmt === undefined) {
    console.error(`i18n: unknown key ${key}`);
    process.exitCode = 1;
    return key;
  }
  for (const a of args) fmt = fmt.replace("%s", String(a));
  return fmt;
}
