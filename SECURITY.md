# 🔒 Security Policy

SPDX-License-Identifier: MIT

[Documentation](docs/README.md) · [Encrypted recovery](docs/BACKUP.md) · [Release process](scripts/release/README.md)

This policy covers the image, host scripts and workflows. Report Tor network vulnerabilities directly to [The Tor Project](https://www.torproject.org/).

## 🏷️ Supported versions

Only the latest **published** release receives maintenance and scheduled rebuilds. The latest published release remains v2.1.0 while this checkout prepares v2.2.0. Publication of v2.2.0 ends support for earlier releases; historic tags remain available for reproducibility.

## 🚨 Urgent Tor update

[Tor 0.4.9.14](https://forum.torproject.org/t/security-release-0-4-9-14/22241) addresses high-severity issues affecting clients, onion services, authorities and relays. Update as soon as possible. Detailed issue tickets were initially withheld under upstream's disclosure policy; do not infer undisclosed exploit details.

Both Dockerfiles enforce Tor >= 0.4.9.14. Operators must recreate the container from a validated updated image to replace Tor; torrc edits and SIGHUP do not update binaries.

## 📦 Dependency policy

Stable Alpine 3.24.2 and Go 1.27.2 are pinned by digest. Lyrebird source is pinned and its Go module graph is checked in. Pion STUN is 3.1.7, above the 3.1.5 security floor for [CVE-2026-54909](https://github.com/advisories/GHSA-34rh-wp3j-6cxc). The actual transport binary is inspected during candidate validation.

OpenSSL's installed libssl3 must be at least 3.5.9. Container updates do not patch the host kernel; operators remain responsible for host security updates.

Scans block fixed HIGH/CRITICAL vulnerabilities and secrets. Full reports and SBOMs remain release evidence, including findings outside that blocking policy. The local module scan reports [GO-2026-5932](https://pkg.go.dev/vuln/GO-2026-5932), an unfixed advisory about deprecated x/crypto OpenPGP packages; assess package inclusion instead of calling the whole module clean.

## 🛡️ Runtime boundary

The image runs as UID 100/GID 101 with Tini and POSIX shell diagnostics. Deployment examples restrict capabilities and use no-new-privileges. Host networking shares the host network namespace; configure firewall and provider rules deliberately.

Mounted torrc files remain authoritative. Generated config is validated before atomic replacement. Diff output redacts every value; validation suppresses raw configuration diagnostics by default. Explicit debug mode may expose details, so review logs privately.

Prepare persistent-volume ownership yourself. Startup cannot silently heal arbitrary host permissions. Keep keys, family material, pt_state and active config together in encrypted recovery. Offline or external master keys need separate custody.

## 🚦 Release gates

All stable/edge AMD64/ARM64 candidates must pass behavior, component floors and security checks before promotion. Promotion loads the validated images and checks their identity; it does not rebuild. Scheduled rebuilds use the latest released tag. Pin updates and new features require a reviewed source release.

Cleanup is manual and separate from validation. Preserve a rollback image, deployment and verified encrypted backup before upgrading.

## 📣 Reporting a Vulnerability

**Do NOT report security vulnerabilities through public GitHub issues.**

### How to Report

**Email:** r3bo0tbx1@brokenbotnet.com
**Subject:** `[SECURITY] Tor Guard Relay – <short summary>`

Please use my PGP key [0xB3BD6196E1CFBFB4 🔑](https://keys.openpgp.org/vks/v1/by-fingerprint/33727F5377D296C320AF704AB3BD6196E1CFBFB4) to encrypt if your report contains sensitive technical details.

### Information to Include

1. **Description** of the vulnerability
2. **Steps to reproduce** the issue
3. **Impact assessment** (who is affected, what's at risk)
4. **Suggested fix** (if you have one)
5. **Your contact information** for follow-up

### What to Expect

- **Acknowledgment:** within 48 hours
- **Initial assessment:** within 1 week
- **Status updates:** every 2 weeks until resolved

**Resolution timelines:**

| Severity | Response Time |
|-----------|----------------|
| Critical | 1-7 days |
| High | 1-4 weeks |
| Medium | 1-3 months |
| Low | Next release cycle |

### Coordinated Disclosure

We follow responsible disclosure practices:
1. **Report received** → We acknowledge and investigate
2. **Fix developed** → We create and test a patch
3. **Coordinated release** → We agree on disclosure timing
4. **Public disclosure** → We release the fix and advisory
5. **Credit given** → We acknowledge the reporter (unless anonymity is requested)

---

## 🔐 Operator responsibilities

- Restrict configuration, key and recovery-identity access; keep private material out of Git and diagnostic reports.
- Validate staged recovery before replacing live data; never activate duplicate identities.
- Treat readiness, public reachability and consensus membership as separate evidence.
- Expose control ports only with deliberate authentication and access restrictions.
- Review [legal considerations](docs/LEGAL.md) before running an exit.

## 📬 Contact

Security: [r3bo0tbx1@brokenbotnet.com](mailto:r3bo0tbx1@brokenbotnet.com). General questions: [project discussions](https://github.com/r3bo0tbx1/tor-guard-relay/discussions).
