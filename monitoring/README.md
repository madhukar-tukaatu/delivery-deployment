# Tukaatu Express Monitoring, Logs & Load Testing Stack

Full-site observability stack for Tukaatu Express: **Grafana, Prometheus, Loki, Promtail, Nginx Exporter, Node Exporter, cAdvisor, MySQL Exporter, Redis Exporter, and k6**.

---

## What It Monitors

1. **Full Site Logs (Loki + Promtail)**:
   - **Real-Time Live Logs**: Ingests logs from all containers (`backend-app`, `backend-nginx`, `backend-queue`, `backend-scheduler`, `backend-reverb`, `frontend`, `mysql`, `redis`).
   - **Laravel Stack Traces**: Multiline grouping captures complete exception traces rather than splitting them into fragmented lines.
   - **Nginx Inbound Traffic Logs**: Captures HTTP status codes (200, 404, 500), requested URIs, HTTP methods, client IPs.
   - **Log Filtering**: Filter by service and search keywords directly in Grafana.

2. **Traffic & Web Server Performance (Prometheus + Nginx Exporter)**:
   - Real-time HTTP requests per second (RPS)
   - Nginx connection pool (Active connections, Reading, Writing, Waiting/Keep-alive)
   - Inbound / outbound network bandwidth

3. **Database & Cache Health (MySQL & Redis Exporters)**:
   - MySQL queries per second, slow queries, active thread connections
   - Redis commands per second, memory consumption, keyspace stats

4. **Host VM & Container Infrastructure (Node Exporter & cAdvisor)**:
   - Host CPU load %, RAM availability, Root disk storage % used
   - Per-container CPU % and working memory (RAM)

---

## Start Monitoring (Local Development)

Ensure your local app containers (`docker-compose.local.yml`) are running, then start the monitoring stack:

```bash
cd delivery-deployment/monitoring
docker compose -f docker-compose.monitoring.yml up -d
```

### URLs

| Service | Local URL | Default Credentials | Description |
|---|---|---|---|
| **Grafana** | `http://localhost:3001` | `admin` / `admin` | Dashboards, Log Explorer & Metrics |
| **Prometheus** | `http://localhost:9090` | None | Scrape targets, PromQL queries |
| **Loki** | `http://localhost:3100` | None | Log aggregation HTTP API |
| **cAdvisor** | `http://localhost:8086` | None | Container metrics browser |

### Pre-Configured Grafana Dashboards

Dashboards are provisioned automatically in Grafana folder **Delivery**:
1. **Tukaatu Express - Full Site & Infrastructure Overview**:
   - HTTP request rates, active connections, host CPU/RAM/Disk, container CPU/RAM, MySQL queries, Redis ops.
2. **Tukaatu Express - Full Site Logs & Diagnostics**:
   - Live streaming logs from all services, error rate histograms, Nginx HTTP access traffic logs, and backend exception trace viewer.

---

## Production VPS Deployment

See [DEPLOY-VPS.md](./DEPLOY-VPS.md).

Uses `docker-compose.monitoring.prod.yml` + `.env.monitoring`.
All services bind strictly to `127.0.0.1` and run with strict memory/CPU limits (~800MB - 1GB footprint total) to protect app performance on a 2GB–4GB VM.

---

## Stop Monitoring

```bash
docker compose -f docker-compose.monitoring.yml down
```

Add `-v` if you also want to clear persisted metrics and log databases (`prometheus_data`, `grafana_data`, `loki_data`).
