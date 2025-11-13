#!/bin/bash
# test-setup-v1.1.0.sh - Create a test v1.1.0 environment for migration testing
# This simulates your production setup in a safe test environment

set -euo pipefail

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Configuration (TEST ENVIRONMENT - different from production)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

BRIDGE_CONTAINER="test-obfs4-bridge"
GUARD_CONTAINER="test-TorGuardRelay"
BRIDGE_VOLUME="test-obfs4-data"
GUARD_DATA_VOLUME="test-tor-guard-data"
GUARD_LOGS_VOLUME="test-tor-guard-logs"
TEST_DIR="${HOME}/tor-test"
LOCALHOST_REGISTRY="localhost:5000"

# Test ports (different from production to avoid conflicts)
TEST_BRIDGE_OR_PORT=19001
TEST_BRIDGE_PT_PORT=19005
TEST_GUARD_OR_PORT=19011
TEST_GUARD_DIR_PORT=19030

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Logging
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

log() { printf "%s\n" "$1"; }
info() { printf "   ℹ️  %s\n" "$1"; }
success() { printf "✅ %s\n" "$1"; }
fail() { printf "❌ %s\n" "$1"; exit 1; }
warn() { printf "⚠️  %s\n" "$1"; }
section() {
  log ""
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log "$1"
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Cleanup function
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

cleanup_test_env() {
  section "🧹 CLEANUP TEST ENVIRONMENT"

  log "Stopping and removing test containers..."
  docker stop "$BRIDGE_CONTAINER" "$GUARD_CONTAINER" 2>/dev/null || true
  docker rm "$BRIDGE_CONTAINER" "$GUARD_CONTAINER" 2>/dev/null || true

  log "Removing test volumes..."
  docker volume rm "$BRIDGE_VOLUME" "$GUARD_DATA_VOLUME" "$GUARD_LOGS_VOLUME" 2>/dev/null || true

  log "Removing test directory..."
  rm -rf "$TEST_DIR"

  success "Test environment cleaned up"
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Main setup
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

main() {
  section "🧪 TEST ENVIRONMENT SETUP - v1.1.0 Simulation"

  log ""
  log "This will create a test environment that simulates your production setup."
  log "Test containers will use different ports to avoid conflicts."
  log ""
  info "Test Bridge:      $BRIDGE_CONTAINER (ports $TEST_BRIDGE_OR_PORT, $TEST_BRIDGE_PT_PORT)"
  info "Test Guard:       $GUARD_CONTAINER (ports $TEST_GUARD_OR_PORT, $TEST_GUARD_DIR_PORT)"
  info "Test volumes:     $BRIDGE_VOLUME, $GUARD_DATA_VOLUME, $GUARD_LOGS_VOLUME"
  info "Test directory:   $TEST_DIR"
  log ""

  read -p "Continue? (y/n) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log "Aborted."
    exit 0
  fi

  # Check if cleanup needed
  if docker ps -a --format '{{.Names}}' | grep -q "^${BRIDGE_CONTAINER}$"; then
    warn "Test containers already exist."
    read -p "Clean up and recreate? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      cleanup_test_env
    else
      fail "Please clean up manually first"
    fi
  fi

  # Create test directory
  section "📁 Creating Test Directory"
  mkdir -p "$TEST_DIR"
  success "Test directory created: $TEST_DIR"

  # Create test torrc for guard relay
  section "📄 Creating Test Guard Relay Config"
  cat > "$TEST_DIR/test-relay.conf" <<EOF
## TEST Guard Relay Configuration
## This simulates your production relay.conf

# Basic Identity (TEST VALUES)
Nickname TestYunoArmpits
ContactInfo test@example.com
Address 127.0.0.1

# Network Configuration (TEST PORTS)
ORPort $TEST_GUARD_OR_PORT
DirPort $TEST_GUARD_DIR_PORT

# Relay Type (SAME AS PRODUCTION)
ExitRelay 0
ExitPolicy reject *:*
IPv6Exit 0
SocksPort 0

# Bandwidth Configuration
RelayBandwidthRate 10 MB
RelayBandwidthBurst 20 MB

# Resource Limits
NumCPUs 1
MaxMemInQueues 256 MB

# Safety & Stability
AssumeReachable 1
SafeLogging 1
AvoidDiskWrites 1
DisableDebuggerAttachment 1

# Data & Logging
DataDirectory /var/lib/tor
Log notice file /var/log/tor/notices.log
Log notice stdout

# Server Publishing (disabled for testing)
PublishServerDescriptor 0
EOF

  success "Test torrc created: $TEST_DIR/test-relay.conf"
  info "ExitRelay 0 and ExitPolicy reject *:* are set (matching production)"

  # Create Docker volumes
  section "💾 Creating Test Volumes"
  docker volume create "$BRIDGE_VOLUME"
  docker volume create "$GUARD_DATA_VOLUME"
  docker volume create "$GUARD_LOGS_VOLUME"
  success "Test volumes created"

  # Check for v1.1.0 image
  section "🔍 Checking for v1.1.0 Image"
  if docker images | grep -q "onion-relay.*1.1.0"; then
    success "Found existing v1.1.0 image"
    V110_IMAGE=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep "onion-relay.*1.1.0" | head -n1)
    info "Using: $V110_IMAGE"
  elif docker images | grep -q "${LOCALHOST_REGISTRY}/r3bo0tbx1/onion-relay"; then
    warn "No v1.1.0 tag found, using localhost:5000/r3bo0tbx1/onion-relay:latest"
    V110_IMAGE="${LOCALHOST_REGISTRY}/r3bo0tbx1/onion-relay:latest"
  else
    warn "No v1.1.0 image found locally"
    info "Will use r3bo0tbx1/onion-relay:latest (simulating v1.1.0)"
    V110_IMAGE="r3bo0tbx1/onion-relay:latest"
  fi

  # Start test bridge container (simulating v1.1.0)
  section "🌉 Starting Test Bridge Container (v1.1.0)"
  log "Creating bridge with ENV variables (matching your production setup)..."

  docker run -d \
    --name "$BRIDGE_CONTAINER" \
    --restart unless-stopped \
    --network host \
    -e "OR_PORT=${TEST_BRIDGE_OR_PORT}" \
    -e "PT_PORT=${TEST_BRIDGE_PT_PORT}" \
    -e "EMAIL=test-admin@example.org" \
    -e "NICKNAME=TestKurisuFeet" \
    -e "OBFS4_ENABLE_ADDITIONAL_VARIABLES=1" \
    -e "OBFS4V_AddressDisableIPv6=0" \
    -e "OBFS4V_MaxMemInQueues=256 MB" \
    -e "OBFS4V_PublishServerDescriptor=0" \
    -v "${BRIDGE_VOLUME}:/var/lib/tor" \
    --security-opt no-new-privileges:true \
    --cap-add NET_BIND_SERVICE \
    --cap-add CHOWN \
    --cap-add SETUID \
    --cap-add SETGID \
    --cap-add DAC_OVERRIDE \
    "$V110_IMAGE"

  success "Test bridge container started: $BRIDGE_CONTAINER"

  # Start test guard relay container (simulating v1.1.0)
  section "🛡️  Starting Test Guard Relay Container (v1.1.0)"
  log "Creating guard with mounted torrc (matching your production setup)..."

  docker run -d \
    --name "$GUARD_CONTAINER" \
    --restart unless-stopped \
    --network host \
    -e "TZ=UTC" \
    -v "${GUARD_DATA_VOLUME}:/var/lib/tor" \
    -v "${GUARD_LOGS_VOLUME}:/var/log/tor" \
    -v "${TEST_DIR}/test-relay.conf:/etc/tor/torrc:ro" \
    --security-opt no-new-privileges:true \
    --cap-add NET_BIND_SERVICE \
    --cap-add CHOWN \
    --cap-add SETUID \
    --cap-add SETGID \
    --cap-add DAC_OVERRIDE \
    "$V110_IMAGE"

  success "Test guard container started: $GUARD_CONTAINER"

  # Wait for initialization
  section "⏳ Waiting for Initialization (30 seconds)"
  log "Waiting for containers to start and generate keys..."
  sleep 30

  # Verify containers are running
  section "✅ Verification"

  log ""
  log "📋 Container Status:"
  docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "NAMES|test-"

  log ""
  log "📦 Volume Status:"
  docker volume ls | grep test-

  log ""
  log "🔑 Checking for generated keys..."
  BRIDGE_KEYS=$(docker run --rm -v "${BRIDGE_VOLUME}:/data" alpine:3.22.2 \
    sh -c "test -d /data/keys && ls -1 /data/keys 2>/dev/null | wc -l || echo 0")
  GUARD_KEYS=$(docker run --rm -v "${GUARD_DATA_VOLUME}:/data" alpine:3.22.2 \
    sh -c "test -d /data/keys && ls -1 /data/keys 2>/dev/null | wc -l || echo 0")

  if [[ "$BRIDGE_KEYS" -gt 0 ]]; then
    success "Bridge has $BRIDGE_KEYS key files"
  else
    warn "Bridge keys not generated yet (may need more time)"
  fi

  if [[ "$GUARD_KEYS" -gt 0 ]]; then
    success "Guard has $GUARD_KEYS key files"
  else
    warn "Guard keys not generated yet (may need more time)"
  fi

  log ""
  log "📄 Checking configurations..."

  # Check bridge config
  if docker exec "$BRIDGE_CONTAINER" cat /etc/tor/torrc 2>/dev/null | grep -q "BridgeRelay 1"; then
    success "Bridge: BridgeRelay 1 confirmed"
  else
    warn "Bridge: BridgeRelay not found in config"
  fi

  # Check guard config
  if docker exec "$GUARD_CONTAINER" cat /etc/tor/torrc 2>/dev/null | grep -q "ExitPolicy reject \*:\*"; then
    success "Guard: ExitPolicy reject *:* confirmed"
  else
    warn "Guard: ExitPolicy not found in config"
  fi

  if docker exec "$GUARD_CONTAINER" cat /etc/tor/torrc 2>/dev/null | grep -q "ExitRelay 0"; then
    success "Guard: ExitRelay 0 confirmed"
  else
    warn "Guard: ExitRelay 0 not found in config"
  fi

  log ""
  log "📊 Container Logs (last 10 lines):"
  log ""
  log "--- Bridge ---"
  docker logs "$BRIDGE_CONTAINER" --tail 10 2>&1 | sed 's/^/  /'
  log ""
  log "--- Guard ---"
  docker logs "$GUARD_CONTAINER" --tail 10 2>&1 | sed 's/^/  /'

  # Final summary
  section "🎉 TEST ENVIRONMENT READY"

  log ""
  success "Test v1.1.0 environment is running!"
  log ""
  log "📋 Test Environment Details:"
  log "  Bridge Container:  $BRIDGE_CONTAINER"
  log "  Guard Container:   $GUARD_CONTAINER"
  log "  Bridge Volume:     $BRIDGE_VOLUME"
  log "  Guard Data Volume: $GUARD_DATA_VOLUME"
  log "  Guard Logs Volume: $GUARD_LOGS_VOLUME"
  log "  Test Config:       $TEST_DIR/test-relay.conf"
  log ""
  log "  Bridge Ports:      $TEST_BRIDGE_OR_PORT (OR), $TEST_BRIDGE_PT_PORT (obfs4)"
  log "  Guard Ports:       $TEST_GUARD_OR_PORT (OR), $TEST_GUARD_DIR_PORT (Dir)"
  log ""
  log "🔍 Useful Commands:"
  log "  docker logs -f $BRIDGE_CONTAINER"
  log "  docker logs -f $GUARD_CONTAINER"
  log "  docker exec $BRIDGE_CONTAINER cat /etc/tor/torrc"
  log "  docker exec $GUARD_CONTAINER cat /etc/tor/torrc"
  log ""
  log "📁 Next Steps:"
  log "  1. Wait 2-5 minutes for Tor to bootstrap"
  log "  2. Check logs for 'Bootstrapped 100%'"
  log "  3. Build v1.1.1 image: ./test-build-v1.1.1.sh"
  log "  4. Run test migration: ./test-migration.sh"
  log ""
  log "🧹 To Clean Up:"
  log "  ./test-setup-v1.1.0.sh cleanup"
  log ""
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Script entry point
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

if [[ "${1:-}" == "cleanup" ]]; then
  cleanup_test_env
else
  main
fi
