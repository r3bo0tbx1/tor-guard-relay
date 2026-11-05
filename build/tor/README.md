# 🧅 Authenticated Tor source builds

Tor is built from a reviewed stable upstream source release for each stable/edge AMD64/ARM64 image. Alpine still supplies the base, build tools and runtime libraries, but its Tor package availability no longer controls our release date. [source.json](source.json) is the single source version, SHA256 and reviewed signing fingerprint; builders and component policy read the same pin.

## 🔐 Source and package verification

The verifier follows [Tor's published verification procedure](https://support.torproject.org/little-t-tor/getting-started/verifying/): authenticate the checksum file's OpenPGP signatures, check the selected archive filename and locked checksum, then hash the archive before extracting or compiling it. Public release keys are vendored and their full signing fingerprints are checked against the documented Tor signers. The verifier uses an isolated temporary keyring with automatic key retrieval disabled. New signers, revoked/expired keys, signature failures, changed checksums and download failures block the build; review key rotations against upstream documentation.

The Tor build stage uses the same Alpine base as its runtime and runs as an unprivileged build user. Its APK recipe follows Alpine's configure flags and runs upstream `make test`. It includes GeoIP data, runtime dependency metadata, Tor's license and `/usr/share/tor/source.json`. The upstream sample torrc patch is unnecessary because this project removes the packaged sample and supplies its own ENV/mounted config contract.

Hosted ARM64 candidate and source-analysis jobs use GitHub's [native `ubuntu-24.04-arm` runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners); AMD64 keeps `ubuntu-latest`. Each job confirms its Docker host architecture. Full Tor builds and upstream sandbox tests require a Linux kernel for the target architecture. Native ARM64 hardware or a [full-system ARM64 VM](../../docs/LOCAL-TESTING.md#environment) can supply that kernel. QEMU user-mode emulation [rejects the seccomp prctl operations](https://github.com/qemu/qemu/blob/master/linux-user/syscall.c), so a user-emulated ARM64 build on an AMD64 kernel can compile successfully and still stop at sandbox tests. Keep that failure blocking; do not skip tests or disable Tor's sandbox support. Published-image monitoring retains QEMU for its short cross-platform binary-version checks.

The build first reads the kernel's seccomp mode without changing its filters. An unsupported kernel or user-mode emulator stops before source downloads and compilation, with an explanation of the target-kernel requirement. This preflight does not replace the full upstream tests.

An ephemeral APK key signs the local package. The runtime trusts its public half only while installing that exact package, then removes it. The private key, compiler and source tree stay in the build stage. Runtime dependencies still come from signed official Alpine repositories; no edge/stable mixing or `--allow-untrusted` installation is used. SBOM/vulnerability scans must identify the source-built `tor` APK and its actual version; binary and provenance checks remain separate blocking gates.

## 🔄 Future releases while the project stays on 2.2.1

The reviewed version is recorded in [source.json](source.json). Tor 0.4.9.16 was an authority-focused emergency release with no new mandatory torrc settings or urgency for ordinary relay and bridge operators. The original v2.2.1 release shipped Tor 0.4.9.15. [Migration guidance](../../docs/MIGRATION.md#-reviewed-tor-source-updates) · [Tor 0.4.9.16 announcement](https://forum.torproject.org/t/security-release-0-4-9-16/22372)

The project version and Tor version are different. A compatible Tor security update can refresh `2.2.1`, `latest` and `edge` images without moving the Git `v2.2.1` tag or changing the project's version marker. GHCR also keeps `2.2.1-edge`. Image labels and retained publication evidence identify the actual main commit; deploy by digest for an immutable build.

GitHub release notes/assets retain the original release's evidence. A later main rebuild retains its own source record, SBOMs and scan/publication artifacts; inspect those and the actual image when checking a refreshed tag. Candidate artifacts include `tor-source.json` with the authenticated version/checksum/signer record.

**🔒🧅** checks upstream stable releases every six hours and on manual dispatch. It ignores alpha/RC/dev archives and compares all four version components. An equal version is a no-op after discovery. For a newer release, the watcher authenticates the archive and saves a proposal in `tor-upstream.json`. On `main`, a separate job checks the proposal against this run's published images and maintains the update PR. Authentication, download and downgrade failures stop the proposal.

### 📝 Automatic update PR

The workflow opens a draft from the reserved `build/tor-source-update` branch and refreshes that same open PR when a newer release arrives. The commit changes only `build/tor/source.json`. Its PR body records the checksum, signer, highest observed installed version and upstream changelog. Review that changelog and add any required operator guidance before merging. The existing PR checks run on each changed revision.

After reviewing the changelog and operator guidance, react **👍 on the bot's review comment** for the current commit. The next scheduled 🔒🧅 run, or a manual run on `main` with `tor_version` blank, checks the repository owner's reaction and waits for every required check on that revision to pass. It then ticks both boxes and marks the PR ready. A refreshed commit gets a new review comment and requires a fresh reaction. Squash merge the PR yourself after reviewing it.

A repeat of the same proposal on the same main revision leaves the PR head alone. When main advances, the bot refreshes its own commit on the new base. The branch update checks the exact remote head so a concurrent edit is preserved. Maintainer commits on the bot branch stop automation until the branch is reviewed. Closing a proposal without merging suppresses that release and older requests. Reopen it manually to resume review. Later releases can open another draft. GitHub's normal merged-branch cleanup applies.

Register a repository-scoped GitHub App with **Contents: read and write** and **Pull requests: read and write**, and install it only on `tor-guard-relay`. Set `TOR_UPDATE_APP_CLIENT_ID` in Actions variables and `TOR_UPDATE_APP_PRIVATE_KEY` in Actions secrets. The workflow requests a short-lived installation token only for the PR step. A missing App configuration leaves the authenticated proposal in the artifact and reports the setup error. App-authored PR events can start the existing PR checks. [GitHub App token setup](https://github.com/actions/create-github-app-token/tree/v3.3.0) · [Workflow trigger details](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow#triggering-a-workflow-from-a-workflow)

### 🖱️ Check an exact release manually

In **Actions → 🔒🧅 → Run workflow**, select the reviewed branch (normally `main`) and enter a stable four-component release such as `0.4.9.16` in **tor_version**. Leave it blank for normal latest-release discovery.

An exact request waits for this run's published-image assessments from Docker Hub and GHCR, stable and edge, AMD64 and ARM64. Each assessment runs the image's actual `tor --version` and records the resolved image digest and architecture. The request is rejected if it is below the reviewed source pin **or any of those eight installed versions**. Missing reports, mismatched identities, invalid/prerelease versions and authentication/download failures block the request. An image failing the new source floor still supplies its observed version; its separate audit remains failed.

Even an explicitly selected equal version authenticates its signed checksum and archive against the existing lock. Equal verified versions pass without a proposal. A newer verified version on `main` follows the draft PR path above. The assessments cover the published images resolved during that run. Private VPS containers and custom images require separate inventories before deployment.

From the repository root, with Python 3.11+ and GnuPG available:

```sh
# Read-only discovery. A verified newer release exits 1 and retains its proposal.
python3 scripts/release/update-tor-source.py --output /tmp/tor-upstream.json
# Authenticate the latest stable release and prepare its local source lock.
python3 scripts/release/update-tor-source.py --write
```

Select a stable version that actually exists. Explicitly selecting the already reviewed version reauthenticates it without changing the pin. Automatic discovery of an equal version skips archive downloads. A newer version is authenticated before writing; the helper never downgrades or blindly accepts a checksum change for an existing pinned version. Direct local CLI use compares against the reviewed pin; `--published-reports DIRECTORY --owner OWNER` also enforces the complete same-run image baseline, as the manual workflow does. Review upstream compatibility, torrc guidance, source keys, release notes and current security documentation alongside the pin. No partial version-only Renovate update is enabled: the authenticated checksum and version move together through this command.

After review, validate all four candidates, recovery and source/image security gates. Merge the update and run the existing main rebuild with publication enabled only when authorized. Scheduled rebuilds also pick up merged pins. They keep the reviewed Tor version until an update is merged; they do not fetch a floating latest Tor binary. An explicit older Git tag still selects that tag's original source and may fail newer security floors or the source-build contract.

After a merge raises the Tor floor, published-image audits flag older digests until a validated rebuild replaces them. Publish the reviewed rebuild before running a manual post-update audit. A successful publishing run also triggers the audit automatically.

Tor API/config or packaging changes that affect operators warrant a new project release rather than silently changing compatibility under `2.2.1`.
