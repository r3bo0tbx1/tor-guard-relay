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

## [1.0.8] - 2025-11-08

🧠 **Polish and refinement release** focused on versioning automation, tag safety, and improved metadata accuracy.
⚙️ Streamlined validation logic, consistent changelog generation, and safer build workflows.

### ✨ Added

* 🧩 Auto-generated `Unreleased` compare link in workflows for dynamic changelog updates
* ⚙️ Added commit and tag automation helpers for PowerShell (version bump, tagging, release)
* 📦 Improved changelog consistency between main branch and GitHub Releases
* 🕒 Timezone logic refined for full `Asia/Tokyo` synchronization across workflows

### 🧰 Improvements

* 🧱 Improved workflow dependency order to prevent tag-push race conditions
* 🔄 Cleaned up redundant trigger filters and unified workflow paths
* 🧩 Optimized `dependabot.yml` and `renovate.json` to coordinate update frequency
* ⚡ Enhanced readability and validation of Docker builds via better cache strategy
* 📜 Simplified changelog entry structure for maintainability

### 🐛 Fixed

* 🧩 Fixed missing newline warning in `.github/dependabot.yml`
* 🔧 Resolved edge cases where both validation and release workflows triggered simultaneously
* 🧹 Cleaned outdated references to removed workflows in comments and docs
* 🧱 Corrected version links and metadata for previous releases

### 🔒 Security

* 🛡️ Verified hardened build permissions for `trivy-action` uploads
* 🧩 Ensured consistent use of `security-events: write` for all scan jobs
* 🔐 Confirmed package pin integrity in Renovate configuration

---

### 🧠 Developer Notes

* ✅ Push main first, tag only after successful validation
* 🧩 Tag creation now automatically updates release notes
* 🪄 PowerShell automation script simplifies version bumping and tagging
* 🕒 All recurring jobs (Dependabot, Renovate, Weekly Build) aligned to `Asia/Tokyo`

---

**🧱 Summary:**

> *Tor Guard Relay v1.0.8 improves workflow safety, version traceability, and automation clarity while tightening CI/CD control and metadata consistency.*

---

## [1.0.7] - 2025-11-07

🧠 Stability and automation refinement release focused on smarter dependency management and workflow consistency.
⚙️ Enhanced multi-architecture build validation and coordinated dependency automation.

*(See prior section for full 1.0.7 details.)*

---

## [1.0.6] - 2025-11-06

🧠 Stability improvements, enhanced IPv6 diagnostics, and dashboard optimizations.
🐳 Migrated base image **back to Alpine 3.22.2** for improved compatibility and reproducible builds.

---

## [1.0.5] - 2025-11-06

🐳 Downgrade base image from Alpine 3.22.2 to 3.21.5

---

## [1.0.4] - 2025-11-06

*(Unchanged from prior release, retained for version history)*

---

## [1.0.3] - 2025-11-06

*(Unchanged from prior release, retained for version history)*

---

## [1.0.2] - 2025-11-05

*(Unchanged from prior release, retained for version history)*

---

## [1.0.1] - 2025-11-05

*(Unchanged from prior release, retained for version history)*

---

## [1.0.0] - 2025-11-01

*(Unchanged from prior release, retained for version history)*

---

## 📊 Release Information

* **🎉 First Release:** v1.0.0 (November 1, 2025)
* **📦 Current Stable:** v1.0.8 (November 8, 2025)
* **🔗 Latest Release:** [GitHub Releases](https://github.com/r3bo0tbx1/tor-guard-relay/releases/latest)
* **🐳 Docker Images:**

  * [GHCR Package](https://github.com/r3bo0tbx1/tor-guard-relay/pkgs/container/onion-relay)
  * [Docker Hub](https://hub.docker.com/r/r3bo0tbx1/onion-relay)

---

## 🔖 Version Support

| Version   | Status                | Support Level                               |
| --------- | --------------------- | ------------------------------------------- |
| **1.0.8** | 🟢 🛡️ **Active**     | Full support (current stable)               |
| **1.0.7** | 🟡 🔧 **Maintenance** | Security + critical fixes only              |
| **1.0.6** | 🟠 ⚠️ **Legacy**      | Security patches only – upgrade recommended |
| **1.0.5** | 🔴 ❌ **EOL**          | No support – upgrade immediately            |

---

## 🔗 Release Links

[1.0.8]: https://github.com/r3bo0tbx1/tor-guard-relay/releases/tag/v1.0.8
[1.0.7]: https://github.com/r3bo0tbx1/tor-guard-relay/releases/tag/v1.0.7
[1.0.6]: https://github.com/r3bo0tbx1/tor-guard-relay/releases/tag/v1.0.6
[1.0.5]: https://github.com/r3bo0tbx1/tor-guard-relay/releases/tag/v1.0.5
[1.0.4]: https://github.com/r3bo0tbx1/tor-guard-relay/releases/tag/v1.0.4
[1.0.3]: https://github.com/r3bo0tbx1/tor-guard-relay/releases/tag/v1.0.3
[1.0.2]: https://github.com/r3bo0tbx1/tor-guard-relay/releases/tag/v1.0.2
[1.0.1]: https://github.com/r3bo0tbx1/tor-guard-relay/releases/tag/v1.0.1
[1.0.0]: https://github.com/r3bo0tbx1/tor-guard-relay/releases/tag/v1.0
[Unreleased]: https://github.com/r3bo0tbx1/tor-guard-relay/compare/v1.0.8...HEAD

---

## 🙏 Contributors

Thank you to all contributors who have helped make this project better!
See [CONTRIBUTORS.md](CONTRIBUTORS.md) for a complete list.

---

## 📝 Changelog Guidelines

This changelog follows these principles:

* ✅ **Semantic Versioning** (MAJOR.MINOR.PATCH)
* 📅 **Chronological Order** (newest first)
* 🎯 **User-Focused**: what changed, not how
* 🔗 **Linked Releases**: direct GitHub release links
* 🏷️ **Categorized Changes**: Added, Fixed, Security, etc.
* 📝 **Keep a Changelog** format compliance

---

**📖 For upgrade instructions, see [MIGRATION.md](docs/MIGRATION.md)**
**🔒 For security-related changes, see [SECURITY.md](SECURITY.md)**