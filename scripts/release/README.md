# Release Automation Scripts

This directory contains automation scripts for managing releases, version updates, and release notes generation.

## Overview

The release automation includes three main components:

1. **Auto-generate release notes** from conventional commits
2. **Auto-update version** numbers across all documentation
3. **SBOM generation** (CycloneDX & SPDX) integrated into CI/CD

## Scripts

### generate-release-notes.sh

Auto-generate release notes from git commit history using conventional commit format.

**Features:**
- Parses conventional commits (feat, fix, docs, chore, etc.)
- Categorizes changes by type with emojis
- Detects breaking changes automatically
- Supports multiple output formats (markdown, github, plain)
- Falls back to all commits if no conventional commits found

**Usage:**

```bash
# Auto-detect previous version and generate notes
./scripts/release/generate-release-notes.sh 1.1.2

# Specify previous version explicitly
./scripts/release/generate-release-notes.sh 1.1.2 1.1.1

# Save to file
./scripts/release/generate-release-notes.sh -o RELEASE_NOTES.md 1.2.0

# GitHub format (used by CI)
./scripts/release/generate-release-notes.sh --format github 1.2.0

# Show only breaking changes
./scripts/release/generate-release-notes.sh --breaking-only 1.2.0

# Disable emojis
./scripts/release/generate-release-notes.sh --no-emoji 1.2.0
```

**Conventional Commit Types:**

| Type | Emoji | Description |
|------|-------|-------------|
| `feat:` | ✨ | New features |
| `fix:` | 🐛 | Bug fixes |
| `docs:` | 📚 | Documentation changes |
| `perf:` | ⚡ | Performance improvements |
| `refactor:` | ♻️ | Code refactoring |
| `test:` | ✅ | Testing changes |
| `build:` | 🏗️ | Build system changes |
| `ci:` | 👷 | CI/CD changes |
| `chore:` | 🔧 | Maintenance tasks |
| `style:` | 💄 | Code style changes |
| `revert:` | ⏪ | Reverts |

**Breaking Changes:**

Breaking changes are detected in two ways:
1. **Type suffix**: `feat!:` or `fix!:` (exclamation mark after type)
2. **Body keyword**: `BREAKING CHANGE:` in commit body

**Example Commits:**

```bash
# Feature
git commit -m "feat: add migration assistant script"

# Bug fix
git commit -m "fix: resolve OBFS4V parsing issue with spaces"

# Breaking change (method 1)
git commit -m "feat!: remove legacy ENV variable support"

# Breaking change (method 2)
git commit -m "feat: redesign configuration system

BREAKING CHANGE: Old ENV variables are no longer supported.
Use TOR_* prefix instead."

# Documentation
git commit -m "docs: update README with migration guide"

# Multiple types in one commit
git commit -m "feat: add SBOM generation

- Generates CycloneDX and SPDX formats
- Integrates with CI/CD workflow
- Attaches to GitHub releases"
```

**Output Example:**

```markdown
## 🧅 Tor Guard Relay v1.2.0

### ✨ Features

- Add migration assistant script (`a1b2c3d4`) by John Doe
- Add SBOM generation to CI/CD (`e5f6g7h8`) by Jane Smith

### 🐛 Bug Fixes

- Resolve OBFS4V parsing issue with spaces (`i9j0k1l2`) by John Doe
- Fix Mermaid diagram rendering in GitHub (`m3n4o5p6`) by Jane Smith

### 📚 Documentation

- Update README with migration guide (`q7r8s9t0`) by John Doe
- Add comprehensive FAQ (`u1v2w3x4`) by Jane Smith

---

**Full Changelog**: v1.1.1...v1.2.0
```

### update-version.sh

Auto-update version numbers across all documentation, templates, and configuration files.

**Features:**
- Updates version in README.md (badges, examples)
- Updates CHANGELOG.md (adds new version header)
- Updates templates/*.yml (Docker Compose image tags)
- Updates templates/*.json (Cosmos Cloud templates)
- Updates docs/*.md (all documentation)
- Updates CLAUDE.md (project documentation)
- Creates backups by default (.bak files)
- Dry-run mode to preview changes

**Usage:**

```bash
# Update version (creates .bak backups)
./scripts/release/update-version.sh 1.1.2

# Preview changes without modifying files
./scripts/release/update-version.sh --dry-run 1.2.0

# Update without creating backups
./scripts/release/update-version.sh --no-backup 1.1.2

# Works with or without 'v' prefix
./scripts/release/update-version.sh v1.1.2
```

**What Gets Updated:**

1. **README.md**
   - Version badges
   - Docker image tags in examples
   - Version references in text

2. **CHANGELOG.md**
   - Adds new version header after `## [Unreleased]` section
   - Format: `## [v1.1.2] - 2025-01-14`

3. **templates/*.yml** (Docker Compose)
   - `image:` tags from `onion-relay:1.1.1` → `onion-relay:1.1.2`

4. **templates/*.json** (Cosmos Cloud)
   - `"image":` fields in JSON templates

5. **docs/*.md** (All documentation)
   - Version references throughout docs

6. **CLAUDE.md** (Project instructions)
   - Version references for Claude Code

**Example Output:**

```
ℹ Current version detected: 1.1.1
ℹ New version: 1.1.2
ℹ Updating README.md...
✅ Updated: README.md
ℹ Updating CHANGELOG.md...
✅ Added version 1.1.2 to CHANGELOG.md
ℹ Updating Docker Compose templates...
✅ Updated: templates/docker-compose-guard-env.yml
✅ Updated: templates/docker-compose-exit.yml
✅ Updated: templates/docker-compose-bridge.yml
...

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ Version Update Complete
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Current Version: 1.1.1
  New Version:     1.1.2
  Files Updated:   15

🔵 Backup files created with .bak extension
🔵 To restore: for f in *.bak; do mv "$f" "${f%.bak}"; done

Next Steps:
  1. Review changes: git diff
  2. Update CHANGELOG.md with release notes
  3. Commit changes: git add -A && git commit -m "chore: bump version to 1.1.2"
  4. Create tag: git tag -a v1.1.2 -m "Release v1.1.2"
  5. Push: git push && git push --tags
```

**Rollback:**

If you need to undo changes:

```bash
# Restore from .bak files
for f in *.bak **/*.bak; do
  [ -f "$f" ] && mv "$f" "${f%.bak}"
