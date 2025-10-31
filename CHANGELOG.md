# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned Features
- Advanced monitoring scripts
- Bridge relay variant

## [1.0] - 2025-11-01

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
- **Latest Release:** [GitHub Releases](https://github.com/r3bo0tbx1/tor-guard-relay/releases/latest)
- **Docker Images:** [GHCR Package](https://github.com/r3bo0tbx1/tor-guard-relay/pkgs/container/onion-relay)

## Version Support

| Version | Status | Support Period |
|---------|--------|----------------|
| 1.0.x   | ✅ Actively Supported | Current |
| Future versions | - | TBD |

[1.0]: https://github.com/r3bo0tbx1/tor-guard-relay/releases/tag/v1.0
[Unreleased]: https://github.com/r3bo0tbx1/tor-guard-relay/compare/v1.0...HEAD
