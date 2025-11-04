# 📊 Monitoring & Observability Guide

Complete guide to monitoring your Tor Guard Relay with **Prometheus**, **Grafana**, and **Alertmanager**.

---

## 📋 Overview

This guide covers:
- ✅ Prometheus metrics collection
- ✅ Grafana dashboard setup
- ✅ Alert configuration
- ✅ Multi-relay monitoring
- ✅ Best practices and troubleshooting

---

## 🏗️ Architecture

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  Tor Relay  │────▶│ Prometheus  │────▶│   Grafana   │
│   :9035     │     │    :9090    │     │    :3000    │
└─────────────┘     └──────┬──────┘     └─────────────┘
                           │
                           ▼
                    ┌─────────────┐
                    │Alertmanager │
                    │    :9093    │
                    └─────────────┘
```

**Components:**
- **Tor Relay** - Exposes metrics via `metrics-http` tool on port 9035
- **Prometheus** - Scrapes and stores metrics
- **Grafana** - Visualizes metrics with dashboards
- **Alertmanager** - Handles alerts and notifications

---

## 🚀 Quick Start

### Single Relay with Monitoring

Use the provided Docker Compose template:

```bash
# Download template
curl -O https://raw.githubusercontent.com/r3bo0tbx1/tor-guard-relay/main/templates/docker-compose.yml

# Download Prometheus config
curl -O https://raw.githubusercontent.com/r3bo0tbx1/tor-guard-relay/main/templates/prometheus.yml

# Start services
docker-compose up -d

# Access Grafana
open http://localhost:3000
```

### Multi-Relay Setup

For monitoring multiple relays:

```bash
# Download multi-relay template
curl -O https://raw.githubusercontent.com/r3bo0tbx1/tor-guard-relay/main/templates/docker-compose-multi-relay.yml

# Configure and start
docker-compose -f docker-compose-multi-relay.yml up -d
```

---

## 📊 Metrics Reference

### Available Metrics

All metrics are prefixed with `tor_relay_` and include a `relay_name` label.

#### Bootstrap & Connectivity

```prometheus
# Bootstrap completion percentage (0-100)
tor_relay_bootstrap_percent{relay_name="MyRelay"} 100

# ORPort reachability (1=reachable, 0=unreachable)
tor_relay_or_port_reachable{relay_name="MyRelay",port="9001"} 1

# DirPort reachability (1=reachable, 0=unreachable)
tor_relay_dir_port_reachable{relay_name="MyRelay",port="9030"} 1
```

#### Performance

```prometheus
# Relay uptime in seconds
tor_relay_uptime_seconds{relay_name="MyRelay"} 214830

# Configured bandwidth rate in bytes/sec
tor_relay_bandwidth_rate_bytes{relay_name="MyRelay"} 52428800

# Configured bandwidth burst in bytes/sec
tor_relay_bandwidth_burst_bytes{relay_name="MyRelay"} 104857600
```

#### Health Status

```prometheus
# Overall health status (1=healthy, 0=unhealthy)
tor_relay_healthy{relay_name="MyRelay"} 1

# Error count
tor_relay_errors_total{relay_name="MyRelay"} 0

# Warning count
tor_relay_warnings_total{relay_name="MyRelay"} 0
```

#### System Resources (when available)

```prometheus
# CPU usage percentage
process_cpu_seconds_total{relay_name="MyRelay"} 1234.56

# Memory usage in bytes
process_resident_memory_bytes{relay_name="MyRelay"} 134217728

# Open file descriptors
process_open_fds{relay_name="MyRelay"} 42
```

---

## 🎨 Prometheus Configuration

### Basic Configuration

**File:** `prometheus.yml`

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    cluster: 'tor-relays'
    environment: 'production'

# Scrape configurations
scrape_configs:
  # Single relay
  - job_name: 'tor-relay'
    static_configs:
      - targets: ['tor-relay:9035']
        labels:
          relay_name: 'MyTorRelay'
  
  # Multiple relays
  - job_name: 'tor-relay-multi'
    static_configs:
      - targets:
        - 'tor-relay-1:9035'
        - 'tor-relay-2:9036'
        - 'tor-relay-3:9037'
        labels:
          cluster: 'tor-multi-relay'
```

### Auto-Discovery (Docker)

For dynamic relay discovery:

```yaml
scrape_configs:
  - job_name: 'tor-relays-docker'
    docker_sd_configs:
      - host: unix:///var/run/docker.sock
    relabel_configs:
      - source_labels: [__meta_docker_container_label_com_example_service]
        regex: 'tor-relay'
        action: keep
      - source_labels: [__meta_docker_container_name]
        target_label: relay_name
```

