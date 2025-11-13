# Migration Guide: v1.1.0 → v1.1.1

This guide documents **two successful real-world migration paths** validated in production:
1. **Guard/Middle Relay** (mounted torrc) - Zero issues
2. **Bridge from Official Image** (thetorproject/obfs4-bridge) - Requires ownership fix

---

## 📋 What's New in v1.1.1

### Security Fixes
- ✅ **Fixed**: Command injection via OBFS4V_* environment variables (CWE-78, CWE-94)
- ✅ **Fixed**: Health check failure on ENV-based deployments (CWE-703)
- ✅ **Fixed**: Privilege escalation attempt with silent failure (CWE-250)
- ✅ **Fixed**: Inadequate input validation (CWE-20)
- ✅ **Fixed**: Workflow permission over-granting (CWE-269)
- ✅ **Fixed**: Temporary file race condition (CWE-377)
- ✅ **Fixed**: TOR_CONTACT_INFO validation false positives

### Improvements
- ✅ Smart healthcheck script works with both mounted and ENV configs
- ✅ Comprehensive input validation with whitespace trimming
- ✅ Better error messages and debugging
- ✅ Removed non-functional chown attempt
- ✅ Cleaned up bridge configuration (removed redundant ExitPolicy)

### Breaking Changes
**None** - All changes are backward compatible!

---

## ✅ Migration Path 1: Guard/Middle Relay (Mounted Config)

**Difficulty**: Easy
**Downtime**: < 2 minutes
**Fingerprint Preserved**: Yes ✅
**Volume Changes Required**: None

### Prerequisites

```bash
# Verify you're using a mounted torrc file
docker inspect <container> --format='{{range .Mounts}}{{if eq .Destination "/etc/tor/torrc"}}MOUNTED{{end}}{{end}}'
# Should output: MOUNTED
```

### Step 1: Backup

```bash
# Stop container
docker stop <container>

# Backup volumes
docker run --rm \
  -v tor-guard-data:/data \
  -v /tmp:/backup \
  alpine:3.22.2 tar czf /backup/tor-guard-data-backup-$(date +%Y%m%d).tar.gz /data

docker run --rm \
  -v tor-guard-logs:/data \
  -v /tmp:/backup \
  alpine:3.22.2 tar czf /backup/tor-guard-logs-backup-$(date +%Y%m%d).tar.gz /data

# Save fingerprint
docker run --rm -v tor-guard-data:/data alpine:3.22.2 cat /data/fingerprint > /tmp/fingerprint-backup.txt
```

### Step 2: Update Configuration

**Cosmos JSON changes**:
```json
{
  "image": "r3bo0tbx1/onion-relay:1.1.1",  // ← Update from :latest or :1.1.0
  "cap_add": [
    "NET_BIND_SERVICE"  // ← Removed unnecessary CHOWN, SETUID, SETGID, DAC_OVERRIDE
  ],
  "labels": {
    "cosmos-version": "1.1.1"  // ← Update version
  }
}
```

### Step 3: Remove Old Container

```bash
docker rm <container>
```

### Step 4: Deploy Updated Container

- Import updated JSON in Cosmos UI
- Or redeploy with `docker-compose up -d`

### Step 5: Verify

```bash
# Check logs
docker logs -f <container>
# Expected: ✅ Using mounted configuration: /etc/tor/torrc

# Verify fingerprint matches
docker exec <container> fingerprint
cat /tmp/fingerprint-backup.txt
# Must match!

# Run diagnostics
docker exec <container> status
docker exec <container> health | jq .
```

### ✅ Success Criteria

- [ ] Container starts successfully
- [ ] Logs show "Using mounted configuration"
- [ ] Fingerprint matches backup
- [ ] Bootstrap reaches 100%
- [ ] Relay is reachable

---

## ⚠️ Migration Path 2: Bridge from Official Image

**Difficulty**: Moderate
**Downtime**: 5-10 minutes
**Fingerprint Preserved**: Yes ✅ (after fix)
**Volume Changes Required**: Yes - UID ownership fix

### The Challenge

**UID Mismatch**:
- Official `thetorproject/obfs4-bridge` (Debian): UID **101**
- `r3bo0tbx1/onion-relay` (Alpine): UID **100**

**Symptom**: `Permission denied` errors if not fixed.

### Prerequisites

```bash
# Verify current image
docker inspect <container> --format='{{.Config.Image}}'
# Should show: thetorproject/obfs4-bridge or similar

# Check ENV variables
docker inspect <container> --format='{{range .Config.Env}}{{println .}}{{end}}' | grep -E "OR_PORT|PT_PORT|EMAIL|NICKNAME"
```

### Recommended Approach: Use Mounted Config

**Why?**
- ✅ More reliable than ENV variables
- ✅ Bypasses validation complexity
- ✅ Same as guard relay (consistent approach)
- ✅ Easier to troubleshoot

