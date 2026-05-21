#!/bin/bash

# =============================================================================
# LaunchPad WordPress - One-Click Installer
# Mục tiêu: Tự động hóa 100% quá trình cài đặt và khởi chạy WordPress.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

echo "================================================================="
echo "🚀 CHÀO MỪNG BẠN ĐẾN VỚI LAUNCHPAD WORDPRESS STACK"
echo "================================================================="
echo ""
echo "⚠️ Yêu cầu hệ thống trước khi bắt đầu:"
echo "   - Đã cài đặt Docker và Docker Compose."
echo "   - Ứng dụng Docker (Docker Desktop/Engine) ĐANG CHẠY."
echo "   - Máy tính còn trống ít nhất 1GB dung lượng ổ cứng."
echo ""
read -p "👉 Bạn đã sẵn sàng chưa? (Nhấn Enter để tiếp tục hoặc Ctrl+C để hủy) "

# 1. Kiểm tra Docker có đang chạy không
echo ""
echo "🔍 [1/4] Đang kiểm tra hệ thống Docker..."
if ! command -v docker &> /dev/null; then
    echo "❌ Lỗi: Không tìm thấy lệnh 'docker'. Vui lòng cài đặt Docker trước!"
    exit 1
fi
if ! docker info > /dev/null 2>&1; then
    echo "❌ Lỗi: Docker chưa được bật. Vui lòng mở Docker Desktop lên nhé!"
    exit 1
fi
echo "✅ Docker đã sẵn sàng!"

# 2. Sinh biến môi trường
echo ""
echo "🔧 [2/4] Đang khởi tạo file cấu hình môi trường (.env)..."
bash scripts/copy-env.sh

# 3. Tạo thư mục phát triển Theme & Plugin (nếu chưa có)
echo ""
echo "📂 [3/4] Đang chuẩn bị cấu trúc thư mục phát triển..."
mkdir -p src/wp-content/themes
mkdir -p src/wp-content/plugins
mkdir -p src/wp-content/mu-plugins
echo "✅ Đã tạo thư mục src/wp-content/{themes,plugins,mu-plugins}!"

# 4. Chạy Docker Compose
echo ""
echo "🐳 [4/4] Đang tải và khởi chạy WordPress & MariaDB..."
echo "⏳ Quá trình này sẽ mất khoảng 1-3 phút (Tùy tốc độ mạng). Vui lòng không tắt cửa sổ này!"
docker compose up -d

# Kiểm tra nếu lệnh chạy thất bại
if [ $? -ne 0 ]; then
    echo "❌ Lỗi: Quá trình khởi động Docker gặp sự cố. Vui lòng kiểm tra log ở trên."
    exit 1
fi

# Đợi WordPress healthy
echo ""
echo "⏳ Đang đợi WordPress khởi động hoàn tất..."
TIMEOUT=120
ELAPSED=0
while ! docker inspect --format='{{.State.Health.Status}}' wordpress 2>/dev/null | grep -q "healthy"; do
    if [ $ELAPSED -ge $TIMEOUT ]; then
        echo "⚠️ Cảnh báo: WordPress chưa healthy sau ${TIMEOUT}s. Có thể vẫn đang khởi động..."
        break
    fi
    sleep 3
    ELAPSED=$((ELAPSED + 3))
    printf "."
done
echo ""

# Lấy port từ .env
WP_PORT=$(grep '^WP_PORT=' .env | cut -d'=' -f2 || echo "8080")

echo ""
echo "================================================================="
echo "🎉 CÀI ĐẶT THÀNH CÔNG! WORDPRESS ĐÃ SẴN SÀNG"
echo "================================================================="
echo "Dưới đây là các đường dẫn để bạn trải nghiệm:"
echo ""
echo "🌐 Website WordPress       : http://localhost:${WP_PORT}"
echo "🛠️ Trang Quản trị (Admin)  : http://localhost:${WP_PORT}/wp-admin"
echo "🗄️ Database (MariaDB)      : localhost:3306"
echo ""
echo "📁 Phát triển Theme/Plugin:"
echo "   - Themes    : src/wp-content/themes/"
echo "   - Plugins   : src/wp-content/plugins/"
echo "   - MU-Plugins: src/wp-content/mu-plugins/"
echo ""
echo "⚙️ Cấu hình PHP (upload size, memory): config/php/uploads.ini"
echo ""
echo "💡 WP-CLI: docker compose run --rm wpcli wp plugin list"
echo "================================================================="