done

# Or use git to reset
git checkout -- .
```

## CI/CD Integration

The release workflow (`.github/workflows/release.yml`) integrates all three automation components:

### Automated SBOM Generation

When a release tag is pushed, the workflow automatically:

1. **Builds Docker image** with multi-arch support (AMD64, ARM64)
2. **Generates SBOM** in multiple formats:
   - **CycloneDX JSON** (`sbom-cyclonedx-v1.1.2.json`)
   - **CycloneDX XML** (`sbom-cyclonedx-v1.1.2.xml`)
   - **SPDX JSON** (`sbom-spdx-v1.1.2.json`)
   - **SPDX tag-value** (`sbom-spdx-v1.1.2.spdx`)
   - **Human-readable table** (`sbom-table-v1.1.2.txt`)
3. **Uploads SBOM** as workflow artifacts (90-day retention)
4. **Attaches SBOM** to GitHub release as downloadable assets

### Automated Release Notes

The workflow generates release notes with this priority:

1. **CHANGELOG.md** (preferred)
   - Extracts section for specific version
   - Format: `## [v1.1.2] - 2025-01-14` or `## v1.1.2`

2. **Auto-generated from commits** (fallback)
   - Uses `generate-release-notes.sh` script
   - Parses conventional commits
   - Categorizes by type with emojis

3. **Simple commit list** (last resort)
   - Basic git log output
   - Shows commit messages with hashes

**Release Note Sections:**

Every release includes:
- 📦 Changes (categorized by type)
- 🐳 Docker Images (pull commands for GHCR and Docker Hub)
- 📋 SBOM (links to downloadable SBOM files)
- 🔗 Full Changelog (compare link)

## Release Workflow

### Manual Release Process

For creating a new release manually:

```bash
# 1. Update version numbers across all files
./scripts/release/update-version.sh 1.2.0

# 2. Review changes
git diff

# 3. Generate release notes (optional, to preview)
./scripts/release/generate-release-notes.sh 1.2.0

# 4. Update CHANGELOG.md with detailed notes
vim CHANGELOG.md
# Add release notes under ## [v1.2.0] - 2025-01-14

# 5. Commit version bump
git add -A
git commit -m "chore: bump version to 1.2.0"

# 6. Create annotated tag
git tag -a v1.2.0 -m "Release v1.2.0"

# 7. Push to trigger release workflow
git push origin main
git push origin v1.2.0

# GitHub Actions will:
# - Build multi-arch Docker images
# - Generate SBOM files
# - Create GitHub release with notes
# - Attach SBOM to release
# - Push images to GHCR and Docker Hub
```

### Automated Release (CI/CD)

The workflow triggers on:

1. **Git tag push** (`v*.*.*`)
   - Full release with SBOM generation
   - Release notes from CHANGELOG.md or auto-generated
   - Updates `:latest` tag

2. **Weekly schedule** (Sundays 18:30 UTC)
   - Rebuilds last release with updated packages
   - No release notes or SBOM (not a new release)
   - Overwrites version tag with fresh build

3. **Manual dispatch** (workflow_dispatch)
   - Test builds with version suffix
   - Useful for testing release process

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
# Download SBOM from GitHub release
wget https://github.com/r3bo0tbx1/test-0f376e81/releases/download/v1.1.2/sbom-cyclonedx-v1.1.2.json

# Scan with Grype
grype sbom:sbom-cyclonedx-v1.1.2.json

# Scan with Trivy
trivy sbom sbom-cyclonedx-v1.1.2.json
```

**Integrate with security tools:**

```bash
# Import into Dependency-Track
curl -X POST "https://dtrack.example.com/api/v1/bom" \
  -H "X-Api-Key: $API_KEY" \
  -F "bom=@sbom-cyclonedx-v1.1.2.json"

# Analyze with Syft
syft sbom-cyclonedx-v1.1.2.json

# View package list
jq '.components[] | {name, version, type}' sbom-cyclonedx-v1.1.2.json
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
./scripts/release/generate-release-notes.sh 1.1.2 1.1.1
```

### Version Update Missing Files

**Problem**: Not all files were updated

**Solution:**
```bash
# Check what current version was detected
./scripts/release/update-version.sh --dry-run 1.1.2

# Search for old version manually
grep -r "1.1.1" . --exclude-dir=.git

# Update manually missed files
sed -i 's/1.1.1/1.1.2/g' path/to/file
```

### SBOM Generation Fails

**Problem**: Syft can't access image

**Solution:**
```bash
# Ensure image exists locally or in registry
docker pull ghcr.io/r3bo0tbx1/onion-relay:1.1.2

# Generate SBOM locally for testing
docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  anchore/syft:latest \
  ghcr.io/r3bo0tbx1/onion-relay:1.1.2 \
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
