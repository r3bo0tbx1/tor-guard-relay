<a id="readme-top"></a>
<div align="center">

# 🧅 Tor Guard Relay

[![🚀✨ Build](https://github.com/r3bo0tbx1/tor-guard-relay/actions/workflows/release.yml/badge.svg)](https://github.com/r3bo0tbx1/tor-guard-relay/actions/workflows/release.yml)
[![Release](https://img.shields.io/github/v/release/r3bo0tbx1/tor-guard-relay?color=blue&label=version&labelColor=0a0a0a)](https://github.com/r3bo0tbx1/tor-guard-relay/releases/latest)
![Platforms](https://img.shields.io/badge/platforms-amd64%20%7C%20arm64-2ea44f?logo=docker&labelColor=0a0a0a)
[![Docker Hub](https://img.shields.io/docker/pulls/r3bo0tbx1/onion-relay?logo=docker&label=Docker%20Hub&labelColor=0a0a0a)](https://hub.docker.com/r/r3bo0tbx1/onion-relay)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?labelColor=0a0a0a)](LICENSE.txt)

<img src="src/logo.png" alt="Onion Bridge/Middle/Guard/Exit Relay" width="400"/>

**A hardened, production-ready Tor relay with built-in diagnostics and monitoring**

[Quick Start](#-quick-start) • [Features](#-key-features) • [Documentation](#-documentation) • [FAQ](docs/FAQ.md) • [Architecture](docs/ARCHITECTURE.md) • [Tools](#-diagnostic-tools) • [Contributing](#-contributing)

</div>

---

## 🚀 What is This?

**Tor Guard Relay** is a production-ready, self-healing Tor relay container designed for privacy advocates who want to contribute to the Tor network securely and efficiently.

> 🌉 **Multi-Mode:** guard, exit, and bridge with obfs4 transport. Configure via `TOR_RELAY_MODE`.

### Why Choose This Project?

- 🛡️ **Security-First** - Hardened Alpine Linux, non-root operation, and minimized port exposure
- 🪶 **Very light** - Ultra-minimal 16.8 MB image
- 🎯 **Simple** - One command to deploy, minimal configuration needed
- 📊 **Observable** - 6 busybox-only diagnostic tools with JSON health API
- 🌉 **Multi-Mode** - Supports guard, exit, and bridge (obfs4) relays
- 🔄 **Automated** - Weekly security rebuilds, CI/CD ready
- 📚 **Documented** - Comprehensive guides for deployment, monitoring, backup, and more
- 🏗️ **Multi-Arch** - Native support for AMD64 and ARM64 (Raspberry Pi, AWS Graviton, etc.)

---

## 🔒 Security Model

### Port Exposure Policy

- **9001** ORPort, public  
- **9030** DirPort, **Disabled (0)** by default
- **9002** obfs4 for bridge mode  

### Environment Variables

- `TOR_ORPORT` default 9001  
- `TOR_DIRPORT` default 0 (Disabled)
- `TOR_OBFS4_PORT` default 9002  

Diagnostics are run only through `docker exec`, with no exposed monitoring ports.

Minimal surface area, roughly 16.8 MB.

---

## ⚡ Quick Start

### System Requirements

| Component | Minimum | Recommended |
|----------|----------|-------------|
| CPU | 1 core | 2+ cores |
| RAM | 512 MB | 1 GB+ |
| Disk | 10 GB | 20 GB+ SSD |
| Bandwidth | 10 Mbps | 100+ Mbps |
| Uptime | 95 percent | 99 percent |
| Docker | 20.10+ | Latest |

**Supported Architectures:** AMD64, ARM64

### Network Security Notes

⚠️ **Port Exposure:**
- **Guard/Middle/Exit:** Port 9001 (ORPort) should be publicly accessible
- **Bridge:** Ports 9001 (ORPort) and 9002 (obfs4) should be publicly accessible
- **No monitoring ports** - all diagnostics via `docker exec` commands only
- Use `--network host` for best IPv6 support (Tor recommended practice)

### Interactive Quick Start (Recommended for Beginners)

**🚀 Try our interactive setup script:**

```bash
# Download and run the quick-start script
curl -fsSL https://raw.githubusercontent.com/r3bo0tbx1/tor-guard-relay/main/scripts/quick-start.sh -o quick-start.sh
chmod +x quick-start.sh
sh ./quick-start.sh
```

The script will:
- ✅ Guide you through relay type selection (guard, exit, bridge)
- ✅ Collect required information with validation
- ✅ Generate deployment commands or docker-compose.yml
- ✅ Provide next steps and monitoring guidance

### Manual Deployment

**Step 1:** Create your relay configuration (or use our [example](examples/relay-guard.conf)):

```bash
mkdir -p ~/tor-relay && cd ~/tor-relay
curl -o relay.conf https://raw.githubusercontent.com/r3bo0tbx1/tor-guard-relay/refs/heads/main/examples/relay-guard.conf
nano relay.conf
```

**Step 2:** Run (Docker Hub)

```bash
docker run -d \
  --name tor-relay \
  --restart unless-stopped \
  --network host \
  --security-opt no-new-privileges:true \
  -v $(pwd)/relay.conf:/etc/tor/torrc:ro \
  -v tor-guard-data:/var/lib/tor \
  -v tor-guard-logs:/var/log/tor \
  r3bo0tbx1/onion-relay:latest
```

**Step 3:** Verify it's running:

```bash
# Check status
docker exec tor-relay status

# View fingerprint
docker exec tor-relay fingerprint

# Stream logs
docker logs -f tor-relay
```

**That's it!** Your relay will bootstrap in 10-30 minutes and appear on [Tor Metrics](https://metrics.torproject.org/rs.html) within 1-2 hours.

> 📖 **Need more?** See our comprehensive [Deployment Guide](docs/DEPLOYMENT.md) for Docker Compose, Cosmos Cloud, Portainer, and advanced setups.

---

## 🎯 Choosing a Variant

We offer **two build variants** to match your risk tolerance and requirements:

### Stable Variant (Recommended)

**Base:** Alpine 3.23.3 | **Recommended for:** Production relays

- ✅ Battle-tested Alpine stable release
- ✅ Weekly automated rebuilds with latest security patches
- ✅ Proven stability for long-running relays
- ✅ Available on both **Docker Hub** and **GHCR**

```bash
# Pull from Docker Hub (easiest)
docker pull r3bo0tbx1/onion-relay:latest
docker pull r3bo0tbx1/onion-relay:1.1.7

# Pull from GHCR
docker pull ghcr.io/r3bo0tbx1/onion-relay:latest
docker pull ghcr.io/r3bo0tbx1/onion-relay:1.1.7
```

### Edge Variant (Testing Only)

**Base:** Alpine edge | **Recommended for:** Testing, security research

- ⚡ Bleeding-edge Alpine packages (faster security updates)
- ⚡ Latest Tor and obfs4 versions as soon as available
- ⚡ **More frequent rebuilds** - Every 3 days + weekly (~2-3x faster updates than stable)
- ⚠️ **NOT recommended for production** - less stable, potential breaking changes
- 📦 Available on both Docker Hub and GHCR

```bash
# Pull from Docker Hub
docker pull r3bo0tbx1/onion-relay:edge

# Pull from GHCR
docker pull ghcr.io/r3bo0tbx1/onion-relay:edge
docker pull ghcr.io/r3bo0tbx1/onion-relay:1.1.7-edge
```

**When to use edge:**
- 🔬 Testing new Tor features before stable release
- 🛡️ Security research requiring latest packages
- 🧪 Non-production test environments
- 🚀 Early adopters willing to accept potential breakage

**Stability comparison:**

| Feature | Stable | Edge |
|---------|--------|------|
| Production ready | ✅ Yes | ❌ No |
| Breaking changes | ❌ Rare | ⚠️ Possible |
| Security updates | Weekly | Every 3 days |
| Package versions | 3.23.3 | Bleeding edge |
| Docker Hub | ✅ Yes | ✅ Yes |
| GHCR | ✅ Yes | ✅ Yes |

> 💡 **Our recommendation:** Use **stable** for production relays, **edge** only for testing or when you specifically need the latest package versions.

---

## 🏗️ Deployment Methods

Choose the method that fits your workflow.

| Method | Best For | Guide |
|--------|----------|--------|
| 🐳 Docker CLI | Quick testing | [Guide](docs/DEPLOYMENT.md#method-1-docker-cli) |
| 📦 Docker Compose | Production | [Guide](docs/DEPLOYMENT.md#method-2-docker-compose) |
| ☁️ Cosmos Cloud | UI based deployment | [Guide](docs/DEPLOYMENT.md#method-3-cosmos-cloud) |
| 🎛️ Portainer | Web UI | [Guide](docs/DEPLOYMENT.md#method-4-portainer) |

**New to Docker?** Try [Cosmos Cloud](https://cosmos-cloud.io/) by [azukaar](https://github.com/azukaar) - a gorgeous, self-hosted Docker management platform.

### Multi-Relay Setup

Running multiple relays? We have templates for that:

- **Docker Compose:** [docker-compose-multi-relay.yml](templates/docker-compose-multi-relay.yml) - 3 relays setup
- **Cosmos Cloud:** [cosmos-compose-multi-relay.json](templates/cosmos-compose-multi-relay.json) - Multi-relay stack

See [Deployment Guide](docs/DEPLOYMENT.md) for complete instructions.

---

## 🔧 Diagnostic Tools

Six busybox-only diagnostic tools are included.

| Tool | Purpose | Usage |
|------|---------|--------|
| status | Full health report | `docker exec tor-relay status` |
| health | JSON health | `docker exec tor-relay health` |
| fingerprint | Show fingerprint | `docker exec tor-relay fingerprint` |
| bridge-line | obfs4 line | `docker exec tor-relay bridge-line` |
| gen-auth | Credentials for Nyx | `docker exec tor-relay gen-auth` |
| gen-family | Happy Family key gen | `docker exec tor-relay gen-family MyRelays` |

```bash
# Full health report with emojis
docker exec tor-relay status

# JSON output for automation/monitoring
docker exec tor-relay health
```

Example JSON:

```json
{
  "status": "up",
  "pid": 1,
  "uptime": "01:00:00",
  "bootstrap": 100,
  "reachable": "true",
  "errors": 0,
  "nickname": "MyRelay",
  "fingerprint": "1234567890ABCDEF"
}
```

> 📖 **Complete reference:** See [Tools Documentation](docs/TOOLS.md) for all 6 tools with examples, JSON schema, and integration guides.

---

## 📊 Monitoring and Observability

<br>
<div align="center">
  <img src="src/screenshots/nyx.png" alt="Nyx Monitor Interface"/>
</div>
<br>

**Real-time CLI monitoring and external observability** are supported for minimal image size and maximum security.

### Real-Time Monitoring (Nyx)

You can connect Nyx (formerly arm) to your relay securely using the Control Port.

1. Generate credentials: `docker exec tor-relay gen-auth`
2. Add the hash to your config
3. Connect via local socket or TCP

> 📖 **Full Setup:** See the [Control Port Guide](docs/CONTROL-PORT.md) for step-by-step Nyx configuration.

### JSON Health API

The `health` tool provides JSON output for monitoring integration:

```bash
# Get health status (raw JSON)
docker exec tor-relay health

# Parse with jq (requires jq installed on HOST machine)
docker exec tor-relay health | jq .

# Example cron-based monitoring
*/5 * * * * docker exec tor-relay health | jq '.status' | grep -q 'healthy' || alert
```

> **Note:** `jq` must be installed on your HOST machine (`apt install jq` / `brew install jq`), NOT in the container.

### Integration Examples

**Prometheus Node Exporter:**
```bash
# Use textfile collector (requires jq on host)
docker exec tor-relay health | jq -r '
  "tor_bootstrap_percent \(.bootstrap)",
  "tor_reachable \(if .reachable == "true" then 1 else 0 end)"
' > /var/lib/node_exporter/tor.prom
```

**Nagios/Icinga:**
```bash
#!/bin/bash
# Requires jq on host machine
HEALTH=$(docker exec tor-relay health)
STATUS=$(echo "$HEALTH" | jq -r '.status')
[ "$STATUS" = "healthy" ] && exit 0 || exit 2
```

> 📖 **Complete guide:** See [Monitoring Documentation](docs/MONITORING.md) for Prometheus, Grafana, alert integration, and observability setup.

---

## 🎯 Key Features

### Security & Reliability
- ✅ Non-root execution (runs as `tor` user)
- ✅ Ultra-minimal Alpine Linux base (**~16.8 MB**)
- ✅ Busybox-only tools (no bash/python dependencies)
- ✅ Automatic permission healing on startup
- ✅ Configuration validation before start
- ✅ Tini init for proper signal handling
- ✅ Graceful shutdown with cleanup

### Operations & Automation
- ✅ **6 busybox-only diagnostic tools** (status, health, fingerprint, bridge-line, gen-auth, gen-family)
- ✅ **JSON health API** for monitoring integration
- ✅ **Multi-mode support** (guard, exit, bridge with obfs4)
- ✅ **Happy Family support** (Tor 0.4.9+ key-based relay families)
- ✅ **ENV-based config** (TOR_RELAY_MODE, TOR_NICKNAME, TOR_FAMILY_ID, etc.)
- ✅ **Multi-architecture** builds (AMD64, ARM64)
- ✅ **Weekly security rebuilds** via GitHub Actions
- ✅ **Docker Compose templates** for single/multi-relay
- ✅ **Cosmos Cloud support** with one-click deploy
- ✅ **Automated Maintenance:** Keeps last 7 releases in registry

### Developer Experience
- ✅ Comprehensive documentation (8 guides)
- ✅ Example configurations included
- ✅ GitHub issue templates
- ✅ Automated dependency updates (Dependabot)
- ✅ CI/CD validation and testing
- ✅ Multi-arch support (same command, any platform)

---

## 🖼️ Gallery

| Cosmos Cloud Dashboard | Docker Logs (Bootstrapping) |
|:-----------------------:|:---------------------------:|
| ![Cosmos](src/screenshots/cosmos-dashboard.png) | ![Bootstrapping](src/screenshots/bootstrapping.png) |
| Relay Status Tool | Obfs4 Bridge Line |
| ![Relay](src/screenshots/relay-status.png) | ![Obfs4](src/screenshots/bridge-line.png) |

---

## 📚 Documentation

**Comprehensive documentation** organized by topic:

### Getting Started
- **[FAQ](docs/FAQ.md)** - ⭐ **NEW!** Frequently asked questions with factual answers
- **[Quick Start Script](scripts/utilities/quick-start.sh)** - ⭐ **NEW!** Interactive relay deployment wizard
- **[Migration Assistant](scripts/migration/migrate-from-official.sh)** - ⭐ **NEW!** Automated migration from thetorproject/obfs4-bridge
- **[Deployment Guide](docs/DEPLOYMENT.md)** - ✨ **UPDATED!** Complete installation for Docker CLI, Compose, Cosmos Cloud, and Portainer
- **[Migration Guide](docs/MIGRATION-V1.1.X.md)** - Upgrade to latest or migrate from other Tor setups

### Technical Reference
- **[Architecture](docs/ARCHITECTURE.md)** - ⭐ **NEW!** Technical architecture with Mermaid diagrams
- **[Tools Reference](docs/TOOLS.md)** - ✨ **UPDATED!** Complete guide to all 6 diagnostic tools
- **[Monitoring Guide](docs/MONITORING.md)** - ✨ **UPDATED!** External monitoring integration, JSON health API, alerts, and observability
- **[Control Port Guide](docs/CONTROL-PORT.md)** - ⭐ **NEW!** Authentication setup and Nyx integration
- **[Backup Guide](docs/BACKUP.md)** - Data persistence, recovery, and disaster planning
- **[Performance Guide](docs/PERFORMANCE.md)** - Optimization, tuning, and resource management

### Legal & Community
- **[Legal Considerations](docs/LEGAL.md)** - ✨ **UPDATED!** Legal aspects of running a Tor relay
- **[Documentation Index](docs/README.md)** - Complete documentation navigation

### Project Info
- **[Security Policy](SECURITY.md)** - Security practices and vulnerability reporting
- **[Contributing Guide](CONTRIBUTING.md)** - How to contribute to the project
- **[Code of Conduct](CODE_OF_CONDUCT.md)** - Community guidelines
- **[Changelog](CHANGELOG.md)** - Version history and changes

> 💡 **Tip:** Start with the [FAQ](docs/FAQ.md) for quick answers or [Documentation Index](docs/README.md) for complete navigation.

---

## 🛠️ Configuration

### Minimal Configuration

```ini
Nickname MyTorRelay
ContactInfo email:your-email[]example.com url:https://example.com proof:uri-rsa ciissversion:2
ORPort 9001
ORPort [::]:9001
DirPort 0
ExitRelay 0
SocksPort 0
DataDirectory /var/lib/tor
Log notice file /var/log/tor/notices.log
```

> 📝 **ContactInfo format:** We recommend the [ContactInfo Information Sharing Specification (CIISS) v2](https://nusenu.github.io/ContactInfo-Information-Sharing-Specification/), a machine-readable format that replaces `@` with `[]` and includes structured fields like `email:`, `url:`, `proof:`, `pgp:`, `hoster:`, and more. Use the [CIISS Generator](https://torcontactinfogenerator.netlify.app/) to create yours.

### Production Configuration

```ini
RelayBandwidthRate 50 MBytes
RelayBandwidthBurst 100 MBytes
NumCPUs 2
MaxMemInQueues 512 MB
ORPort [::]:9001
```

### Example Configurations

Examples are found in the [`examples/`](examples/) directory for complete, annotated configuration files:

- **[relay-guard.conf](examples/relay-guard.conf)** - Recommended production config
- Additional examples for specific use cases

> 📖 **Configuration help:** See [Deployment Guide](docs/DEPLOYMENT.md#configuration) for complete reference.

### Happy Family (Tor 0.4.9+)

Tor 0.4.9 introduces **Happy Families**, a cryptographic key-based replacement for `MyFamily`. Instead of listing every relay fingerprint in every relay's config, all relays in a family share one secret key.

**Why upgrade?**
- Eliminates huge `MyFamily` lists that waste bandwidth and memory
- Simpler to maintain - one key file instead of N×N fingerprint entries
- Required for future Arti Relay compatibility

#### Option A: Generate a new family key in Docker

Use this if you don't already have a family key from another setup.

```bash
# 1. Generate a family key (run on any ONE relay container)
docker exec tor-relay gen-family MyRelays

# 2. Note the FamilyId output - you need it for your torrc
#    FamilyId <value>

# 3. Copy the key to all your other relay containers
docker cp tor-relay:/var/lib/tor/keys/MyRelays.secret_family_key .
docker cp MyRelays.secret_family_key other-relay:/var/lib/tor/keys/

# 4. Fix ownership and permissions inside the target container
docker exec -u 0 other-relay chown 100:101 /var/lib/tor/keys/MyRelays.secret_family_key
docker exec -u 0 other-relay chmod 600 /var/lib/tor/keys/MyRelays.secret_family_key

# 5. Add FamilyId to each relay's torrc, then restart
docker restart tor-relay other-relay
```

#### Option B: Import an existing family key into Docker

Use this if you already generated a family key on a bare-metal or source-built Tor relay and want to use the same key for your Docker relays.

```bash
# 1. Transfer the .secret_family_key file to your Docker host
#    (via scp, sftp, or any secure method)
scp user@source-server:/var/lib/tor/keys/MyRelays.secret_family_key ~/tor-keys/

# 2. Copy the key into each running container (no restart needed yet)
docker cp ~/tor-keys/MyRelays.secret_family_key tor-relay:/var/lib/tor/keys/

# 3. Fix ownership and permissions inside the container
#    The tor user in the container runs as UID 100, GID 101
docker exec -u 0 tor-relay chown 100:101 /var/lib/tor/keys/MyRelays.secret_family_key
docker exec -u 0 tor-relay chmod 600 /var/lib/tor/keys/MyRelays.secret_family_key

# 4. Verify the key is in place
docker exec tor-relay ls -la /var/lib/tor/keys/MyRelays.secret_family_key

# 5. Add the FamilyId line to your torrc (same value from your source server)
#    FamilyId <your-family-id-value>
#    Keep your existing MyFamily lines during the transition period

# 6. Restart the container to pick up the config change
docker restart tor-relay
```

Repeat steps 2-6 for each container that should be in the family.

> **This is safe for running containers.** `docker cp` writes directly into the named Docker volume. Your relay identity keys, family key, and all data persist in the volume across container restarts, image updates, and `docker compose up --force-recreate`. Volumes are **only** deleted if you explicitly run `docker volume rm` or `docker compose down -v`.

#### Torrc configuration

During the transition period, configure **both** `FamilyId` and `MyFamily` in your torrc:

```ini
# Happy Family (Tor 0.4.9+)
FamilyId wweKJrJxUDs1EdtFFHCDtvVgTKftOC/crUl1mYJv830

# MyFamily (legacy - keep during transition)
MyFamily 9A2B5C7D8E1F3A4B6C8D0E2F4A6B8C0D2E4F6A8B
MyFamily 1F3E5D7C9B0A2F4E6D8C0B2A4F6E8D0C2B4A6F8E
```

The Tor Project will announce when `MyFamily` can be removed.

#### ENV-based config (alternative to mounted torrc)

```yaml
environment:
  TOR_FAMILY_ID: "wweKJrJxUDs1EdtFFHCDtvVgTKftOC/crUl1mYJv830"
  TOR_MY_FAMILY: "FINGERPRINT1,FINGERPRINT2,FINGERPRINT3"
```

#### Key persistence

The `.secret_family_key` file lives in `/var/lib/tor/keys/` inside your data volume. It persists across container restarts and image updates automatically.

| Scenario | Identity preserved? | Family key preserved? |
|----------|:---:|:---:|
| `docker restart` | ✅ | ✅ |
| `docker compose up --force-recreate` | ✅ | ✅ |
| `docker compose down` then `up` | ✅ | ✅ |
| `docker compose down -v` | ❌ | ❌ |
| `docker volume rm <volume>` | ❌ | ❌ |

> ⚠️ **Treat the `.secret_family_key` like a private key.** Anyone with this file can claim their relay belongs to your family. Back it up securely - losing it means regenerating for all relays.

> 📖 **Official docs:** [Tor Happy Family Guide](https://community.torproject.org/relay/setup/post-install/family-ids/)

---

## 🔍 Monitoring Your Relay

### Check Bootstrap Status

```bash
# Quick status
docker exec tor-relay status

# JSON output for automation (raw)
docker exec tor-relay health

# Parse specific field with jq (requires jq on host)
docker exec tor-relay health | jq .bootstrap
```

### View on Tor Metrics

After 1-2 hours, find your relay:

🔗 **[Tor Metrics Relay Search](https://metrics.torproject.org/rs.html)**

Search by:
- Nickname (e.g., "MyTorRelay")
- Fingerprint (get with `docker exec tor-relay fingerprint`)
- IP address

### Expected Timeline

| Milestone | Time | What to Expect |
|-----------|------|----------------|
| Bootstrap Complete | 10-30 min | Logs show "Bootstrapped 100%" |
| Appears on Metrics | 1-2 hours | Relay visible in search |
| First Statistics | 24-48 hours | Bandwidth graphs appear |
| Guard Flag | 8+ days | Trusted for entry connections |

> 🗳️ **How relay flags work:** Tor has **9 Directory Authorities** that vote every hour on relay flags (Guard, Stable, Fast, HSDir, etc.). A relay only receives a flag when **at least 5 of 9** authorities agree in the consensus. This is why flags take time - your relay must prove itself to a majority of independent authorities.

> 📖 **Detailed monitoring:** See [Monitoring Guide](docs/MONITORING.md) for complete observability setup with Prometheus and Grafana.

---

## 🐛 Troubleshooting

### Quick Diagnostics

```bash
# Check overall status
docker exec tor-relay status

# Check JSON health (raw)
docker exec tor-relay health

# View fingerprint
docker exec tor-relay fingerprint

# For bridge mode: Get bridge line
docker exec tor-relay bridge-line

# Generate Control Port hash
docker exec tor-relay gen-auth

# Generate/view Happy Family key
docker exec tor-relay gen-family MyRelays
docker exec tor-relay gen-family --show
```

### Common Issues

| Problem | Quick Fix |
|---------|-----------|
| Container won't start | Check logs: `docker logs tor-relay` |
| Permission / ownership errors | See **Bind Mount Ownership** below |
| ORPort not reachable | Verify firewall: `sudo ufw allow 9001/tcp` |
| Not on Tor Metrics | Wait 24h, verify bootstrap complete |
| Low/no traffic | Normal for new relays (2-8 weeks to build reputation) |

### Bind Mount Ownership

If you use **host bind mounts** (e.g. `-v /my/path:/var/lib/tor`) instead of named Docker volumes, the mounted directories must be owned by the container's `tor` user (**UID 100, GID 101**). Tor will refuse to start if directories have incorrect ownership.

**Symptoms:**
```
[warn] /var/lib/tor//keys is not owned by this user (tor, 100) but by <unknown> (99)
[warn] Failed to parse/validate config: Couldn't access private data directory "/var/lib/tor//keys"
```

**Fix - set correct ownership on the host:**
```bash
chown -R 100:101 /path/to/your/tor-data
chown -R 100:101 /path/to/your/tor-keys   # if mounted separately
```

> 💡 **Tip:** Named Docker volumes (e.g. `-v tor-guard-data:/var/lib/tor`) handle ownership automatically and avoid this issue entirely. We recommend using named volumes unless you have a specific reason to use bind mounts.

> 📖 **Full troubleshooting:** See [Tools Documentation](docs/TOOLS.md#troubleshooting) for detailed diagnostic procedures.

---

## 🏢 Architecture and Design

> 📐 **NEW:** See the complete [Architecture Documentation](docs/ARCHITECTURE.md) for detailed technical design with Mermaid diagrams covering:
> - Container lifecycle and initialization flow (6 phases)
> - ENV compatibility layer and configuration priority
> - Config generation for guard/exit/bridge modes with Happy Family support
> - OBFS4V security validation
> - Diagnostic tools architecture
> - Signal handling and graceful shutdown

### Flowchart

```mermaid
flowchart TB
    Start([🐳 docker run]) --> Init

    subgraph Init["⚙️ INITIALIZATION"]
        direction TB
        Check{"📄 Config File
        at /etc/tor/torrc?"}
        
        Check -->|✅ Mounted| Mount["📁 Use Mounted Config
        Full Tor Control"]
        Check -->|❌ No File| Env{"🌐 ENV Variables?
        NICKNAME + CONTACT_INFO"}
        
        Env -->|✅ Set| Generate["⚙️ Auto-Generate torrc
        from ENV Variables"]
        Env -->|❌ Missing| Error["❌ ERROR
        No Configuration Found"]
        
        Mount --> Validate
        Generate --> Validate
        Validate["🧪 Validate Config
        tor --verify-config"]
        Validate -->|❌ Invalid| Error
    end

    Init -->|✅ Valid Config| ModeSelect

    subgraph ModeSelect["🎯 RELAY MODE SELECTION"]
        direction LR
        Mode{TOR_RELAY_MODE}
        
        Mode -->|guard| Guard["🛡️ GUARD/MIDDLE
        ━━━━━━━━━━
        Routes Traffic
        ExitRelay 0
        DirPort Disabled"]
        Mode -->|exit| Exit["🚪 EXIT RELAY
        ━━━━━━━━━━
        Last Hop to Internet
        ExitRelay 1
        Custom Exit Policy"]
        Mode -->|bridge| Bridge["🌉 BRIDGE + obfs4
        ━━━━━━━━━━
        Censorship Resistant
        BridgeRelay 1
        Lyrebird Transport"]
    end

    Guard --> Running
    Exit --> Running
    Bridge --> Running

    Running(["🟢 TOR RELAY RUNNING"])
    
    Running --> Ops

    subgraph Ops["🛠️ OPERATIONS"]
        direction TB
        Tools["🔧 Diagnostic Tools
        via docker exec"]
        
        Tools --> Status["📊 status
        ━━━━━━━━━━
        Full Health Report
        Bootstrap Progress
        Reachability Status"]
        Tools --> Health["💚 health
        ━━━━━━━━━━
        JSON Health API
        For Monitoring Systems"]
        Tools --> Finger["🆔 fingerprint
        ━━━━━━━━━━
        Show Relay Identity
        Tor Metrics URL"]
        Tools --> BLine["🌉 bridge-line
        ━━━━━━━━━━
        Get obfs4 Bridge Line
        Share with Users"]
        Tools --> GenAuth["🔑 gen-auth
        ━━━━━━━━━━
        Generate Control
        Port Auth Data"]
        Tools --> GenFamily["👨‍👩‍👧 gen-family
        ━━━━━━━━━━
        Happy Family Key
        Generation & Import"]
    end

    Running -->|docker stop SIGTERM| Shutdown

    subgraph Shutdown["🧹 GRACEFUL SHUTDOWN"]
        direction TB
        Graceful["Close Circuits Cleanly
        Notify Directory Authorities
        Save State to Disk
        Exit Gracefully"]
    end

    Error --> End([⛔ Container Exits])
    Graceful --> End2([✅ Clean Stop])

    style Start fill:#4FC3F7,stroke:#0288D1,stroke-width:3px,color:#000
    style Running fill:#66BB6A,stroke:#388E3C,stroke-width:3px,color:#fff
    
    style Mount fill:#81C784,stroke:#388E3C,stroke-width:2px,color:#000
    style Generate fill:#81C784,stroke:#388E3C,stroke-width:2px,color:#000
    style Validate fill:#FFD54F,stroke:#F57C00,stroke-width:2px,color:#000
    style Error fill:#E57373,stroke:#C62828,stroke-width:3px,color:#fff
    
    style Guard fill:#64B5F6,stroke:#1976D2,stroke-width:2px,color:#000
    style Exit fill:#F06292,stroke:#C2185B,stroke-width:2px,color:#fff
    style Bridge fill:#BA68C8,stroke:#7B1FA2,stroke-width:2px,color:#fff
    
    style Status fill:#4DD0E1,stroke:#0097A7,stroke-width:2px,color:#000
    style Health fill:#4DD0E1,stroke:#0097A7,stroke-width:2px,color:#000
    style Finger fill:#4DD0E1,stroke:#0097A7,stroke-width:2px,color:#000
    style BLine fill:#4DD0E1,stroke:#0097A7,stroke-width:2px,color:#000
    style GenAuth fill:#4DD0E1,stroke:#0097A7,stroke-width:2px,color:#000
    style GenFamily fill:#4DD0E1,stroke:#0097A7,stroke-width:2px,color:#000
    
    style Graceful fill:#FFB74D,stroke:#F57C00,stroke-width:2px,color:#000
    style End fill:#E57373,stroke:#C62828,stroke-width:2px,color:#fff
    style End2 fill:#66BB6A,stroke:#388E3C,stroke-width:2px,color:#fff
    
    style Init fill:#FFF9C4,stroke:#F9A825,stroke-width:2px
    style ModeSelect fill:#E1BEE7,stroke:#8E24AA,stroke-width:2px
    style Ops fill:#B2EBF2,stroke:#00ACC1,stroke-width:2px
    style Shutdown fill:#FFCCBC,stroke:#E64A19,stroke-width:2px
```

### Why Host Network Mode?

This project uses `--network host` for important reasons:

- ✅ **IPv6 Support** - Direct access to host's IPv6 stack
- ✅ **No NAT** - Tor binds directly to ports without translation
- ✅ **Better Performance** - Eliminates network overhead
- ✅ **Tor Recommended** - Follows Tor Project best practices

**Security:** The container still runs as non-root with restricted permissions. Host networking is standard for Tor relays.

### Multi-Architecture Support

Docker automatically pulls the correct architecture:

```bash
# Same command works on:
# - x86_64 servers (pulls amd64)
# - Raspberry Pi (pulls arm64)
# - AWS Graviton (pulls arm64)
docker pull r3bo0tbx1/onion-relay:latest
```

Verify what you got:
```bash
docker exec tor-relay cat /build-info.txt | grep Architecture
```

---

## 🤝 Contributing

Contributions are welcome.

- 🐛 **Report bugs** via [GitHub Issues](https://github.com/r3bo0tbx1/tor-guard-relay/issues)
- 💡 **Suggest features** or improvements
- 📖 **Improve documentation** (typos, clarity, examples)
- 🔧 **Submit pull requests** (code, configs, workflows)
- ⭐ **Star the repository** to show support
- 🧅 **Run a relay** and strengthen the network!

### Development Setup

```bash
# Clone repository
git clone https://github.com/r3bo0tbx1/tor-guard-relay.git
cd tor-guard-relay

# Build locally
docker build -t tor-relay:dev .

# Test
docker run --rm tor-relay:dev status
```

See [Contributing Guide](CONTRIBUTING.md) for detailed instructions.

---

## 📦 Templates and Examples

All templates are in the [`templates/`](templates/) directory:

### Docker Compose
- [docker-compose.yml](templates/docker-compose/docker-compose.yml) - Single relay
- [docker-compose-multi-relay.yml](templates/docker-compose/docker-compose-multi-relay.yml) - 3 relays + monitoring

### Cosmos Cloud
- [cosmos-compose.json](templates/cosmos-compose/cosmos-compose.json) - Single relay
- [cosmos-compose-multi-relay.json](templates/cosmos-compose/cosmos-compose-multi-relay.json) - Multi-relay stack

### Tor Exit Notice
You can find them in [`templates/tor-exit-notice`](templates/tor-exit-notice) directory

### Monitoring
See [Monitoring Guide](docs/MONITORING.md) for external monitoring integration examples with Prometheus, Nagios, and other tools

### Configuration Examples
See [`examples/`](examples/) directory for relay configurations.

---

## 🔐 Security

### ⚠️ Version Deprecation Notice

> **All versions prior to v1.1.5 have been deprecated and removed from registries.** These versions were affected by **CVE-2025-15467** (OpenSSL, CVSS 9.8), a critical vulnerability in the OpenSSL library bundled through the Alpine base image. v1.1.5 patched this by upgrading to Alpine 3.23.3 (OpenSSL 3.5.5+). **If you are running any version older than v1.1.5, upgrade immediately:**
>
> ```bash
> docker pull r3bo0tbx1/onion-relay:latest
> ```

### Best Practices

✅ Store `relay.conf` with restricted permissions (`chmod 600`)  
✅ Never commit configs with sensitive info to Git  
✅ Use [CIISS v2](https://nusenu.github.io/ContactInfo-Information-Sharing-Specification/) format in ContactInfo for verification  
✅ Regularly update Docker image for security patches  
✅ Monitor logs for suspicious activity  
✅ Configure firewall properly  

### Security Policy

Found a vulnerability? See our [Security Policy](SECURITY.md) for responsible disclosure.

### Updates

Images are automatically rebuilt on separate schedules to include security patches:

**Stable Variant** (`:latest`)
- **Schedule:** Every Sunday at 18:30 UTC
- **Includes:** Latest Tor + Alpine 3.23.3 updates
- **Strategy:** Overwrites last release version (e.g., `:1.1.7`) with updated packages
- **Tags Updated:** `:latest` and version tags (e.g., `:1.1.7`)

**Edge Variant** (`:edge`)
- **Schedule:** Every 3 days at 12:00 UTC (independent schedule)
- **Includes:** Latest Tor + Alpine edge (bleeding-edge) updates
- **Strategy:** Overwrites last release version (e.g., `:1.1.7-edge`) with updated packages
- **Tags Updated:** `:edge` and version tags (e.g., `:1.1.7-edge`)
- **Frequency:** ~2-3x more frequent updates than stable

All images auto-published to Docker Hub and GitHub Container Registry

---

## 🌐 Resources

### Container Registries
- 🐳 [Docker Hub Repository](https://hub.docker.com/r/r3bo0tbx1/onion-relay)
- 📦 [GitHub Container Registry](https://github.com/r3bo0tbx1/tor-guard-relay/pkgs/container/onion-relay)

### Official Tor Project
- 📚 [Relay Setup Guide](https://community.torproject.org/relay/setup/)
- 💬 [Relay Operators Forum](https://forum.torproject.org/c/relay-operators)
- 📧 [Mailing List](https://lists.torproject.org/cgi-bin/mailman/listinfo/tor-relays)
- 📊 [Tor Metrics](https://metrics.torproject.org/)

### This Project
- 📖 [Documentation](docs/README.md)
- 🐛 [Issue Tracker](https://github.com/r3bo0tbx1/tor-guard-relay/issues)
- 💬 [Discussions](https://github.com/r3bo0tbx1/tor-guard-relay/discussions)
- 📦 [Container Registry](https://github.com/r3bo0tbx1/tor-guard-relay/pkgs/container/onion-relay)

---

## 📊 Project Status

<div align="center">

![Docker Hub Pulls](https://img.shields.io/docker/pulls/r3bo0tbx1/onion-relay?style=for-the-badge&logo=docker)
![GitHub Repo stars](https://img.shields.io/github/stars/r3bo0tbx1/tor-guard-relay?style=for-the-badge)
![GitHub Issues](https://img.shields.io/github/issues/r3bo0tbx1/tor-guard-relay?style=for-the-badge)

**Current Version:** v1.1.7 • **Status:** Production Ready  
**Image Size:** 16.8 MB • **Retention:** Last 7 Releases  
**Registries:** Docker Hub • GHCR  

</div>

---

## 📄 License

Project is licensed under the MIT License.  
See [License](LICENSE.txt) for full details.

---

## 🙏 Acknowledgments

- **The Tor Project** for maintaining the global privacy network  
- **Alpine Linux** for a minimal and secure base image  
- **azukaar** for Cosmos Cloud  
- **All relay operators** supporting privacy and anti-censorship worldwide

---

## 💖 Support the Project

This project is open source. Your support helps sustainability and improvements.

### Bitcoin (BTC)
```
bc1qltkajaswmzx9jwets8hfz43nkvred5w92syyq4
```

Or via **[AnonPay](https://trocador.app/anonpay?ticker_to=btc&network_to=Mainnet&address=bc1qltkajaswmzx9jwets8hfz43nkvred5w92syyq4&ref=sqKNYGZbRl&direct=True&name=rE-Bo0tbx1+%28r3bo0tbx1%29&description=Support+FOSS+Development&email=r3bo0tbx1%40brokenbotnet.com)** (convert any crypto)

### Monero (XMR)
```
45mNg5cG1S2B2C5dndJP65SSEXseHFVqFdv1N6paAraD1Jk9kQxQQArVcjfQmgCcmthrUF3jbNs74c5AbWqMwAAgAjDYzrZ
```
Or via **[AnonPay](https://trocador.app/anonpay?ticker_to=xmr&network_to=Mainnet&address=85ft7ehMfcKSSp8Ve92Y9oARmqvDjYvEiKQkzdp3qiyzP9dpLeJXFahgHcoXUPeE9TacqDCUXWppNffE3YDC1Wu1NnQ71rT&ref=sqKNYGZbRl&direct=True&name=rE-Bo0tbx1+%28r3bo0tbx1%29&description=Support+FOSS+Development&email=r3bo0tbx1%40brokenbotnet.com)** (convert any crypto)

### Other Ways to Support

- ⭐ Star the repo  
- 🐛 Report bugs  
- 💡 Suggest features  
- 📖 Improve documentation  
- 🤝 Submit patches  
- 🧅 Run a relay  

---

## ⭐ Star History

<div align="center">

<a href="https://www.star-history.com/#r3bo0tbx1/tor-guard-relay&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=r3bo0tbx1/tor-guard-relay&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=r3bo0tbx1/tor-guard-relay&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=r3bo0tbx1/tor-guard-relay&type=date&legend=top-left" />
 </picture>
</a>

</div>

---

<div align="center">

### Made with 💜 for a freer, uncensored internet

*Protecting privacy, one relay at a time* 🔁🧅✨

⭐ Star this repo if you find it useful!

🌍 [Support Internet Freedom](https://donate.torproject.org/)  
📚 [Documentation](docs/README.md)  
⬆ [Back to top](#readme-top)

</div>
