# 🔄 Migration Guide

Guide for migrating between Tor Guard Relay versions and from other Tor relay setups.

---

## 📋 Overview

This guide covers:
- ✅ Migrating from v1.0 to v1.1
- ✅ Migrating from official Tor Docker images
- ✅ Migrating from manual Tor installations
- ✅ Preserving relay identity and keys
- ✅ Zero-downtime migration strategies

---

## 🚀 v1.0 → v1.1 Migration

### What's New in v1.1

**Major Changes:**
- ✅ Reorganized repository structure (tools/, templates/, docs/)
- ✅ Enhanced CI/CD workflows with multi-arch builds
- ✅ New monitoring tools (dashboard, metrics-http)
- ✅ Improved docker-entrypoint.sh with better error handling
- ✅ Comprehensive documentation (TOOLS.md, MONITORING.md)
- ✅ Updated Prometheus and Grafana templates
- ✅ Better health checks and diagnostics

**Breaking Changes:**
- ⚠️ **None** - v1.1 is backward compatible with v1.0
- Volume mounts and configuration remain unchanged
- All tools maintain the same interface

### Migration Steps

#### Method 1: In-Place Update (Recommended)

```bash
# 1. Stop the current relay
docker stop tor-relay

# 2. Backup relay data (CRITICAL - preserves identity)
docker run --rm \
  -v tor-guard-data:/data \
  -v ~/backups:/backup \
  alpine tar czf /backup/tor-backup-$(date +%Y%m%d).tar.gz -C /data .

# 3. Pull new v1.1 image
docker pull ghcr.io/r3bo0tbx1/onion-relay:v1.1

# 4. Update container (data volumes persist automatically)
docker rm tor-relay

docker run -d \
  --name tor-relay \
  --restart unless-stopped \
  -v tor-guard-data:/var/lib/tor \
  -v tor-guard-logs:/var/log/tor \
  -v $(pwd)/relay.conf:/etc/tor/torrc:ro \
  -p 9001:9001 \
  -e ENABLE_METRICS=true \
  -e ENABLE_HEALTH_CHECK=true \
  ghcr.io/r3bo0tbx1/onion-relay:v1.1

# 5. Verify relay identity is preserved
docker exec tor-relay fingerprint
# Should show same fingerprint as before

# 6. Check new tools are available
docker exec tor-relay status
docker exec tor-relay health | jq .
```

#### Method 2: Docker Compose Update

```bash
# 1. Update docker-compose.yml
sed -i 's/:latest/:v1.1/g' docker-compose.yml

# 2. Pull new image
docker-compose pull

# 3. Recreate containers (volumes persist)
docker-compose up -d

# 4. Verify
docker-compose exec tor-relay status
```

### Verification Checklist

After migration, verify:

- [ ] Relay fingerprint matches pre-migration
- [ ] Bootstrap completes to 100%
- [ ] ORPort is reachable
- [ ] Metrics endpoint works (if enabled)
- [ ] New tools respond: `status`, `health`, `dashboard`
- [ ] Logs show no errors
- [ ] Relay appears on Tor Metrics with same identity

```bash
# Quick verification script
#!/bin/bash
echo "🧅 v1.1 Migration Verification"
echo "================================"

echo -n "✓ Container running: "
docker ps | grep -q tor-relay && echo "YES" || echo "NO"

echo -n "✓ Fingerprint: "
docker exec tor-relay fingerprint | grep -q "Fingerprint:" && echo "OK" || echo "FAILED"

echo -n "✓ Health check: "
docker exec tor-relay health | jq -e '.status == "healthy"' &>/dev/null && echo "HEALTHY" || echo "CHECK FAILED"

echo -n "✓ Metrics: "
curl -s http://localhost:9035/metrics | grep -q "tor_relay_" && echo "OK" || echo "DISABLED/FAILED"

echo -n "✓ Bootstrap: "
docker exec tor-relay health | jq -r '.bootstrap.percent' | grep -q "100" && echo "100%" || echo "IN PROGRESS"

echo "================================"
echo "Migration verification complete!"
```

---

## 🔄 Migrating from Official Tor Docker

If you're currently using the official Tor Project Docker images:

### Pre-Migration

```bash
# 1. Note your current relay fingerprint
docker exec <your-tor-container> cat /var/lib/tor/fingerprint
# Save this - you'll verify it matches after migration

# 2. Backup relay keys (CRITICAL)
docker cp <your-tor-container>:/var/lib/tor/keys ./tor-keys-backup

# 3. Backup your torrc configuration
docker cp <your-tor-container>:/etc/tor/torrc ./torrc-backup
```

### Migration

