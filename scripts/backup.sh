#!/usr/bin/env bash

set -e

BACKUP_DIR="${BACKUP_DIR:-/var/backups/delivery}"
DATE=$(date +"%Y-%m-%d_%H-%M-%S")

mkdir -p "$BACKUP_DIR"

cd /var/www/delivery/delivery-deployment

# Use deployment env file
if [ -f .env.production ]; then
  ENV_FILE=".env.production"
elif [ -f .env.deployment ]; then
  ENV_FILE=".env.deployment"
else
  echo "ERROR: No .env file found"
  exit 1
fi

# Load environment variables
export $(grep -v '^#' "$ENV_FILE" | xargs)

docker compose --env-file "$ENV_FILE" exec -T mysql \
  mysqldump -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" \
  > "$BACKUP_DIR/db_$DATE.sql"

tar -czf "$BACKUP_DIR/storage_$DATE.tar.gz" \
  -C /var/lib/docker/volumes/delivery_backend_storage/_data .

echo "Backup completed: $BACKUP_DIR"
echo "Files:"
ls -lh "$BACKUP_DIR"/*.sql "$BACKUP_DIR"/*.tar.gz 2>/dev/null || true
