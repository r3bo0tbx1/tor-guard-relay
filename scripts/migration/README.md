# Migration Scripts

This directory contains automated migration tools for upgrading from other Tor relay images to `r3bo0tbx1/onion-relay`.

## 🔐 Required recovery setup

Install host Python 3.10+ and age. Prepare public recipient and private recovery identity files as described in the backup guide, then export their paths:

```sh
export RELAY_BACKUP_RECIPIENTS="$HOME/.config/relay-backup/recipients.txt"
export RELAY_BACKUP_IDENTITY="$HOME/.config/relay-backup/identity.txt"
sh scripts/migration/migrate-from-official.sh
```

These variables hold file paths, never passphrases. The migration assistant creates and fully verifies an encrypted backup of the detected source container before changing data. Backup failure aborts migration. It no longer creates a plaintext tar archive or offers to proceed without verification.

For a source without a detectable container or a supported config/include layout, follow manual staged recovery in the current migration guide. Do not guess a data path from unrelated volumes.

## ✅ Before and after

Record image digest, deployment, fingerprint, ownership, family material and bridge transport state. Inspect listener and mount choices before accepting the assistant's prompts.

After recreation, verify the same fingerprint, valid active torrc, current Tor version, fresh bootstrap and independent public reachability. Obtain a bridge line with an explicit public address. Retain the old deployment and encrypted backup for rollback, and never run duplicate identities.

The old `migration-validator.sh`, emergency torrc-deletion script and v1.1.x migration test are retired with clear successor instructions. Use health/doctor, host inventory and the isolated encrypted recovery rehearsal instead.


> [!WARNING]
> 📜 This guide retains historical problem descriptions and deployment context. Its legacy plaintext backup and live-volume replacement procedures are superseded by verified encrypted recovery. Use the current procedure above; do not copy old cleanup commands onto live state.

## migrate-from-official.sh

Automated migration assistant for users moving from the official `thetorproject/obfs4-bridge` image to this project.

### What It Does

1. **Detects existing setup** - Finds your running official bridge container and extracts configuration
2. **Backs up data** - Creates and fully verifies an encrypted age archive of config, includes, identity and state
3. **Fixes UID mismatch** - Corrects ownership from Debian (UID 101) to Alpine (UID 100)
4. **Deploys new container** - Creates new container with same configuration
5. **Validates migration** - Verifies fingerprint preservation and bridge functionality
6. **Provides next steps** - Clear guidance on monitoring and verification

### Why You Need This

The official `thetorproject/obfs4-bridge` image uses:
- **Base:** Debian
- **User:** debian-tor (UID 101)

This project uses:
- **Base:** Alpine Linux
- **User:** tor (UID 100)

Without fixing the UID mismatch, you'll get permission errors:
```
Directory /var/lib/tor cannot be read: Permission denied
```

### Quick Start

```bash
# Interactive migration (recommended)
./scripts/migration/migrate-from-official.sh

# The script will:
# 1. Detect your existing container
# 2. Extract NICKNAME, EMAIL, OR_PORT, PT_PORT
# 3. Prompt for confirmation before each step
# 4. Create backup in ~/tor-backups/
# 5. Fix ownership automatically
# 6. Deploy new container
# 7. Validate fingerprint matches
```

### Manual Mode

Manual configuration prompts are retained for compatibility, but automatic migration requires a detectable source container for verified encrypted backup. Without one, use [staged manual migration](../../docs/MIGRATION.md); the script aborts before modifying storage.

```bash
./scripts/migration/migrate-from-official.sh

# When prompted "No thetorproject/obfs4-bridge container found":
# Choose "Continue with manual configuration"

# You'll be asked for:
# - Volume name (e.g., obfs4-data)
# - New container name (default: tor-bridge)
# - OR_PORT (default: 9001)
# - PT_PORT (default: 9002)
# - NICKNAME
# - EMAIL
```

### What Gets Preserved

✅ **Identity keys** - Your relay's cryptographic identity
✅ **Fingerprint** - Relay reputation and statistics
✅ **Bridge credentials** - obfs4 state and bridge line
✅ **Tor state** - Bootstrap state and consensus cache

### Migration Checklist

**Before running:**
- [ ] Note your current fingerprint: `docker exec <container> cat /var/lib/tor/fingerprint`
- [ ] Save your bridge line: `docker exec <container> cat /var/lib/tor/pt_state/obfs4_bridgeline.txt`
- [ ] Verify volume name: `docker inspect <container> --format='{{range .Mounts}}{{.Name}}{{end}}'`
- [ ] Ensure sufficient disk space for backup (~100 MB typical)

