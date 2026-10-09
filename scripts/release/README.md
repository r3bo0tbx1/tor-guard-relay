# 🚀 Release Preparation

[Project](../../README.md) · [Documentation](../../docs/README.md) · [v2.2.0 notes](../../docs/releases/v2.2.0.md)

Keep preparation local until the maintainer publishes the reviewed commit and tag. The source branch, curated release notes, generated artifacts and article should agree on the implemented behavior.

## 🛠️ Local commands

```sh
sh scripts/release/update-version.sh 2.2.0 --dry-run
python3 scripts/release/check-versions.py
python3 scripts/testing/check-docs.py
sh scripts/release/generate-release-notes.sh 2.2.0 v2.1.0 --output /tmp/release-draft.md
```

The version checker discovers tracked and nonignored documentation, scripts and workflows, synchronizing current Alpine references from the stable Dockerfile. `--write` applies changes; `--version X.Y.Z` also updates managed current project references. Historical changelog entries and historical migration release semantics are retained.

The notes generator handles leading gitmoji, conventional scopes and multiline breaking-change bodies, and keeps emoji headings by default. Use `--no-emoji` or `--format plain` only when you want plain output. Its output is a review draft. The release workflow publishes the curated file at `docs/releases/vVERSION.md`.

## 🏗️ Candidate pipeline

1. Resolve the triggering release tag, or the latest stable tag for a scheduled rebuild. Require its commit to be an ancestor of main.
2. Build stable and edge candidates for AMD64 and ARM64, without publishing.
3. Run offline behavior tests and component security floors against each loaded image.
4. Generate SBOMs and run blocking vulnerability/secret scans.
5. Save each validated image, checksum, inspect metadata and scan evidence.
6. Load those same image archives in promotion, verify image identity, publish immutable staging references, and assemble version/alias manifests from their digests.
7. Publish curated release notes and attach security evidence only after promotion succeeds.

Schedules rebuild the latest released tag, not unreleased main. A dependency update on main reaches scheduled rebuilds only after a new reviewed release tag contains it. Manual dispatch defaults to validation without publication. The retention workflow produces a read-only registry inventory; it cannot delete rollback images. Review manifests, architecture digests and rollback references before any manual deletion.

The promotion job needs Docker Hub credentials and GitHub package permissions. Cross-registry promotion must be observed in the first maintainer-triggered run; local testing does not establish remote registry behavior.

### ✅ Required validation checks

The validation workflow preserves the four names required by the main branch ruleset: `🔍 Lint and Validate`, `🏗️ Build Docker Image`, `🧪 Integration Tests` and `🛡️ Security Scan`. The last three aggregate the complete stable/edge and AMD64/ARM64 candidate matrix, including behavioral acceptance and security policy. They run even after a dependency fails and succeed only when source validation and every image job succeed.

Candidate artifacts are replaced on workflow reruns; registry staging tags include both the run ID and attempt so a retry does not reuse an earlier staging tag. Version and alias tags remain mutable for validated scheduled rebuilds.

### 📦 Dependency update boundaries

Renovate currently proposes Docker base, GitHub Actions and locked Go module updates. It does not track `LYREBIRD_REVISION`. An upstream Lyrebird commit does not change the source pin during scheduled rebuilds. Review and update every source-pin occurrence in both Dockerfiles together, check upstream changes against the locked Go graph, and pass the full candidate matrix before tagging a release.

Automatic source-pin proposals would need a Renovate `custom.regex` manager using the `git-refs` datasource for an explicitly selected upstream branch or tag. Keep those proposals subject to review and the same release gates. The repository's Renovate integration must also be enabled; configuration alone does not run the bot.

After a Docker base version proposal, run `python3 scripts/release/check-versions.py --write` and review the synchronized examples and OCI base label. The consistency gate deliberately rejects unsynchronized documentation.

## 🛡️ Evidence and rollback

Retain source SHA, architecture, image ID/digest, Tor version, Alpine/OpenSSL packages, Lyrebird revision/Go dependency graph, SBOM and the full vulnerability/secret report. Promotion blocks any secret finding or HIGH/CRITICAL vulnerability with an available fix. Unfixed and lower-severity findings remain in the report for assessment. Never call a candidate published based only on a local build.

Preserve the previous validated image digest, deployment and encrypted backup before upgrading. Do not rewrite historical release descriptions when updating current examples.
