# 📜 Changelog

All notable changes to this project will be documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### 🎯 Planned Features

* 📊 Additional monitoring integrations (Datadog, New Relic)
* 🔄 Automatic relay configuration updates
* 🧪 Enhanced integration testing suite

---

## [1.1.8] - 2026-04-03

### ⚡ Improvements

- **HEALTHCHECK Interval**: Reduced Docker healthcheck interval from 10 minutes to 5 minutes for faster failure detection. Container unhealthy state now detected in ~15 minutes (5m × 3 retries) instead of 30 minutes.
- **Health Tool Enhancement**: Added `tor_version` and `relay_mode` fields to JSON output of the `health` diagnostic tool for better monitoring and automation support.
- **README Optimization**: Trimmed README.md from 1,084 lines to 749 lines (31% reduction) for better scannability. Removed redundant content (Mermaid flowchart, gallery, star history) already available in dedicated documentation files. All information remains accessible through documentation links.

### 🔒 Validation

- **TOR_FAMILY_ID Validation**: Added strict validation for the `TOR_FAMILY_ID` environment variable. The entrypoint now validates that FamilyId values are exactly 52 characters and properly base32-encoded (uppercase A-Z and digits 2-7 only). Invalid values fail fast with clear error messages.

### 🐛 Fixed

- **Exit Mode ENV Config**: Fixed `TOR_EXIT_POLICY` environment variable handling in exit mode. The entrypoint now correctly generates `ExitPolicy` directives in torrc (e.g., `ExitPolicy reject *:*`) instead of bare policy rules. Exit relays now work with ENV-based configuration.
- **mktemp Portability**: Fixed `mktemp` usage in entrypoint to be POSIX-compliant by removing non-portable `-t` flag, improving compatibility across different shell environments.

### ⚙️ Changed

- **Version Bump**: Updated version string from v1.1.7 to v1.1.8 in startup banner and documentation.

> **BREAKING CHANGES:** None. All changes are backward compatible. `TOR_FAMILY_ID` validation only applies to ENV-based configurations; mounted torrc files are unaffected.

---

## [1.1.7] - 2026-03-02

### 🎉 Happy Family Support (Tor 0.4.9+)

This release introduces full support for Tor's new **Happy Family** system (`FamilyId`), which replaces the legacy `MyFamily` fingerprint-exchange workflow. Relay operators can now link all their relays into a family using a single cryptographic key instead of manually listing every fingerprint on every relay.

### ✨ Features

- **New Tool: `gen-family`**: Generate or view Tor Happy Family keys inside the container. Supports `gen-family <Name>` (generate), `gen-family --show` (view existing), `gen-family --force` (overwrite without backup), and `gen-family --help`.
- **`FamilyId` ENV Support**: New `TOR_FAMILY_ID` environment variable to set the `FamilyId` directive in generated torrc (guard/middle/exit modes).
- **`MyFamily` ENV Support**: New `TOR_MY_FAMILY` environment variable (comma-separated fingerprints) for backward compatibility with the legacy `MyFamily` directive.
- **Family Key Detection**: Phase 2 of the entrypoint now scans `/var/lib/tor/keys/*.secret_family_key` and logs detected keys at startup.
- **Import Workflow**: Operators can import existing family keys from bare-metal Tor installations via `docker cp` + ownership fix (`chown 100:101`).

### ⚙️ Changed

- **Entrypoint** (`docker-entrypoint.sh`): Phase 2 now detects family keys; config generation for guard/middle and exit modes appends `FamilyId` and `MyFamily` lines when the corresponding ENV vars are set.
- **Dockerfiles** (`Dockerfile`, `Dockerfile.edge`): Added `COPY` and `chmod +x` for the new `gen-family` tool.
- **`status` Tool** (`tools/status`): Now displays family key count and Happy Family configuration status after the fingerprint section.
- **Tool Count**: Increased from 5 to **6** diagnostic tools (status, health, fingerprint, bridge-line, gen-auth, **gen-family**).

### 📚 Documentation

