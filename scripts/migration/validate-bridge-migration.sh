#!/bin/bash
# validate-bridge-migration.sh - Verify bridge migration success
# Run this AFTER you've deployed the v1.1.1 container

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}ℹ️  $1${NC}"; }
success() { echo -e "${GREEN}✅ $1${NC}"; }
error() { echo -e "${RED}❌ $1${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $1${NC}"; }

CONTAINER_NAME="obfs4-bridge"
EXPECTED_FINGERPRINT="${1:-}"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔍 Bridge Migration Validation"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ -n "$EXPECTED_FINGERPRINT" ]; then
    log "Expected fingerprint: $EXPECTED_FINGERPRINT"
    echo ""
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Test 1: Container running
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

log "Test 1: Checking if container is running..."

if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    UPTIME=$(docker ps --format '{{.Names}}\t{{.Status}}' | grep "^${CONTAINER_NAME}" | awk '{print $2, $3, $4}')
    success "Container is running (uptime: $UPTIME)"
else
    error "Container is NOT running!"
    log "Check logs with: docker logs ${CONTAINER_NAME}"
    exit 1
fi

echo ""

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Test 2: Configuration source
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

log "Test 2: Verifying configuration source..."

LOGS=$(docker logs "${CONTAINER_NAME}" 2>&1 | tail -100)

if echo "$LOGS" | grep -q "Config source: environment"; then
    success "Configuration generated from ENV variables (correct)"
elif echo "$LOGS" | grep -q "Config source: mounted"; then
    error "Using MOUNTED configuration (should be environment)!"
    warn "This means an old torrc file still exists. Run bridge-migration-fix.sh again."
    exit 1
else
    warn "Could not determine config source from logs"
fi

echo ""

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Test 3: Relay mode
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

log "Test 3: Verifying relay mode..."

if echo "$LOGS" | grep -q "Relay mode: bridge"; then
    success "Bridge mode detected (correct)"
else
    error "Bridge mode NOT detected!"
    warn "Check if PT_PORT environment variable is set"
    exit 1
fi

echo ""

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Test 4: Configuration validation
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

log "Test 4: Checking configuration validation..."

if echo "$LOGS" | grep -q "Configuration is valid"; then
    success "Configuration validated successfully"
else
    error "Configuration validation FAILED!"
    log "Recent logs:"
    echo "$LOGS" | tail -20 | sed 's/^/   /'
    exit 1
fi

echo ""

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Test 5: Tor startup
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

log "Test 5: Verifying Tor started..."

if echo "$LOGS" | grep -q "Starting Tor relay"; then
    success "Tor relay started"
else
    error "Tor relay did NOT start!"
    exit 1
fi

echo ""

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Test 6: Bootstrap progress
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

log "Test 6: Checking bootstrap progress..."

if echo "$LOGS" | grep -q "Bootstrapped 100% (done): Done"; then
    success "Bootstrap completed (100%)"
elif echo "$LOGS" | grep "Bootstrapped" | tail -1 | grep -qE "Bootstrapped [0-9]+%"; then
    BOOTSTRAP=$(echo "$LOGS" | grep "Bootstrapped" | tail -1 | sed -n 's/.*Bootstrapped \([0-9]\+%\).*/\1/p')
    warn "Bootstrap in progress: $BOOTSTRAP (wait a few more seconds)"
else
    warn "Bootstrap progress not yet visible (container may be starting)"
fi

echo ""

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Test 7: Fingerprint check
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

log "Test 7: Verifying bridge fingerprint..."

sleep 2  # Give Tor a moment to create keys if needed

CURRENT_FINGERPRINT=$(docker exec "${CONTAINER_NAME}" fingerprint 2>/dev/null | grep -oE '[A-F0-9]{40}' | head -1 || echo "")

if [ -z "$CURRENT_FINGERPRINT" ]; then
    warn "Could not retrieve fingerprint yet (may need more time to bootstrap)"
else
    success "Current fingerprint: $CURRENT_FINGERPRINT"

    if [ -n "$EXPECTED_FINGERPRINT" ]; then
        if [ "$CURRENT_FINGERPRINT" = "$EXPECTED_FINGERPRINT" ]; then
            success "Fingerprint MATCHES original! Bridge identity preserved! 🎉"
        else
            error "Fingerprint DOES NOT MATCH!"
            error "Expected: $EXPECTED_FINGERPRINT"
            error "Current:  $CURRENT_FINGERPRINT"
            warn "Your bridge identity has been lost. You need to restore from backup!"
            exit 1
        fi
    else
        log "No expected fingerprint provided (use: ./validate-bridge-migration.sh YOUR_FINGERPRINT)"
    fi

    log "Tor Metrics: https://metrics.torproject.org/rs.html#search/${CURRENT_FINGERPRINT}"
