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

### Test 1: Guard Relay (Mounted Config)

```bash
# Create test config
cat > /tmp/relay-test.conf << 'EOF'
Nickname TestGuardRelay
ContactInfo test@example.com
ORPort 9001
DirPort 9030
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
  -e EMAIL="test@example.com" \
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
docker exec test-bridge bridge-line

# Cleanup
docker stop test-bridge && docker rm test-bridge
docker volume rm test-bridge-data
```

### Test 3: Bridge with Mounted Config (Recommended)

```bash
# Create bridge config
cat > /tmp/bridge-test.conf << 'EOF'
Nickname TestBridgeMounted
ContactInfo test@example.com
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
# Test health check script directly
docker run --rm \
  -v /tmp/relay-test.conf:/etc/tor/torrc:ro \
  localhost:5000/onion-relay:test \
  /usr/local/bin/healthcheck.sh

# Expected: exit code 0 (healthy)
echo "Health check status: $?"

# Test with invalid config
docker run --rm localhost:5000/onion-relay:test sh -c \
  "echo 'InvalidDirective BadValue' > /etc/tor/torrc && /usr/local/bin/healthcheck.sh"

# Expected: exit code 1 (unhealthy)
echo "Health check status: $?"
```

### Test 5: Input Validation

```bash
# Test nickname validation (should fail - too long)
docker run --rm \
  -e TOR_NICKNAME="ThisNicknameIsWayTooLongAndShouldFail" \
  -e TOR_CONTACT_INFO="test@example.com" \
  localhost:5000/onion-relay:test 2>&1 | grep -i error

# Test port validation (should fail - invalid port)
docker run --rm \
  -e TOR_NICKNAME="TestRelay" \
  -e TOR_CONTACT_INFO="test@example.com" \
  -e TOR_ORPORT="99999" \
  localhost:5000/onion-relay:test 2>&1 | grep -i error

# Test bandwidth format (should succeed)
docker run --rm \
  -e TOR_NICKNAME="TestRelay" \
  -e TOR_CONTACT_INFO="test@example.com" \
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
  -e EMAIL="test@example.com" \
  -e NICKNAME=TestSec \
  -e OBFS4_ENABLE_ADDITIONAL_VARIABLES=1 \
  -e OBFS4V_MaxMemInQueues="512 MB" \
  localhost:5000/onion-relay:test \
  sh -c "cat /etc/tor/torrc | grep MaxMemInQueues"

# Test non-whitelisted variable (should warn and skip)
docker run --rm \
  -e OR_PORT=9001 \
  -e PT_PORT=9002 \
  -e EMAIL="test@example.com" \
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
- [ ] Image size is ~17.1MB (`docker images localhost:5000/onion-relay:test`)

---

## 🐛 Debugging

### View Generated torrc

```bash
# For ENV-based config
docker run --rm \
  -e TOR_NICKNAME=Debug \
  -e TOR_CONTACT_INFO=debug@test.com \
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
# Stop and remove all test containers
docker ps -a | grep test- | awk '{print $1}' | xargs docker rm -f

# Remove test volumes
docker volume ls | grep test- | awk '{print $2}' | xargs docker volume rm

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
- **[Migration Guide](../MIGRATION-V1.1.X.md)** - Upgrading between versions
- **[Security Audit Report](../SECURITY-AUDIT-REPORT.md)** - Security fixes

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
