# Troubleshooting

**यहाँ से शुरू करें:** `bash scripts/doctor.sh`। हर `[FAIL]` पंक्ति
`→ fix: <ठीक कमांड>` पर समाप्त होती है — पहले वही चलाएं; यह पृष्ठ सामान्य
वालों के पीछे का तर्क समझाता है। हर प्रविष्टि लक्षण → निदान → समाधान के
रूप में है, और हर कमांड copy-paste करके चलाया जा सकता है।

प्रविष्टियाँ केवल देखी गई विफलताओं से आती हैं — यहाँ कुछ भी गढ़ा नहीं गया है।

---

### 1. सार्वजनिक tunnel URL 502 / 503 / 504 देता है

Tunnel अवसंरचना ने जवाब दिया, लेकिन आपकी मशीन तक का forward चरण विफल रहा।

**निदान:**
```bash
curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$(cat .tunnel-url)"
curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:20128/dashboard
```

**समाधान:**
- स्थानीय curl `000` देता है (कुछ भी सुन नहीं रहा) → 9Router बंद है:
  `bash restart-9router.sh`
- स्थानीय curl `200`/`307` देता है (9Router स्वस्थ) → बीमार tunnel client
  है: `bash restart-tunnel.sh`

---

### 2. Bot चुप है, लेकिन gateway प्रक्रिया जीवित है

Telegram polling ठहर सकता है जबकि प्रक्रिया अभी भी मौजूद हो — "प्रक्रिया
जीवित है" का मतलब "gateway स्वस्थ है" नहीं है।

**निदान:**
```bash
bash scripts/doctor.sh   # assertion 7 reports heartbeat age / pid mismatch
# or manually:
cat "$HERMES_HOME/state/gateway.heartbeat"
```

**समाधान:**
```bash
DRY_RUN=1 bash gateway-watch.sh   # shows what it would do, changes nothing
bash gateway-watch.sh             # restarts the gateway on stale heartbeat
```

---

### 3. Dashboard बार-बार लॉगिन पर redirect करता है

Dashboard पासवर्ड फ़ाइल गायब है या आप जो टाइप कर रहे हैं उससे मेल नहीं
खाती।

**निदान:**
```bash
ls -l .dashboard-pw   # must exist, 600
```

**समाधान:** सही पासवर्ड `.dashboard-pw` में लिखें
(`chmod 600 .dashboard-pw`), फिर `bash restart-9router.sh` चलाएं ताकि
dashboard उसे उठा ले।

---

### 4. Bot किसी विशिष्ट उपयोगकर्ता को जवाब नहीं देता

Gateway default-deny है: केवल `TELEGRAM_ALLOWED_USERS` में मौजूद संख्यात्मक
Telegram ID को ही जवाब मिलते हैं। "Bot एक व्यक्ति के लिए चुप है" लगभग
हमेशा यही मामला होता है।

**निदान:** gateway env फ़ाइल (`.hermes/.env`) में उपयोगकर्ता के संख्यात्मक
ID को `TELEGRAM_ALLOWED_USERS` से जांचें।

**समाधान:** संख्यात्मक ID को `TELEGRAM_ALLOWED_USERS` में जोड़ें, फिर नई
allowlist के साथ gateway को restart करने के लिए `bash start-gateway.sh`
चलाएं।

---

### 5. install.sh के ठीक बाद `hermes: command not found`

`install.sh` `~/.local/bin` को `~/.bashrc` में जोड़ता है, लेकिन गैर-लॉगिन
shell उसे source नहीं करते।

**निदान:**
```bash
command -v hermes      # empty
ls ~/.local/bin/hermes # exists
```

**समाधान:**
```bash
export PATH="$HOME/.local/bin:$PATH"
```

---

### 6. `hermes doctor` विफलताएं बताता है

**निदान:** उसका आउटपुट पढ़ें। आम तौर पर देखा गया मामला प्रदाता auth
(समाप्त/रद्द मॉडल क्रेडेंशियल) है।

**समाधान:** मॉडल लॉगिन फिर से चलाएं: `hermes setup --portal`

---

### 7. Tunnel सेटअप के दौरान wrangler auth विफल

**निदान:** `wrangler whoami` — यदि यह त्रुटि दे, तो कोई मान्य auth मौजूद
नहीं है।

**समाधान:** एक auth रास्ता चुनें:
- `wrangler login` (ब्राउज़र OAuth), या
- क्षणिक env var के रूप में `CLOUDFLARE_API_TOKEN`।

Token को कभी `wrangler.toml` में न डालें।

---

### 8. Port 20128 पहले से उपयोग में है

एक पुराना (बिना supervisor वाला) 9Router port पर कब्ज़ा किए है, इसलिए
supervisor वाला bind नहीं हो सकता।

**निदान:**
```bash
curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:20128/dashboard
```
यदि कुछ जवाब देता है लेकिन प्रक्रिया supervisor वाली नहीं है, तो वह पुरानी
है।

**समाधान:** `bash restart-9router.sh` — यह exact-PID नियमों से पुरानी
प्रक्रिया को रोकता है और supervised instance शुरू करता है। कभी
`pkill -f 9router` न करें (यह बहुत व्यापक रूप से मेल खाता है, आपके अपने
shell सहित)।

---

### 9. doctor कहता है gateway गायब/अस्पष्ट है, लेकिन वह वास्तव में चल रहा है

आपकी मशीन पर gateway launcher एक ऐसा argv आकार उपयोग करता है जिसे doctor
का `pgrep` पैटर्न कवर नहीं करता। देखा गया मामला: provisioned venv launcher
`sys.argv = ['-c', 'gateway', 'run']` पास करता है — `-c` स्ट्रिंग के अंदर
अल्पविराम से अलग, सटे हुए शब्दों के रूप में नहीं — जिसे मूल केवल-सटे-शब्दों
वाला पैटर्न चूक गया।

**निदान:**
```bash
pgrep -af "gateway" | head   # find the real gateway cmdline
grep -n "gateway_pids" scripts/doctor.sh   # see the pattern doctor uses
```

**समाधान:** `scripts/doctor.sh` में `gateway_pids()` के separator class को
अपने launcher के आकार को कवर करने के लिए चौड़ा करें, फिर
`bash scripts/doctor.test.sh` फिर से चलाएं — commit करने से पहले सभी
परीक्षण पास होने चाहिए।

---

*English version: [troubleshooting.md](troubleshooting.md) · Versi Bahasa Indonesia: [troubleshooting.id.md](troubleshooting.id.md) · Versi Bahasa Malaysia: [troubleshooting.ms.md](troubleshooting.ms.md) · Tiếng Việt: [troubleshooting.vi.md](troubleshooting.vi.md) · 日本語: [troubleshooting.ja.md](troubleshooting.ja.md)*
