<div align="center">

<img src="https://raw.githubusercontent.com/r3bo0tbx1/tor-guard-relay/main/src/logo.png" alt="Tor AIO Stack" width="360" />

# 🧅 Tor AIO Stack

**Complete Bridge, Relay & Exit Node Solution**

[![Release](https://img.shields.io/github/v/release/r3bo0tbx1/tor-guard-relay?style=for-the-badge&color=7d4698)](https://github.com/r3bo0tbx1/tor-guard-relay/releases/latest)
[![Docker Pulls](https://img.shields.io/docker/pulls/r3bo0tbx1/onion-relay?style=for-the-badge&logo=docker)](https://hub.docker.com/r/r3bo0tbx1/onion-relay)
[![Platforms](https://img.shields.io/badge/platforms-amd64%20%7C%20arm64-2ea44f?style=for-the-badge)](https://github.com/r3bo0tbx1/tor-guard-relay)

**Hardened · Lightweight · Observable**

[📚 Documentation](https://github.com/r3bo0tbx1/tor-guard-relay#-documentation) · [🌐 Live Dashboard](https://relays.brokenbotnet.com/) · [💜 Support](https://brokenbotnet.com/donate/)

</div>

---

## 🆕 v2.2.0 — safer relay operations and encrypted recovery

Current release: <!-- RELAY_VERSION -->v2.2.0<!-- /RELAY_VERSION -->.

| Feature | What it gives you |
| --- | --- |
| 🛡️ Tor 0.4.9.14 or newer | Enforced runtime security floor |
| 🔎 Current-run diagnostics | Health, readiness, `doctor` and redacted config checks |
| ⚙️ Validated configuration | Atomic changes and reloads that preserve the Tor process |
| 🔐 Encrypted recovery | Verified backups of config, identity keys and relay state; staged offline restore |
| 📊 Fleet inventory | Host-side inventory and metrics without an exposed diagnostics port |
| 🏗️ Verified publication | Both architectures checked before their exact images reach the registries |

📖 [Release notes and migration details](https://github.com/r3bo0tbx1/tor-guard-relay/releases/tag/v2.2.0)

## 🏷️ Choose your image

| Docker Hub tag | Variant | Platforms |
| --- | --- | --- |
| `latest` | Stable, recommended for production | AMD64 / ARM64 |
| `2.2.0` | Current stable release series | AMD64 / ARM64 |
| `edge` | Alpine edge, for testing | AMD64 / ARM64 |

Stable uses **Alpine 3.24.2**. Validated manual and scheduled rebuilds from main include merged fixes and fresh packages; version tags can receive those rebuilds. Pin an image digest when you need an exact build.

Retired container tags can be removed while [historical GitHub releases and their SBOM/security assets](https://github.com/r3bo0tbx1/tor-guard-relay/releases) remain available. Keep a verified current image digest for rollback.

```bash
docker pull r3bo0tbx1/onion-relay:latest
docker pull r3bo0tbx1/onion-relay:2.2.0
docker pull r3bo0tbx1/onion-relay:edge
```

📦 GHCR additionally provides versioned edge tags, including `ghcr.io/r3bo0tbx1/onion-relay:2.2.0-edge`.

## 🚀 Deploy with your own relay configuration

Use the [deployment guide](https://github.com/r3bo0tbx1/tor-guard-relay/blob/main/docs/DEPLOYMENT.md) for Docker CLI, Compose, Portainer or Cosmos Cloud. Set your relay nickname, contact, mode and bandwidth before starting a public relay.

> 🔐 Before upgrading, verify an encrypted backup and compare relay fingerprints. Recovery tooling requires host Python 3.10+ and age. Keep persistent changes in deployment ENV or a mounted torrc; generated torrc is recreated on restart. Never activate two copies of the same relay identity.

[🔐 Backup and recovery](https://github.com/r3bo0tbx1/tor-guard-relay/blob/main/docs/BACKUP.md) · [🧰 Operator tools](https://github.com/r3bo0tbx1/tor-guard-relay/blob/main/docs/TOOLS.md) · [🛡️ Security policy](https://github.com/r3bo0tbx1/tor-guard-relay/blob/main/SECURITY.md)
