
# Deploy monitoring on the VPS (does not replace the app stack)

This is the operational runbook kept in the repo. The fuller guide (panel meanings, daily checklist, alert responses) is the **Tukaatu Express monitoring guide** Page in the chat.

## Why this will not conflict with the app

- Monitoring lives under `monitoring/` and uses `docker-compose.monitoring.prod.yml`.
- It does **not** replace `docker-compose.yml`. The only optional app change is the PHP-FPM status overlay (`docker-compose.fpm-status.yml`), which adds one read-only volume to `backend-app`.
- Your uncommitted server changes to `docker-compose.yml` / `scripts/backup.sh` stay as they are if you do not run `git reset --hard`.
- All monitoring ports bind to **127.0.0.1** only (Grafana included). Do not publish 3001/9090/9104/9113/9115/8086 on `0.0.0.0`.

## 0) Diagnose first (paste this output before changing anything)

Run on 103.160.22.27:

```bash
echo '=== monitoring containers ==='
docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' | grep -E 'NAME|prom|grafana|cadvisor|exporter|loki|promtail|alertmanager|blackbox' || true

echo '=== docker networks ==='
docker network ls | grep -E 'NETWORK|delivery|monitor'

echo '=== app containers and their networks ==='
for c in delivery-backend-app delivery-backend-nginx delivery-mysql delivery-redis; do
  echo "-- $c"
  docker inspect "$c" --format '{{.State.Status}} networks={{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}' 2>/dev/null || echo missing
done

echo '=== prometheus targets (if already running) ==='
curl -sS http://127.0.0.1:9090/api/v1/targets | python3 -c '
import json,sys
d=json.load(sys.stdin)
t=d.get("data",{}).get("activeTargets",[])
if not t:
    print("no targets or prometheus not reachable")
for x in t:
    labels=x.get("labels",{})
    print(f"{labels.get(\"job\",\"?\"):15} {x.get(\"health\"):5} {labels.get(\"instance\",\"\")} {x.get(\"lastError\",\"\")}")
' 2>/dev/null || curl -sS -o /tmp/prom-targets.json -w "curl_exit=$? http_code=%{http_code}\n" http://127.0.0.1:9090/api/v1/targets

echo '=== stub_status from a throwaway client on the app network ==='
NET=$(docker inspect delivery-backend-nginx --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}' 2>/dev/null)
echo "nginx network=$NET"
if [ -n "$NET" ]; then
  docker run --rm --network "$NET" curlimages/curl:8.10.1 -sS -m 5 -D- http://delivery-backend-nginx/stub_status || true
fi
```

## A) On the VPS — get the branch without wiping dirty files

```bash
cd /var/www/delivery/delivery-deployment
git status
git fetch origin
git checkout monitoring-fix
# If checkout is blocked by dirty files, do not reset --hard.
# Copy dirty files aside, then checkout, then copy them back.
```

## B) Configure secrets (once)

```bash
cd /var/www/delivery/delivery-deployment/monitoring
cp .env.monitoring.example .env.monitoring
nano .env.monitoring
# Set GRAFANA_ADMIN_PASSWORD and MYSQL_EXPORTER_PASSWORD to strong unique values.
# Set DELIVERY_NETWORK to the network name printed in step 0 (must match the app containers).
```

Create the MySQL exporter user (password must match `MYSQL_EXPORTER_PASSWORD`). Do **not** reuse the MySQL root password:

```bash
cd /var/www/delivery/delivery-deployment
# Reads MYSQL_ROOT_PASSWORD from the already-deployed env file; it is not printed.
docker compose --env-file .env.production exec -T mysql mysql -uroot -p"$MYSQL_ROOT_PASSWORD" <<'SQL'
CREATE USER IF NOT EXISTS 'exporter'@'%' IDENTIFIED BY 'CHANGE_ME';
ALTER USER 'exporter'@'%' IDENTIFIED BY 'CHANGE_ME';
GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO 'exporter'@'%';
FLUSH PRIVILEGES;
SQL
```

