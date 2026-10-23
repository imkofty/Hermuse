# Troubleshooting

**Bắt đầu tại đây:** `bash scripts/doctor.sh`. Mỗi dòng `[FAIL]` đều kết thúc
bằng `→ fix: <lệnh chính xác>` — hãy chạy nó trước; trang này giải thích lý
do đằng sau những lỗi phổ biến. Mỗi mục có dạng Triệu chứng → Chẩn đoán →
Cách khắc phục, và mọi lệnh đều có thể copy-paste để chạy.

Các mục chỉ đến từ những lỗi đã quan sát thực tế — không có gì ở đây bị bịa ra.

---

### 1. URL tunnel công khai trả về 502 / 503 / 504

Hạ tầng tunnel đã trả lời, nhưng chặng chuyển tiếp tới máy của bạn thất bại.

**Chẩn đoán:**
```bash
curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$(cat .tunnel-url)"
curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:20128/dashboard
```

**Cách khắc phục:**
- Curl cục bộ trả về `000` (không có gì đang lắng nghe) → 9Router đã sập:
  `bash restart-9router.sh`
- Curl cục bộ trả về `200`/`307` (9Router khỏe) → tunnel client mới là kẻ
  bị bệnh: `bash restart-tunnel.sh`

---

### 2. Bot im lặng, nhưng tiến trình gateway vẫn còn sống

Telegram polling có thể bị treo trong khi tiến trình vẫn tồn tại — "tiến
trình còn sống" không có nghĩa là "gateway khỏe mạnh".

**Chẩn đoán:**
```bash
bash scripts/doctor.sh   # assertion 7 reports heartbeat age / pid mismatch
# or manually:
cat "$HERMES_HOME/state/gateway.heartbeat"
```

**Cách khắc phục:**
```bash
DRY_RUN=1 bash gateway-watch.sh   # shows what it would do, changes nothing
bash gateway-watch.sh             # restarts the gateway on stale heartbeat
```

---

### 3. Dashboard cứ chuyển hướng tới trang đăng nhập mãi

File mật khẩu dashboard bị thiếu hoặc không khớp với những gì bạn đang gõ.

**Chẩn đoán:**
```bash
ls -l .dashboard-pw   # must exist, 600
```

**Cách khắc phục:** ghi mật khẩu đúng vào `.dashboard-pw`
(`chmod 600 .dashboard-pw`), rồi `bash restart-9router.sh` để dashboard
nhận nó.

---

### 4. Bot không trả lời một người dùng cụ thể

Gateway là default-deny: chỉ các ID Telegram dạng số trong
`TELEGRAM_ALLOWED_USERS` mới nhận được trả lời. "Bot im lặng với một người"
hầu như luôn là chuyện này.

**Chẩn đoán:** đối chiếu ID dạng số của người dùng với `TELEGRAM_ALLOWED_USERS`
trong file env của gateway (`.hermes/.env`).

**Cách khắc phục:** thêm ID dạng số vào `TELEGRAM_ALLOWED_USERS`, rồi
`bash start-gateway.sh` để khởi động lại gateway với allowlist mới.

---

### 5. `hermes: command not found` ngay sau install.sh

`install.sh` thêm `~/.local/bin` vào `~/.bashrc`, nhưng các shell không
đăng nhập không nạp nó.

**Chẩn đoán:**
```bash
command -v hermes      # empty
ls ~/.local/bin/hermes # exists
```

**Cách khắc phục:**
```bash
export PATH="$HOME/.local/bin:$PATH"
```

---

### 6. `hermes doctor` báo lỗi

**Chẩn đoán:** đọc kết quả của nó. Trường hợp thường gặp là xác thực nhà
cung cấp (kredensial mô hình đã hết hạn/bị thu hồi).

**Cách khắc phục:** chạy lại đăng nhập mô hình: `hermes setup --portal`

---

### 7. Xác thực wrangler thất bại trong lúc thiết lập tunnel

**Chẩn đoán:** `wrangler whoami` — nếu nó báo lỗi, nghĩa là không có xác
thực hợp lệ nào.

**Cách khắc phục:** chọn một đường xác thực:
- `wrangler login` (OAuth qua trình duyệt), hoặc
- `CLOUDFLARE_API_TOKEN` dưới dạng biến môi trường tạm thời.

Không bao giờ đặt token vào `wrangler.toml`.

---

### 8. Cổng 20128 đã bị sử dụng

Một 9Router cũ (không có supervisor) đang giữ cổng, nên bản có supervisor
không bind được.

**Chẩn đoán:**
```bash
curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:20128/dashboard
```
Nếu có thứ gì đó trả lời nhưng tiến trình không phải bản có supervisor, nó
là bản cũ.

**Cách khắc phục:** `bash restart-9router.sh` — nó dừng tiến trình cũ bằng
quy tắc PID chính xác và khởi động bản có supervisor. Không bao giờ
`pkill -f 9router` (nó khớp quá rộng, kể cả shell của chính bạn).

---

### 9. doctor nói gateway bị thiếu/mơ hồ, nhưng thực ra nó đang chạy

Trình khởi chạy gateway trên máy của bạn dùng một dạng argv mà mẫu `pgrep`
của doctor không bao phủ. Trường hợp đã quan sát: trình khởi chạy venv được
cấp truyền `sys.argv = ['-c', 'gateway', 'run']` — cách nhau bằng dấu phẩy
bên trong chuỗi `-c`, không phải các từ kề nhau — mà mẫu chỉ-kề-nhau ban đầu
đã bỏ sót.

**Chẩn đoán:**
```bash
pgrep -af "gateway" | head   # find the real gateway cmdline
grep -n "gateway_pids" scripts/doctor.sh   # see the pattern doctor uses
```

**Cách khắc phục:** mở rộng lớp ký tự phân cách trong `gateway_pids()` trong
`scripts/doctor.sh` để bao phủ dạng trình khởi chạy của bạn, rồi chạy lại
`bash scripts/doctor.test.sh` — mọi kiểm thử phải đạt trước khi commit.

---

*English version: [troubleshooting.md](troubleshooting.md) · Versi Bahasa Indonesia: [troubleshooting.id.md](troubleshooting.id.md) · Versi Bahasa Malaysia: [troubleshooting.ms.md](troubleshooting.ms.md) · हिन्दी: [troubleshooting.hi.md](troubleshooting.hi.md) · 日本語: [troubleshooting.ja.md](troubleshooting.ja.md)*
