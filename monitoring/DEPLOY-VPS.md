# Deploy monitoring on VPS (safe — does not touch app stack)

## Why this will not conflict

- Monitoring lives only under `monitoring/` (new folder).
- It uses `docker-compose.monitoring.prod.yml` — **never** edits `docker-compose.yml`.
- Your uncommitted server changes (`docker-compose.yml`, `scripts/backup.sh`) stay as they are.
- Grafana/Prometheus bind to **127.0.0.1** only (not public internet).
- Memory limits keep the monitoring stack from starving the app (~1.2 GB max reserved).

## A) From your laptop — commit only monitoring

```bash
cd delivery-deployment
git add monitoring/
git status   # confirm ONLY monitoring/ is staged (not backup.sh / docker-compose.yml)
git commit -m "Add optional Prometheus/Grafana monitoring stack for VPS"
git push
```

Do **not** stage `scripts/backup.sh` unless you intend to.

## B) On the VPS — pull without touching dirty files

```bash
cd /var/www/delivery/delivery-deployment

# 1) Confirm dirty files stay local
git status

# 2) Pull. New folder only → no conflict with your modified files
git pull origin main

# 3) Confirm app still running (should be unchanged)
docker ps --format 'table {{.Names}}\t{{.Status}}' | grep delivery
```

If `git pull` ever complains about `docker-compose.yml` / `backup.sh`, **stop** and run:

```bash
git stash push -m "server-local" -- docker-compose.yml scripts/backup.sh
git pull origin main
git stash pop
```

## C) Configure secrets (once)

```bash
cd /var/www/delivery/delivery-deployment/monitoring
cp .env.monitoring.example .env.monitoring
nano .env.monitoring   # set strong GRAFANA_ADMIN_PASSWORD

# Confirm Docker network name (usually delivery-deployment_delivery)
docker network ls | grep delivery

# Put real MySQL root password (from .env.production) into exporter config
cp prometheus/my.cnf.prod prometheus/my.cnf.prod.bak
nano prometheus/my.cnf.prod
# set: password=<MYSQL_ROOT_PASSWORD from .env.production>
# host should stay: delivery-mysql
```

Make sure `.env.monitoring` and the real `my.cnf.prod` password are **not** committed.

## D) Start monitoring only

```bash
cd /var/www/delivery/delivery-deployment/monitoring

docker compose --env-file .env.monitoring -f docker-compose.monitoring.prod.yml pull
docker compose --env-file .env.monitoring -f docker-compose.monitoring.prod.yml up -d

docker compose --env-file .env.monitoring -f docker-compose.monitoring.prod.yml ps
```

Check targets (from the VPS):

```bash
curl -s http://127.0.0.1:9090/api/v1/targets | head
```

## E) Open Grafana safely

Because it listens on localhost only:

```bash
# from your PC (SSH tunnel):
ssh -L 3001:127.0.0.1:3001 deploy@YOUR_VPS_IP
```

Then browse http://localhost:3001 on your PC — Dashboards → Delivery → **Delivery overview**.

## F) Rollback (if anything feels wrong)

```bash
cd /var/www/delivery/delivery-deployment/monitoring
docker compose --env-file .env.monitoring -f docker-compose.monitoring.prod.yml down
```

App containers are untouched. Add `-v` only if you also want to wipe Prometheus/Grafana data volumes.

## Do NOT

- Run `docker compose up -d` on the main `docker-compose.yml` for this
- Expose 3001/9090 on `0.0.0.0` without auth / firewall
- Commit `.env.monitoring` or a my.cnf with the real root password