#!/bin/bash

# =============================================================================
# LaunchPad WordPress - Reset Repository Script
# Mục tiêu: Đưa dự án về trạng thái "sạch sẽ" như lúc mới clone code về.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

echo "🔄 Bắt đầu Reset Repository..."

# 1. Tắt Docker và xóa toàn bộ Volumes (Database, WordPress core, uploads)
echo "🛑 Đang tắt Docker và dọn dẹp toàn bộ Volumes..."
docker compose down -v 2>/dev/null || true

# 2. Xóa file .env
echo "🗑️ Đang xóa file cấu hình (.env)..."
rm -f .env

# 3. Không xóa src/wp-content/{themes,plugins,mu-plugins} vì đó là code dev
echo ""
echo "======================================================"
echo "✅ Reset thành công! Dự án đã hoàn toàn sạch sẽ."
echo "📦 (Thư mục src/wp-content/ vẫn được giữ nguyên để bảo toàn code)"
echo ""
echo "👉 Để bắt đầu lại, hãy chạy:"
echo "   bash scripts/install.sh"
echo "======================================================"
