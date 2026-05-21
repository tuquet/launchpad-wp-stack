#!/bin/bash

# =============================================================================
# Script: migrate.sh
# Mục đích: Export dữ liệu WordPress từ LOCAL và chuẩn bị file migration
#           để import lên VPS Production.
#
# Script này thực hiện:
#   1. Export Database từ MariaDB container (mysqldump)
#   2. Đóng gói wp-content/uploads (media files)
#   3. Tạo thư mục migration/ chứa toàn bộ dữ liệu sẵn sàng chuyển
#
# Cách dùng:
#   bash scripts/migrate.sh export              # Xuất dữ liệu từ local
#   bash scripts/migrate.sh import <OLD_URL>     # Import dữ liệu trên VPS
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
MIGRATION_DIR="$PROJECT_DIR/migration"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# ── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ── Export: Chạy trên máy LOCAL ─────────────────────────────────────────────
do_export() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}📦 EXPORT WordPress Data (Local → Migration Package)${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    mkdir -p "$MIGRATION_DIR"

    # 1. Export Database
    echo -e "\n${YELLOW}[1/3]${NC} Đang export Database..."
    DB_FILE="$MIGRATION_DIR/db_backup_${TIMESTAMP}.sql"

    docker exec wp-db sh -c \
        'exec mysqldump -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" --single-transaction --quick' \
        > "$DB_FILE"

    echo -e "${GREEN}  ✅ Database exported: $(basename "$DB_FILE") ($(du -h "$DB_FILE" | cut -f1))${NC}"

    # 2. Export wp-content/uploads (media files)
    echo -e "\n${YELLOW}[2/3]${NC} Đang đóng gói Media Uploads..."
    UPLOADS_FILE="$MIGRATION_DIR/uploads_${TIMESTAMP}.tar.gz"

    docker exec wordpress sh -c \
        'cd /var/www/html/wp-content && tar czf - uploads 2>/dev/null' \
        > "$UPLOADS_FILE"

    UPLOADS_SIZE=$(du -h "$UPLOADS_FILE" | cut -f1)
    echo -e "${GREEN}  ✅ Uploads exported: $(basename "$UPLOADS_FILE") ($UPLOADS_SIZE)${NC}"

    # 3. Tạo symlink "latest" để dễ tham chiếu
    echo -e "\n${YELLOW}[3/3]${NC} Đang tạo symlinks..."
    ln -sf "$(basename "$DB_FILE")" "$MIGRATION_DIR/db_latest.sql"
    ln -sf "$(basename "$UPLOADS_FILE")" "$MIGRATION_DIR/uploads_latest.tar.gz"

    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}✅ EXPORT HOÀN TẤT!${NC}"
    echo ""
    echo -e "📂 Thư mục migration: ${MIGRATION_DIR}"
    echo -e "   📄 Database : $(basename "$DB_FILE") ($( du -h "$DB_FILE" | cut -f1))"
    echo -e "   📦 Uploads  : $(basename "$UPLOADS_FILE") ($UPLOADS_SIZE)"
    echo ""
    echo -e "${YELLOW}Bước tiếp theo:${NC}"
    echo "  1. Copy thư mục migration/ lên VPS:"
    echo "     scp -r migration/ user@VPS_IP:/path/to/launchpad-wp-stack/"
    echo ""
    echo "  2. Trên VPS, chạy:"
    echo "     bash scripts/migrate.sh import http://localhost:8888"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# ── Import: Chạy trên VPS ───────────────────────────────────────────────────
