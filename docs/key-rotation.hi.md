# क्रेडेंशियल Rotation गाइड

कब rotate करें: कोई secret लीक हो सकता है (गलती से साझा हो गया, repo में
commit हो गया, स्क्रीन पर दिख गया), किसी व्यक्ति के पास अब उसकी पहुँच नहीं
होनी चाहिए, या बस एक निर्धारित समय पर। Rotation सस्ता है — बहस करने के
बजाय कर डालें।

*English version: [key-rotation.md](key-rotation.md) · Versi Bahasa Indonesia: [key-rotation.id.md](key-rotation.id.md) · Versi Bahasa Malaysia: [key-rotation.ms.md](key-rotation.ms.md) · Tiếng Việt: [key-rotation.vi.md](key-rotation.vi.md) · 日本語: [key-rotation.ja.md](key-rotation.ja.md)*

## Secrets क्या हैं

| Secret | कहाँ रहता है | किसके द्वारा उपयोग |
|---|---|---|
| Tunnel key | `~/.tunnel-key` (600) | `tunnel-client.mjs` ↔ Pages Functions (`TUNNEL_KEY` secret) |
| 9Router dashboard पासवर्ड | repo root में `.dashboard-pw` (600) | `start-9router.sh` → 9Router |
| Telegram bot token | repo root में `.env` (600) | Telegram gateway |
| Cloudflare API token | **कहीं नहीं — केवल क्षणिक** | सेटअप के दौरान `wrangler`; कभी सहेजा नहीं जाता |

ऊपर के सभी gitignored हैं। हर commit से पहले सत्यापित करें:
`git status --porcelain` में वे सूचीबद्ध नहीं होने चाहिए।

## नियम 0 — rotate करने से पहले backup लें

```bash
mkdir -p ~/.hermuse-secret-backup && chmod 700 ~/.hermuse-secret-backup
BK=~/.hermuse-secret-backup/$(date -u +%F)
mkdir -p "$BK"
cp -p ~/.tunnel-key .env .dashboard-pw "$BK/" 2>/dev/null
chmod 600 "$BK"/*
```

यदि कुछ गड़बड़ हो जाए, तो `$BK` से restore करें और नीचे का मेल खाता restart
चरण दोहराएं।

## 1. Tunnel key rotate करें (`TUNNEL_KEY`)

Key को **दो** जगहों पर मेल खाना चाहिए: आपकी स्थानीय `~/.tunnel-key` और
Pages project का `TUNNEL_KEY` secret। बेमेल = client को हर poll पर HTTP 403
मिलता है (वह backoff के साथ retry करता है, इसलिए घबराने के बजाय तुरंत ठीक
करें)।

```bash
# 1. नई key बनाएं और स्थानीय रूप से सहेजें
openssl rand -hex 32 > ~/.tunnel-key && chmod 600 ~/.tunnel-key

# 2. अपना Pages project नाम खोजें (tunnel URL या wrangler.toml से)
PROJECT="$(basename "$(tr -d '[:space:]' < .tunnel-url)" .pages.dev)"
echo "project: $PROJECT"

# 3. नई key को Pages secret के रूप में डालें (wrangler login या CLOUDFLARE_API_TOKEN चाहिए)
printf '%s' "$(cat ~/.tunnel-key)" | wrangler pages secret put TUNNEL_KEY --project-name="$PROJECT"

# 4. Tunnel client को restart करें ताकि वह नई key उठा ले
bash restart-tunnel.sh
```

**सत्यापित करें:**

```bash
sleep 10
curl -s -o /dev/null -w '%{http_code}\n' --max-time 10 "$(cat .tunnel-url)"
# अपेक्षित 200 या 307 (307 = dashboard लॉगिन पर redirect, सामान्य)
bash scripts/doctor.sh   # अपेक्षित: 0 FAIL
```

ब्राउज़र में सार्वजनिक tunnel URL खोलें — 9Router dashboard लोड होना चाहिए।

## 2. 9Router dashboard पासवर्ड rotate करें

```bash
# 1. नया पासवर्ड बनाएं और सहेजें (अंतिम newline की समस्या नहीं: $(...) उसे हटा देता है)
openssl rand -base64 24 | tr -d '\n' > .dashboard-pw && chmod 600 .dashboard-pw

# 2. 9Router को restart करें ताकि वह नया पासवर्ड उठा ले
bash restart-9router.sh
```

**सत्यापित करें:**

```bash
sleep 8
curl -s -o /dev/null -w '%{http_code}\n' --max-time 10 http://127.0.0.1:20128/dashboard
# अपेक्षित 200 या 307
```

फिर नए पासवर्ड के साथ सार्वजनिक tunnel URL पर लॉगिन करें
(जब ज़रूरत हो तो दिखाने के लिए `cat .dashboard-pw` — इसे कभी चैट में
paste न करें)।

## 3. Telegram bot token rotate करें

```bash
# 1. Telegram में, @BotFather खोलें → /revoke → अपना bot चुनें → नया token कॉपी करें।
# 2. .env का backup लें और अपडेट करें (केवल token का मान बदलें):
cp -p .env .env.bak && chmod 600 .env.bak
# .env संपादित करें और TELEGRAM_BOT_TOKEN=<new-token> सेट करें, या यह चलाएं:
python3 - <<'EOF'
import re
tok = input("नया bot token paste करें: ").strip()
p = ".env"
s = open(p).read()
s2 = re.sub(r"^TELEGRAM_BOT_TOKEN=.*$", "TELEGRAM_BOT_TOKEN=" + tok, s, flags=re.M)
open(p, "w").write(s2)
print("अपडेट हुआ" if s2 != s else "कोई बदलाव नहीं — .env में key का नाम जांचें")
EOF
chmod 600 .env

# 3. Gateway को restart करें (exact-PID नियम: केवल तभी kill करें जब ठीक एक उम्मीदवार हो)
PID=$(pgrep -f "[g]ateway.*run")
[ "$(printf '%s' "$PID" | wc -l)" = "1" ] && kill "$PID" || echo "कोई एकल gateway PID नहीं — मैन्युअल रूप से जांचें"
sleep 3
bash start-gateway.sh
```

**सत्यापित करें:** Telegram में अपने bot को `/start` भेजें → वह जवाब देता
है। (यदि चुप हो, तो सामान्य कारण allowlist है: आपका संख्यात्मक ID `.env`
में `TELEGRAM_ALLOWED_USERS` में होना चाहिए।)

## अंतिम जांच

```bash
bash scripts/doctor.sh   # अपेक्षित: doctor: N ok, 0 FAIL, ...
```

## Rollback

```bash
BK=~/.hermuse-secret-backup/<date>   # वह तारीख जो आपने नियम 0 में उपयोग की थी
cp -p "$BK"/.tunnel-key ~/.
cp -p "$BK"/.env "$BK"/.dashboard-pw .
chmod 600 ~/.tunnel-key .env .dashboard-pw
# फिर वह *रिमोट* आधा हिस्सा दोबारा करें जो आप पहले ही बदल चुके हैं:
#  - tunnel key: restore की गई key के साथ खंड 1 का चरण 3 फिर चलाएं, फिर restart-tunnel.sh
#  - dashboard पासवर्ड: bash restart-9router.sh
#  - bot token: @BotFather /revoke फिर से संभव नहीं है — पुराना token हमेशा के
#    लिए मर चुका है। नया वाला रखें।
```

टिप्पणी: revoke किया गया Telegram bot token कभी restore नहीं हो सकता —
rollback केवल tunnel key और dashboard पासवर्ड पर लागू होता है।
