# Release Automation Scripts

This directory contains automation scripts for managing releases, version updates, and release notes generation.

## Overview

The release automation includes three main components:

1. **Auto-generate release notes** from conventional commits
2. **Auto-update version** numbers across all documentation
3. **SBOM generation** (CycloneDX & SPDX) integrated into CI/CD

## Scripts

## 🛠️ Local commands

```sh
sh scripts/release/update-version.sh 2.2.0 --dry-run
python3 scripts/release/check-versions.py
python3 scripts/testing/check-dependency-pins.py
python3 scripts/testing/check-docs.py
sh scripts/release/generate-release-notes.sh 2.2.0 v2.1.0 --output /tmp/release-draft.md
```

The version checker discovers tracked and nonignored documentation, scripts and workflows, synchronizing current Alpine references from the stable Dockerfile. `--write` applies changes; `--version X.Y.Z` also updates managed current project references. Historical changelog entries and historical migration release semantics are retained.

The notes generator handles leading gitmoji, conventional scopes and multiline breaking-change bodies, and keeps emoji headings by default. Use `--no-emoji` or `--format plain` only when you want plain output. Its output is a review draft. The release workflow publishes the curated file at `docs/releases/vVERSION.md`.


### 📝 Curated notes and version markers

Use the notes generator for a local review draft; the hosted release publishes `docs/releases/vVERSION.md`. The version synchronizer updates explicit current markers and validates examples against the stable Dockerfile, leaving historical changelog entries intact. No helper commits, pushes, signs or publishes automatically.

---

## CI/CD Integration

## 🏗️ Candidate pipeline

1. Resolve the triggering release tag, or the latest stable tag for a scheduled rebuild. Require its commit to be an ancestor of main. Resolve the current reviewed main security-policy SHA separately.
2. Build stable and edge candidates for AMD64 and ARM64, without publishing.
3. Run offline behavior tests and component security floors against each loaded image.
4. Analyze Go source reachability with the tagged source/lock/toolchain, proving that the transport matches the candidate byte for byte. Generate SBOMs and run blocking vulnerability/secret scans. Use current main security policy and component floors even when rebuilding an older tag.
5. Save each validated image, checksum, inspect metadata and scan evidence.
6. Load those same image archives in promotion, verify image identity, publish unique staging references, and assemble version/alias manifests from their digests.
7. Publish curated release notes and attach security evidence only after promotion succeeds.

Schedules rebuild the latest released tag, not unreleased main. A dependency update on main reaches scheduled rebuilds only after a new reviewed release tag contains it. Manual dispatch defaults to validation without publication. The retention workflow produces a read-only registry inventory; it cannot delete rollback images. Review manifests, architecture digests and rollback references before any manual deletion.

The promotion job needs Docker Hub credentials and GitHub package permissions. Cross-registry promotion must be observed in the first maintainer-triggered run; local testing does not establish remote registry behavior.

### ✅ Required validation checks

The validation workflow preserves the four names required by the main branch ruleset: `🔍 Lint and Validate`, `🏗️ Build Docker Image`, `🧪 Integration Tests` and `🛡️ Security Scan`. The last three aggregate the complete stable/edge and AMD64/ARM64 candidate matrix, including behavioral acceptance and security policy. They run even after a dependency fails and succeed only when source validation and every image job succeed.

Candidate artifacts are replaced on workflow reruns; registry staging tags include both the run ID and attempt so a retry does not reuse an earlier staging tag. Version and alias tags remain mutable for validated scheduled rebuilds.

### 📦 Dependency update boundaries

Renovate proposes Docker base, GitHub Actions, locked Go module, scanner-tool and upstream Lyrebird source-pin updates. Its `custom.regex` manager follows upstream `main` with `git-refs`, keeping all four `LYREBIRD_REVISION` occurrences synchronized. Source and Go updates require review and the full candidate matrix. The bot integration must be enabled separately; configuration does not run the bot.

Docker/toolchain, source and Go proposals can be created on any Renovate run without a weekly window. Security-alert PRs require review and bypass normal update scheduling. Review upstream changes against the independently maintained lock; patch a vulnerable Go dependency without waiting for a Lyrebird source commit when compatible.

Indirect Go updates are explicitly enabled. Renovate's OSV security PR coverage is limited to direct dependencies; Go source analysis and image scans cover additional findings that need maintainer triage. Do not assume the bot can automatically remediate every transitive vulnerability.

The `build/lyrebird` directory contains the reviewed Go graph, while the Docker builder fetches the pinned Lyrebird source. Renovate can propose a version with only its go.mod checksum. Both builders download the complete selected graph, authenticate module content through Go's checksum verification, verify the module cache, and require go.mod to remain unchanged before read-only compilation. Automatic toolchain switching is disabled: review and update the pinned builder when a dependency requires a newer Go version. Do not run `go mod tidy` in the lock-only directory; it needs the actual Lyrebird source to preserve the required packages.