do_import() {
    local OLD_URL="${1:-}"

    if [ -z "$OLD_URL" ]; then
        echo -e "${RED}❌ Thiếu tham số OLD_URL!${NC}"
        echo "Cách dùng: bash scripts/migrate.sh import http://localhost:8888"
        echo ""
        echo "OLD_URL là địa chỉ WordPress trên máy local (hoặc domain cũ)."
        echo "Script sẽ tự động thay thế bằng domain/IP mới trên VPS."
        exit 1
    fi

    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}📥 IMPORT WordPress Data (Migration Package → VPS)${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    # Kiểm tra file migration tồn tại
    if [ ! -f "$MIGRATION_DIR/db_latest.sql" ]; then
        echo -e "${RED}❌ Không tìm thấy file migration/db_latest.sql${NC}"
        echo "Hãy chạy 'bash scripts/migrate.sh export' trên máy local trước."
        exit 1
    fi

    # 1. Import Database
    echo -e "\n${YELLOW}[1/3]${NC} Đang import Database..."
    docker exec -i wp-db sh -c \
        'exec mysql -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE"' \
        < "$MIGRATION_DIR/db_latest.sql"
    echo -e "${GREEN}  ✅ Database imported thành công!${NC}"

    # 2. Import Uploads
    if [ -f "$MIGRATION_DIR/uploads_latest.tar.gz" ]; then
        echo -e "\n${YELLOW}[2/3]${NC} Đang giải nén Media Uploads..."
        docker exec -i wordpress sh -c \
            'cd /var/www/html/wp-content && tar xzf -' \
            < "$MIGRATION_DIR/uploads_latest.tar.gz"

        # Fix ownership
        docker exec wordpress chown -R www-data:www-data /var/www/html/wp-content/uploads
        echo -e "${GREEN}  ✅ Uploads imported thành công!${NC}"
    else
        echo -e "${YELLOW}  ⏩ Không tìm thấy uploads_latest.tar.gz — bỏ qua.${NC}"
    fi

    # 3. Search-Replace URLs (THE CRITICAL STEP!)
    echo -e "\n${YELLOW}[3/3]${NC} Đang thay thế URLs trong database..."

    # Detect new URL
    WP_PORT=$(grep '^WP_PORT=' "$PROJECT_DIR/.env" 2>/dev/null | cut -d'=' -f2 || echo "8888")
    SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost")
    NEW_URL="http://${SERVER_IP}:${WP_PORT}"

    echo -e "  🔄 OLD: ${RED}${OLD_URL}${NC}"
    echo -e "  🔄 NEW: ${GREEN}${NEW_URL}${NC}"

    # wp search-replace xử lý an toàn serialized data
    docker compose run --rm wpcli wp search-replace \
        "$OLD_URL" "$NEW_URL" \
        --all-tables --precise --recurse-objects --skip-columns=guid

    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}✅ IMPORT HOÀN TẤT!${NC}"
    echo ""
    echo -e "🌐 WordPress: ${NEW_URL}"
    echo -e "🛠️ Admin:     ${NEW_URL}/wp-admin"
    echo ""
    echo -e "${YELLOW}💡 Nếu bạn có domain, hãy chạy lại search-replace:${NC}"
    echo "   docker compose run --rm wpcli wp search-replace \\"
    echo "     '${NEW_URL}' 'https://yourdomain.com' \\"
    echo "     --all-tables --precise --recurse-objects --skip-columns=guid"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# ── Main ────────────────────────────────────────────────────────────────────
ACTION="${1:-}"

case "$ACTION" in
    export)
        do_export
        ;;
    import)
        shift
        do_import "$@"
        ;;
    *)
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "📦 LaunchPad WordPress — Migration Tool"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "Cách dùng:"
        echo "  bash scripts/migrate.sh export             # Xuất DB + Uploads từ local"
        echo "  bash scripts/migrate.sh import <OLD_URL>   # Import vào VPS + search-replace"
        echo ""
        echo "Workflow đầy đủ:"
        echo "  [LOCAL]  bash scripts/migrate.sh export"
        echo "  [LOCAL]  scp -r migration/ user@VPS:/path/to/launchpad-wp-stack/"
        echo "  [VPS]    bash scripts/migrate.sh import http://localhost:8888"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        ;;
esac
