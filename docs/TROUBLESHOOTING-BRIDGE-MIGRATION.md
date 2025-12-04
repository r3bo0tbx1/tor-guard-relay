# Troubleshooting Bridge Migration to >=v1.1.1

This guide addresses the specific issue where migrating from `thetorproject/obfs4-bridge` to `r3bo0tbx1/onion-relay:1.1.1` results in configuration validation failures and changing fingerprints.

## Problem Description

### Symptoms

1. **Container crash loop** with these logs:
   ```
   ✅ Using mounted configuration: /etc/tor/torrc
   🛑 Configuration validation failed!
   🛑 ERROR: Invalid Tor configuration. Set DEBUG=true for details.
   ```

2. **Fingerprints changing on every restart** - CRITICAL issue indicating bridge identity loss:
   ```
   2025-11-12 17:45:45: CD2A0C40DA625C943A2174171D18AFF2849328DC
   2025-11-12 17:50:18: 5895203866064C4270F909BE4327B43AA5E5D44A
   2025-11-12 17:58:31: D059C6613DB06B256AD488859659A9A605E8643B
   ```

### Root Cause

The `thetorproject/obfs4-bridge` image creates a `torrc` file that may persist in the Docker volume or get recreated. When you migrate to `r3bo0tbx1/onion-relay:1.1.1`, the entrypoint script checks for existing configuration files with this priority:

1. **Priority 1**: Existing `/etc/tor/torrc` file (mounted or in volume)
2. **Priority 2**: Environment variables (OR_PORT, PT_PORT, EMAIL, NICKNAME)

If an old `torrc` exists, v1.1.1 tries to use it but it may be:
- Incompatible format
- Using different paths
- Missing required directives for v1.1.1 validation

The **changing fingerprints** indicate an even more serious issue: the `/var/lib/tor/keys/` directory is being lost, meaning your bridge identity is being regenerated each time.

## Emergency Fix Procedure

### Step 1: Run Diagnostic Script

We've provided a comprehensive diagnostic script that will:
- Check if your volume exists
- Verify Tor identity keys are preserved
- Find and remove incompatible torrc files
- Create a backup of your current volume
- Extract your current fingerprint

**Run this first:**

```bash
# Make sure you're in the tor-guard-relay directory
cd /path/to/tor-guard-relay

# Run the diagnostic script
./bridge-migration-fix.sh
```

**Expected output:**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔧 Bridge Migration Emergency Fix
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

ℹ️  Step 1: Checking container status...
✅ Container found

ℹ️  Step 2: Inspecting volume obfs4-data...
✅ Volume exists
ℹ️  Volume mountpoint: /var/lib/docker/volumes/obfs4-data/_data

ℹ️  Step 3: Checking volume contents...

📁 Volume contents:
   drwxr-xr-x    5 tor      tor           4096 Nov 12 17:45 .
   drwxr-xr-x    3 root     root          4096 Nov 12 17:40 ..
   drwx------    2 tor      tor           4096 Nov 12 17:45 keys
   drwx------    2 tor      tor           4096 Nov 12 17:45 pt_state
   -rw-r--r--    1 tor      tor          12345 Nov 12 17:45 cached-descriptors

🔑 Checking for Tor identity keys...
✅ keys/ directory exists
   -rw-------    1 tor      tor           1024 Nov 12 17:45 secret_id_key
   -rw-------    1 tor      tor             96 Nov 12 17:45 ed25519_master_id_secret_key
✅ secret_id_key found (RSA identity)
✅ ed25519_master_id_secret_key found (Ed25519 identity)

🔐 Checking for obfs4 bridge state...
✅ pt_state/ directory exists
   -rw-------    1 tor      tor            512 Nov 12 17:45 obfs4_state.json
✅ obfs4_state.json found (bridge credentials)

ℹ️  Step 4: Checking for incompatible torrc files...
✅ No torrc files found in volume (this is GOOD)

ℹ️  Step 5: Creating backup of volume...
✅ Backup created: bridge-backup-20251112-180000.tar.gz
ℹ️  Keep this backup safe - it contains your bridge identity keys!

