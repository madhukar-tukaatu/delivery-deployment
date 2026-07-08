#!/usr/bin/env bash

set -e

BASE_DIR="${BASE_DIR:-/var/www/delivery}"

echo "Going to project directory..."
cd "$BASE_DIR"

echo "Pulling latest backend..."
git -C delivery-backend pull origin main

echo "Pulling latest frontend..."
git -C delivery-frontend pull origin main

echo "Pulling latest deployment repo..."
git -C delivery-deployment pull origin main

cd delivery-deployment

echo "Building and starting containers..."
docker compose --env-file .env.production up -d --build --remove-orphans

echo "Running Laravel migrations..."
docker compose --env-file .env.production exec -T backend-app php artisan migrate --force

echo "Linking storage..."
docker compose --env-file .env.production exec -T backend-app php artisan storage:link || true

echo "Optimizing Laravel..."
docker compose --env-file .env.production exec -T backend-app php artisan optimize:clear
docker compose --env-file .env.production exec -T backend-app php artisan config:cache
docker compose --env-file .env.production exec -T backend-app php artisan route:cache
docker compose --env-file .env.production exec -T backend-app php artisan view:cache

echo "Restarting queue and scheduler..."
docker compose --env-file .env.production restart backend-queue backend-scheduler backend-reverb

echo "Cleaning old Docker images..."
docker image prune -f

echo "Deployment completed."