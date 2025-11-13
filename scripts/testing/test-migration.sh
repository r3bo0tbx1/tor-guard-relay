#!/bin/bash
# test-migration.sh - Test migration from v1.1.0 to v1.1.1 in safe test environment
# Usage: ./test-migration.sh [pre-migration|migrate|post-migration|rollback]

set -euo pipefail

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# TEST Configuration (different from production)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

BRIDGE_CONTAINER="test-obfs4-bridge"
GUARD_CONTAINER="test-TorGuardRelay"
BRIDGE_VOLUME="test-obfs4-data"
GUARD_DATA_VOLUME="test-tor-guard-data"
GUARD_LOGS_VOLUME="test-tor-guard-logs"
TEST_DIR="${HOME}/tor-test"
BACKUP_DIR="${TEST_DIR}/backup"
STATE_FILE="${BACKUP_DIR}/test-migration-state.txt"
GUARD_TORRC_PATH="${TEST_DIR}/test-relay.conf"

LOCALHOST_REGISTRY="localhost:5000"
V111_IMAGE="${LOCALHOST_REGISTRY}/r3bo0tbx1/onion-relay:1.1.1"

# Test ports
TEST_BRIDGE_OR_PORT=19001
TEST_BRIDGE_PT_PORT=19005
TEST_GUARD_OR_PORT=19011
TEST_GUARD_DIR_PORT=19030

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_WARNED=0

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Logging helpers
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