**After migration:**
- [ ] Verify fingerprint matches old fingerprint
- [ ] Check bootstrap progress: `docker exec tor-bridge status`
- [ ] Verify bridge line: `docker exec tor-bridge bridge-line --address 203.0.113.42`
- [ ] Check Tor Metrics (may take 24h): https://metrics.torproject.org/rs.html#search/YOUR_FINGERPRINT
- [ ] Monitor logs for 24 hours: `docker logs -f tor-bridge`
- [ ] Keep backup for at least 1 week

### Script Features

**Automatic Detection:**
- Finds `thetorproject/obfs4-bridge` containers
- Extracts ENV variables (NICKNAME, EMAIL, OR_PORT, PT_PORT)
- Detects volume mounts automatically
- Reads current fingerprint from volume

**Safety Features:**
- Creates backup before any changes
- Validates each step before proceeding
- Preserves old container (stopped, not deleted)
- Provides rollback instructions
- Confirms before destructive operations

**Validation:**
- Checks volume ownership (100:101)
- Waits for container startup (60s timeout)
- Waits for Tor bootstrap (300s timeout)
- Compares old vs new fingerprint
- Validates bridge line generation
- Runs health checks

**User Experience:**
- Color-coded output (errors, warnings, success)
- Progress indicators with step numbers
- Clear next steps after completion
- Helpful error messages with troubleshooting

### Example Output

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    Migration Assistant: Official Tor Bridge → Onion Relay
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

This script automates migration from:
  Source: thetorproject/obfs4-bridge (Debian, UID 101)
  Target: r3bo0tbx1/onion-relay (Alpine, UID 100)


━━━ Step 1: Pre-flight Checks
✅ Docker is available

━━━ Step 2: Detect Existing Setup
✅ Found container: obfs4-bridge
ℹ Configuration detected:
ℹ   Nickname: MyBridge
ℹ   Email: admin@example.com
ℹ   OR Port: 9001
ℹ   PT Port: 9002
ℹ Volume mounts:
ℹ   obfs4-data → /var/lib/tor
ℹ Checking current fingerprint...
✅ Current fingerprint: 1234567890ABCDEF1234567890ABCDEF12345678

❓ Proceed with migration? [y/N]: y

━━━ Step 3: Backup Current Data
❓ Create backup of volume 'obfs4-data'? [y/N]: y
ℹ Creating backup of volume 'obfs4-data'...
✅ Encrypted backup created and fully verified: /home/user/tor-backups/BACKUP.tar.gz.age

━━━ Step 4: Stop Old Container
ℹ Stopping container: obfs4-bridge
✅ Container stopped
❓ Remove old container 'obfs4-bridge'? (keeps volumes) [y/N]: y
✅ Container removed

━━━ Step 5: Fix Volume Ownership
ℹ Current ownership: 101:101
ℹ Fixing ownership: debian-tor (101) → tor (100)...
ℹ Current ownership: 101:101
ℹ New ownership: 100:101
✅ Ownership fixed successfully

━━━ Step 6: Deploy New Container
ℹ Deploying new container: tor-bridge
ℹ Image: r3bo0tbx1/onion-relay:latest
ℹ Running command:
  docker run -d \
    --name tor-bridge \
    --network host \
    --restart unless-stopped \
    ...
✅ Container started

━━━ Step 7: Wait for Container to Start
ℹ Waiting for container to start (max 60s)...
✅ Container is running

━━━ Step 8: Wait for Tor Bootstrap
ℹ Waiting for Tor to bootstrap (max 300s)...
ℹ Bootstrap progress: 5%
ℹ Bootstrap progress: 25%
ℹ Bootstrap progress: 75%
ℹ Bootstrap progress: 90%
✅ Tor fully bootstrapped (100%)

━━━ Step 9: Validate Migration
ℹ Checking fingerprint...
✅ Fingerprint: 1234567890ABCDEF1234567890ABCDEF12345678
✅ Fingerprint matches (relay identity preserved)
ℹ Checking bridge line...
✅ Bridge line generated successfully
ℹ Bridge line:
  obfs4 1.2.3.4:9002 1234567890ABCDEF1234567890ABCDEF12345678 cert=... iat-mode=0
ℹ Checking health status...
✅ Health check passed

━━━ Migration Complete!

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ Migration Successful
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Next Steps:

1️⃣  Check container status:
   docker exec tor-bridge status

2️⃣  View logs:
   docker logs -f tor-bridge

3️⃣  Get bridge line (after bootstrap complete):
   docker exec tor-bridge bridge-line --address 203.0.113.42

4️⃣  Check fingerprint on Tor Metrics:
   https://metrics.torproject.org/rs.html#details/1234567890ABCDEF1234567890ABCDEF12345678

5️⃣  Monitor resource usage:
   docker stats tor-bridge
