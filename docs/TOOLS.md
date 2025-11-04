# 🛠️ Tools Reference Guide

**Tor Guard Relay v1.1** includes a comprehensive suite of diagnostic and management tools built directly into the container. All tools are Alpine-compatible, executable without file extensions, and designed for production use.

---

## 📋 Tool Overview

| Tool | Purpose | Output Format | ENV Variables |
|------|---------|---------------|---------------|
| **status** | Complete relay health report | Text (emoji) | None |
| **fingerprint** | Display relay fingerprint | Text | None |
| **health** | JSON health diagnostics | JSON | None |
| **metrics** | Prometheus metrics | Prometheus | `RELAY_NICKNAME` |
| **metrics-http** | HTTP metrics server | HTTP | `METRICS_PORT` |
| **dashboard** | Live HTML dashboard | HTML | None |
| **setup** | Interactive config wizard | Interactive | All Tor vars |
| **net-check** | Network diagnostics | Text (emoji) | None |
| **view-logs** | Live log streaming | Text | `TOR_LOG_DIR` |

---

## 🔧 Tool Details

### `status`

**Purpose:** Comprehensive relay health and status report

**Usage:**
```bash
docker exec tor-relay status
```

**Output Example:**
```
🧅 Tor Relay Status Report
═══════════════════════════════════

📦 Build Information
   Version: v1.1
   Build Date: 2025-11-04
   Architecture: amd64

🚀 Bootstrap Progress
   Status: ✅ Complete (100%)
   Circuits: 3 active

🔗 Network Status
   ORPort: ✅ Reachable (9001)
   Public IP: 203.0.113.42
   
📊 Performance
   Uptime: 2d 14h 30m
   Bandwidth: 50 MB/s
```

**Environment Variables:** None required

**Exit Codes:**
- `0` - Status retrieved successfully
- `1` - Tor service not running or error

---

### `fingerprint`

**Purpose:** Display relay fingerprint with direct links to Tor Metrics

**Usage:**
```bash
docker exec tor-relay fingerprint
```

**Output Example:**
```
🔑 Tor Relay Fingerprint

Nickname: MyTorRelay
Fingerprint: 1234 5678 90AB CDEF 1234 5678 90AB CDEF 1234 5678

🔗 Tor Metrics: https://metrics.torproject.org/rs.html#details/123456...
```

**Environment Variables:** None required

**Exit Codes:**
- `0` - Fingerprint retrieved
- `1` - Fingerprint not yet available (bootstrapping)

---

### `health`

**Purpose:** Machine-readable JSON health check for monitoring systems

**Usage:**
```bash
docker exec tor-relay health
```

**Output Example:**
```json
{
  "status": "healthy",
  "uptime": 214830,
  "bootstrap": {
    "percent": 100,
    "status": "Done"
  },
  "timestamp": "2025-11-04T12:30:45Z",
  "relay_info": {
    "nickname": "MyTorRelay",
    "fingerprint": "1234567890ABCDEF...",
    "or_port": 9001,
    "dir_port": 9030
  },
  "network": {
    "or_port_reachable": true,
    "dir_port_reachable": true,
    "public_ip": "203.0.113.42"
  },
  "issues": {
    "errors": 0,
    "warnings": 0
  }
}
```

**Environment Variables:** None required

**Status Values:**
- `healthy` - All systems operational
- `warning` - Minor issues detected
- `error` - Critical issues present
- `bootstrapping` - Still connecting to Tor network

**Exit Codes:**
- `0` - Health check completed
- `1` - Critical error or Tor not running

---

### `metrics`

**Purpose:** Generate Prometheus-format metrics for monitoring

**Usage:**
```bash
docker exec tor-relay metrics
```

