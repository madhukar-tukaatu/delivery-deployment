
# Delivery monitoring stack

Prometheus, Grafana, Loki, exporters and Alertmanager for Tukaatu Express.

- **Local:** `docker compose -f docker-compose.monitoring.yml up -d` from this directory. Grafana: http://127.0.0.1:3001 (admin/admin). Requires the `delivery-local` stack to be running.
- **Production:** follow [DEPLOY-VPS.md](DEPLOY-VPS.md). All ports bind to 127.0.0.1. Reach Grafana through an SSH tunnel or the OpenResty snippet in `openresty/grafana.conf`.

Dashboards are provisioned from `grafana/dashboards/`:

- `Tukaatu Express - Full Site & Infrastructure Overview` (uid `delivery-overview`)
- `Tukaatu Express - Full Site Logs & Diagnostics` (uid `delivery-logs`)

Alert rules live in `prometheus/alerts.yml`. Alertmanager ships with a placeholder receiver only — no credentials are invented here.

PHP-FPM panels need the optional overlay `docker-compose.fpm-status.yml` applied to `backend-app`.
