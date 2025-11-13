# ⚡ Performance Tuning & Optimization - Tor Guard Relay

Complete guide to optimizing CPU, memory, bandwidth, and network performance for your Tor relay.

---

## Table of Contents

- [Performance Baseline](#performance-baseline)
- [CPU Optimization](#cpu-optimization)
- [Memory Management](#memory-management)
- [Bandwidth Optimization](#bandwidth-optimization)
- [Network Tuning](#network-tuning)
- [Monitoring & Metrics](#monitoring--metrics)
- [Benchmarking](#benchmarking)
- [Troubleshooting](#troubleshooting)

---

## Performance Baseline

### System Requirements by Relay Tier

| Tier | CPU | RAM | Bandwidth | Use Case |
|------|-----|-----|-----------|----------|
| **Entry** | 1 core | 512 MB | 10–50 Mbps | Home lab, testing |
| **Standard** | 2 cores | 1–2 GB | 50–500 Mbps | Production guard relay |
| **High-Capacity** | 4+ cores | 4+ GB | 500+ Mbps | High-traffic relay |
| **Enterprise** | 8+ cores | 8+ GB | 1 Gbps+ | Multiple relays |

### Expected Resource Usage (Steady State)

| Resource | Entry | Standard | High-Cap | Notes |
|----------|-------|----------|----------|-------|
| CPU | 5–15% | 10–25% | 20–40% | Varies by traffic |
| Memory | 80–150 MB | 200–400 MB | 500+ MB | Increases with connections |
| Bandwidth | 5–50 Mbps | 50–500 Mbps | 500+ Mbps | Depends on limits |
| Disk I/O | Light | Moderate | Heavy | Monitor during bootstrap |

---

## CPU Optimization

### 1. Allocate CPU Cores

By default, Tor uses all available cores. Restrict or optimize as needed.

#### Check Current Allocation

```bash
# View Tor config
docker exec guard-relay grep -i numcpus /etc/tor/torrc

# View system CPUs
docker exec guard-relay nproc
```

#### Configure CPU Cores in relay.conf

```conf
# Use specific number of cores (example: 4 cores)
NumCPUs 4

# Or auto-detect (default, recommended)
NumCPUs 0
```

#### For Docker Compose

```yaml
services:
  tor-guard-relay:
    # ... other config
    deploy:
      resources:
        limits:
          cpus: '4.0'  # Limit to 4 cores
        reservations:
          cpus: '2.0'  # Reserve 2 cores minimum
```

### 2. CPU Prioritization

Ensure Tor gets fair CPU scheduling.

```bash
# View current CPU usage
docker stats guard-relay --no-stream

# Show detailed CPU metrics
docker exec guard-relay ps aux | grep tor
```

### 3. Disable Unnecessary Features

```conf
# Disable directory service (if not needed)
# DirPort 0

# Keep SOCKS disabled (we're a relay, not a client)
SocksPort 0

# Disable bridge operation (if running guard relay)
BridgeRelay 0
```

### 4. Optimize Connection Handling

```conf
# Maximum simultaneous connections
# Default usually fine, but can tune:
# MaxClientCircuitsPending 100

# Connection timeout (default 15 minutes)
# CircuitIdleTimeout 900
```

---

## Memory Management

### 1. Monitor Memory Usage

```bash
# Real-time memory monitoring
docker stats guard-relay

# View memory trends over 1 hour
watch -n 60 'docker exec guard-relay ps aux | grep tor | grep -v grep'

# Historical memory usage
docker exec guard-relay cat /proc/meminfo
```

### 2. Set Memory Limits in Docker Compose

```yaml
services:
  tor-guard-relay:
    deploy:
      resources:
        limits:
          memory: 2G        # Hard limit
        reservations:
          memory: 1G        # Guaranteed allocation
```

### 3. Configure Tor Memory Settings

```conf
# MaxMemInQueues - Maximum total memory for circuit queues
# Default: 512 MB (usually fine)
MaxMemInQueues 512 MB

# When memory hits threshold, new circuits rejected
# Prevents OOM (out of memory) crashes
```

### 4. Handle Memory Leaks

**Monitor for gradual increase:**

```bash
#!/bin/bash
# Save as: /usr/local/bin/monitor-memory-growth.sh

CONTAINER="guard-relay"
INTERVAL=300  # 5 minutes

while true; do
  MEMORY=$(docker exec "$CONTAINER" ps aux | \
    grep '[t]or ' | awk '{print $6}' | head -1)
  
  echo "$(date): Memory = ${MEMORY}KB"
  sleep $INTERVAL
done
```

Run and observe for 24 hours:

```bash
/usr/local/bin/monitor-memory-growth.sh | tee /tmp/memory-log.txt

# Analyze growth rate
tail -20 /tmp/memory-log.txt
```

---

## Bandwidth Optimization

### 1. Understand Bandwidth Limits

```conf
# Average bandwidth (sustained rate)
RelayBandwidthRate 100 MBytes

# Burst bandwidth (temporary spikes)
RelayBandwidthBurst 200 MBytes
```

### 2. Set Realistic Limits

**Calculate your limits based on ISP:**

```
Available Bandwidth: 1000 Mbps (ISP plan)
Usable for Tor: 50% (leave headroom for other services)
= 500 Mbps

Convert to MBytes/s: 500 Mbps ÷ 8 = 62.5 MBytes/s

Recommended:
- RelayBandwidthRate 50 MBytes
- RelayBandwidthBurst 100 MBytes
```

### 3. Bandwidth Accounting

**Limit total monthly traffic:**

```conf
# Monthly accounting window
# Starts on the 1st at UTC midnight
AccountingStart month 1 00:00

# Maximum data (upload + download combined)
AccountingMax 1000 GB
```

### 4. Monitor Actual Bandwidth Usage

```bash
# Real-time bandwidth stats
docker exec guard-relay tail -f /var/log/tor/notices.log | grep "bandwidth"

# Historical bandwidth usage
docker exec guard-relay grep "bandwidth" /var/log/tor/notices.log | tail -20
```

### 5. Optimize for Your Network

#### For Home Networks

```conf
# Conservative settings for residential connections
RelayBandwidthRate 10 MBytes
RelayBandwidthBurst 20 MBytes
```

#### For VPS with Unmetered Bandwidth

```conf
# Maximize contribution
RelayBandwidthRate 500 MBytes
RelayBandwidthBurst 1000 MBytes
```

#### For Datacenters with Traffic Shaping

```conf
# Match provider limits
RelayBandwidthRate 100 MBytes  # ISP limit
RelayBandwidthBurst 150 MBytes
```

---

## Network Tuning

### 1. Enable IPv6 (if available)

**In relay.conf:**

```conf
# Dual-stack support
ORPort 9001
ORPort [::]:9001

# Directory port for IPv6
DirPort 9030
```

**Verify IPv6 is working:**

```bash
docker exec guard-relay curl -6 -s https://icanhazip.com
# Should return IPv6 address

docker exec guard-relay curl -4 -s https://icanhazip.com
# Should return IPv4 address
```

### 2. Optimize TCP Settings

**On the host system (for Docker host):**

```bash
# Increase TCP connection backlog
sudo sysctl -w net.core.somaxconn=65535

# Increase listen queue length
sudo sysctl -w net.ipv4.tcp_max_syn_backlog=65535

# Enable TCP keepalives
sudo sysctl -w net.ipv4.tcp_keepalives_intvl=60

# Make permanent
echo "net.core.somaxconn=65535" | sudo tee -a /etc/sysctl.conf
echo "net.ipv4.tcp_max_syn_backlog=65535" | sudo tee -a /etc/sysctl.conf
```

### 3. Firewall Optimization

**Ensure firewall rules don't throttle traffic:**

```bash
# UFW example
sudo ufw status

# High performance rules
sudo iptables -I INPUT -p tcp --dport 9001 -j ACCEPT

# Save rules
sudo iptables-save > /etc/iptables/rules.v4
```

### 4. DNS Performance

**Configure Tor to use fast DNS:**

```conf
# Use Google DNS (example)
ServerDNSListenAddress 127.0.0.1:53
ServerDNSResolvConfFile /etc/resolv.conf
```

Verify DNS resolution is fast:

```bash
# Test DNS response time
time docker exec guard-relay tor --resolve example.com
```

---

## Monitoring & Metrics

v1.1.1 uses **external monitoring** with the `health` JSON API for minimal image size and maximum security.

### 1. JSON Health API

Get relay metrics via the `health` tool:

```bash
# Get full health status (raw JSON)
docker exec guard-relay health

# Parse with jq (requires jq on host)
docker exec guard-relay health | jq .

# Check specific metrics
docker exec guard-relay health | jq .bootstrap      # Bootstrap percentage
docker exec guard-relay health | jq .reachable      # ORPort reachability
docker exec guard-relay health | jq .uptime_seconds # Uptime
```

**Example JSON output:**
```json
{
  "status": "up",
  "bootstrap": 100,
  "reachable": true,
  "fingerprint": "1234567890ABCDEF...",
  "nickname": "MyRelay",
  "uptime_seconds": 86400
}
```

### 2. Prometheus Integration (External)

Use the `health` tool with Prometheus node_exporter textfile collector:

**Create metrics exporter script:**

```bash
#!/bin/bash
# /usr/local/bin/tor-metrics-exporter.sh
# Requires: jq on host (apt install jq / brew install jq)

HEALTH=$(docker exec guard-relay health)

echo "$HEALTH" | jq -r '
  "tor_bootstrap_percent \(.bootstrap)",
  "tor_reachable \(if .reachable then 1 else 0 end)",
  "tor_uptime_seconds \(.uptime_seconds // 0)"
' > /var/lib/node_exporter/textfile_collector/tor.prom
```

**Run via cron every 5 minutes:**
```bash
chmod +x /usr/local/bin/tor-metrics-exporter.sh
crontab -e
*/5 * * * * /usr/local/bin/tor-metrics-exporter.sh
```

### 3. Set Up Prometheus Scraping

**prometheus.yml:**

```yaml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'node_exporter'  # Scrapes textfile collector
    static_configs:
      - targets: ['localhost:9035']
    metrics_path: '/metrics'
```

### 4. Create Grafana Dashboard

**Key metrics to track:**

```promql
# Bandwidth rates
rate(tor_relay_bytes_read_total[5m])
rate(tor_relay_bytes_written_total[5m])

# Connection counts
tor_relay_connections

# CPU usage
rate(process_cpu_seconds_total[5m])

# Memory usage
process_resident_memory_bytes / 1024 / 1024
```

---

## Benchmarking

### Baseline Test (New Relay)

Run after initial bootstrap to establish baseline.

```bash
#!/bin/bash
# Save as: /usr/local/bin/benchmark-relay.sh

CONTAINER="guard-relay"
DURATION=300  # 5 minutes

echo "=== Tor Relay Benchmark ==="
echo "Duration: $DURATION seconds"
echo ""

# Capture initial state
MEM_START=$(docker exec $CONTAINER ps aux | grep '[t]or ' | awk '{print $6}')
CPU_START=$(docker exec $CONTAINER ps aux | grep '[t]or ' | awk '{print $3}')

echo "Starting metrics..."
echo "Initial Memory: ${MEM_START}KB"
echo "Initial CPU: ${CPU_START}%"
echo ""

# Run for duration
sleep $DURATION

# Capture final state
MEM_END=$(docker exec $CONTAINER ps aux | grep '[t]or ' | awk '{print $6}')
CPU_END=$(docker exec $CONTAINER ps aux | grep '[t]or ' | awk '{print $3}')

# Bandwidth
BW_READ=$(docker exec $CONTAINER grep "bandwidth" /var/log/tor/notices.log | tail -1)
BW_WRITE=$(docker logs $CONTAINER 2>&1 | grep "bandwidth" | tail -1)

echo "=== Results ==="
echo "Memory Delta: $(( MEM_END - MEM_START ))KB"
echo "CPU Usage: ${CPU_END}%"
echo "Last Bandwidth Report:"
echo "  Read: $BW_READ"
echo "  Write: $BW_WRITE"
echo ""
echo "Timestamp: $(date)"
```

Run benchmark:

```bash
chmod +x /usr/local/bin/benchmark-relay.sh
/usr/local/bin/benchmark-relay.sh
```

### Compare Against Benchmarks

| Metric | Entry | Standard | High-Cap |
|--------|-------|----------|----------|
| **5-min avg CPU** | <15% | 10–25% | 20–40% |
| **5-min avg MEM** | <200 MB | 200–500 MB | 500+ MB |
| **Active Connections** | <100 | 100–500 | 500–2000 |
| **Bootstrap Time** | 10–30 min | 10–30 min | 10–30 min |

---

## Troubleshooting

### High CPU Usage

**Symptoms:** CPU consistently >50%

**Diagnosis:**

```bash
# Check if relay is under heavy load
docker stats guard-relay --no-stream

# View top processes inside container
docker exec guard-relay ps aux --sort=-%cpu

# Check Tor config for tuning issues
docker exec guard-relay grep -E "NumCPUs|MaxClientCircuitsPending" /etc/tor/torrc
```

**Solutions:**

```conf
# Limit CPU cores
NumCPUs 2  # Instead of auto

# Reduce allowed circuits
MaxClientCircuitsPending 50  # Default is usually 100
```

### High Memory Usage

**Symptoms:** Memory >75% of limit, or constantly increasing

**Diagnosis:**

```bash
# Check memory trend
docker exec guard-relay free -h

# Look for memory leak signs in logs
docker logs guard-relay 2>&1 | grep -i "memory\|oom"

# Check MaxMemInQueues setting
docker exec guard-relay grep MaxMemInQueues /etc/tor/torrc
```

**Solutions:**

```conf
# Reduce max in-flight data
MaxMemInQueues 256 MB  # More conservative

# Or increase if system has capacity
MaxMemInQueues 1024 MB  # If you have 8+ GB RAM
```

### Low Bandwidth Usage

**Symptoms:** Bandwidth well below configured limits

**Diagnosis:**

```bash
# Check configured limits
docker exec guard-relay grep "RelayBandwidth" /etc/tor/torrc

# Check actual usage
docker logs guard-relay 2>&1 | grep "Average"

# Verify ORPort is reachable
docker exec guard-relay status | grep "reachable"
# Or use JSON health check
docker exec guard-relay health | jq .reachable
```

**Solutions:**

- Give relay time to build reputation (2–8 weeks for full capacity)
- Increase bandwidth limits if you have capacity
- Check firewall isn't limiting traffic
- Verify network connectivity is stable

### Connection Pool Exhaustion

**Symptoms:** "Too many open files" errors

**Diagnosis:**

```bash
# Check file descriptor usage
docker exec guard-relay cat /proc/sys/fs/file-max
docker exec guard-relay ulimit -n
```

**Solutions:**

```bash
# Increase container file descriptor limit
docker run -d \
  --ulimit nofile=65535:65535 \
  # ... other options
  r3bo0tbx1/onion-relay:latest
```

---

## Best Practices

### ✅ DO

- ✅ **Monitor metrics continuously** - Use Prometheus + Grafana
- ✅ **Start conservative, scale gradually** - Begin with lower bandwidth limits
- ✅ **Test configuration changes** - Benchmark before/after
- ✅ **Keep logs rotating** - Prevent disk fill
- ✅ **Plan for peak load** - Size hardware for bursts, not average
- ✅ **Document your settings** - Know why you tuned each parameter

### ❌ DON'T

- ❌ **Don't max out bandwidth day 1** - New relays need reputation first
- ❌ **Don't ignore resource limits** - OOM kills are hard to debug
- ❌ **Don't tune blindly** - Always measure, then adjust
- ❌ **Don't forget IPv6** - Half the network could be IPv6

---

## Reference

**Key Configuration Parameters:**

```conf
# CPU
NumCPUs 4

# Memory
MaxMemInQueues 512 MB

# Bandwidth
RelayBandwidthRate 100 MBytes
RelayBandwidthBurst 200 MBytes

# Connections
MaxClientCircuitsPending 100

# Network
ORPort 9001
ORPort [::]:9001
DirPort 9030
```

**Quick Performance Checklist:**

- [ ] CPU allocation set appropriately
- [ ] Memory limits configured
- [ ] Bandwidth limits realistic
- [ ] IPv6 enabled (if available)
- [ ] Metrics enabled for monitoring
- [ ] Prometheus scraping configured
- [ ] Alerts set for resource thresholds
- [ ] Baseline benchmarks recorded

---

## Support

- 📖 [Backup Guide](./BACKUP.md)
- 🚀 [Deployment Guide](./DEPLOYMENT.md)
- 🐛 [Report Issues](https://github.com/r3bo0tbx1/tor-guard-relay/issues)
- 💬 [Tor Performance Forum](https://forum.torproject.org/c/relay-operators)