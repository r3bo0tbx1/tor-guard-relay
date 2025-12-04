# 📊 Monitoring Guide

Guide to monitoring your Tor Guard Relay with external tools. The >=v1.1.1 ultra-optimized build (~20 MB) does not include built-in Prometheus metrics endpoints, but provides multiple alternatives for monitoring.

---

## 📋 Overview

**What Changed in v1.1.1:**
- ❌ Removed built-in `metrics-http` server (to reduce image size)
- ❌ Removed Python-based dashboard
- ✅ Kept `health` tool for JSON status output
- ✅ Kept `status` tool for human-readable output
- ✅ Enhanced logging for external monitoring integration

**Monitoring Options:**
1. Docker health checks (built-in)
2. `health` tool with external scrapers
3. Log file monitoring
4. External Prometheus exporters
5. Cloud monitoring services

---

## 🚀 Quick Start Options

### Option 1: Docker Health Checks (Simplest)

Built-in Docker health checks automatically monitor relay status:

```bash
# Check health status
docker inspect --format='{{.State.Health.Status}}' tor-relay

# Get health history (requires jq on host)
docker inspect --format='{{json .State.Health}}' tor-relay | jq
```

**Healthcheck Configuration:**
```yaml
# Already included in all compose templates
healthcheck:
  test: ["CMD-SHELL", "/usr/local/bin/healthcheck.sh"]
  interval: 10m
  timeout: 15s
  start_period: 30s
  retries: 3
```

**Monitoring:**
- Use `docker events` to watch health changes
- Integrate with Docker monitoring tools (Portainer, Netdata, etc.)
- Alert on `health_status: unhealthy` events

---

### Option 2: Health Tool with External Scraper

Use the `health` tool's JSON output with your monitoring system:

**Setup Simple HTTP Wrapper:**
```bash
# Create simple health endpoint with netcat
while true; do
  HEALTH=$(docker exec tor-relay health)
  echo -e "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n$HEALTH" | nc -l -p 9100
done
```

**Or use a proper wrapper script:**
```python
#!/usr/bin/env python3
from flask import Flask, jsonify
import subprocess
import json

app = Flask(__name__)

@app.route('/health')
def health():
    result = subprocess.run(
        ['docker', 'exec', 'tor-relay', 'health'],
        capture_output=True,
        text=True
    )
    return jsonify(json.loads(result.stdout))

@app.route('/metrics')
def metrics():
    health_data = subprocess.run(
        ['docker', 'exec', 'tor-relay', 'health'],
        capture_output=True,
        text=True
    )
    data = json.loads(health_data.stdout)

    # Convert to Prometheus format
    metrics = f"""# HELP tor_relay_up Relay is running
# TYPE tor_relay_up gauge
tor_relay_up {{nickname="{data['nickname']}"}} {1 if data['status'] == 'up' else 0}

# HELP tor_relay_bootstrap_percent Bootstrap completion
# TYPE tor_relay_bootstrap_percent gauge
tor_relay_bootstrap_percent {{nickname="{data['nickname']}"}} {data['bootstrap']}

# HELP tor_relay_errors Error count
# TYPE tor_relay_errors gauge
tor_relay_errors {{nickname="{data['nickname']}"}} {data['errors']}
"""
    return metrics, 200, {'Content-Type': 'text/plain; charset=utf-8'}

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=9100)
```

**Prometheus Configuration:**
```yaml
scrape_configs:
  - job_name: 'tor-relay'
    static_configs:
      - targets: ['localhost:9100']
    scrape_interval: 60s
```

---

### Option 3: Log File Monitoring

Monitor Tor logs directly for events and errors:

**Filebeat Configuration:**
```yaml
# filebeat.yml
filebeat.inputs:
  - type: log
    enabled: true
    paths:
      - /var/lib/docker/volumes/tor-guard-logs/_data/notices.log
    fields:
      service: tor-relay
    multiline:
      pattern: '^\['
      negate: true
      match: after

output.elasticsearch:
  hosts: ["localhost:9200"]
  index: "tor-relay-logs-%{+yyyy.MM.dd}"
```

