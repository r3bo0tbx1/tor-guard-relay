# 📦 Lyrebird Dependency Lock

The Dockerfiles fetch the reviewed Lyrebird revision, then use this go.mod/go.sum graph with readonly module resolution. Source updates and dependency updates are separate review steps: compare upstream changes, build both architectures, inspect the linked transport metadata, and run candidate security checks before publication.

Do not replace the graph with upstream defaults without checking the Pion STUN security floor. Renovate can propose Go module updates; component checks and offline image acceptance remain required.

## 🔄 Independent update paths

Renovate tracks upstream `main` through a `git-refs` custom manager and proposes one reviewed source-pin update across all four ARG occurrences in both Dockerfiles. The pin consistency check rejects stage or variant drift. Source proposals are not auto-merged.

Go dependency fixes can update this lock before Lyrebird upstream changes its own graph. Docker base/toolchain, Go graph, source-pin and scanner-tool proposals have no weekly scheduling restriction. Vulnerability alerts receive expedited handling. The bot must be enabled for the repository; these rules do not guarantee when a hosted run will occur.

Indirect Go dependency updates are explicitly enabled; Renovate otherwise disables them by default. OSV-based automatic security alerts cover direct dependencies only, so retain source/image scans and review indirect findings promptly.

### 📦 One Go update batch

Routine minor, patch, digest and pin updates share the `🧅 Lyrebird Go dependencies` group, including indirect modules. One PR validates the combined graph through the complete stable/edge AMD64/ARM64 matrix. Direct major updates and source-pin proposals keep their own review boundaries; routine indirect major updates are deferred because their import paths belong to upstream consumers. Vulnerability alerts remain immediate and can cross routine restrictions for explicit review. The five-PR limit caps simultaneous proposals rather than the total backlog, so lowering it alone cannot replace grouping.

Regenerate a combined lock against the actual pinned Lyrebird source with the pinned builder and `GOTOOLCHAIN=local`. Review all graph changes, authenticate the downloads, then retain `-mod=readonly` for candidate builds. Running `go mod tidy` in this lock-only directory would remove needed dependencies.

### 🧩 Pion compatibility boundary

The v2.2.0 batch updates Snowflake to 2.15.1 and selects these compatible components:

| Module | Selected version |
| --- | --- |
| WebRTC v4 | 4.2.20 |
| ICE v4 | 4.4.2 |
| TURN v5 | 5.1.0 |
| mDNS v2 | 2.2.0 |
| SRTP v3 | 3.0.13 |

[WebRTC 4.2.21](https://github.com/pion/webrtc/blob/v4.2.21/go.mod) switches to Pion transport v5, while Snowflake's network interface uses transport v4. The latest SRTP buffer interface also belongs to transport v5. Blindly selecting the latest versions produces incompatible Go interfaces; missing checksums are a separate issue. Renovate now limits routine proposals for these five components to the reviewed versions above. These are temporary compatibility limits, not a claim that every later release is unsafe. Reassess them whenever Snowflake or Lyrebird source changes, review an upstream adaptation or compatible backport, and rerun the full candidate gates before lifting a limit.

RTP v2 changes its module import path. Replacing the indirect RTP v1 requirement cannot migrate WebRTC and other upstream consumers. Keep routine indirect major proposals deferred until those consumers migrate; retain eligible patch/minor updates. Do not enable `gomodTidy` or automatic import-path rewriting in this source-less lock directory.

### 🛡️ Security fixes and policy evidence

Compatibility limits apply to routine updates. Detected GitHub/OSV security-fix proposals are ungrouped, immediate and never auto-merged; the security override allows review beyond routine ceilings and indirect-major restrictions. OSV's generated fix range and GitHub's fixed-version filter remain effective. An incompatible security candidate still fails build/security gates: review a source migration, a maintained backport or exposure mitigation rather than bypassing CI. OSV's direct-dependency coverage limitation still applies, so source/image scans remain essential.

The pinned Renovate validator in [security-tools.json](../security-tools.json) also runs the [behavior checker](../../scripts/testing/check-renovate.mjs) in PR/main source validation before image builds. It resolves the real presets and exercises Renovate's rule engine, version filtering and advisory adapters against compatible updates, the known Pion proposals, RTP's major migration and synthetic security-fix fixtures. Tool updates must preserve those behaviors. The independent lock also includes the compatible `golang.org/x/net` 0.61.0 update.

The first source scan retained module-level [GO-2026-5841](https://pkg.go.dev/vuln/GO-2026-5841) for `klauspost/compress` 1.18.0 without a reachable call. The current batch moves the lock to 1.20.1 after the earlier fix in 1.18.7, independently of the Lyrebird source revision. Keep the full analysis rather than inferring exposure from a module name alone.

The host/CI Go checker rebuilds only the native builder stage, verifies that its transport bytes match each candidate, and analyzes the same source/lock/toolchain for Linux AMD64 or ARM64. It uses the scanner version in [security-tools.json](../security-tools.json). Reachable Go findings block publication regardless of severity or fix availability; full module/package findings remain visible. No scanner is added to the runtime image.

After a reviewed update passes candidate gates, publish a new patch release promptly. Existing release tags retain their source identity, and scheduled rebuilds use the latest released tag. Recreate running containers from the validated new image.
