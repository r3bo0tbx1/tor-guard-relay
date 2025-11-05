# 📜 Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### 🎯 Planned Features
- 🌉 Bridge relay variant
- 📊 Additional monitoring integrations (Datadog, New Relic)
- 🔄 Automatic relay configuration updates
- 🧪 Enhanced integration testing suite

---

## [1.0.3] - 2025-11-06

### 🚀 CI/CD & Build System

**Workflow Improvements**
- ✨ Unified and simplified `release.yml` with dual GHCR + Docker Hub publishing  
- 🔧 Added `dos2unix` and auto `chmod +x` script normalization  
- 🏷️ Improved version detection and tagging logic  
- 📊 Enhanced build summaries and metadata consistency  
- 🎨 Added emoji-enhanced workflow output for better readability

**Build Process**
- 🐳 Streamlined multi-arch build pipeline
- 💾 Improved build caching strategy
- 🔍 Enhanced validation pre-checks

### 🧱 Validation & Linting

**Quality Assurance**
- ✅ Expanded `validate.yml` for comprehensive Dockerfile, YAML, and Shell linting  
- 🛡️ Added Trivy security scan with SARIF report generation
- 📚 Implemented documentation completeness checks  
- 🔎 Fixed all lint and formatting warnings across workflows and templates  
- 🎯 Added shell script extension verification (.sh enforcement)

**Static Analysis**
- 📝 ShellCheck integration for all shell scripts
- 🐳 Hadolint for Dockerfile best practices
- 📋 yamllint for YAML validation
- 🔖 JSON syntax validation

### 🧩 General Improvements

**Code Quality**
- 📄 Normalized line endings across all files (CRLF → LF)
- 🧹 Removed trailing spaces and fixed formatting
- ✨ Updated Prometheus and Compose templates for compliance  
- 🏗️ Cleaned repository structure for cross-platform builds
- 📦 Improved file organization and naming conventions

**Documentation**
- 📖 Updated all examples to reflect current best practices
- 🔗 Fixed broken links and outdated references
- ✏️ Corrected typos and improved clarity

---

## [1.0.2] - 2025-11-05

### 🔒 Security Hardening

**Network Exposure Model**
- 🔐 Enforced strict two-port exposure policy (9001 ORPort, 9030 DirPort only)
- 🏠 All monitoring services (metrics, health, dashboard) bound to localhost (127.0.0.1)
- 🛡️ Updated documentation to reflect secure-by-default configuration
- ⚠️ Added prominent security warnings for external port exposure

**Tool Security**
- 🔧 Changed default bind addresses from 0.0.0.0 → 127.0.0.1 (dashboard, metrics-http)
- 💾 Added automatic configuration backup in setup tool
- ⏱️ Implemented rate limiting for HTTP servers
- 🛑 Enhanced SIGTERM handling for clean shutdowns
- 🔒 Improved process isolation and signal handling

**Infrastructure**
- 📌 Pinned base image to Alpine 3.22.2 for reproducible builds
- ⬆️ Updated GitHub Actions to latest versions (checkout@v5, etc.)
- 🐛 Fixed invalid docker build commands in CI/CD
- 🧹 Enhanced process cleanup in docker-entrypoint.sh
- 🔍 Added build metadata validation

### 📚 Documentation

**New Content**
- 📖 Comprehensive port exposure policy documentation
- 🔒 Security model clarification (public vs internal ports)
- 🚀 Enhanced deployment examples with security warnings
- 📊 Improved monitoring setup guides with localhost binding examples
- 🌐 Added Nginx reverse proxy examples

**Updates**
- ✅ All documentation aligned to v1.0.2
- 🔢 Corrected version references throughout
- ⚠️ Enhanced security warnings for external port exposure
- 🐳 Updated template configurations
- 📝 Improved README structure and navigation

### 🛠️ Technical Improvements

**Scripts**
- ✨ Enhanced integration-check.sh with port validation
- 📊 Improved relay-status.sh output formatting
- 🔍 Added version consistency checks
- 🐛 Fixed edge cases in error handling
- 🚀 Optimized script performance

**Templates**
- 🐳 Updated all docker-compose templates with explicit port policies
- 📊 Enhanced Prometheus/Grafana configurations
- ☁️ Improved Cosmos Cloud templates with security annotations
- 🔧 Added environment variable validation
- 📖 Better inline documentation

### 🐛 Bug Fixes
- ✅ Corrected version inconsistencies across documentation
- 🔌 Fixed port exposure examples in deployment guides
- 📊 Updated monitoring endpoint documentation
- 🔗 Repaired broken internal links
- 📝 Fixed typos in configuration examples

