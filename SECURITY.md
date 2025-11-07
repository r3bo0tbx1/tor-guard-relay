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
| **1.1.0** | 🟢 🛡️ **Active**     | Full support (current stable)               |
| **1.0.9** | 🟡 🔧 **Maintenance** | Security + critical fixes only              |
| **1.0.8** | 🟠 ⚠️ **Legacy**      | Security patches only – upgrade recommended |
| **1.0.7** | 🔴 ❌ **EOL**          | No support – upgrade immediately            |

---

## 🔒 Network Security Model

### External Port Exposure

**CRITICAL: Only TWO ports should be exposed to the public internet:**

```
EXPOSED PORTS (Public):
  9001/tcp  →  Tor ORPort (Onion Router Port)
  9030/tcp  →  Tor DirPort (Directory Service Port)
```

**All other services MUST bind to localhost only (127.0.0.1)** for security:

```
INTERNAL SERVICES (Localhost Only):
  127.0.0.1:9035  →  Prometheus metrics endpoint
  127.0.0.1:9036  →  Health check API
  127.0.0.1:9037  →  Dashboard HTTP server
  127.0.0.1:9038+ →  Additional relay instances
```

### Network Architecture

This project follows a **two-tier port exposure model**:

#### 🌐 Public Ports (External Access Required)

- **9001** - ORPort (Tor relay traffic)
  - Must be publicly accessible
  - Firewall: Allow inbound TCP
  - Required for relay operation
  
- **9030** - DirPort (Directory service)
  - Should be publicly accessible
  - Optional but recommended
  - Reduces load on directory authorities

#### 🔒 Internal Ports (Localhost Only)

- **9035** - Metrics HTTP (Prometheus endpoint)
  - Bound to 127.0.0.1 by default
  - Access via: `docker exec` or localhost tunnel
  - ⚠️ Never expose without authentication

- **9036** - Health Check (Status API)
  - Bound to 127.0.0.1 by default
  - For monitoring systems only
  - ⚠️ Never expose without authentication

- **9037** - Dashboard HTTP (Web UI)
  - Bound to 127.0.0.1 by default
  - Access via: SSH tunnel or reverse proxy
  - ⚠️ Never expose without authentication

### Port Policy Rationale

**Why this matters:**
- ✅ **Minimizes attack surface** - Only Tor protocol ports exposed
- ✅ **Prevents unauthorized access** - Metrics/dashboards remain private
- ✅ **Follows Tor best practices** - Standard relay configuration
- ✅ **Defense in depth** - Additional layer beyond firewall rules

**Security implications:**
- Exposed ORPort (9001): Required for Tor relay operation
- Exposed DirPort (9030): Optional but recommended for directory service
- Internal metrics (9035+): Protected from external access
- No other services should be externally accessible

### Port Exposure Best Practices

#### ✅ Secure Configuration

```bash
# Docker CLI - Secure port mapping
docker run -d \
  --name tor-relay \
  -p 9001:9001 \
  -p 9030:9030 \
  -p 127.0.0.1:9035:9035 \
  -p 127.0.0.1:9036:9036 \
  ghcr.io/r3bo0tbx1/onion-relay:latest
```

```yaml
# Docker Compose - Secure port mapping
services:
  tor-relay:
    ports:
      - "9001:9001"              # Public - ORPort
      - "9030:9030"              # Public - DirPort
      - "127.0.0.1:9035:9035"    # Localhost - Metrics
      - "127.0.0.1:9036:9036"    # Localhost - Health
```

#### ❌ Insecure Configuration (DO NOT USE)

```bash
# ❌ BAD - Exposes monitoring without auth
docker run -p 0.0.0.0:9035:9035 ...

# ❌ BAD - Exposes all internal services
docker run -p 9035:9035 -p 9036:9036 ...

# ⚠️ USE WITH CAUTION - Host network mode
docker run --network host ...
# Only use if you understand implications and have proper firewall rules
```

### External Monitoring Access

If you need external access to metrics/health endpoints, use one of these secure methods:

#### Option 1: Reverse Proxy with Authentication (Recommended)

