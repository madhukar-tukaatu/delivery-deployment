#!/usr/bin/env bash

set -euo pipefail

BASE_DIR="/var/www/delivery"
COMPOSE_ENV=".env.production"
MAX_WAIT_SECONDS=120

log() {
  echo "[deploy $(date '+%Y-%m-%d %H:%M:%S')] $*"
}

wait_for_backend() {
  local waited=0
  log "Waiting for backend PHP-FPM to accept connections..."

  until docker compose --env-file "$COMPOSE_ENV" exec -T backend-app php -r 'exit(@fsockopen("127.0.0.1", 9000) ? 0 : 1);' >/dev/null 2>&1; do
    if [ "$waited" -ge "$MAX_WAIT_SECONDS" ]; then
      log "ERROR: backend-app PHP-FPM did not become ready within ${MAX_WAIT_SECONDS}s"
      return 1
    fi
    sleep 2
    waited=$((waited + 2))
  done

  log "PHP-FPM is up. Waiting for HTTP via backend-nginx..."
  waited=0
  until docker compose --env-file "$COMPOSE_ENV" exec -T backend-nginx wget -q -O /dev/null --timeout=3 "http://127.0.0.1/" 2>/dev/null; do
    if [ "$waited" -ge "$MAX_WAIT_SECONDS" ]; then
      log "WARNING: HTTP health check timed out after ${MAX_WAIT_SECONDS}s (continuing; nginx reload still applied)"
      return 0
    fi
    sleep 2
    waited=$((waited + 2))
  done

  log "Backend HTTP is responding."
}

reload_nginx() {
  log "Reloading Docker backend-nginx (clear stale upstream to backend-app)..."
  if docker compose --env-file "$COMPOSE_ENV" exec -T backend-nginx nginx -t >/dev/null 2>&1; then
    docker compose --env-file "$COMPOSE_ENV" exec -T backend-nginx nginx -s reload
    log "backend-nginx reloaded."
  else
    log "nginx -t failed or reload unavailable; restarting backend-nginx container..."
    docker compose --env-file "$COMPOSE_ENV" restart backend-nginx
  fi

  # Host nginx is often the TLS terminator in front of :8081 / :3000
  if command -v nginx >/dev/null 2>&1 && [ -d /etc/nginx ]; then
    if sudo nginx -t >/dev/null 2>&1; then
      log "Reloading host nginx..."
      sudo systemctl reload nginx 2>/dev/null || sudo nginx -s reload || true
    else
      log "Host nginx config test failed; skipping host reload."
    fi
  elif systemctl is-active --quiet nginx 2>/dev/null; then
    log "Reloading host nginx via systemctl..."
    sudo systemctl reload nginx || true
  else
    log "No host nginx service detected; skipped."
  fi
}

run_artisan_caches() {
  log "Clearing and caching Laravel..."
  docker compose --env-file "$COMPOSE_ENV" exec -T backend-app php artisan optimize:clear

  docker compose --env-file "$COMPOSE_ENV" exec -T backend-app php artisan config:cache
  docker compose --env-file "$COMPOSE_ENV" exec -T backend-app php artisan view:cache

  # route:cache fails hard on duplicate route names; keep app bootable without cached routes
  if docker compose --env-file "$COMPOSE_ENV" exec -T backend-app php artisan route:cache; then
    log "route:cache OK."
  else
    log "ERROR: route:cache failed (likely duplicate route names). Leaving routes uncached so API can still boot."
    docker compose --env-file "$COMPOSE_ENV" exec -T backend-app php artisan route:clear || true
    return 1
  fi
}

log "Moving to base directory..."
cd "$BASE_DIR"

log "Syncing backend with GitHub..."
git -C delivery-backend fetch origin main
git -C delivery-backend reset --hard origin/main
git -C delivery-backend clean -fd

log "Syncing frontend with GitHub..."
git -C delivery-frontend fetch origin main
git -C delivery-frontend reset --hard origin/main
git -C delivery-frontend clean -fd

log "Syncing deployment repo with GitHub..."
git -C delivery-deployment fetch origin main
git -C delivery-deployment reset --hard origin/main
git -C delivery-deployment clean -fd -e .env.production

log "Moving to deployment repo..."
cd "$BASE_DIR/delivery-deployment"

log "Building and starting Docker containers..."
docker compose --env-file "$COMPOSE_ENV" up -d --build --remove-orphans

# Always recreate nginx after backend rebuild so it never keeps a dead upstream IP
log "Recreating backend-nginx against current backend-app..."
docker compose --env-file "$COMPOSE_ENV" up -d --no-deps --force-recreate backend-nginx

wait_for_backend
reload_nginx

log "Running Laravel migrations..."
docker compose --env-file "$COMPOSE_ENV" exec -T backend-app php artisan migrate --force

log "Creating storage link..."
docker compose --env-file "$COMPOSE_ENV" exec -T backend-app php artisan storage:link || true

set +e
run_artisan_caches
CACHE_STATUS=$?
set -e

log "Restarting workers..."
docker compose --env-file "$COMPOSE_ENV" restart backend-queue backend-scheduler backend-reverb

# Final nginx refresh after artisan/workers settle
reload_nginx

log "Cleaning unused Docker images..."
docker image prune -f

if [ "$CACHE_STATUS" -ne 0 ]; then
  log "Deployment finished with WARNINGS: route:cache failed. Fix duplicate routes, then redeploy."
  exit 1
fi

log "Deployment completed successfully."