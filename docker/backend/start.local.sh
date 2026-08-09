#!/bin/sh

set -eu

cd /var/www/html

echo "============================================"
echo "Starting Laravel local container"
echo "============================================"

# ------------------------------------------------------------
# Laravel directories
# ------------------------------------------------------------

mkdir -p \
    storage/app \
    storage/app/public \
    storage/framework \
    storage/framework/cache \
    storage/framework/cache/data \
    storage/framework/sessions \
    storage/framework/views \
    storage/framework/testing \
    storage/logs \
    bootstrap/cache

# ------------------------------------------------------------
# Permissions
# ------------------------------------------------------------

chown -R www-data:www-data storage bootstrap/cache 2>/dev/null || true

chmod -R 775 storage bootstrap/cache 2>/dev/null || true

# ------------------------------------------------------------
# Composer dependencies
# ------------------------------------------------------------

if [ ! -f vendor/autoload.php ]; then
    echo "Composer dependencies not found."
    echo "Installing Composer dependencies..."

    composer install \
        --prefer-dist \
        --no-interaction \
        --optimize-autoloader
else
    echo "Composer dependencies already installed."
fi

# ------------------------------------------------------------
# Laravel storage link
# ------------------------------------------------------------

if [ ! -L public/storage ] && [ ! -e public/storage ]; then
    php artisan storage:link || true
fi

# ------------------------------------------------------------
# Clear stale Laravel caches
# ------------------------------------------------------------

php artisan optimize:clear || true

# ------------------------------------------------------------
# Recreate required directories AFTER optimize:clear
# ------------------------------------------------------------

mkdir -p \
    storage/framework/cache/data \
    storage/framework/sessions \
    storage/framework/views \
    storage/framework/testing \
    storage/logs \
    bootstrap/cache

chown -R www-data:www-data storage bootstrap/cache 2>/dev/null || true
chmod -R 775 storage bootstrap/cache 2>/dev/null || true

echo "============================================"
echo "Laravel backend is ready."
echo "============================================"

exec "$@"