### ⚡ Performance
- 🚀 Reduced container startup time by 15%
- 💾 Optimized disk I/O for log operations
- 🧠 Improved memory footprint
- 🔄 Faster configuration validation

---

## [1.0.1] - 2025-11-05

### 🎉 Major Restructuring

**Repository Organization**
- 📁 Reorganized repository into professional directory structure
- 🗂️ Created `.github/`, `docs/`, `templates/`, `tools/` directories
- ✨ All files now in proper locations per project standards
- 🧹 Cleaned up root directory for better navigation
- 📦 Improved file categorization

**New Documentation (4 Major Files)**
- 🛠️ `docs/TOOLS.md` - Comprehensive tool reference (11.8KB)
  - Complete guide to all diagnostic utilities
  - Usage examples and troubleshooting
  - Integration patterns
  
- 📊 `docs/MONITORING.md` - Complete observability guide (12.5KB)
  - Prometheus metrics documentation
  - Grafana dashboard setup
  - Alert configuration examples
  
- 🔄 `docs/MIGRATION.md` - Version upgrade procedures (13.9KB)
  - Step-by-step upgrade guides
  - Breaking change documentation
  - Rollback procedures
  
- 📖 `docs/README.md` - Documentation navigation hub (6.2KB)
  - Central documentation index
  - Quick-start guides
  - Resource links

**GitHub Integration**
- 🤖 Updated Dependabot for automated dependency updates (`.github/dependabot.yml`)
- 🔒 Configured security scanning
- 📦 Package ecosystem monitoring
- ⏰ Automated weekly update checks

**Improved Documentation**
- ✨ Updated README.md - cleaner, more scannable, better organized
- 🔗 All documentation now properly linked and cross-referenced
- 📝 ~2,010 lines of new comprehensive documentation
- 🎯 Improved navigation and discoverability
- 📚 Enhanced code examples

**Breaking Changes**
- ✅ None! Fully backward compatible with v1.0
- 🐳 Same Docker commands work
- 🔧 Same tool interfaces
- 💾 Volume mounts unchanged
- 🔌 Port mappings consistent

---

## [1.0.0] - 2025-11-01

### 🎉 Initial Release

**Tor Guard Relay v1.0** – A production-ready, hardened Tor relay container with comprehensive features built-in from day one.

### ✨ Core Features

**Built-in Diagnostic Tools**
- 🩺 `relay-status` - Comprehensive health report with bootstrap progress, reachability, and error detection
- 🔑 `fingerprint` - Quick fingerprint lookup with direct links to Tor Metrics
- 📋 `view-logs` - Live log streaming for real-time monitoring
- 🌐 `net-check` - Network connectivity diagnostics
- 📊 `metrics` - Prometheus metrics exporter
- 🔧 `setup` - Interactive relay configuration wizard

**Multi-Architecture Support**
- 🖥️ Native builds for `linux/amd64` (x86_64 servers)
- 🥧 Native builds for `linux/arm64` (Raspberry Pi, Oracle ARM, AWS Graviton)
- 🔄 Automatic architecture detection by Docker
- 📦 Single image tag works across all platforms
- ⚡ Optimized binaries for each architecture

**Self-Healing Capabilities**
- 🔧 Automatic permission repair on every container boot
- ✅ Configuration validation before Tor starts
- 🛡️ Graceful error handling with helpful user messages
- 🔄 Tini init system for clean process management and signal handling
- 🩹 Automatic recovery from common misconfigurations

**Build & Deployment**
- 📊 Build metadata tracking (version, date, architecture)
- 🤖 GitHub Actions workflow for weekly automated builds
- 🏗️ Multi-arch Docker builds with SHA-based versioning
- 🐳 Docker Compose template for production deployments
- ☁️ Cosmos Cloud JSON for one-click deployment
- 📖 Comprehensive deployment guide covering 4 methods

### 🔐 Security

**Container Hardening**
- 👤 Non-root operation (runs as `tor` user, UID 100)
- 🏔️ Minimal Alpine Linux base image (~35 MB compressed)
- 🔒 Hardened permissions with automatic healing
- 🛡️ Capability restrictions (only required capabilities granted)
- 📖 Read-only configuration mounting
- ✅ Configuration validation on startup

**Security Practices**
- 📋 Security policy with responsible disclosure process
- 🔐 No secrets in logs or error messages
- 🚫 Minimal attack surface
- 🔍 Regular security scanning with Trivy
- 📦 Reproducible builds with pinned dependencies

### 📚 Documentation

**Comprehensive Guides**
- 🚀 Complete deployment guide for Docker CLI, Docker Compose, Cosmos Cloud, and Portainer
- 🐛 Troubleshooting guide with common issues and solutions
- 🔒 Security best practices and hardening guide
- 🤝 Contributing guidelines with code of conduct
- 📝 Example configuration files with detailed comments
- 🌐 Multi-architecture usage instructions

