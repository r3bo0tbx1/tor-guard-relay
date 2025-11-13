#!/bin/bash
# bridge-migration-fix.sh - Emergency fix for bridge container crash loop
# Diagnoses volume issues and preserves bridge identity keys

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}ℹ️  $1${NC}"; }
success() { echo -e "${GREEN}✅ $1${NC}"; }
error() { echo -e "${RED}❌ $1${NC}"; exit 1; }
warn() { echo -e "${YELLOW}⚠️  $1${NC}"; }

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔧 Bridge Migration Emergency Fix"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

CONTAINER_NAME="obfs4-bridge"
VOLUME_NAME="obfs4-data"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Step 1: Check if container exists and stop it
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

log "Step 1: Checking container status..."

if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        log "Stopping container ${CONTAINER_NAME}..."
        docker stop "${CONTAINER_NAME}" || warn "Failed to stop container gracefully"
    fi
    success "Container found"
else
    warn "Container ${CONTAINER_NAME} not found (this is OK if you haven't deployed yet)"
fi

echo ""

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Step 2: Inspect the volume
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

log "Step 2: Inspecting volume ${VOLUME_NAME}..."

if ! docker volume inspect "${VOLUME_NAME}" >/dev/null 2>&1; then
    error "Volume ${VOLUME_NAME} does not exist! This means all your bridge keys are lost."
fi

success "Volume exists"

# Get volume mountpoint
VOLUME_PATH=$(docker volume inspect "${VOLUME_NAME}" --format '{{.Mountpoint}}')
log "Volume mountpoint: ${VOLUME_PATH}"

echo ""

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Step 3: Check volume contents
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

log "Step 3: Checking volume contents..."

echo ""
log "📁 Volume contents:"
docker run --rm -v "${VOLUME_NAME}:/data" alpine ls -la /data | sed 's/^/   /'
echo ""

# Check for critical files
log "🔑 Checking for Tor identity keys..."

HAS_KEYS=false
if docker run --rm -v "${VOLUME_NAME}:/data" alpine test -d /data/keys 2>/dev/null; then
    success "keys/ directory exists"
    docker run --rm -v "${VOLUME_NAME}:/data" alpine ls -la /data/keys 2>/dev/null | sed 's/^/   /' || true

    if docker run --rm -v "${VOLUME_NAME}:/data" alpine test -f /data/keys/secret_id_key 2>/dev/null; then
        success "secret_id_key found (RSA identity)"
        HAS_KEYS=true
    fi

    if docker run --rm -v "${VOLUME_NAME}:/data" alpine test -f /data/keys/ed25519_master_id_secret_key 2>/dev/null; then
        success "ed25519_master_id_secret_key found (Ed25519 identity)"
        HAS_KEYS=true
    fi
else
    warn "keys/ directory NOT found"
fi

if [ "$HAS_KEYS" = false ]; then
    error "No Tor identity keys found! Your bridge identity is lost. You'll need to start fresh."
fi

echo ""

# Check for obfs4 state
log "🔐 Checking for obfs4 bridge state..."

if docker run --rm -v "${VOLUME_NAME}:/data" alpine test -d /data/pt_state 2>/dev/null; then
    success "pt_state/ directory exists"
    docker run --rm -v "${VOLUME_NAME}:/data" alpine ls -la /data/pt_state 2>/dev/null | sed 's/^/   /' || true

    if docker run --rm -v "${VOLUME_NAME}:/data" alpine test -f /data/pt_state/obfs4_state.json 2>/dev/null; then
        success "obfs4_state.json found (bridge credentials)"
    fi
else
    warn "pt_state/ directory NOT found (will be regenerated)"
fi

echo ""

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Step 4: Check for problematic torrc file
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

log "Step 4: Checking for incompatible torrc files..."

TORRC_FOUND=false

# Check common locations for torrc
for location in "/data/torrc" "/data/etc/tor/torrc" "/data/config/torrc"; do
    if docker run --rm -v "${VOLUME_NAME}:/data" alpine test -f "$location" 2>/dev/null; then
        warn "Found torrc at: $location"
        TORRC_FOUND=true

        echo ""
        log "Contents of $location:"
        docker run --rm -v "${VOLUME_NAME}:/data" alpine cat "$location" 2>/dev/null | head -20 | sed 's/^/   /'
        echo ""
    fi
done

if [ "$TORRC_FOUND" = false ]; then
    success "No torrc files found in volume (this is GOOD)"
fi

echo ""

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Step 5: Backup current volume state
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

log "Step 5: Creating backup of volume..."

BACKUP_FILE="bridge-backup-$(date +%Y%m%d-%H%M%S).tar.gz"

docker run --rm \
    -v "${VOLUME_NAME}:/data" \
    -v "$(pwd):/backup" \
    alpine tar czf "/backup/${BACKUP_FILE}" /data

success "Backup created: ${BACKUP_FILE}"
log "Keep this backup safe - it contains your bridge identity keys!"

echo ""

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Step 6: Remove problematic torrc files
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

if [ "$TORRC_FOUND" = true ]; then
    log "Step 6: Removing incompatible torrc files..."

    for location in "/data/torrc" "/data/etc/tor/torrc" "/data/config/torrc"; do
        if docker run --rm -v "${VOLUME_NAME}:/data" alpine test -f "$location" 2>/dev/null; then
            docker run --rm -v "${VOLUME_NAME}:/data" alpine rm -f "$location"
            success "Removed: $location"
        fi
    done

    # Also remove /data/etc directory if empty
    docker run --rm -v "${VOLUME_NAME}:/data" alpine rm -rf /data/etc 2>/dev/null || true

    success "All torrc files removed - ENV variables will be used instead"
    echo ""
else
    log "Step 6: No torrc cleanup needed"
    echo ""
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Step 7: Get current fingerprint (if keys exist)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

if [ "$HAS_KEYS" = true ]; then
    log "Step 7: Extracting current bridge fingerprint..."

    # Try to get fingerprint from cached-descriptors
    if docker run --rm -v "${VOLUME_NAME}:/data" alpine test -f /data/cached-descriptors 2>/dev/null; then
        FINGERPRINT=$(docker run --rm -v "${VOLUME_NAME}:/data" alpine grep "^fingerprint" /data/cached-descriptors 2>/dev/null | head -1 | awk '{print $2}' || echo "")

        if [ -n "$FINGERPRINT" ]; then
            success "Current fingerprint: ${FINGERPRINT}"
            log "Save this! You'll verify it matches after migration."
            log "Tor Metrics: https://metrics.torproject.org/rs.html#search/${FINGERPRINT}"
        else
            warn "Could not extract fingerprint from cached-descriptors"
        fi
    else
        warn "cached-descriptors not found (this is OK for new relays)"
    fi

    echo ""
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Summary and next steps
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
success "Diagnosis and cleanup complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ "$HAS_KEYS" = true ]; then
    success "✅ Your bridge identity keys are preserved"
else
    error "❌ Bridge identity keys NOT found - identity will be lost"
fi

if [ "$TORRC_FOUND" = true ]; then
    success "✅ Incompatible torrc files removed"
else
    success "✅ No torrc cleanup was needed"
fi

success "✅ Backup created: ${BACKUP_FILE}"

echo ""
log "Next steps:"
echo "  1. Use the corrected Cosmos JSON (will be provided)"
echo "  2. Deploy container with ENV variables (no torrc mount)"
echo "  3. Verify fingerprint matches: docker exec obfs4-bridge fingerprint"
echo "  4. Check health: docker exec obfs4-bridge health | jq ."
echo ""
log "If container still fails, run with DEBUG=true in environment to see exact error"
echo ""