After a Docker base version proposal, run `python3 scripts/release/check-versions.py --write` and review the synchronized examples and OCI base label. The consistency gate deliberately rejects unsynchronized documentation.

<a id="expedited-security-response"></a>

### 🚨 Expedited security response

Do not wait for a scheduled rebuild or feature release when an applicable security fix is available. Update the affected source pin, Go lock, builder/base or component floor, run the full candidate gates, merge the reviewed change and publish a new patch tag. A merged lock/source update alone cannot change images rebuilt from an older release tag.

If no fix exists, assess exposure and mitigate it, for example by disabling an affected transport or reviewing a backport. HIGH/CRITICAL image findings and reachable Go findings block publication even without a fix. There is no automatic ignore list or severity downgrade. Any policy change for demonstrated non-applicability needs an explicit reviewed change with supporting evidence.

### 🔎 Continuous security watch

The read-only `🔒🧅 Security watch` workflow runs on relevant main changes, manual dispatch and every six hours. It analyzes current pinned source/Go locks for both architectures and independently scans the exact published stable/edge architecture digests from Docker Hub and GHCR using current advisory data. It records manifests, image IDs and complete reports, including failure diagnostics, for 30 days. Failures appear in Actions; configure your GitHub Actions notifications to receive them.

The published-image lane performs package/secret assessment; source reachability is reported for the current checkout, which may differ from a published release. GitHub schedules and advisory ingestion can be delayed. Monitoring never publishes images, changes a live relay, opens issues or sends third-party messages.

Each published-image summary shows the version/source labels, exact scanned image, HIGH/CRITICAL packages, installed versions and reported fixes. A main merge can pass candidate validation while the monitor flags older registry images. Publish the reviewed release tag, verify the replacement digests, then rescan them. The monitor retains its failure status while blocking findings remain; an unfixed finding requires exposure assessment and mitigation.

---

## Release Workflow

### 🧭 Maintainer publication order

1. Review the local branch, curated notes, compatibility changes and candidate evidence.
2. Push the branch yourself and open a PR; wait for all required checks on its latest revision.
3. Merge through the repository's review and linear-history policy.
4. Create and push the reviewed release tag yourself. Observe all four candidate gates before promotion.
5. Verify both architectures and exact published digests in Docker Hub and GHCR; retain evidence and rollback references.
6. Upgrade the real relay deliberately after encrypted recovery rehearsal, then check fingerprint continuity, fresh bootstrap and public reachability.

The release workflow uses immutable candidate evidence and promotes the same images. A main push does not publish a version; manual dispatch defaults to validation. Current reviewed policy is separate from tagged source. Trusted main verifies the full source and policy commit SHAs against reviewed ancestry before preparing separate immutable worktrees. Checkout credentials are not retained.

## 🛡️ Evidence and rollback

Retain source and security-policy SHAs, architecture, image ID/digest, Tor version, Alpine/OpenSSL packages, Lyrebird revision/Go dependency graph, Go reachability report, SBOM and the full vulnerability/secret report. Promotion blocks secrets, all HIGH/CRITICAL image findings, and reachable Go vulnerabilities regardless of a fixed version or severity label. Unfixed and lower-severity findings remain in the report for assessment. Scanner failures and malformed/incomplete reports fail closed. Never call a candidate published based only on a local build.

Preserve the previous validated image digest, deployment and encrypted backup before upgrading. Do not rewrite historical release descriptions when updating current examples.

---

## SBOM (Software Bill of Materials)

### What is SBOM?

SBOM provides transparency about software components and dependencies:

- **Security**: Identify vulnerable packages quickly
- **Compliance**: Meet regulatory requirements (NTIA, EO 14028)
- **Supply chain**: Track third-party components
- **Auditing**: Know exactly what's in your container

### SBOM Formats

**CycloneDX** (OWASP standard)
- JSON: Machine-readable, API-friendly
- XML: Enterprise tooling compatibility

**SPDX** (Linux Foundation standard)
- JSON: Modern, developer-friendly
- Tag-value: Traditional, widely supported

**Table** (Human-readable)
- Plain text listing of all packages
- Quick manual inspection

### Using SBOM Files

**Check for vulnerabilities:**

```bash
# After the maintainer publishes v2.2.0, download its evidence archive.
# Until then, use the retained candidate artifacts from the validation run.
curl --fail --location --output release-evidence.tar.gz \
  https://github.com/r3bo0tbx1/tor-guard-relay/releases/download/v2.2.0/release-evidence.tar.gz
mkdir release-evidence
tar -xzf release-evidence.tar.gz -C release-evidence
# Select one candidate's SBOM; the archive retains all four variants.
cp release-evidence/candidate-stable-amd64/sbom/sbom.cdx.json sbom.cdx.json

# Scan with Grype
grype sbom:sbom.cdx.json

# Scan with Trivy
trivy sbom sbom.cdx.json
```