**Promtail Configuration (for Loki):**
```yaml
# promtail-config.yml
server:
  http_listen_port: 9080

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://localhost:3100/loki/api/v1/push

scrape_configs:
  - job_name: tor-relay
    static_configs:
      - targets:
          - localhost
        labels:
          job: tor-relay
          __path__: /var/lib/docker/volumes/tor-guard-logs/_data/*.log
```

**Key Log Patterns to Monitor:**
```bash
# Bootstrap complete
grep "Bootstrapped 100%" /var/log/tor/notices.log

# ORPort reachability
grep "Self-testing indicates your ORPort is reachable" /var/log/tor/notices.log

# Errors
grep "\[err\]" /var/log/tor/notices.log

# Warnings
grep "\[warn\]" /var/log/tor/notices.log

# Bandwidth self-test
grep "bandwidth self-test...done" /var/log/tor/notices.log
```

---

### Option 4: External Prometheus Exporters

Use dedicated Tor exporters that parse Tor control port:

**Option A: tor_exporter**
```bash
# Install tor_exporter
docker run -d --name tor-exporter \
  --network host \
  ghcr.io/atx/prometheus-tor_exporter:latest \
  --tor.control-address=127.0.0.1:9051

# Add to Prometheus
scrape_configs:
  - job_name: 'tor-exporter'
    static_configs:
      - targets: ['localhost:9099']
```

**Option B: Custom exporter from health tool**

See Option 2 above for Python Flask example.

---

### Option 5: Cloud Monitoring Services

**DataDog:**
```yaml
# datadog.yaml
logs:
  - type: file
    path: /var/lib/docker/volumes/tor-guard-logs/_data/notices.log
    service: tor-relay
    source: tor

checks:
  http_check:
    instances:
      - name: tor-relay-health
        url: http://localhost:9100/health
        timeout: 5
```

**New Relic:**
```yaml
integrations:
  - name: nri-docker
    env:
      DOCKER_API_VERSION: v1.40
    interval: 60s

  - name: nri-flex
    config:
      name: tor-relay-health
      apis:
        - event_type: TorRelayHealth
          commands:
            - run: docker exec tor-relay health
              split: none
```

---

## 📊 Monitoring Metrics

**Available from `health` tool:**
```json
{
  "status": "up|down|error",
  "pid": 123,
  "uptime": "2d 14h 30m",
  "bootstrap": 0-100,
  "reachable": "true|false",
  "errors": 0,
  "nickname": "MyRelay",
  "fingerprint": "ABCD..."
}
```

**Key Metrics to Track:**
- `status` - Relay health (up/down/error)
- `bootstrap` - Connection progress (0-100%)
- `reachable` - ORPort accessibility
- `errors` - Error count
- `uptime` - Relay uptime

**From Logs:**
- Bootstrap events
- ORPort reachability tests
- Bandwidth usage
- Connection counts (if exit relay)
- Warning and error messages

---

## 🔔 Alerting

### Simple Shell Script Alert
```bash
#!/bin/bash
# check-tor-relay.sh
# Requires: jq installed on host (apt install jq / brew install jq)

STATUS=$(docker exec tor-relay health | jq -r '.status')
BOOTSTRAP=$(docker exec tor-relay health | jq -r '.bootstrap')
ERRORS=$(docker exec tor-relay health | jq -r '.errors')

if [ "$STATUS" != "up" ]; then
  echo "CRITICAL: Tor relay is $STATUS"
  # Send alert via email, Slack, Discord, etc.
  curl -X POST https://hooks.slack.com/services/YOUR/WEBHOOK \
    -d "{\"text\": \"Tor relay is $STATUS\"}"
  exit 2
fi

if [ "$BOOTSTRAP" -lt 100 ]; then
  echo "WARNING: Bootstrap at $BOOTSTRAP%"
  exit 1
fi

if [ "$ERRORS" -gt 0 ]; then
  echo "WARNING: $ERRORS errors detected"
  exit 1
fi

echo "OK: Relay healthy, $BOOTSTRAP% bootstrapped"
exit 0
```

