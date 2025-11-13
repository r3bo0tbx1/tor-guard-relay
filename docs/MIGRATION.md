# Migration Guide - Tor Guard Relay

This document provides general migration guidance for Tor Guard Relay deployments.

For **specific v1.1.0 → v1.1.1 migration**, see [`MIGRATION-V1.1.X.md`](MIGRATION-V1.1.X.md).

---

## 📋 General Migration Principles

### 1. Always Backup First

```bash
# Backup data volume
docker run --rm \
  -v <volume-name>:/data \
  -v /tmp:/backup \
  alpine:3.22.2 tar czf /backup/tor-backup-$(date +%Y%m%d).tar.gz /data

# Verify backup
ls -lh /tmp/tor-backup-*.tar.gz

# Save fingerprint
docker run --rm -v <volume-name>:/data alpine:3.22.2 cat /data/fingerprint > /tmp/fingerprint-backup.txt
```

### 2. Fingerprint Preservation

**Your relay identity is stored in**:
- `/var/lib/tor/keys/secret_id_key` (RSA identity)
- `/var/lib/tor/keys/ed25519_master_id_secret_key` (Ed25519 identity)
- `/var/lib/tor/pt_state/obfs4_state.json` (bridge credentials, bridges only)

**CRITICAL**: These files must be preserved or your relay will get a new fingerprint.

### 3. Configuration Approaches

**Recommended: Mounted Config File**
```yaml
volumes:
  - type: bind
    source: /path/to/relay.conf
    target: /etc/tor/torrc
    read_only: true
```

**Alternative: Environment Variables**
```yaml
environment:
  - TOR_RELAY_MODE=guard
  - TOR_NICKNAME=MyRelay
  - TOR_CONTACT_INFO=email@example.com
```

**Priority**: Mounted file > ENV variables

---

## 🔄 Migration Scenarios

### Scenario 1: Upgrading Between Versions (Same Image)

**Example**: v1.1.0 → v1.1.1

**Steps**:
1. Stop container
2. Backup volumes
3. Remove container (`docker rm`)
4. Pull new image version
5. Create new container with same volumes
6. Verify fingerprint matches

**Expected Downtime**: 1-5 minutes

**See**: [`MIGRATION-V1.1.X.md`](MIGRATION-V1.1.X.md) for detailed instructions

### Scenario 2: Migrating from Official Tor Images

**Example**: `thetorproject/obfs4-bridge` → `r3bo0tbx1/onion-relay`

**Challenges**:
- Different base OS (Debian → Alpine)
- Different user UID (101 → 100)
- Volume ownership needs fixing

**Steps**:
1. Backup everything
2. **Fix volume ownership**: `chown -R 100:101`
3. Create config file (recommended over ENV)
4. Deploy new container
5. Verify fingerprint preserved

**Expected Downtime**: 5-10 minutes

**See**: [`MIGRATION-V1.1.X.md`](MIGRATION-V1.1.X.md) - Migration Path 2

### Scenario 3: Changing Relay Type

**Example**: Guard → Exit, Guard → Bridge

**Warning**: ⚠️ This changes your relay's role and requires careful consideration.

**Steps**:
1. Understand legal implications (especially for exit relays)
2. Update configuration
3. Restart container
4. Monitor logs for warnings
5. Wait 24-48 hours for Tor network to update

**Fingerprint**: Preserved ✅

### Scenario 4: Moving to New Server

**Steps**:
1. **On old server**:
   - Stop container
   - Backup volume to tarball
   - Transfer tarball to new server

2. **On new server**:
   - Create volume
   - Restore from tarball
   - Deploy container with same configuration
   - Verify fingerprint

**Example**:
```bash
# Old server - create backup
docker run --rm -v tor-data:/data -v $PWD:/backup alpine:3.22.2 \
  tar czf /backup/tor-data.tar.gz /data

# Transfer tor-data.tar.gz to new server

# New server - restore
docker volume create tor-data
docker run --rm -v tor-data:/data -v $PWD:/backup alpine:3.22.2 \
  tar xzf /backup/tor-data.tar.gz -C /
```

---

## ⚙️ Container vs Image vs Configuration

**Image**: The Docker image (`r3bo0tbx1/onion-relay:1.1.1`)
- Contains Tor binary, scripts, OS
- Immutable
- Can be updated independently

**Container**: Running instance
- Created from image
- Has specific configuration
- Must be recreated to use new image

**Configuration**: Your relay settings
- Mounted file (`/etc/tor/torrc`)
- OR environment variables
- Persists across container recreations

**Volumes**: Your relay data
- Identity keys
- State information
- Logs
- Persists across container recreations

---

## 🔍 Verification Checklist

After any migration:

- [ ] Container starts successfully
- [ ] No errors in logs: `docker logs <container> | grep -i error`
- [ ] Fingerprint matches backup
- [ ] Configuration loaded correctly
- [ ] Bootstrap reaches 100%
- [ ] Relay/bridge is reachable
- [ ] Diagnostic tools work:
  - `docker exec <container> status`
  - `docker exec <container> health`
  - `docker exec <container> fingerprint`