fi

echo ""

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Test 8: Health check
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

log "Test 8: Running health check..."

HEALTH=$(docker exec "${CONTAINER_NAME}" health 2>/dev/null || echo "{}")

if echo "$HEALTH" | jq -e '.status' >/dev/null 2>&1; then
    STATUS=$(echo "$HEALTH" | jq -r '.status')
    BOOTSTRAP=$(echo "$HEALTH" | jq -r '.bootstrap // "unknown"')
    MODE=$(echo "$HEALTH" | jq -r '.relay_mode // "unknown"')

    success "Health check passed"
    log "  Status:    $STATUS"
    log "  Bootstrap: $BOOTSTRAP"
    log "  Mode:      $MODE"

    if [ "$MODE" != "bridge" ]; then
        warn "Relay mode is '$MODE' (expected 'bridge')"
    fi
else
    warn "Health check not ready yet (container may still be initializing)"
fi

echo ""

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Test 9: obfs4 configuration
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

log "Test 9: Verifying obfs4 configuration..."

TORRC=$(docker exec "${CONTAINER_NAME}" cat /etc/tor/torrc 2>/dev/null)

if echo "$TORRC" | grep -q "ServerTransportPlugin obfs4"; then
    success "obfs4 transport configured"
else
    error "obfs4 transport NOT configured!"
    exit 1
fi

if echo "$TORRC" | grep -q "ServerTransportListenAddr"; then
    OBFS4_PORT=$(echo "$TORRC" | grep "ServerTransportListenAddr" | awk '{print $4}' | cut -d: -f2)
    success "obfs4 listening on port: $OBFS4_PORT"
else
    warn "Could not determine obfs4 port"
fi

if echo "$TORRC" | grep -q "BridgeRelay 1"; then
    success "BridgeRelay enabled"
else
    error "BridgeRelay NOT enabled!"
    exit 1
fi

echo ""

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Test 10: OBFS4V_* variables processed
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

log "Test 10: Checking OBFS4V_* variable processing..."

if echo "$TORRC" | grep -q "AddressDisableIPv6"; then
    success "OBFS4V_AddressDisableIPv6 processed"
else
    warn "OBFS4V_AddressDisableIPv6 not found (check if OBFS4_ENABLE_ADDITIONAL_VARIABLES=1)"
fi

if echo "$TORRC" | grep -q "MaxMemInQueues"; then
    success "OBFS4V_MaxMemInQueues processed"
else
    warn "OBFS4V_MaxMemInQueues not found"
fi

echo ""

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Test 11: No errors in logs
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

log "Test 11: Checking for errors in logs..."

ERROR_COUNT=$(echo "$LOGS" | grep -i "error" | grep -v "no errors" | wc -l)
WARN_COUNT=$(echo "$LOGS" | grep -i "\[warn\]" | wc -l)

if [ "$ERROR_COUNT" -eq 0 ]; then
    success "No errors found in logs"
else
    warn "Found $ERROR_COUNT error(s) in logs:"
    echo "$LOGS" | grep -i "error" | grep -v "no errors" | tail -5 | sed 's/^/   /'
fi

if [ "$WARN_COUNT" -eq 0 ]; then
    success "No warnings found in logs"
else
    log "Found $WARN_COUNT warning(s) in logs (this may be normal)"
fi

echo ""

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Summary
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
success "Migration validation complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ -n "$CURRENT_FINGERPRINT" ] && [ -n "$EXPECTED_FINGERPRINT" ] && [ "$CURRENT_FINGERPRINT" = "$EXPECTED_FINGERPRINT" ]; then
    success "🎉 Bridge identity PRESERVED! Migration successful!"
    echo ""
    log "Next steps:"
    echo "  1. Wait 10-30 minutes for full bootstrap"
    echo "  2. Get bridge line: docker exec ${CONTAINER_NAME} bridge-line"
    echo "  3. Monitor Tor Metrics: https://metrics.torproject.org/rs.html#search/${CURRENT_FINGERPRINT}"
    echo "  4. Share your bridge line with users who need it"
else
    log "Next steps:"
    echo "  1. Wait for bootstrap to complete (check logs)"
    echo "  2. Verify fingerprint: docker exec ${CONTAINER_NAME} fingerprint"
    if [ -n "$EXPECTED_FINGERPRINT" ]; then
        echo "  3. Expected fingerprint: $EXPECTED_FINGERPRINT"
    fi
    echo "  4. Get bridge line: docker exec ${CONTAINER_NAME} bridge-line"
    echo "  5. Monitor health: docker exec ${CONTAINER_NAME} health | jq ."
fi

echo ""