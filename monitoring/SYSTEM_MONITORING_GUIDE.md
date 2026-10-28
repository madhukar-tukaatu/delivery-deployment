# Tukaatu Express - Full System Application, Monitoring & Reporting Manual

This manual provides the complete technical guide for operating the **Tukaatu Express** application stack, its internal connectivity with the monitoring tools (**Prometheus, Grafana, Loki, Promtail, and Exporters**), the full command reference for the application, and the incident diagnostics and reporting workflow.

---

## 1. How the Delivery System Connects to Monitoring (Data Flow Architecture)

The delivery application stack does not require intrusive proprietary agents. Instead, telemetry flows through dedicated collectors and agents operating over internal Docker virtual networks.

```
       [ Client Request / Rider App ]
                     │
                     ▼
         ┌────────────────────────┐
         │ delivery-backend-nginx │ ──(stdout)──┐
         │      (Port 80/8081)    │             │
         └───────────┬────────────┘             │
                     │                          │
        ┌────────────┴────────────┐             │
        ▼                         ▼             │
┌───────────────┐         ┌───────────────┐     │
│  /stub_status │         │  backend-app  │     │
│   (Internal)  │         │ (PHP-FPM :9000)     │
└───────┬───────┘         └───────┬───────┘     │
        │                         │ (stdout)    │
        ▼                         ▼             ▼
┌───────────────┐         ┌───────────────────────────────┐
│nginx-exporter │         │  Docker Engine Logging Driver │
│    (:9113)    │         │  /var/lib/docker/containers/  │
└───────┬───────┘         └───────────────┬───────────────┘
        │                                 │
        │ PromQL Scrape                   │ Tailed by /var/run/docker.sock
        ▼                                 ▼
┌───────────────┐                 ┌───────────────┐
│  Prometheus   │                 │   Promtail    │
│    (:9090)    │                 │    Agent      │
└───────┬───────┘                 └───────┬───────┘
        │                                 │
        │ Metrics Data                    │ Pushes batches (LogQL)
        ▼                                 ▼
┌─────────────────────────────────────────────────────────┐
│                       GRAFANA 11                        │
│                 Dashboards & Reporting                  │
└─────────────────────────────────────────────────────────┘
```

### The 6 Telemetry Pipelines Explained

#### Pipe 1: Inbound HTTP Traffic & Connection States
1. **Source**: Inbound HTTP requests hit `delivery-backend-nginx`.
2. **Exposure**: Nginx maintains real-time active connections and request totals via the `/stub_status` endpoint (configured in `delivery-deployment/nginx/backend.conf`).
3. **Scraper**: `delivery-nginx-exporter` periodically reads `http://backend-nginx:80/stub_status`.
4. **Metrics Generated**:
   - `nginx_http_requests_total`: Monotonically increasing counter of all handled HTTP requests.
   - `nginx_connections_active`: Total currently open client connections.
   - `nginx_connections_reading`: Requests where Nginx is reading client request headers.
   - `nginx_connections_writing`: Requests where Nginx is writing data back to the client.
   - `nginx_connections_waiting`: Keep-alive client connections waiting for next request.
5. **Storage & Dashboards**: Prometheus pulls these metrics every 15s. Grafana computes `rate(nginx_http_requests_total[1m])` to present real-time **Requests per Second (RPS)**.

#### Pipe 2: Full Site Logs & Multiline Stack Traces
1. **Source**: All services (`backend-app`, `backend-nginx`, `backend-queue`, `backend-scheduler`, `backend-reverb`, `frontend`, `mysql`, `redis`) write logs to standard output (`stdout`) and standard error (`stderr`).
2. **Capture**: Docker writes each line to `/var/lib/docker/containers/<container-id>/<container-id>-json.log`.
3. **Collector**: `delivery-promtail` connects to the Docker socket (`/var/run/docker.sock`) and container directories.
4. **Pipeline Processing**:
   - **Multiline Aggregation**: Promtail detects the Laravel log signature `^(\[\d{4}-\d{2}-\d{2}\s\d{2}:\d{2}:\d{2}\])` and joins entire 50-line PHP stack traces into a single log event.
   - **Severity Extraction**: Inspects text for `ERROR`, `CRITICAL`, `WARNING`, or `INFO` and assigns the `level` label.
   - **HTTP Access Parsing**: From Nginx access logs, extracts `http_method` (GET, POST, etc.) and `http_status` (200, 404, 500).
5. **Push**: Promtail ships chunks over HTTP to `http://loki:3100/loki/api/v1/push`.
6. **Querying**: Grafana connects to Loki datasource. Engineers search logs in real time using LogQL syntax.

#### Pipe 3: Database Throughput (MySQL)
1. **Source**: `delivery-mysql` port `3306`.
2. **Scraper**: `delivery-mysql-exporter` connects using client credentials in `prometheus/my.cnf.prod`.
3. **Metrics Generated**: `mysql_global_status_queries` (throughput), `mysql_global_status_threads_connected` (client pool saturation), `mysql_global_status_slow_queries` (unindexed queries), and InnoDB buffer pool hit ratios.