ℹ️  Step 6: No torrc cleanup needed

ℹ️  Step 7: Extracting current bridge fingerprint...
✅ Current fingerprint: B1702095E8D048CF68190284BB11E183A0CDD533
ℹ️  Save this! You'll verify it matches after migration.
ℹ️  Tor Metrics: https://metrics.torproject.org/rs.html#search/B1702095E8D048CF68190284BB11E183A0CDD533

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ Diagnosis and cleanup complete!
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✅ Your bridge identity keys are preserved
✅ No torrc cleanup was needed
✅ Backup created: bridge-backup-20251112-180000.tar.gz
```

### Step 2: Deploy Fixed Configuration

After the diagnostic script completes, use the corrected Cosmos JSON:

**File:** `templates/cosmos-compose-bridge-migrated-v1.1.1.json`

```json
{
  "minVersion": "0.8.0",
  "services": {
    "obfs4-bridge": {
      "image": "localhost:5000/r3bo0tbx1/onion-relay:latest",
      "container_name": "obfs4-bridge",
      "restart": "unless-stopped",
      "network_mode": "host",
      "environment": [
        "OR_PORT=9001",
        "PT_PORT=9005",
        "EMAIL=admin@email.org",
        "NICKNAME=MyObfs4Bridge",
        "OBFS4_ENABLE_ADDITIONAL_VARIABLES=1",
        "OBFS4V_AddressDisableIPv6=0",
        "OBFS4V_MaxMemInQueues=1024 MB"
      ],
      "volumes": [
        {
          "type": "volume",
          "source": "obfs4-data",
          "target": "/var/lib/tor"
        }
      ],
      "security_opt": ["no-new-privileges:true"],
      "cap_add": ["NET_BIND_SERVICE", "CHOWN", "SETUID", "SETGID", "DAC_OVERRIDE"],
      "labels": {
        "cosmos-stack": "TorBridge",
        "cosmos-stack-main": "obfs4-bridge",
        "cosmos-icon": "https://iili.io/KsXP2Y7.png",
        "cosmos-auto-update": "true",
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

**Key points:**
- ✅ Uses ENV variables (OR_PORT, PT_PORT, etc.) - official Tor Project naming
- ✅ Volume mount: `obfs4-data` → `/var/lib/tor` (preserves keys)
- ✅ No `/etc/tor/torrc` bind mount (lets v1.1.1 generate config from ENV)
- ✅ Bridge mode auto-detected from `PT_PORT`
- ✅ `OBFS4_ENABLE_ADDITIONAL_VARIABLES=1` enables OBFS4V_* processing

### Step 3: Verify Migration Success

After deploying, verify everything works:

```bash
# 1. Check container is running
docker ps | grep obfs4-bridge

# 2. Check logs for successful startup
docker logs -f obfs4-bridge
```

**Expected successful startup logs:**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🧅 Tor Guard Relay v1.1.1 - Initialization
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🗂️  Phase 1: Directory Structure
   Created directories:
   • Data:  /var/lib/tor
   • Logs:  /var/log/tor
   • Run:   /run/tor

🔐 Phase 2: Permission Hardening
✅ Permissions configured securely

🔧 Phase 3: Configuration Setup
   Generating configuration from environment variables...
✅ Configuration generated from ENV vars

🔎 Phase 4: Configuration Validation
   📦 Tor version: Tor version 0.4.8.20.
   Validating torrc syntax...
✅ Configuration is valid

📊 Phase 5: Build Information
   🌐 Relay mode: bridge
   🔧 Config source: environment

🧩 Phase 6: Available Diagnostic Tools

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ Starting Tor relay...
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Nov 12 18:30:00.000 [notice] Tor 0.4.8.20 running on Linux...
Nov 12 18:30:00.000 [notice] Read configuration file "/etc/tor/torrc".
Nov 12 18:30:01.000 [notice] Bootstrapped 5% (conn): Connecting to a relay
Nov 12 18:30:02.000 [notice] Bootstrapped 10% (conn_done): Connected to a relay
...
Nov 12 18:30:10.000 [notice] Bootstrapped 100% (done): Done
```

**Critical checks:**

1. **Config source must be "environment"**, not "mounted":
   ```
   ✅ Configuration generated from ENV vars  ← GOOD
   🔧 Config source: environment             ← GOOD
   ```

2. **Relay mode must be "bridge"** (auto-detected from PT_PORT):
   ```
   🌐 Relay mode: bridge  ← GOOD
   ```

3. **Verify fingerprint matches** (from diagnostic script):
   ```bash
   docker exec obfs4-bridge fingerprint
   ```

   Should output the SAME fingerprint from Step 1. If it's different, your keys weren't preserved!

4. **Check health**:
   ```bash
   docker exec obfs4-bridge health | jq .
   ```

   Expected output:
   ```json
   {
     "status": "ok",
     "relay_mode": "bridge",
     "bootstrap": "100%",
     "fingerprint": "B1702095E8D048CF68190284BB11E183A0CDD533",
     "nickname": "MyObfs4Bridge",
     "or_port": 9001,
     "obfs4_port": 9005
   }
   ```

5. **Get bridge line** (after 10-30 minutes of operation):
   ```bash
   docker exec obfs4-bridge bridge-line
   ```

## If Still Failing: Advanced Debugging

### Enable DEBUG mode

If the container still crashes, add `DEBUG=true` to environment to see exact validation error:

```json
"environment": [
  "DEBUG=true",  // ← Add this first
  "OR_PORT=9001",
  "PT_PORT=9005",
  // ... rest of ENV vars
]
```

Redeploy and check logs:
```bash
docker logs obfs4-bridge 2>&1 | grep -A 10 "Configuration validation failed"
```

### Common Issues

#### Issue 1: "Using mounted configuration" when you don't have a mount

**Symptom:**
```
✅ Using mounted configuration: /etc/tor/torrc
🛑 Configuration validation failed!
```

**Cause:** Old torrc file exists somewhere (in volume or image)

**Fix:**
```bash
# Check if torrc exists in volume
docker run --rm -v obfs4-data:/data alpine find /data -name "torrc"

# Remove any found torrc files
docker run --rm -v obfs4-data:/data alpine rm -f /data/torrc /data/etc/tor/torrc
```

#### Issue 2: Fingerprints still changing after migration

**Symptom:** `docker exec obfs4-bridge fingerprint` shows different value each time

**Cause:** Volume is being recreated or not properly mounted

**Fix:**
```bash
# Verify volume exists and has keys
docker run --rm -v obfs4-data:/data alpine ls -la /data/keys

# Should see:
#   -rw------- secret_id_key
#   -rw------- ed25519_master_id_secret_key

# If missing, restore from backup:
docker run --rm \
  -v obfs4-data:/data \
  -v $(pwd):/backup \
  alpine tar xzf /backup/bridge-backup-YYYYMMDD-HHMMSS.tar.gz -C /
```

#### Issue 3: Permission errors after migration

**Symptom:**
```
[warn] Directory /var/lib/tor cannot be read: Permission denied
```

**Fix:** v1.1.1 has automatic permission healing. If it still fails:
```bash
# Fix permissions manually
docker run --rm -v obfs4-data:/data alpine chown -R 1000:1000 /data
docker run --rm -v obfs4-data:/data alpine chmod 700 /data
```

#### Issue 4: obfs4 transport not working

**Symptom:**
```
[warn] We were supposed to start obfs4 but couldn't
```

**Fix:** Verify lyrebird is installed:
```bash
docker exec obfs4-bridge which lyrebird
# Should output: /usr/bin/lyrebird

# Check if obfs4 port is configured
docker exec obfs4-bridge grep -i "ServerTransportListenAddr" /etc/tor/torrc
# Should output: ServerTransportListenAddr obfs4 0.0.0.0:9005
```

## Rollback Procedure

If migration fails and you need to go back to the official bridge image:

### Step 1: Stop v1.1.1 container

```bash
docker stop obfs4-bridge
docker rm obfs4-bridge
```

### Step 2: Restore backup (if needed)

```bash
# Only if you lost keys or data
docker volume rm obfs4-data
docker volume create obfs4-data

docker run --rm \
  -v obfs4-data:/data \
  -v $(pwd):/backup \
  alpine tar xzf /backup/bridge-backup-YYYYMMDD-HHMMSS.tar.gz -C /
```

### Step 3: Redeploy official bridge

Use your original `thetorproject/obfs4-bridge` configuration:

```json
{
  "minVersion": "0.8.0",
  "services": {
    "obfs4-bridge": {
      "image": "thetorproject/obfs4-bridge:latest",
      "container_name": "obfs4-bridge",
      "restart": "unless-stopped",
      "network_mode": "host",
      "environment": [
        "OR_PORT=9001",
        "PT_PORT=9005",
        "EMAIL=admin@email.org",
        "NICKNAME=MyObfs4Bridge"
      ],
      "volumes": [
        {
          "type": "volume",
          "source": "obfs4-data",
          "target": "/var/lib/tor"
        }
      ]
    }
  },
  "volumes": {
    "obfs4-data": {}
  }
}
```

### Step 4: Verify rollback success

```bash
docker logs -f obfs4-bridge

# Should start successfully and reuse existing keys
# Fingerprint should match your original
```

## Prevention for Future Migrations

1. **Always backup first:**
   ```bash
   docker run --rm \
     -v obfs4-data:/data \
     -v $(pwd):/backup \
     alpine tar czf /backup/bridge-backup-$(date +%Y%m%d).tar.gz /data
   ```

2. **Test with DEBUG=true** on first migration

3. **Verify fingerprint immediately** after migration

4. **Keep old container stopped** (not removed) until you verify new one works:
   ```bash
   docker stop obfs4-bridge    # ← Just stop, don't remove
   # ... deploy new v1.1.1 container with different name ...
   # ... verify it works ...
   # ... then remove old container
   ```

5. **Monitor Tor Metrics** for 24-48 hours to ensure bridge stays published

## Support

If you've followed all steps and still have issues:

1. Run diagnostic script and save output:
   ```bash
   ./bridge-migration-fix.sh > migration-debug.log 2>&1
   ```

2. Collect container logs with DEBUG:
   ```bash
   # Add DEBUG=true to environment, redeploy, then:
   docker logs obfs4-bridge > container-debug.log 2>&1
   ```

3. Open an issue with:
   - `migration-debug.log`
   - `container-debug.log`
   - Your Cosmos JSON (remove sensitive info like EMAIL)
   - Output of `docker volume inspect obfs4-data`

**GitHub Issues:** https://github.com/r3bo0tbx1/tor-guard-relay/issues

## Summary Checklist

Before migration:
- [ ] Run `bridge-migration-fix.sh` diagnostic script
- [ ] Save current fingerprint
- [ ] Create backup of `obfs4-data` volume
- [ ] Verify identity keys exist in volume

After migration:
- [ ] Container starts without crash loop
- [ ] Logs show "Config source: environment" (not "mounted")
- [ ] Relay mode is "bridge" (auto-detected)
- [ ] Fingerprint matches original (verify with `docker exec obfs4-bridge fingerprint`)
- [ ] Health check passes (`docker exec obfs4-bridge health | jq .`)
- [ ] Bootstrap reaches 100%
- [ ] Bridge line available after 10-30 minutes (`docker exec obfs4-bridge bridge-line`)
- [ ] Tor Metrics still shows your bridge (wait 1-2 hours)

**Migration should preserve:**
- ✅ Bridge fingerprint (same identity keys)
- ✅ obfs4 credentials (pt_state/obfs4_state.json)
- ✅ Bridge reputation and history
- ✅ All configuration (ORPort, PT port, nickname, contact info)

**Migration adds:**
- ✨ Official Tor Project ENV variable compatibility
- ✨ Bootstrap progress logs in terminal
- ✨ Enhanced emoji logging (v1.1.0 style)
- ✨ 4 diagnostic tools (status, health, fingerprint, bridge-line)
- ✨ Auto-detection of bridge mode from PT_PORT
- ✨ OBFS4V_* variable processing

Your bridge identity and reputation are preserved throughout the migration!