**Output Example:**
```prometheus
# HELP tor_relay_uptime_seconds Relay uptime in seconds
# TYPE tor_relay_uptime_seconds gauge
tor_relay_uptime_seconds{relay_name="MyTorRelay"} 214830

# HELP tor_relay_bootstrap_percent Bootstrap completion percentage
# TYPE tor_relay_bootstrap_percent gauge
tor_relay_bootstrap_percent{relay_name="MyTorRelay"} 100

# HELP tor_relay_or_port_reachable ORPort reachability status
# TYPE tor_relay_or_port_reachable gauge
tor_relay_or_port_reachable{relay_name="MyTorRelay",port="9001"} 1

# HELP tor_relay_bandwidth_rate_bytes Configured bandwidth rate
# TYPE tor_relay_bandwidth_rate_bytes gauge
tor_relay_bandwidth_rate_bytes{relay_name="MyTorRelay"} 52428800
```

**Environment Variables:**
- `RELAY_NICKNAME` - Sets the relay name label in metrics (optional)

**Exit Codes:**
- `0` - Metrics generated
- `1` - Error generating metrics

---

### `metrics-http`

**Purpose:** HTTP server for exposing Prometheus metrics

**Usage:**
```bash
# Start metrics HTTP server (runs in background)
metrics-http 9035

# Access metrics endpoint
curl http://localhost:9035/metrics
```

**Environment Variables:**
- `METRICS_PORT` - Port to listen on (default: 9035)

**Endpoints:**
- `GET /metrics` - Prometheus metrics
- `GET /health` - Health check endpoint
- `GET /` - Simple status page

**Exit Codes:**
- `0` - Server running
- `1` - Port already in use or error

**Note:** Automatically started by docker-entrypoint.sh if `ENABLE_METRICS=true`

---

### `dashboard`

**Purpose:** Interactive HTML dashboard with real-time relay status

**Usage:**
```bash
# Generate dashboard HTML
docker exec tor-relay dashboard > dashboard.html

# Or access via HTTP if metrics-http is running
curl http://localhost:9035/dashboard
```

**Features:**
- Real-time bootstrap progress
- Network reachability status
- Performance metrics visualization
- Quick action buttons
- Auto-refresh every 30 seconds

**Environment Variables:** None required

**Browser Access:**
When `metrics-http` is running, access dashboard at:
`http://<server-ip>:9035/dashboard`

---

### `setup`

**Purpose:** Interactive wizard for generating relay configuration

**Usage:**
```bash
docker exec -it tor-relay setup
```

**Interactive Prompts:**
1. Relay Nickname
2. Contact Information (email)
3. ORPort (default: 9001)
4. DirPort (default: 9030)
5. Bandwidth Rate (MB/s)
6. Bandwidth Burst (MB/s)
7. IPv6 support (yes/no)
8. Exit policy (guard/middle only)

**Output:** Generates `/etc/tor/torrc` or outputs to stdout

**Environment Variables:**
- `TOR_CONFIG` - Config file path (default: /etc/tor/torrc)
- All standard Tor environment variables

**Exit Codes:**
- `0` - Configuration created successfully
- `1` - Invalid input or error

---

### `net-check`

**Purpose:** Comprehensive network diagnostics for relay troubleshooting

**Usage:**
```bash
docker exec tor-relay net-check
```

**Output Example:**
```
🌐 Network Diagnostics Report
════════════════════════════════════

✅ IPv4 Connectivity: OK (203.0.113.42)
✅ IPv6 Connectivity: OK (2001:db8::1)
✅ DNS Resolution: OK
✅ Tor Consensus: Reachable
✅ ORPort 9001: OPEN
✅ DirPort 9030: OPEN

🔍 Diagnostic Details:
   • Public IPv4: 203.0.113.42
   • Public IPv6: 2001:db8::1
   • DNS Resolver: 1.1.1.1
   • Tor Authority: 128.31.0.34:9131 (reachable)
```

**Checks Performed:**
- IPv4 connectivity and public IP detection
- IPv6 connectivity and public IP detection (if enabled)
- DNS resolution (multiple resolvers)
- Tor directory authority connectivity
- ORPort reachability (internal and external)
- DirPort reachability (internal and external)

**Environment Variables:** None required

**Exit Codes:**
- `0` - All checks passed
- `1` - One or more checks failed

---

