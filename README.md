# WordPress Docker Compose Setup

Tài liệu hướng dẫn triển khai WordPress phiên bản mới nhất sử dụng Docker Compose. Dự án này bao gồm hai dịch vụ chính được cô lập trong cùng một mạng nội bộ (`wp_network`):
1. **WordPress** (bản mới nhất - `latest`)
2. **MariaDB** (bản ổn định biên bản dài hạn - `10.11`)

---

## 🛠️ Yêu cầu hệ thống

Trước khi bắt đầu, hãy đảm bảo máy tính của bạn đã cài đặt:
- **Docker Desktop** (hoặc Docker Engine trên Linux).
- **Docker Compose** (đã được tích hợp sẵn trong Docker Desktop).

---

## 📂 Cấu trúc thư mục

```text
launchpad-wp-stack/
├── .env                  # Lưu trữ thông tin nhạy cảm và cấu hình (đã được bỏ qua bởi .gitignore)
├── .env.example          # File mẫu cấu hình mẫu
├── .gitignore            # Bỏ qua file .env và log
├── docker-compose.yml    # File cấu hình Docker Compose
└── README.md             # Tài liệu hướng dẫn sử dụng (file này)
```

---

## 🚀 Hướng dẫn khởi chạy nhanh

### Bước 1: Chuẩn bị file môi trường
File `.env` đã được tạo sẵn với các thông tin mặc định cơ bản. Bạn có thể mở file `.env` lên để tùy chỉnh lại mật khẩu cơ sở dữ liệu hoặc thay đổi cổng chạy WordPress nếu cần:

```ini
# Cổng chạy WordPress trên máy host (Mặc định là 8080)
WP_PORT=8080

# Thông tin Database
DB_NAME=wordpress
DB_USER=wordpress_user
DB_PASSWORD=wordpress_secure_password_123!
DB_ROOT_PASSWORD=mariadb_root_secure_password_999!
```

> [!WARNING]
> Để bảo mật tốt nhất cho môi trường Production (nếu có), hãy luôn thay đổi `DB_PASSWORD` và `DB_ROOT_PASSWORD` thành các chuỗi ngẫu nhiên, độ phức tạp cao.

### Bước 2: Khởi chạy các container
Mở Terminal/Powershell tại thư mục dự án và chạy lệnh sau:

```bash
docker compose up -d
```

Lệnh trên sẽ tự động tải các Image WordPress và MariaDB mới nhất về máy, sau đó tạo mạng nội bộ và khởi động dịch vụ dưới dạng chạy ngầm (`-d`).

### Bước 3: Truy cập WordPress
Sau khi các dịch vụ đã khởi chạy thành công (mất khoảng 10-15 giây để cơ sở dữ liệu khởi tạo lần đầu), bạn hãy mở trình duyệt web và truy cập:

👉 **[http://localhost:8080](http://localhost:8080)**

*(Nếu bạn thay đổi cổng `WP_PORT` trong `.env` thành cổng khác, ví dụ `80`, hãy truy cập `http://localhost`).*

---

## ⚙️ Các lệnh quản lý thông dụng

*   **Xem trạng thái các container:**
    ```bash
    docker compose ps
    ```
*   **Xem log thời gian thực (để debug nếu gặp lỗi):**
    ```bash
    docker compose logs -f
    ```
*   **Dừng dịch vụ (không mất dữ liệu):**
    ```bash
    docker compose down
    ```
*   **Dừng dịch vụ và xóa sạch dữ liệu (CẨN THẬN - Lệnh này sẽ xóa toàn bộ bài viết, cấu hình và tệp đã upload):**
    ```bash
    docker compose down -v
    ```

---

## 💾 Lưu trữ dữ liệu (Data Persistence)
Dự án sử dụng **Docker Named Volumes** để bảo toàn dữ liệu khi container bị dừng hoặc cập nhật:
- `db_data`: Lưu trữ toàn bộ cơ sở dữ liệu MariaDB.
- `wp_data`: Lưu trữ mã nguồn WordPress và thư mục `wp-content` (nơi chứa theme, plugin, hình ảnh đã tải lên).
