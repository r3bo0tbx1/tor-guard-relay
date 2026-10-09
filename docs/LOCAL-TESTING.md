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
> 🧅 **v2.2.0 release candidate:** Tor must be **0.4.9.14 or newer**. Current-run health, validated configuration and encrypted recovery are described in the [release notes](releases/v2.2.0.md). Recreate from the validated image to update Tor; changing torrc alone does not upgrade the binary.

## Environment

Docker Desktop on Windows with WSL works. Run host scripts in Linux/WSL with Python 3.10+, age, ShellCheck and dos2unix. A Linux Docker daemon is also supported. ARM64 testing on an AMD64 machine requires registered QEMU/binfmt support.

On Docker Desktop, finish WSL source/recovery commands before registering ARM64 emulation and running ARM64 fixtures. This environment has reset binfmt registration when WSL sessions changed; running those steps concurrently produced local `exec format error` failures. Re-register with `docker run --privileged --rm tonistiigi/binfmt --install arm64` after the WSL commands finish, then run ARM64 builds and tests sequentially with respect to WSL activity.

## 🔎 Source checks

```sh
python3 scripts/release/check-versions.py
python3 scripts/testing/check-templates.py
python3 scripts/testing/check-docs.py
shellcheck -S warning -x docker-entrypoint.sh healthcheck.sh lib/*.sh tools/* scripts/utilities/relay-backup.sh scripts/utilities/relay-inventory.sh
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

```sh
docker buildx build --platform linux/amd64 --load \
  --build-arg BUILD_VERSION=2.2.0-local -t tor-relay:2.2.0-local .
python3 scripts/testing/image-acceptance.py tor-relay:2.2.0-local
python3 scripts/testing/check-image.py tor-relay:2.2.0-local
```

Repeat with `Dockerfile.edge` and both `linux/amd64` and `linux/arm64`. Pass the platform explicitly to image acceptance for ARM64. Check-image reads the Go dependency metadata from the actual transport binary as well as Tor and installed OpenSSL packages.

The Go inspector uses the digest-pinned builder from the policy Dockerfiles on the Docker host architecture, so ARM64 metadata can be inspected natively on an AMD64 host. An exact local inspector image avoids a registry request. Otherwise, its fetch has at most three attempts of 120 seconds each with 10- and 20-second delays. Once fetched, inspection runs with network disabled and implicit pulls prohibited. Component/inspection failures are never retried or bypassed.

Acceptance covers guard, exit and bridge generation, custom torrc path, accounting, config validation, PID-preserving reload, fresh restart evidence, bridge transport state and clean shutdown. Injected bootstrap messages test observation logic; they are not proof of live bootstrap.

## 🔐 Recovery rehearsal

Follow [Backup](BACKUP.md) using a synthetic source. Create → verify → restore must preserve the fingerprint and pass offline Tor configuration validation. Rehearse named-volume and bind-mount layouts with includes when those match your deployment.

The archive regression suite checks wrong identities, truncation, unsafe paths, links, duplicate entries, mismatched hashes and refusal to overwrite an existing restore destination. Failure-path checks should also confirm that a stopped source stays stopped and a source stopped by create is restarted.

Run the isolated named-volume and bind-mount rehearsal with a task-owned scratch parent accessible to Docker:

```sh
python3 scripts/testing/recovery-rehearsal.py --image tor-relay:2.2.0-local --bind-parent /path/to/scratch
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