### Step 1: Backup Everything

```bash
# Stop container
docker stop obfs4-bridge

# Backup volume (CRITICAL!)
docker run --rm \
  -v obfs4-data:/data \
  -v /tmp:/backup \
  alpine:3.22.2 tar czf /backup/obfs4-data-backup-$(date +%Y%m%d).tar.gz /data

# Verify backup
ls -lh /tmp/obfs4-data-backup-*.tar.gz

# Save fingerprint
docker run --rm -v obfs4-data:/data alpine:3.22.2 cat /data/fingerprint > /tmp/bridge-fingerprint-backup.txt
cat /tmp/bridge-fingerprint-backup.txt
```

### Step 2: Fix Volume Ownership (CRITICAL!)

```bash
# Check current ownership (should be 101:101)
docker run --rm -v obfs4-data:/data alpine:3.22.2 ls -ldn /data
# Output: drwx------ ... 101 101 ...

# Fix ownership: 101 → 100
docker run --rm -v obfs4-data:/data alpine:3.22.2 chown -R 100:101 /data

# Verify fix
docker run --rm -v obfs4-data:/data alpine:3.22.2 ls -ldn /data
# Output: drwx------ ... 100 101 ...  ← MUST show 100!

# Verify key files are readable
docker run --rm -v obfs4-data:/data alpine:3.22.2 ls -la /data/keys/
# Should show files owned by 100:101
```

### Step 3: Create Bridge Config File

```bash
# Create config directory
sudo mkdir -p /home/$(whoami)/onion

# Create bridge.conf
sudo tee /home/$(whoami)/onion/bridge.conf > /dev/null << 'EOF'
# Tor obfs4 Bridge Configuration
Nickname MyObfs4Bridge
ContactInfo admin@email.org

# Network configuration
ORPort 9001
SocksPort 0

# Data directories
DataDirectory /var/lib/tor
Log notice file /var/log/tor/notices.log

# Bridge relay configuration
BridgeRelay 1
PublishServerDescriptor bridge

# obfs4 pluggable transport
ServerTransportPlugin obfs4 exec /usr/bin/lyrebird
ServerTransportListenAddr obfs4 0.0.0.0:9005
ExtORPort auto

# Additional options
MaxMemInQueues 1024 MB
AddressDisableIPv6 0
EOF

# Customize with your values
sudo nano /home/$(whoami)/onion/bridge.conf
```

### Step 4: Remove Old Container

```bash
docker rm obfs4-bridge
```

### Step 5: Deploy with Mounted Config

**Cosmos JSON**:
```json
{
  "minVersion": "0.8.0",
  "services": {
    "obfs4-bridge": {
      "image": "r3bo0tbx1/onion-relay:1.1.1",
      "container_name": "obfs4-bridge",
      "restart": "unless-stopped",
      "network_mode": "host",
      "environment": [
        "TZ=UTC"
      ],
      "volumes": [
        {
          "type": "volume",
          "source": "obfs4-data",
          "target": "/var/lib/tor"
        },
        {
          "type": "bind",
          "source": "/home/youruser/onion/bridge.conf",
          "target": "/etc/tor/torrc",
          "read_only": true
        }
      ],
      "security_opt": [
        "no-new-privileges:true"
      ],
      "labels": {
        "cosmos-stack": "TorBridge",
        "cosmos-stack-main": "obfs4-bridge",
        "cosmos-description": "🌉 Hardened obfs4 Bridge v1.1.1",
        "cosmos-icon": "https://iili.io/KsXP2Y7.png",
        "cosmos-auto-update": "true",
        "cosmos-auto-update-type": "registry",
        "cosmos-force-network-secured": "false",
        "cosmos-version": "1.1.1"
      }
    }
  },
  "volumes": {
    "obfs4-data": {}
  }
}
```

**Key changes**:
- ✅ Removed ALL ENV variables
- ✅ Added mounted bridge.conf
- ✅ Updated image to 1.1.1

### Step 6: Deploy and Verify

```bash
# Import JSON in Cosmos UI and start

# Check logs
docker logs -f obfs4-bridge
# Expected:
# ✅ Using mounted configuration: /etc/tor/torrc
# ✅ Configuration is valid
# 🚀 Tor relay started

# Wait 30 seconds, then verify fingerprint
docker exec obfs4-bridge fingerprint
cat /tmp/bridge-fingerprint-backup.txt
# MUST MATCH!

# Check configuration
docker exec obfs4-bridge cat /etc/tor/torrc
# Should show BridgeRelay 1, obfs4 config, etc.

# Run health check
docker exec obfs4-bridge health | jq .

# Run full status
docker exec obfs4-bridge status
```

### Step 7: Get Bridge Line (After 24-48 Hours)