```bash
# 4. Stop official Tor container
docker stop <your-tor-container>

# 5. Create volume for Tor Guard Relay
docker volume create tor-guard-data
docker volume create tor-guard-logs

# 6. Restore keys to new volume
docker run --rm \
  -v tor-guard-data:/data \
  -v $(pwd)/tor-keys-backup:/backup:ro \
  alpine sh -c "cp -a /backup/* /data/keys/ && chown -R 100:101 /data"

# 7. Start Tor Guard Relay with same config
docker run -d \
  --name tor-relay \
  --restart unless-stopped \
  -v tor-guard-data:/var/lib/tor \
  -v tor-guard-logs:/var/log/tor \
  -v $(pwd)/torrc-backup:/etc/tor/torrc:ro \
  -p 9001:9001 \
  ghcr.io/r3bo0tbx1/onion-relay:latest

# 8. Verify fingerprint matches
docker exec tor-relay fingerprint
```

### Configuration Differences

Official Tor images vs. Tor Guard Relay:

| Feature | Official Tor | Tor Guard Relay |
|---------|-------------|-----------------|
| Base image | Debian/Alpine | Alpine (minimal) |
| Built-in tools | None | 9 diagnostic tools |
| Monitoring | External | Built-in Prometheus |
| Health checks | Basic | Comprehensive JSON |
| Dashboard | None | Built-in HTML dashboard |
| Auto-healing | No | Yes (permissions) |
| Architecture | Manual | Multi-arch auto |

---

## 🖥️ Migrating from Manual Installation

If you're running Tor directly on a server (not containerized):

### Pre-Migration

```bash
# 1. Backup relay keys (MOST IMPORTANT)
sudo tar czf ~/tor-keys-backup.tar.gz -C /var/lib/tor keys/

# 2. Backup torrc
sudo cp /etc/tor/torrc ~/torrc-backup

# 3. Note fingerprint
sudo cat /var/lib/tor/fingerprint
```

### Migration Strategy

**Option A: Side-by-Side (Zero Downtime)**

```bash
# 1. Change manual Tor ORPort to temporary port
sudo sed -i 's/ORPort 9001/ORPort 9002/g' /etc/tor/torrc
sudo systemctl restart tor

# 2. Start Docker relay on port 9001 with restored keys
docker volume create tor-guard-data
docker run --rm \
  -v tor-guard-data:/data \
  -v ~/tor-keys-backup.tar.gz:/backup.tar.gz:ro \
  alpine sh -c "tar xzf /backup.tar.gz -C /data && chown -R 100:101 /data"

docker run -d \
  --name tor-relay \
  -v tor-guard-data:/var/lib/tor \
  -v $(pwd)/torrc-backup:/etc/tor/torrc:ro \
  -p 9001:9001 \
  ghcr.io/r3bo0tbx1/onion-relay:latest

# 3. Wait for Docker relay to be fully bootstrapped
docker exec tor-relay status

# 4. Stop manual Tor
sudo systemctl stop tor
sudo systemctl disable tor

# 5. Clean up
docker exec tor-relay fingerprint  # Verify same fingerprint
```

**Option B: Replace (Requires Downtime)**

```bash
# 1. Stop manual Tor
sudo systemctl stop tor

# 2. Create volume and restore keys
docker volume create tor-guard-data
docker run --rm \
  -v tor-guard-data:/data \
  -v ~/tor-keys-backup.tar.gz:/backup.tar.gz:ro \
  alpine sh -c "tar xzf /backup.tar.gz -C /data && chown -R 100:101 /data"

# 3. Start containerized relay
docker run -d \
  --name tor-relay \
  --restart unless-stopped \
  -v tor-guard-data:/var/lib/tor \
  -v $(pwd)/torrc-backup:/etc/tor/torrc:ro \
  -p 9001:9001 \
  ghcr.io/r3bo0tbx1/onion-relay:latest

# 4. Verify
docker exec tor-relay fingerprint
docker exec tor-relay status
```

### Post-Migration Cleanup

```bash
# Optional: Remove manual Tor installation
sudo apt-get remove --purge tor tor-geoipdb -y
sudo apt-get autoremove -y

# Optional: Clean up old data (AFTER verifying Docker relay works)
# sudo rm -rf /var/lib/tor
# sudo rm -rf /etc/tor
```

---

## 🔑 Preserving Relay Identity

**CRITICAL:** Your relay's identity is stored in these files:

```
/var/lib/tor/keys/
├── ed25519_master_id_public_key
├── ed25519_master_id_secret_key
├── ed25519_signing_cert
├── ed25519_signing_secret_key
└── secret_id_key
```

**To preserve your relay's reputation and identity:**

1. **Always backup these files before migration**
2. **Never lose these files** - they cannot be recovered
3. **Verify fingerprint after migration** matches original
4. **If fingerprint changes** - you've lost your identity and must start over

### Emergency Recovery

If you've lost your keys but have a backup:

