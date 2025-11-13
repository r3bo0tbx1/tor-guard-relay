# 🛠️ Tools Reference Guide

**Tor Guard Relay v1.1.1** includes 4 essential diagnostic tools built directly into the ultra-optimized ~20 MB container. All tools are busybox-compatible, executable without file extensions, and designed for production use.

---

## 📋 Tool Overview

| Tool | Purpose | Output Format | Notes |
|------|---------|---------------|-------|
| **status** | Complete relay health report | Text (emoji) | Full diagnostic dashboard |
| **health** | JSON health diagnostics | JSON | Machine-readable for monitoring |
| **fingerprint** | Display relay fingerprint | Text | With Tor Metrics link |
| **bridge-line** | Get obfs4 bridge line | Text | Bridge mode only |

---

## 🔧 Tool Details

### `status`

**Purpose:** Comprehensive relay health and status report with emoji formatting

**Usage:**
```bash
docker exec tor-relay status
```

**Output Example:**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🧅 Tor Relay Status
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🚀 Status:      RUNNING (PID: 123)
✅ Bootstrap:   100% COMPLETE
🌐 ORPort:      REACHABLE
🪪 Nickname:    MyGuardRelay
🔑 Fingerprint: ABCD1234...WXYZ9876
✅ Errors:      0
⏱️  Uptime:      2d 14h 30m

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
💡 Tip: Use 'docker logs -f <container>' for live logs
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

**Exit Codes:**
- `0` - Status retrieved successfully
- `1` - Tor service not running or error

---

### `health`

**Purpose:** Machine-readable JSON health check for monitoring systems and automation

**Usage:**
```bash
docker exec tor-relay health

# Parse with jq
docker exec tor-relay health | jq .status
```

**Output Example:**
```json
{
  "status": "up",
  "pid": 123,
  "uptime": "2d 14h 30m",
  "bootstrap": 100,
  "reachable": "true",
  "errors": 0,
  "nickname": "MyGuardRelay",
  "fingerprint": "ABCD1234567890ABCDEF1234567890ABCDEFGHIJ"
}
```

**Status Values:**
- `up` - Relay is running and healthy
- `down` - Relay is not running
- `error` - Critical issues detected

**Exit Codes:**
- `0` - Health check completed
- `1` - Critical error or Tor not running

**Integration Example:**
```bash
#!/bin/bash
# Simple health monitoring script
HEALTH=$(docker exec tor-relay health)
STATUS=$(echo "$HEALTH" | jq -r '.status')

if [ "$STATUS" != "up" ]; then
  echo "ALERT: Relay is $STATUS"
  # Send notification
fi
```

---

### `fingerprint`

**Purpose:** Display relay fingerprint with direct links to Tor Metrics

**Usage:**
```bash
docker exec tor-relay fingerprint
```

**Output Example:**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔑 Relay Fingerprint
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🪪 Nickname:    MyTorRelay
🔑 Fingerprint: ABCD 1234 5678 90AB CDEF 1234 5678 90AB CDEF 1234

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🔗 Tor Metrics: https://metrics.torproject.org/rs.html#details/ABCD...

💡 Your relay will appear in Tor Metrics after 1-2 hours
```

**Exit Codes:**
- `0` - Fingerprint retrieved
- `1` - Fingerprint not yet available (still bootstrapping)

**When Available:**
- Guard/Middle relays: ~1-2 hours after first start
- Exit relays: ~1-2 hours after first start
- Bridges: Not published publicly (by design)

---

### `bridge-line`

**Purpose:** Get the obfs4 bridge line for sharing with users (bridge mode only)

**Usage:**
```bash
docker exec tor-bridge bridge-line
```

**Output Example:**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🌉 obfs4 Bridge Line
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Bridge obfs4 203.0.113.42:9002 ABCD...WXYZ cert=abc123...xyz789 iat-mode=0

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📋 Sharing Guidelines:
   • Only share with people you trust
   • Do NOT publish publicly
   • Helps users in censored countries

💡 Bridge line available 24-48 hours after first start
```

**Exit Codes:**
- `0` - Bridge line retrieved
- `1` - Bridge line not yet available or not in bridge mode

**When Available:**
- Bridges take 24-48 hours after first start to generate the bridge line
- The bridge line is stored in `/var/lib/tor/pt_state/obfs4_bridgeline.txt`
- Also visible in logs: `docker logs <container> | grep "bridge line"`

**Important:**
- Only works in bridge mode (`TOR_RELAY_MODE=bridge`)
- Requires persistent volumes for `/var/lib/tor`
- Bridge addresses are NOT published in public directories

---

## 🚀 Common Workflows

