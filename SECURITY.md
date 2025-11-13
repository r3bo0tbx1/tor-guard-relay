# Security Policy 🔒
SPDX-License-Identifier: MIT

## Scope

This policy covers the **Tor Guard Relay** Docker image, scripts, and workflows in this repository.
Issues related to the Tor network itself should be reported directly to [The Tor Project](https://www.torproject.org/).

---

## Supported Versions

We actively support the following versions with security updates:

| Version   | Status                | Support Level                               |
| --------- | --------------------- | ------------------------------------------- |
| **1.1.1** | 🟢 🛡️ **Active**     | Full support (current stable)               |
| **1.1.0** | 🟡 🔧 **Maintenance** | Security + critical fixes only              |
| **1.0.9** | 🟠 ⚠️ **Legacy**      | Security patches only – upgrade recommended |
| **1.0.8** | 🔴 ❌ **EOL**          | No support – upgrade immediately            |

---

## 🔒 Network Security Model

### Ultra-Minimal Port Exposure

**v1.1.1 follows an ultra-minimal security architecture:**

- ✅ **NO monitoring HTTP endpoints** - Removed for maximum security
- ✅ **NO exposed metrics ports** - All monitoring via `docker exec` only
- ✅ **Only Tor protocol ports exposed** - ORPort, DirPort (configurable), obfs4 (bridge mode)
- ✅ **~20 MB image** - Minimal attack surface

### Public Port Exposure (Configurable)

**Ports exposed depend on relay mode and configuration:**

#### Guard/Middle Relay Mode:
```
PUBLIC PORTS:
  TOR_ORPORT   (default: 9001)  →  Tor ORPort (relay traffic)
  TOR_DIRPORT  (default: 9030)  →  Directory service (optional, set to 0 to disable)
```

#### Exit Relay Mode:
```
PUBLIC PORTS:
  TOR_ORPORT   (default: 9001)  →  Tor ORPort (relay traffic)
  TOR_DIRPORT  (default: 9030)  →  Directory service (optional, set to 0 to disable)
```

#### Bridge Relay Mode:
```
PUBLIC PORTS:
  TOR_ORPORT      (default: 9001)  →  Tor ORPort (relay traffic)
  TOR_OBFS4_PORT  (default: 9002)  →  obfs4 pluggable transport
```

**All port numbers are fully configurable via environment variables.**

### No Monitoring Ports

**v1.1.1 has ZERO exposed monitoring services:**

- ❌ No metrics HTTP endpoints
- ❌ No health check HTTP APIs
- ❌ No dashboard web interfaces
- ✅ All diagnostics via `docker exec` commands only

**Available diagnostic tools (container exec only):**
```bash
docker exec tor-relay status        # Health report with emojis
docker exec tor-relay health        # JSON health output
docker exec tor-relay fingerprint   # Display fingerprint
docker exec tor-relay bridge-line   # Get bridge line (bridge mode)
```

### Network Architecture

This project uses **host networking mode** (`--network host`) for best Tor performance:

**Why host networking?**
- ✅ **IPv6 Support** - Direct access to host's IPv6 stack
- ✅ **No NAT** - Tor binds directly to ports without translation
- ✅ **Better Performance** - Eliminates network overhead
- ✅ **Tor Recommended** - Follows Tor Project best practices

**Security with host networking:**
- ✅ Runs as non-root user (`tor` UID 100)
- ✅ Drops all capabilities, adds only required ones
- ✅ Uses `no-new-privileges:true`
- ✅ Minimal Alpine Linux base (~20 MB)
- ✅ No exposed monitoring ports
- ✅ Automatic permission healing

### Port Policy Rationale

**Why this matters:**
- ✅ **Minimizes attack surface** - Only Tor protocol ports exposed
- ✅ **No monitoring vulnerabilities** - Cannot attack what doesn't exist
- ✅ **Follows Tor best practices** - Standard relay configuration
- ✅ **Defense in depth** - Ultra-minimal design philosophy

**Security implications:**
- Exposed ORPort: Required for Tor relay operation (configurable)
- Exposed DirPort: Optional for directory service (can be disabled)
- Exposed obfs4 port: Only in bridge mode (configurable)
- NO other services are accessible (internal or external)

### Port Exposure Best Practices

#### ✅ Secure Configuration (Recommended)

```bash
# Docker CLI with host networking (recommended)
docker run -d \
  --name tor-relay \
  --network host \
  --restart unless-stopped \
  -v $(pwd)/relay.conf:/etc/tor/torrc:ro \
  -v tor-guard-data:/var/lib/tor \
  -v tor-guard-logs:/var/log/tor \
  ghcr.io/r3bo0tbx1/onion-relay:latest
```

```yaml
# Docker Compose with host networking
services:
  tor-relay:
    image: ghcr.io/r3bo0tbx1/onion-relay:latest
    container_name: tor-relay
    restart: unless-stopped
    network_mode: host
    volumes:
      - ./relay.conf:/etc/tor/torrc:ro
      - tor-guard-data:/var/lib/tor
      - tor-guard-logs:/var/log/tor
```

### External Monitoring Access

v1.1.1 uses external monitoring for maximum security and minimal image size:

#### Option 1: Docker Exec (Simplest)

```bash
# Check status
docker exec tor-relay status

# Get JSON health (raw)
docker exec tor-relay health

# Parse with jq (requires jq on host)
docker exec tor-relay health | jq .

# View fingerprint
docker exec tor-relay fingerprint
```

#### Option 2: JSON Health API Wrapper

Create your own HTTP wrapper if needed:

```python
#!/usr/bin/env python3
from flask import Flask, jsonify
import subprocess
import json

app = Flask(__name__)

@app.route('/health')
def health():
    result = subprocess.run(
        ['docker', 'exec', 'tor-relay', 'health'],
        capture_output=True,
        text=True
    )
    return jsonify(json.loads(result.stdout))

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=9100)  # Bind to localhost only!
```

#### Option 3: External Prometheus Exporter

Use dedicated Tor exporters for Prometheus integration:

```bash
# Use tor_exporter for detailed metrics
docker run -d --name tor-exporter \
  --network host \
  ghcr.io/atx/prometheus-tor_exporter:latest \
  --tor.control-address=127.0.0.1:9051
```

See [Monitoring Guide](docs/MONITORING.md) for complete integration examples.

### Firewall Configuration

**Recommended firewall rules for guard/middle relay:**

```bash
# UFW (Ubuntu/Debian)
sudo ufw default deny incoming
sudo ufw allow 9001/tcp  # ORPort (or your custom port)
sudo ufw allow 9030/tcp  # DirPort (optional, or your custom port)
sudo ufw enable

# iptables
sudo iptables -A INPUT -p tcp --dport 9001 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 9030 -j ACCEPT
sudo iptables -A INPUT -j DROP

# firewalld (RHEL/CentOS)
sudo firewall-cmd --permanent --add-port=9001/tcp
sudo firewall-cmd --permanent --add-port=9030/tcp
sudo firewall-cmd --reload
```

**For bridge mode:**

```bash
# UFW (Ubuntu/Debian)
sudo ufw allow 9001/tcp  # ORPort
sudo ufw allow 9002/tcp  # obfs4 port
```

**For custom ports:**

```bash
# Replace with your configured ports
sudo ufw allow <TOR_ORPORT>/tcp
sudo ufw allow <TOR_DIRPORT>/tcp  # guard/exit only
sudo ufw allow <TOR_OBFS4_PORT>/tcp  # bridge only
```

---

## Security Updates

- Security patches are released as soon as possible after discovery
- Critical vulnerabilities are prioritized
- Weekly automated builds include the latest Alpine and Tor security updates
- Subscribe to [GitHub Releases](https://github.com/r3bo0tbx1/tor-guard-relay/releases) for notifications

### Automated Hardening

To reduce patch-lag risk, GitHub Actions automatically:
1. Pulls the latest Alpine base image
2. Installs the latest Tor package
3. Applies security patches
4. Rebuilds multi-architecture images
5. Publishes to Docker Hub and GHCR

**Rebuild schedule:** Sundays at 18:30 UTC

These rebuilds include Alpine CVE patches and Tor security fixes without changing functionality.

---

## Reporting a Vulnerability

**Do NOT report security vulnerabilities through public GitHub issues.**

### How to Report

**Email:** r3bo0tbx1@brokenbotnet.com
**Subject:** `[SECURITY] Tor Guard Relay – <short summary>`

Please use my PGP key [0xB3BD6196E1CFBFB4 🔑](https://keys.openpgp.org/vks/v1/by-fingerprint/33727F5377D296C320AF704AB3BD6196E1CFBFB4) to encrypt if your report contains sensitive technical details.

### Information to Include

1. **Description** of the vulnerability
2. **Steps to reproduce** the issue
3. **Impact assessment** (who is affected, what's at risk)
4. **Suggested fix** (if you have one)
5. **Your contact information** for follow-up

### What to Expect

- **Acknowledgment:** within 48 hours
- **Initial assessment:** within 1 week
- **Status updates:** every 2 weeks until resolved

**Resolution timelines:**

| Severity | Response Time |
|-----------|----------------|
| Critical | 1-7 days |
| High | 1-4 weeks |
| Medium | 1-3 months |
| Low | Next release cycle |

### Coordinated Disclosure

We follow responsible disclosure practices:
1. **Report received** → We acknowledge and investigate
2. **Fix developed** → We create and test a patch
3. **Coordinated release** → We agree on disclosure timing
4. **Public disclosure** → We release the fix and advisory
5. **Credit given** → We acknowledge the reporter (unless anonymity is requested)

---

## Security Best Practices

### For Relay Operators

#### Configuration Security

```bash
# Secure your relay.conf file
chmod 600 /path/to/relay.conf
chown root:root /path/to/relay.conf

# Use read-only mounts
-v /path/to/relay.conf:/etc/tor/torrc:ro
```

#### Contact Information

```conf
# Use a dedicated email for relay operations
ContactInfo tor-relay@example.com <0xPGP_FINGERPRINT>

# Optionally include abuse contact
ContactInfo your-email proof:uri-rsa abuse:abuse@example.com
```

#### Network Security

```bash
# Regular security updates
apt update && apt upgrade -y   # Ubuntu/Debian
yum update -y                  # RHEL/CentOS

# Verify firewall rules
sudo ufw status numbered
sudo iptables -L -n -v

# Pull latest security-patched image
docker pull ghcr.io/r3bo0tbx1/onion-relay:latest
```

#### Monitoring

```bash
# Log monitoring
docker logs tor-relay 2>&1 | grep -iE "(error|warn|critical)"

# Health checks via diagnostic tools
docker exec tor-relay status

# JSON health check for automation (raw)
docker exec tor-relay health

# Parse with jq (requires jq on host)
docker exec tor-relay health | jq .

# Resource monitoring
docker stats tor-relay --no-stream
```

---

### For Contributors

#### Code Security

* Never commit secrets or API keys
* Use `.gitignore` for sensitive files
* Review dependencies for vulnerabilities
* Follow the principle of least privilege
* Validate all user inputs
* Use POSIX sh only (no bash dependencies)

#### Docker Security

```dockerfile
# Always specify explicit base version
FROM alpine:3.22.2  # Pinned version for reproducibility

# Run as non-root user
USER tor

# Use Docker security options
--security-opt no-new-privileges:true
--cap-drop ALL
--cap-add NET_BIND_SERVICE
--cap-add CHOWN
--cap-add SETUID
--cap-add SETGID
--cap-add DAC_OVERRIDE
```

#### Secret Management

```bash
# NEVER do this:
git add relay.conf  # Contains sensitive info!

# Instead:
echo "*.conf" >> .gitignore
echo "relay.conf" >> .gitignore
```

---

## Known Security Considerations

### Host Network Mode

**What:** Container uses `--network host`
**Why:** Enables Tor dual-stack (IPv4 + IPv6) support and eliminates NAT overhead

**Security Impact:**
* ✅ Container runs as non-root user (`tor` UID 100)
* ✅ Drops all capabilities, adds only required ones
* ✅ Uses `no-new-privileges:true`
* ✅ No exposed monitoring services
* ⚠️ Shares host network namespace (required for IPv6)
* ⚠️ Relies on firewall for port isolation

**Mitigations:**
* Drops all capabilities by default
* Adds only NET_BIND_SERVICE, CHOWN, SETUID, SETGID, DAC_OVERRIDE
* Uses `no-new-privileges:true`
* Ultra-minimal Alpine base (~20 MB)
* NO monitoring HTTP endpoints to attack
* Automatic permission healing
* Configuration validation before start

### Volume Permissions

**What:** Persistent volumes store keys and state
**Security Impact:** Keys live in `/var/lib/tor`; protect from unauthorized access

**Mitigation:**

```bash
# Check volume permissions
docker volume inspect tor-guard-data

# The container automatically sets:
chmod 700 /var/lib/tor
chown tor:tor /var/lib/tor
```

**UID/GID in Alpine:**
- `tor` user: UID 100, GID 101
- Different from Debian-based images (UID 101)
- Automatic permission healing on startup

### Configuration Exposure

**What:** Configuration is mounted from the host
**Impact:** May reveal bandwidth limits, ContactInfo, etc.

**Mitigation:**
* Use read-only mount (`:ro`)
* Set restrictive file permissions (600)
* Never commit configs to Git
* Sanitize before sharing

---

## Security Features

### Built-in Protections

* ✅ Non-root operation (user `tor` UID 100)
* ✅ Minimal base image (Alpine Linux ~20 MB)
* ✅ Drops all capabilities, adds only required ones
* ✅ Read-only configuration mount
* ✅ Automatic permission healing
* ✅ Configuration validation on startup
* ✅ NO exposed monitoring HTTP endpoints
* ✅ Busybox-only tools (no bash/python dependencies)
* ✅ Smart healthcheck.sh for Docker health checks
* ✅ Input validation for all ENV variables
* ✅ OBFS4V_* whitelist to prevent command injection

### Multi-Mode Support (v1.1.1)

The container supports three relay modes:

| Mode | Default Config | Security Risk |
|------|----------------|---------------|
| **guard** | Guard/middle relay | Low |
| **exit** | Exit relay | **HIGH** - Legal implications |
| **bridge** | obfs4 bridge | Low-Medium |

**Default:** Guard/middle relay (lowest risk)

**Changing modes:**
```bash
-e TOR_RELAY_MODE=guard   # Guard/middle relay (default)
-e TOR_RELAY_MODE=exit    # Exit relay (understand legal risks!)
-e TOR_RELAY_MODE=bridge  # obfs4 bridge
```

See [docs/MULTI-MODE.md](docs/MULTI-MODE.md) and [docs/LEGAL.md](docs/LEGAL.md) for details.

### Weekly Security Updates

To ensure ongoing hardening, CI automatically:
1. Pulls latest Alpine base (weekly)
2. Installs updated Tor package
3. Applies available security patches
4. Rebuilds for AMD64 + ARM64
5. Publishes to Docker Hub and GHCR

**Schedule:** Sundays at 18:30 UTC

Enable automatic updates in Cosmos:

```json
"cosmos-auto-update": "true",
"cosmos-auto-update-notify": "true"
```

---

## Compliance & Legal

### Tor Network Participation

Running a Tor relay is legal in most countries, but:
* ⚠️ Check local laws and ISP terms of service
* ⚠️ Understand guard vs. exit vs. bridge differences
* ⚠️ Keep contact information accurate
* ⚠️ Read [docs/LEGAL.md](docs/LEGAL.md) before deployment

**This project supports guard, exit, and bridge modes (configurable via TOR_RELAY_MODE).**

### Data Handling

* Tor relays do **not** log traffic content
* Relay fingerprints are public (guard/exit modes)
* Bridge fingerprints are NOT public (distributed via BridgeDB)
* Contact information and bandwidth statistics are public (guard/exit modes)

### Abuse Handling

If you receive abuse complaints:
1. Verify it's actually your relay
2. Review Tor Project [abuse response templates](https://community.torproject.org/relay/community-resources/eff-tor-legal-faq/)
3. Respond professionally
4. Consider your legal position
5. Join [tor-relays mailing list](https://lists.torproject.org/cgi-bin/mailman/listinfo/tor-relays) for help

---

## Security Resources

### Official Tor Resources

* [Tor Relay Guide](https://community.torproject.org/relay/)
* [Tor Security Documentation](https://support.torproject.org/)
* [Good/Bad Relays Criteria](https://community.torproject.org/relay/community-resources/good-bad-isps/)
* [EFF Tor Legal FAQ](https://community.torproject.org/relay/community-resources/eff-tor-legal-faq/)

### Docker Security

* [Docker Security Best Practices](https://docs.docker.com/engine/security/)
* [CIS Docker Benchmark](https://www.cisecurity.org/benchmark/docker)
* [OWASP Docker Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Docker_Security_Cheat_Sheet.html)

### Alpine Linux

* [Alpine Security](https://alpinelinux.org/security/)
* [Alpine Package Updates](https://pkgs.alpinelinux.org/packages)

---

## Network Security Audit

### Quick Security Checklist

```bash
#!/bin/bash
# security-audit.sh - Quick security audit for Tor Guard Relay

echo "🔒 Tor Guard Relay v1.1.1 Security Audit"
echo "==========================================="

# Check container is using host networking
echo ""
echo "1. Checking network mode..."
NETWORK_MODE=$(docker inspect tor-relay --format='{{.HostConfig.NetworkMode}}')
if [ "$NETWORK_MODE" = "host" ]; then
  echo "✅ Using host networking (recommended)"
else
  echo "⚠️  Not using host networking: $NETWORK_MODE"
fi

# Test Tor ports
echo ""
echo "2. Testing Tor port accessibility..."
PUBLIC_IP=$(curl -s https://icanhazip.com)
timeout 5 nc -zv $PUBLIC_IP 9001 && echo "✅ ORPort accessible" || echo "❌ ORPort not accessible"

# Verify diagnostic tools work
echo ""
echo "3. Testing diagnostic tools..."
docker exec tor-relay status > /dev/null 2>&1 && echo "✅ status tool works" || echo "❌ status tool failed"
docker exec tor-relay health > /dev/null 2>&1 && echo "✅ health tool works" || echo "❌ health tool failed"

# Check file permissions
echo ""
echo "4. Checking critical file permissions..."
docker exec tor-relay ls -la /var/lib/tor | grep -E "keys|fingerprint"

# Check process user
echo ""
echo "5. Checking process user..."
docker exec tor-relay ps aux | grep -E "^tor" | grep -v grep | head -1

# Check capabilities
echo ""
echo "6. Checking container capabilities..."
docker inspect tor-relay --format='{{.HostConfig.CapDrop}}' | grep -q "ALL" && echo "✅ All capabilities dropped" || echo "⚠️  Capabilities not fully restricted"

# Check volumes
echo ""
echo "7. Checking volume mounts..."
docker inspect tor-relay --format='{{range .Mounts}}{{.Source}} → {{.Destination}} ({{.Mode}}){{println}}{{end}}'

echo ""
echo "==========================================="
echo "✅ Audit complete!"
```

---

## Hall of Fame 🏆

Security researchers who responsibly disclose vulnerabilities will be listed here:

*No vulnerabilities reported yet.*

---

## Contact

* **Security Issues:** [r3bo0tbx1@brokenbotnet.com](mailto:r3bo0tbx1@brokenbotnet.com)
* **General Questions:** [GitHub Discussions](https://github.com/r3bo0tbx1/tor-guard-relay/discussions)
* **Project Maintainer:** rE-Bo0t.bx1

---

**Thank you for helping keep this project secure!** 🔒🧅

---

*Last Updated: 2025-11-13 | Version: 1.1.1*
