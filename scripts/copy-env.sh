#!/bin/bash

# =============================================================================
# Script: copy-env.sh
# Mục đích: Copy .env.example sang .env, tự động sinh TOÀN BỘ mật khẩu và
#           WordPress Authentication Keys & Salts bằng openssl.
#
# Cách dùng:
#   bash scripts/copy-env.sh               # Tạo .env mới (không ghi đè nếu đã có)
#   bash scripts/copy-env.sh --force       # Ghi đè .env cũ, sinh lại mật khẩu mới
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
EXAMPLE_PATH="$PROJECT_DIR/.env.example"
ENV_PATH="$PROJECT_DIR/.env"

# ── Parse Arguments ──────────────────────────────────────────────────────────
FORCE=0
for arg in "$@"; do
  case "$arg" in
    --force|-f) FORCE=1 ;;
  esac
done

# ── Pre-flight Check ────────────────────────────────────────────────────────
if [ ! -f "$EXAMPLE_PATH" ]; then
  echo "❌ [Error] Không tìm thấy file .env.example tại: $EXAMPLE_PATH"
  exit 1
fi

if [ -f "$ENV_PATH" ] && [ $FORCE -eq 0 ]; then
  echo "⏩ [Skip] File .env đã tồn tại. Secrets và cấu hình được giữ nguyên."
  echo "   Dùng --force để ghi đè và sinh lại mật khẩu mới."
  exit 0
fi

# ── Copy Template ───────────────────────────────────────────────────────────
echo ""
echo "🔧 Đang tạo file .env từ template .env.example..."
cp "$EXAMPLE_PATH" "$ENV_PATH"

# ── Generate Random Secrets ─────────────────────────────────────────────────
echo "🔐 Đang sinh mật khẩu và WordPress Salts ngẫu nhiên..."

# Hàm sinh chuỗi ngẫu nhiên (dùng openssl, fallback sang /dev/urandom)
generate_secret() {
  local length=${1:-48}
  if command -v openssl &> /dev/null; then
    openssl rand -base64 "$length" | tr -d '\n/+=' | head -c "$length"
  else
    cat /dev/urandom | tr -dc 'a-zA-Z0-9!@#$%^&*()_+-=' | head -c "$length"
  fi
}

# Thay thế tất cả các placeholder "tobemodified_*" bằng secrets ngẫu nhiên
# Mỗi placeholder nhận 1 giá trị KHÁC NHAU (không dùng chung 1 secret)
if command -v perl &> /dev/null; then
  # Perl: Mỗi match gọi openssl riêng biệt → mỗi key là unique
  perl -pi -e 's/tobemodified[a-zA-Z0-9_]*/qx(openssl rand -base64 48 | tr -d "\\n\/+=" | head -c 48)/gie' "$ENV_PATH"
else
  echo "  ⚠️ [Warning] Perl not found. Dùng sed fallback (mỗi key vẫn unique)."
  # Sed fallback: Thay từng placeholder một
  while IFS= read -r placeholder; do
    SECRET=$(generate_secret 48)
    # Escape các ký tự đặc biệt cho sed
    ESCAPED_SECRET=$(printf '%s\n' "$SECRET" | sed 's/[&/\]/\\&/g')
    sed -i.bak "s/$placeholder/$ESCAPED_SECRET/" "$ENV_PATH"
  done < <(grep -oP 'tobemodified[a-zA-Z0-9_]*' "$ENV_PATH" | sort -u)
  rm -f "$ENV_PATH.bak"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Đã tạo .env thành công với mật khẩu ngẫu nhiên!"
echo ""
echo "📄 File cấu hình: $ENV_PATH"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