```bash
# Bridge line appears after Tor publishes to BridgeDB
docker exec obfs4-bridge bridge-line
```

### ✅ Success Criteria

- [ ] Container starts successfully
- [ ] Logs show "Using mounted configuration"
- [ ] Fingerprint matches backup (CRITICAL!)
- [ ] Bootstrap reaches 100%
- [ ] Bridge line available after 24-48 hours

---

## 🚨 Troubleshooting

### Issue 1: "Permission denied" on startup

**Symptom**:
```
Directory /var/lib/tor cannot be read: Permission denied
```

**Cause**: Volume ownership not fixed (still UID 101)

**Fix**:
```bash
docker stop obfs4-bridge
docker run --rm -v obfs4-data:/data alpine:3.22.2 chown -R 100:101 /data
docker start obfs4-bridge
```

### Issue 2: Different fingerprint after migration

**Symptom**: Fingerprint changed, new bridge identity

**Cause**: Bridge keys not preserved

**Fix**: Restore from backup:
```bash
docker stop obfs4-bridge
docker run --rm -v obfs4-data:/data -v /tmp:/backup alpine:3.22.2 \
  sh -c 'rm -rf /data/* && tar xzf /backup/obfs4-data-backup-*.tar.gz -C / && chown -R 100:101 /data'
docker start obfs4-bridge
```

### Issue 3: "TOR_CONTACT_INFO contains invalid characters"

**Symptom**: Container in restart loop with validation error

**Cause**: Fixed in v1.1.1 - validation was too strict

**Solution**: Use mounted config instead of ENV variables (see Step 3-5 above)

### Issue 4: Container restart loop (general)

**Debug**:
```bash
# Check logs
docker logs obfs4-bridge --tail 50

# Check if it's actually using new image
docker inspect obfs4-bridge --format='{{.Image}}'
docker images r3bo0tbx1/onion-relay:1.1.1 --format='{{.ID}}'
# IDs must match!

# If IDs don't match: remove and recreate container
docker stop obfs4-bridge
docker rm obfs4-bridge
# Then redeploy
```

### Issue 5: Health check failing

**Symptom**: Container marked unhealthy

**Cause**: Old health check used hardcoded path

**Fix**: v1.1.1 includes smart healthcheck.sh that works with both mounted and ENV configs. Just update to 1.1.1 image.

---

## 📊 Comparison: ENV vs Mounted Config

| Aspect | ENV Variables | Mounted Config |
|--------|---------------|----------------|
| **Complexity** | Medium | Simple |
| **Validation** | Strict (can cause issues) | Minimal (tor validates) |
| **Debugging** | Harder | Easier (just cat file) |
| **Updates** | Restart container | Edit file + restart |
| **Recommended** | No ⚠️ | **Yes** ✅ |
| **Use Case** | Quick testing | Production |

**Recommendation**: Always use mounted config for production deployments.

---

## 🎯 Pre-Migration Checklist

### For All Migrations
- [ ] Current fingerprint saved to file
- [ ] Volumes backed up with timestamps
- [ ] Old container can be removed (stopped first)
- [ ] Firewall rules documented
- [ ] Testing plan prepared

### For Bridge from Official Image
- [ ] Volume ownership fix command prepared
- [ ] bridge.conf file created and customized
- [ ] Backup includes pt_state/obfs4_state.json
- [ ] Expected fingerprint documented

### Post-Migration
- [ ] Fingerprint matches backup
- [ ] Container starts without errors
- [ ] Bootstrap reaches 100%
- [ ] Diagnostic tools work (status, health, fingerprint)
- [ ] Monitoring updated (if applicable)

---

## 📚 Additional Resources

- **Security Audit Report**: `SECURITY-AUDIT-REPORT.md`
- **General Migration Guide**: `MIGRATION.md`
- **Troubleshooting**: `docs/TROUBLESHOOTING-BRIDGE-MIGRATION.md`
- **Tools Documentation**: `docs/TOOLS.md`
- **Deployment Guide**: `docs/DEPLOYMENT.md`

---

## 🔒 Security Notes

### What's Fixed in v1.1.1

1. **Command Injection** (CRITICAL): OBFS4V_* variables now validated with whitelist
2. **Health Check** (CRITICAL): Works with both mounted and ENV configs
3. **Input Validation** (CRITICAL): Comprehensive validation with whitespace trimming
4. **Permissions** (HIGH): Removed non-functional chown attempt
5. **Contact Info Validation** (HIGH): Fixed false positives

### Risk Assessment

**Before Migration**: MEDIUM (using v1.1.0 with known vulnerabilities)
**After Migration**: LOW (all critical vulnerabilities patched)

**Recommendation**: Migrate as soon as possible to address security fixes.

---

*Last Updated: 2025-11-13*
*Validated with production deployments*