**Run with cron:**
```cron
*/5 * * * * /usr/local/bin/check-tor-relay.sh
```

### Docker Events Alert
```bash
#!/bin/bash
# watch-docker-health.sh
# Requires: jq installed on host (apt install jq / brew install jq)

docker events --filter 'event=health_status' --format '{{json .}}' | while read event; do
  STATUS=$(echo $event | jq -r '.Actor.Attributes."health_status"')
  CONTAINER=$(echo $event | jq -r '.Actor.Attributes.name')

  if [ "$STATUS" = "unhealthy" ]; then
    echo "ALERT: $CONTAINER is unhealthy"
    # Send notification
  fi
done
```

---

## 🏗️ Example: Complete Monitoring Stack

**Docker Compose with external monitoring:**

```yaml
version: '3.8'

services:
  tor-relay:
    image: r3bo0tbx1/onion-relay:latest
    container_name: tor-relay
    network_mode: host
    volumes:
      - ./relay.conf:/etc/tor/torrc:ro
      - tor-data:/var/lib/tor
      - tor-logs:/var/log/tor
    healthcheck:
      test: ["CMD", "tor", "--verify-config", "-f", "/etc/tor/torrc"]
      interval: 10m
      timeout: 15s
      retries: 3

  # Health exporter (Python wrapper)
  health-exporter:
    image: python:3.11-slim
    container_name: tor-health-exporter
    network_mode: host
    volumes:
      - ./health-exporter.py:/app/exporter.py
      - /var/run/docker.sock:/var/run/docker.sock:ro
    command: python /app/exporter.py
    depends_on:
      - tor-relay

  # Prometheus
  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus-data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.retention.time=30d'

  # Grafana
  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
    volumes:
      - grafana-data:/var/lib/grafana

volumes:
  tor-data:
  tor-logs:
  prometheus-data:
  grafana-data:
```

---

## 💡 Tips & Best Practices

1. **Use `health` tool** - JSON output perfect for automation
2. **Monitor Docker health** - Built-in, no extra tools needed
3. **Alert on status changes** - Watch for `status != "up"`
4. **Track bootstrap** - New relays take 5-15 minutes
5. **Monitor logs** - Tor logs are comprehensive and informative
6. **External exporters** - Use tor_exporter for detailed metrics
7. **Keep it simple** - Don't over-complicate monitoring

---

## 📚 Related Documentation

- [Tools Reference](./TOOLS.md) - Built-in diagnostic tools
- [Deployment Guide](./DEPLOYMENT.md) - Installation and configuration
- [Performance Guide](./PERFORMANCE.md) - Optimization tips

---

## ❓ FAQ

**Q: Why was the built-in metrics endpoint removed?**
A: To achieve the ultra-small image size (~20 MB). The metrics server required Python, Flask, and other dependencies (~25+ MB). External monitoring is more flexible anyway.

**Q: Can I still use Prometheus?**
A: Yes! Use the Python wrapper example above, or a dedicated Tor exporter like `prometheus-tor_exporter`.

**Q: What's the simplest monitoring option?**
A: Docker health checks + the `health` tool. No additional infrastructure needed.

**Q: How do I monitor multiple relays?**
A: Run the health exporter on each host, or use log aggregation (Loki, ELK, Datadog).

**Q: Where can I find the logs?**
A:
- Inside container: `/var/log/tor/notices.log`
- On host: `/var/lib/docker/volumes/tor-guard-logs/_data/notices.log`
- Via docker: `docker logs tor-relay`

---

**Last Updated:** December 2025 | **Version:** 1.1.3