```nginx
# Nginx with HTTP Basic Auth
server {
    listen 443 ssl;
    server_name metrics.example.com;
    
    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;
    
    location /metrics {
        auth_basic "Restricted";
        auth_basic_user_file /etc/nginx/.htpasswd;
        proxy_pass http://127.0.0.1:9035;
    }
    
    location /health {
        auth_basic "Restricted";
        auth_basic_user_file /etc/nginx/.htpasswd;
        proxy_pass http://127.0.0.1:9036;
    }
}
```

#### Option 2: SSH Tunnel

```bash
# Forward remote metrics to local machine
ssh -L 9035:localhost:9035 user@relay-server
ssh -L 9036:localhost:9036 user@relay-server

# Access locally (no public exposure)
curl http://localhost:9035/metrics
curl http://localhost:9036/health
```

#### Option 3: VPN Access

- Deploy relay and monitoring in same VPN
- Access internal ports over encrypted VPN tunnel
- No public exposure required
- Recommended for multi-relay deployments

### Default Behavior Changes (v1.0.2)

Prior to v1.0.2, some tools defaulted to `0.0.0.0` (all interfaces). **As of v1.0.2:**

| Tool | Previous Default | New Default | Override |
|------|------------------|-------------|----------|
| dashboard | 0.0.0.0:8080 | 127.0.0.1:8080 | `DASHBOARD_BIND=0.0.0.0` |
| metrics-http | 0.0.0.0:9035 | 127.0.0.1:9035 | `METRICS_BIND=0.0.0.0` |

**Migration Note**: If you previously relied on external access without explicit configuration, you must now:

1. **Use environment variables** to bind to `0.0.0.0` (NOT recommended), OR
2. **Implement reverse proxy** with authentication (RECOMMENDED)

Example of override (only if you understand the security implications):

```bash
# NOT RECOMMENDED - Only use in trusted networks
docker run -d \
  -e METRICS_BIND=0.0.0.0 \
  -p 9035:9035 \
  ghcr.io/r3bo0tbx1/onion-relay:latest
```

### Firewall Configuration

**Recommended firewall rules:**

```bash
# UFW (Ubuntu/Debian)
sudo ufw default deny incoming
sudo ufw allow 9001/tcp  # ORPort
sudo ufw allow 9030/tcp  # DirPort (optional)
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

### Docker Network Mode

**Host networking (network_mode: host):**
- Used for dual-stack IPv4/IPv6 support
- Allows direct port binding without NAT
- Services still bind to 127.0.0.1 for internal access
- Container remains isolated (non-root user, dropped capabilities)

**Security measures when using host networking:**
- Non-root execution (runs as `tor` user)
- Capability restrictions (`--cap-drop ALL`)
- No new privileges (`--security-opt no-new-privileges:true`)
- Minimal Alpine base image
- Automatic permission healing

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
5. Publishes to GHCR

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

#### Port Security Configuration

```bash
# Verify only required ports are exposed
docker ps --format "table {{.Names}}\t{{.Ports}}"

# Expected output should show ONLY:
# 0.0.0.0:9001->9001/tcp
# 0.0.0.0:9030->9030/tcp

# Check internal services bind to localhost
docker exec guard-relay netstat -tlnp | grep -E "9035|9036|9037"
# Should show 127.0.0.1:PORT only

# Test external accessibility (should fail for metrics)
curl -m 5 http://YOUR_PUBLIC_IP:9035/metrics
# Should timeout or be refused

# Test internal accessibility (should work from container)
docker exec guard-relay curl -s http://127.0.0.1:9035/metrics
# Should return Prometheus metrics
```

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
```

#### Monitoring

```bash
# Log monitoring
docker logs guard-relay 2>&1 | grep -iE "(error|warn|critical)"

# Scheduled health checks
0 */6 * * * docker exec guard-relay status >> /var/log/relay-check.log

# Resource monitoring
docker stats guard-relay --no-stream

# Port accessibility audit
docker exec guard-relay net-check
```

---

### For Contributors

#### Code Security