- **README.md**: Added comprehensive "Happy Family (Tor 0.4.9+)" section with Option A (generate new key) and Option B (import existing key), persistence safety table, updated tools table (6 tools), updated features list, added gen-family to flowchart diagram, and added troubleshooting entries.
- **docs/ARCHITECTURE.md**: Updated all mermaid diagrams - container lifecycle, Phase 2, config generation (guard + exit), diagnostic tools subgraph, directory structure. Updated tool characteristics table, references table, and bumped doc version to 1.1.0.
- **docs/TOOLS.md**: Added full `gen-family` documentation section with usage, output examples, exit codes, and "Set Up Happy Family" workflow. Updated count from 5 → 6 tools and FAQ.
- **docs/DEPLOYMENT.md**: Updated diagnostic tool count references (5 → 6) across 3 locations.
- **docs/MIGRATION.md**: Added `gen-family --show` to post-migration diagnostic checklist.
- **docs/MIGRATION-V1.1.X.md**: Added `gen-family` to diagnostic tool verification checklist.
- **Example Configs**: Added commented `FamilyId` and `MyFamily` placeholders to `relay-guard.conf`, `relay-exit.conf`, and `relay-bridge.conf`.
- **Docker Compose Templates**: Added `TOR_FAMILY_ID` and `TOR_MY_FAMILY` env vars to guard, exit, and multi-relay templates with setup instructions (Option A/B).
- **Directory Authority Voting**: Added explanation of how Tor's 9 directory authorities vote on relay flags (Guard, Stable, Fast, HSDir) and that at least 5 of 9 must agree in consensus, across README, FAQ, DEPLOYMENT, and MULTI-MODE docs.
- **CIISS v2 ContactInfo**: Added documentation for the [ContactInfo Information Sharing Specification v2](https://nusenu.github.io/ContactInfo-Information-Sharing-Specification/) with field reference table, generator link, and `proof:uri-rsa` verification explanation. Updated all `TOR_CONTACT_INFO` examples to use CIISS v2 format.

### 🔁 CI/CD

- **validate.yml**: Added `gen-family` to shell lint, ShellCheck, tool extension verification (threshold 5 → 6), integration tool checks, help-flags test, file-permissions test, and tool-executability test. Updated build summary.
- **scripts/utilities/security-validation-tests.sh**: Added `gen-family` to tool security checks and syntax validation loops.
- **scripts/utilities/quick-test.sh**: Added Test 4.5 for `gen-family --help` executability. Updated summary line.

### 🛡️ Security

- **SECURITY.md**: Updated supported versions table (1.1.7 active, 1.1.6 maintenance). Added `gen-family` to diagnostic tools list.

> **BREAKING CHANGES:** None. The `TOR_FAMILY_ID` and `TOR_MY_FAMILY` environment variables are entirely optional. Existing deployments continue to work without changes.

---

## [1.1.6] - 2026-02-08

### 🐛 Fixed
* **Bind Mount Ownership:** Added startup detection for bind-mounted data/keys directories with incorrect ownership. The entrypoint now warns users with actionable `chown` commands when volumes are not writable by the `tor` user (UID 100, GID 101).
* **DEBUG Flag:** Made the `DEBUG` environment variable case-insensitive - now accepts `true`, `TRUE`, `1`, `yes`, `YES`.
* **Documentation Typo:** Fixed incorrect `chown 1000:1000` → `chown 100:101` in bridge migration troubleshooting guide.

### 🛡️ Security
* **Version Deprecation:** Deprecated and removed all versions prior to v1.1.5 from registries due to CVE-2025-15467 (OpenSSL, CVSS 9.8). Added deprecation notice to README and SECURITY.md.

### 📚 Documentation
* Added bind mount ownership troubleshooting section to README.
* Updated all version references across 20+ files to v1.1.6.
* Rewrote PR template as a clean reusable form.
* Updated CHANGELOG and SECURITY lifecycle tables.

### ⚙️ Changed
* Updated all Cosmos Cloud and Docker Compose template versions to 1.1.6.

---

## [1.1.5] - 2026-01-31

### 🛡️ Security Fixes
* OpenSSL Patch: Mitigated CVE-2025-15467 (CVSS 9.8 🚨) by upgrading openssl to version 3.5.5-r0 or later via the Alpine base image update.

### ⚙️ Changed
* Base Image: Updated Alpine from 3.23.2 to 3.23.3 to incorporate latest security patches and library improvements.
* Build Tooling: Updated docker/dockerfile tag to v1.21.

### 🐛 Fixed
* General Maintenance: Addressed various minor bug fixes and stability improvements.

---

## [1.1.4] - 2025-12-21

### 🏗️ Build Variants

| Variant | Base Image | Tags | Registries | Notes |
| :--- | :--- | :--- | :--- | :--- |
| **🟢 Stable** | Alpine 3.23.2 | `:latest`, `:1.1.4` | Docker Hub, GHCR | **Recommended** for production. |
| **⚠️ Edge** | Alpine Edge | `:edge`, `:1.1.4-edge` | GHCR Only | Testing only; not for production. |

### ⚙️ Changed (Refactor)
* **Tor Configuration:** Modernized relay templates and hardened security defaults.
* **Networking:** Disabled `DirPort` (set to `0`) across all relay types and compose templates.
* **Metadata:** Updated `ContactInfo` to follow the `ciissversion:2` format.
* **Policy Refinement:** Enhanced exit policies and security for Exit, Guard, and Bridge roles.
* **Synchronization:** Unified configurations across `cosmos-compose` and `docker-compose`.

### ➕ Added
* **Monitoring:** Integrated `nyx.config` for enhanced relay visualization.
* **Performance:** Added support for **IPv6** and hardware acceleration.

### 🗑️ Removed
* **Maintenance:** Updated retention policy to keep the last **7 releases** (14 tags) and purge legacy build artifacts.

> **BREAKING CHANGES:** None.

---

## [1.1.3] - 2025-12-05

### ⚡ Optimization & Tooling Update

Focused on refining deployment templates, enhancing security defaults in Compose configurations, and updating core dependencies to the latest stable releases.

### ✨ Features

- **New Tool**: Introduced `gen-auth` utility to easily generate hashed passwords for Tor Control Port authentication.
- **Healthchecks**: Added native Docker healthcheck definitions to all Compose templates for improved orchestration reliability.
- **Dependencies**: Updated base images to **Alpine 3.23.0** and **Golang 1.25.5** for latest security patches and performance.

### 🐳 Docker Compose Refactoring

- **Standardization**: Unified security options and capabilities (dropping unnecessary privileges) across all templates.
- **Cleanup**: Removed excessive comments and legacy instructions from Compose files for a cleaner, production-ready format.
- **Volumes**: Enhanced volume management configurations to ensure robust data persistence across container recreations.
- **Consistency**: Standardized environment variable definitions across Guard, Exit, and Bridge templates.

---

## [1.1.2] - 2025-11-18

Add Alpine edge variant with dual-track build strategy 🏗️✅ - 🟢/⚠️

### ✨ Features

- Add Dockerfile.edge for bleeding-edge Alpine builds
- Implement dual-track CI/CD strategy (stable + edge variants)
- Configure GHCR-only deployment for edge variant (prevents production use)
- Add separate SBOM generation for both variants
- Skip Docker Hub login for edge builds to optimize workflow

### 📚 Documentation

- Enhance comprehensive testing scripts documentation
  - Document quick-test.sh for ENV compatibility validation
  - Add test-build-v1.1.2.sh for local registry testing
  - Document security-validation-tests.sh usage
- Add project screenshots (bootstrapping, bridge-line, relay-status, Cosmos dashboard)
- Add project logo (src/logo.png)
- Update FAQ.md with edge variant information
- Refine PR template with security considerations
- Update workflows documentation for dual-track strategy

### 🔁 CI/CD Improvements

- Extend release.yml with matrix strategy for stable/edge builds
- Add variant-specific tagging (:edge, :1.1.2-edge)
- Remove dependabot.yml (manual dependency management preferred)
- Enhance validate.yml with Trivy SARIF upload

### 🏗️ Build Variants

🟢 Stable (Production):
- Base: Alpine 3.22.2
- Tags: :latest, :stable, :1.1.2
- Registries: Docker Hub + GHCR
- Recommended for production relays

⚠️ Edge (Testing):
- Base: Alpine edge (bleeding edge)
- Tags: :edge, :1.1.2-edge  
- Registries: GHCR only
- Latest Tor/obfs4 packages, NOT recommended for production

BREAKING CHANGES: None

---

## [1.1.1] - 2025-11-14

### 🚀 Major Release: Ultra-Optimized Build + Security Hardening + Configuration Enhancement

**This is a major architectural release** migrating from a dual-build structure (45MB) to a single ultra-optimized 16.8 MB build with busybox-only dependencies, comprehensive security hardening, simplified multi-mode operation, and enhanced configuration documentation.

### ✨ Core Features

* 🧅 **Multi-mode relay support** - Single container for guard/exit/bridge via `TOR_RELAY_MODE` environment variable
* 🌉 **Bridge relay with obfs4** - Integrated lyrebird for pluggable transport (drop-in replacement for `thetorproject/obfs4-bridge`)
* 🔧 **ENV-based configuration** - Full relay setup via environment variables (TOR_*, official bridge naming compatible)
* 📊 **Smart diagnostics** - 4 busybox-only tools: `status`, `health`, `fingerprint`, `bridge-line`
* 📉 **Image size** - Reduced from ~45MB to ~17.1 MB (busybox-only, no bash/python/jq)
* 🩺 **Smart healthcheck** - New `healthcheck.sh` works with both mounted configs and ENV variables
* 🔄 **Weekly rebuilds** - Automated Sunday 18:30 UTC rebuilds with latest Alpine/Tor patches (same version tag, fresh packages)

### 📖 Configuration & Documentation Enhancements (Latest)

* 🔧 **OBFS4V_* Variable Parsing (CRITICAL FIX)**
  - Fixed busybox regex incompatibility causing rejection of values with spaces
  - Issue: `OBFS4V_MaxMemInQueues="1024 MB"` was rejected with "dangerous characters" error
  - Solution: Rewrote validation (docker-entrypoint.sh:309-321) with busybox-compatible commands (`wc -l`, `tr -d`)
  - Impact: Bridge operators can now use advanced memory/CPU settings without errors

* 🌉 **PT_PORT Support & Official Bridge Naming**
  - Added `PT_PORT` environment variable for drop-in compatibility with `thetorproject/obfs4-bridge`
  - PT_PORT automatically detects and enables bridge mode (no `TOR_RELAY_MODE` needed)
  - Full compatibility with official bridge ENV naming: `OR_PORT`, `PT_PORT`, `EMAIL`, `NICKNAME`
  - Bridge templates now reference both TOR_* and official naming conventions

* 📊 **Bandwidth Configuration Clarification**
  - Documented `TOR_BANDWIDTH_RATE/BURST` → `RelayBandwidthRate/Burst` translation
  - Added Option 1 vs Option 2 explanations in all example configs:
    - `RelayBandwidthRate/Burst` (relay-specific traffic only, recommended)
    - `BandwidthRate/Burst` (all Tor traffic including directory requests)
  - Updated all templates with inline bandwidth option comments

* 📚 **Template & Example Updates**
  - **examples/relay-bridge.conf**: Added Method 2 with PT_PORT (official naming)
  - **examples/relay-exit.conf**: Added BandwidthRate/Burst as Option 2 with explanations
  - **examples/relay-guard.conf**: Added BandwidthRate/Burst as Option 2 for consistency
  - **cosmos-compose-bridge.json**: Added note about OR_PORT/PT_PORT alternative
  - **cosmos-compose-guard.json**: Documented bandwidth options (RelayBandwidth vs Bandwidth)
  - **cosmos-compose-exit.json**: Documented bandwidth options with recommendations
  - **docker-compose-bridge.yml**: Added official naming alternative info
  - **docker-compose-guard-env.yml**: Added bandwidth comment explaining options
  - **docker-compose-exit.yml**: Added bandwidth comment explaining options

* 📝 **Documentation Updates**
  - **CLAUDE.md**: Enhanced "Key Differences" section with bandwidth options
  - **templates/README.md**: Cross-references to bandwidth configuration methods
  - All templates now include comprehensive mounted config vs ENV comparison

### 🔒 Security Fixes

* 🔐 **Fixed 32 vulnerabilities** across 4 severity levels:
  - **6 CRITICAL**: Command injection (OBFS4V_*), health check failures, privilege escalation, validation gaps, workflow permissions, temp file races
  - **8 HIGH**: JSON injection, bash-specific features, permission handling
  - **10 MEDIUM**: Various validation and error handling improvements
  - **8 LOW**: Code quality and best practices
* 🛡️ **Minimal attack surface** - No exposed monitoring ports, all diagnostics via `docker exec` only
* 🔑 **Input validation** - Comprehensive ENV variable validation with whitespace trimming and OBFS4V_* whitelist
* 📋 **Security audit** - Complete vulnerability analysis documented in `SECURITY-AUDIT-REPORT.md`

### 📚 Templates & Documentation

* **Templates (13 files updated)**:
  - All Docker Compose templates now use smart `healthcheck.sh` script
  - Cosmos templates use `:latest` tag instead of hardcoded versions
  - Fixed image names (tor-guard-relay → onion-relay) and broken migration doc references
  - Added official bridge templates with `thetorproject/obfs4-bridge` ENV compatibility
* **Documentation consolidation**:
  - Removed outdated monitoring infrastructure references (metrics ports, HTTP endpoints, old ENV vars)
  - Clarified `jq` usage (must be on HOST machine, not in container)
  - Documented weekly build strategy (overwrites version tags with fresh packages)
  - Consolidated 7 migration docs into 2 canonical guides
  - Complete rewrite of TOOLS.md and MONITORING.md for v1.1.1 architecture

### ⚙️ Configuration & Compatibility

* 🔄 **Tor bootstrap logs** - Real-time progress (0-100%) now visible in `docker logs` for all relay types
* 🎨 **Enhanced emoji logging** - Clear visual feedback throughout (🔖, 💚, 🛑, 🗂️, 🔐, 🔧, 🔎, 📊, 🧩)
* 🔄 **Official bridge ENV compatibility** - 100% compatible with `OR_PORT`, `PT_PORT`, `EMAIL`, `NICKNAME`, `OBFS4V_*` variables
* 🧹 **Simplified bridge config** - Removed redundant `ExitPolicy reject *:*` (BridgeRelay 1 is sufficient)
* 📦 **Build metadata** - `/build-info.txt` with version, build date, and architecture

### 🔧 Dependency Management

* **Renovate** - Removed pinned package version tracking (only tracks Alpine base image), added OSV vulnerability scanning
* **Dependabot** - Added security labels, major version blocks, clarified unpinned package strategy
* **Hadolint** - Added trusted registries whitelist, comprehensive security check documentation

### 🗑️ Removed (Simplification)

* ❌ **Monitoring ENV vars** - ENABLE_METRICS, ENABLE_HEALTH_CHECK, ENABLE_NET_CHECK, METRICS_PORT (use external monitoring)
* ❌ **Deprecated tools** - metrics, dashboard, net-check, view-logs, setup, metrics-http (consolidated to 4 core tools)
* ❌ **Built-in monitoring stack** - Prometheus/Grafana/Alertmanager (use external solutions)
* ❌ **Dual-build structure** - Single optimized build only

### 🐛 Bug Fixes

* **CRITICAL**: Fixed TOR_CONTACT_INFO validation crash loops (whitespace handling, line count check)
* **CRITICAL**: Fixed missing Tor bootstrap logs in container output (added `Log notice stdout`)
* Fixed healthcheck failures on ENV-based deployments
* Fixed version references across all scripts and documentation
* Corrected image size documentation (~35MB → ~16.8 MB)

### 🔄 Migration Path

**Breaking Changes:**
- ENV vars `ENABLE_METRICS`, `ENABLE_HEALTH_CHECK`, `ENABLE_NET_CHECK`, `METRICS_PORT` no longer supported
- Tools `metrics`, `dashboard`, `net-check`, `view-logs`, `setup`, `metrics-http` removed

**Upgrade Steps:**
1. Remove old monitoring ENV vars from your deployment configs
2. Update to use `TOR_RELAY_MODE` environment variable (guard/exit/bridge)
3. Use external monitoring with `docker exec <container> health` for JSON health data
4. **Guard/Middle relays**: Seamless upgrade with mounted configs
5. **Bridges from official image**: Requires UID ownership fix (`chown -R 100:101`)

**See**: `docs/MIGRATION-V1.1.X.md` for complete step-by-step migration instructions.

---

## [1.1.0] - 2025-11-08

### ✨ Added

* 🧩 Input sanitization helpers to ensure safe numeric evaluation in all status checks
* 🧱 Integrated integer guard function (`is_integer`) to prevent bad-number shell errors
* 🕒 Unified UTC timestamp formatting for consistent output across commands

### 🧰 Improvements

* 📜 `view-logs`: Compact single-line statistics (`📊 Stats: total | errors | warnings`) for cleaner display
* 📊 The dashboard script now requires API token authentication for secure access and features a new notification UI for better visibility.
* 🔑 The fingerprint script has been overhauled for cleaner output, better input validation, and a more helpful guide.
* 🧰 General shell cleanup and quoting improvements for portability across BusyBox, Alpine, and Debian-based images

### 🐛 Fixed

* 🧹 Removed recurring `sh: 0: bad number` warnings in `status` output
* 🧩 Fixed multi-line log stats formatting issue in `view-logs`
* 🔧 Corrected potential false negatives in `BOOTSTRAP_PERCENT` extraction
* 🧠 Resolved misinterpretation of empty variables during numeric comparisons
* 🥬 Configuration, health checks, and monitoring have been refined for better reliability and integration.

### 🔒 Security

* 🧩 Verified `set -e` safety to prevent unintended script exits on minor grep/curl failures
* 🐳 Docker Compose now includes enhanced security configurations and persistent volume support to prevent data loss.
* 📋 Cosmos templates have been updated with more secure and sensible default environment variables.

---

## [1.0.9] - 2025-11-07

🧠 **Maintenance and polish release** improving shell reliability, output consistency, and readability across status and log utilities.
🎨 Streamlined log viewer formatting, sanitized numeric parsing, and removed noisy shell error messages for cleaner execution.

### ✨ Added

* 🧩 Input sanitization helpers to ensure safe numeric evaluation in all status checks
* 🧱 Integrated integer guard function (`is_integer`) to prevent bad-number shell errors
* 🕒 Unified UTC timestamp formatting for consistent output across commands

### 🧰 Improvements

* 📜 `view-logs`: Compact single-line statistics (`📊 Stats: total | errors | warnings`) for cleaner display
* 🧅 `status`: Sanitized bootstrap parsing and error-free numeric comparison
* ⚙️ Hardened `set -e` handling with fallback defaults for missing values
* 🧩 Refined whitespace and CRLF handling in log parsing for improved compatibility
* 🧰 General shell cleanup and quoting improvements for portability across BusyBox, Alpine, and Debian-based images

### 🐛 Fixed

* 🧹 Removed recurring `sh: 0: bad number` warnings in `status` output
* 🧩 Fixed multi-line log stats formatting issue in `view-logs`
* 🔧 Corrected potential false negatives in `BOOTSTRAP_PERCENT` extraction
* 🧠 Resolved misinterpretation of empty variables during numeric comparisons

### 🔒 Security

* 🧩 Verified `set -e` safety to prevent unintended script exits on minor grep/curl failures
* 🛡️ Strengthened input filtering to prevent malformed log content injection into shell context

---

### 🧠 Developer Notes

* ✅ Both `status` and `view-logs` scripts tested under Alpine BusyBox and Debian Dash shells
* 🧩 Scripts now fully pass shellcheck (`shfmt` + POSIX mode) validation
* 💡 Compatible with Docker health checks and CI/CD validation hooks

---

**🧱 Summary:**

> *Tor Guard Relay v1.0.9 delivers a clean, error-free shell experience, better numeric safety, and a polished command-line output for monitoring and log viewing.*

---

## [1.0.8] - 2025-11-07

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
* **📦 Current Stable:** v1.1.8 (April 3, 2026)
* **🔗 Latest Release:** [GitHub Releases](https://github.com/r3bo0tbx1/tor-guard-relay/releases/latest)
* **🐳 Docker Images:**

  * [GHCR Package](https://github.com/r3bo0tbx1/tor-guard-relay/pkgs/container/onion-relay)
  * [Docker Hub](https://hub.docker.com/r/r3bo0tbx1/onion-relay)

---

## 🔖 Version Support

| Version   | Status                | Support Level                               |
| --------- | --------------------- | ------------------------------------------- |
| **1.1.8** | 🟢 🛡️ **Active**     | Full support (current stable)               |
| **1.1.7** | 🟡 📦 **Maintenance** | Security updates only                       |
| **1.1.6** | 🟡 🔧 **Maintenance** | Security + critical fixes only              |
| **< 1.1.5** | 🔴 ❌ **Deprecated**   | Removed - contains CVE-2025-15467 (OpenSSL CVSS 9.8). Upgrade immediately. |

---

## 🔗 Release Links

[1.1.8]: https://github.com/r3bo0tbx1/tor-guard-relay/releases/tag/v1.1.8
[1.1.7]: https://github.com/r3bo0tbx1/tor-guard-relay/releases/tag/v1.1.7
[1.1.6]: https://github.com/r3bo0tbx1/tor-guard-relay/releases/tag/v1.1.6
[1.1.5]: https://github.com/r3bo0tbx1/tor-guard-relay/releases/tag/v1.1.5
[1.1.4]: https://github.com/r3bo0tbx1/tor-guard-relay/releases/tag/v1.1.4
[1.1.3]: https://github.com/r3bo0tbx1/tor-guard-relay/releases/tag/v1.1.3
[1.1.2]: https://github.com/r3bo0tbx1/tor-guard-relay/releases/tag/v1.1.2
[1.1.1]: https://github.com/r3bo0tbx1/tor-guard-relay/releases/tag/v1.1.1
[1.1.0]: https://github.com/r3bo0tbx1/tor-guard-relay/releases/tag/v1.1.0
[1.0.9]: https://github.com/r3bo0tbx1/tor-guard-relay/releases/tag/v1.0.9
[1.0.8]: https://github.com/r3bo0tbx1/tor-guard-relay/releases/tag/v1.0.8
[1.0.7]: https://github.com/r3bo0tbx1/tor-guard-relay/releases/tag/v1.0.7
[1.0.6]: https://github.com/r3bo0tbx1/tor-guard-relay/releases/tag/v1.0.6
[1.0.5]: https://github.com/r3bo0tbx1/tor-guard-relay/releases/tag/v1.0.5
[1.0.4]: https://github.com/r3bo0tbx1/tor-guard-relay/releases/tag/v1.0.4
[1.0.3]: https://github.com/r3bo0tbx1/tor-guard-relay/releases/tag/v1.0.3
[1.0.2]: https://github.com/r3bo0tbx1/tor-guard-relay/releases/tag/v1.0.2
[1.0.1]: https://github.com/r3bo0tbx1/tor-guard-relay/releases/tag/v1.0.1
[Unreleased]: https://github.com/r3bo0tbx1/tor-guard-relay/compare/v1.0.1...HEAD

---

## 🙏 Contributors

Thank you to all contributors who have helped make this project better!

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
