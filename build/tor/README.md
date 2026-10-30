# 🧅 Authenticated Tor source builds

Tor is built from a reviewed stable upstream source release for each stable/edge AMD64/ARM64 image. Alpine still supplies the base, build tools and runtime libraries, but its Tor package availability no longer controls our release date. [source.json](source.json) is the single source version, SHA256 and reviewed signing fingerprint; builders and component policy read the same pin.

## 🔐 Source and package verification

The verifier follows [Tor's published verification procedure](https://support.torproject.org/little-t-tor/getting-started/verifying/): authenticate the checksum file's OpenPGP signatures, check the selected archive filename and locked checksum, then hash the archive before extracting or compiling it. Public release keys are vendored and their full signing fingerprints are checked against the documented Tor signers. The verifier uses an isolated temporary keyring with automatic key retrieval disabled. New signers, revoked/expired keys, signature failures, changed checksums and download failures block the build; review key rotations against upstream documentation.

The Tor build stage uses the same Alpine base as its runtime and runs as an unprivileged build user. Its APK recipe follows Alpine's configure flags and runs upstream `make test`. It includes GeoIP data, runtime dependency metadata, Tor's license and `/usr/share/tor/source.json`. The upstream sample torrc patch is unnecessary because this project removes the packaged sample and supplies its own ENV/mounted config contract.

Hosted ARM64 candidate and source-analysis jobs use GitHub's [native `ubuntu-24.04-arm` runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners); AMD64 keeps `ubuntu-latest`. Each job confirms its Docker host architecture. Full Tor builds and upstream sandbox tests require a Linux kernel for the target architecture. Native ARM64 hardware or a [full-system ARM64 VM](../../docs/LOCAL-TESTING.md#environment) can supply that kernel. QEMU user-mode emulation [rejects the seccomp prctl operations](https://github.com/qemu/qemu/blob/master/linux-user/syscall.c), so a user-emulated ARM64 build on an AMD64 kernel can compile successfully and still stop at sandbox tests. Keep that failure blocking; do not skip tests or disable Tor's sandbox support. Published-image monitoring retains QEMU for its short cross-platform binary-version checks.

The build first reads the kernel's seccomp mode without changing its filters. An unsupported kernel or user-mode emulator stops before source downloads and compilation, with an explanation of the target-kernel requirement. This preflight does not replace the full upstream tests.

An ephemeral APK key signs the local package. The runtime trusts its public half only while installing that exact package, then removes it. The private key, compiler and source tree stay in the build stage. Runtime dependencies still come from signed official Alpine repositories; no edge/stable mixing or `--allow-untrusted` installation is used. SBOM/vulnerability scans must identify the source-built `tor` APK and its actual version; binary and provenance checks remain separate blocking gates.

## 🔄 Future releases while the project stays on 2.2.1

The project version and Tor version are different. A compatible Tor security update can refresh `2.2.1`, `latest` and `edge` images without moving the Git `v2.2.1` tag or changing the project's version marker. GHCR also keeps `2.2.1-edge`. Image labels and retained publication evidence identify the actual main commit; deploy by digest for an immutable build.

GitHub release notes/assets retain the original release's evidence. A later main rebuild retains its own source record, SBOMs and scan/publication artifacts; inspect those and the actual image when checking a refreshed tag. Candidate artifacts include `tor-source.json` with the authenticated version/checksum/signer record.

Once this workflow change is merged, **🔒🧅** checks upstream stable releases every six hours and on manual dispatch. It ignores alpha/RC/dev archives and compares all four version components. An equal version is a no-op after discovery; a lower version is rejected. A newer release is downloaded and authenticated, its proposed lock is retained in `tor-upstream.json`, and the watch check fails to request maintainer review. Network/authentication failures also fail; they never advance the source pin. Monitoring does not commit, open a PR, merge or publish automatically.

From the repository root, with Python 3.11+ and GnuPG available:

```sh
# Read-only discovery. A verified newer release exits 1 and retains its proposal.
python3 scripts/release/update-tor-source.py --output /tmp/tor-upstream.json
# Prepare a local reviewed update. This changes only build/tor/source.json.
python3 scripts/release/update-tor-source.py --version 0.4.9.16 --write
```

The example future version must actually exist. The update command verifies its signatures and archive before writing; it never downgrades or blindly accepts a checksum change for an existing pinned version. Review upstream compatibility, torrc guidance, source keys, release notes and current security documentation alongside the pin. No partial version-only Renovate update is enabled: the authenticated checksum and version move together through this command.

After review, validate all four candidates, recovery and source/image security gates. Merge the update and run the existing main rebuild with publication enabled only when authorized. Scheduled rebuilds also pick up merged pins. They keep the reviewed Tor version until an update is merged; they do not fetch a floating latest Tor binary. An explicit older Git tag still selects that tag's original source and may fail newer security floors or the source-build contract.

Tor API/config or packaging changes that affect operators warrant a new project release rather than silently changing compatibility under `2.2.1`.
