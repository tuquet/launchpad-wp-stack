#!/bin/bash

# =============================================================================
# LaunchPad WordPress - Backup Script
# Mục tiêu: Tạo bản sao lưu toàn diện (DB, Uploads, Code) để khôi phục khi lỗi.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="$PROJECT_DIR/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# ── Colors ───────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "🔄 Bắt đầu sao lưu hệ thống..."

# 1. Đảm bảo thư mục backup tồn tại
mkdir -p "$BACKUP_DIR"

# Tạo thư mục tạm thời để gom dữ liệu
TEMP_DIR=$(mktemp -d -p "$BACKUP_DIR" tmp_backup_XXXXXX)
trap 'rm -rf "$TEMP_DIR"' EXIT

# 2. Backup Database
echo -e "${YELLOW}[1/4]${NC} Đang export Database..."
docker exec wp-db sh -c \
    'exec mysqldump -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" --single-transaction --quick' \
    > "$TEMP_DIR/db.sql" || { echo -e "${RED}❌ Lỗi export database! Có thể db container chưa khởi động.${NC}"; exit 1; }

# 3. Backup Uploads (Media)
echo -e "${YELLOW}[2/4]${NC} Đang đóng gói thư mục Uploads (Media)..."
docker exec wordpress sh -c \
    'cd /var/www/html/wp-content && tar czf - uploads 2>/dev/null' \
    > "$TEMP_DIR/uploads.tar.gz" || { echo -e "${RED}❌ Lỗi đóng gói uploads!${NC}"; exit 1; }

# 4. Backup Code (themes, plugins, mu-plugins) từ máy host
echo -e "${YELLOW}[3/4]${NC} Đang đóng gói Code (themes, plugins, mu-plugins)..."
tar -czf "$TEMP_DIR/code.tar.gz" \
    -C "$PROJECT_DIR/src/wp-content" themes plugins mu-plugins 2>/dev/null || { echo -e "${RED}❌ Lỗi đóng gói code!${NC}"; exit 1; }

# 5. Đóng gói tất cả thành file backup master
echo -e "${YELLOW}[4/4]${NC} Đang tạo file nén tổng hợp..."
BACKUP_FILE="$BACKUP_DIR/backup_${TIMESTAMP}.tar.gz"
tar -czf "$BACKUP_FILE" -C "$TEMP_DIR" db.sql uploads.tar.gz code.tar.gz

echo -e "${GREEN}✅ Đã tạo thành công bản backup: $(basename "$BACKUP_FILE") ($(du -h "$BACKUP_FILE" | cut -f1))${NC}"

# 6. Dọn dẹp bản backup cũ - Chỉ giữ lại 3 bản gần nhất
echo -e "\n🧹 Đang kiểm tra và dọn dẹp các bản backup cũ (chỉ giữ lại 3 bản gần nhất)..."

# Sắp xếp file theo thời gian sửa đổi (mới nhất lên đầu)
# Đường dẫn không chứa khoảng trắng nên dùng ls -t cực kỳ tin cậy và đơn giản
BACKUP_FILES=($(ls -t "$BACKUP_DIR"/backup_*.tar.gz 2>/dev/null || true))

NUM_BACKUPS=${#BACKUP_FILES[@]}

if [ "$NUM_BACKUPS" -gt 3 ]; then
    echo "Phát hiện $NUM_BACKUPS bản backup. Tiến hành xoá các bản cũ hơn..."
    for ((i=3; i<NUM_BACKUPS; i++)); do
        echo "🗑️ Xoá bản backup cũ: $(basename "${BACKUP_FILES[i]}")"
        rm -f "${BACKUP_FILES[i]}"
    done
else
    echo "Chỉ có $NUM_BACKUPS bản backup. Không cần dọn dẹp."
fi

echo -e "${GREEN}🎉 Hoàn tất sao lưu!${NC}"
