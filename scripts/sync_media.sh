#!/bin/bash
cd /home/tattoo/launchpad-wp-stack

echo "1. Chuẩn bị môi trường staging trong shared volume..."
docker compose exec -u root wordpress mkdir -p /var/www/html/wp-content/uploads/wp_media_staging
docker compose exec -u root wordpress chown -R www-data:www-data /var/www/html/wp-content/uploads/wp_media_staging

echo "2. Giải nén media-sync.zip vào staging..."
docker compose exec -u root wordpress apt-get update
docker compose exec -u root wordpress apt-get install -y unzip
# Giải nén thẳng vào shared volume
docker compose cp media-sync.zip wordpress:/tmp/media-sync.zip
docker compose exec -u root wordpress sh -c "unzip -o -q /tmp/media-sync.zip -d /var/www/html/wp-content/uploads/wp_media_staging/"
docker compose exec -u root wordpress chown -R www-data:www-data /var/www/html/wp-content/uploads/wp_media_staging

echo "3. Copy kịch bản PHP vào shared volume..."
docker compose cp scripts/sync_media.php wordpress:/var/www/html/wp-content/uploads/sync_media.php
docker compose exec -u root wordpress chown www-data:www-data /var/www/html/wp-content/uploads/sync_media.php

echo "4. Tiến hành Import (Bỏ qua file đã tồn tại)..."
# Giờ wpcli có thể truy cập được cả ảnh và script
docker compose run --rm wpcli wp eval-file /var/www/html/wp-content/uploads/sync_media.php

echo "5. Dọn dẹp rác..."
docker compose exec -u root wordpress rm -rf /var/www/html/wp-content/uploads/wp_media_staging /var/www/html/wp-content/uploads/sync_media.php /tmp/media-sync.zip
rm -f /home/tattoo/launchpad-wp-stack/media-sync.zip

echo "Hoàn thành đồng bộ!"
