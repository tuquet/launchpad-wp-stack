#!/bin/bash

# =============================================================================
# LaunchPad WordPress - Restore Script
# Mục tiêu: Khôi phục toàn bộ trạng thái hệ thống từ file backup.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="$PROJECT_DIR/backups"

# ── Colors ───────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}======================================================${NC}"
echo -e "${YELLOW}🔄 HỆ THỐNG KHÔI PHỤC DỮ LIỆU (RESTORE)${NC}"
echo -e "${YELLOW}======================================================${NC}"

# 1. Kiểm tra sự tồn tại của thư mục backups
if [ ! -d "$BACKUP_DIR" ]; then
    echo -e "${RED}❌ Không tìm thấy thư mục backups tại: $BACKUP_DIR${NC}"
    exit 1
fi

# 2. Tìm danh sách các file backup
BACKUP_FILES=($(find "$BACKUP_DIR" -name "backup_*.tar.gz" -type f | sort -r 2>/dev/null || true))
NUM_BACKUPS=${#BACKUP_FILES[@]}

if [ "$NUM_BACKUPS" -eq 0 ]; then
    echo -e "${RED}❌ Không tìm thấy file backup nào dạng backup_*.tar.gz trong thư mục backups.${NC}"
    exit 1
fi

SELECTED_BACKUP=""

# Nếu truyền tham số là tên file
if [ $# -ge 1 ]; then
    ARG_FILE="$1"
    # Nếu là đường dẫn tương đối hoặc tuyệt đối, hoặc chỉ là tên file
    if [ -f "$ARG_FILE" ]; then
        SELECTED_BACKUP="$ARG_FILE"
    elif [ -f "$BACKUP_DIR/$ARG_FILE" ]; then
        SELECTED_BACKUP="$BACKUP_DIR/$ARG_FILE"
    else
        echo -e "${RED}❌ Không tìm thấy file backup: $ARG_FILE${NC}"
        exit 1
    fi
else
    # Không truyền tham số -> Hiển thị danh sách để lựa chọn
    echo -e "Danh sách các bản backup hiện có (mới nhất xếp trước):"
    for ((i=0; i<NUM_BACKUPS; i++)); do
        FILE_NAME=$(basename "${BACKUP_FILES[i]}")
        FILE_SIZE=$(du -h "${BACKUP_FILES[i]}" | cut -f1)
        FILE_DATE=$(date -r "${BACKUP_FILES[i]}" "+%Y-%m-%d %H:%M:%S")
        echo -e "  [$((i+1))] $FILE_NAME ($FILE_SIZE) - Tạo lúc: $FILE_DATE"
    done
    echo ""
    read -p "Chọn số thứ tự bản backup bạn muốn phục hồi [mặc định: 1]: " CHOICE
    CHOICE=${CHOICE:-1}

    # Kiểm tra lựa chọn hợp lệ
    if ! [[ "$CHOICE" =~ ^[0-9]+$ ]] || [ "$CHOICE" -lt 1 ] || [ "$CHOICE" -gt "$NUM_BACKUPS" ]; then
        echo -e "${RED}❌ Lựa chọn không hợp lệ!${NC}"
        exit 1
    fi

    SELECTED_BACKUP="${BACKUP_FILES[$((CHOICE-1))]}"
fi

echo -e "\n👉 Bản backup được chọn: ${GREEN}$(basename "$SELECTED_BACKUP")${NC}"

# 3. Yêu cầu xác nhận cực kỳ quan trọng
echo -e "${RED}⚠️  CẢNH BÁO QUAN TRỌNG: Hành động này sẽ GHI ĐÈ toàn bộ Database, Media Uploads và Code (themes, plugins) hiện tại.${NC}"
read -p "Bạn có chắc chắn muốn tiếp tục khôi phục dữ liệu không? (Nhập 'yes' để xác nhận): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo -e "❌ Đã huỷ bỏ khôi phục dữ liệu."
    exit 0
fi

echo -e "\n🚀 Bắt đầu khôi phục..."

# Tạo thư mục tạm để giải nén bản backup master
TEMP_DIR=$(mktemp -d -p "$BACKUP_DIR" tmp_restore_XXXXXX)
trap 'rm -rf "$TEMP_DIR"' EXIT

# 4. Giải nén file backup tổng hợp
echo -e "${YELLOW}[1/4]${NC} Đang giải nén file backup master..."
tar -xzf "$SELECTED_BACKUP" -C "$TEMP_DIR"

# 5. Phục hồi Database
echo -e "${YELLOW}[2/4]${NC} Đang phục hồi Database..."
if [ -f "$TEMP_DIR/db.sql" ]; then
    docker exec -i wp-db sh -c \
        'exec mysql -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE"' \
        < "$TEMP_DIR/db.sql"
    echo -e "${GREEN}  ✅ Phục hồi Database thành công!${NC}"
else
    echo -e "${RED}  ❌ Không tìm thấy db.sql trong bản backup!${NC}"
    exit 1
fi

# 6. Phục hồi Uploads (Media) vào docker volume qua container wordpress
echo -e "${YELLOW}[3/4]${NC} Đang phục hồi Media Uploads..."
if [ -f "$TEMP_DIR/uploads.tar.gz" ]; then
    # Xoá thư mục uploads cũ trong container trước để tránh rác
    docker exec wordpress rm -rf /var/www/html/wp-content/uploads
    # Giải nén đè lên
    docker exec -i wordpress sh -c \
        'cd /var/www/html/wp-content && tar xzf -' \
        < "$TEMP_DIR/uploads.tar.gz"
    # Khôi phục phân quyền cho Apache
    docker exec wordpress chown -R www-data:www-data /var/www/html/wp-content/uploads
    echo -e "${GREEN}  ✅ Phục hồi Media Uploads thành công!${NC}"
else
    echo -e "${RED}  ❌ Không tìm thấy uploads.tar.gz trong bản backup!${NC}"
    exit 1
fi

# 7. Phục hồi Code (Themes, Plugins, MU-plugins)
echo -e "${YELLOW}[4/4]${NC} Đang phục hồi Code (Themes & Plugins)..."
if [ -f "$TEMP_DIR/code.tar.gz" ]; then
    # Xoá các file cũ an toàn từ bên trong container (tránh lỗi Permission denied trên host do files thuộc sở hữu của www-data)
    echo "🧹 Dọn dẹp files cũ trong các thư mục mount..."
    docker exec wordpress sh -c '
        [ -d /var/www/html/wp-content/themes ] && find /var/www/html/wp-content/themes -mindepth 1 -delete
        [ -d /var/www/html/wp-content/plugins ] && find /var/www/html/wp-content/plugins -mindepth 1 -delete
        [ -d /var/www/html/wp-content/mu-plugins ] && find /var/www/html/wp-content/mu-plugins -mindepth 1 -delete
    ' || true

    echo "📦 Giải nén Code từ bên trong container..."
    # Stream code.tar.gz vào container để giải nén bằng quyền root của container (các file sẽ tự động xuất hiện trên host qua volume mounts)
    docker exec -i wordpress sh -c 'cd /var/www/html/wp-content && tar xzf -' < "$TEMP_DIR/code.tar.gz"
    
    # Đồng bộ lại quyền sở hữu cho www-data trong container
    docker exec wordpress chown -R www-data:www-data \
        /var/www/html/wp-content/themes \
        /var/www/html/wp-content/plugins \
        /var/www/html/wp-content/mu-plugins 2>/dev/null || true
        
    echo -e "${GREEN}  ✅ Phục hồi Code thành công!${NC}"
else
    echo -e "${RED}  ❌ Không tìm thấy code.tar.gz trong bản backup!${NC}"
    exit 1
fi

echo -e "\n${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}🎉 KHÔI PHỤC DỮ LIỆU THÀNH CÔNG!${NC}"
echo -e "Website của bạn đã được đưa về trạng thái ngày: $(date -r "$SELECTED_BACKUP" "+%Y-%m-%d %H:%M:%S")"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
