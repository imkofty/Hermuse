# Hướng dẫn xoay vòng kredensial

Khi nào nên xoay vòng: một secret có thể đã bị lộ (vô tình chia sẻ, bị commit
vào repo, bị nhìn thấy trên màn hình), một người từng có quyền truy cập không
nên còn giữ nó nữa, hoặc đơn giản là theo lịch. Xoay vòng rất rẻ — hãy làm
luôn thay vì tranh luận.

*English version: [key-rotation.md](key-rotation.md) · Versi Bahasa Indonesia: [key-rotation.id.md](key-rotation.id.md) · Versi Bahasa Malaysia: [key-rotation.ms.md](key-rotation.ms.md) · हिन्दी: [key-rotation.hi.md](key-rotation.hi.md) · 日本語: [key-rotation.ja.md](key-rotation.ja.md)*

## Các secret là gì

| Secret | Nằm ở | Được dùng bởi |
|---|---|---|
| Tunnel key | `~/.tunnel-key` (600) | `tunnel-client.mjs` ↔ Pages Functions (secret `TUNNEL_KEY`) |
| Mật khẩu dashboard 9Router | `.dashboard-pw` ở thư mục gốc repo (600) | `start-9router.sh` → 9Router |
| Token bot Telegram | `.env` ở thư mục gốc repo (600) | Telegram gateway |
| Token API Cloudflare | **không ở đâu cả — chỉ dùng tạm thời** | `wrangler` trong lúc thiết lập; không bao giờ được lưu |

Tất cả những thứ trên đều được gitignore. Hãy kiểm tra trước mỗi lần commit:
`git status --porcelain` không được liệt kê chúng.

## Quy tắc 0 — sao lưu trước khi xoay vòng

```bash
mkdir -p ~/.hermuse-secret-backup && chmod 700 ~/.hermuse-secret-backup
BK=~/.hermuse-secret-backup/$(date -u +%F)
mkdir -p "$BK"
cp -p ~/.tunnel-key .env .dashboard-pw "$BK/" 2>/dev/null
chmod 600 "$BK"/*
```

Nếu có gì trục trặc, hãy khôi phục từ `$BK` và lặp lại bước khởi động lại
tương ứng bên dưới.

## 1. Xoay vòng tunnel key (`TUNNEL_KEY`)

Key phải khớp ở **hai** nơi: `~/.tunnel-key` cục bộ của bạn và secret
`TUNNEL_KEY` của Pages project. Không khớp = client nhận HTTP 403 ở mọi lần
poll (nó thử lại với backoff, vì vậy hãy sửa ngay thay vì hoảng loạn).

```bash
# 1. Tạo và lưu key mới ở máy cục bộ
openssl rand -hex 32 > ~/.tunnel-key && chmod 600 ~/.tunnel-key

# 2. Tìm tên Pages project của bạn (từ URL tunnel hoặc wrangler.toml)
PROJECT="$(basename "$(tr -d '[:space:]' < .tunnel-url)" .pages.dev)"
echo "project: $PROJECT"

# 3. Đẩy key mới lên làm Pages secret (cần wrangler login hoặc CLOUDFLARE_API_TOKEN)
printf '%s' "$(cat ~/.tunnel-key)" | wrangler pages secret put TUNNEL_KEY --project-name="$PROJECT"

# 4. Khởi động lại tunnel client để nó nhận key mới
bash restart-tunnel.sh
```

**Kiểm tra:**

```bash
sleep 10
curl -s -o /dev/null -w '%{http_code}\n' --max-time 10 "$(cat .tunnel-url)"
# kỳ vọng 200 hoặc 307 (307 = chuyển hướng tới đăng nhập dashboard, bình thường)
bash scripts/doctor.sh   # kỳ vọng: 0 FAIL
```

Mở URL tunnel công khai trong trình duyệt — dashboard 9Router sẽ tải được.

## 2. Xoay vòng mật khẩu dashboard 9Router

```bash
# 1. Tạo và lưu mật khẩu mới (không lo ký tự xuống dòng ở cuối: $(...) sẽ cắt bỏ)
openssl rand -base64 24 | tr -d '\n' > .dashboard-pw && chmod 600 .dashboard-pw

# 2. Khởi động lại 9Router để nó nhận mật khẩu mới
bash restart-9router.sh
```

**Kiểm tra:**

```bash
sleep 8
curl -s -o /dev/null -w '%{http_code}\n' --max-time 10 http://127.0.0.1:20128/dashboard
# kỳ vọng 200 hoặc 307
```

Sau đó đăng nhập tại URL tunnel công khai bằng mật khẩu mới
(`cat .dashboard-pw` để hiển thị khi bạn cần — không bao giờ dán nó vào chat).

## 3. Xoay vòng token bot Telegram

```bash
# 1. Trong Telegram, mở @BotFather → /revoke → chọn bot của bạn → sao chép token MỚI.
# 2. Sao lưu và cập nhật .env (chỉ thay giá trị token):
cp -p .env .env.bak && chmod 600 .env.bak
# sửa .env và đặt TELEGRAM_BOT_TOKEN=<token-mới>, hoặc chạy:
python3 - <<'EOF'
import re
tok = input("dán token bot mới: ").strip()
p = ".env"
s = open(p).read()
s2 = re.sub(r"^TELEGRAM_BOT_TOKEN=.*$", "TELEGRAM_BOT_TOKEN=" + tok, s, flags=re.M)
open(p, "w").write(s2)
print("đã cập nhật" if s2 != s else "KHÔNG THAY ĐỔI — kiểm tra tên key trong .env")
EOF
chmod 600 .env

# 3. Khởi động lại gateway (quy tắc PID chính xác: chỉ kill khi có đúng một ứng viên)
PID=$(pgrep -f "[g]ateway.*run")
[ "$(printf '%s' "$PID" | wc -l)" = "1" ] && kill "$PID" || echo "không có gateway PID duy nhất — hãy kiểm tra thủ công"
sleep 3
bash start-gateway.sh
```

**Kiểm tra:** gửi `/start` cho bot của bạn trong Telegram → bot trả lời.
(Nếu im lặng, nguyên nhân thường gặp là allowlist: ID dạng số của bạn phải
nằm trong `TELEGRAM_ALLOWED_USERS` trong `.env`.)

## Kiểm tra cuối

```bash
bash scripts/doctor.sh   # kỳ vọng: doctor: N ok, 0 FAIL, ...
```

## Rollback

```bash
BK=~/.hermuse-secret-backup/<date>   # ngày bạn đã dùng ở Quy tắc 0
cp -p "$BK"/.tunnel-key ~/.
cp -p "$BK"/.env "$BK"/.dashboard-pw .
chmod 600 ~/.tunnel-key .env .dashboard-pw
# rồi làm lại phần *từ xa* mà bạn đã thay đổi:
#  - tunnel key: chạy lại bước 3 của mục 1 với key đã khôi phục, rồi restart-tunnel.sh
#  - mật khẩu dashboard: bash restart-9router.sh
#  - token bot: /revoke lại ở @BotFather là KHÔNG thể — token cũ đã chết
#    vĩnh viễn. Hãy giữ token mới.
```

Lưu ý: token bot Telegram đã bị thu hồi không bao giờ khôi phục được —
rollback chỉ áp dụng cho tunnel key và mật khẩu dashboard.
