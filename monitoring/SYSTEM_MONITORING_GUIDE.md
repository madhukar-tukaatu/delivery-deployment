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

---

## 5. End-to-End System Verification Checklist

Run these quick diagnostic commands on the server to verify each monitoring component is healthy and reporting data:

### 1. Check Container Health
```bash
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```
All 9 monitoring containers should show `Up`:
- `delivery-grafana`
- `delivery-prometheus`
- `delivery-loki`
- `delivery-promtail`
- `delivery-cadvisor`
- `delivery-nginx-exporter`
- `delivery-node-exporter`
- `delivery-mysql-exporter`
- `delivery-redis-exporter`

### 2. Verify Prometheus Scrape Targets
Query the Prometheus internal targets API:
```bash
curl -s http://127.0.0.1:9090/api/v1/targets | python3 -c "
import sys, json
data = json.load(sys.stdin)
for t in data['data']['activeTargets']:
    print(f\"{t['labels']['job']}: {t['health']} ({t['scrapeUrl']})\")
"
```
**Expected Output**:
```
prometheus: up
cadvisor: up
nginx: up
node: up
mysql: up
redis: up
```

### 3. Verify Loki Log Ingestion
Check that Loki is ready to receive and serve logs:
```bash
# Check readiness
curl -s http://127.0.0.1:3100/ready
# Output should be: ready

# Query latest 5 lines of logs from Loki
curl -G -s "http://127.0.0.1:3100/loki/api/v1/query" \
  --data-urlencode 'query={container=~"delivery.*"}' \
  --data-urlencode 'limit=5' | python3 -m json.tool | head -n 30
```

### 4. Verify Promtail Log Tailing
Check that Promtail is successfully discovering and streaming from Docker containers:
```bash
curl -s http://127.0.0.1:9080/targets | grep -E "delivery|State"
```

---

## 6. Full Alerting & Reporting Setup Guide

Grafana 11 includes an enterprise-grade Alerting & Reporting engine. Follow this guide to set up automated alerts and scheduled reports.

---

### A. Setting Up Alert Notification Channels (Contact Points)

To receive real-time notifications when an incident occurs:

1. Open Grafana: `http://103.160.22.123:3001`
2. Navigate to: **Alerting** (bell icon on left menu) &rarr; **Contact points**.
3. Click **Add contact point**.

#### Option 1: Telegram Alerts (Recommended for Instant Alerts)
- **Name**: `Telegram-Delivery-Alerts`
- **Integration**: `Telegram`
- **BOT API Token**: Enter your Telegram bot token from `@BotFather`.
- **Chat ID**: Enter your Telegram Group ID or personal ID.
- Click **Test** &rarr; **Save contact point**.

#### Option 2: Discord or Slack Webhooks
- **Name**: `Discord-DevOps-Channel`
- **Integration**: `Discord` (or `Slack`)
- **Webhook URL**: Paste your incoming webhook URL.
- Click **Test** &rarr; **Save contact point**.

#### Option 3: Email Alerts (SMTP)
- Set up SMTP credentials in `monitoring/docker-compose.monitoring.prod.yml` under `grafana` environment:
  ```yaml
  GF_SMTP_ENABLED: "true"
  GF_SMTP_HOST: "smtp.gmail.com:587"
  GF_SMTP_USER: "your-email@gmail.com"
  GF_SMTP_PASSWORD: "your-app-password"
  GF_SMTP_FROM_ADDRESS: "alerts@tukaatu.com"
  ```

---

### B. Configuring Essential Alert Rules in Grafana

Navigate to: **Alerting** &rarr; **Alert rules** &rarr; **New alert rule**.

#### Rule 1: HTTP 500 Error Spike (Critical)
- **Rule Name**: `Tukaatu Express - Elevated 5xx Server Errors`
- **Datasource**: `Loki`
- **Query**:
  ```logql
  sum(rate({container=~".*nginx.*"} |~ " 50[0-9] " [2m]))
  ```
