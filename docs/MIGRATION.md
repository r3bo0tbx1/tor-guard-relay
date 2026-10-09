# Migration Guide - Tor Guard Relay

This document provides general migration guidance for Tor Guard Relay deployments.

For **specific v1.1.0 → >=v1.1.1 migration**, see [`MIGRATION-V1.1.X.md`](MIGRATION-V1.1.X.md).

---

## 📋 General Migration Principles

### 1. Always Backup First

## 📋 Before you start

Run from the repository on Linux or WSL. With Docker Desktop, the command uses `docker.exe` from WSL when available. Set `DOCKER` to override the CLI. Store backups and private age identities in the Linux filesystem with restricted permissions; Windows-mounted directories do not provide the same Unix permission guarantees.

Create a recovery identity once, store its private key separately from the archives, and copy only its public recipient into the recipient file:

```sh
umask 077
mkdir -p "$HOME/.config/relay-backup" "$HOME/relay-backups"
age-keygen -o "$HOME/.config/relay-backup/identity.txt"
age-keygen -y "$HOME/.config/relay-backup/identity.txt" > "$HOME/.config/relay-backup/recipients.txt"
```

Use an existing organization recipient file if you already manage recovery keys. Losing every decryption identity makes the backup unrecoverable. External or offline Tor master keys are **not included** and need a separate encrypted recovery procedure.

## 📦 Create

Preview coverage first. The source must already have a fingerprint and keys.

```sh
sh scripts/utilities/relay-backup.sh create --container tor-relay \
  --recipients "$HOME/.config/relay-backup/recipients.txt" \
  --output-dir "$HOME/relay-backups" --dry-run

sh scripts/utilities/relay-backup.sh create --container tor-relay \
  --recipients "$HOME/.config/relay-backup/recipients.txt" \
  --output-dir "$HOME/relay-backups" --stop \
  --deployment-file templates/docker-compose/docker-compose-guard-env.yml
```

Replace the deployment-file path with your actual Compose or ENV file. Each optional file is encrypted too; use distinct basenames. Add `--logs` only when you need incident evidence. Interactive `--passphrase` replaces `--recipients`; never put a passphrase in command arguments or ENV variables.

A running source requires explicit `--stop`. The command waits for Docker to report it stopped with PID zero, refuses shared storage with another running container writer, and restarts only the source it stopped. A source already stopped remains stopped. A failure removes the partial ciphertext and attempts source restart; a restart failure is reported separately. The default stop timeout is 45 seconds.

| Included | Coverage |
| --- | --- |
| Configuration | Active torrc and supported recursive absolute includes |
| Identity and state | Entire effective DataDirectory, including keys, fingerprint, family material, state, caches and pt_state |
| Manifest | File hashes, modes, original paths, fingerprint, image identity and available build labels |
| Optional files | Explicit deployment files; logs with `--logs` |

The command supports exact absolute include files, flat absolute include globs and directories with a trailing slash. Relative includes, unmatched globs, links, special files and conflicting DataDirectory overrides fail closed. Host processes writing bind mounts cannot be detected through Docker; stop those writers yourself. The default total payload limit is 20 GiB, configurable with `--max-bytes`.


Verify the archive and rehearse staged restore before changing state.

---

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

## 📋 Prepare

Record source image digest, deployment, fingerprint, public listeners and mount layout. Identify the active torrc, all include files and the effective DataDirectory. Preserve family key material and obfs4 pt_state with identity keys.

Create and verify an [encrypted backup](BACKUP.md), then rehearse restore into a new staging directory using a compatible local image. Keep the original data untouched until recovery and fingerprint checks pass.

## 🚀 Upgrade an existing deployment

1. Review ENV versus mounted config ownership. Persist lasting changes in the deployment.
2. Validate torrc and Compose/template syntax.
3. Stop the old relay and confirm no other writer shares the data.
4. Recreate with the validated image, retaining the original data and include mounts.
5. Confirm Tor 0.4.9.14 or newer and the original fingerprint.
6. Check fresh bootstrap evidence and public listeners independently.
7. Keep the previous image/deployment and backup until the new relay is verified.

Avoid volume deletion commands. Do not remove keys or pt_state to fix configuration errors.

## 🌉 Official bridge ownership

