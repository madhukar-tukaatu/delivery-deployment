# Delivery local monitoring + load testing

Stack: Prometheus, Grafana, cAdvisor, MySQL exporter, Redis exporter, k6 (on demand).

## Start monitoring (while delivery-local is already up)

```bash
cd delivery-deployment/monitoring
docker compose -f docker-compose.monitoring.yml up -d
```

## URLs

| Service     | URL                      | Notes                |
|------------|---------------------------|----------------------|
| Grafana    | http://localhost:3001     | admin / admin        |
| Prometheus | http://localhost:9090     | targets status       |
| cAdvisor   | http://localhost:8086     | container metrics    |

Dashboard: **Delivery / Delivery local overview** (auto-provisioned).

## Run k6 from Docker

From `monitoring/`:

```bash
# smoke
docker compose -f docker-compose.monitoring.yml run --rm -e BASE_URL=http://delivery-local-backend-nginx -e FRONTEND_URL=http://delivery-local-frontend:3000 k6 run /scripts/smoke.js

# peak (~10k DAU-ish concurrent browsers)
docker compose -f docker-compose.monitoring.yml run --rm -e BASE_URL=http://delivery-local-backend-nginx k6 run /scripts/peak-10k-dau.js

# login load (set a real password)
docker compose -f docker-compose.monitoring.yml run --rm ^
  -e BASE_URL=http://delivery-local-backend-nginx ^
  -e LOGIN_EMAIL=admin@example.com ^
  -e LOGIN_PASSWORD=your-password ^
  k6 run /scripts/auth-login.js
```

Watch Grafana while k6 runs: container CPU/memory, MySQL queries, Redis commands.

## Stop

```bash
docker compose -f docker-compose.monitoring.yml down
```

Data volumes (`prometheus_data`, `grafana_data`) are kept unless you add `-v`.

## Notes

- This monitors infrastructure. App-level Laravel metrics (request latency by route) need a later instrumentation step.
- On Docker Desktop Windows, cAdvisor metrics for containers are the useful signal; host Node Exporter is skipped on purpose.
- Default Grafana password is `admin` — change it before any shared/VPS use.

## VPS (production) deploy

See [DEPLOY-VPS.md](./DEPLOY-VPS.md). Use `docker-compose.monitoring.prod.yml` + `.env.monitoring` — separate from the app compose so server git dirty files are safe.