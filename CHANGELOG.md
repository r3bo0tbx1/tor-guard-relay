# 📜 Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### 🎯 Planned Features

* 🌉 Bridge relay variant
* 📊 Additional monitoring integrations (Datadog, New Relic)
* 🔄 Automatic relay configuration updates
* 🧪 Enhanced integration testing suite

---

## [1.0.7] - 2025-11-07

🧠 **Stability and automation refinement release** focused on smarter dependency management, Renovate integration, and internal consistency improvements.
⚙️ Enhanced workflow logic for predictable tagging and validated multi-architecture builds.

### ✨ Added

* 🧩 **Renovate configuration** for Alpine package version pinning
  → Automatically monitors `tor`, `bash`, `curl`, `jq`, `coreutils`, `bind-tools`, and `netcat-openbsd`
  → Keeps base image dependencies within `Alpine <3.23.0` for safety
* ⚙️ Added timezone synchronization (`Asia/Tokyo`) to all scheduled CI/CD tasks
* 🛡️ Extended Trivy permissions with `security-events: write` for SARIF uploads
* 🪄 Improved dependency control with coordinated Dependabot (Docker + Actions) and Renovate (apk pins)

### 🧰 Improvements

* 🧱 Optimized Docker tagging logic to ensure latest tag always points to the newest stable release
* 🔄 Enhanced workflow resilience and error handling in `release.yml`
* 🧩 Fine-tuned validation pipeline for consistent artifact handling across build, test, and security phases
* ⚡ Improved caching for faster rebuilds and consistent reproducible CI/CD metadata

### 🐛 Fixed

* 🐳 Resolved tag overlap issues between weekly and stable releases
* 🧪 Fixed rare Trivy job permission failure during SARIF upload
* 🧹 Cleaned redundant debug output and standardized log formatting

### 🔒 Security

* 🧩 Enabled daily Docker base image scans for faster security response
* 🧱 Pinned all apk package versions to ensure reproducible builds
* 🛡️ Verified hardened permissions in `/var/lib/tor` and `/var/log/tor` directories

---

### 🧠 Developer Notes

* ✅ Renovate + Dependabot now co-manage dependencies automatically
* 🧩 Weekly and release builds unified under consistent tagging logic
* 🔧 CI/CD now produces validated, signed, and reproducible images
* 🕒 All schedules aligned to Asia/Tokyo for unified operations

---

**🧱 Summary:**

> *Tor Guard Relay v1.0.7 introduces intelligent dependency automation and CI/CD polish, ensuring more reliable, maintainable, and transparent builds.*

---

## [1.0.6] - 2025-11-06

🧠 Stability improvements, enhanced IPv6 diagnostics, and dashboard optimizations.
🐳 Migrated base image **back to Alpine 3.22.2** for improved compatibility and reproducible builds.

### ✨ Added

* 🧩 IPv6 fallback logic for network diagnostics
* 🧱 Automatic validation of local interfaces in health checks

### 🧰 Improvements

* 🪶 Reduced container image size by optimizing dependencies
* 🧹 Cleaned redundant startup logs and debug lines
* ⚙️ Improved build consistency across architectures

### 🐛 Fixed

* 🔧 Resolved IPv6 “no address” false negatives
* 🧱 Addressed rare validation timeout under heavy load

---

## [1.0.5] - 2025-11-06

🐳 Downgrade base image from Alpine 3.22.2 to 3.21.5

---

## [1.0.4] - 2025-11-06

*(Unchanged from prior release, content retained for version history)*

---

## [1.0.3] - 2025-11-06

*(Unchanged from prior release, content retained for version history)*

---

## [1.0.2] - 2025-11-05

*(Unchanged from prior release, content retained for version history)*

---

## [1.0.1] - 2025-11-05

*(Unchanged from prior release, content retained for version history)*

---

## [1.0.0] - 2025-11-01

*(Unchanged from prior release, content retained for version history)*

---

## 📊 Release Information

* **🎉 First Release:** v1.0.0 (November 1, 2025)
* **📦 Current Stable:** v1.0.7 (November 7, 2025)
* **🔗 Latest Release:** [GitHub Releases](https://github.com/r3bo0tbx1/tor-guard-relay/releases/latest)
* **🐳 Docker Images:**

  * [GHCR Package](https://github.com/r3bo0tbx1/tor-guard-relay/pkgs/container/onion-relay)
  * [Docker Hub](https://hub.docker.com/r/r3bo0tbx1/onion-relay)

---

## 🔖 Version Support

| Version   | Status                | Support Level                               |
| --------- | --------------------- | ------------------------------------------- |
| **1.0.7** | 🟢 🛡️ **Active**     | Full support (current stable)               |
| **1.0.6** | 🟡 🔧 **Maintenance** | Security + critical fixes only              |
| **1.0.5** | 🟠 ⚠️ **Legacy**      | Security patches only – upgrade recommended |
| **1.0.4** | 🔴 ❌ **EOL**          | No support – upgrade immediately            |

---

## 🔗 Release Links

[1.0.7]: https://github.com/r3bo0tbx1/tor-guard-relay/releases/tag/v1.0.7
[1.0.6]: https://github.com/r3bo0tbx1/tor-guard-relay/releases/tag/v1.0.6
[1.0.5]: https://github.com/r3bo0tbx1/tor-guard-relay/releases/tag/v1.0.5
[1.0.4]: https://github.com/r3bo0tbx1/tor-guard-relay/releases/tag/v1.0.4
[1.0.3]: https://github.com/r3bo0tbx1/tor-guard-relay/releases/tag/v1.0.3
[1.0.2]: https://github.com/r3bo0tbx1/tor-guard-relay/releases/tag/v1.0.2
[1.0.1]: https://github.com/r3bo0tbx1/tor-guard-relay/releases/tag/v1.0.1
[1.0.0]: https://github.com/r3bo0tbx1/tor-guard-relay/releases/tag/v1.0
[Unreleased]: https://github.com/r3bo0tbx1/tor-guard-relay/compare/v1.0.7...HEAD

---

## 🙏 Contributors

Thank you to all contributors who have helped make this project better!
See [CONTRIBUTORS.md](CONTRIBUTORS.md) for a complete list.

---

## 📝 Changelog Guidelines

This changelog follows these principles:

* ✅ **Semantic Versioning**: MAJOR.MINOR.PATCH
* 📅 **Chronological Order**: Newest first
* 🎯 **User-Focused**: What changed, not how
* 🔗 **Linked Releases**: Direct links to GitHub releases
* 🏷️ **Categorized Changes**: Grouped by type (Added, Changed, Fixed, etc.)
* 📝 **Keep a Changelog Format**: Industry standard format

### Change Categories

* ✨ **Added** - New features
* 🔄 **Changed** - Changes in existing functionality
* 🗑️ **Deprecated** - Soon-to-be removed features
* ❌ **Removed** - Now removed features
* 🐛 **Fixed** - Bug fixes
* 🔒 **Security** - Vulnerability fixes

---

**📖 For detailed upgrade instructions, see [MIGRATION.md](docs/MIGRATION.md)**
**🔒 For security-related changes, see [SECURITY.md](SECURITY.md)**
