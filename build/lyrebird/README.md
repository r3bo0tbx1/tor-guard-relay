# 📦 Lyrebird Dependency Lock

The Dockerfiles fetch the reviewed Lyrebird revision, then use this go.mod/go.sum graph with readonly module resolution. Source updates and dependency updates are separate review steps: compare upstream changes, build both architectures, inspect the linked transport metadata, and run candidate security checks before publication.

Do not replace the graph with upstream defaults without checking the Pion STUN security floor. Renovate can propose Go module updates; component checks and offline image acceptance remain required.

## 🔄 Independent update paths

Renovate tracks upstream `main` through a `git-refs` custom manager and proposes one reviewed source-pin update across all four ARG occurrences in both Dockerfiles. The pin consistency check rejects stage or variant drift. Source proposals are not auto-merged.

Go dependency fixes can update this lock before Lyrebird upstream changes its own graph. Docker base/toolchain, Go graph, source-pin and scanner-tool proposals have no weekly scheduling restriction. Vulnerability alerts receive expedited handling. The bot must be enabled for the repository; these rules do not guarantee when a hosted run will occur.

Indirect Go dependency updates are explicitly enabled; Renovate otherwise disables them by default. OSV-based automatic security alerts cover direct dependencies only, so retain source/image scans and review indirect findings promptly.

The first source scan retained module-level [GO-2026-5841](https://pkg.go.dev/vuln/GO-2026-5841) for `klauspost/compress` 1.18.0 without a reachable call. The lock nevertheless moves to the available fixed 1.18.7, independently of the Lyrebird source revision. Keep the full analysis rather than inferring exposure from a module name alone.

The host/CI Go checker rebuilds only the native builder stage, verifies that its transport bytes match each candidate, and analyzes the same source/lock/toolchain for Linux AMD64 or ARM64. It uses the scanner version in [security-tools.json](../security-tools.json). Reachable Go findings block publication regardless of severity or fix availability; full module/package findings remain visible. No scanner is added to the runtime image.

After a reviewed update passes candidate gates, publish a new patch release promptly. Existing release tags retain their source identity, and scheduled rebuilds use the latest released tag. Recreate running containers from the validated new image.
