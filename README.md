# 🚀 LaunchPad WordPress Stack

**LaunchPad WordPress Stack** là giải pháp triển khai WordPress chuyên nghiệp bằng Docker, được thiết kế theo tiêu chuẩn **Senior WordPress Developer** với cấu trúc thư mục tối ưu cho việc phát triển Theme và Plugin.

Hệ thống được đóng gói hoàn chỉnh với tiêu chí: _Nhanh chóng, Bảo mật, Dễ phát triển và Sẵn sàng cho Production._

---

## ✨ Điểm nổi bật

- 🔐 **One-Click Install:** Tự động sinh toàn bộ mật khẩu và WordPress Salts ngẫu nhiên bằng `openssl`.
- 📂 **Cấu trúc Dev chuyên nghiệp:** Mount riêng `themes/`, `plugins/`, `mu-plugins/` — code trực tiếp trên host, phản ánh real-time vào container.
- ⚙️ **PHP tùy chỉnh sẵn:** Upload max size `256MB`, memory limit `512MB`, max execution time `300s` — sẵn sàng cài theme và plugin nặng.
- 🛠️ **WP-CLI tích hợp:** Quản trị WordPress qua dòng lệnh chuyên nghiệp.
- 🏥 **Healthcheck tự động:** MariaDB và WordPress đều có healthcheck, đảm bảo service khởi động đúng thứ tự.
- 💾 **Data Persistence:** Database, uploads, và WordPress core đều được lưu bền vững qua Docker Named Volumes.

---

## 📂 Cấu trúc Dự án

```text
launchpad-wp-stack/
├── compose.yml               # Docker Compose chính
├── .env.example              # Template cấu hình (placeholder secrets)
├── .env                      # Cấu hình thực tế (auto-generated, .gitignored)
├── .gitignore
│
├── config/
│   └── php/
│       └── uploads.ini       # Custom PHP config (upload size, memory, timeout)
│
├── scripts/
│   ├── install.sh            # 🚀 One-Click Installer
│   ├── copy-env.sh           # 🔐 Sinh .env với mật khẩu ngẫu nhiên
│   ├── reset.sh              # 🔄 Reset về trạng thái sạch
│   └── cleanup.sh            # 🧹 Dọn dẹp Docker system
│
├── src/
│   └── wp-content/
│       ├── themes/           # 🎨 Phát triển Theme (mount → container)
│       ├── plugins/          # 🔌 Phát triển Plugin (mount → container)
│       └── mu-plugins/       # ⚡ Must-Use Plugins (tự động load)
│
└── README.md
```

### Chiến lược Mount Volume

| Thư mục Host | Mount vào Container | Kiểu | Mục đích |
|---|---|---|---|
| `config/php/uploads.ini` | `/usr/local/etc/php/conf.d/uploads.ini` | Bind (read-only) | Cấu hình PHP tùy chỉnh |
| `src/wp-content/themes/` | `/var/www/html/wp-content/themes/` | Bind | Dev theme — code real-time |
| `src/wp-content/plugins/` | `/var/www/html/wp-content/plugins/` | Bind | Dev plugin — code real-time |
| `src/wp-content/mu-plugins/` | `/var/www/html/wp-content/mu-plugins/` | Bind | Must-Use plugins |
| Docker Volume `wp-uploads` | `/var/www/html/wp-content/uploads/` | Named Volume | Media uploads (binary, .gitignored) |
| Docker Volume `wp-core` | `/var/www/html/` | Named Volume | WordPress core files |
| Docker Volume `db-data` | `/var/lib/mysql/` | Named Volume | MariaDB database |

---

## 🎯 Cài đặt Nhanh

### Cách 1: Cài đặt tự động "1 Chạm" (Khuyên dùng)

```bash
bash scripts/install.sh
```

Script sẽ tự động: Kiểm tra Docker → Sinh mật khẩu → Tạo thư mục dev → Khởi chạy containers → Đợi healthy.

### Cách 2: Cài đặt từng bước (Dành cho Developer)

**1. Sinh cấu hình và mật khẩu ngẫu nhiên:**