Earlier Debian-based bridge deployments commonly used UID 101; this image uses UID 100/GID 101. Inspect actual ownership before changing it. Apply ownership fixes only to the intended stopped relay data, after verified recovery. Retain the original owner information for rollback.

The interactive [migration assistant](../scripts/migration/README.md) now requires encrypted backup creation and verification before mutation. Unsupported source layouts fail instead of silently falling back to a plaintext archive. Manual staged recovery is preferable for layouts the assistant cannot identify.

## 👨‍👩‍👧 Happy Family and accounting

Preserve family keys and FamilyId settings. Accounting state is part of DataDirectory, so keep it with the configuration defining AccountingMax and AccountingStart. IPv6 listener/policy changes also require provider and firewall checks; syntax validity does not prove connectivity.

## ↩️ Rollback

Stop the new relay before bringing back the old image with the old deployment. Preserve the current data for investigation. If restoring is necessary, restore into a new directory, validate offline, compare the original fingerprint, and activate explicitly. Never run both copies of the identity.

---

## ⚙️ Container vs Image vs Configuration

**Image**: The Docker image (`r3bo0tbx1/onion-relay:latest`)
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
  - `docker exec <container> gen-family --show` (if using Happy Family)
- [ ] Tor Metrics shows relay (after 1-2 hours)

---

## 🛠️ Common Migration Issues

### Issue: "Permission denied" Errors

**Cause**: Volume ownership mismatch

**Fix**:
```bash
# Check ownership
docker run --rm -v <volume>:/data alpine:3.24.2 ls -ldn /data

# Fix if needed (Alpine tor user is UID 100)
docker run --rm -v <volume>:/data alpine:3.24.2 chown -R 100:101 /data
```

### Issue: Fingerprint Changed

**Cause**: The deployment did not preserve the original private identity keys.

**Fix**: Stop the replacement relay and preserve both state directories. Verify your encrypted archive and restore into a new staging directory using the [recovery procedure](BACKUP.md#recovery-procedures). Compare fingerprints before activation; never erase live storage to make room for a restore.

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

**Fix**: Use v2.2.0 diagnostics: `doctor` identifies configuration and process failures; `health` separates liveness, readiness and freshness.

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
- **Security Policy**: [`../SECURITY.md`](../SECURITY.md)

---

## 🆘 Getting Help

If migration fails:

1. **Check logs**: `docker logs <container>`
2. **Verify backup**: the full encrypted archive with `relay-backup.sh verify`
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

```sh
# Preview encrypted coverage, then take a controlled snapshot.
sh scripts/utilities/relay-backup.sh create --container tor-relay \
  --recipients "$HOME/.config/relay-backup/recipients.txt" \
  --output-dir "$HOME/relay-backups" --dry-run
sh scripts/utilities/relay-backup.sh create --container tor-relay \
  --recipients "$HOME/.config/relay-backup/recipients.txt" \
  --output-dir "$HOME/relay-backups" --stop

# Replace BACKUP with the archive name printed by create.
sh scripts/utilities/relay-backup.sh verify "$HOME/relay-backups/BACKUP.tar.gz.age" \
  --identity "$HOME/.config/relay-backup/identity.txt"
sh scripts/utilities/relay-backup.sh restore "$HOME/relay-backups/BACKUP.tar.gz.age" \
  --identity "$HOME/.config/relay-backup/identity.txt" \
  --destination "$HOME/relay-restored" --validation-image tor-relay:2.2.0-local
```

🔐 Keep the private age identity separately. Restore only to a new staging directory, validate ownership and mounts, and stop the previous relay before activating its identity. The validation image must already exist locally.

```sh
# After deliberate activation, compare identity and fresh health.
docker exec tor-relay fingerprint
docker exec tor-relay health | jq .
docker exec tor-relay doctor
```

---

### Version-Specific Migrations

| From | To | Guide |
|------|-----|-------|
| v1.1.0 | >=v1.1.1 | [MIGRATION-V1.1.X.md](MIGRATION-V1.1.X.md) |
| Official bridge | v1.1.1 | [MIGRATION-V1.1.X.md](MIGRATION-V1.1.X.md) - Path 2 |
| Future | Future | This document + version-specific guide |

---

*Last Updated: 2026-10-09*