log() { printf "%s\n" "$1"; }
info() { printf "   ℹ️  %s\n" "$1"; }
success() { printf "✅ %s\n" "$1"; ((TESTS_PASSED++)); }
fail() { printf "❌ %s\n" "$1"; ((TESTS_FAILED++)); }
warn() { printf "⚠️  %s\n" "$1"; ((TESTS_WARNED++)); }
section() {
  log ""
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log "$1"
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Helper functions
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

ensure_backup_dir() {
  if [[ ! -d "$BACKUP_DIR" ]]; then
    mkdir -p "$BACKUP_DIR"
  fi
}

save_state() {
  local key="$1"
  local value="$2"
  echo "${key}=${value}" >> "$STATE_FILE"
}

load_state() {
  local key="$1"
  if [[ -f "$STATE_FILE" ]]; then
    grep "^${key}=" "$STATE_FILE" | tail -n1 | cut -d= -f2- || echo ""
  else
    echo ""
  fi
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Pre-migration checks
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pre_migration_checks() {
  section "🔍 PRE-MIGRATION VALIDATION (TEST MODE)"

  log ""
  log "Testing migration on test containers (safe, non-production)"
  log ""

  ensure_backup_dir
  > "$STATE_FILE"

  # Check 1: Test containers exist
  log "🐳 Checking test containers..."
  if docker ps -a --format '{{.Names}}' | grep -q "^${BRIDGE_CONTAINER}$"; then
    success "Test bridge container exists"
    if docker ps --format '{{.Names}}' | grep -q "^${BRIDGE_CONTAINER}$"; then
      info "Bridge is RUNNING"
      save_state "BRIDGE_WAS_RUNNING" "yes"
    else
      warn "Bridge is STOPPED"
      save_state "BRIDGE_WAS_RUNNING" "no"
    fi
  else
    fail "Test bridge container NOT FOUND - run ./test-setup-v1.1.0.sh first"
    return 1
  fi

  if docker ps -a --format '{{.Names}}' | grep -q "^${GUARD_CONTAINER}$"; then
    success "Test guard container exists"
    if docker ps --format '{{.Names}}' | grep -q "^${GUARD_CONTAINER}$"; then
      info "Guard is RUNNING"
      save_state "GUARD_WAS_RUNNING" "yes"
    else
      warn "Guard is STOPPED"
      save_state "GUARD_WAS_RUNNING" "no"
    fi
  else
    fail "Test guard container NOT FOUND - run ./test-setup-v1.1.0.sh first"
    return 1
  fi

  # Check 2: Volumes exist
  log ""
  log "📦 Checking test volumes..."
  docker volume ls | grep -q "$BRIDGE_VOLUME" && success "Volume '$BRIDGE_VOLUME' exists" || fail "Volume '$BRIDGE_VOLUME' NOT FOUND"
  docker volume ls | grep -q "$GUARD_DATA_VOLUME" && success "Volume '$GUARD_DATA_VOLUME' exists" || fail "Volume '$GUARD_DATA_VOLUME' NOT FOUND"
  docker volume ls | grep -q "$GUARD_LOGS_VOLUME" && success "Volume '$GUARD_LOGS_VOLUME' exists" || fail "Volume '$GUARD_LOGS_VOLUME' NOT FOUND"

  # Check 3: Save fingerprints
  log ""
  log "🔑 Saving current fingerprints..."
  if docker ps --format '{{.Names}}' | grep -q "^${BRIDGE_CONTAINER}$"; then
    BRIDGE_FP=$(docker exec "$BRIDGE_CONTAINER" cat /var/lib/tor/fingerprint 2>/dev/null || echo "")
    if [[ -n "$BRIDGE_FP" ]]; then
      success "Bridge fingerprint: $BRIDGE_FP"
      save_state "BRIDGE_FINGERPRINT" "$BRIDGE_FP"
      echo "$BRIDGE_FP" > "${BACKUP_DIR}/test-bridge-fingerprint.txt"
    else
      warn "No bridge fingerprint yet (may need more time)"
    fi
  fi

  if docker ps --format '{{.Names}}' | grep -q "^${GUARD_CONTAINER}$"; then
    GUARD_FP=$(docker exec "$GUARD_CONTAINER" cat /var/lib/tor/fingerprint 2>/dev/null || echo "")
    if [[ -n "$GUARD_FP" ]]; then
      success "Guard fingerprint: $GUARD_FP"
      save_state "GUARD_FINGERPRINT" "$GUARD_FP"
      echo "$GUARD_FP" > "${BACKUP_DIR}/test-guard-fingerprint.txt"
    else
      warn "No guard fingerprint yet (may need more time)"
    fi
  fi

  # Check 4: Count keys
  log ""
  log "🔐 Checking for Tor keys..."
  if docker run --rm -v "${BRIDGE_VOLUME}:/data" alpine:3.22.2 test -d /data/keys; then
    KEY_COUNT=$(docker run --rm -v "${BRIDGE_VOLUME}:/data" alpine:3.22.2 ls -1 /data/keys 2>/dev/null | wc -l)
    if [[ "$KEY_COUNT" -gt 0 ]]; then
      success "Bridge has $KEY_COUNT key files"
      save_state "BRIDGE_KEYS_COUNT" "$KEY_COUNT"
    else
      warn "Bridge keys directory empty"
    fi
  else
    warn "Bridge keys directory doesn't exist yet"
  fi

  if docker run --rm -v "${GUARD_DATA_VOLUME}:/data" alpine:3.22.2 test -d /data/keys; then
    KEY_COUNT=$(docker run --rm -v "${GUARD_DATA_VOLUME}:/data" alpine:3.22.2 ls -1 /data/keys 2>/dev/null | wc -l)
    if [[ "$KEY_COUNT" -gt 0 ]]; then
      success "Guard has $KEY_COUNT key files"
      save_state "GUARD_KEYS_COUNT" "$KEY_COUNT"
    else
      warn "Guard keys directory empty"
    fi
  else
    warn "Guard keys directory doesn't exist yet"
  fi

  # Check 5: Verify torrc
  log ""
  log "📄 Checking guard torrc..."
  if [[ -f "$GUARD_TORRC_PATH" ]]; then
    success "Guard torrc found"
    grep -q "^ExitRelay 0" "$GUARD_TORRC_PATH" && success "  ✓ ExitRelay 0" || warn "  ! ExitRelay 0 not found"
    grep -q "^ExitPolicy reject \*:\*" "$GUARD_TORRC_PATH" && success "  ✓ ExitPolicy reject *:*" || warn "  ! ExitPolicy not found"
  else
    fail "Guard torrc NOT FOUND"
  fi

  # Backup
  log ""
  log "💾 Creating backups..."
  TIMESTAMP=$(date +%Y%m%d-%H%M%S)

  docker run --rm -v "${BRIDGE_VOLUME}:/data" -v "${BACKUP_DIR}:/backup" alpine:3.22.2 \
    tar czf "/backup/test-bridge-backup-${TIMESTAMP}.tar.gz" -C /data . 2>&1 | grep -v "tar:" || true
  [[ -f "${BACKUP_DIR}/test-bridge-backup-${TIMESTAMP}.tar.gz" ]] && \
    success "Bridge backed up" || fail "Bridge backup failed"
  save_state "BRIDGE_BACKUP_FILE" "test-bridge-backup-${TIMESTAMP}.tar.gz"

  docker run --rm -v "${GUARD_DATA_VOLUME}:/data" -v "${BACKUP_DIR}:/backup" alpine:3.22.2 \
    tar czf "/backup/test-guard-data-backup-${TIMESTAMP}.tar.gz" -C /data . 2>&1 | grep -v "tar:" || true
  [[ -f "${BACKUP_DIR}/test-guard-data-backup-${TIMESTAMP}.tar.gz" ]] && \
    success "Guard data backed up" || fail "Guard data backup failed"
  save_state "GUARD_DATA_BACKUP_FILE" "test-guard-data-backup-${TIMESTAMP}.tar.gz"

  docker run --rm -v "${GUARD_LOGS_VOLUME}:/data" -v "${BACKUP_DIR}:/backup" alpine:3.22.2 \
    tar czf "/backup/test-guard-logs-backup-${TIMESTAMP}.tar.gz" -C /data . 2>&1 | grep -v "tar:" || true
  [[ -f "${BACKUP_DIR}/test-guard-logs-backup-${TIMESTAMP}.tar.gz" ]] && \
    success "Guard logs backed up" || fail "Guard logs backup failed"
  save_state "GUARD_LOGS_BACKUP_FILE" "test-guard-logs-backup-${TIMESTAMP}.tar.gz"

  section "✅ PRE-MIGRATION COMPLETE"
  log ""
  log "Backups saved in: $BACKUP_DIR"
  log "State saved in: $STATE_FILE"
  log ""
  log "Ready to migrate! Run:"
  log "  ./test-migration.sh migrate"
  log ""
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Migration execution
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

do_migration() {
  section "🔄 EXECUTING TEST MIGRATION"

  log ""
  log "This will migrate test containers from v1.1.0 to v1.1.1"
  log ""
  info "Bridge: $BRIDGE_CONTAINER"
  info "Guard:  $GUARD_CONTAINER"
  info "New image: $V111_IMAGE"
  log ""

  read -p "Continue? (y/n) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log "Migration cancelled"
    exit 0
  fi

  # Step 1: Stop containers
  log ""
  log "🛑 Stopping test containers..."
  docker stop "$BRIDGE_CONTAINER" "$GUARD_CONTAINER"
  success "Containers stopped"

  # Step 2: Fix permissions
  log ""
  log "🔐 Fixing volume permissions for Alpine UID 100:101..."
  docker run --rm -v "${BRIDGE_VOLUME}:/data" alpine:3.22.2 chown -R 100:101 /data
  docker run --rm -v "${GUARD_DATA_VOLUME}:/data" alpine:3.22.2 chown -R 100:101 /data
  docker run --rm -v "${GUARD_LOGS_VOLUME}:/data" alpine:3.22.2 chown -R 100:101 /data
  success "Permissions fixed"

  # Verify ownership
  OWNER=$(docker run --rm -v "${BRIDGE_VOLUME}:/data" alpine:3.22.2 stat -c "%u %g" /data)
  if [[ "$OWNER" == "100 101" ]]; then
    success "  Bridge volume: UID 100, GID 101 ✓"
  else
    warn "  Bridge volume ownership: $OWNER (expected 100 101)"
  fi

  # Step 3: Pull new image
  log ""
  log "📥 Pulling v1.1.1 image..."
  if docker pull "$V111_IMAGE"; then
    success "Image pulled: $V111_IMAGE"
  else
    fail "Failed to pull image - is it built? Run ./test-build-v1.1.1.sh"
    return 1
  fi

  # Step 4: Remove old containers
  log ""
  log "🗑️  Removing old containers..."
  docker rm "$BRIDGE_CONTAINER" "$GUARD_CONTAINER"
  success "Old containers removed"

  # Step 5: Create new bridge container
  log ""
  log "🌉 Creating new bridge container (v1.1.1)..."
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
    --cap-drop ALL \
    --cap-add NET_BIND_SERVICE \
    --cap-add CHOWN \
    --cap-add SETUID \
    --cap-add SETGID \
    --cap-add DAC_OVERRIDE \
    "$V111_IMAGE"
  success "Bridge container created"

  # Step 6: Create new guard container
  log ""
  log "🛡️  Creating new guard container (v1.1.1)..."
  docker run -d \
    --name "$GUARD_CONTAINER" \
    --restart unless-stopped \
    --network host \
    -e "TZ=UTC" \
    -v "${GUARD_DATA_VOLUME}:/var/lib/tor" \
    -v "${GUARD_LOGS_VOLUME}:/var/log/tor" \
    -v "${GUARD_TORRC_PATH}:/etc/tor/torrc:ro" \
    --security-opt no-new-privileges:true \
    --cap-drop ALL \
    --cap-add NET_BIND_SERVICE \
    --cap-add CHOWN \
    --cap-add SETUID \
    --cap-add SETGID \
    --cap-add DAC_OVERRIDE \
    "$V111_IMAGE"
  success "Guard container created"

  # Step 7: Wait for initialization
  log ""
  log "⏳ Waiting 15 seconds for initialization..."
  sleep 15

  section "✅ MIGRATION COMPLETE"
  log ""
  log "New containers running with v1.1.1"
  log ""
  log "📋 Container Status:"
  docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Image}}" | grep -E "NAMES|test-"
  log ""
  log "Next step:"
  log "  ./test-migration.sh post-migration"
  log ""
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Post-migration validation
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

post_migration_checks() {
  section "✅ POST-MIGRATION VALIDATION (TEST MODE)"

  log ""
  log "Validating test migration success..."
  log ""

  # Reset counters
  TESTS_PASSED=0
  TESTS_FAILED=0
  TESTS_WARNED=0

  # Wait a bit more
  log "⏳ Waiting additional 10 seconds..."
  sleep 10

  # Check 1: Containers running
  log ""
  log "🐳 Checking containers..."
  if docker ps --format '{{.Names}}' | grep -q "^${BRIDGE_CONTAINER}$"; then
    success "Bridge container RUNNING"
  else
    fail "Bridge container NOT RUNNING"
  fi

  if docker ps --format '{{.Names}}' | grep -q "^${GUARD_CONTAINER}$"; then
    success "Guard container RUNNING"
  else
    fail "Guard container NOT RUNNING"
  fi

  # Check 2: Using v1.1.1 image
  log ""
  log "🏷️  Checking image versions..."
  BRIDGE_IMAGE=$(docker inspect "$BRIDGE_CONTAINER" --format '{{.Config.Image}}' 2>/dev/null || echo "")
  GUARD_IMAGE=$(docker inspect "$GUARD_CONTAINER" --format '{{.Config.Image}}' 2>/dev/null || echo "")

  if echo "$BRIDGE_IMAGE" | grep -q "1.1.1"; then
    success "Bridge using v1.1.1 image"
  else
    fail "Bridge NOT using v1.1.1: $BRIDGE_IMAGE"
  fi

  if echo "$GUARD_IMAGE" | grep -q "1.1.1"; then
    success "Guard using v1.1.1 image"
  else
    fail "Guard NOT using v1.1.1: $GUARD_IMAGE"
  fi

  # Check 3: Fingerprints match
  log ""
  log "🔑 Verifying fingerprints..."
  SAVED_BRIDGE_FP=$(load_state "BRIDGE_FINGERPRINT")
  SAVED_GUARD_FP=$(load_state "GUARD_FINGERPRINT")

  if [[ -n "$SAVED_BRIDGE_FP" ]]; then
    CURRENT_BRIDGE_FP=$(docker exec "$BRIDGE_CONTAINER" cat /var/lib/tor/fingerprint 2>/dev/null || echo "")
    if [[ "$CURRENT_BRIDGE_FP" == "$SAVED_BRIDGE_FP" ]]; then
      success "Bridge fingerprint MATCHED ✓"
    else
      fail "Bridge fingerprint MISMATCH!"
      info "  Expected: $SAVED_BRIDGE_FP"
      info "  Got:      $CURRENT_BRIDGE_FP"
    fi
  else
    warn "No saved bridge fingerprint to compare"
  fi

  if [[ -n "$SAVED_GUARD_FP" ]]; then
    CURRENT_GUARD_FP=$(docker exec "$GUARD_CONTAINER" cat /var/lib/tor/fingerprint 2>/dev/null || echo "")
    if [[ "$CURRENT_GUARD_FP" == "$SAVED_GUARD_FP" ]]; then
      success "Guard fingerprint MATCHED ✓"
    else
      fail "Guard fingerprint MISMATCH!"
      info "  Expected: $SAVED_GUARD_FP"
      info "  Got:      $CURRENT_GUARD_FP"
    fi
  else
    warn "No saved guard fingerprint to compare"
  fi

  # Check 4: Key counts
  log ""
  log "🔐 Verifying keys preserved..."
  SAVED_BRIDGE_KEYS=$(load_state "BRIDGE_KEYS_COUNT")
  if [[ -n "$SAVED_BRIDGE_KEYS" ]] && [[ "$SAVED_BRIDGE_KEYS" != "0" ]]; then
    CURRENT_BRIDGE_KEYS=$(docker run --rm -v "${BRIDGE_VOLUME}:/data" alpine:3.22.2 ls -1 /data/keys 2>/dev/null | wc -l)
    if [[ "$CURRENT_BRIDGE_KEYS" -ge "$SAVED_BRIDGE_KEYS" ]]; then
      success "Bridge keys: $CURRENT_BRIDGE_KEYS (expected >= $SAVED_BRIDGE_KEYS)"
    else
      fail "Bridge key count mismatch"
    fi
  fi

  SAVED_GUARD_KEYS=$(load_state "GUARD_KEYS_COUNT")
  if [[ -n "$SAVED_GUARD_KEYS" ]] && [[ "$SAVED_GUARD_KEYS" != "0" ]]; then
    CURRENT_GUARD_KEYS=$(docker run --rm -v "${GUARD_DATA_VOLUME}:/data" alpine:3.22.2 ls -1 /data/keys 2>/dev/null | wc -l)
    if [[ "$CURRENT_GUARD_KEYS" -ge "$SAVED_GUARD_KEYS" ]]; then
      success "Guard keys: $CURRENT_GUARD_KEYS (expected >= $SAVED_GUARD_KEYS)"
    else
      fail "Guard key count mismatch"
    fi
  fi

  # Check 5: Configs
  log ""
  log "📄 Validating configurations..."
  BRIDGE_TORRC=$(docker exec "$BRIDGE_CONTAINER" cat /etc/tor/torrc 2>/dev/null || echo "")
  echo "$BRIDGE_TORRC" | grep -q "BridgeRelay 1" && success "  ✓ BridgeRelay 1" || fail "  ✗ BridgeRelay 1 missing"
  echo "$BRIDGE_TORRC" | grep -q "ServerTransportListenAddr obfs4.*${TEST_BRIDGE_PT_PORT}" && success "  ✓ obfs4 port correct" || warn "  ! obfs4 port"

  GUARD_TORRC=$(docker exec "$GUARD_CONTAINER" cat /etc/tor/torrc 2>/dev/null || echo "")
  echo "$GUARD_TORRC" | grep -q "ExitRelay 0" && success "  ✓ ExitRelay 0" || fail "  ✗ ExitRelay 0 MISSING!"
  echo "$GUARD_TORRC" | grep -q "ExitPolicy reject \*:\*" && success "  ✓ ExitPolicy reject *:*" || fail "  ✗ ExitPolicy MISSING!"

  # Check 6: Ports
  log ""
  log "🔌 Checking network ports..."
  if ss -tulnp 2>/dev/null | grep -q ":${TEST_BRIDGE_OR_PORT} "; then
    success "Bridge OR port listening"
  else
    warn "Bridge OR port not detected"
  fi

  if ss -tulnp 2>/dev/null | grep -q ":${TEST_BRIDGE_PT_PORT} "; then
    success "Bridge obfs4 port listening"
  else
    warn "Bridge obfs4 port not detected"
  fi

  if ss -tulnp 2>/dev/null | grep -q ":${TEST_GUARD_OR_PORT} "; then
    success "Guard OR port listening"
  else
    warn "Guard OR port not detected"
  fi

  # Check 7: Bootstrap
  log ""
  log "🔄 Checking bootstrap status..."
  BRIDGE_BOOTSTRAP=$(docker logs "$BRIDGE_CONTAINER" --since 5m 2>&1 | grep -i "Bootstrapped" | tail -n1 || echo "")
  if echo "$BRIDGE_BOOTSTRAP" | grep -q "100%"; then
    success "Bridge: Bootstrapped 100%"
  elif echo "$BRIDGE_BOOTSTRAP" | grep -q "Bootstrapped"; then
    warn "Bridge: Bootstrap in progress"
    info "$BRIDGE_BOOTSTRAP"
  else
    warn "Bridge: No bootstrap status yet"
  fi

  GUARD_BOOTSTRAP=$(docker logs "$GUARD_CONTAINER" --since 5m 2>&1 | grep -i "Bootstrapped" | tail -n1 || echo "")
  if echo "$GUARD_BOOTSTRAP" | grep -q "100%"; then
    success "Guard: Bootstrapped 100%"
  elif echo "$GUARD_BOOTSTRAP" | grep -q "Bootstrapped"; then
    warn "Guard: Bootstrap in progress"
    info "$GUARD_BOOTSTRAP"
  else
    warn "Guard: No bootstrap status yet"
  fi

  # Summary
  section "📊 TEST MIGRATION SUMMARY"
  log ""
  log "Results:"
  log "  ✅ Passed:   $TESTS_PASSED"
  log "  ❌ Failed:   $TESTS_FAILED"
  log "  ⚠️  Warnings: $TESTS_WARNED"
  log ""

  if [[ $TESTS_FAILED -eq 0 ]]; then
    success "🎉 TEST MIGRATION SUCCESSFUL!"
    log ""
    log "The migration process works correctly."
    log "You can safely use this on production."
    log ""
    log "📋 Review logs:"
    log "  docker logs -f $BRIDGE_CONTAINER"
    log "  docker logs -f $GUARD_CONTAINER"
    log ""
    return 0
  else
    fail "❌ TEST MIGRATION HAS ISSUES: $TESTS_FAILED failures"
    log ""
    log "Please report these failures:"
    log "  1. Copy the output above"
    log "  2. Include container logs:"
    log "     docker logs $BRIDGE_CONTAINER --tail 50"
    log "     docker logs $GUARD_CONTAINER --tail 50"
    log ""
    log "To rollback test:"
    log "  ./test-migration.sh rollback"
    log ""
    return 1
  fi
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Rollback
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

do_rollback() {
  section "🔙 TEST ROLLBACK"

  log ""
  warn "This will restore test containers to pre-migration state"
  log ""
  read -p "Continue? (y/n) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log "Rollback cancelled"
    exit 0
  fi

  log ""
  log "🛑 Stopping containers..."
  docker stop "$BRIDGE_CONTAINER" "$GUARD_CONTAINER" 2>/dev/null || true
  docker rm "$BRIDGE_CONTAINER" "$GUARD_CONTAINER" 2>/dev/null || true

  log ""
  log "📦 Restoring volumes from backups..."
  BRIDGE_BACKUP=$(load_state "BRIDGE_BACKUP_FILE")
  GUARD_DATA_BACKUP=$(load_state "GUARD_DATA_BACKUP_FILE")
  GUARD_LOGS_BACKUP=$(load_state "GUARD_LOGS_BACKUP_FILE")

  if [[ -f "${BACKUP_DIR}/${BRIDGE_BACKUP}" ]]; then
    docker run --rm -v "${BRIDGE_VOLUME}:/data" -v "${BACKUP_DIR}:/backup" alpine:3.22.2 \
      sh -c "rm -rf /data/* && tar xzf /backup/${BRIDGE_BACKUP} -C /data"
    success "Bridge volume restored"
  else
    fail "Bridge backup not found: ${BRIDGE_BACKUP}"
  fi

  if [[ -f "${BACKUP_DIR}/${GUARD_DATA_BACKUP}" ]]; then
    docker run --rm -v "${GUARD_DATA_VOLUME}:/data" -v "${BACKUP_DIR}:/backup" alpine:3.22.2 \
      sh -c "rm -rf /data/* && tar xzf /backup/${GUARD_DATA_BACKUP} -C /data"
    success "Guard data volume restored"
  else
    fail "Guard data backup not found: ${GUARD_DATA_BACKUP}"
  fi

  log ""
  success "Rollback complete! Re-run ./test-setup-v1.1.0.sh to restart test environment"
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Main
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

main() {
  local mode="${1:-}"

  log ""
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log "🧪 TEST MIGRATION: v1.1.0 → v1.1.1"
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log ""

  case "$mode" in
    pre-migration)
      pre_migration_checks
      ;;
    migrate)
      do_migration
      ;;
    post-migration)
      post_migration_checks
      ;;
    rollback)
      do_rollback
      ;;
    *)
      log "Usage: $0 [pre-migration|migrate|post-migration|rollback]"
      log ""
      log "Test Migration Workflow:"
      log "  1. ./test-migration.sh pre-migration   - Validate & backup"
      log "  2. ./test-migration.sh migrate          - Perform migration"
      log "  3. ./test-migration.sh post-migration   - Validate success"
      log "  4. ./test-migration.sh rollback         - Rollback if needed"
      log ""
      exit 1
      ;;
  esac
}

main "$@"