```bash
bash scripts/copy-env.sh
```

**2. Khởi động hệ thống:**

```bash
docker compose up -d
```

### Cuối cùng: Truy cập WordPress

- 🌐 **Website:** [http://localhost:8080](http://localhost:8080)
- 🛠️ **Admin Panel:** [http://localhost:8080/wp-admin](http://localhost:8080/wp-admin)

_(Tài khoản admin được tạo trong lần truy cập đầu tiên)._

---

## 💻 Hướng dẫn Phát triển

### Phát triển Theme

```bash
# Tạo theme mới
mkdir -p src/wp-content/themes/my-theme

# Tạo file tối thiểu cho theme
cat > src/wp-content/themes/my-theme/style.css << 'EOF'
/*
Theme Name: My Theme
Description: Custom theme
Version: 1.0
*/
EOF

cat > src/wp-content/themes/my-theme/index.php << 'EOF'
<?php get_header(); ?>
<main><?php the_content(); ?></main>
<?php get_footer(); ?>
EOF
```

Theme sẽ tự động xuất hiện tại **Admin > Giao diện > Themes**.

### Phát triển Plugin

```bash
# Tạo plugin mới
mkdir -p src/wp-content/plugins/my-plugin

cat > src/wp-content/plugins/my-plugin/my-plugin.php << 'EOF'
<?php
/**
 * Plugin Name: My Plugin
 * Description: Custom plugin
 * Version: 1.0
 */
EOF
```

Plugin sẽ tự động xuất hiện tại **Admin > Plugins**.

### WP-CLI

```bash
# Liệt kê tất cả plugins
docker compose run --rm wpcli wp plugin list

# Cài đặt và kích hoạt plugin từ repository
docker compose run --rm wpcli wp plugin install woocommerce --activate

# Cập nhật WordPress core
docker compose run --rm wpcli wp core update

# Xuất Database
docker compose run --rm wpcli wp db export /var/www/html/backup.sql
```

---

## ⚙️ Các lệnh Quản lý

| Lệnh | Mô tả |
|---|---|
| `docker compose ps` | Xem trạng thái containers |
| `docker compose logs -f` | Xem log thời gian thực |
| `docker compose down` | Dừng dịch vụ (giữ dữ liệu) |
| `docker compose down -v` | ⚠️ Dừng + xóa sạch dữ liệu |
| `bash scripts/reset.sh` | Reset về trạng thái ban đầu |
| `bash scripts/cleanup.sh` | Dọn dẹp Docker system |

---

## ⚙️ Cấu hình PHP

File [config/php/uploads.ini](./config/php/uploads.ini) cho phép tuỳ chỉnh các giới hạn PHP quan trọng:

| Cấu hình | Mặc định | Mô tả |
|---|---|---|
| `upload_max_filesize` | 256M | Kích thước file upload tối đa |
| `post_max_size` | 256M | Kích thước POST request tối đa |
| `memory_limit` | 512M | Bộ nhớ PHP tối đa |
| `max_execution_time` | 300s | Thời gian thực thi tối đa |
| `max_input_vars` | 5000 | Số biến input tối đa (cần cho Page Builders) |

Thay đổi giá trị trong `.env` rồi restart container:

```bash
docker compose restart wordpress
```

---

## 🌌 Hệ sinh thái LaunchPad

Dự án này là một phần của hệ sinh thái **LaunchPad** — Bộ giải pháp toàn diện cho các dự án khởi nghiệp và doanh nghiệp:

- 💻 [**LaunchPad CMS Fullstack**](https://github.com/tuquet/launchpad-cms-fullstack): Strapi 5 + Next.js 16 Headless CMS.
- 🐳 [**LaunchPad Registry Stack**](https://github.com/tuquet/launchpad-registry-stack): Private Docker Registry + Nginx UI.
- 📰 [**LaunchPad WordPress Stack**](https://github.com/tuquet/launchpad-wp-stack): WordPress Professional Docker Setup (repo này).

⭐️ **Nếu bạn thấy hệ sinh thái này hữu ích, hãy ủng hộ bằng cách thả Star trên GitHub nhé!**
