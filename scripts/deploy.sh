#!/usr/bin/env bash

set -e

BASE_DIR="/var/www/delivery"

echo "Moving to base directory..."
cd "$BASE_DIR"

echo "Syncing backend with GitHub..."
git -C delivery-backend fetch origin main
git -C delivery-backend reset --hard origin/main
git -C delivery-backend clean -fd

echo "Syncing frontend with GitHub..."
git -C delivery-frontend fetch origin main
git -C delivery-frontend reset --hard origin/main
git -C delivery-frontend clean -fd

echo "Syncing deployment repo with GitHub..."
git -C delivery-deployment fetch origin main
git -C delivery-deployment reset --hard origin/main
git -C delivery-deployment clean -fd -e .env.production

echo "Moving to deployment repo..."
cd "$BASE_DIR/delivery-deployment"

echo "Building and starting Docker containers..."
docker compose --env-file .env.production up -d --build --remove-orphans

echo "Running Laravel migrations..."
docker compose --env-file .env.production exec -T backend-app php artisan migrate --force

echo "Creating storage link..."
docker compose --env-file .env.production exec -T backend-app php artisan storage:link || true

echo "Clearing and caching Laravel..."
docker compose --env-file .env.production exec -T backend-app php artisan optimize:clear
docker compose --env-file .env.production exec -T backend-app php artisan config:cache
docker compose --env-file .env.production exec -T backend-app php artisan route:cache
docker compose --env-file .env.production exec -T backend-app php artisan view:cache

echo "Restarting workers..."
docker compose --env-file .env.production restart backend-queue backend-scheduler backend-reverb

echo "Cleaning unused Docker images..."
docker image prune -f

echo "Deployment completed successfully."