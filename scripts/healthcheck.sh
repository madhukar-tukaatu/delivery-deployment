#!/usr/bin/env bash

set -e

cd /var/www/delivery/delivery-deployment

docker compose ps

curl -I http://localhost:3000 || true
curl -I http://localhost:8081 || true

echo "Healthcheck completed."