- **Condition**: Alert when query is `> 0.05` for 2 minutes.
- **Summary**: `Nginx is reporting more than 5% HTTP 500 errors. Investigate backend PHP-FPM immediately.`

#### Rule 2: Host Memory Saturation (> 85%)
- **Rule Name**: `VPS - RAM Overload Warning`
- **Datasource**: `Prometheus`
- **Query**:
  ```promql
  (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100
  ```
- **Condition**: Alert when query is `> 85` for 5 minutes.
- **Summary**: `VPS RAM usage has exceeded 85%. Risk of PHP-FPM out-of-memory crash.`

#### Rule 3: Root Disk Storage Running Low (< 15% Free)
- **Rule Name**: `VPS - Low Disk Space`
- **Datasource**: `Prometheus`
- **Query**:
  ```promql
  (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100
  ```
- **Condition**: Alert when query is `< 15` for 10 minutes.
- **Summary**: `Less than 15% disk space remaining on root partition. Prune docker logs and old backups.`

#### Rule 4: MySQL Database Offline or Stalled
- **Rule Name**: `Database - MySQL Service Down`
- **Datasource**: `Prometheus`
- **Query**:
  ```promql
  mysql_up == 0
  ```
- **Condition**: Alert when query is `== 0` for 1 minute.
- **Summary**: `delivery-mysql is unreachable. The application cannot serve traffic.`

---

### C. Exporting Reports & Incident Logs

#### 1. Exporting a Live Dashboard Snapshot / PDF
1. Go to **Dashboards** &rarr; Open **Tukaatu Express - Full Site & Infrastructure Overview**.
2. Select the desired timeframe (e.g., `Last 7 days` or `Yesterday 00:00 to 23:59`).
3. Click the **Share** icon (top right corner):
   - **Snapshot**: Generate an interactive, shareable public link or local snapshot that can be sent to team members.
   - **Print / PDF**: Use your browser's Print dialog (`Ctrl + P`) &rarr; Save as PDF with `Background graphics` enabled for an executive summary report.

#### 2. Exporting Incident Logs as CSV
1. Go to **Explore** (compass icon on left menu).
2. Select datasource: **Loki**.
3. Run your incident query, for example:
   ```logql
   {container=~".*backend-app.*"} |~ "(?i)exception|fatal|error"
   ```
4. Click **Inspect** (top right) &rarr; **Data** tab &rarr; **Download CSV**.
5. You now have the exact timestamped logs and stack traces ready for incident reviews or developer ticketing.

---

### D. Standard Weekly Operations Report Template

Use this markdown template to document weekly production reviews:

```markdown
# Tukaatu Express Weekly System & Traffic Report
**Reporting Period**: [Date] to [Date]
**Platform**: Production VPS (103.160.22.123)

## 1. Traffic & SLA Overview
- Total Handled HTTP Requests: [increase(nginx_http_requests_total[7d])]
- Peak Traffic Rate: [Peak Req/s] on [Date & Time]
- Average Daily Requests: [Total / 7]
- Uptime / Availability SLA: [Calculated Availability %] (Target: 99.9%)

## 2. Infrastructure Health
- Average Host CPU Utilization: [%]
- Peak Host RAM Consumption: [%] (Max limit: 85%)
- Storage Used: [GB] / [Total GB] ([%] free space)
- MySQL Average Queries/sec: [queries/s]
- Redis Memory Footprint: [MB]

## 3. Incident & Error Log Summary
- Total 5xx Server Errors: [Count]
- Total 4xx Client Errors: [Count]
- Failed Queue Jobs: [Count from php artisan queue:failed]
- Top Failing Endpoints:
  1. `POST /api/v1/...` (Reason: ...)
  2. `GET /api/v1/...` (Reason: ...)

## 4. Maintenance Actions Taken
- Docker image pruning executed: [Yes/No]
- Database backup verified: [Yes/No]
- Disk storage headroom verified: [Yes/No]
```
