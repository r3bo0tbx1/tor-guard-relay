# 🚀 Release Preparation

[Project](../../README.md) · [Documentation](../../docs/README.md) · [v2.2.0 notes](../../docs/releases/v2.2.0.md)

Keep preparation local until the maintainer publishes the reviewed commit and tag. The source branch, curated release notes, generated artifacts and article should agree on the implemented behavior.

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

After a Docker base version proposal, run `python3 scripts/release/check-versions.py --write` and review the synchronized examples and OCI base label. The consistency gate deliberately rejects unsynchronized documentation.

<a id="expedited-security-response"></a>

### 🚨 Expedited security response

Do not wait for a scheduled rebuild or feature release when an applicable security fix is available. Update the affected source pin, Go lock, builder/base or component floor, run the full candidate gates, merge the reviewed change and publish a new patch tag. A merged lock/source update alone cannot change images rebuilt from an older release tag.

If no fix exists, assess exposure and mitigate it, for example by disabling an affected transport or reviewing a backport. HIGH/CRITICAL image findings and reachable Go findings block publication even without a fix. There is no automatic ignore list or severity downgrade. Any policy change for demonstrated non-applicability needs an explicit reviewed change with supporting evidence.

### 🔎 Continuous security watch

The read-only `🔒🧅 Security watch` workflow runs on relevant main changes, manual dispatch and every six hours. It analyzes current pinned source/Go locks for both architectures and independently scans the exact published stable/edge architecture digests from Docker Hub and GHCR using current advisory data. It records manifests, image IDs and complete reports, including failure diagnostics, for 30 days. Failures appear in Actions; configure your GitHub Actions notifications to receive them.

The published-image lane performs package/secret assessment; source reachability is reported for the current checkout, which may differ from a published release. GitHub schedules and advisory ingestion can be delayed. Monitoring never publishes images, changes a live relay, opens issues or sends third-party messages.

## 🛡️ Evidence and rollback

Retain source and security-policy SHAs, architecture, image ID/digest, Tor version, Alpine/OpenSSL packages, Lyrebird revision/Go dependency graph, Go reachability report, SBOM and the full vulnerability/secret report. Promotion blocks secrets, all HIGH/CRITICAL image findings, and reachable Go vulnerabilities regardless of a fixed version or severity label. Unfixed and lower-severity findings remain in the report for assessment. Scanner failures and malformed/incomplete reports fail closed. Never call a candidate published based only on a local build.

Preserve the previous validated image digest, deployment and encrypted backup before upgrading. Do not rewrite historical release descriptions when updating current examples.
