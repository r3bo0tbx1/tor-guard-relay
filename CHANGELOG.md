# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned Features
- Bridge relay variant
- Additional monitoring integrations

## [1.0.3] - 2025-11-06

### 🚀 CI/CD & Build System

- Unified and simplified `release.yml` with dual GHCR + Docker Hub publishing  
- Added `dos2unix` and auto `chmod +x` script normalization  
- Improved version detection and tagging logic  
- Enhanced build summaries and metadata consistency  

### 🧱 Validation & Linting

- Expanded `validate.yml` for full Dockerfile, YAML, and Shell linting  
- Added Trivy security scan and documentation checks  
- Fixed all lint and formatting warnings across workflows and templates  

### 🧩 General Improvements

- Normalized line endings and removed trailing spaces  
- Updated Prometheus and Compose templates for compliance  
- Cleaned repository structure for cross-platform builds

## [1.0.2] - 2025-11-05

### 🔒 Security Hardening

**Network Exposure Model**
- Enforced strict two-port exposure policy (9001 ORPort, 9030 DirPort only)
- All monitoring services (metrics, health, dashboard) bound to localhost (127.0.0.1)
- Updated documentation to reflect secure-by-default configuration

**Tool Security**
- Changed default bind addresses from 0.0.0.0 → 127.0.0.1 (dashboard, metrics-http)
- Added automatic configuration backup in setup tool
- Implemented rate limiting for HTTP servers
- Enhanced SIGTERM handling for clean shutdowns

**Infrastructure**
- Pinned base image to Alpine 3.22.2 for reproducible builds
- Updated GitHub Actions to latest versions
- Fixed invalid docker build commands in CI/CD
- Enhanced process cleanup in docker-entrypoint.sh

### 📚 Documentation

**New Content**
- Comprehensive port exposure policy documentation
- Security model clarification (public vs internal ports)
- Enhanced deployment examples with security warnings
- Improved monitoring setup guides with localhost binding examples

**Updates**
- All documentation aligned to v1.0.2
- Corrected version references throughout
- Enhanced security warnings for external port exposure
- Updated template configurations

### 🛠️ Technical Improvements

**Scripts**
- Enhanced integration-check.sh with port validation
- Improved relay-status.sh output formatting
- Added version consistency checks

**Templates**
- Updated all docker-compose templates with explicit port policies
- Enhanced Prometheus/Grafana configurations
- Improved Cosmos Cloud templates with security annotations

### 🐛 Fixes
- Corrected version inconsistencies across documentation
- Fixed port exposure examples in deployment guides
- Updated monitoring endpoint documentation

---

## [1.0.1] - 2025-11-05

### 🎉 Major Restructuring

**Repository Organization**
- Reorganized repository into professional directory structure
- Created `.github/`, `docs/`, `templates/`, `tools/` directories
- All files now in proper locations per project standards

**New Documentation (4 files)**
- `docs/TOOLS.md` - Comprehensive tool reference (11.8KB)
- `docs/MONITORING.md` - Complete observability guide (12.5KB)
- `docs/MIGRATION.md` - Version upgrade procedures (13.9KB)
- `docs/README.md` - Documentation navigation hub (6.2KB)

**GitHub Integration**
- Updated Dependabot for automated dependency updates (`.github/dependabot.yml`)

**Improved Documentation**
- Updated README.md - cleaner, more scannable, better organized
- All documentation now properly linked and cross-referenced
- ~2,010 lines of new comprehensive documentation

**Breaking Changes**
- None! Fully backward compatible with v1.0
- Same Docker commands work
- Same tool interfaces
- Volume mounts unchanged

---

## [1.0.0] - 2025-11-01

### 🎉 Initial Release

**Tor Guard Relay v1.0** – A production-ready, hardened Tor relay container with comprehensive features built-in from day one.

### ✨ Core Features

**Built-in Diagnostic Tools**
- `relay-status` - Comprehensive health report with bootstrap progress, reachability, and error detection
- `fingerprint` - Quick fingerprint lookup with direct links to Tor Metrics
- `view-logs` - Live log streaming for real-time monitoring

**Multi-Architecture Support**
- Native builds for `linux/amd64` (x86_64 servers)
- Native builds for `linux/arm64` (Raspberry Pi, Oracle ARM, AWS Graviton)
- Automatic architecture detection by Docker
- Single image tag works across all platforms

**Self-Healing Capabilities**
- Automatic permission repair on every container boot
- Configuration validation before Tor starts
- Graceful error handling with helpful user messages
- Tini init system for clean process management and signal handling

**Build & Deployment**
- Build metadata tracking (version, date, architecture)
- GitHub Actions workflow for weekly automated builds
- Multi-arch Docker builds with SHA-based versioning
- Docker Compose template for production deployments
- Cosmos Cloud JSON for one-click deployment
- Comprehensive deployment guide covering 4 methods

### 🔐 Security

- Non-root operation (runs as `tor` user)
- Minimal Alpine Linux base image (~35 MB compressed)
- Hardened permissions with automatic healing
- Capability restrictions (only required capabilities granted)
- Read-only configuration mounting
- Configuration validation on startup
- Security policy with responsible disclosure process

### 📚 Documentation

- Complete deployment guide for Docker CLI, Docker Compose, Cosmos Cloud, and Portainer
- Troubleshooting guide with common issues and solutions
- Security best practices and hardening guide
- Contributing guidelines with code of conduct
- Example configuration files with detailed comments
- Multi-architecture usage instructions

### 🤖 Automation

- Weekly automated builds via GitHub Actions
- Multi-platform builds (amd64 + arm64) in single workflow
- Build caching for faster CI/CD
- Automatic tagging with version and git SHA
- GHCR (GitHub Container Registry) publishing

### 🛡️ Reliability

- Tini as PID 1 for proper signal handling
- Zero-downtime restart capability
- Automatic error recovery
- Health check endpoint
- Persistent volume support
- Graceful shutdown handling

### 📦 Templates & Examples

- Docker Compose configuration
- Cosmos Cloud JSON template
- Complete relay.conf example with comments
- Status checking script for external monitoring

## Release Information

- **First Release:** v1.0 (November 1, 2025)
- **Current Release:** v1.0.2
- **Latest Release:** [GitHub Releases](https://github.com/r3bo0tbx1/tor-guard-relay/releases/latest)
- **Docker Images:** [GHCR Package](https://github.com/r3bo0tbx1/tor-guard-relay/pkgs/container/onion-relay)

## Version Support

| Version | Status | Support Period |
|---------|--------|----------------|
| 1.0.2   | ✅ Actively Supported | Current |
| 1.0.1   | ✅ Supported | Until v1.1.0 |
| 1.0.0   | ⚠️ Legacy | Security updates only |

[1.0.2]: https://github.com/r3bo0tbx1/tor-guard-relay/releases/tag/v1.0.2
[1.0.1]: https://github.com/r3bo0tbx1/tor-guard-relay/releases/tag/v1.0.1
[1.0.0]: https://github.com/r3bo0tbx1/tor-guard-relay/releases/tag/v1.0.0
[Unreleased]: https://github.com/r3bo0tbx1/tor-guard-relay/compare/v1.0.2...HEAD