# Security Policy 🔒
SPDX-License-Identifier: MIT

> [!IMPORTANT]
> 🧅 **v2.2.0 release candidate:** Tor must be **0.4.9.14 or newer**. Current-run health, validated configuration and encrypted recovery are described in the [release notes](docs/releases/v2.2.0.md). Recreate from the validated image to update Tor; changing torrc alone does not upgrade the binary.

## Scope

This policy covers the **Tor Guard Relay** Docker image, scripts, and workflows in this repository.
Issues related to the Tor network itself should be reported directly to [The Tor Project](https://www.torproject.org/).

---

## Supported Versions

Only the latest published release receives maintenance. v2.2.0 is the prepared candidate; confirm its actual publication before upgrading. Historical tags remain useful as recorded rollback material, not supported targets.

| Version | Status |
| --- | --- |
| Latest published release | ✅ Supported |
| v2.2.0 candidate | 🧪 Locally validated; publication is a separate gate |
| Older releases | 📜 Historical / unsupported |

---

## Recent Security Advisories

### [CVE-2026-54909](https://github.com/advisories/GHSA-34rh-wp3j-6cxc) (Pion STUN / Lyrebird)

- Affects `github.com/pion/stun/v3` versions through v3.1.4. Affected Lyrebird builds link the vulnerable v3.0.0 release through Snowflake and Pion ICE.
- When the STUN/ICE parsing path is used, a malformed `XOR-MAPPED-ADDRESS` attribute can remotely trigger a panic and denial of service. The normal obfs4 server path does not exercise this code, but the vulnerable component remains linked into the Lyrebird binary.
- Remediation is **image-level**: stable and edge builds now explicitly update Pion STUN to v3.1.5 or later when compiling Lyrebird.
- Fix status: prepared for the next patch release. The current stable version remains v2.1.0 until that release is published.

### [CVE-2026-31789](https://nvd.nist.gov/vuln/detail/CVE-2026-31789) (OpenSSL / Alpine package)

- Affects vulnerable OpenSSL package ranges in Alpine-based images.
- Fix target for this project is `openssl >= 3.5.6-r0` via base image/package refresh and rebuild.
- Mitigation is **image-level**: pull updated image tags after release.

### [CVE-2026-31431](https://nvd.nist.gov/vuln/detail/CVE-2026-31431) ("Copy Fail" Linux kernel)

- This is a Linux kernel vulnerability and is in CISA KEV.
- Mitigation is primarily **host-level**: update/pin host kernels using your distro or cloud vendor guidance.
- Pulling a new container image does **not** patch an unpatched host kernel.

---

## 🔒 Network Security Model

### Ultra-Minimal Port Exposure

**This project follows an ultra-minimal security architecture:**

- ✅ **NO monitoring HTTP endpoints** - Removed for maximum security
- ✅ **NO exposed metrics ports** - All monitoring via `docker exec` only
- ✅ **Only Tor protocol ports exposed** - ORPort (configurable), obfs4 (bridge mode), DirPort (disabled)
- ✅ **~variant-dependent image size image** - Minimal attack surface

### Public Port Exposure (Configurable)

**Ports exposed depend on relay mode and configuration:**

#### Guard/Middle Relay Mode:
```
PUBLIC PORTS:
  TOR_ORPORT   (default: 9001)  →  Tor ORPort (relay traffic)
  TOR_DIRPORT                   →  Directory service (optional, disabled by default)
```

#### Exit Relay Mode:
```
PUBLIC PORTS:
  TOR_ORPORT   (default: 9001)  →  Tor ORPort (relay traffic)
  TOR_DIRPORT                   →  Directory service (optional, disabled by default)
```

#### Bridge Relay Mode:
```
PUBLIC PORTS:
  TOR_ORPORT      (default: 9001)  →  Tor ORPort (relay traffic)
  TOR_OBFS4_PORT  (default: 9002)  →  obfs4 pluggable transport
```

**All port numbers are fully configurable via environment variables.**

### No Monitoring Ports

**ZERO exposed monitoring services:**

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
docker exec tor-relay gen-auth      # Generate Control Port hash
docker exec tor-relay gen-family    # Generate/view Happy Family key (Tor 0.4.9.2-alpha or later)
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
- ✅ Minimal Alpine Linux base (~variant-dependent image size)
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
- Disabled DirPort: Not necessary unless you operate a Directory Authority
- Exposed obfs4 port: Only in bridge mode (configurable)
- NO other services are accessible (internal or external)

### Port Exposure Best Practices

#### ✅ Secure Configuration (Recommended)

```bash
# Docker CLI with host networking (recommended)
docker run -d \
  --name tor-relay \
  --network host \
  --security-opt no-new-privileges:true \
  --restart unless-stopped \
  -v $(pwd)/relay.conf:/etc/tor/torrc:ro \
  -v tor-guard-data:/var/lib/tor \
  -v tor-guard-logs:/var/log/tor \
  r3bo0tbx1/onion-relay:latest # or ghcr.io/r3bo0tbx1/onion-relay:latest
```

```yaml
# Docker Compose with host networking
services:
  tor-relay:
    image: r3bo0tbx1/onion-relay:latest
    container_name: tor-relay
    restart: unless-stopped
    network_mode: host
    volumes:
      - ./relay.conf:/etc/tor/torrc:ro
      - tor-guard-data:/var/lib/tor
      - tor-guard-logs:/var/log/tor
```

### External Monitoring Access

External monitoring is used for maximum security and minimal image size:

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
sudo ufw enable

# iptables
sudo iptables -A INPUT -p tcp --dport 9001 -j ACCEPT
sudo iptables -A INPUT -j DROP

# firewalld (RHEL/CentOS)
sudo firewall-cmd --permanent --add-port=9001/tcp
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
sudo ufw allow <TOR_ORPORT>/tcp  # guard/exit only
sudo ufw allow <TOR_OBFS4_PORT>/tcp  # bridge only
```

---

## Security Updates

## 🏷️ Supported versions

Only the latest **published** release receives maintenance and scheduled rebuilds. The latest published release remains v2.1.0 while this checkout prepares v2.2.0. Publication of v2.2.0 ends support for earlier releases; historic tags remain available for reproducibility.

## 🚨 Urgent Tor update

[Tor 0.4.9.14](https://forum.torproject.org/t/security-release-0-4-9-14/22241) addresses high-severity issues affecting clients, onion services, authorities and relays. Update as soon as possible. Detailed issue tickets were initially withheld under upstream's disclosure policy; do not infer undisclosed exploit details.

Both Dockerfiles enforce Tor >= 0.4.9.14. Operators must recreate the container from a validated updated image to replace Tor; torrc edits and SIGHUP do not update binaries.

## 📦 Dependency policy

Stable Alpine 3.24.2 and Go 1.27.2 are pinned by digest. Lyrebird source is pinned and its Go module graph is checked in. Pion STUN is 3.1.7, above the 3.1.5 security floor for [CVE-2026-54909](https://github.com/advisories/GHSA-34rh-wp3j-6cxc). The actual transport binary is inspected during candidate validation.

OpenSSL's installed libssl3 must be at least 3.5.9. Container updates do not patch the host kernel; operators remain responsible for host security updates.

Scans block all HIGH/CRITICAL image vulnerabilities, including unfixed findings, and secrets. Go source analysis separately blocks known reachable vulnerabilities even without a severity label or fixed version. It uses the same pinned source/lock/toolchain and proves that the analyzed transport matches the candidate bytes. Full reports and SBOMs remain release evidence, including findings outside that blocking policy. The local module scan reports [GO-2026-5932](https://pkg.go.dev/vuln/GO-2026-5932), an unfixed advisory about deprecated x/crypto OpenPGP packages; assess package inclusion instead of calling the whole module clean.

Renovate proposes reviewed Lyrebird source pins and independent Go dependency updates. Compatible dependency fixes need not wait for Lyrebird upstream to update its graph. Base/toolchain/source/Go proposals have no weekly update window; security fixes get expedited review and a patch release after validation. Pins remain explicit, and source updates are not auto-merged.

The read-only security workflow analyzes current source and rescans published architecture digests in both registries every six hours, on relevant main changes and by manual dispatch. Complete results are retained for 30 days. Subscribe to Actions failure notifications; the workflow does not send third-party messages. Scheduling and advisory ingestion are not instantaneous, and scanners cannot guarantee detection of every vulnerability. See the [security response procedure](scripts/release/README.md#expedited-security-response).

## 🛡️ Runtime boundary

The image runs as UID 100/GID 101 with Tini and POSIX shell diagnostics. Deployment examples restrict capabilities and use no-new-privileges. Host networking shares the host network namespace; configure firewall and provider rules deliberately.

Mounted torrc files remain authoritative. Generated config is validated before atomic replacement. Diff output redacts every value; validation suppresses raw configuration diagnostics by default. Explicit debug mode may expose details, so review logs privately.

Prepare persistent-volume ownership yourself. Startup cannot silently heal arbitrary host permissions. Keep keys, family material, pt_state and active config together in encrypted recovery. Offline or external master keys need separate custody.

## 🚦 Release gates

All stable/edge AMD64/ARM64 candidates must pass behavior, component floors and security checks before promotion. Promotion loads the validated images and checks their identity; it does not rebuild. Scheduled rebuilds use the latest released tag with current reviewed main security policy. Source and policy SHAs are recorded independently. Pin updates and new features require a reviewed source release.

An available fix for an applicable security issue should proceed through expedited validation and release, without waiting for the routine schedule. An unfixed issue still requires assessment and mitigation; severe image findings or reachable Go findings remain blockers. This checkout contains no automatic security exception mechanism.

Cleanup is manual and separate from validation. Preserve a rollback image, deployment and verified encrypted backup before upgrading.

## 📣 Reporting a Vulnerability

**Do NOT report security vulnerabilities through public GitHub issues.**

For harassment, privacy violations in community spaces or other conduct concerns,
use the private [Code of Conduct reporting process](CODE_OF_CONDUCT.md#-reporting-a-concern).
Use this security process for technical vulnerabilities; if an incident involves
both, explain that in your private report so it can be assessed together.

### How to Report

**Email:** r3bo0tbx1@brokenbotnet.com
**Subject:** `[SECURITY] Tor Guard Relay – <short summary>`

Please use my PGP key [0xB3BD6196E1CFBFB4 🔑](https://brokenbotnet.com/0xB3BD6196E1CFBFB4.asc) to encrypt if your report contains sensitive technical details.

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

## 🔐 Operator responsibilities

- Restrict configuration, key and recovery-identity access; keep private material out of Git and diagnostic reports.
- Validate staged recovery before replacing live data; never activate duplicate identities.
- Treat readiness, public reachability and consensus membership as separate evidence.
- Expose control ports only with deliberate authentication and access restrictions.
- Review [legal considerations](docs/LEGAL.md) before running an exit.

## 📬 Contact

Security: [r3bo0tbx1@brokenbotnet.com](mailto:r3bo0tbx1@brokenbotnet.com). General questions: [project discussions](https://github.com/r3bo0tbx1/tor-guard-relay/discussions).


The following network, disclosure and operator guidance remains part of this policy.

---

## Reporting a Vulnerability

**Do NOT report security vulnerabilities through public GitHub issues.**

### How to Report

**Email:** r3bo0tbx1@brokenbotnet.com
**Subject:** `[SECURITY] Tor Guard Relay – <short summary>`

Please use my PGP key [0xB3BD6196E1CFBFB4 🔑](https://brokenbotnet.com/0xB3BD6196E1CFBFB4.asc) to encrypt if your report contains sensitive technical details.

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
# CIISS v3 format (recommended) - generate at https://torcontactinfogenerator.netlify.app/
ContactInfo email:tor-relay[]example.com url:https://example.com proof:uri-familyid-ed25519 pgp:EF6E286DDA85EA2A4BA7DE684E2C6E8793298290 ciissversion:3

# With abuse contact (recommended for exits)
ContactInfo email:tor-relay[]example.com abuse:abuse[]example.com url:https://example.com proof:uri-familyid-ed25519 ciissversion:3
```

> 📝 **CIISS v3:** The [ContactInfo Information Sharing Specification](https://nusenu.github.io/ContactInfo-Information-Sharing-Specification/) provides a machine-readable, verifiable format. The `proof:uri-familyid-ed25519` method lets tools verify your relay ownership by checking `https://your-domain/.well-known/tor-relay/ed25519-family-id.txt` for your Happy Family ID (Tor 0.4.9.2-alpha or later).

#### Network Security

```bash
# Regular security updates
apt update && apt upgrade -y   # Ubuntu/Debian
yum update -y                  # RHEL/CentOS

# Verify firewall rules
sudo ufw status numbered
sudo iptables -L -n -v

# Pull latest security-patched image
docker pull r3bo0tbx1/onion-relay:latest
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
FROM alpine:3.24.2  # Pinned version for reproducibility

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

**What‼️:** Container uses `--network host`

**Why ⁉️:** Enables Tor dual-stack (IPv4 + IPv6) support and eliminates NAT overhead

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
* Ultra-minimal Alpine base (~variant-dependent image size)
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
* ✅ Minimal base image (Alpine Linux ~variant-dependent image size)
* ✅ Drops all capabilities, adds only required ones
* ✅ Read-only configuration mount
* ✅ Automatic permission healing
* ✅ Configuration validation on startup
* ✅ NO exposed monitoring HTTP endpoints
* ✅ Busybox-only tools (no bash/python dependencies)
* ✅ Smart healthcheck.sh for Docker health checks
* ✅ Input validation for all ENV variables
* ✅ OBFS4V_* whitelist to prevent command injection

### Multi-Mode Support

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

🛡️ Scheduled rebuilds use the latest reviewed release tag with current reviewed security policy. Source and lock changes need a new reviewed tag; a rebuild does not automatically move a pinned source revision.

Renovate proposes compatible source, toolchain/base and direct/indirect Go updates. Applicable fixes follow the [expedited response procedure](scripts/release/README.md#expedited-security-response). Read-only six-hour monitoring detects newly disclosed image/package and source findings; it does not patch running relays.

---

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

echo "🔒 Tor Guard Relay Security Audit"
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

*Last Updated: 2026-08-02 | Current Stable: 2.1.0*