#### Pipe 4: Cache & Queue Throughput (Redis)
1. **Source**: `delivery-redis` port `6379`.
2. **Scraper**: `delivery-redis-exporter` connects to `redis://delivery-redis:6379`.
3. **Metrics Generated**: `redis_commands_processed_total` (ops/sec), `redis_memory_used_bytes` (RAM consumed), `redis_connected_clients`, and keyspace eviction rates.

#### Pipe 5: Container Resource Utilization (cAdvisor)
1. **Source**: Linux kernel control groups (`cgroups`) on the host.
2. **Collector**: `cAdvisor` mounts `/sys/fs/cgroup`, `/var/run/docker.sock`, and `/var/lib/docker`.
3. **Metrics Generated**: Container CPU utilization seconds, resident memory bytes (`container_memory_working_set_bytes`), and network Rx/Tx bytes per container name.

#### Pipe 6: Host Machine Health (Node Exporter)
1. **Source**: Host VM Linux kernel (`/proc` and `/sys`).
2. **Collector**: `delivery-node-exporter` reads host CPU idle/iowait percentages, memory available, disk read/write bandwidth, and root filesystem free space.

---

## 2. Core Delivery Application Command Reference

### A. Container Lifecycle Commands

#### Local Environment (`delivery-deployment/`)
```powershell
# Start all application containers in background
docker compose -f docker-compose.local.yml up -d

# Check status and health of all app containers
docker compose -f docker-compose.local.yml ps

# View live streaming logs of the backend app
docker compose -f docker-compose.local.yml logs -f backend-app

# View live streaming logs of queue worker
docker compose -f docker-compose.local.yml logs -f backend-queue

# Restart a specific service (e.g. after code or env change)
docker compose -f docker-compose.local.yml restart backend-app backend-nginx

# Stop all local delivery containers
docker compose -f docker-compose.local.yml down
```

#### Production VPS (`/var/www/delivery/delivery-deployment/`)
```bash
# Start all production application containers
docker compose --env-file .env.production up -d

# Check container health and uptime
docker compose --env-file .env.production ps

# Force recreate backend-nginx against fresh PHP-FPM upstream IP
docker compose --env-file .env.production up -d --no-deps --force-recreate backend-nginx

# View live logs of all production app services
docker compose --env-file .env.production logs -f --tail=100 backend-app backend-nginx

# Restart workers cleanly after code updates
docker compose --env-file .env.production restart backend-queue backend-scheduler backend-reverb
```

---

### B. Laravel Backend Artisan Operations

Execute these commands inside the `backend-app` container:

#### 1. Database Migrations & Status
```bash
# Check status of all migrations (ran vs pending)
docker compose --env-file .env.production exec -T backend-app php artisan migrate:status

# Run pending database migrations in production (forced)
docker compose --env-file .env.production exec -T backend-app php artisan migrate --force

# Rollback the last migration batch (use with caution)
docker compose --env-file .env.production exec -T backend-app php artisan migrate:rollback --step=1
```

#### 2. Caching & Performance Optimization
```bash
# Flush all application, route, config, and view caches
docker compose --env-file .env.production exec -T backend-app php artisan optimize:clear

# Rebuild configuration cache (fastest config loading)
docker compose --env-file .env.production exec -T backend-app php artisan config:cache

# Rebuild route cache
docker compose --env-file .env.production exec -T backend-app php artisan route:cache

# Rebuild compiled Blade views
docker compose --env-file .env.production exec -T backend-app php artisan view:cache

# Re-link public storage directory
docker compose --env-file .env.production exec -T backend-app php artisan storage:link
```

#### 3. Queue Management & Background Jobs
```bash
# View list of failed jobs
docker compose --env-file .env.production exec -T backend-app php artisan queue:failed

# Retry all failed jobs
docker compose --env-file .env.production exec -T backend-app php artisan queue:retry all

# Retry a single failed job by ID
docker compose --env-file .env.production exec -T backend-app php artisan queue:retry <JOB_ID>

# Flush (delete) all failed jobs
docker compose --env-file .env.production exec -T backend-app php artisan queue:flush

# Restart queue workers gracefully
docker compose --env-file .env.production exec -T backend-app php artisan queue:restart
```

#### 4. WebSockets (Laravel Reverb)
```bash
# Check if Reverb WebSocket server process is running
docker compose --env-file .env.production exec -T backend-reverb ps aux

# Restart Reverb WebSockets container
docker compose --env-file .env.production restart backend-reverb
```

---

### C. Database & Redis Operations

#### MySQL Backup & Direct CLI
```bash
# Create immediate database backup (.sql file)
docker compose --env-file .env.production exec -T mysql mysqldump -u root -p"$MYSQL_ROOT_PASSWORD" tukaatu_express > /var/backups/delivery/manual_backup_$(date +%F).sql

# Restore a database from a .sql dump
docker compose --env-file .env.production exec -T mysql mysql -u root -p"$MYSQL_ROOT_PASSWORD" tukaatu_express < /path/to/backup.sql

# Open interactive MySQL shell
docker compose --env-file .env.production exec -it mysql mysql -u root -p"$MYSQL_ROOT_PASSWORD" tukaatu_express
```

