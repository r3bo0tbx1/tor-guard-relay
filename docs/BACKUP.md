# 🔐 Backup & Recovery Guide - Tor Guard Relay

Complete instructions for backing up and restoring your Tor relay's identity, keys, and configuration data.

---

## Table of Contents

- [Why Backups Matter](#why-backups-matter)
- [What to Backup](#what-to-backup)
- [Backup Methods](#backup-methods)
- [Recovery Procedures](#recovery-procedures)
- [Migration Guide](#migration-guide)
- [Best Practices](#best-practices)

---

## Why Backups Matter

Your Tor relay's **identity is permanent**. Once established, it becomes part of the Tor network's fabric. Losing these keys means:

- 🚫 Loss of your relay's fingerprint
- 📉 Loss of reputation built over time
- 🔄 New relay starting from zero
- ⏰ 8+ days to regain guard flag

**Backup your keys immediately after first successful bootstrap.**

---

## What to Backup

### 🔑 Critical Files (Preserve Forever)

Located in `/var/lib/tor/`:

| File | Purpose | Restore Impact |
|------|---------|-----------------|
| `keys/ed25519_master_id_secret_key` | Master identity key | **CRITICAL** - Defines relay identity |
| `keys/ed25519_signing_secret_key` | Signing key | **CRITICAL** - Signs all operations |
| `keys/secret_onion_key` | Onion key | **CRITICAL** - Onion address generation |
| `fingerprint` | Your relay fingerprint | Reference only (can regenerate) |

### 📋 Important Files (Backup Regularly)

| File | Purpose | Restore Impact |
|------|---------|-----------------|
| `cached-consensus` | Current Tor consensus | Nice to have (rebuilds automatically) |
| `cached-descriptors` | Relay descriptors | Nice to have (rebuilds automatically) |
| `state` | Relay state file | Optional (recreated on startup) |

### ⚙️ Configuration (Backup Before Changes)

| File | Location | Purpose |
|------|----------|---------|
| `relay.conf` | Host machine | Your relay configuration |
| `torrc` | `/etc/tor/torrc` (in container) | Mounted copy of relay.conf |

---

## Backup Methods

### Quick Backup (Simplest)

Copy the keys directory straight out of a running container:

```bash
docker cp <container-name>:/var/lib/tor/keys ./RelayKeyBackup
```

That's it. The `RelayKeyBackup/` folder now contains your relay's identity keys. Store it somewhere safe.

---

### Method 1: Docker Volume Backup (Recommended)

**Pros:** Complete, easy to restore, version-controlled  
**Cons:** Requires disk space for full volume copy

#### Step 1: Stop the Relay Gracefully

```bash
# Stop relay (allows clean shutdown)
docker stop guard-relay

# Wait for graceful shutdown
sleep 5

# Verify stopped
docker ps | grep guard-relay
```

#### Step 2: Backup the Volume

```bash
# Create backup directory
mkdir -p ~/tor-relay-backups/$(date +%Y-%m-%d)

# Backup the tor-guard-data volume
docker run --rm \
  -v tor-guard-data:/data \
  -v ~/tor-relay-backups/$(date +%Y-%m-%d):/backup \
  alpine tar czf /backup/tor-data-$(date +%s).tar.gz -C /data .

# Verify backup created
ls -lh ~/tor-relay-backups/$(date +%Y-%m-%d)/
```

**Output:**
```
-rw-r--r-- 1 user user 2.5M Jan 1 12:00 tor-data-1704110400.tar.gz
```

#### Step 3: Backup the Logs Volume

```bash
# Backup logs for audit trail
docker run --rm \
  -v tor-guard-logs:/data \
  -v ~/tor-relay-backups/$(date +%Y-%m-%d):/backup \
  alpine tar czf /backup/tor-logs-$(date +%s).tar.gz -C /data .

# Verify
ls -lh ~/tor-relay-backups/$(date +%Y-%m-%d)/
```

#### Step 4: Restart the Relay

```bash
# Restart relay
docker start guard-relay

# Monitor startup
docker logs -f guard-relay
```

---

### Method 2: Direct Key Extraction

**Pros:** Minimal, extracts only critical keys  
**Cons:** Manual process, easier to miss files

#### Extract Keys While Running

```bash
# Create secure backup directory
mkdir -p ~/tor-relay-backups/keys-only
chmod 700 ~/tor-relay-backups/keys-only

# Extract keys directly from container
docker exec guard-relay tar czf - -C /var/lib/tor/keys . | \
  tar xzf - -C ~/tor-relay-backups/keys-only/

# Verify contents
ls -la ~/tor-relay-backups/keys-only/
```

**Expected output:**
```
ed25519_master_id_secret_key
ed25519_signing_secret_key
secret_onion_key
```

#### Secure the Backup

```bash
# Set restrictive permissions
chmod 600 ~/tor-relay-backups/keys-only/*

# Verify ownership
ls -la ~/tor-relay-backups/keys-only/
```

---

### Method 3: Automated Daily Backup

**Pros:** Hands-off, versioned history  
**Cons:** Requires cron setup, disk space

#### Create Backup Script

```bash
#!/bin/bash
# Save as: /usr/local/bin/backup-tor-relay.sh

set -euo pipefail

BACKUP_DIR="/backups/tor-relay"
RETENTION_DAYS=30
CONTAINER="guard-relay"
TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)

# Create backup directory
mkdir -p "$BACKUP_DIR/$TIMESTAMP"

# Stop relay gracefully
echo "🛑 Stopping relay..."
docker stop "$CONTAINER" || true
sleep 5

# Backup data volume
echo "💾 Backing up data volume..."
docker run --rm \
  -v tor-guard-data:/data \
  -v "$BACKUP_DIR/$TIMESTAMP":/backup \
  alpine tar czf /backup/tor-data.tar.gz -C /data .

# Backup logs volume
echo "📝 Backing up logs..."
docker run --rm \
  -v tor-guard-logs:/data \
  -v "$BACKUP_DIR/$TIMESTAMP":/backup \
  alpine tar czf /backup/tor-logs.tar.gz -C /data .

# Extract fingerprint for reference
docker start "$CONTAINER"
sleep 10
docker exec "$CONTAINER" cat /var/lib/tor/fingerprint > "$BACKUP_DIR/$TIMESTAMP/fingerprint.txt" || true

# Create manifest
cat > "$BACKUP_DIR/$TIMESTAMP/MANIFEST.txt" << EOF
Tor Guard Relay Backup
Timestamp: $TIMESTAMP
Container: $CONTAINER
Relay: $(grep Nickname /opt/tor-relay/relay.conf | cut -d' ' -f2)
Files:
  - tor-data.tar.gz (Relay identity and state)
  - tor-logs.tar.gz (Tor logs for audit)
  - fingerprint.txt (Relay fingerprint reference)
EOF

# Cleanup old backups (keep last 30 days)
echo "🧹 Cleaning up old backups..."
find "$BACKUP_DIR" -maxdepth 1 -type d -mtime +$RETENTION_DAYS -exec rm -rf {} \;

# Summary
echo "✅ Backup complete: $BACKUP_DIR/$TIMESTAMP"
du -sh "$BACKUP_DIR/$TIMESTAMP"
```

#### Make Executable

```bash
chmod +x /usr/local/bin/backup-tor-relay.sh
```

#### Add to Cron (Daily at 2 AM)

```bash
# Edit crontab
crontab -e

# Add line:
0 2 * * * /usr/local/bin/backup-tor-relay.sh >> /var/log/tor-backup.log 2>&1
```

#### Monitor Backup Logs

```bash
# View backup logs
tail -f /var/log/tor-backup.log

# Check backup history
ls -lah /backups/tor-relay/
```

---

### Method 4: Off-Site Backup (Cloud/External)

**Pros:** Disaster recovery, geographic redundancy  
**Cons:** Security risk if not encrypted, potential costs

#### Encrypt Backup Before Upload

```bash
# Generate encryption key (save this somewhere secure!)
openssl rand -base64 32 > ~/tor-relay-backup.key

# Encrypt backup before upload
gpg --symmetric --cipher-algo AES256 \
  --output tor-data-encrypted.tar.gz.gpg \
  tor-data-$(date +%s).tar.gz

# Upload to cloud (e.g., AWS S3)
aws s3 cp tor-data-encrypted.tar.gz.gpg s3://my-backups/tor-relay/
```

#### Decrypt When Needed

```bash
# Decrypt backup
gpg --decrypt tor-data-encrypted.tar.gz.gpg > tor-data-restored.tar.gz

# Verify integrity
tar tzf tor-data-restored.tar.gz | head -10
```

---

## Recovery Procedures

### Scenario 1: Container Corruption

**Problem:** Container is running but data is corrupted  
**Recovery time:** 15 minutes

#### Steps

```bash
# 1. Stop the relay
docker stop guard-relay

# 2. Remove corrupted volume
docker volume rm tor-guard-data

# 3. Create new volume
docker volume create tor-guard-data

# 4. Restore from backup
docker run --rm \
  -v tor-guard-data:/data \
  -v ~/tor-relay-backups/2024-01-01:/backup \
  alpine tar xzf /backup/tor-data-1704110400.tar.gz -C /data

# 5. Verify permissions
docker exec guard-relay chown -R tor:tor /var/lib/tor

# 6. Restart relay
docker start guard-relay

# 7. Monitor startup
docker logs -f guard-relay
```

---

### Scenario 2: Server Failure - Full Restore

**Problem:** Entire server lost, migrating to new hardware  
**Recovery time:** 30 minutes

#### Steps

```bash
# 1. Prepare new server with Docker

# 2. Copy backup to new server
scp -r ~/tor-relay-backups/2024-01-01 user@new-server:/tmp/

# 3. On new server, create volume and restore
docker volume create tor-guard-data
docker run --rm \
  -v tor-guard-data:/data \
  -v /tmp/2024-01-01:/backup \
  alpine tar xzf /backup/tor-data-1704110400.tar.gz -C /data

# 4. Copy relay configuration
scp /opt/tor-relay/relay.conf user@new-server:/opt/tor-relay/

# 5. On new server, start relay
docker run -d \
  --name guard-relay \
  --network host \
  -v /opt/tor-relay/relay.conf:/etc/tor/torrc:ro \
  -v tor-guard-data:/var/lib/tor \
  -v tor-guard-logs:/var/log/tor \
  --restart unless-stopped \
  r3bo0tbx1/onion-relay:latest

# 6. Verify relay is using old identity
docker exec guard-relay fingerprint
# Should match original fingerprint!
```

---

### Scenario 3: Key Loss - Emergency Recovery

**Problem:** All keys lost, only backup exists  
**Recovery time:** 5 minutes

#### Restore Keys Only

```bash
# Stop relay
docker stop guard-relay

# Clear tor data
docker run --rm \
  -v tor-guard-data:/data \
  alpine rm -rf /data/*

# Restore from backup
docker run --rm \
  -v tor-guard-data:/data \
  -v ~/tor-relay-backups/keys-only:/backup \
  alpine bash -c "cp -r /backup/* /data/"

# Fix permissions
docker exec guard-relay chown -R tor:tor /var/lib/tor
docker exec guard-relay chmod 700 /var/lib/tor/keys

# Restart
docker start guard-relay

# Verify identity recovered
docker exec guard-relay fingerprint
```

---

## Migration Guide

### Move Relay to New Server (Same Identity)

**Goal:** Keep relay fingerprint, move to new hardware

#### Pre-Migration Checklist

- ✅ Recent full backup created
- ✅ New server prepared with Docker
- ✅ Network firewall rules ready
- ✅ DNS/IP planning done
- ✅ Maintenance window scheduled

#### Step-by-Step Migration

```bash
# === ON OLD SERVER ===

# 1. Create final backup
docker stop guard-relay
sleep 5
docker run --rm \
  -v tor-guard-data:/data \
  -v ~/tor-relay-backups/migration:/backup \
  alpine tar czf /backup/tor-data-final.tar.gz -C /data .

# 2. Verify backup
ls -lh ~/tor-relay-backups/migration/

# === TRANSFER TO NEW SERVER ===

# 3. Copy backup securely
scp -r ~/tor-relay-backups/migration user@new-server:/tmp/

# 4. Copy relay configuration
scp /opt/tor-relay/relay.conf user@new-server:/opt/tor-relay/

# === ON NEW SERVER ===

# 5. Create volume and restore
docker volume create tor-guard-data
docker run --rm \
  -v tor-guard-data:/data \
  -v /tmp/migration:/backup \
  alpine tar xzf /backup/tor-data-final.tar.gz -C /data

# 6. Start relay on new server
docker run -d \
  --name guard-relay \
  --network host \
  -v /opt/tor-relay/relay.conf:/etc/tor/torrc:ro \
  -v tor-guard-data:/var/lib/tor \
  -v tor-guard-logs:/var/log/tor \
  --restart unless-stopped \
  r3bo0tbx1/onion-relay:latest

# 7. Verify startup and identity
docker logs -f guard-relay
docker exec guard-relay fingerprint

# === FINAL VERIFICATION ===

# 8. Check on Tor Metrics (should recognize old fingerprint within hours)
# https://metrics.torproject.org/rs.html

# 9. After verification, on old server:
docker stop guard-relay
docker rm guard-relay
```

#### Verification After Migration

```bash
# Check logs for successful bootstrap
docker logs guard-relay 2>&1 | grep "Bootstrapped 100"

# Verify fingerprint matches backup
docker exec guard-relay fingerprint
# Compare with: cat ~/tor-relay-backups/migration/fingerprint.txt

# Monitor for 24 hours for any issues
docker stats guard-relay --no-stream
```

---

### Zero-Downtime Migration (Advanced)

**Goal:** Migrate relay without downtime by running dual servers

#### Setup

```bash
# 1. OLD SERVER: Create backup
docker stop guard-relay
docker run --rm \
  -v tor-guard-data:/data \
  -v ~/tor-relay-backups/dual:/backup \
  alpine tar czf /backup/tor-data.tar.gz -C /data .

# 2. NEW SERVER: Restore backup and start
docker volume create tor-guard-data
docker run --rm \
  -v tor-guard-data:/data \
  -v /tmp/dual:/backup \
  alpine tar xzf /backup/tor-data.tar.gz -C /data

docker run -d \
  --name guard-relay \
  --network host \
  -v /opt/tor-relay/relay.conf:/etc/tor/torrc:ro \
  -v tor-guard-data:/var/lib/tor \
  -v tor-guard-logs:/var/log/tor \
  --restart unless-stopped \
  r3bo0tbx1/onion-relay:latest

# 3. Verify NEW server is running
docker logs guard-relay | grep "Bootstrapped"

# 4. Wait 30 minutes for NEW server to stabilize
sleep 1800

# 5. OLD SERVER: Restart old relay
docker start guard-relay

# 6. Both servers now running same relay identity
# Tor network handles this gracefully

# 7. OLD SERVER: After 24 hours, shut down
docker stop guard-relay
```

---

## Best Practices

### ✅ DO

- ✅ **Backup immediately after bootstrap** - Preserve identity
- ✅ **Use strong encryption** for off-site backups
- ✅ **Test restores regularly** - Backups are worthless if unverifiable
- ✅ **Document fingerprints** - Keep reference copy of fingerprint
- ✅ **Automate backups** - Set and forget with cron
- ✅ **Store backups securely** - Encrypt sensitive data
- ✅ **Keep multiple copies** - Local + off-site minimum
- ✅ **Version your backups** - Date-stamped directories

### ❌ DON'T

- ❌ **Don't backup `/etc/tor/torrc`** - Mount as read-only from host
- ❌ **Don't share backup media unencrypted** - Keys are sensitive
- ❌ **Don't rely on single backup** - 3-2-1 rule applies
- ❌ **Don't ignore backup failures** - Monitor logs
- ❌ **Don't delete old backups immediately** - Keep 30+ days

### 📊 3-2-1 Backup Rule

Maintain at minimum:

- **3 copies** of your data
  - Original (running relay)
  - Backup 1 (local storage)
  - Backup 2 (off-site)
- **2 different media types**
  - NVMe/SSD
  - USB external drive
- **1 off-site copy**
  - Cloud storage (encrypted)
  - Or remote server

---

## Troubleshooting

### Backup Failed: "Volume is in use"

```bash
# Problem: Cannot backup running volume
# Solution: Stop relay first

docker stop guard-relay
sleep 5
# Retry backup command
```

### Restore Failed: "File permissions denied"

```bash
# Problem: Restored files have wrong ownership
# Solution: Fix permissions

docker exec guard-relay chown -R tor:tor /var/lib/tor
docker exec guard-relay chmod 700 /var/lib/tor/keys
```

### Fingerprint Changed After Restore

```bash
# Problem: Restored relay has different fingerprint
# Cause: Keys weren't backed up, only state
# Solution: Use Method 2 (Direct Key Extraction) for future backups

# For now, accept new identity:
docker exec guard-relay fingerprint
# This is your new permanent fingerprint
```

---

## Reference

**Backup Command Cheat Sheet:**

```bash
# Quick backup (stop relay)
docker stop guard-relay && \
docker run --rm -v tor-guard-data:/data -v ~/backups:/backup alpine tar czf /backup/tor-$(date +%s).tar.gz -C /data . && \
docker start guard-relay

# Quick restore
docker run --rm -v tor-guard-data:/data -v ~/backups:/backup alpine tar xzf /backup/tor-1704110400.tar.gz -C /data

# Verify backup integrity
tar tzf ~/backups/tor-1704110400.tar.gz | head -20

# Calculate backup size
du -sh ~/backups/tor-1704110400.tar.gz
```

---

## Support

- 📖 [Main README](../README.md)
- 🚀 [Deployment Guide](./DEPLOYMENT.md)
- 🐛 [Report Issues](https://github.com/r3bo0tbx1/tor-guard-relay/issues)
- 💬 [Tor Relay Forum](https://forum.torproject.org/)