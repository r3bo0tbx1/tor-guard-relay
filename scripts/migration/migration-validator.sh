#!/bin/bash
# migration-validator.sh - Comprehensive validation script for Tor relay migration
# v1.1.1 - Safe migration from v1.1.0 to v1.1.1
# Usage: ./migration-validator.sh [pre-migration|post-migration|rollback-check]

set -euo pipefail

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Configuration
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

BACKUP_DIR="${HOME}/backup"
STATE_FILE="${BACKUP_DIR}/migration-state.txt"
BRIDGE_CONTAINER="obfs4-bridge"
GUARD_CONTAINER="TorGuardRelay"
GUARD_TORRC_PATH="/home/akira/onion/relay.conf"

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

check_root() {
  if [[ $EUID -ne 0 ]]; then
    fail "This script must be run with sudo/root privileges"
    exit 1
  fi
}

check_docker() {
  if ! command -v docker &> /dev/null; then
    fail "Docker is not installed or not in PATH"
    exit 1
  fi
  success "Docker is available"
}

ensure_backup_dir() {
  if [[ ! -d "$BACKUP_DIR" ]]; then
    log "Creating backup directory: $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
  fi
  success "Backup directory ready: $BACKUP_DIR"
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
# Pre-migration checks and backups
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

pre_migration_checks() {
  section "🔍 PRE-MIGRATION VALIDATION"

  log ""
  log "This will validate your current v1.1.0 setup and create backups."
  log "⚠️  DO NOT proceed to migration until all checks pass!"
  log ""

  > "$STATE_FILE"

  log "📦 Checking Docker volumes..."
  if docker volume ls | grep -q "obfs4-data"; then
    success "Volume 'obfs4-data' exists"
    save_state "VOLUME_OBFS4_EXISTS" "yes"
  else
    fail "Volume 'obfs4-data' NOT FOUND"
    return 1
  fi

  if docker volume ls | grep -q "tor-guard-data"; then
    success "Volume 'tor-guard-data' exists"
    save_state "VOLUME_GUARD_DATA_EXISTS" "yes"
  else
    fail "Volume 'tor-guard-data' NOT FOUND"
    return 1
  fi

  if docker volume ls | grep -q "tor-guard-logs"; then
    success "Volume 'tor-guard-logs' exists"
    save_state "VOLUME_GUARD_LOGS_EXISTS" "yes"
  else
    fail "Volume 'tor-guard-logs' NOT FOUND"
    return 1
  fi

  log ""
  log "🐳 Checking containers..."
  if docker ps -a --format '{{.Names}}' | grep -q "^${BRIDGE_CONTAINER}$"; then
    success "Container '${BRIDGE_CONTAINER}' exists"
    if docker ps --format '{{.Names}}' | grep -q "^${BRIDGE_CONTAINER}$"; then
      info "Bridge container is RUNNING"
      save_state "BRIDGE_WAS_RUNNING" "yes"
    else
      warn "Bridge container is STOPPED"
      save_state "BRIDGE_WAS_RUNNING" "no"
    fi
  else
    warn "Container '${BRIDGE_CONTAINER}' not found (might be new setup)"
    save_state "BRIDGE_EXISTS" "no"
  fi

  if docker ps -a --format '{{.Names}}' | grep -q "^${GUARD_CONTAINER}$"; then
    success "Container '${GUARD_CONTAINER}' exists"
    if docker ps --format '{{.Names}}' | grep -q "^${GUARD_CONTAINER}$"; then
      info "Guard container is RUNNING"
      save_state "GUARD_WAS_RUNNING" "yes"
    else
      warn "Guard container is STOPPED"
      save_state "GUARD_WAS_RUNNING" "no"
    fi
  else
    warn "Container '${GUARD_CONTAINER}' not found (might be new setup)"
    save_state "GUARD_EXISTS" "no"
  fi

  log ""
  log "🔑 Saving current fingerprints..."
  if docker ps --format '{{.Names}}' | grep -q "^${BRIDGE_CONTAINER}$"; then
    BRIDGE_FP=$(docker exec "$BRIDGE_CONTAINER" cat /var/lib/tor/fingerprint 2>/dev/null || echo "")
    if [[ -n "$BRIDGE_FP" ]]; then
      success "Bridge fingerprint: $BRIDGE_FP"
      save_state "BRIDGE_FINGERPRINT" "$BRIDGE_FP"
      echo "$BRIDGE_FP" > "${BACKUP_DIR}/bridge-fingerprint.txt"
    else
      warn "No bridge fingerprint found (might be new bridge)"
    fi
  else
    warn "Cannot read bridge fingerprint (container not running)"
  fi

  if docker ps --format '{{.Names}}' | grep -q "^${GUARD_CONTAINER}$"; then
    GUARD_FP=$(docker exec "$GUARD_CONTAINER" cat /var/lib/tor/fingerprint 2>/dev/null || echo "")
    if [[ -n "$GUARD_FP" ]]; then
      success "Guard fingerprint: $GUARD_FP"
      save_state "GUARD_FINGERPRINT" "$GUARD_FP"
      echo "$GUARD_FP" > "${BACKUP_DIR}/guard-fingerprint.txt"
    else
      warn "No guard fingerprint found (might be new relay)"
    fi
  else
    warn "Cannot read guard fingerprint (container not running)"
  fi

  log ""
  log "🔐 Checking for Tor identity keys..."
  if docker run --rm -v obfs4-data:/data alpine:3.23.3 test -d /data/keys; then
    KEY_COUNT=$(docker run --rm -v obfs4-data:/data alpine:3.23.3 ls -1 /data/keys 2>/dev/null | wc -l)
    if [[ "$KEY_COUNT" -gt 0 ]]; then
      success "Bridge has $KEY_COUNT key files in /var/lib/tor/keys/"
      save_state "BRIDGE_KEYS_COUNT" "$KEY_COUNT"
    else
      warn "Bridge keys directory exists but is empty (new bridge?)"
    fi
  else
    warn "Bridge keys directory does not exist yet"
  fi

  if docker run --rm -v tor-guard-data:/data alpine:3.23.3 test -d /data/keys; then
    KEY_COUNT=$(docker run --rm -v tor-guard-data:/data alpine:3.23.3 ls -1 /data/keys 2>/dev/null | wc -l)
    if [[ "$KEY_COUNT" -gt 0 ]]; then
      success "Guard has $KEY_COUNT key files in /var/lib/tor/keys/"
      save_state "GUARD_KEYS_COUNT" "$KEY_COUNT"
    else
      warn "Guard keys directory exists but is empty (new relay?)"
    fi
  else
    warn "Guard keys directory does not exist yet"
  fi

  log ""
  log "📄 Checking guard relay torrc file..."
  if [[ -f "$GUARD_TORRC_PATH" ]]; then
    success "Guard torrc found at: $GUARD_TORRC_PATH"

    if grep -q "^ExitRelay 0" "$GUARD_TORRC_PATH"; then
      success "  ✓ ExitRelay 0 confirmed"
    else
      warn "  ! ExitRelay 0 not found in torrc"
    fi

    if grep -q "^ExitPolicy reject \*:\*" "$GUARD_TORRC_PATH"; then
      success "  ✓ ExitPolicy reject *:* confirmed"
    else
      warn "  ! ExitPolicy reject *:* not found in torrc"
    fi

    cp "$GUARD_TORRC_PATH" "${BACKUP_DIR}/relay.conf.backup"
    success "Torrc backed up to: ${BACKUP_DIR}/relay.conf.backup"
  else
    fail "Guard torrc NOT FOUND at: $GUARD_TORRC_PATH"
    return 1
  fi
}

backup_all_data() {
  section "💾 CREATING BACKUPS"

  log ""
  log "Creating timestamped backups of all volumes and configs..."
  log "This may take a few minutes depending on data size."
  log ""

  TIMESTAMP=$(date +%Y%m%d-%H%M%S)

  log "📦 Backing up obfs4-data..."
  docker run --rm \
    -v obfs4-data:/data \
    -v "${BACKUP_DIR}:/backup" \
    alpine:3.23.3 \
    tar czf "/backup/obfs4-data-backup-${TIMESTAMP}.tar.gz" -C /data . 2>&1 | grep -v "tar:" || true

  if [[ -f "${BACKUP_DIR}/obfs4-data-backup-${TIMESTAMP}.tar.gz" ]]; then
    SIZE=$(du -h "${BACKUP_DIR}/obfs4-data-backup-${TIMESTAMP}.tar.gz" | cut -f1)
    success "Bridge backup created: obfs4-data-backup-${TIMESTAMP}.tar.gz ($SIZE)"
    save_state "BRIDGE_BACKUP_FILE" "obfs4-data-backup-${TIMESTAMP}.tar.gz"
  else
    fail "Bridge backup FAILED"
    return 1
  fi

  log ""
  log "📦 Backing up tor-guard-data..."
  docker run --rm \
    -v tor-guard-data:/data \
    -v "${BACKUP_DIR}:/backup" \
    alpine:3.23.3 \
    tar czf "/backup/tor-guard-data-backup-${TIMESTAMP}.tar.gz" -C /data . 2>&1 | grep -v "tar:" || true

  if [[ -f "${BACKUP_DIR}/tor-guard-data-backup-${TIMESTAMP}.tar.gz" ]]; then
    SIZE=$(du -h "${BACKUP_DIR}/tor-guard-data-backup-${TIMESTAMP}.tar.gz" | cut -f1)
    success "Guard data backup created: tor-guard-data-backup-${TIMESTAMP}.tar.gz ($SIZE)"
    save_state "GUARD_DATA_BACKUP_FILE" "tor-guard-data-backup-${TIMESTAMP}.tar.gz"
  else
    fail "Guard data backup FAILED"
    return 1
  fi

  log ""
  log "📦 Backing up tor-guard-logs..."
  docker run --rm \
    -v tor-guard-logs:/data \
    -v "${BACKUP_DIR}:/backup" \
    alpine:3.23.3 \
    tar czf "/backup/tor-guard-logs-backup-${TIMESTAMP}.tar.gz" -C /data . 2>&1 | grep -v "tar:" || true

  if [[ -f "${BACKUP_DIR}/tor-guard-logs-backup-${TIMESTAMP}.tar.gz" ]]; then
    SIZE=$(du -h "${BACKUP_DIR}/tor-guard-logs-backup-${TIMESTAMP}.tar.gz" | cut -f1)
    success "Guard logs backup created: tor-guard-logs-backup-${TIMESTAMP}.tar.gz ($SIZE)"
    save_state "GUARD_LOGS_BACKUP_FILE" "tor-guard-logs-backup-${TIMESTAMP}.tar.gz"
  else
    fail "Guard logs backup FAILED"
    return 1
  fi

  log ""
  log "🐳 Backing up container configurations..."
  docker inspect "$BRIDGE_CONTAINER" > "${BACKUP_DIR}/bridge-config-${TIMESTAMP}.json" 2>/dev/null || warn "Could not backup bridge container config"
  docker inspect "$GUARD_CONTAINER" > "${BACKUP_DIR}/guard-config-${TIMESTAMP}.json" 2>/dev/null || warn "Could not backup guard container config"

  log ""
  success "All backups completed successfully!"
  log ""
  info "Backup location: $BACKUP_DIR"
  info "Backup timestamp: $TIMESTAMP"
  log ""
  log "📋 Backup files:"
  ls -lh "${BACKUP_DIR}/"*"${TIMESTAMP}"* 2>/dev/null || true
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Post-migration validation
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

post_migration_checks() {
  section "✅ POST-MIGRATION VALIDATION"

  log ""
  log "Validating migrated containers and data integrity..."
  log ""

  log "⏳ Waiting 15 seconds for containers to initialize..."
  sleep 15

  log ""
  log "📦 Verifying volumes preserved..."
  docker volume ls | grep -q "obfs4-data" && success "Volume 'obfs4-data' preserved" || fail "Volume 'obfs4-data' MISSING"
  docker volume ls | grep -q "tor-guard-data" && success "Volume 'tor-guard-data' preserved" || fail "Volume 'tor-guard-data' MISSING"
  docker volume ls | grep -q "tor-guard-logs" && success "Volume 'tor-guard-logs' preserved" || fail "Volume 'tor-guard-logs' MISSING"

  log ""
  log "🐳 Checking container status..."
  if docker ps --format '{{.Names}}' | grep -q "^${BRIDGE_CONTAINER}$"; then
    success "Bridge container is RUNNING"
  else
    fail "Bridge container is NOT RUNNING"
    docker ps -a | grep "$BRIDGE_CONTAINER" || warn "Container not found at all"
  fi

  if docker ps --format '{{.Names}}' | grep -q "^${GUARD_CONTAINER}$"; then
    success "Guard container is RUNNING"
  else
    fail "Guard container is NOT RUNNING"
    docker ps -a | grep "$GUARD_CONTAINER" || warn "Container not found at all"
  fi

  log ""
  log "🔑 Verifying fingerprints preserved..."
  SAVED_BRIDGE_FP=$(load_state "BRIDGE_FINGERPRINT")
  SAVED_GUARD_FP=$(load_state "GUARD_FINGERPRINT")

  if [[ -n "$SAVED_BRIDGE_FP" ]]; then
    CURRENT_BRIDGE_FP=$(docker exec "$BRIDGE_CONTAINER" cat /var/lib/tor/fingerprint 2>/dev/null || echo "")
    if [[ "$CURRENT_BRIDGE_FP" == "$SAVED_BRIDGE_FP" ]]; then
      success "Bridge fingerprint MATCHED (identity preserved)"
    else
      fail "Bridge fingerprint MISMATCH!"
      info "  Expected: $SAVED_BRIDGE_FP"
      info "  Got:      $CURRENT_BRIDGE_FP"
    fi
  else
    warn "No saved bridge fingerprint to compare (might be new bridge)"
    CURRENT_BRIDGE_FP=$(docker exec "$BRIDGE_CONTAINER" cat /var/lib/tor/fingerprint 2>/dev/null || echo "")
    if [[ -n "$CURRENT_BRIDGE_FP" ]]; then
      info "  Current: $CURRENT_BRIDGE_FP"
    fi
  fi

  if [[ -n "$SAVED_GUARD_FP" ]]; then
    CURRENT_GUARD_FP=$(docker exec "$GUARD_CONTAINER" cat /var/lib/tor/fingerprint 2>/dev/null || echo "")
    if [[ "$CURRENT_GUARD_FP" == "$SAVED_GUARD_FP" ]]; then
      success "Guard fingerprint MATCHED (identity preserved)"
    else
      fail "Guard fingerprint MISMATCH!"
      info "  Expected: $SAVED_GUARD_FP"
      info "  Got:      $CURRENT_GUARD_FP"
    fi
  else
    warn "No saved guard fingerprint to compare (might be new relay)"
    CURRENT_GUARD_FP=$(docker exec "$GUARD_CONTAINER" cat /var/lib/tor/fingerprint 2>/dev/null || echo "")
    if [[ -n "$CURRENT_GUARD_FP" ]]; then
      info "  Current: $CURRENT_GUARD_FP"
    fi
  fi

  log ""
  log "🔐 Verifying Tor keys preserved..."
  SAVED_BRIDGE_KEYS=$(load_state "BRIDGE_KEYS_COUNT")
  if [[ -n "$SAVED_BRIDGE_KEYS" ]] && [[ "$SAVED_BRIDGE_KEYS" != "0" ]]; then
    CURRENT_BRIDGE_KEYS=$(docker run --rm -v obfs4-data:/data alpine:3.23.3 ls -1 /data/keys 2>/dev/null | wc -l)
    if [[ "$CURRENT_BRIDGE_KEYS" -ge "$SAVED_BRIDGE_KEYS" ]]; then
      success "Bridge has $CURRENT_BRIDGE_KEYS key files (expected >= $SAVED_BRIDGE_KEYS)"
    else
      fail "Bridge key count mismatch: expected >= $SAVED_BRIDGE_KEYS, got $CURRENT_BRIDGE_KEYS"
    fi
  else
    warn "No saved bridge key count to compare"
  fi

  SAVED_GUARD_KEYS=$(load_state "GUARD_KEYS_COUNT")
  if [[ -n "$SAVED_GUARD_KEYS" ]] && [[ "$SAVED_GUARD_KEYS" != "0" ]]; then
    CURRENT_GUARD_KEYS=$(docker run --rm -v tor-guard-data:/data alpine:3.23.3 ls -1 /data/keys 2>/dev/null | wc -l)
    if [[ "$CURRENT_GUARD_KEYS" -ge "$SAVED_GUARD_KEYS" ]]; then
      success "Guard has $CURRENT_GUARD_KEYS key files (expected >= $SAVED_GUARD_KEYS)"
    else
      fail "Guard key count mismatch: expected >= $SAVED_GUARD_KEYS, got $CURRENT_GUARD_KEYS"
    fi
  else
    warn "No saved guard key count to compare"
  fi

  log ""
  log "🌉 Validating bridge configuration..."
  BRIDGE_TORRC=$(docker exec "$BRIDGE_CONTAINER" cat /etc/tor/torrc 2>/dev/null || echo "")
  if [[ -n "$BRIDGE_TORRC" ]]; then
    echo "$BRIDGE_TORRC" | grep -q "BridgeRelay 1" && success "  ✓ BridgeRelay 1" || fail "  ✗ BridgeRelay 1 missing"
    echo "$BRIDGE_TORRC" | grep -q "ORPort 9001" && success "  ✓ ORPort 9001" || warn "  ! ORPort not 9001"
    echo "$BRIDGE_TORRC" | grep -q "ServerTransportListenAddr obfs4.*9005" && success "  ✓ obfs4 port 9005" || warn "  ! obfs4 port not 9005"
    echo "$BRIDGE_TORRC" | grep -q "Nickname KurisuMakiseFeet" && success "  ✓ Nickname preserved" || warn "  ! Nickname changed"
  else
    fail "Could not read bridge torrc"
  fi

  log ""
  log "🛡️  Validating guard relay configuration..."
  GUARD_TORRC=$(docker exec "$GUARD_CONTAINER" cat /etc/tor/torrc 2>/dev/null || echo "")
  if [[ -n "$GUARD_TORRC" ]]; then
    echo "$GUARD_TORRC" | grep -q "ExitRelay 0" && success "  ✓ ExitRelay 0 (NOT an exit)" || fail "  ✗ ExitRelay 0 missing"
    echo "$GUARD_TORRC" | grep -q "ExitPolicy reject \*:\*" && success "  ✓ ExitPolicy reject *:*" || fail "  ✗ ExitPolicy reject *:* missing"
    echo "$GUARD_TORRC" | grep -q "ORPort 9001" && success "  ✓ ORPort 9001" || warn "  ! ORPort not 9001"
    echo "$GUARD_TORRC" | grep -q "DirPort 9030" && success "  ✓ DirPort 9030" || warn "  ! DirPort not 9030"
    echo "$GUARD_TORRC" | grep -q "Nickname YunoSweatyArmpits" && success "  ✓ Nickname preserved" || warn "  ! Nickname changed"
  else
    fail "Could not read guard torrc"
  fi

  log ""
  log "🔌 Checking network ports..."
  if ss -tulnp 2>/dev/null | grep -q ":9001 "; then
    success "ORPort 9001 is listening"
  else
    warn "ORPort 9001 not detected (may still be bootstrapping)"
  fi

  if ss -tulnp 2>/dev/null | grep -q ":9005 "; then
    success "Bridge obfs4 port 9005 is listening"
  else
    warn "Bridge port 9005 not detected (may still be bootstrapping)"
  fi

  if ss -tulnp 2>/dev/null | grep -q ":9030 "; then
    success "Guard DirPort 9030 is listening"
  else
    warn "Guard DirPort 9030 not detected (may still be bootstrapping)"
  fi

  log ""
  log "📋 Checking container logs for errors..."
  BRIDGE_ERRORS=$(docker logs "$BRIDGE_CONTAINER" --since 5m 2>&1 | grep -i "error\|critical\|failed" | grep -v "Permission denied" | wc -l)
  if [[ "$BRIDGE_ERRORS" -eq 0 ]]; then
    success "Bridge logs: No errors in last 5 minutes"
  else
    warn "Bridge logs: Found $BRIDGE_ERRORS potential error messages"
    info "Run: docker logs $BRIDGE_CONTAINER --since 5m | grep -i error"
  fi

  GUARD_ERRORS=$(docker logs "$GUARD_CONTAINER" --since 5m 2>&1 | grep -i "error\|critical\|failed" | grep -v "Permission denied" | wc -l)
  if [[ "$GUARD_ERRORS" -eq 0 ]]; then
    success "Guard logs: No errors in last 5 minutes"
  else
    warn "Guard logs: Found $GUARD_ERRORS potential error messages"
    info "Run: docker logs $GUARD_CONTAINER --since 5m | grep -i error"
  fi

  log ""
  log "🔄 Checking Tor bootstrap status..."
  BRIDGE_BOOTSTRAP=$(docker logs "$BRIDGE_CONTAINER" --since 10m 2>&1 | grep -i "Bootstrapped" | tail -n1 || echo "")
  if echo "$BRIDGE_BOOTSTRAP" | grep -q "100%"; then
    success "Bridge: Bootstrapped 100% (connected to Tor network)"
  elif echo "$BRIDGE_BOOTSTRAP" | grep -q "Bootstrapped"; then
    warn "Bridge: Bootstrap in progress: $BRIDGE_BOOTSTRAP"
    info "This is normal, wait 5-10 minutes"
  else
    warn "Bridge: No bootstrap status found yet"
  fi

  GUARD_BOOTSTRAP=$(docker logs "$GUARD_CONTAINER" --since 10m 2>&1 | grep -i "Bootstrapped" | tail -n1 || echo "")
  if echo "$GUARD_BOOTSTRAP" | grep -q "100%"; then
    success "Guard: Bootstrapped 100% (connected to Tor network)"
  elif echo "$GUARD_BOOTSTRAP" | grep -q "Bootstrapped"; then
    warn "Guard: Bootstrap in progress: $GUARD_BOOTSTRAP"
    info "This is normal, wait 5-10 minutes"
  else
    warn "Guard: No bootstrap status found yet"
  fi
  log ""
  log "📄 Verifying configuration source..."
  if docker logs "$BRIDGE_CONTAINER" --since 10m 2>&1 | grep -q "Configuration generated from ENV vars"; then
    success "Bridge: Using ENV variables (correct for bridge mode)"
  elif docker logs "$BRIDGE_CONTAINER" --since 10m 2>&1 | grep -q "Using mounted configuration"; then
    warn "Bridge: Using mounted config (expected ENV vars)"
  fi

  if docker logs "$GUARD_CONTAINER" --since 10m 2>&1 | grep -q "Using mounted configuration"; then
    success "Guard: Using mounted torrc (correct)"
  elif docker logs "$GUARD_CONTAINER" --since 10m 2>&1 | grep -q "Configuration generated from ENV vars"; then
    warn "Guard: Using ENV vars (expected mounted torrc)"
  fi
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Test summary
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

print_summary() {
  section "📊 VALIDATION SUMMARY"
  log ""
  log "Test Results:"
  log "  ✅ Passed:  $TESTS_PASSED"
  log "  ❌ Failed:  $TESTS_FAILED"
  log "  ⚠️  Warnings: $TESTS_WARNED"
  log ""

  if [[ $TESTS_FAILED -eq 0 ]]; then
    if [[ $TESTS_WARNED -eq 0 ]]; then
      success "🎉 ALL TESTS PASSED! Migration successful."
      log ""
      log "Next steps:"
      log "  1. Monitor logs for 10-15 minutes: docker logs -f $BRIDGE_CONTAINER"
      log "  2. Wait for 'Bootstrapped 100%' message"
      log "  3. Check Tor Metrics in 24-48 hours for your relays"
      log ""
      return 0
    else
      warn "✅ All critical tests passed, but there are $TESTS_WARNED warnings."
      log ""
      log "Warnings are usually non-critical (bootstrap in progress, etc.)"
      log "Monitor logs and re-run this script in 10 minutes."
      log ""
      return 0
    fi
  else
    fail "❌ MIGRATION HAS ISSUES: $TESTS_FAILED test(s) failed!"
    log ""
    log "⚠️  DO NOT PROCEED without investigating failures."
    log ""
    log "To rollback:"
    log "  sudo ./migration-validator.sh rollback-check"
    log ""
    return 1
  fi
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Rollback validation
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

rollback_check() {
  section "🔙 ROLLBACK READINESS CHECK"

  log ""
  log "Checking if you can safely rollback to v1.1.0..."
  log ""

  log "📦 Checking backups..."
  BRIDGE_BACKUP=$(load_state "BRIDGE_BACKUP_FILE")
  GUARD_DATA_BACKUP=$(load_state "GUARD_DATA_BACKUP_FILE")
  GUARD_LOGS_BACKUP=$(load_state "GUARD_LOGS_BACKUP_FILE")

  if [[ -f "${BACKUP_DIR}/${BRIDGE_BACKUP}" ]]; then
    success "Bridge backup found: $BRIDGE_BACKUP"
  else
    fail "Bridge backup NOT FOUND"
  fi

  if [[ -f "${BACKUP_DIR}/${GUARD_DATA_BACKUP}" ]]; then
    success "Guard data backup found: $GUARD_DATA_BACKUP"
  else
    fail "Guard data backup NOT FOUND"
  fi

  if [[ -f "${BACKUP_DIR}/${GUARD_LOGS_BACKUP}" ]]; then
    success "Guard logs backup found: $GUARD_LOGS_BACKUP"
  else
    fail "Guard logs backup NOT FOUND"
  fi

  if [[ -f "${BACKUP_DIR}/relay.conf.backup" ]]; then
    success "Guard torrc backup found"
  else
    warn "Guard torrc backup not found"
  fi

  log ""
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log "🔙 ROLLBACK COMMANDS"
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log ""
  log "Run these commands to rollback:"
  log ""
  log "# 1. Stop and remove new containers"
  log "sudo docker stop $BRIDGE_CONTAINER $GUARD_CONTAINER"
  log "sudo docker rm $BRIDGE_CONTAINER $GUARD_CONTAINER"
  log ""
  log "# 2. Restore bridge volume"
  log "sudo docker run --rm -v obfs4-data:/data -v ${BACKUP_DIR}:/backup alpine:3.23.3 \\"
  log "  sh -c 'rm -rf /data/* && tar xzf /backup/${BRIDGE_BACKUP} -C /data'"
  log ""
  log "# 3. Restore guard data volume"
  log "sudo docker run --rm -v tor-guard-data:/data -v ${BACKUP_DIR}:/backup alpine:3.23.3 \\"
  log "  sh -c 'rm -rf /data/* && tar xzf /backup/${GUARD_DATA_BACKUP} -C /data'"
  log ""
  log "# 4. Restore guard logs volume"
  log "sudo docker run --rm -v tor-guard-logs:/data -v ${BACKUP_DIR}:/backup alpine:3.23.3 \\"
  log "  sh -c 'rm -rf /data/* && tar xzf /backup/${GUARD_LOGS_BACKUP} -C /data'"
  log ""
  log "# 5. Re-import old v1.1.0 Cosmos JSON configs"
  log "# (Manually via Cosmos UI, or recreate containers with docker run)"
  log ""
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Main script logic
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

main() {
  local mode="${1:-pre-migration}"

  log ""
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log "🧅 Tor Relay Migration Validator v1.1.6"
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log ""

  check_root
  check_docker
  ensure_backup_dir

  case "$mode" in
    pre-migration)
      pre_migration_checks
      backup_all_data
      print_summary
      log ""
      log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      log "✅ PRE-MIGRATION COMPLETE"
      log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      log ""
      log "You can now proceed with migration:"
      log "  1. Stop containers: sudo docker stop $BRIDGE_CONTAINER $GUARD_CONTAINER"
      log "  2. Fix permissions (see migration guide)"
      log "  3. Pull new image: sudo docker pull r3bo0tbx1/onion-relay:latest"
      log "  4. Import new Cosmos JSON configs"
      log "  5. Run post-migration validation: sudo ./migration-validator.sh post-migration"
      log ""
      ;;

    post-migration)
      post_migration_checks
      print_summary
      ;;

    rollback-check)
      rollback_check
      ;;

    *)
      log "Usage: $0 [pre-migration|post-migration|rollback-check]"
      log ""
      log "Modes:"
      log "  pre-migration   - Validate current setup and create backups"
      log "  post-migration  - Validate migration was successful"
      log "  rollback-check  - Show rollback commands if needed"
      log ""
      exit 1
      ;;
  esac
}

main "$@"