#### Redis CLI & Queue Inspection
```bash
# Check Redis ping
docker compose --env-file .env.production exec -T redis redis-cli ping

# Check memory stats and total keys
docker compose --env-file .env.production exec -T redis redis-cli info memory

# Check pending jobs in high-priority queue
docker compose --env-file .env.production exec -T redis redis-cli llen "queues:high"

# Check pending jobs in default queue
docker compose --env-file .env.production exec -T redis redis-cli llen "queues:default"
```

---

## 3. Tools Reporting & Incident Diagnostics Guide

When an incident occurs or when generating system performance reports, follow these step-by-step diagnostic workflows.

---

### Scenario A: Diagnosing HTTP 500 Internal Server Errors
1. **Detect the Error Spike**:
   - Open Grafana → Dashboard **Tukaatu Express - Full Site Logs & Diagnostics**.
   - Look at the **Nginx 5xx Server Errors** badge and the **Error & Warning Spikes** graph.
2. **Find the Failing HTTP Route in Nginx Logs**:
   - In the **Nginx Inbound HTTP Traffic Logs** panel, filter with LogQL:
     ```logql
     {container=~".*nginx.*"} |~ " 50[0-9] "
     ```
   - Identify the timestamp, request method (`POST` / `GET`), client IP, and URI (e.g. `/api/v1/pricing/estimate`).
3. **Isolate the PHP Stack Trace**:
   - In the **Backend App & Queue Worker Stack Traces** panel, set the time range to the exact second of the request.
   - Filter with:
     ```logql
     {container=~".*backend-app.*"} |~ "500|Exception|Fatal|Error"
     ```
   - The multiline parser presents the complete PHP file name, line number, and stack trace causing the failure.

---

### Scenario B: Diagnosing Doorstep POD Payment & Webhook Failures
1. **Locate the Payment Session ID**:
   - Identify the `payment_session_id` or rider order number (e.g., `tex_pod_e0fbf8bcb40df9c97cd...`).
2. **Track the Transaction Across All Containers**:
   - In Grafana Log Explorer, run:
     ```logql
     {container=~"delivery.*"} |= "tex_pod_e0fbf8bcb40df9c97cd"
     ```
   - This returns the combined timeline:
     - When Nginx accepted the webhook callback from Store Manager / HamroPay.
     - When `backend-app` validated the HMAC SHA256 signature and timestamp tolerance.
     - When `backend-queue` queued the settlement or delivery status update.
     - Whether any database lock or network timeout occurred.

---

### Scenario C: Diagnosing Slow Requests & High Latency
1. **Check Nginx Connections Saturation**:
   - Open **Tukaatu Express - Full Site & Infrastructure Overview**.
   - Check **Nginx Connections Pool**:
     - High `waiting` = Clients keeping connections alive (normal).
     - High `writing` = Slow client internet or large response payloads.
     - High `reading` = Network congestion or large upload payloads.
2. **Check Database Query Bottlenecks**:
   - Inspect **MySQL Queries / sec** and **Threads Connected**.
   - If queries spike above 500/s while CPU spikes, run in MySQL CLI:
     ```sql
     SHOW FULL PROCESSLIST;
     ```
   - Look for unindexed queries locking tables or long-running transactions.

---

### Scenario D: Generating Weekly Traffic & Health Reports

To compile a weekly operational report for stakeholders:

1. **Traffic Volume (Total Requests Handled)**:
   - In Prometheus or Grafana, set time range to `now-7d`.
   - Run PromQL:
     ```promql
     increase(nginx_http_requests_total[7d])
     ```
   - Gives the exact total number of requests handled during the week.

2. **Peak Traffic Hours**:
   - View the **HTTP Traffic Rate** graph over 7 days.
   - Note the highest Requests/sec peak and matching time of day.

3. **System Error Budget (Availability %)**:
   - Calculate uptime availability percentage:
     ```promql
     (1 - (sum(increase(nginx_http_requests_total{status=~"5.."}[7d])) / sum(increase(nginx_http_requests_total[7d])))) * 100
     ```

4. **Resource Headroom (VPS Capacity Check)**:
   - Review **Host RAM Usage %** and **Root Disk Usage %**.
   - Ensure available memory never dropped below 15% and disk free space remains above 20%.

---

## 4. Full Deployment Workflow (Zero-Downtime Script)

To deploy both code updates and monitoring safely without dropping client connections, use the master automated deploy script:

```bash
cd /var/www/delivery/delivery-deployment
./scripts/deploy.sh main
```

The script performs the following orchestrated steps automatically:
1. `git reset --hard origin/main` across backend, frontend, and deployment repos.
2. Builds Docker images with `--pull`.
3. Brings up updated containers.
4. Recreates `backend-nginx` against fresh PHP-FPM container upstream sockets.
5. Runs `php artisan migrate --force`.
6. Executes `optimize:clear`, `config:cache`, and `route:cache`.
7. Gracefully restarts queue workers and WebSockets.
8. Reloads Nginx without dropping traffic (`nginx -s reload`).
9. Prunes dangling Docker images.
