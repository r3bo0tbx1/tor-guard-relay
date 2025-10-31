# Security Policy 🔒
SPDX-License-Identifier: MIT

## Scope

This policy covers the **Tor Guard Relay** Docker image, scripts, and workflows in this repository.  
Issues related to the Tor network itself should be reported directly to [The Tor Project](https://www.torproject.org/).

---

## Supported Versions

We actively support the following versions with security updates:

| Version | Supported | Status |
|----------|------------|--------|
| 1.0      | ✅ | Current stable release |
| < 1.0    | ❌ | Pre-release versions |

---

## Security Updates

- Security patches are released as soon as possible after discovery.  
- Critical vulnerabilities are prioritized.  
- Weekly automated builds include the latest Alpine and Tor security updates.  
- Subscribe to [GitHub Releases](https://github.com/r3bo0tbx1/tor-guard-relay/releases) for notifications.

### Automated Hardening

To reduce patch-lag risk, GitHub Actions automatically:
1. Pulls the latest Alpine base image.
2. Installs the latest Tor package.
3. Applies security patches.
4. Rebuilds multi-architecture images.
5. Publishes to GHCR.

These rebuilds include Alpine CVE patches and Tor security fixes without changing functionality.

---

## Reporting a Vulnerability

**Do NOT report security vulnerabilities through public GitHub issues.**

### How to Report

**Email:** r3bo0tbx1@brokenbotnet.com  
**Subject:** `[SECURITY] Tor Guard Relay – <short summary>`  
Please use my PGP [0xB3BD6196E1CFBFB4 🔑](https://keys.openpgp.org/vks/v1/by-fingerprint/33727F5377D296C320AF704AB3BD6196E1CFBFB4) to encrypt if your report contains sensitive technical details.

### Information to Include
1. **Description** of the vulnerability.  
2. **Steps to reproduce** the issue.  
3. **Impact assessment** (who is affected, what's at risk).  
4. **Suggested fix** (if you have one).  
5. **Your contact information** for follow-up.

### What to Expect
- **Acknowledgment:** within 48 hours  
- **Initial assessment:** within 1 week  
- **Status updates:** every 2 weeks until resolved  

**Resolution timelines**
| Severity | Response Time |
|-----------|----------------|
| Critical | 1 to 7 days |
| High | 1 to 4 weeks |
| Medium | 1 to 3 months |
| Low | Next release cycle |

### Coordinated Disclosure

We follow responsible disclosure practices:
1. **Report received** → We acknowledge and investigate.  
2. **Fix developed** → We create and test a patch.  
3. **Coordinated release** → We agree on disclosure timing.  
4. **Public disclosure** → We release the fix and advisory.  
5. **Credit given** → We acknowledge the reporter (unless anonymity is requested).

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
````

#### Contact Information

```conf
# Use a dedicated email for relay operations
ContactInfo tor-relay@example.com <0xPGP_FINGERPRINT>

# Optionally include abuse contact
ContactInfo your-email proof:uri-rsa abuse:abuse@example.com
```

#### Network Security

```bash
# Firewall rules (UFW example)
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 9001/tcp  # ORPort
sudo ufw allow 22/tcp    # SSH (be careful!)
sudo ufw enable

# Regular security updates
apt update && apt upgrade -y   # Ubuntu/Debian
yum update -y                  # RHEL/CentOS
```

#### Monitoring

```bash
# Log monitoring
docker logs guard-relay 2>&1 | grep -iE "(error|warn|critical)"

# Scheduled health checks
0 */6 * * * docker exec guard-relay relay-status >> /var/log/relay-check.log

# Resource monitoring
docker stats guard-relay --no-stream
```

---

### For Contributors

#### Code Security

* Never commit secrets or API keys.
* Use `.gitignore` for sensitive files.
* Review dependencies for vulnerabilities.
* Follow the principle of least privilege.
* Validate all user inputs.

#### Docker Security

```dockerfile
# Always specify explicit base version
FROM alpine:edge  # Pinned dynamically in CI for latest security patches

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
* ⚠️ Can bind to any host port

**Mitigations:**

* Drops unnecessary capabilities
* Uses `no-new-privileges:true`
* Only grants required capabilities
* Relies on proper firewall configuration

### Volume Permissions

**What:** Persistent volumes store keys and state.
**Security Impact:** Keys live in `/var/lib/tor`; protect them from unauthorized access.

**Mitigation:**

```bash
# Check volume permissions
docker volume inspect tor-guard-data

# The container automatically sets:
chmod 700 /var/lib/tor
chown tor:tor /var/lib/tor
```

### Configuration Exposure

**What:** Configuration is mounted from the host.
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

### Weekly Security Updates

To ensure ongoing hardening, CI automatically:

1. Pulls latest Alpine base.
2. Installs updated Tor.
3. Applies available patches.
4. Rebuilds and republishes to GHCR.

Enable automatic updates in Cosmos:

```json
"cosmos-auto-update": "true",
"cosmos-auto-update-notify": "true"
```

---

## Compliance & Legal

### Tor Network Participation

Running a Tor relay is legal in most countries, but:

* ⚠️ Check local laws and ISP terms of service.
* ⚠️ Understand exit vs. guard relay differences.
* ⚠️ Keep contact information accurate.

**This project runs GUARD relays (not exit relays) by default.**

### Data Handling

* Tor relays do **not** log traffic content.
* Relay fingerprints are public.
* Contact information and bandwidth statistics are public.

### Abuse Handling

If you receive abuse complaints:

1. Verify it’s actually your relay.
2. Review Tor Project [abuse response templates](https://community.torproject.org/relay/community-resources/eff-tor-legal-faq/).
3. Respond professionally.
4. Consider your legal position.
5. Join [tor-relays mailing list](https://lists.torproject.org/cgi-bin/mailman/listinfo/tor-relays) for help.

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