**Integrate with security tools:**

```bash
# Import into Dependency-Track
curl -X POST "https://dtrack.example.com/api/v1/bom" \
  -H "X-Api-Key: $API_KEY" \
  -F "bom=@sbom.cdx.json"

# Analyze with Syft
syft sbom.cdx.json

# View package list
jq '.components[] | {name, version, type}' sbom.cdx.json
```

**Example SBOM Content:**

```json
{
  "bomFormat": "CycloneDX",
  "specVersion": "1.4",
  "version": 1,
  "metadata": {
    "component": {
      "type": "container",
      "name": "onion-relay",
      "version": "1.1.2"
    }
  },
  "components": [
    {
      "type": "library",
      "name": "alpine-baselayout",
      "version": "3.4.3-r2",
      "purl": "pkg:apk/alpine/alpine-baselayout@3.4.3-r2"
    },
    {
      "type": "library",
      "name": "tor",
      "version": "0.4.8.10-r0",
      "purl": "pkg:apk/alpine/tor@0.4.8.10-r0"
    }
  ]
}
```

## Best Practices

### Conventional Commits

Follow the [Conventional Commits](https://www.conventionalcommits.org/) specification:

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

**Benefits:**
- Automated changelog generation
- Semantic versioning hints
- Better commit history readability
- Easier rollback and debugging

### Version Numbering

Follow [Semantic Versioning](https://semver.org/) (SemVer):

- **MAJOR** (1.0.0 → 2.0.0): Breaking changes
- **MINOR** (1.1.0 → 1.2.0): New features (backward compatible)
- **PATCH** (1.1.1 → 1.1.2): Bug fixes (backward compatible)

**Examples:**
- `feat!: remove old ENV variables` → MAJOR bump
- `feat: add migration script` → MINOR bump
- `fix: resolve parsing error` → PATCH bump

### CHANGELOG.md Format

Use [Keep a Changelog](https://keepachangelog.com/) format:

```markdown
# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

## [v1.2.0] - 2025-01-14

### Added
- Migration assistant script for official Tor bridge image migration
- SBOM generation in CI/CD workflow
- Auto-generated release notes from conventional commits

### Changed
- Updated release workflow with SBOM integration
- Improved release notes generation with fallback mechanism

### Fixed
- OBFS4V parsing issue with values containing spaces
- Mermaid diagram rendering on GitHub

## [v1.1.1] - 2025-01-10

### Fixed
- Busybox compatibility in OBFS4V validation
- Numeric sanitization in diagnostic tools
```

## Troubleshooting

### Release Notes Not Generating

**Problem**: Auto-generation finds no commits

**Solution:**
```bash
# Check git history
git log --oneline

# Verify previous tag exists
git describe --tags --abbrev=0

# Specify previous version explicitly
sh scripts/release/generate-release-notes.sh 2.2.0 v2.1.0 --output /tmp/release-draft.md
```

### Version Update Missing Files

**Problem**: Not all files were updated

**Solution:**
```bash
# Check what current version was detected
sh scripts/release/update-version.sh 2.2.0 --dry-run

# Search for old version manually
rg "RELAY_VERSION|Alpine|onion-relay:" README.md docs templates

# Verify managed fields without rewriting historical releases.
python3 scripts/release/check-versions.py
```

### SBOM Generation Fails

**Problem**: Syft can't access image

**Solution:**
```bash
# Ensure image exists locally or in registry
docker pull ghcr.io/r3bo0tbx1/onion-relay:2.2.0

# Generate SBOM locally for testing
docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  anchore/syft:latest \
  ghcr.io/r3bo0tbx1/onion-relay:2.2.0 \
  -o cyclonedx-json
```

### Workflow Permission Errors

**Problem**: `Resource not accessible by integration`

**Solution:** Ensure workflow has correct permissions:

```yaml
permissions:
  contents: write      # Create releases
  packages: write      # Push to GHCR
  security-events: write  # Upload SARIF
```

## Additional Resources

- **Conventional Commits**: https://www.conventionalcommits.org/
- **Semantic Versioning**: https://semver.org/
- **Keep a Changelog**: https://keepachangelog.com/
- **CycloneDX**: https://cyclonedx.org/
- **SPDX**: https://spdx.dev/
- **NTIA SBOM**: https://www.ntia.gov/sbom

## Contributing

When adding new release automation features:

1. Update this README with usage examples
2. Add tests for new functionality
3. Update `.github/workflows/release.yml` if needed
4. Follow existing script patterns (POSIX sh, color output, error handling)
5. Document all environment variables and options