```bash
# Create new volume
docker volume create tor-guard-data-recovered

# Restore keys
docker run --rm \
  -v tor-guard-data-recovered:/data \
  -v ~/tor-keys-backup.tar.gz:/backup.tar.gz:ro \
  alpine sh -c "mkdir -p /data/keys && tar xzf /backup.tar.gz -C /data && chown -R 100:101 /data"

# Start relay with recovered volume
docker run -d \
  --name tor-relay-recovered \
  -v tor-guard-data-recovered:/var/lib/tor \
  -v $(pwd)/relay.conf:/etc/tor/torrc:ro \
  -p 9001:9001 \
  ghcr.io/r3bo0tbx1/onion-relay:latest

# Verify fingerprint
docker exec tor-relay-recovered fingerprint
```

---

## 🚨 Common Migration Issues

### Issue: Fingerprint Changed After Migration

**Cause:** Keys were not properly preserved or restored with wrong permissions.

**Solution:**
```bash
# Stop relay
docker stop tor-relay

# Restore keys backup
docker run --rm \
  -v tor-guard-data:/data \
  -v ~/tor-keys-backup.tar.gz:/backup.tar.gz:ro \
  alpine sh -c "rm -rf /data/keys && tar xzf /backup.tar.gz -C /data && chown -R 100:101 /data"

# Restart
docker start tor-relay
```

### Issue: Permission Denied Errors

**Cause:** Wrong file ownership in restored keys.

**Solution:**
```bash
# Fix permissions (auto-healed on next restart, but can force)
docker run --rm \
  -v tor-guard-data:/data \
  alpine sh -c "chown -R 100:101 /data && chmod 700 /data/keys && chmod 600 /data/keys/*"
```

### Issue: Bootstrap Fails After Migration

**Cause:** Network connectivity or configuration issues.

**Solution:**
```bash
# Run network diagnostics
docker exec tor-relay net-check

# Check logs
docker exec tor-relay view-logs --errors

# Verify configuration
docker exec tor-relay cat /etc/tor/torrc
```

### Issue: Old Tor Process Still Running

**Cause:** Manual Tor installation not fully stopped.

**Solution:**
```bash
# Stop system Tor
sudo systemctl stop tor
sudo systemctl disable tor

# Verify nothing on port 9001
sudo netstat -tulpn | grep 9001

# Kill any remaining Tor processes
sudo pkill -9 tor
```

---

## 📊 Migration Checklist

Use this checklist for smooth migrations:

### Pre-Migration
- [ ] Backup relay keys (most critical)
- [ ] Backup torrc configuration
- [ ] Note current fingerprint
- [ ] Test backups can be extracted
- [ ] Document current monitoring setup
- [ ] Check current bandwidth usage

### During Migration
- [ ] Pull new image version
- [ ] Create new volumes
- [ ] Restore keys with correct ownership
- [ ] Mount configuration
- [ ] Start new container
- [ ] Verify container starts without errors

### Post-Migration
- [ ] Verify same fingerprint
- [ ] Confirm bootstrap reaches 100%
- [ ] Check ORPort reachability
- [ ] Test all tools (status, health, etc.)
- [ ] Verify metrics (if enabled)
- [ ] Update monitoring dashboards
- [ ] Test log access
- [ ] Check Tor Metrics shows relay as active

### Cleanup (after 24h of successful operation)
- [ ] Remove old container
- [ ] Clean up old volumes (if not reusing)
- [ ] Remove manual Tor installation (if applicable)
- [ ] Archive old backups
- [ ] Update documentation

---

## 🆘 Rollback Procedure

If migration fails and you need to rollback:

```bash
# 1. Stop new container
docker stop tor-relay
docker rm tor-relay

# 2. If upgrading from v1.0: revert to old image
docker run -d \
  --name tor-relay \
  --restart unless-stopped \
  -v tor-guard-data:/var/lib/tor \
  -v tor-guard-logs:/var/log/tor \
  -v $(pwd)/relay.conf:/etc/tor/torrc:ro \
  -p 9001:9001 \
  ghcr.io/r3bo0tbx1/onion-relay:v1.0

# 3. If migrating from manual: restore system Tor
sudo systemctl start tor
sudo systemctl enable tor

# 4. Verify fingerprint matches original
```

---

## 📚 Related Documentation

- [Deployment Guide](./DEPLOYMENT.md) - Fresh installation
- [Backup Guide](./BACKUP.md) - Data persistence strategies
- [Tools Reference](./TOOLS.md) - Using diagnostic tools
- [Monitoring Guide](./MONITORING.md) - Setting up monitoring

---

## 💡 Migration Tips

1. **Always test in staging first** if you have multiple relays
2. **Migrate during low-traffic periods** to minimize impact
3. **Keep old backups for 30 days** after successful migration
4. **Document your specific configuration** before starting
5. **Have rollback plan ready** before beginning migration
6. **Monitor closely for 24-48h** after migration

---

**Last Updated:** November 2025 | **Version:** 1.1