- [ ] Tor Metrics shows relay (after 1-2 hours)

---

## 🛠️ Common Migration Issues

### Issue: "Permission denied" Errors

**Cause**: Volume ownership mismatch

**Fix**:
```bash
# Check ownership
docker run --rm -v <volume>:/data alpine:3.22.2 ls -ldn /data

# Fix if needed (Alpine tor user is UID 100)
docker run --rm -v <volume>:/data alpine:3.22.2 chown -R 100:101 /data
```

### Issue: Fingerprint Changed

**Cause**: Identity keys not preserved

**Fix**: Restore from backup:
```bash
docker stop <container>
docker run --rm -v <volume>:/data -v /tmp:/backup alpine:3.22.2 \
  sh -c 'rm -rf /data/* && tar xzf /backup/tor-backup-*.tar.gz -C /'
docker start <container>
```

### Issue: Container Restart Loop

**Debug**:
```bash
# Check logs
docker logs <container> --tail 50

# Verify using correct image
docker inspect <container> --format='{{.Image}}'

# Check configuration
docker exec <container> cat /etc/tor/torrc
```

**Common causes**:
- Invalid configuration syntax
- Missing required fields
- ENV variable validation failures (use mounted config instead)

### Issue: Health Check Failing

**Cause**: Old versions had hardcoded health check path

**Fix**: Update to v1.1.1+ which includes smart healthcheck script

---

## 📊 Migration Planning

### Before Migration

1. **Document current state**:
   - Image version
   - Configuration source (file or ENV)
   - Volume names
   - Port mappings
   - Current fingerprint

2. **Test plan**:
   - What to verify post-migration
   - Rollback procedure
   - Downtime window

3. **Communication**:
   - Notify users (for bridges)
   - Schedule maintenance window
   - Prepare status updates

### During Migration

1. **Follow documented procedure**
2. **Take backups**
3. **Verify each step**
4. **Don't skip verification**

### After Migration

1. **Monitor logs for 30 minutes**
2. **Verify fingerprint**
3. **Check Tor Metrics after 1-2 hours**
4. **Update documentation**
5. **Keep backups for 7 days**

---

## 🔒 Security Considerations

### UID/GID Consistency

**This image uses**:
- User: `tor`
- UID: 100
- GID: 101

**When migrating from Debian-based images**:
- Old UID: 101
- **Must fix volume ownership**

### File Permissions

**Expected permissions**:
```
drwx------  /var/lib/tor     (700, owned by tor)
drwxr-xr-x  /var/log/tor     (755, owned by tor)
-rw-------  keys/*           (600, owned by tor)
```

### Capabilities

**Minimal required**:
```yaml
cap_add:
  - NET_BIND_SERVICE  # Only if using ports < 1024
```

**Avoid granting unnecessary capabilities**.

---

## 📚 Resources

- **v1.1.0 → v1.1.1 Migration**: [`MIGRATION-V1.1.X.md`](MIGRATION-V1.1.X.md)
- **Deployment Guide**: [`DEPLOYMENT.md`](DEPLOYMENT.md)
- **Troubleshooting**: [`TROUBLESHOOTING-BRIDGE-MIGRATION.md`](TROUBLESHOOTING-BRIDGE-MIGRATION.md)
- **Tools Documentation**: [`TOOLS.md`](TOOLS.md)
- **Security Audit**: [`../SECURITY-AUDIT-REPORT.md`](../SECURITY-AUDIT-REPORT.md)

---

## 🆘 Getting Help

If migration fails:

1. **Check logs**: `docker logs <container>`
2. **Verify backup**: `ls -lh /tmp/tor-backup-*.tar.gz`
3. **Restore from backup** if needed
4. **Consult troubleshooting docs**
5. **Open GitHub issue** with:
   - Migration path (what → what)
   - Error messages
   - Log output
   - Configuration (redact sensitive info)

---

## ⚡ Quick Reference

### Common Commands

```bash
# Backup
docker run --rm -v <vol>:/data -v /tmp:/backup alpine:3.22.2 tar czf /backup/backup.tar.gz /data

# Restore
docker run --rm -v <vol>:/data -v /tmp:/backup alpine:3.22.2 tar xzf /backup/backup.tar.gz -C /

# Fix ownership (Alpine)
docker run --rm -v <vol>:/data alpine:3.22.2 chown -R 100:101 /data

# Get fingerprint
docker exec <container> fingerprint

# Check health
docker exec <container> health | jq .

# Full status
docker exec <container> status
```

### Version-Specific Migrations

| From | To | Guide |
|------|-----|-------|
| v1.1.0 | v1.1.1 | [MIGRATION-V1.1.X.md](MIGRATION-V1.1.X.md) |
| Official bridge | v1.1.1 | [MIGRATION-V1.1.X.md](MIGRATION-V1.1.X.md) - Path 2 |
| Future | Future | This document + version-specific guide |

---

*Last Updated: 2025-11-13*