* Never commit secrets or API keys
* Use `.gitignore` for sensitive files
* Review dependencies for vulnerabilities
* Follow the principle of least privilege
* Validate all user inputs

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
**Why:** Enables Tor dual-stack (IPv4 + IPv6) support

**Security Impact:**
* ✅ Container cannot access other containers
* ✅ Runs as non-root user (`tor`)
* ⚠️ Shares host network namespace
* ⚠️ Can bind to any host port (mitigated by localhost binding)

**Mitigations:**
* Drops unnecessary capabilities
* Uses `no-new-privileges:true`
* Only grants required capabilities
* Internal services bind to 127.0.0.1 only
* Relies on proper firewall configuration

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

### Configuration Exposure

**What:** Configuration is mounted from the host  
**Impact:** May reveal bandwidth limits, ContactInfo, etc.

**Mitigation:**
* Use read-only mount (`:ro`)
* Set restrictive file permissions (600)
* Never commit configs
* Sanitize before sharing

---

## Security Features

### Built-in Protections

* ✅ Non-root operation (user `tor`)
* ✅ Minimal base image (Alpine Linux)
* ✅ Drops unnecessary capabilities
* ✅ Read-only configuration mount
* ✅ Automatic permission healing
* ✅ Configuration validation on startup
* ✅ Localhost-only binding for internal services

### Port Binding Security

**External (public) services:**
```
ORPort 9001          # Binds to 0.0.0.0:9001
ORPort [::]:9001     # Binds to [::]:9001 (IPv6)
DirPort 9030         # Binds to 0.0.0.0:9030
```

**Internal (localhost-only) services:**
```
metrics-http binds to 127.0.0.1:9035
health API binds to 127.0.0.1:9036
dashboard binds to 127.0.0.1:9037
```

### Weekly Security Updates

To ensure ongoing hardening, CI automatically:
1. Pulls latest Alpine base
2. Installs updated Tor
3. Applies available patches
4. Rebuilds and republishes to GHCR

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
* ⚠️ Understand exit vs. guard relay differences
* ⚠️ Keep contact information accurate

**This project runs GUARD relays (not exit relays) by default.**

### Data Handling

* Tor relays do **not** log traffic content
* Relay fingerprints are public
* Contact information and bandwidth statistics are public

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
echo "=================================="

# Check exposed ports
echo ""
echo "1. Checking exposed ports..."
docker ps --format "table {{.Names}}\t{{.Ports}}" | grep guard-relay

# Check internal service bindings
echo ""
echo "2. Checking internal service bindings..."
docker exec guard-relay netstat -tlnp 2>/dev/null | grep -E "9035|9036|9037" || echo "No internal services detected"

# Test external accessibility
echo ""
echo "3. Testing external port accessibility..."
PUBLIC_IP=$(curl -s https://icanhazip.com)
timeout 5 nc -zv $PUBLIC_IP 9001 && echo "✅ ORPort 9001 accessible" || echo "❌ ORPort 9001 not accessible"
timeout 5 nc -zv $PUBLIC_IP 9030 && echo "✅ DirPort 9030 accessible" || echo "⚠️  DirPort 9030 not accessible"

# Test metrics should NOT be externally accessible
echo ""
echo "4. Testing metrics port (should NOT be accessible externally)..."
timeout 5 curl -s http://$PUBLIC_IP:9035/metrics && echo "❌ SECURITY ISSUE: Metrics exposed!" || echo "✅ Metrics properly secured"

# Check file permissions
echo ""
echo "5. Checking critical file permissions..."
docker exec guard-relay ls -la /var/lib/tor | grep -E "keys|fingerprint"

# Check user
echo ""
echo "6. Checking process user..."
docker exec guard-relay ps aux | grep tor | head -1

# Check capabilities
echo ""
echo "7. Checking container capabilities..."
docker inspect guard-relay --format='{{.HostConfig.CapDrop}}' | grep -q "ALL" && echo "✅ All capabilities dropped" || echo "⚠️  Capabilities not fully restricted"

echo ""
echo "=================================="
echo "Audit complete!"
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

*Last Updated: 2025-11-05 | Version: 1.1.0*