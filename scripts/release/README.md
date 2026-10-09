# Release preparation

[Project](../../README.md) · [Documentation](../../docs/README.md) · [v2.2.0 notes](../../docs/releases/v2.2.0.md)

Keep preparation local until the maintainer publishes the reviewed commit and tag. The source branch, curated release notes, generated artifacts and article should agree on the implemented behavior.

## Local commands

```sh
sh scripts/release/update-version.sh 2.2.0 --dry-run
python3 scripts/release/check-versions.py
python3 scripts/testing/check-docs.py
sh scripts/release/generate-release-notes.sh 2.2.0 v2.1.0 --output /tmp/release-draft.md
```

The version checker discovers tracked and nonignored documentation, scripts and workflows, synchronizing current Alpine references from the stable Dockerfile. `--write` applies changes; `--version X.Y.Z` also updates managed current project references. Historical changelog entries and historical migration release semantics are retained.

The notes generator handles leading gitmoji, conventional scopes and multiline breaking-change bodies. Its output is a review draft. The release workflow publishes the curated file at `docs/releases/vVERSION.md`.

## Candidate pipeline

1. Resolve the triggering release tag, or the latest stable tag for a scheduled rebuild. Require its commit to be an ancestor of main.
2. Build stable and edge candidates for AMD64 and ARM64, without publishing.
3. Run offline behavior tests and component security floors against each loaded image.
4. Generate SBOMs and run blocking vulnerability/secret scans.
5. Save each validated image, checksum, inspect metadata and scan evidence.
6. Load those same image archives in promotion, verify image identity, publish immutable staging references, and assemble version/alias manifests from their digests.
7. Publish curated release notes and attach security evidence only after promotion succeeds.

Schedules rebuild the latest released tag, not unreleased main. A dependency update on main reaches scheduled rebuilds only after a new reviewed release tag contains it. Manual dispatch defaults to validation without publication. The retention workflow produces a read-only registry inventory; it cannot delete rollback images. Review manifests, architecture digests and rollback references before any manual deletion.

The promotion job needs Docker Hub credentials and GitHub package permissions. Cross-registry promotion must be observed in the first maintainer-triggered run; local testing does not establish remote registry behavior.

## Evidence and rollback

Retain source SHA, architecture, image ID/digest, Tor version, Alpine/OpenSSL packages, Lyrebird revision/Go dependency graph, SBOM and the full vulnerability/secret report. Promotion blocks any secret finding or HIGH/CRITICAL vulnerability with an available fix. Unfixed and lower-severity findings remain in the report for assessment. Never call a candidate published based only on a local build.

Preserve the previous validated image digest, deployment and encrypted backup before upgrading. Do not rewrite historical release descriptions when updating current examples.
