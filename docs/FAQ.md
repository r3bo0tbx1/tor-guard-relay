# ❓ Frequently Asked Questions (FAQ)

Common questions about Tor Guard Relay deployment, configuration, and troubleshooting.

---

## 📋 Table of Contents

- [General](#-general)
- [Deployment & Configuration](#-deployment--configuration)
- [Relay Operation](#-relay-operation)
- [Troubleshooting](#-troubleshooting)
- [Migration](#-migration)
- [Security & Legal](#-security--legal)

---

## 🌐 General

### What is this project?

**Tor Guard Relay** is a production-ready Docker container for running Tor relays. It supports three relay types:
- **Guard/Middle relay** - First hop in Tor circuits (default)
- **Exit relay** - Last hop (requires legal preparation)
- **Bridge relay** - Helps users bypass censorship (obfs4 support)

Built on Alpine Linux 3.22.2 with a minimal 20MB image size, busybox-only tools, and weekly automated security rebuilds.

### What makes this different from the official Tor images?

| Feature | This Project | Official Images |
|---------|--------------|-----------------|
| **Image size** | ~17.1 MB | ~100+ MB |
| **Base** | Alpine 3.22.2 | Debian |
| **Diagnostics** | 4 busybox tools + JSON API | None |
| **Multi-mode** | Guard/Exit/Bridge in one image | Separate images |
| **Weekly rebuilds** | ✅ Automated | ❌ Manual |
| **ENV configuration** | ✅ Full support | Limited |
| **Official bridge naming** | ✅ Drop-in compatible | N/A |

### Is this production-ready?

**Yes.** Current version is v1.1.1 (Active/Stable). Used in production with:
- ✅ Security-hardened (32 vulnerabilities fixed in v1.1.1)
- ✅ Non-root execution (tor user, UID 100)
- ✅ Weekly automated rebuilds with latest Tor + Alpine patches
- ✅ Multi-architecture support (AMD64, ARM64)
- ✅ Comprehensive documentation (11 guides)

---

## 🚀 Deployment & Configuration

### How do I choose between ENV variables and mounted config file?

**Use ENV variables if:**
- ✅ Simple guard/middle/bridge setup
- ✅ Standard port configuration
- ✅ Basic bandwidth limits
- ✅ Quick deployment is priority

**Use mounted config file if:**
- ✅ Complex exit policies
- ✅ Advanced Tor options not in OBFS4V_* whitelist
- ✅ Multiple ORPort addresses (IPv4 + IPv6)
- ✅ Production deployment requiring full control

**Example ENV-based deployment:**
```bash
docker run -d \
  --name tor-relay \
  --network host \
  -e TOR_RELAY_MODE=guard \
  -e TOR_NICKNAME=MyGuardRelay \
  -e TOR_CONTACT_INFO="admin@example.com" \
  -e TOR_ORPORT=9001 \
  -e TOR_DIRPORT=9030 \
  -v tor-data:/var/lib/tor \
  ghcr.io/r3bo0tbx1/onion-relay:latest
```

**Example mounted config:**
```bash
docker run -d \
  --name tor-relay \
  --network host \
  -v /path/to/relay.conf:/etc/tor/torrc:ro \
  -v tor-data:/var/lib/tor \
  ghcr.io/r3bo0tbx1/onion-relay:latest
```

### What's the difference between TOR_* and official bridge naming?

Both work identically - we support two naming conventions for compatibility:

**TOR_* Naming (Our Standard):**
```bash
TOR_RELAY_MODE=bridge
TOR_NICKNAME=MyBridge
TOR_CONTACT_INFO=admin@example.com
TOR_ORPORT=9001
TOR_OBFS4_PORT=9002
```

**Official Tor Project Naming (Drop-in Compatible):**
```bash
NICKNAME=MyBridge
EMAIL=admin@example.com
OR_PORT=9001
PT_PORT=9002  # Auto-detects bridge mode!
```

**Key difference:** Setting `PT_PORT` automatically enables bridge mode (no need for `TOR_RELAY_MODE=bridge`).

### What's the difference between RelayBandwidthRate and BandwidthRate?

**RelayBandwidthRate/Burst (Recommended):**
- Limits **relay traffic only** (connections between Tor nodes)
- Directory requests and other Tor infrastructure traffic NOT limited
- Best for relays to avoid degrading directory service

**BandwidthRate/Burst (Global):**
- Limits **ALL Tor traffic** (relay + directory + everything)
- Can slow down your relay's ability to serve directory information
- Use only if you need strict total bandwidth control

**ENV variables always use RelayBandwidthRate:**
```bash
TOR_BANDWIDTH_RATE="50 MBytes"    # → RelayBandwidthRate in torrc
TOR_BANDWIDTH_BURST="100 MBytes"  # → RelayBandwidthBurst in torrc
```

**In mounted config, you choose:**
```conf
# Option 1 (recommended):
RelayBandwidthRate 50 MBytes
RelayBandwidthBurst 100 MBytes

# Option 2 (global limit):
BandwidthRate 50 MBytes
BandwidthBurst 100 MBytes
```

### Can I use OBFS4V_* variables with spaces (like "1024 MB")?

**Yes**, as of v1.1.1! The busybox regex bug was fixed (docker-entrypoint.sh:309-321).

**This now works:**
```bash
OBFS4_ENABLE_ADDITIONAL_VARIABLES=1
OBFS4V_MaxMemInQueues=1024 MB
OBFS4V_AddressDisableIPv6=0
OBFS4V_NumCPUs=4
```

**Prior to v1.1.1**, spaces caused "dangerous characters" errors. Update to v1.1.1+ if experiencing this issue.

### What ports need to be publicly accessible?

**Guard/Middle Relay:**
- `TOR_ORPORT` (default: 9001) - **PUBLIC**
- `TOR_DIRPORT` (default: 9030) - **PUBLIC** (optional, set to 0 to disable)

**Exit Relay:**
- `TOR_ORPORT` (default: 9001) - **PUBLIC**
- `TOR_DIRPORT` (default: 9030) - **PUBLIC**

**Bridge Relay:**
- `TOR_ORPORT` (default: 9001) - **PUBLIC**
- `TOR_OBFS4_PORT` (default: 9002) - **PUBLIC**

**No monitoring ports exposed** - all diagnostics via `docker exec` only (security by design).

**Firewall example (UFW):**
```bash
# Guard relay
sudo ufw allow 9001/tcp
sudo ufw allow 9030/tcp

# Bridge relay
sudo ufw allow 9001/tcp
sudo ufw allow 9002/tcp
```

---

## 🧅 Relay Operation

### Why is my relay not appearing on Tor Metrics?

**Expected timeline:**
| Milestone | Time | What to Check |
|-----------|------|---------------|
| Bootstrap complete | 10-30 min | `docker exec tor-relay status` shows 100% |
| Appears on metrics | 1-2 hours | Search https://metrics.torproject.org/rs.html |
| First statistics | 24-48 hours | Bandwidth graphs appear |
| Guard flag | 8+ days | Relay trusted for entry connections |

**Troubleshooting:**
1. **Check bootstrap:** `docker exec tor-relay status`
   - Must show "Bootstrapped 100%"
2. **Check reachability:** Logs should show "Self-testing indicates your ORPort is reachable"
3. **Verify firewall:** Ports must be accessible from outside your network
4. **Check logs:** `docker logs tor-relay | grep -i error`
5. **Verify fingerprint exists:** `docker exec tor-relay fingerprint`

**Still not showing?**
- Wait 24-48 hours (Tor network consensus updates slowly)
- Ensure ExitRelay is 0 for guard relays (not publishing as exit)
- Check `PublishServerDescriptor 1` in config

### How do I get my bridge line?

**After 24-48 hours**, run:
```bash
docker exec tor-bridge bridge-line
```

**Output format:**
```
Bridge obfs4 <IP>:<PORT> <FINGERPRINT> cert=<CERT> iat-mode=0
```

**Alternative methods:**
```bash
# Read directly from file
docker exec tor-bridge cat /var/lib/tor/pt_state/obfs4_bridgeline.txt

# Search logs
docker logs tor-bridge | grep "bridge line"
```

**Share your bridge:**
- ✅ Share with people you trust
- ❌ **DO NOT** publish publicly (defeats censorship circumvention)
- Users can also get bridges from https://bridges.torproject.org/

### Why is my relay using very little bandwidth?

**This is normal for new relays!** Tor network builds trust slowly.

**Typical bandwidth progression:**
- **Week 1-2:** Almost no traffic (building reputation)
- **Week 3-4:** Gradual increase as directory consensus includes you
- **Week 5-8:** Significant traffic increase
- **8+ days:** May receive Guard flag (massive traffic increase)

**Factors affecting bandwidth:**
1. **Relay age** - New relays are untrusted
2. **Uptime percentage** - Must maintain 99%+ for Guard flag
3. **Relay flags** - Guard, Fast, Stable flags increase usage
4. **Configured bandwidth** - Tor won't exceed your limits
5. **Exit policy** - Exit relays typically get more traffic

**Not a bug** - be patient and maintain high uptime!

---

## 🔧 Troubleshooting

### Container won't start - "Permission denied" errors

**Problem:** `Directory /var/lib/tor cannot be read: Permission denied`

**Cause:** Volume ownership mismatch (usually when migrating from Debian-based images)

**Fix:**
```bash
# Alpine uses UID 100 (tor user)
docker run --rm -v tor-data:/data alpine:3.22.2 chown -R 100:101 /data

# Verify fix
docker run --rm -v tor-data:/data alpine:3.22.2 ls -ldn /data
# Should show: drwx------ X 100 101 ...
```

**Prevent in future:** Always use same image consistently (don't switch between official and this image without migration).

### "OBFS4V_MaxMemInQueues: dangerous characters" error

**Problem:** Bridge configuration rejected with this error (values with spaces)

**Cause:** Bug in v1.1.0 and earlier - busybox regex incompatibility

**Fix:** **Update to v1.1.1+**
```bash
docker pull ghcr.io/r3bo0tbx1/onion-relay:latest
docker stop tor-bridge
docker rm tor-bridge
docker run ...  # Recreate with new image
```

**Verify fix:**
```bash
docker exec tor-bridge cat /build-info.txt
# Should show: Version: 1.1.1 or later

# Verify OBFS4V variables work
docker exec tor-bridge cat /etc/tor/torrc | grep MaxMemInQueues
# Should show: MaxMemInQueues 1024 MB (if variable was set)
```

### Why does TOR_RELAY_MODE say "guard" when I set PT_PORT?

**Problem:** Log shows guard mode but you expected bridge mode

**Cause:** Running old image (< v1.1.1) without PT_PORT auto-detection

**Fix:** Update to v1.1.1+ where PT_PORT automatically enables bridge mode:
```bash
# v1.1.1+ auto-detects bridge mode from PT_PORT
docker run -d \
  --name tor-bridge \
  --network host \
  -e PT_PORT=9002 \  # Auto-enables bridge mode!
  -e NICKNAME=MyBridge \
  -e EMAIL=admin@example.com \
  -v tor-data:/var/lib/tor \
  ghcr.io/r3bo0tbx1/onion-relay:latest
```

**Verify:**
```bash
docker logs tor-bridge | grep "Relay mode"
# Should show: 🎯 Relay mode: bridge
```

### How do I restart vs recreate a container?

**CRITICAL:** Many issues arise from restarting old containers instead of recreating with new image.

**Wrong (uses old image):**
```bash
docker stop tor-relay
docker pull ghcr.io/r3bo0tbx1/onion-relay:latest  # Downloads new image
docker start tor-relay  # ❌ Still uses OLD image!
```

**Correct (uses new image):**
```bash
docker stop tor-relay
docker rm tor-relay  # Remove old container
docker pull ghcr.io/r3bo0tbx1/onion-relay:latest  # Download new image
docker run -d --name tor-relay ...  # ✅ New container with new image
```

**Verify which image container is using:**
```bash
# Get container's image ID
docker inspect tor-relay --format='{{.Image}}'

# Get current image ID
docker images ghcr.io/r3bo0tbx1/onion-relay:latest --format='{{.ID}}'

# IDs must match!
```

---

## 🔄 Migration

### How do I migrate from thetorproject/obfs4-bridge?

**Official image → This image migration:**

1. **Backup your data:**
```bash
docker run --rm -v obfs4-data:/data -v /tmp:/backup \
  alpine tar czf /backup/tor-backup.tar.gz /data
```

2. **Fix UID/GID (REQUIRED):**
```bash
# Official image: UID 101 (debian-tor)
# Our image: UID 100 (tor)
docker run --rm -v obfs4-data:/data alpine:3.22.2 chown -R 100:101 /data
```

3. **Update configuration:**
```bash
# Change ONLY the image name - keep same ENV variables!
# Old:
# image: thetorproject/obfs4-bridge:latest

# New:
image: ghcr.io/r3bo0tbx1/onion-relay:latest
```

4. **Recreate container:**
```bash
docker stop obfs4-bridge
docker rm obfs4-bridge
docker run -d \
  --name obfs4-bridge \
  --network host \
  -e OR_PORT=9001 \
  -e PT_PORT=9002 \
  -e EMAIL=admin@example.com \
  -e NICKNAME=MyBridge \
  -v obfs4-data:/var/lib/tor \  # Same volume!
  ghcr.io/r3bo0tbx1/onion-relay:latest
```

5. **Verify fingerprint unchanged:**
```bash
docker exec obfs4-bridge fingerprint
# Must match your old fingerprint!
```

**See:** [MIGRATION.md](MIGRATION.md) for complete guide

### How do I upgrade from v1.1.0 to v1.1.1?

**Guard/Exit relays (no changes required):**
```bash
docker pull ghcr.io/r3bo0tbx1/onion-relay:latest
docker stop tor-relay
docker rm tor-relay
docker run -d --name tor-relay ...  # Same config
```

**Bridge relays (OBFS4V fix applies):**
- Same process as above
- OBFS4V_* variables with spaces now work correctly
- No config changes needed

**Verify upgrade:**
```bash
docker exec tor-relay cat /build-info.txt
# Should show: Version: 1.1.1

docker exec tor-relay fingerprint
# Verify fingerprint unchanged
```

---

## 🔒 Security & Legal

### Is it legal to run a Tor relay?

**Generally yes**, but depends on jurisdiction and relay type:

**Guard/Middle Relay:**
- ✅ Legal in most countries
- ✅ Traffic is encrypted (you can't see content)
- ✅ You're NOT the exit point
- ⚠️ Inform your ISP (recommended)

**Exit Relay:**
- ⚠️ **Legal but complex** - requires preparation
- ⚠️ Your IP associated with exit traffic
- ⚠️ You WILL receive abuse complaints
- ⚠️ Read [docs/LEGAL.md](LEGAL.md) **BEFORE** running exit relay

**Bridge Relay:**
- ✅ Legal in most countries
- ✅ Helps censored users
- ✅ Not published in main directory
- ⚠️ Check local laws on censorship circumvention tools

**Resources:**
- [EFF Tor Legal FAQ](https://community.torproject.org/relay/community-resources/eff-tor-legal-faq/)
- [Tor Project Legal Resources](https://community.torproject.org/relay/community-resources/)
- This project's [LEGAL.md](LEGAL.md)

### How secure is this container?

**Security features:**
- ✅ Non-root execution (tor user, UID 100, GID 101)
- ✅ Ultra-minimal image (~17.1 MB, Alpine 3.22.2)
- ✅ Busybox-only (no bash, python, or unnecessary binaries)
- ✅ No exposed monitoring ports (diagnostics via `docker exec` only)
- ✅ Weekly automated security rebuilds (Sundays 18:30 UTC)
- ✅ Tini init for proper signal handling
- ✅ Security-first template configurations (no-new-privileges, minimal caps)
- ✅ Comprehensive security audit (32 vulnerabilities fixed in v1.1.1)

**Security updates:**
- **Weekly rebuilds** pull latest Alpine + Tor patches
- **Same version tag** overwritten with updated packages (e.g., :1.1.1)
- **No package pinning** - always latest stable Tor from Alpine edge

**Verify security:**
```bash
# Check build info
docker exec tor-relay cat /build-info.txt

# Run security validation
./scripts/utilities/security-validation-tests.sh
```

### What data does the relay store?

**Persistent data in `/var/lib/tor`:**
- **Identity keys** - Your relay's cryptographic identity (CRITICAL - don't lose!)
- **State file** - Tor's runtime state
- **Cached directory** - Tor network consensus
- **Bridge credentials** - obfs4 state (bridge mode only)

**Logs in `/var/log/tor`:**
- **notices.log** - Tor operational logs
- **Rotated automatically** - No unbounded growth

**Container does NOT store:**
- ❌ User traffic content (encrypted)
- ❌ Websites visited through relay
- ❌ User IP addresses
- ❌ Browsing history

**Backup requirements:**
- **MUST backup:** `/var/lib/tor` (contains identity keys)
- **Optional:** Logs (for debugging only)

**See:** [BACKUP.md](BACKUP.md) for backup strategies

---

## 💡 Additional Resources

### Where can I find more help?

- **Documentation:** [docs/](../)
- **GitHub Issues:** https://github.com/r3bo0tbx1/tor-guard-relay/issues
- **GitHub Discussions:** https://github.com/r3bo0tbx1/tor-guard-relay/discussions
- **Tor Project Relay Guide:** https://community.torproject.org/relay/
- **Tor Metrics:** https://metrics.torproject.org/

### How can I contribute?

- 🧅 **Run a relay** - Strengthen the Tor network
- 🐛 **Report bugs** - Open issues on GitHub
- 📖 **Improve docs** - Fix typos, add examples, translate
- 💻 **Submit code** - Bug fixes, features, optimizations
- ⭐ **Star the repo** - Show support!

See [CONTRIBUTING.md](../CONTRIBUTING.md) for guidelines.

---

**Last Updated:** November 2025 (v1.1.1)
**Maintained by:** [@r3bo0tbx1](https://github.com/r3bo0tbx1)
