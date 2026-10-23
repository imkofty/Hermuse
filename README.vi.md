# Hermuse — self-hosted AI agent stack (Hermes + 9Router + Telegram)

![Hermuse banner](assets/banner.png)

[🇬🇧 English](README.md) · [🇮🇩 Indonesia](README.id.md) · [🇲🇾 Malaysia](README.ms.md) · 🇻🇳 **Việt Nam** · [🇮🇳 हिन्दी](README.hi.md) · [🇯🇵 日本語](README.ja.md)

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

**Hermuse = Hermes + Muse.** Các script và hướng dẫn để chạy Hermes Agent (AI
agent từ Nous Research) + 9Router + một Telegram gateway trên server của
chính bạn — một bản sao chính xác của stack đang chạy trên VM của Muse.

**Kết quả cuối cùng:** bot AI Telegram cá nhân của bạn, trực tuyến 24/7 và
sẵn sàng trò chuyện bất cứ lúc nào, cộng với một dashboard mô hình mà bạn có
thể mở từ bất kỳ trình duyệt nào.

## Bắt đầu nhanh

Những gì bạn cần:

- Một VM Linux như của Muse (Ubuntu 22.04/24.04; 2 vCPU / 4 GB RAM là đủ)
- Một tài khoản Cloudflare miễn phí (cho tunnel dashboard)
- Một bot Telegram (miễn phí qua [@BotFather](https://t.me/BotFather))

**Mới làm quen với tất cả những thứ này?** Hãy làm theo thứ tự sau:

1. `bash scripts/install.sh` — cài đặt mọi thứ (các gói phụ thuộc, Hermes, 9Router)
Verify: `hermes --version` → in ra một dòng phiên bản; `9router --version` → in ra một phiên bản
2. `hermes setup --portal` — đăng nhập mô hình; `hermes gateway setup` — kết nối bot Telegram của bạn
Verify: gửi `/start` cho bot của bạn → bot trả lời (ID Telegram dạng số của bạn phải nằm trong allowlist của gateway)
3. `bash scripts/setup-tunnel.sh <pages-project-name> <d1-name>` — cài đặt tunnel Cloudflare
Verify: `pgrep -f "tunnel-client[.]mjs"` → in ra một PID
4. Làm theo [thứ tự khởi động đúng](#thứ-tự-khởi-động-đúng) bên dưới, rồi đặt watchdog vào cron
Verify: `bash scripts/doctor.sh` → phần tóm tắt hiển thị `0 FAIL`

Đã quen rồi và muốn dùng trực tiếp các script vận hành? Xem bảng
[bố cục file](#bố-cục-file).

## Cách hoạt động

```
Telegram (bạn)
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

**Vì sao dùng long-poll?** Endpoint `/__tunnel/poll` giữ kết nối trong
~20 giây khi hàng đợi trống trước khi phản hồi (hoặc phản hồi ngay khi có
request đến). Nếu không, việc poll mỗi 400ms–2.5s sẽ đốt hết **hạn mức
100k requests/ngày của gói miễn phí** Cloudflare Workers chỉ trong vài giờ;
với long-poll, mức dùng khi nhàn rỗi giảm xuống ~4.300 requests/ngày. Xem
`tunnel/pages-tunnel/functions/__tunnel/poll.js` để biết cách triển khai.

9Router chỉ bind vào `127.0.0.1` (an toàn, không bao giờ lộ ra ngoài).
Polling tunnel được dùng vì trên mạng VM gốc, các kết nối WebSocket,
QUIC/UDP và `cloudflared` tới edge đều thất bại — xem
[hồ sơ thất bại](docs/arsip-tunnel-gagal.md). Trên một VM/mạng bình thường,
`cloudflared` thuần có lẽ đơn giản hơn.

## Bố cục file

| File | Vai trò |
|---|---|
| `run-hermes.sh` | Chạy Hermes CLI. Mặc định: chuyển tiếp tới lệnh `hermes` tiêu chuẩn do `scripts/install.sh` cài đặt. Chế độ venv tùy chọn: đặt biến môi trường `HERMES_VENV` + `HERMES_SRC` (được kiểm tra trước; đường dẫn không hợp lệ sẽ thất bại nhanh với thông báo rõ ràng). |
| `start-gateway.sh` | Chạy Telegram gateway ở chế độ tách rời (`setsid`+`nohup`). |
| `start-9router.sh` | Supervisor của 9Router: bind `127.0.0.1:20128`, tự khởi động lại khi crash. Mật khẩu dashboard được đọc từ `.dashboard-pw` (600). |
| `start-pages-tunnel.sh` | Supervisor của tunnel client (`tunnel-client.mjs`), tự khởi động lại. |
| `restart-9router.sh` | Kill tiến trình 9Router cũ (mẫu an toàn, chống tự kill) + khởi động supervisor ở chế độ tách rời. |
| `restart-tunnel.sh` | Kill tunnel client cũ + khởi động supervisor ở chế độ tách rời. |
| `watchdog.sh` | Kiểm tra 9Router, tunnel client, gateway; khởi động lại bất cứ thành phần nào đã chết. Dành cho cron. |
| `gateway-watch.sh` | Watchdog chống treo cho Telegram gateway: phát hiện tình trạng treo ngầm qua heartbeat của event-loop + hoạt động của adapter, không chỉ "tiến trình còn sống". Dành cho cron (mỗi 5 phút). |
| `tunnel-client.mjs` | Polling client: kéo hàng đợi từ Pages, chuyển tiếp tới 9Router cục bộ, gửi phản hồi trở lại. |
| `tunnel/` | Schema D1 (`schema.sql`) + Pages Functions + `wrangler.toml.example`. |
| `scripts/install.sh` | Cài đặt từ đầu: các gói phụ thuộc, Node.js LTS, Hermes, 9Router. |
| `scripts/setup-tunnel.sh` | Thiết lập tunnel: tạo key → tạo D1 → deploy Pages → đặt secret. |
| `scripts/setup-tunnel-cloudflared.sh` | Tunnel thay thế qua `cloudflared` cho các mạng bình thường (không phải sandbox): cài binary, đăng nhập, tạo tunnel, route DNS, hướng dẫn chạy. |
| `docs/arsip-tunnel-gagal.md` | Hồ sơ: các thất bại của `cloudflared` & Tailscale trên mạng VM gốc (bằng tiếng Indonesia). |

## Thứ tự khởi động đúng

Chạy theo thứ tự (một lần là đủ; các supervisor + watchdog lo phần còn lại):

1. 9Router trước (supervisor tách rời, tự khởi động lại):
   `bash restart-9router.sh`
Verify: `curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:20128/dashboard` → in ra `200` hoặc `307` (307 = chuyển hướng tới trang đăng nhập, bình thường)

2. Tunnel client (cần `TUNNEL_BASE_URL` hoặc file `.tunnel-url`):
   `export TUNNEL_BASE_URL='https://<your-project>.pages.dev'` rồi `bash restart-tunnel.sh`
Verify: `pgrep -f "tunnel-client[.]mjs"` → in ra một PID

3. Telegram gateway (tách rời):
   `bash start-gateway.sh`
Verify: `pgrep -f "[g]ateway['\", ]+run"` → in ra đúng một PID

Sau đó mở `https://<your-project>.pages.dev` trong trình duyệt — dashboard
9Router sẽ hiện ra. Nếu bạn nhận được `504 tunnel timeout (client offline?)`,
nghĩa là tunnel client chưa chạy.

## Watchdog (cron mỗi 5 phút)

```bash
crontab -e
# thêm dòng này (điều chỉnh đường dẫn):
*/5 * * * * /path/to/Hermuse/watchdog.sh
```

Watchdog kiểm tra ba thứ — 9Router (`curl` tới `/dashboard`), tunnel client
(`pgrep tunnel-client[.]mjs`), Telegram gateway (`gateway.*run`) — và khởi
động lại bất cứ thành phần nào đã chết qua các script `restart-*`. Nó giữ
im lặng (không ghi log) khi mọi thứ khỏe mạnh; nó chỉ ghi log khi thực sự
khởi động lại thứ gì đó.

> Đối với cron: lưu URL tunnel trong file `.tunnel-url` (chmod 600) trong
> thư mục này, vì cron không kế thừa các biến môi trường tương tác của bạn:
> `echo -n 'https://<your-project>.pages.dev' > .tunnel-url && chmod 600 .tunnel-url`

## Watchdog chống treo cho gateway (tùy chọn nhưng khuyến nghị)

`watchdog.sh` ở trên chỉ kiểm tra "tiến trình có tồn tại hay không". Nếu
Telegram polling bị treo trong khi tiến trình vẫn còn sống, nó sẽ lọt qua.
`gateway-watch.sh` lấp khoảng trống đó bằng ba lớp:

1. Gateway PID bị thiếu → khởi động lại ngay.
2. Heartbeat của event-loop (`$HERMES_HOME/state/gateway.heartbeat`, do
   gateway tự ghi) cũ hơn >120s → khởi động lại ngay.
3. Heartbeat còn mới nhưng 0 hoạt động Telegram adapter trong `gateway.log`
   suốt 15 phút → đánh dấu nghi ngờ, khởi động lại nếu xác nhận ở 2 lần
   chạy liên tiếp.

Quy tắc cứng: chỉ kill khi có đúng 1 PID ứng viên (không mơ hồ).
Không bao giờ đụng vào 9Router. Chạy thử không hành động thật:
`DRY_RUN=1 bash gateway-watch.sh`.

```bash
crontab -e
# thêm (có thể xen kẽ với watchdog.sh):
*/5 * * * * /path/to/Hermuse/gateway-watch.sh
```

## Tự khởi động sau khi reboot

`scripts/start-all.sh` khởi động bất kỳ thành phần Hermuse nào đang tắt
(9Router, tunnel client, Telegram gateway) — idempotent, các thành phần
đang chạy không bị đụng vào:

```bash
bash /path/to/Hermuse/scripts/start-all.sh
```

Để nó chạy tự động mỗi lần VPS reboot, đối với một VPS Linux bình thường:

**Lựa chọn 1 — cron `@reboot`:**

```bash
crontab -e
# thêm:
@reboot sleep 30 && /path/to/Hermuse/scripts/start-all.sh >> /path/to/Hermuse/boot.log 2>&1
```

**Lựa chọn 2 — systemd user unit** (`~/.config/systemd/user/hermuse.service`):

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
# để chạy mà không cần đăng nhập: sudo loginctl enable-linger $USER
```

(Cả hai ví dụ đều dành cho VPS/mạng bình thường và chưa được kiểm thử trên
mọi distro — hãy điều chỉnh theo hệ thống của bạn. Cron watchdog 5 phút
vẫn được khuyến nghị làm lưới an toàn.)

## Cài đặt từ đầu

Bắt đầu từ con số không? Bắt đầu tại đây:

```bash
bash scripts/install.sh        # dependencies + Node.js + Hermes + 9Router + hermes doctor
```
(cần `sudo` không mật khẩu, hoặc chạy với quyền root — nếu không script sẽ
thất bại nhanh)

Sau đó là các wizard nhà cung cấp mô hình & Telegram gateway:

```bash
hermes setup --portal   # đăng nhập Nous qua OAuth (hoặc: hermes model để chọn nhà cung cấp)
hermes gateway setup    # nhập token bot Telegram + allowlist ID dạng số của bạn
```

Cuối cùng, thiết lập tunnel Cloudflare:

```bash
CLOUDFLARE_API_TOKEN='<token>' bash scripts/setup-tunnel.sh <pages-project-name> <d1-name>
```

(Token Cloudflare chỉ được dùng tạm thời — nó không được lưu trong bất kỳ
file nào.)

## Bảo mật — đừng bỏ qua

- Các file secret **luôn `chmod 600`** và **không bao giờ được commit**:
  `.env`, `.tunnel-key`, `.tunnel-url`, `.dashboard-pw`, `wrangler.toml`
  (tất cả đều được `.gitignore` bao phủ).
- Telegram gateway: **default-deny**. Chỉ các ID dạng số trong
  `TELEGRAM_ALLOWED_USERS` mới dùng được bot (`TELEGRAM_BOT_TOKEN` +
  `TELEGRAM_ALLOWED_USERS` nằm trong `.env`).
- **Mật khẩu dashboard 9Router:** `scripts/setup-tunnel.sh` tạo
  `.dashboard-pw` (600) cho bạn, và `start-9router.sh` từ chối khởi động
  khi tunnel công khai đã được cấu hình mà file đó bị thiếu hoặc trống.
  Hãy thay nội dung của nó nếu bạn muốn mật khẩu của riêng mình.
- Đừng để lộ cổng 20128 ra internet mà không có bảo vệ; 9Router chỉ bind
  vào `127.0.0.1`.
- Nếu token bot Telegram của bạn bị lộ: `/revoke` trong @BotFather, thay
  nó trong `.env`, khởi động lại gateway.
- **Muốn xoay vòng kredensial?** Làm theo [hướng dẫn xoay vòng kredensial](docs/key-rotation.vi.md) từng bước (tunnel key, mật khẩu dashboard, token bot).
- **Xác thực tunnel fail-closed.** Các Pages function từ chối mọi lệnh gọi
  poll/respond trừ khi `TUNNEL_KEY` được đặt làm Pages secret VÀ khớp với
  key của client — secret chưa được đặt không còn lặng lẽ có nghĩa là
  "tunnel mở" nữa.
- **Đang nâng cấp một cơ sở dữ liệu tunnel hiện có?** Chạy các migration
  một lần **theo thứ tự** — các cơ sở dữ liệu cũ cần cả bốn, không chỉ
  cái đầu tiên:
  `wrangler d1 execute <db-name> --remote --file=tunnel/migrations/001-claim-lease.sql`
  rồi `002-idempotency-ratelimit.sql`, rồi `003-response-idempotency.sql`,
  rồi `004-idempotency-principal.sql`
  (cùng một lệnh, khác `--file`). Cài đặt mới không cần chúng
  (schema.sql đã bao gồm mọi thứ), và chạy lại
  `scripts/setup-tunnel.sh` sẽ áp dụng chúng cho bạn. Kiểm tra sau đó bằng
  `bash scripts/check-tunnel-schema.sh <db-name>` — nó in ra lệnh sửa
  chính xác cho bất cứ thứ gì còn thiếu.
- **Payload bị giới hạn ở mức D1 có thể lưu.** D1 giới hạn một
  string/BLOB/hàng ở 2.000.000 byte và các body di chuyển dưới dạng
  Base64, vì vậy tunnel chấp nhận body request/response tối đa 1.350.000
  byte thô (1.800.000 ký tự Base64); payload lớn hơn nhận 413 rõ ràng thay
  vì một lần insert cơ sở dữ liệu thất bại.
- **Idempotency gắn với người gọi.** Một phản hồi đã lưu chỉ được phát lại
  khi idempotency key, kredensial của người gọi và payload request chính
  xác đều khớp. Dùng lại một key với payload khác sẽ nhận 409 Conflict;
  phản hồi của người gọi khác không bao giờ được phát lại cho bạn.
- **Kiểm tra sức khỏe của watchdog đi qua tunnel thật.** Với file
  `.health-key` (do `scripts/setup-tunnel.sh` tạo), watchdog và doctor
  xác minh tunnel công khai từ đầu đến cuối bằng một probe nonce đã xác
  thực được client cục bộ trả lời — một 401/403 từ edge đơn thuần không
  còn được tính là "khỏe mạnh" nữa. Nếu `.tunnel-url` tồn tại nhưng
  `.health-key` bị thiếu hoặc trống, watchdog ghi một ERROR cứng và đánh
  trượt bài kiểm tra tunnel thay vì lặng lẽ bỏ qua probe.

## Ghi chú

<details>
<summary><strong>Những gì đã thất bại trên mạng gốc (hồ sơ)</strong></summary>

Trên mạng VM gốc, hai cách tiếp cận tiêu chuẩn **đã thất bại hoàn toàn**:

- **Cloudflare Tunnel (`cloudflared`)** — QUIC/UDP bị chặn, TLS tới các IP
  edge bị can thiệp, proxy từ chối CONNECT tới cổng 7844.
- **Tailscale** — control plane không xuyên qua được mạng (HTTP 400
  từ MITM).

Chi tiết + ví dụ cấu hình đã che thông tin nhạy cảm:
[docs/arsip-tunnel-gagal.md](docs/arsip-tunnel-gagal.md) (bằng tiếng Indonesia).
Trên một VM/mạng bình thường, cả hai có lẽ là con đường dễ nhất.

</details>

## Giấy phép

MIT.
