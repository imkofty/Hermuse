// Hermuse i18n helper (Node) — mirrors lib/i18n.sh for tunnel-client.mjs.
// Language: process.env.HERMUSE_LANG — one of: id (default, legacy
// behaviour), en, ms, vi, hi, ja. Unknown values fall back to id.
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
  vi: {
    tunnel_env_missing: "TUNNEL_BASE_URL chưa được đặt. Ví dụ:",
    tunnel_env_example: "  TUNNEL_BASE_URL=https://<project-cua-ban>.pages.dev node tunnel-client.mjs",
    tunnel_env_alt: "  (hoặc lưu URL vào file .tunnel-url khi chạy qua start-pages-tunnel.sh)",
    tunnel_key_unreadable: "Không đọc được file key: %s (tạo bằng: openssl rand -hex 32 > %s && chmod 600 %s)",
    tunnel_key_empty: "Key trống trong %s",
    tunnel_local_not_loopback: "TUNNEL_LOCAL phải là URL loopback (nhận được: %s). Chỉ đặt TUNNEL_ALLOW_REMOTE_LOCAL=1 khi bạn thực sự muốn forward đến nơi khác.",
    tunnel_response_too_large: "Phản hồi cục bộ vượt quá giới hạn %s MB",
    tunnel_response_deadline: "Đọc phản hồi cục bộ vượt quá deadline %s ms",
  },
  hi: {
    tunnel_env_missing: "TUNNEL_BASE_URL सेट नहीं है। उदाहरण:",
    tunnel_env_example: "  TUNNEL_BASE_URL=https://<aapka-project>.pages.dev node tunnel-client.mjs",
    tunnel_env_alt: "  (या start-pages-tunnel.sh से चलाने पर URL को .tunnel-url फ़ाइल में सहेजें)",
    tunnel_key_unreadable: "Key फ़ाइल नहीं पढ़ी जा सकी: %s (इससे बनाएं: openssl rand -hex 32 > %s && chmod 600 %s)",
    tunnel_key_empty: "%s में key खाली है",
    tunnel_local_not_loopback: "TUNNEL_LOCAL एक loopback URL होना चाहिए (मिला: %s)। TUNNEL_ALLOW_REMOTE_LOCAL=1 केवल तभी सेट करें जब आप सचमुच कहीं और forward करना चाहते हों।",
    tunnel_response_too_large: "स्थानीय प्रतिक्रिया %s MB की सीमा से अधिक है",
    tunnel_response_deadline: "स्थानीय प्रतिक्रिया पढ़ना %s ms की deadline से अधिक हो गया",
  },
  ja: {
    tunnel_env_missing: "TUNNEL_BASE_URL が設定されていません。例:",
    tunnel_env_example: "  TUNNEL_BASE_URL=https://<あなたのプロジェクト>.pages.dev node tunnel-client.mjs",
    tunnel_env_alt: "  （または start-pages-tunnel.sh 経由で実行する場合は、URL を .tunnel-url ファイルに保存してください）",
    tunnel_key_unreadable: "キーファイルを読み取れません: %s（作成方法: openssl rand -hex 32 > %s && chmod 600 %s）",
    tunnel_key_empty: "%s のキーが空です",
    tunnel_local_not_loopback: "TUNNEL_LOCAL は loopback URL でなければなりません（取得値: %s）。本当に別の場所へ転送する場合のみ TUNNEL_ALLOW_REMOTE_LOCAL=1 を設定してください。",
    tunnel_response_too_large: "ローカルレスポンスが上限 %s MB を超えています",
    tunnel_response_deadline: "ローカルレスポンスの読み取りが期限 %s ms を超えました",
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
