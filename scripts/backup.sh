#!/usr/bin/env bash

set -e

BACKUP_DIR="${BACKUP_DIR:-/var/backups/delivery}"
DATE=$(date +"%Y-%m-%d_%H-%M-%S")

mkdir -p "$BACKUP_DIR"

cd /var/www/delivery/delivery-deployment

docker compose --env-file .env.production exec -T mysql \
  mysqldump -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" \
  > "$BACKUP_DIR/db_$DATE.sql"

tar -czf "$BACKUP_DIR/storage_$DATE.tar.gz" \
  -C /var/lib/docker/volumes/delivery_backend_storage/_data .

echo "Backup completed: $BACKUP_DIR"