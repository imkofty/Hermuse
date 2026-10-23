# Hermuse — self-hosted AI agent stack (Hermes + 9Router + Telegram)

![Hermuse banner](assets/banner.png)

[🇬🇧 English](README.md) · [🇮🇩 Indonesia](README.id.md) · [🇲🇾 Malaysia](README.ms.md) · [🇻🇳 Việt Nam](README.vi.md) · 🇮🇳 **हिन्दी** · [🇯🇵 日本語](README.ja.md)

[![Stars](https://img.shields.io/github/stars/imkofty/Hermuse?style=for-the-badge&logo=github&color=20808D)](https://github.com/imkofty/Hermuse/stargazers)
[![Forks](https://img.shields.io/github/forks/imkofty/Hermuse?style=for-the-badge&logo=github&color=4DD0E1)](https://github.com/imkofty/Hermuse/network/members)
[![Issues](https://img.shields.io/github/issues/imkofty/Hermuse?style=for-the-badge&logo=github&color=FFB454)](https://github.com/imkofty/Hermuse/issues)
[![License: MIT](https://img.shields.io/github/license/imkofty/Hermuse?style=for-the-badge&color=3FB950)](LICENSE)
[![doctor](https://github.com/imkofty/Hermuse/actions/workflows/doctor.yml/badge.svg)](https://github.com/imkofty/Hermuse/actions/workflows/doctor.yml)

[![Linux](https://img.shields.io/badge/OS-Linux-FCC624?style=for-the-badge&logo=linux&logoColor=black)](https://ubuntu.com/)
[![Node.js](https://img.shields.io/badge/node-%3E%3D18-339933?style=for-the-badge&logo=node.js&logoColor=white)](https://nodejs.org/)
[![Telegram](https://img.shields.io/badge/Telegram-Gateway-26A5E4?style=for-the-badge&logo=telegram&logoColor=white)](https://core.telegram.org/bots)
[![Cloudflare](https://img.shields.io/badge/Cloudflare-Tunnel-F68204?style=for-the-badge&logo=cloudflare&logoColor=white)](https://www.cloudflare.com/)
[![Bash](https://img.shields.io/badge/Bash-Scripts-4EAA25?style=for-the-badge&logo=gnu-bash&logoColor=white)]()

**Hermuse = Hermes + Muse.** Hermes Agent (Nous Research का AI agent) +
9Router + एक Telegram gateway को अपने ही सर्वर पर चलाने के लिए स्क्रिप्ट और
गाइड — Muse के VM पर चल रहे stack की हूबहू प्रतिकृति।

**अंतिम परिणाम:** आपका अपना Telegram AI bot, 24/7 ऑनलाइन और किसी भी समय
चैट के लिए तैयार, साथ ही एक मॉडल dashboard जिसे आप किसी भी ब्राउज़र से
खोल सकते हैं।

## त्वरित शुरुआत

आपको चाहिए:

- Muse जैसा एक Linux VM (Ubuntu 22.04/24.04; 2 vCPU / 4 GB RAM पर्याप्त है)
- एक मुफ़्त Cloudflare खाता (dashboard tunnel के लिए)
- एक Telegram bot ([@BotFather](https://t.me/BotFather) के ज़रिए मुफ़्त)

**इन सब में नए हैं?** इस क्रम में चलें:

1. `bash scripts/install.sh` — सब कुछ इंस्टॉल करता है (निर्भरताएं, Hermes, 9Router)
Verify: `hermes --version` → एक संस्करण पंक्ति छापता है; `9router --version` → एक संस्करण छापता है
2. `hermes setup --portal` — मॉडल लॉगिन; `hermes gateway setup` — अपना Telegram bot जोड़ें
Verify: अपने bot को `/start` भेजें → वह जवाब देता है (आपका संख्यात्मक Telegram ID gateway allowlist में होना चाहिए)
3. `bash scripts/setup-tunnel.sh <pages-project-name> <d1-name>` — Cloudflare tunnel इंस्टॉल करें
Verify: `pgrep -f "tunnel-client[.]mjs"` → एक PID छापता है
4. नीचे दिए [सही बूट क्रम](#सही-बूट-क्रम) का पालन करें, फिर watchdog को cron पर रखें
Verify: `bash scripts/doctor.sh` → सारांश में `0 FAIL` दिखता है

पहले से सहज हैं और सीधे परिचालन स्क्रिप्ट चाहिए? [फ़ाइल लेआउट](#फ़ाइल-लेआउट)
तालिका देखें।

## यह कैसे काम करता है

```
Telegram (you)
   │ polling
   ▼
Hermes gateway  ──▶  model:
   (run-hermes.sh)        ├─▶ Nous (direct, via OAuth / API key)
                          └─▶ 9Router  (127.0.0.1:20128, OpenAI-compatible)

Browser (internet)
   │ plain HTTPS
   ▼
<your-project>.pages.dev  (Cloudflare Pages Functions)
   │ request/response queue
   ▼
D1  (tunnel_requests / tunnel_responses tables)
   ▲ ~20s HTTPS long-poll
   │
tunnel-client.mjs  (on your VM)
   │ forward
   ▼
9Router at 127.0.0.1:20128
```

**Long-poll क्यों?** `/__tunnel/poll` endpoint, जब queue खाली हो, तो जवाब
देने से पहले कनेक्शन को ~20 सेकंड तक रोके रखता है (या अनुरोध आते ही तुरंत
जवाब देता है)। इसके बिना, हर 400ms–2.5s पर poll करने से Cloudflare
Workers की **100k requests/day मुफ़्त-कोटा** सीमा कुछ ही घंटों में खत्म हो
जाती; long-poll के साथ, निष्क्रिय उपयोग घटकर ~4,300 requests/day रह जाता
है। क्रियान्वयन के लिए `tunnel/pages-tunnel/functions/__tunnel/poll.js`
देखें।

9Router केवल `127.0.0.1` पर bind होता है (सुरक्षित, कभी उजागर नहीं)।
Polling tunnel इसलिए उपयोग होता है क्योंकि मूल VM नेटवर्क पर WebSocket,
QUIC/UDP, और edge तक `cloudflared` कनेक्शन सभी विफल रहे — [विफलता
अभिलेख](docs/arsip-tunnel-gagal.md) देखें। एक सामान्य VM/नेटवर्क पर, सादा
`cloudflared` शायद सरल रहेगा।

## फ़ाइल लेआउट

| File | भूमिका |
|---|---|
| `run-hermes.sh` | Hermes CLI चलाता है। डिफ़ॉल्ट: `scripts/install.sh` द्वारा इंस्टॉल मानक `hermes` कमांड को forward करता है। वैकल्पिक venv मोड: `HERMES_VENV` + `HERMES_SRC` env vars सेट करें (पहले से सत्यापित; अमान्य पथ स्पष्ट संदेश के साथ तेज़ी से विफल होते हैं)। |
| `start-gateway.sh` | Telegram gateway को detached चलाता है (`setsid`+`nohup`)। |
| `start-9router.sh` | 9Router supervisor: `127.0.0.1:20128` पर bind होता है, crash पर auto-restart। Dashboard पासवर्ड `.dashboard-pw` (600) से पढ़ा जाता है। |
| `start-pages-tunnel.sh` | Tunnel client supervisor (`tunnel-client.mjs`), auto-restart। |
| `restart-9router.sh` | पुरानी 9Router प्रक्रिया को मारता है (सुरक्षित पैटर्न, anti self-kill) + supervisor को detached शुरू करता है। |
| `restart-tunnel.sh` | पुराने tunnel client को मारता है + supervisor को detached शुरू करता है। |
| `watchdog.sh` | 9Router, tunnel client, gateway की जांच करता है; जो मर गया उसे restart करता है। Cron के लिए। |
| `gateway-watch.sh` | Telegram gateway के लिए anti-stall watchdog: केवल "प्रक्रिया जीवित है" से नहीं, event-loop heartbeat + adapter गतिविधि से मूक ठहराव का पता लगाता है। Cron के लिए (हर 5 मिनट)। |
| `tunnel-client.mjs` | Polling client: Pages से queue खींचता है, स्थानीय 9Router को forward करता है, जवाब वापस भेजता है। |
| `tunnel/` | D1 schema (`schema.sql`) + Pages Functions + `wrangler.toml.example`। |
| `scripts/install.sh` | शुरुआत से इंस्टॉल: निर्भरताएं, Node.js LTS, Hermes, 9Router। |
| `scripts/setup-tunnel.sh` | Tunnel सेटअप: key बनाएं → D1 बनाएं → Pages deploy करें → secret सेट करें। |
| `scripts/setup-tunnel-cloudflared.sh` | सामान्य नेटवर्कों के लिए `cloudflared` के ज़रिए वैकल्पिक tunnel (sandbox के लिए नहीं): binary इंस्टॉल, लॉगिन, tunnel बनाना, DNS route, चलाने के निर्देश। |
| `docs/arsip-tunnel-gagal.md` | अभिलेख: मूल VM नेटवर्क पर `cloudflared` और Tailscale की विफलताएं (इंडोनेशियाई में)। |

## सही बूट क्रम

क्रम से चलाएं (एक बार पर्याप्त है; supervisor + watchdog बाकी संभालते हैं):

1. पहले 9Router (detached supervisor, auto-restart):
   `bash restart-9router.sh`
Verify: `curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:20128/dashboard` → `200` या `307` छापता है (307 = लॉगिन पर redirect, सामान्य)

2. Tunnel client (`TUNNEL_BASE_URL` या `.tunnel-url` फ़ाइल चाहिए):
   `export TUNNEL_BASE_URL='https://<your-project>.pages.dev'` फिर `bash restart-tunnel.sh`
Verify: `pgrep -f "tunnel-client[.]mjs"` → एक PID छापता है

3. Telegram gateway (detached):
   `bash start-gateway.sh`
Verify: `pgrep -f "[g]ateway['\", ]+run"` → ठीक एक PID छापता है

फिर ब्राउज़र में `https://<your-project>.pages.dev` खोलें — 9Router
dashboard दिखना चाहिए। यदि आपको `504 tunnel timeout (client offline?)`
मिले, तो tunnel client अभी नहीं चल रहा है।

## Watchdog (हर 5 मिनट cron)

```bash
crontab -e
# यह पंक्ति जोड़ें (पथ समायोजित करें):
*/5 * * * * /path/to/Hermuse/watchdog.sh
```

Watchdog तीन चीज़ें जांचता है — 9Router (`/dashboard` पर `curl`), tunnel
client (`pgrep tunnel-client[.]mjs`), Telegram gateway (`gateway.*run`) —
और जो मर गया उसे `restart-*` स्क्रिप्ट से restart करता है। जब सब स्वस्थ
हो तो यह चुप रहता है (कोई log नहीं लिखता); यह केवल तब log करता है जब
वास्तव में कुछ restart करता है।

> Cron के लिए: tunnel URL को इस फ़ोल्डर में `.tunnel-url` फ़ाइल (chmod 600)
> में रखें, क्योंकि cron आपके इंटरैक्टिव environment variables को inherit
> नहीं करता:
> `echo -n 'https://<your-project>.pages.dev' > .tunnel-url && chmod 600 .tunnel-url`

## Anti-stall gateway watchdog (वैकल्पिक लेकिन अनुशंसित)

ऊपर वाला `watchdog.sh` केवल "प्रक्रिया मौजूद है या नहीं" जांचता है। यदि
Telegram polling ठहर जाए जबकि प्रक्रिया अभी भी जीवित हो, तो यह निकल
जाता है। `gateway-watch.sh` इस कमी को तीन परतों से बंद करता है:

1. Gateway PID गायब → तुरंत restart।
2. Event-loop heartbeat (`$HERMES_HOME/state/gateway.heartbeat`, gateway
   द्वारा स्वतः लिखा जाता है) >120s पुराना → तुरंत restart।
3. Heartbeat ताज़ा है लेकिन `gateway.log` में 15 मिनट से 0 Telegram
   adapter गतिविधि → संदिग्ध चिह्नित करें, लगातार 2 runs में पुष्टि होने
   पर restart करें।

कठोर नियम: केवल तभी kill करें जब ठीक 1 उम्मीदवार PID हो (कोई अस्पष्टता
नहीं)। 9Router को कभी नहीं छूता। बिना वास्तविक कार्रवाई के dry-run:
`DRY_RUN=1 bash gateway-watch.sh`।

```bash
crontab -e
# जोड़ें (watchdog.sh के साथ बारी-बारी चल सकता है):
*/5 * * * * /path/to/Hermuse/gateway-watch.sh
```

## Reboot के बाद auto-start

`scripts/start-all.sh` जो भी Hermuse घटक बंद हो उसे शुरू करता है (9Router,
tunnel client, Telegram gateway) — idempotent, चल रहे घटकों को छुआ नहीं
जाता:

```bash
bash /path/to/Hermuse/scripts/start-all.sh
```

इसे हर VPS reboot पर स्वतः चलाने के लिए, एक सामान्य Linux VPS के लिए:

**विकल्प 1 — cron `@reboot`:**

```bash
crontab -e
# जोड़ें:
@reboot sleep 30 && /path/to/Hermuse/scripts/start-all.sh >> /path/to/Hermuse/boot.log 2>&1
```

**विकल्प 2 — systemd user unit** (`~/.config/systemd/user/hermuse.service`):

```ini
[Unit]
Description=Hermuse stack (9Router + tunnel + Telegram gateway)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/path/to/Hermuse/scripts/start-all.sh
RemainAfterExit=yes

[Install]
WantedBy=default.target
```

```bash
systemctl --user daemon-reload
systemctl --user enable --now hermuse.service
# लॉगिन के बिना चलाने के लिए: sudo loginctl enable-linger $USER
```

(दोनों उदाहरण एक सामान्य VPS/नेटवर्क के लिए हैं और हर distro पर परखे नहीं
गए हैं — अपने सिस्टम के अनुसार ढालें। सुरक्षा जाल के रूप में 5-मिनट
watchdog cron फिर भी अनुशंसित है।)

## शुरुआत से इंस्टॉल

कुछ भी नहीं से शुरू कर रहे हैं? यहाँ से शुरू करें:

```bash
bash scripts/install.sh        # dependencies + Node.js + Hermes + 9Router + hermes doctor
```
(पासवर्ड-रहित `sudo` चाहिए, या root के रूप में चलाएं — अन्यथा स्क्रिप्ट
तेज़ी से विफल हो जाती है)

फिर मॉडल प्रदाता और Telegram gateway विज़ार्ड:

```bash
hermes setup --portal   # OAuth के ज़रिए Nous में लॉगिन करें (या: प्रदाता चुनने के लिए hermes model)
hermes gateway setup    # अपना Telegram bot token + संख्यात्मक-ID allowlist डालें
```

अंत में, Cloudflare tunnel सेटअप:

```bash
CLOUDFLARE_API_TOKEN='<token>' bash scripts/setup-tunnel.sh <pages-project-name> <d1-name>
```

(Cloudflare token केवल क्षणिक रूप से उपयोग होता है — यह किसी फ़ाइल में
सहेजा नहीं जाता।)

## सुरक्षा — इसे न छोड़ें

- Secret फ़ाइलें **हमेशा `chmod 600`** और **कभी commit नहीं**:
  `.env`, `.tunnel-key`, `.tunnel-url`, `.dashboard-pw`, `wrangler.toml`
  (सभी `.gitignore` में हैं)।
- Telegram gateway: **default-deny**। केवल `TELEGRAM_ALLOWED_USERS` में
  मौजूद संख्यात्मक ID ही bot का उपयोग कर सकते हैं (`TELEGRAM_BOT_TOKEN` +
  `TELEGRAM_ALLOWED_USERS` `.env` में रहते हैं)।
- **9Router dashboard पासवर्ड:** `scripts/setup-tunnel.sh` आपके लिए
  `.dashboard-pw` (600) बनाता है, और यदि सार्वजनिक tunnel कॉन्फ़िगर हो तो
  वह फ़ाइल गायब या खाली होने पर `start-9router.sh` बूट होने से इनकार कर
  देता है। यदि आप अपना पासवर्ड चाहते हैं तो उसकी सामग्री बदल दें।
- Port 20128 को असुरक्षित रूप से इंटरनेट पर उजागर न करें; 9Router केवल
  `127.0.0.1` पर bind होता है।
- यदि आपका Telegram bot token लीक हो जाए: @BotFather में `/revoke` करें,
  `.env` में बदलें, gateway restart करें।
- **क्रेडेंशियल rotate कर रहे हैं?** चरण-दर-चरण [क्रेडेंशियल rotation गाइड](docs/key-rotation.hi.md) का पालन करें (tunnel key, dashboard पासवर्ड, bot token)।
- **Tunnel auth fail-closed है।** Pages functions हर poll/respond कॉल को
  अस्वीकार करते हैं जब तक `TUNNEL_KEY` Pages secret के रूप में सेट न हो
  और client की key से मेल न खाए — unset secret का अब चुपचाप अर्थ "खुला
  tunnel" नहीं है।
- **मौजूदा tunnel डेटाबेस को upgrade कर रहे हैं?** एक-बारगी migrations को
  **क्रम से** चलाएं — पुराने डेटाबेस को सभी चार चाहिए, केवल पहला नहीं:
  `wrangler d1 execute <db-name> --remote --file=tunnel/migrations/001-claim-lease.sql`
  फिर `002-idempotency-ratelimit.sql`, फिर `003-response-idempotency.sql`,
  फिर `004-idempotency-principal.sql`
  (वही कमांड, अलग `--file`)। नए इंस्टॉल को इनकी ज़रूरत नहीं
  (schema.sql में पहले से सब कुछ है), और `scripts/setup-tunnel.sh` फिर से
  चलाने पर ये आपके लिए लागू हो जाते हैं। बाद में
  `bash scripts/check-tunnel-schema.sh <db-name>` से सत्यापित करें — जो
  कुछ भी अभी गायब हो उसके लिए यह ठीक सुधार कमांड छापता है।
- **Payloads D1 की भंडारण क्षमता तक सीमित हैं।** D1 एक string/BLOB/row
  को 2,000,000 bytes तक सीमित करता है और bodies Base64 के रूप में यात्रा
  करती हैं, इसलिए tunnel request/response bodies को अधिकतम 1,350,000 कच्चे
  bytes (1,800,000 Base64 अक्षर) तक स्वीकार करता है; बड़े payloads को
  विफल डेटाबेस insert के बजाय स्पष्ट 413 मिलता है।
- **Idempotency कॉलर से बंधी है।** सहेजा गया जवाब केवल तभी replay होता है
  जब idempotency key, कॉलर का क्रेडेंशियल, और ठीक-ठीक request payload —
  तीनों मेल खाएं। किसी key को अलग payload के साथ फिर से उपयोग करने पर
  409 Conflict मिलता है; किसी अन्य कॉलर का जवाब आपको कभी replay नहीं
  होता।
- **Watchdog स्वास्थ्य जांच असली tunnel से गुज़रती है।** `.health-key`
  फ़ाइल (जो `scripts/setup-tunnel.sh` बनाता है) के साथ, watchdog और doctor
  सार्वजनिक tunnel को एक प्रमाणित nonce probe से end-to-end सत्यापित करते
  हैं जिसका जवाब स्थानीय client देता है — केवल edge का 401/403 अब
  "स्वस्थ" नहीं गिना जाता। यदि `.tunnel-url` मौजूद है लेकिन `.health-key`
  गायब या खाली है, तो watchdog एक कठोर ERROR log करता है और probe को
  चुपचाप छोड़ने के बजाय tunnel जांच को विफल करता है।

## टिप्पणियाँ

<details>
<summary><strong>मूल नेटवर्क पर क्या विफल रहा (अभिलेख)</strong></summary>

मूल VM नेटवर्क पर, दो मानक दृष्टिकोण **पूरी तरह विफल** रहे:

- **Cloudflare Tunnel (`cloudflared`)** — QUIC/UDP अवरुद्ध, edge IP तक TLS
  में हस्तक्षेप, proxy ने port 7844 पर CONNECT अस्वीकार किया।
- **Tailscale** — control plane नेटवर्क से गुज़र नहीं सका (MITM से
  HTTP 400)।

विवरण + साफ़ किए गए config उदाहरण:
[docs/arsip-tunnel-gagal.md](docs/arsip-tunnel-gagal.md) (इंडोनेशियाई में)।
एक सामान्य VM/नेटवर्क पर दोनों शायद सबसे आसान रास्ता हैं।

</details>

## लाइसेंस

MIT.
