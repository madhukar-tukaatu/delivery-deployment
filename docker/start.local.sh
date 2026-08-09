#!/bin/sh

set -e

echo "Starting Laravel development container..."

cd /var/www/html

# =========================================================
# Laravel directories
# =========================================================

mkdir -p \
    storage/framework/cache/data \
    storage/framework/sessions \
    storage/framework/views \
    storage/framework/testing \
    storage/logs \
    bootstrap/cache

# =========================================================
# Permissions
# =========================================================

chown -R www-data:www-data \
    storage \
    bootstrap/cache

chmod -R 775 \
    storage \
    bootstrap/cache

# =========================================================
# Composer dependencies
# =========================================================

if [ ! -f vendor/autoload.php ]; then
    echo "Installing Composer dependencies..."

    composer install \
        --prefer-dist \
        --no-interaction \
        --optimize-autoloader
fi

# =========================================================
# Laravel caches
#
# Do NOT fail container startup if an optional Laravel
# cache operation fails during first boot.
# =========================================================

php artisan package:discover --ansi || true

echo "Laravel backend is ready."

exec "$@"