---

## 📈 Grafana Dashboards

### Pre-built Dashboard

A complete Grafana dashboard is provided in the repository:

```bash
# Import dashboard
curl -O https://raw.githubusercontent.com/r3bo0tbx1/tor-guard-relay/main/templates/grafana-dashboard.json

# In Grafana UI:
# 1. Go to Dashboards → Import
# 2. Upload grafana-dashboard.json
# 3. Select Prometheus datasource
# 4. Click Import
```

### Dashboard Panels

The provided dashboard includes:

1. **Overview Row**
   - Relay Status (UP/DOWN)
   - Bootstrap Progress
   - Uptime
   - ORPort/DirPort Reachability

2. **Network Row**
   - Public IP Address
   - Port Status
   - Bandwidth Configuration

3. **Performance Row**
   - CPU Usage Graph
   - Memory Usage Graph
   - Network Traffic (if available)

4. **Health Row**
   - Error Count
   - Warning Count
   - Recent Issues Timeline

5. **Multi-Relay Row** (when monitoring multiple relays)
   - Relay Comparison Table
   - Aggregate Statistics

### Custom Queries

Example PromQL queries for custom panels:

```prometheus
# Average bootstrap across all relays
avg(tor_relay_bootstrap_percent)

# Relays not fully bootstrapped
count(tor_relay_bootstrap_percent < 100)

# Total bandwidth capacity
sum(tor_relay_bandwidth_rate_bytes)

# Relay availability (24h)
avg_over_time(tor_relay_healthy[24h])

# Unreachable relays
count(tor_relay_or_port_reachable == 0)
```

---

## 🚨 Alerting

### Alert Rules

**File:** `prometheus-alerts.yml`

```yaml
groups:
  - name: tor_relay_alerts
    interval: 30s
    rules:
      # Critical: Relay is down
      - alert: TorRelayDown
        expr: up{job="tor-relay"} == 0
        for: 5m
        labels:
          severity: critical
          alert_type: availability
        annotations:
          summary: "Relay {{ $labels.relay_name }} is down"
          description: "Relay has been unreachable for 5 minutes"

      # Critical: Bootstrap not complete
      - alert: TorBootstrapIncomplete
        expr: tor_relay_bootstrap_percent < 100
        for: 10m
        labels:
          severity: warning
          alert_type: bootstrap
        annotations:
          summary: "Relay {{ $labels.relay_name }} bootstrap incomplete"
          description: "Bootstrap at {{ $value }}% for 10+ minutes"

      # Critical: ORPort unreachable
      - alert: TorORPortUnreachable
        expr: tor_relay_or_port_reachable == 0
        for: 10m
        labels:
          severity: critical
          alert_type: reachability
        annotations:
          summary: "Relay {{ $labels.relay_name }} ORPort unreachable"
          description: "ORPort {{ $labels.port }} has been unreachable for 10 minutes"

      # Warning: High error count
      - alert: TorRelayHighErrors
        expr: increase(tor_relay_errors_total[5m]) > 5
        for: 5m
        labels:
          severity: warning
          alert_type: health
        annotations:
          summary: "Relay {{ $labels.relay_name }} has high error count"
          description: "{{ $value }} errors in last 5 minutes"

      # Warning: High CPU usage
      - alert: TorRelayHighCPU
        expr: rate(process_cpu_seconds_total[5m]) > 0.8
        for: 15m
        labels:
          severity: warning
          alert_type: performance
        annotations:
          summary: "Relay {{ $labels.relay_name }} high CPU"
          description: "CPU usage: {{ $value | humanizePercentage }}"

      # Warning: High memory usage
      - alert: TorRelayHighMemory
        expr: process_resident_memory_bytes / 1024 / 1024 > 512
        for: 10m
        labels:
          severity: warning
          alert_type: performance
        annotations:
          summary: "Relay {{ $labels.relay_name }} high memory"
          description: "Memory: {{ $value | humanize }}MB"
```

### Alertmanager Configuration

**File:** `alertmanager.yml`