### 1. Quick Health Check
```bash
# Visual status check
docker exec tor-relay status

# JSON health check for automation
docker exec tor-relay health | jq .status

# Check bootstrap progress
docker exec tor-relay health | jq .bootstrap
```

### 2. Find Your Relay on Tor Metrics
```bash
# Get fingerprint and metrics link
docker exec tor-relay fingerprint

# Wait 1-2 hours after first start
# Click the Tor Metrics link or search manually
```

### 3. Share Your Bridge
```bash
# Get bridge line (bridge mode only)
docker exec tor-bridge bridge-line

# Wait 24-48 hours after first start
# Share ONLY with trusted users, NOT publicly
```

### 4. Automated Monitoring
```bash
# Simple monitoring script
while true; do
  STATUS=$(docker exec tor-relay health | jq -r '.status')
  BOOTSTRAP=$(docker exec tor-relay health | jq -r '.bootstrap')

  echo "[$(date)] Status: $STATUS | Bootstrap: $BOOTSTRAP%"

  if [ "$STATUS" != "up" ]; then
    # Send alert
    echo "ALERT: Relay is down!"
  fi

  sleep 60
done
```

### 5. Check Logs
```bash
# View recent logs
docker logs --tail 100 tor-relay

# Follow logs in real-time
docker logs -f tor-relay

# Filter for errors
docker logs tor-relay 2>&1 | grep -i error

# Filter for warnings
docker logs tor-relay 2>&1 | grep -i warn
```

---

## 🔐 Security Notes

- All tools run as non-root `tor` user
- Tools are read-only and don't modify relay state
- No sensitive data exposed (fingerprints are public by design)
- Bridge lines should be shared privately, not published
- Logs contain no user traffic data (Tor privacy design)

---

## 🐛 Troubleshooting

### Tool not found
```bash
# Verify tools exist
docker exec tor-relay ls -la /usr/local/bin/

# Should show: status, health, fingerprint, bridge-line

# Check PATH
docker exec tor-relay echo $PATH
```

### Permission denied
```bash
# Should not happen - tools are set to +x in Dockerfile
# If it does, rebuild image:
docker build --no-cache -t tor-relay:latest .
```

### Empty output or errors
```bash
# Check if Tor is running
docker exec tor-relay ps aux | grep tor

# Check logs for errors
docker logs tor-relay | tail -50

# Restart container
docker restart tor-relay
```

### Fingerprint not available
```bash
# Normal during bootstrap (first 5-15 minutes)
# Check bootstrap progress
docker exec tor-relay health | jq .bootstrap

# Wait for 100% bootstrap
docker logs tor-relay | grep "Bootstrapped 100%"
```

### Bridge line not available
```bash
# Normal for first 24-48 hours
# Check if in bridge mode
docker exec tor-relay grep BridgeRelay /etc/tor/torrc

# Check for obfs4 files
docker exec tor-relay ls -la /var/lib/tor/pt_state/

# Check logs
docker logs tor-relay | grep -i obfs4
```

---

## 💡 Tips & Best Practices

1. **Use `health` for automation** - JSON output is perfect for scripts and monitoring systems

2. **Check `status` during troubleshooting** - Human-readable format with emoji makes issues obvious

3. **Save your fingerprint** - Store it somewhere safe for relay tracking

4. **Monitor bootstrap** - New relays take 5-15 minutes to fully bootstrap

5. **Be patient with bridges** - Bridge lines take 24-48 hours to generate

6. **Use docker logs** - Built-in logging is comprehensive and easier than installing extra tools

7. **Keep it simple** - This minimal toolset covers 99% of relay operation needs

---

## 📚 Related Documentation

- [Deployment Guide](./DEPLOYMENT.md) - Installation and configuration
- [Multi-Mode Guide](./MULTI-MODE.md) - Guard, Exit, and Bridge modes
- [Backup Guide](./BACKUP.md) - Data persistence and recovery
- [Performance Guide](./PERFORMANCE.md) - Optimization tips

---

## ❓ FAQ

**Q: Why only 4 tools instead of 9?**
A: The v1.1.1 build prioritizes size optimization (~20 MB vs 45+ MB). These 4 tools cover all essential operations. For advanced monitoring, use external tools like Prometheus.

**Q: Where are metrics/monitoring endpoints?**
A: Removed to achieve ultra-small image size. Use `health` tool with external monitoring systems or check `/var/log/tor/notices.log` directly.

**Q: Can I still use Prometheus?**
A: Yes! Export logs or use `health` JSON output with a Prometheus exporter. See [MONITORING.md](./MONITORING.md) for alternatives.

**Q: What happened to the dashboard?**
A: Removed (required Python/Flask). Use `status` tool for visual output or build your own dashboard using `health` JSON.

---

**Last Updated:** November 2025 | **Version:** 1.1.1