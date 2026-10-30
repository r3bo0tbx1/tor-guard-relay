# Local Testing Guide

**For Contributors and Developers Only**

> ⚠️ **Most Users Should Use Published Images**
>
> If you're deploying a Tor relay, use the published images from Docker Hub or GHCR:
> - **Docker Hub**: `r3bo0tbx1/onion-relay:latest`
> - **GHCR**: `ghcr.io/r3bo0tbx1/onion-relay:latest`
>
> This guide is for **contributors** who are modifying code, scripts, or workflows.

---

> [!IMPORTANT]
> 🧅 **v2.2.1 preparation:** Tor must be **0.4.9.15 or newer**. Review the [release and torrc migration notes](releases/v2.2.1.md); Tor is built from authenticated upstream source on each matching Alpine base; publication requires all candidate gates. Recreate from the validated image to update Tor; changing torrc alone does not upgrade the binary.

## Environment

Docker Desktop on Windows with WSL works. Run source checks in Linux/WSL with Python 3.11+, age, ShellCheck and dos2unix. A Linux Docker daemon is also supported. Full source builds and upstream sandbox tests require a Linux kernel for the target architecture. For ARM64 candidates, use native ARM64 hardware or a full-system ARM64 Linux VM with Docker running inside the guest.

QEMU/binfmt supports short cross-platform version checks, but its user-mode emulation cannot load Tor's seccomp sandbox filters. An emulated source build can compile and then fail the upstream sandbox tests; do not bypass that gate. See the [source-build guide](../build/tor/README.md). Hosted candidate jobs use native ARM64 runners.

For short emulated checks on Docker Desktop, finish WSL commands before registering binfmt. WSL session changes can reset its registration and cause `exec format error`. Re-register with `docker run --privileged --rm tonistiigi/binfmt --install arm64` after WSL commands finish, then run those checks sequentially with respect to WSL activity.

### 🍓 ARM64 without a Raspberry Pi