```yaml
global:
  resolve_timeout: 5m
  slack_api_url: 'YOUR_SLACK_WEBHOOK_URL'

route:
  receiver: 'default'
  group_by: ['alertname', 'relay_name']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 12h
  
  routes:
    # Critical alerts - immediate notification
    - match:
        severity: critical
      receiver: 'critical-alerts'
      group_wait: 10s
      repeat_interval: 4h
    
    # Warnings - less frequent
    - match:
        severity: warning
      receiver: 'warnings'
      group_wait: 2m
      repeat_interval: 24h

receivers:
  - name: 'default'
    slack_configs:
      - channel: '#tor-relay-general'
        title: '🧅 Tor Guard Relay Alert'
        text: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'

  - name: 'critical-alerts'
    slack_configs:
      - channel: '#tor-relay-critical'
        title: '🚨 CRITICAL: Tor Relay Alert'
        text: '{{ range .Alerts }}{{ .Annotations.summary }}{{ end }}'
        color: '{{ if eq .Status "firing" }}danger{{ else }}good{{ end }}'
    
    # Optional: Discord webhook
    webhook_configs:
      - url: 'YOUR_DISCORD_WEBHOOK_URL'

  - name: 'warnings'
    slack_configs:
      - channel: '#tor-relay-warnings'
        title: '⚠️ Warning: Tor Relay'
        text: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'
```

---

## 🔍 Troubleshooting

### Prometheus Not Scraping Metrics

```bash
# Check if metrics endpoint is accessible
curl http://localhost:9035/metrics

# Check Prometheus targets
open http://localhost:9090/targets

# Check container networking
docker network inspect bridge

# Verify ENABLE_METRICS is set
docker exec tor-relay env | grep ENABLE_METRICS
```

### No Data in Grafana

```bash
# Verify Prometheus datasource
# Grafana → Configuration → Data Sources → Prometheus
# Test the connection

# Check if Prometheus has data
curl 'http://localhost:9090/api/v1/query?query=tor_relay_uptime_seconds'

# Check time range in Grafana dashboard
# Ensure time range covers when relay was running
```

### Alerts Not Firing

```bash
# Check alert rules are loaded
open http://localhost:9090/rules

# Verify Alertmanager connection
open http://localhost:9090/alerts

# Check Alertmanager is receiving alerts
open http://localhost:9093

# Test webhook endpoints
curl -X POST YOUR_SLACK_WEBHOOK_URL -d '{"text":"Test"}'
```

---

## 📊 Best Practices

### 1. Retention Configuration

```yaml
# In prometheus.yml
global:
  # Keep metrics for 30 days
  storage.tsdb.retention.time: 30d
  
  # Or limit by size
  storage.tsdb.retention.size: 10GB
```

### 2. Scrape Intervals

- **Production:** 15-30 seconds
- **Development:** 5-10 seconds
- **High-load relays:** 30-60 seconds

### 3. Alert Tuning

- Set appropriate `for` durations to avoid alert fatigue
- Use `group_wait` to batch related alerts
- Configure escalation via `repeat_interval`

### 4. Dashboard Organization

- Use template variables for relay selection
- Create separate dashboards for overview vs. detailed metrics
- Use row collapse for optional sections

### 5. Resource Management

```yaml
# Limit Prometheus memory
command:
  - '--storage.tsdb.retention.time=30d'
  - '--config.file=/etc/prometheus/prometheus.yml'
  
# Set resource limits in Docker Compose
deploy:
  resources:
    limits:
      cpus: '1'
      memory: 2G
```

---

## 🔐 Security

### Metrics Endpoint Protection

```nginx
# Nginx reverse proxy example
server {
    listen 443 ssl;
    server_name metrics.example.com;

    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;

    location /metrics {
        auth_basic "Restricted";
        auth_basic_user_file /etc/nginx/.htpasswd;
        proxy_pass http://localhost:9035;
    }
}
```

### Grafana Authentication

```yaml
# In grafana datasource config
environment:
  - GF_SECURITY_ADMIN_PASSWORD=secure_password_here
  - GF_USERS_ALLOW_SIGN_UP=false
  - GF_AUTH_ANONYMOUS_ENABLED=false
```

---

## 📚 Related Documentation

- [Tools Reference](./TOOLS.md) - Detailed tool documentation
- [Deployment Guide](./DEPLOYMENT.md) - Installation instructions
- [Performance Guide](./PERFORMANCE.md) - Optimization tips
- [Backup Guide](./BACKUP.md) - Data persistence

---

## 🆘 Support

- 📖 [Prometheus Documentation](https://prometheus.io/docs/)
- 📖 [Grafana Documentation](https://grafana.com/docs/)
- 🐛 [Report Issues](https://github.com/r3bo0tbx1/tor-guard-relay/issues)
- 💬 [Community Forum](https://forum.torproject.org/)

---

**Last Updated:** November 2025 | **Version:** 1.1