**Quick Start**
- ⚡ 5-minute setup guide
- 🎯 Common use cases and examples
- 🔗 Links to external resources
- 💡 Tips and best practices

### 🤖 Automation

**CI/CD Pipeline**
- 📅 Weekly automated builds via GitHub Actions
- 🏗️ Multi-platform builds (amd64 + arm64) in single workflow
- 💾 Build caching for faster CI/CD
- 🏷️ Automatic tagging with version and git SHA
- 📦 GHCR (GitHub Container Registry) publishing
- 🐳 Docker Hub mirroring

**Quality Checks**
- ✅ Automated testing suite
- 🔍 Lint validation
- 🛡️ Security scanning
- 📊 Build verification

### 🛡️ Reliability

**Production Ready**
- 🔄 Tini as PID 1 for proper signal handling
- ⚡ Zero-downtime restart capability
- 🩹 Automatic error recovery
- 🏥 Health check endpoint
- 💾 Persistent volume support
- 🛑 Graceful shutdown handling

**Monitoring**
- 📊 Prometheus metrics export
- 📈 Built-in health checks
- 📋 Structured logging
- 🔔 Alert-ready status endpoints

### 📦 Templates & Examples

**Ready-to-Use Configurations**
- 🐳 Docker Compose configuration
- ☁️ Cosmos Cloud JSON template
- 📝 Complete relay.conf example with comments
- 📊 Status checking script for external monitoring
- 🔧 Systemd service files
- 🌐 Nginx reverse proxy examples

---

## 📊 Release Information

- **🎉 First Release:** v1.0.0 (November 1, 2025)
- **📦 Current Stable:** v1.0.3 (November 6, 2025)
- **🔗 Latest Release:** [GitHub Releases](https://github.com/r3bo0tbx1/tor-guard-relay/releases/latest)
- **🐳 Docker Images:** 
  - [GHCR Package](https://github.com/r3bo0tbx1/tor-guard-relay/pkgs/container/onion-relay)
  - [Docker Hub](https://hub.docker.com/r/r3bo0tbx1/onion-relay)

---

## 🔖 Version Support

| Version | Status | Support Level |
|---------|--------|---------------|
| **1.0.3** | 🟢 🛡️ **Active** | Full support (current stable) |
| **1.0.2** | 🟢 🛡️ **Active** | Full support until v1.1.0 |
| **1.0.1** | 🟡 🔧 **Maintenance** | Security + critical fixes only |
| **1.0.0** | 🟠 ⚠️ **Legacy** | Security patches only - upgrade recommended |

### 📋 Support Legend

- 🟢 **Active Support**: Security fixes + new features + bug fixes
- 🟡 **Maintenance**: Security fixes + critical bugs only  
- 🟠 **Legacy**: Security patches only - plan to upgrade
- 🔴 **End of Life**: No support - upgrade immediately

---

## 🔗 Release Links

[1.0.3]: https://github.com/r3bo0tbx1/tor-guard-relay/releases/tag/v1.0.3
[1.0.2]: https://github.com/r3bo0tbx1/tor-guard-relay/releases/tag/v1.0.2
[1.0.1]: https://github.com/r3bo0tbx1/tor-guard-relay/releases/tag/v1.0.1
[1.0.0]: https://github.com/r3bo0tbx1/tor-guard-relay/releases/tag/v1.0.0
[Unreleased]: https://github.com/r3bo0tbx1/tor-guard-relay/compare/v1.0.3...HEAD

---

## 🙏 Contributors

Thank you to all contributors who have helped make this project better!

See [CONTRIBUTORS.md](CONTRIBUTORS.md) for a complete list.

---

## 📝 Changelog Guidelines

This changelog follows these principles:

- ✅ **Semantic Versioning**: MAJOR.MINOR.PATCH
- 📅 **Chronological Order**: Newest first
- 🎯 **User-Focused**: What changed, not how
- 🔗 **Linked Releases**: Direct links to GitHub releases
- 🏷️ **Categorized Changes**: Grouped by type (Added, Changed, Fixed, etc.)
- 📝 **Keep a Changelog Format**: Industry standard format

### Change Categories

- ✨ **Added** - New features
- 🔄 **Changed** - Changes in existing functionality
- 🗑️ **Deprecated** - Soon-to-be removed features
- ❌ **Removed** - Now removed features
- 🐛 **Fixed** - Bug fixes
- 🔒 **Security** - Vulnerability fixes

---

**📖 For detailed upgrade instructions, see [MIGRATION.md](docs/MIGRATION.md)**

**🔒 For security-related changes, see [SECURITY.md](SECURITY.md)**