A full-system [QEMU ARM `virt` machine](https://www.qemu.org/docs/master/system/arm/virt.html) runs its own ARM64 Linux kernel, unlike Docker's binfmt user-mode emulation. Install Docker **inside that guest** and run the build/test commands there. CPU emulation is slower than native hardware and does not establish Raspberry Pi performance or hardware compatibility. Hosted native ARM64 candidate jobs remain required before publication.

1. On an Ubuntu/WSL host, install `qemu-system-arm`, `qemu-utils`, `qemu-efi-aarch64` and `cloud-image-utils`. Use an official [Alpine ARM64 cloud image](https://alpinelinux.org/cloud/), verify its checksum and detached OpenPGP signature against Alpine's published full fingerprint, and keep the verified image read-only.
2. Create a task-owned QCOW2 overlay and NoCloud seed with a temporary SSH public key. Run `qemu-system-aarch64` with `-machine virt -cpu max -accel tcg -m 3072 -smp 2`, AAVMF firmware, the overlay, seed and virtio devices. Bind any SSH forwarding explicitly to loopback, for example `hostfwd=tcp:127.0.0.1:2264-:22`. Keep Docker's API on the guest's Unix socket.
3. Inside the guest, install Docker, its buildx CLI plugin and the testing prerequisites. Use an account authorized for the guest's Docker Unix socket. On Alpine, start the `cgroups` OpenRC service before Docker; wait for `docker version` to report its server architecture. Confirm the architecture and kernel preflight before a long build:

```sh
uname -m                                      # aarch64
docker version --format '{{.Server.Arch}}'     # arm64
python3 build/tor/preflight.py
```

4. Copy the reviewed working source into the guest, including uncommitted release changes. Cloning the current remote branch alone will omit local preparation. Keep real relay data, ENV, credentials and keys out of the test guest. Run both candidates sequentially:

```sh
set -eu
version=$(python3 scripts/release/check-versions.py --print-version)
for variant in stable edge; do
  recipe=Dockerfile
  test "$variant" != edge || recipe=Dockerfile.edge
  image="relay-arm64-local:$variant"
  docker buildx build --platform linux/arm64 --load --progress plain \
    -f "$recipe" --build-arg BUILD_VERSION="$version-local" \
    -t "$image" .
  python3 scripts/testing/image-acceptance.py "$image" --platform linux/arm64
  python3 scripts/testing/check-image.py "$image"
done
```

Retain the full upstream test output. A successful kernel preflight alone is insufficient: the build must pass upstream sandbox tests, then image behavior, component/security scans, SBOMs, source/image identity and encrypted recovery checks. Use the same gates documented below and in the candidate workflow. Do not disable sandbox support, skip failing tests or publish from this rehearsal. Shut down the disposable guest after testing and keep its disk only if needed for continued local validation.

## 🔎 Source checks

```sh
python3 scripts/release/check-versions.py
python3 scripts/testing/check-templates.py
python3 scripts/testing/check-docs.py
shellcheck -S warning -x docker-entrypoint.sh healthcheck.sh lib/*.sh tools/* build/tor/build.sh scripts/utilities/relay-backup.sh scripts/utilities/relay-inventory.sh
python3 -m unittest discover -s tests -v
git diff --check
```

Archive tests require age on PATH. A skipped archive test is not a recovery pass. Check LF line endings with dos2unix before building on Windows.

### 🧩 Renovate behavior checks

PR/main validation also installs the reviewed Renovate version from `build/security-tools.json` with the latest Node 24 patch. Only RE2's native installation script is rebuilt. To run the same checks with a supported Node 24 runtime:

```sh
version=$(python3 -c 'import json; print(json.load(open("build/security-tools.json"))["renovate"])')
tool_root=$(mktemp -d)
npm install --prefix "$tool_root" --ignore-scripts --package-lock=false --no-audit --no-fund "renovate@$version"
npm rebuild --prefix "$tool_root" re2
node "$tool_root/node_modules/renovate/dist/config-validator.js" --no-global --strict .github/renovate.json
node scripts/testing/check-renovate.mjs "$tool_root/node_modules/renovate"
```

Remove the task-owned temporary tool directory when finished. The checker uses Renovate's real presets, rule engine and version/advisory filters; it makes no repository mutations or live advisory queries. Security fixtures ensure routine compatibility limits and indirect-major deferrals do not suppress fix proposals. Reassess the documented limits when changing the source or Snowflake graph. Do not tidy the lock directory without the actual Lyrebird source.

## 🏗️ Build and inspect candidates

The source builds Tor from the authenticated pin in `build/tor/source.json`, independently of Alpine’s Tor package. Alpine still supplies the base and runtime libraries. Follow the [source verification and validation order](#-release-preparation-order) before treating a local build as a candidate.

### ✅ Release preparation order

1. Keep source, samples, current documentation and managed version markers synchronized; preserve historical release records, artwork, emojis and Mermaid diagrams.
2. Run local regression, shell, workflow, dependency, documentation and recursive template checks.
3. Authenticate the pinned Tor source archive and its reviewed release signer. Verify matching Alpine builder/runtime bases, source-package metadata and runtime libraries for both architectures.
4. Build stable/edge AMD64/ARM64 candidates with the normal Dockerfiles. Verify binary versions, each sample configuration, ENV generation, reload/startup, shutdown and identity-preserving encrypted recovery.
5. Run component/security gates and retain exact candidate digests, SBOMs and scan evidence. Prepare the signed release commit/tag and publish only after all four candidates pass and the maintainer authorizes publication.
6. Follow the migration checklist and retain evidence from real deployments. Keep registry-retention protection and the existing published notice unchanged by preparation. The [fleet-review helper](REGISTRY-RETENTION.md#-prepare-a-fleet-review-proposal) can prepare additive protection from fresh reports; it cannot renew stale evidence or authorize deletion without complete coverage.

Coordinate the managed version bump with the new release tag after the approved change reaches main. Until `v2.2.1` exists on main, scheduled/manual main rebuilds reject the mismatch with the last published `v2.2.0` namespace. Do not merge the version bump early expecting routine rebuilds to publish it under `2.2.0`, or suppress published-image alerts while old Tor binaries remain deployed.

Record incomplete candidate gates in the maintainer's validation evidence. The curated release notes are published verbatim after promotion, so keep preparation status and unfinished-test claims out of that publication copy.

### 🔨 Build a local candidate

```sh
version=$(python3 scripts/release/check-versions.py --print-version)
docker buildx build --platform linux/amd64 --load \
  --build-arg BUILD_VERSION="$version-local" -t tor-relay:local .
python3 scripts/testing/image-acceptance.py tor-relay:local
python3 scripts/testing/check-image.py tor-relay:local
```

Repeat with `Dockerfile.edge`. Test both `linux/amd64` and `linux/arm64` on their corresponding hosts or full-system guests. Pass the platform explicitly to image acceptance for ARM64. Check-image reads the Go dependency metadata from the actual transport binary as well as Tor and installed OpenSSL packages.

The Go inspector uses the digest-pinned builder from the policy Dockerfiles on the Docker host architecture, so ARM64 metadata can be inspected natively on an AMD64 host. An exact local inspector image avoids a registry request. Otherwise, its fetch has at most three attempts of 120 seconds each with 10- and 20-second delays. Once fetched, inspection runs with network disabled and implicit pulls prohibited. Component/inspection failures are never retried or bypassed.

Acceptance validates all three sample torrc files after replacing only their address placeholders with reserved test addresses. It also covers guard, exit and bridge generation, custom torrc path, accounting, config validation, PID-preserving reload, fresh restart evidence, bridge transport state and clean shutdown. Injected bootstrap messages test observation logic; they are not proof of live bootstrap.

## 🔄 Upgrade rehearsal

Use two images that already exist locally. Tag the reviewed previous v2.2.0 image as `relay-previous:local` and the candidate as `tor-relay:local`; verify their image IDs instead of relying on a stale local `latest` tag. The rehearsal creates only disposable named volumes and synthetic identities, disables container networking, and tests guard, exit and obfs4 bridge upgrades with ENV-generated and read-only mounted torrc/includes. It stops the old process before starting the replacement, checks identity/family/bridge state and UID/GID, and confirms that historical bootstrap logs do not establish new-run readiness. It removes only its own labelled fixtures.

```sh
python3 scripts/testing/upgrade-rehearsal.py \
  --from-image relay-previous:local \
  --to-image tor-relay:local --output /tmp/relay-upgrade.json
```

Repeat with the corresponding edge images. This is offline compatibility evidence; it does not prove public bootstrap, reachability or consensus flags.

## 🔐 Recovery rehearsal

Follow [Backup](BACKUP.md) using a synthetic source. Create → verify → restore must preserve the fingerprint and pass offline Tor configuration validation. Rehearse named-volume and bind-mount layouts with includes when those match your deployment.

The archive regression suite checks wrong identities, truncation, unsafe paths, links, duplicate entries, mismatched hashes and refusal to overwrite an existing restore destination. Failure-path checks should also confirm that a stopped source stays stopped and a source stopped by create is restarted.

Run the isolated named-volume and bind-mount rehearsal with a task-owned scratch parent accessible to Docker:

```sh
python3 scripts/testing/recovery-rehearsal.py --image tor-relay:local --bind-parent /path/to/scratch
```

## 🎨 Presentation checks

Check every local Markdown link and image with the docs checker. Review the README and curated notes rendered on desktop and mobile. Run the separate website's Hugo build, security audit and tests before including an article in a publication handoff.

## 📋 Prerequisites

- Docker 20.10+
- Docker Compose (optional)
- Local Docker Registry v2 (for development workflow)
- dos2unix (for Windows contributors)

---

## 🏗️ Development Workflow with Local Registry

### Step 1: Start Local Registry

```bash
# Start a local Docker Registry v2
docker run -d -p 5000:5000 --name registry registry:2

# Verify it's running
curl http://localhost:5000/v2/_catalog
```

### Step 2: Build and Push to Local Registry

```bash
# Clone repository
git clone https://github.com/r3bo0tbx1/tor-guard-relay.git
cd tor-guard-relay

# Normalize line endings (important for Windows)
dos2unix docker-entrypoint.sh healthcheck.sh tools/* 2>/dev/null || true

# Build image
docker build -t localhost:5000/onion-relay:test .

# Push to local registry
docker push localhost:5000/onion-relay:test

# Verify in registry
curl http://localhost:5000/v2/onion-relay/tags/list
```

### Step 3: Test from Local Registry

```bash
# Pull from local registry
docker pull localhost:5000/onion-relay:test

# Run test container
docker run --rm localhost:5000/onion-relay:test status
```

**Why use local registry?**
- Mirrors production workflow
- Tests multi-arch builds locally
- Easier to share with team members on same network
- Closer to CI/CD environment

---

## 🧪 Test Scenarios

> [!NOTE]
> The original manual deployment fixtures below are optional developer examples. The release's behavioral gate is `image-acceptance.py` with networking disabled. Live fixtures cannot establish production readiness, and commands that pull `latest` test a published image rather than your local candidate.


### Test 1: Guard Relay (Mounted Config)

```bash
# Create test config
cat > /tmp/relay-test.conf << 'EOF'
Nickname TestGuardRelay
ContactInfo email:test[]example.com url:https://example.com proof:uri-familyid-ed25519 ciissversion:3
ORPort 9001
DirPort 0
ExitRelay 0
ExitPolicy reject *:*
DataDirectory /var/lib/tor
Log notice file /var/log/tor/notices.log
SocksPort 0
EOF

# Run guard relay
docker run -d \
  --name test-guard \
  --network host \
  -v /tmp/relay-test.conf:/etc/tor/torrc:ro \
  -v test-guard-data:/var/lib/tor \
  -v test-guard-logs:/var/log/tor \
  localhost:5000/onion-relay:test

# Verify
docker logs test-guard
# Expected: ✅ Using mounted configuration: /etc/tor/torrc

# Test diagnostics
docker exec test-guard status
docker exec test-guard health | jq .
docker exec test-guard fingerprint

# Cleanup
docker stop test-guard && docker rm test-guard
docker volume rm test-guard-data test-guard-logs
```

### Test 2: Bridge with Official ENV Naming

**Tests drop-in compatibility with `thetorproject/obfs4-bridge`:**

```bash
# Run bridge with official naming
docker run -d \
  --name test-bridge \
  --network host \
  -e OR_PORT=9001 \
  -e PT_PORT=9002 \
  -e EMAIL="email:test[]example.com url:https://example.com proof:uri-familyid-ed25519 ciissversion:3" \
  -e NICKNAME=TestBridge \
  -e OBFS4_ENABLE_ADDITIONAL_VARIABLES=1 \
  -e OBFS4V_AddressDisableIPv6=0 \
  -e OBFS4V_MaxMemInQueues="512 MB" \
  -v test-bridge-data:/var/lib/tor \
  localhost:5000/onion-relay:test

# Verify auto-detection
docker logs test-bridge
# Expected:
# ✅ Configuration generated from ENV vars
# 🌐 Relay mode: bridge (auto-detected from PT_PORT)

# Check generated torrc
docker exec test-bridge cat /etc/tor/torrc
# Should include:
# - BridgeRelay 1
# - ServerTransportPlugin obfs4 exec /usr/bin/lyrebird
# - ServerTransportListenAddr obfs4 0.0.0.0:9002
# - MaxMemInQueues 512 MB

# Verify lyrebird is running
docker exec test-bridge pgrep -a lyrebird

# Test bridge-line tool (after bootstrap)
docker exec test-bridge bridge-line --address 203.0.113.42

# Cleanup
docker stop test-bridge && docker rm test-bridge
docker volume rm test-bridge-data
```

### Test 3: Bridge with Mounted Config (Recommended)

```bash
# Create bridge config
cat > /tmp/bridge-test.conf << 'EOF'
Nickname TestBridgeMounted
ContactInfo email:test[]example.com url:https://example.com proof:uri-familyid-ed25519 ciissversion:3
ORPort 9001
SocksPort 0
DataDirectory /var/lib/tor
Log notice file /var/log/tor/notices.log
BridgeRelay 1
PublishServerDescriptor bridge
ServerTransportPlugin obfs4 exec /usr/bin/lyrebird
ServerTransportListenAddr obfs4 0.0.0.0:9002
ExtORPort auto
MaxMemInQueues 512 MB
AddressDisableIPv6 0
EOF

# Run bridge
docker run -d \
  --name test-bridge-mounted \
  --network host \
  -v /tmp/bridge-test.conf:/etc/tor/torrc:ro \
  -v test-bridge-mounted-data:/var/lib/tor \
  localhost:5000/onion-relay:test

# Verify
docker logs test-bridge-mounted
# Expected: ✅ Using mounted configuration: /etc/tor/torrc

# Cleanup
docker stop test-bridge-mounted && docker rm test-bridge-mounted
docker volume rm test-bridge-mounted-data
```

### Test 4: Health Check

```bash
# The fixture starts Tor with networking disabled and checks stale/current-run evidence.
python3 scripts/testing/image-acceptance.py localhost:5000/onion-relay:test --platform linux/amd64

# Against your deliberately started test relay:
docker exec test-guard /usr/local/bin/healthcheck.sh
docker exec test-guard health | jq '{liveness, config_valid, readiness, fresh, reason}'
docker exec test-guard doctor --json
```

Docker health requires a running Tor process and valid config. A container running only the healthcheck script must fail; a valid torrc alone does not make a relay healthy. Readiness additionally requires fresh current-run evidence.

---

### Test 5: Input Validation

```bash
# Test nickname validation (should fail - too long)
docker run --rm \
  -e TOR_NICKNAME="ThisNicknameIsWayTooLongAndShouldFail" \
  -e TOR_CONTACT_INFO="email:test[]example.com url:https://example.com proof:uri-familyid-ed25519 ciissversion:3" \
  localhost:5000/onion-relay:test 2>&1 | grep -i error

# Test port validation (should fail - invalid port)
docker run --rm \
  -e TOR_NICKNAME="TestRelay" \
  -e TOR_CONTACT_INFO="email:test[]example.com url:https://example.com proof:uri-familyid-ed25519 ciissversion:3" \
  -e TOR_ORPORT="99999" \
  localhost:5000/onion-relay:test 2>&1 | grep -i error

# Test bandwidth format (should succeed)
docker run --rm \
  -e TOR_NICKNAME="TestRelay" \
  -e TOR_CONTACT_INFO="email:test[]example.com url:https://example.com proof:uri-familyid-ed25519 ciissversion:3" \
  -e TOR_BANDWIDTH_RATE="10 MBytes" \
  localhost:5000/onion-relay:test \
  sh -c "cat /etc/tor/torrc | grep -i bandwidth"
```

### Test 6: OBFS4V_* Whitelist Security

```bash
# Test whitelisted variable (should succeed)
docker run --rm \
  -e OR_PORT=9001 \
  -e PT_PORT=9002 \
  -e EMAIL="email:test[]example.com url:https://example.com proof:uri-familyid-ed25519 ciissversion:3" \
  -e NICKNAME=TestSec \
  -e OBFS4_ENABLE_ADDITIONAL_VARIABLES=1 \
  -e OBFS4V_MaxMemInQueues="512 MB" \
  localhost:5000/onion-relay:test \
  sh -c "cat /etc/tor/torrc | grep MaxMemInQueues"

# Test non-whitelisted variable (should warn and skip)
docker run --rm \
  -e OR_PORT=9001 \
  -e PT_PORT=9002 \
  -e EMAIL="email:test[]example.com url:https://example.com proof:uri-familyid-ed25519 ciissversion:3" \
  -e NICKNAME=TestSec \
  -e OBFS4_ENABLE_ADDITIONAL_VARIABLES=1 \
  -e OBFS4V_EvilDirective="malicious value" \
  localhost:5000/onion-relay:test 2>&1 | grep -i "not in whitelist"
```

---

## 🔍 Verification Checklist

After building locally:

- [ ] All tool scripts are executable (`ls -l /usr/local/bin/`)
- [ ] Tool scripts have no .sh extensions
- [ ] All scripts use `#!/bin/sh` shebang
- [ ] Build info exists (`cat /build-info.txt`)
- [ ] Tor version is current (`tor --version`)
- [ ] Lyrebird is available (`/usr/bin/lyrebird --version`)
- [ ] Health check works for both mounted and ENV configs
- [ ] Diagnostic tools produce correct output
- [ ] Input validation catches invalid values
- [ ] OBFS4V_* whitelist blocks dangerous options
- [ ] Image size is ~variant-dependent image size (`docker images localhost:5000/onion-relay:test`)

---

## 🐛 Debugging

### View Generated torrc

```bash
# For ENV-based config
docker run --rm \
  -e TOR_NICKNAME=Debug \
  -e TOR_CONTACT_INFO=email:debug[]test.com url:https://example.com proof:uri-familyid-ed25519 ciissversion:3 \
  localhost:5000/onion-relay:test \
  cat /etc/tor/torrc

# For mounted config
docker run --rm \
  -v /tmp/relay-test.conf:/etc/tor/torrc:ro \
  localhost:5000/onion-relay:test \
  cat /etc/tor/torrc
```

### Check Script Syntax

```bash
# Validate all shell scripts
for script in docker-entrypoint.sh healthcheck.sh tools/*; do
  echo "Checking $script..."
  sh -n "$script" && echo "✅ OK" || echo "❌ FAIL"
done
```

### Test Permissions

```bash
# Check file permissions in image
docker run --rm localhost:5000/onion-relay:test ls -la /usr/local/bin/
docker run --rm localhost:5000/onion-relay:test ls -ldn /var/lib/tor
docker run --rm localhost:5000/onion-relay:test ls -ldn /var/log/tor
```

---

## 🔄 Multi-Arch Testing

### Build for Multiple Architectures

This example requires separate matching-kernel builders for AMD64 and ARM64. Configure those buildx nodes first; a single AMD64 Docker Desktop daemon with binfmt cannot satisfy the ARM64 source-build sandbox gate. For a local alternative, use the full-system guest procedure above and build each architecture on its matching Docker engine.

```bash
# Set up buildx (once)
docker buildx create --name multiarch --use
docker buildx inspect --bootstrap

# Build for both AMD64 and ARM64
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t localhost:5000/onion-relay:multiarch \
  --push \
  .

# Test on current architecture
docker pull localhost:5000/onion-relay:multiarch
docker run --rm localhost:5000/onion-relay:multiarch cat /build-info.txt
```

---

## 🧹 Cleanup

```bash
# Remove only the named fixtures you created for these tests
docker rm -f test-guard test-bridge test-bridge-mounted

# Remove test volumes
docker volume rm test-guard-data test-bridge-data test-bridge-mounted-data

# Remove test images
docker rmi localhost:5000/onion-relay:test
docker rmi localhost:5000/onion-relay:multiarch

# Stop local registry
docker stop registry && docker rm registry

# Clean up test configs
rm -f /tmp/relay-test.conf /tmp/bridge-test.conf
```

---

## 📚 See Also

- **[Contributing Guide](../CONTRIBUTING.md)** - How to contribute code
- **[Deployment Guide](DEPLOYMENT.md)** - Production deployment methods
- **[Migration Guide](MIGRATION-V1.1.X.md)** - Upgrading between versions
- **[Security Policy](../SECURITY.md)** - Security information

---

## 💡 Tips for Contributors

1. **Always test with local registry** - Mirrors production workflow
2. **Test both mounted config and ENV variables** - Both must work
3. **Verify input validation** - Test edge cases and invalid inputs
4. **Check all diagnostic tools** - Ensure they work correctly
5. **Test on multiple architectures** - If you can (buildx helps)
6. **Run security validation** - Use `scripts/utilities/security-validation-tests.sh`
7. **Update documentation** - If you change behavior

---

*This guide is for development and testing. Production users should use published images from Docker Hub or GHCR.*
