#!/usr/bin/env bash

set -e

BASE_DIR="/var/www/delivery"

echo "Moving to base directory..."
cd "$BASE_DIR"

echo "Pulling backend..."
git -C delivery-backend pull origin main

echo "Pulling frontend..."
git -C delivery-frontend pull origin main

echo "Pulling deployment repo..."
git -C delivery-deployment pull origin main

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