```

### Troubleshooting

#### Migration Failed at Ownership Fix

**Symptom:** "Failed to fix ownership" error

**Cause:** Volume is mounted as read-only or insufficient permissions

**Solution:**
```bash
# Manually fix ownership
docker run --rm -v <volume-name>:/data alpine:3.24.2 chown -R 100:101 /data

# Verify
docker run --rm -v <volume-name>:/data alpine:3.24.2 ls -ldn /data
# Should show: drwx------ 5 100 101 ...
```

#### Fingerprint Mismatch After Migration

**Symptom:** Old and new fingerprints don't match

**Cause:** Identity keys were not preserved or volume mount incorrect

**Solution:**
> 🔐 This historical backup/cleanup command is retired. Follow the encrypted create → verify → staged restore procedure in the current backup guide.


#### Bootstrap Timeout

**Symptom:** "Timeout waiting for bootstrap completion"

**Cause:** Tor network is slow or connectivity issues

**Solution:**
```bash
# Check if Tor is actually running
docker exec tor-bridge pgrep tor

# Check logs for errors
docker logs tor-bridge 2>&1 | tail -50

# Manual bootstrap check
docker exec tor-bridge health | jq .

# Wait longer (Tor can take 5-10 minutes on first run)
watch -n5 'docker exec tor-bridge health | jq .bootstrap'
```

#### Container Exits Immediately

**Symptom:** Container starts but immediately exits

**Cause:** Configuration error or volume permission issues

**Solution:**
```bash
# Check container logs
docker logs tor-bridge

# Common issues:
# 1. "Directory /var/lib/tor cannot be read: Permission denied"
#    → Run ownership fix again

# 2. "Invalid configuration"
#    → Check ENV variables: docker inspect tor-bridge --format='{{range .Config.Env}}{{println .}}{{end}}'

# 3. "Could not bind to 0.0.0.0:9001: Address already in use"
#    → Change OR_PORT or stop conflicting service
```

#### Bridge Line Not Generated

**Symptom:** `docker exec tor-bridge bridge-line --address 203.0.113.42` returns empty

**Cause:** Bootstrap not complete or obfs4 not configured

**Solution:**
```bash
# Check bootstrap status
docker exec tor-bridge status

# Should show "Bootstrap: 100% (done)"

# Check if lyrebird (obfs4) is running
docker exec tor-bridge pgrep lyrebird

# Check obfs4 state file
docker exec tor-bridge cat /var/lib/tor/pt_state/obfs4_state.json

# Wait 5 minutes after 100% bootstrap, then try again
docker exec tor-bridge bridge-line --address 203.0.113.42
```

### Rollback Procedure

If migration fails or you want to revert:

> 🔐 This historical backup/cleanup command is retired. Follow the encrypted create → verify → staged restore procedure in the current backup guide.


### Security Notes

**The script is safe because:**
- ✅ Stops containers before modifying data
- ✅ Creates backups before making changes
- ✅ Validates each step before proceeding
- ✅ Never deletes volumes (only fixes ownership)
- ✅ Preserves old container until you confirm success
- ✅ Uses official Alpine image for ownership fixes

**What to verify after migration:**
- Container is running: `docker ps | grep tor-bridge`
- Tor is bootstrapped: `docker exec tor-bridge status`
- Fingerprint unchanged: Compare with your saved fingerprint
- Bridge line works: Test obfs4 connection from client
- Logs are clean: `docker logs tor-bridge` should show no errors
- Tor Metrics updated (24h): Check bridge appears on metrics.torproject.org

### Additional Resources

- **Main Documentation:** [../../docs/MIGRATION-V1.1.X.md](../../docs/MIGRATION-V1.1.X.md)
- **FAQ:** [../../docs/FAQ.md](../../docs/FAQ.md) - See "How do I migrate from the official Tor Project bridge image?"
- **Architecture:** [../../docs/ARCHITECTURE.md](../../docs/ARCHITECTURE.md) - Understanding UID/GID differences
- **Deployment Guide:** [../../docs/DEPLOYMENT.md](../../docs/DEPLOYMENT.md) - Post-migration deployment options

### Support

If you encounter issues:

1. **Check logs:** `docker logs tor-bridge`
2. **Run diagnostics:** `docker exec tor-bridge status`
3. **Verify volume:** `docker run --rm -v <volume>:/data alpine:3.24.2 ls -la /data`
4. **Check FAQ:** See docs/FAQ.md for common issues
5. **Review architecture:** See docs/ARCHITECTURE.md for technical details

### Contributing

Found a bug or have a suggestion? Open an issue or pull request on GitHub.

### License

Same license as the main project (see repository root LICENSE file).