Replace both `CHANGE_ME` occurrences with the same password you put in `.env.monitoring`. If `MYSQL_ROOT_PASSWORD` is not in your shell, run the SQL through a one-off exec after entering the root password yourself.

If this repository was ever public, treat the old MySQL root password as leaked and rotate it after monitoring is up (see the guide).

## C) Optional: PHP-FPM status page (needed for the PHP-FPM panels)

```bash
cd /var/www/delivery/delivery-deployment
docker compose --env-file .env.production \
  -f docker-compose.yml -f monitoring/docker-compose.fpm-status.yml \
  up -d --no-deps backend-app
```

This recreates `delivery-backend-app` once (~2s of 502s locally). The status path is not published on HTTP; the exporter scrapes FastCGI on port 9000.

Also confirm `nginx/backend.conf` still has `location /stub_status` (allow only private ranges). If the running nginx container predates that location, recreate it:

```bash
docker compose --env-file .env.production up -d --no-deps --force-recreate backend-nginx
```

## D) Start or refresh the monitoring stack

```bash
cd /var/www/delivery/delivery-deployment/monitoring
docker compose --env-file .env.monitoring -f docker-compose.monitoring.prod.yml pull
docker compose --env-file .env.monitoring -f docker-compose.monitoring.prod.yml up -d
docker compose --env-file .env.monitoring -f docker-compose.monitoring.prod.yml ps
```

If compose errors with `network ... declared as external, but could not be found`, `DELIVERY_NETWORK` is wrong. Fix it in `.env.monitoring` and retry. Do not remove `external: true`.

## E) Check Prometheus targets (SSH tunnel)

From your laptop:

```bash
ssh -L 9090:127.0.0.1:9090 -L 3001:127.0.0.1:3001 USER@103.160.22.27
```

On the server, or through the tunnel:

```bash
curl -s http://127.0.0.1:9090/api/v1/targets | python3 -c '
import json,sys
d=json.load(sys.stdin)
for x in d.get("data",{}).get("activeTargets",[]):
    l=x.get("labels",{})
    print(f"{l.get(\"job\",\"?\"):18} {x.get(\"health\"):5} {l.get(\"instance\",\"\")} {x.get(\"lastError\",\"\")}")
'
```

Jobs that must be **up**: `prometheus`, `cadvisor`, `mysql`, `redis`, `nginx`, `node`, `blackbox-http`. `php-fpm` is up after the FPM overlay. Open http://127.0.0.1:9090/targets through the tunnel.

## F) Open Grafana safely

Grafana listens on `127.0.0.1:3001` only (this branch no longer publishes it on all interfaces).

```bash
# same tunnel as above, then browse:
# http://localhost:3001
```

Log in with `GRAFANA_ADMIN_USER` / `GRAFANA_ADMIN_PASSWORD`. Open **Dashboards → Delivery → Tukaatu Express - Full Site & Infrastructure Overview**.

To put Grafana behind the host OpenResty proxy instead of a tunnel, use `monitoring/openresty/grafana.conf` and keep the bind address on localhost.

## G) Rollback (app containers stay up)

```bash
cd /var/www/delivery/delivery-deployment/monitoring
docker compose --env-file .env.monitoring -f docker-compose.monitoring.prod.yml down
```

Add `-v` only if you also want to wipe Prometheus/Grafana/Loki data volumes.

To drop the FPM status volume, recreate `backend-app` from `docker-compose.yml` alone.

## Do NOT

- Run `docker compose up -d` on the main `docker-compose.yml` as part of this change (except the optional `--no-deps backend-app` / `backend-nginx` recreate above).
- Expose Grafana, Prometheus, or any exporter on `0.0.0.0`.
- Commit `.env.monitoring` or a MySQL password file.
- Use `git reset --hard` on the server if `docker-compose.yml` or `backup.sh` have local edits.
