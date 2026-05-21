#!/bin/bash

# =============================================================================
# Script: copy-env.sh
# Mục đích: Copy .env.example sang .env, tự động sinh TOÀN BỘ mật khẩu và
#           WordPress Authentication Keys & Salts bằng openssl.
#           Tự động set COMPOSE_FILE phù hợp với môi trường.
#
# Cách dùng:
#   bash scripts/copy-env.sh                  # Dev (mặc định)
#   bash scripts/copy-env.sh --env prod       # Production
#   bash scripts/copy-env.sh --force          # Ghi đè .env cũ
#   bash scripts/copy-env.sh --env prod -f    # Production + ghi đè
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
EXAMPLE_PATH="$PROJECT_DIR/.env.example"
ENV_PATH="$PROJECT_DIR/.env"

# ── Parse Arguments ──────────────────────────────────────────────────────────
FORCE=0
ENV_MODE="dev"
PREV_ARG=""

for arg in "$@"; do
  case "$arg" in
    --force|-f) FORCE=1 ;;
    --env)      ;; # handled below
    dev|prod)
      if [ "${PREV_ARG:-}" = "--env" ]; then
        ENV_MODE="$arg"
      fi
      ;;
  esac
  PREV_ARG="$arg"
done

# ── Compose File Mapping ────────────────────────────────────────────────────
case "$ENV_MODE" in
  dev)  COMPOSE_FILE_VALUE="compose.yml" ;;
  prod) COMPOSE_FILE_VALUE="compose.prod.yml" ;;
  *)
    echo "❌ [Error] Unknown environment: $ENV_MODE. Use 'dev' or 'prod'."
    exit 1
    ;;
esac

echo ""
echo "🔧 Environment: $ENV_MODE → COMPOSE_FILE=$COMPOSE_FILE_VALUE"

# ── Pre-flight Check ────────────────────────────────────────────────────────
if [ ! -f "$EXAMPLE_PATH" ]; then
  echo "❌ [Error] Không tìm thấy file .env.example tại: $EXAMPLE_PATH"
  exit 1
fi

SKIP_COPY=0
if [ -f "$ENV_PATH" ] && [ $FORCE -eq 0 ]; then
  echo "⏩ [Skip] File .env đã tồn tại. Secrets và cấu hình được giữ nguyên."
  echo "   Dùng --force để ghi đè và sinh lại mật khẩu mới."
  SKIP_COPY=1
fi

if [ $SKIP_COPY -eq 0 ]; then
  # ── Copy Template ───────────────────────────────────────────────────────────
  echo "📋 Đang tạo file .env từ template .env.example..."
  cp "$EXAMPLE_PATH" "$ENV_PATH"

  # ── Generate Random Secrets ─────────────────────────────────────────────────
  echo "🔐 Đang sinh mật khẩu và WordPress Salts ngẫu nhiên..."

  # Hàm sinh chuỗi ngẫu nhiên (dùng openssl, fallback sang /dev/urandom)
  generate_secret() {
    local length=${1:-48}
    if command -v openssl &> /dev/null; then
      openssl rand -base64 "$length" | tr -d '\n/+=' | head -c "$length"
    else
      cat /dev/urandom | tr -dc 'a-zA-Z0-9_+-' | head -c "$length"
    fi
  }

  # Thay thế tất cả các placeholder "tobemodified_*" bằng secrets ngẫu nhiên
  if command -v perl &> /dev/null; then
    perl -pi -e 's/tobemodified[a-zA-Z0-9_]*/qx(openssl rand -base64 48 | tr -d "\\n\/+=" | head -c 48)/gie' "$ENV_PATH"
  else
    echo "  ⚠️ [Warning] Perl not found. Dùng sed fallback (mỗi key vẫn unique)."
    while IFS= read -r placeholder; do
      SECRET=$(generate_secret 48)
      ESCAPED_SECRET=$(printf '%s\n' "$SECRET" | sed 's/[&/\]/\\&/g')
      sed -i.bak "s/$placeholder/$ESCAPED_SECRET/" "$ENV_PATH"
    done < <(grep -oP 'tobemodified[a-zA-Z0-9_]*' "$ENV_PATH" | sort -u)
    rm -f "$ENV_PATH.bak"
  fi
fi

# ── Inject COMPOSE_FILE ────────────────────────────────────────────────────
# Cập nhật COMPOSE_FILE trong .env (cho cả trường hợp skip và không skip)
if grep -q '^COMPOSE_FILE=' "$ENV_PATH" 2>/dev/null; then
  sed -i.bak "s|^COMPOSE_FILE=.*|COMPOSE_FILE=$COMPOSE_FILE_VALUE|" "$ENV_PATH"
  rm -f "$ENV_PATH.bak"
else
  # Thêm COMPOSE_FILE vào đầu file
  {
    echo "COMPOSE_FILE=$COMPOSE_FILE_VALUE"
    echo ""
    cat "$ENV_PATH"
  } > "$ENV_PATH.tmp" && mv "$ENV_PATH.tmp" "$ENV_PATH"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ $SKIP_COPY -eq 0 ]; then
  echo "✅ Đã tạo .env thành công với mật khẩu ngẫu nhiên!"
else
  echo "✅ Đã cập nhật COMPOSE_FILE=$COMPOSE_FILE_VALUE trong .env"
fi
echo ""
echo "📄 File cấu hình: $ENV_PATH"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
