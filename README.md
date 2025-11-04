<a id="readme-top"></a>
<div align="center">

# 🧅 Tor Guard Relay

[![🧱 Build & Publish](https://github.com/r3bo0tbx1/tor-guard-relay/actions/workflows/build.yml/badge.svg)](https://github.com/r3bo0tbx1/tor-guard-relay/actions/workflows/release.yml)
[![Release](https://img.shields.io/github/v/release/r3bo0tbx1/tor-guard-relay?color=blue&label=version)](https://github.com/r3bo0tbx1/tor-guard-relay/releases/latest)
![Platforms](https://img.shields.io/badge/platforms-amd64%20%7C%20arm64-2ea44f?logo=docker)
![GHCR](https://img.shields.io/badge/GHCR-ghcr.io%2Fr3bo0tbx1%2Fonion--relay-blue?logo=github)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE.txt)

<img src="src/onion.png" alt="Onion diagram" width="400"/>

**A hardened, production-ready Tor relay with built-in diagnostics and monitoring**

[Quick Start](#-quick-start) • [Features](#-key-features) • [Documentation](#-documentation) • [Tools](#-diagnostic-tools) • [Contributing](#-contributing)

</div>

---

## 🚀 What is This?

**Tor Guard Relay** is a **production-ready, self-healing Tor relay container** designed for privacy advocates who want to contribute to the Tor network securely and efficiently.

> **🌉 Want to run a Tor Bridge instead?**  
> This project focuses on guard/middle relays. For bridge setup, visit the [Official Tor Bridge Guide](https://community.torproject.org/relay/setup/bridge/docker/)

### Why Choose This Project?

- 🛡️ **Security-First** - Hardened Alpine Linux, non-root operation, automatic permission healing
- 🎯 **Simple** - One command to deploy, minimal configuration needed
- 📊 **Observable** - 9 built-in diagnostic tools + Prometheus metrics
- 🔄 **Automated** - Weekly builds, auto-updates, CI/CD ready
- 📚 **Documented** - Comprehensive guides for deployment, monitoring, backup, and more
- 🏗️ **Multi-Arch** - Native support for AMD64 and ARM64 (Raspberry Pi, AWS Graviton, etc.)

---

## ⚡ Quick Start

### System Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| CPU | 1 core | 2+ cores |
| RAM | 512 MB | 1 GB+ |
| Disk | 10 GB | 20 GB+ SSD |
| Bandwidth | 10 Mbps | 100+ Mbps |
| Uptime | 95%+ | 99%+ |
| Docker | 20.10+ | Latest |

**Supported Architectures:** AMD64 (x86_64) • ARM64 (aarch64)

### Deploy in 30 Seconds

**Step 1:** Create your relay configuration (or use our [example](examples/relay.conf)):

```bash
# Create config directory
mkdir -p ~/tor-relay && cd ~/tor-relay

# Download example config
curl -O https://raw.githubusercontent.com/r3bo0tbx1/tor-guard-relay/main/examples/relay.conf

# Edit with your details
nano relay.conf
# Important: Set Nickname, ContactInfo, and bandwidth limits
```

**Step 2:** Run the relay:

```bash
docker run -d \
  --name tor-relay \
  --restart unless-stopped \
  --network host \
  -v $(pwd)/relay.conf:/etc/tor/torrc:ro \
  -v tor-guard-data:/var/lib/tor \
  -v tor-guard-logs:/var/log/tor \
  ghcr.io/r3bo0tbx1/onion-relay:latest
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

## 🏗️ Deployment Methods

Choose the method that fits your workflow:

| Method | Best For | Guide |
|--------|----------|-------|
| 🐳 **Docker CLI** | Quick testing, learning | [Guide](docs/DEPLOYMENT.md#method-1-docker-cli) |
| 📦 **Docker Compose** | Production, GitOps | [Guide](docs/DEPLOYMENT.md#method-2-docker-compose) |
| ☁️ **Cosmos Cloud** | Beautiful UI, beginners | [Guide](docs/DEPLOYMENT.md#method-3-cosmos-cloud) |
| 🎛️ **Portainer** | Web UI management | [Guide](docs/DEPLOYMENT.md#method-4-portainer) |

**New to Docker?** Try [Cosmos Cloud](https://cosmos-cloud.io/) by [azukaar](https://github.com/azukaar) - a gorgeous, self-hosted Docker management platform.

### Multi-Relay Setup

Running multiple relays? We have templates for that:

- **Docker Compose:** [docker-compose-multi-relay.yml](templates/docker-compose-multi-relay.yml) - 3 relays + Prometheus + Grafana
- **Cosmos Cloud:** [cosmos-compose-multi-relay.json](templates/cosmos-compose-multi-relay.json) - Full monitoring stack

See [Deployment Guide](docs/DEPLOYMENT.md) for complete instructions.

---

## 🔧 Diagnostic Tools

**v1.1 includes 9 production-ready diagnostic tools** - no external scripts needed!

### Quick Reference

| Tool | Purpose | Usage |
|------|---------|-------|
| **status** | Complete health report | `docker exec tor-relay status` |
| **fingerprint** | Display relay fingerprint | `docker exec tor-relay fingerprint` |
| **health** | JSON health check | `docker exec tor-relay health` |
| **metrics** | Prometheus metrics | `docker exec tor-relay metrics` |
| **dashboard** | HTML dashboard | `docker exec tor-relay dashboard` |
| **net-check** | Network diagnostics | `docker exec tor-relay net-check` |
| **view-logs** | Stream logs | `docker exec tor-relay view-logs` |
| **setup** | Config wizard | `docker exec -it tor-relay setup` |
| **metrics-http** | HTTP metrics server | Background service on port 9035 |

### Example: Quick Health Check

```bash
docker exec tor-relay status
```

**Output:**
```
🧅 Tor Relay Status Report
═══════════════════════════════════

📦 Build: v1.1 (2025-11-04, amd64)
🚀 Bootstrap: ✅ 100% Complete
🔗 ORPort: ✅ Reachable (9001)
📊 Uptime: 2d 14h 30m
🔑 Fingerprint: MyRelay 1234...ABCD

⚠️  Issues: ✅ No errors or warnings
```

> 📖 **Complete reference:** See [Tools Documentation](docs/TOOLS.md) for all 9 tools with examples, environment variables, and troubleshooting.

---

## 📊 Monitoring & Observability

### Built-in Metrics

Expose Prometheus metrics for monitoring:

```bash
# Enable metrics endpoint
docker run -d \
  --name tor-relay \
  -e ENABLE_METRICS=true \
  -e METRICS_PORT=9035 \
  -p 9035:9035 \
  ghcr.io/r3bo0tbx1/onion-relay:latest
```

Access metrics at `http://localhost:9035/metrics`

### Full Monitoring Stack

Deploy with **Prometheus + Grafana + Alertmanager**:

```bash
# Download multi-relay template with monitoring
curl -O https://raw.githubusercontent.com/r3bo0tbx1/tor-guard-relay/main/templates/docker-compose-multi-relay.yml

# Start everything
docker-compose -f docker-compose-multi-relay.yml up -d

# Access dashboards
# Grafana:     http://localhost:3000 (admin/admin)
# Prometheus:  http://localhost:9090
```

**Includes:**
- Pre-configured Prometheus scraping
- [Grafana dashboard](templates/grafana-dashboard.json) with visualizations
- [Alert rules](templates/prometheus.yml) for relay health
- [Alertmanager](templates/alertmanager.yml) for Slack/Discord notifications

> 📖 **Complete setup:** See [Monitoring Guide](docs/MONITORING.md) for metrics reference, alert rules, dashboard setup, and troubleshooting.

---

## 🎯 Key Features

### Security & Reliability
- ✅ Non-root execution (runs as `tor` user)
- ✅ Hardened Alpine Linux base (~35 MB)
- ✅ Automatic permission healing on startup
- ✅ Configuration validation before start
- ✅ Tini init for proper signal handling
- ✅ Graceful shutdown with cleanup

### Operations & Automation
- ✅ **9 diagnostic tools** built-in (status, health, metrics, etc.)
- ✅ **Prometheus metrics** for monitoring
- ✅ **HTML dashboard** for at-a-glance status
- ✅ **Multi-architecture** builds (AMD64, ARM64)
- ✅ **Weekly auto-builds** via GitHub Actions
- ✅ **Docker Compose templates** for single/multi-relay
- ✅ **Cosmos Cloud support** with one-click deploy

### Developer Experience
- ✅ Comprehensive documentation (8 guides)
- ✅ Example configurations included
- ✅ GitHub issue templates
- ✅ Automated dependency updates (Dependabot)
- ✅ CI/CD validation and testing
- ✅ Multi-arch support (same command, any platform)

---

## 📚 Documentation

**v1.1 includes comprehensive documentation** organized by topic:

### Getting Started
- **[Deployment Guide](docs/DEPLOYMENT.md)** - Complete installation for Docker CLI, Compose, Cosmos Cloud, and Portainer
- **[Migration Guide](docs/MIGRATION.md)** - Upgrade from v1.0 or migrate from other Tor setups

### Operations
- **[Tools Reference](docs/TOOLS.md)** - Complete guide to all 9 diagnostic tools
- **[Monitoring Guide](docs/MONITORING.md)** - Prometheus, Grafana, alerts, and observability
- **[Backup Guide](docs/BACKUP.md)** - Data persistence, recovery, and disaster planning
- **[Performance Guide](docs/PERFORMANCE.md)** - Optimization, tuning, and resource management

### Legal & Community
- **[Legal Considerations](docs/LEGAL.md)** - Legal aspects of running a Tor relay
- **[Documentation Index](docs/README.md)** - Complete documentation navigation

### Project Info
- **[Security Policy](SECURITY.md)** - Security practices and vulnerability reporting
- **[Contributing Guide](CONTRIBUTING.md)** - How to contribute to the project
- **[Code of Conduct](CODE_OF_CONDUCT.md)** - Community guidelines
- **[Changelog](CHANGELOG.md)** - Version history and changes

> 💡 **Tip:** Start with the [Documentation Index](docs/README.md) to find what you need quickly.

---

## 🛠️ Configuration

### Minimal Configuration

The simplest relay needs just these settings:

```ini
# relay.conf
Nickname MyTorRelay
ContactInfo your-email@example.com
ORPort 9001
ORPort [::]:9001
DirPort 9030

ExitRelay 0
SocksPort 0
DataDirectory /var/lib/tor
Log notice file /var/log/tor/notices.log
```

### Production Configuration

Add bandwidth limits and optimizations:

```ini
# Bandwidth (MB/s)
RelayBandwidthRate 50 MBytes
RelayBandwidthBurst 100 MBytes

# Performance
NumCPUs 2
MaxMemInQueues 512 MB

# IPv6 support
ORPort [::]:9001
```

### Example Configurations

See the [`examples/`](examples/) directory for complete, annotated configuration files:

- **[relay.conf](examples/relay.conf)** - Recommended production config
- Additional examples for specific use cases

> 📖 **Configuration help:** See [Deployment Guide](docs/DEPLOYMENT.md#configuration) for complete reference.

---

## 🔍 Monitoring Your Relay

### Check Bootstrap Status

```bash
# Quick status
docker exec tor-relay status

# JSON output for automation
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

> 📖 **Detailed monitoring:** See [Monitoring Guide](docs/MONITORING.md) for complete observability setup with Prometheus and Grafana.

---

## 🐛 Troubleshooting

### Quick Diagnostics

```bash
# Check overall status
docker exec tor-relay status

# Run network diagnostics
docker exec tor-relay net-check

# View recent errors
docker exec tor-relay view-logs --errors

# Check JSON health
docker exec tor-relay health | jq .
```

### Common Issues

| Problem | Quick Fix |
|---------|-----------|
| Container won't start | Check logs: `docker logs tor-relay` |
| ORPort not reachable | Verify firewall: `sudo ufw allow 9001/tcp` |
| Not on Tor Metrics | Wait 24h, verify bootstrap complete |
| Low/no traffic | Normal for new relays (2-8 weeks to build reputation) |

> 📖 **Full troubleshooting:** See [Tools Documentation](docs/TOOLS.md#troubleshooting) for detailed diagnostic procedures.

---

## 🏢 Architecture & Design

### Why Host Network Mode?

This project uses `--network host` for important reasons:

✅ **IPv6 Support** - Direct access to host's IPv6 stack  
✅ **No NAT** - Tor binds directly to ports without translation  
✅ **Better Performance** - Eliminates network overhead  
✅ **Tor Recommended** - Follows Tor Project best practices  

**Security:** The container still runs as non-root with restricted permissions. Host networking is standard for Tor relays.

### Multi-Architecture Support

Docker automatically pulls the correct architecture:

```bash
# Same command works on:
# - x86_64 servers (pulls amd64)
# - Raspberry Pi (pulls arm64)
# - AWS Graviton (pulls arm64)
docker pull ghcr.io/r3bo0tbx1/onion-relay:latest
```

Verify what you got:
```bash
docker exec tor-relay cat /build-info.txt | grep Architecture
```

---

## 🤝 Contributing

We welcome contributions! Here's how you can help:

- 🐛 **Report bugs** via [GitHub Issues](https://github.com/r3bo0tbx1/tor-guard-relay/issues)
- 💡 **Suggest features** or improvements
- 📖 **Improve documentation** (typos, clarity, examples)
- 🔧 **Submit pull requests** (code, configs, workflows)
- ⭐ **Star the repository** to show support
- 🧅 **Run a relay** and strengthen the network!

### Development

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

## 📦 Templates & Examples

All templates are in the [`templates/`](templates/) directory:

### Docker Compose
- [docker-compose.yml](templates/docker-compose.yml) - Single relay
- [docker-compose-multi-relay.yml](templates/docker-compose-multi-relay.yml) - 3 relays + monitoring

### Cosmos Cloud
- [cosmos-compose.json](templates/cosmos-compose.json) - Single relay
- [cosmos-compose-multi-relay.json](templates/cosmos-compose-multi-relay.json) - Multi-relay stack

### Monitoring
- [prometheus.yml](templates/prometheus.yml) - Prometheus configuration
- [alertmanager.yml](templates/alertmanager.yml) - Alert routing
- [grafana-dashboard.json](templates/grafana-dashboard.json) - Pre-built dashboard

### Configuration Examples
See [`examples/`](examples/) directory for relay configurations.

---

## 🔐 Security

### Best Practices

✅ Store `relay.conf` with restricted permissions (`chmod 600`)  
✅ Never commit configs with sensitive info to Git  
✅ Use PGP key in ContactInfo for verification  
✅ Regularly update Docker image for security patches  
✅ Monitor logs for suspicious activity  
✅ Configure firewall properly  

### Security Policy

Found a vulnerability? See our [Security Policy](SECURITY.md) for responsible disclosure.

### Updates

Images are automatically rebuilt weekly to include security patches:
- **Schedule:** Every Monday at 03:00 UTC
- **Includes:** Latest Tor + Alpine updates
- **Auto-published:** To GitHub Container Registry

---

## 🌐 Resources

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

![Docker Pulls](https://img.shields.io/docker/pulls/r3bo0tbx1/onion-relay?style=for-the-badge)
![GitHub Stars](https://img.shields.io/github/stars/r3bo0tbx1/tor-guard-relay?style=for-the-badge)
![GitHub Issues](https://img.shields.io/github/issues/r3bo0tbx1/tor-guard-relay?style=for-the-badge)

**Current Version:** v1.1  
**Status:** Production Ready  
**Last Build:** Weekly (Mondays 03:00 UTC)

</div>

---

## 📄 License

This project is licensed under the [MIT License](LICENSE.txt).

Free to use, modify, and distribute. See license file for details.

---

## 🙏 Acknowledgments

- **[The Tor Project](https://www.torproject.org/)** - Building the foundation of online privacy
- **[Alpine Linux](https://alpinelinux.org/)** - Minimal, secure base image
- **[azukaar](https://github.com/azukaar)** - Creator of [Cosmos Cloud](https://cosmos-cloud.io/)
- **All relay operators** - Strengthening the Tor network worldwide

---

## 💖 Support the Project

### Support Development

This project is free and open source. If it saved you time and you want to support future development:

**Bitcoin (BTC):**
```
bc1qltkajaswmzx9jwets8hfz43nkvred5w92syyq4
```

Or via **[AnonPay](https://trocador.app/anonpay?ticker_to=btc&network_to=Mainnet&address=bc1qltkajaswmzx9jwets8hfz43nkvred5w92syyq4&ref=sqKNYGZbRl&direct=True&name=rE-Bo0tbx1+%28r3bo0tbx1%29&description=Support+FOSS+Development&email=r3bo0tbx1%40brokenbotnet.com)** (convert any crypto)

**Monero (XMR):**
```
45mNg5cG1S2B2C5dndJP65SSEXseHFVqFdv1N6paAraD1Jk9kQxQQArVcjfQmgCcmthrUF3jbNs74c5AbWqMwAAgAjDYzrZ
```

Or via **[AnonPay](https://trocador.app/anonpay?ticker_to=xmr&network_to=Mainnet&address=85ft7ehMfcKSSp8Ve92Y9oARmqvDjYvEiKQkzdp3qiyzP9dpLeJXFahgHcoXUPeE9TacqDCUXWppNffE3YDC1Wu1NnQ71rT&ref=sqKNYGZbRl&direct=True&name=rE-Bo0tbx1+%28r3bo0tbx1%29&description=Support+FOSS+Development&email=r3bo0tbx1%40brokenbotnet.com)** (convert any crypto)

### Other Ways to Support

- ⭐ **Star this repository**
- 🐛 **Report bugs** and issues
- 💡 **Suggest features** for future versions
- 📖 **Improve documentation**
- 🤝 **Contribute code** or configs
- 🧅 **Run a relay** and help the network
- 📢 **Share** with others who might benefit

Stars and feedback are just as valuable! 🙏

---

<div align="center">

**Made with 💜 for a freer, uncensored internet**

*Protecting privacy, one relay at a time* 🧅✨

🌍 [Support Internet Freedom](https://donate.torproject.org/) • 📚 [Documentation](docs/README.md) • ⬆ [Back to top](#readme-top)

</div>