### `view-logs`

**Purpose:** Stream Tor relay logs with optional filtering

**Usage:**
```bash
# View last 50 lines
docker exec tor-relay view-logs

# Follow logs in real-time
docker exec tor-relay view-logs -f

# Filter for errors only
docker exec tor-relay view-logs --errors

# Filter for warnings and errors
docker exec tor-relay view-logs --warn
```

**Options:**
- `-f, --follow` - Follow log output (like tail -f)
- `-n <lines>` - Show last N lines (default: 50)
- `--errors` - Show only ERROR level messages
- `--warn` - Show WARNING and ERROR messages
- `--bootstrap` - Show only bootstrap-related messages

**Environment Variables:**
- `TOR_LOG_DIR` - Log directory path (default: /var/log/tor)

**Exit Codes:**
- `0` - Logs displayed successfully
- `1` - Log file not found or error

---

## 🚀 Common Workflows

### 1. Quick Health Check
```bash
# Simple status check
docker exec tor-relay status

# JSON health check for automation
docker exec tor-relay health | jq .status
```

### 2. Setup Prometheus Monitoring
```bash
# Start metrics HTTP server
docker exec tor-relay metrics-http 9035 &

# Configure Prometheus to scrape:
# http://<relay-ip>:9035/metrics
```

### 3. Troubleshoot Network Issues
```bash
# Run comprehensive network diagnostics
docker exec tor-relay net-check

# Check relay fingerprint and Metrics link
docker exec tor-relay fingerprint

# View recent errors
docker exec tor-relay view-logs --errors | tail -20
```

### 4. Monitor Bootstrap Progress
```bash
# Watch bootstrap in real-time
watch -n 5 'docker exec tor-relay health | jq .bootstrap'

# Or use status tool
docker exec tor-relay status | grep Bootstrap
```

### 5. Generate Configuration
```bash
# Interactive setup
docker exec -it tor-relay setup

# Or use environment variables
docker run -e RELAY_NICKNAME=MyRelay \
  -e RELAY_CONTACT=admin@example.com \
  ghcr.io/r3bo0tbx1/onion-relay:latest
```

---

## 🔐 Security Notes

- All tools run as non-root `tor` user
- No tools write to disk (except setup when instructed)
- Metrics expose no sensitive data
- Dashboard can be password-protected via reverse proxy
- Logs contain no sensitive user data (Tor privacy design)

---

## 🐛 Troubleshooting

### Tool not found
```bash
# Verify tool exists and is executable
docker exec tor-relay ls -la /usr/local/bin/

# Check PATH
docker exec tor-relay echo $PATH
```

### Permission denied
```bash
# Should not happen - tools auto-fixed by entrypoint
# If it does, check Dockerfile COPY command

# Manual fix (shouldn't be needed):
docker exec -u root tor-relay chmod +x /usr/local/bin/*
```

### Empty or error output
```bash
# Check if Tor is running
docker exec tor-relay pgrep tor

# Check logs for errors
docker exec tor-relay view-logs --errors

# Restart container
docker restart tor-relay
```

### Metrics HTTP server fails to start
```bash
# Check if port is in use
docker exec tor-relay netstat -tulpn | grep 9035

# Try different port
docker exec tor-relay metrics-http 9036
```

---

## 📚 Related Documentation

- [Deployment Guide](./DEPLOYMENT.md) - Installation and configuration
- [Monitoring Guide](./MONITORING.md) - Prometheus and Grafana setup
- [Backup Guide](./BACKUP.md) - Data persistence and recovery
- [Performance Guide](./PERFORMANCE.md) - Optimization tips

---

## 💡 Tips

1. **Automation**: Use `health` tool's JSON output for monitoring scripts
2. **Monitoring**: Always enable `metrics-http` for production relays
3. **Diagnostics**: Run `net-check` after any network configuration changes
4. **Logs**: Use `view-logs --follow` during initial bootstrap
5. **Dashboard**: Useful for at-a-glance status without CLI

---

**Last Updated:** November 2025 | **Version:** 1.1