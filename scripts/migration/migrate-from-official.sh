#!/bin/sh
# Migration Assistant: thetorproject/obfs4-bridge → r3bo0tbx1/onion-relay
# Automates UID fix (Debian 101 → Alpine 100) and validates migration

set -e

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Color Output (POSIX-compatible)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

log() { printf "${BLUE}ℹ${NC} %s\n" "$*"; }
success() { printf "${GREEN}✅${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}⚠${NC} %s\n" "$*"; }
error() { printf "${RED}❌${NC} %s\n" "$*"; }
step() { printf "\n${CYAN}${BOLD}━━━ %s${NC}\n" "$*"; }
die() { error "$*"; exit 1; }

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Utility Functions
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Prompt for confirmation
confirm() {
    prompt="$1"
    printf "${YELLOW}❓ %s [y/N]: ${NC}" "$prompt"
    read -r response
    case "$response" in
        [yY][eE][sS]|[yY]) return 0 ;;
        *) return 1 ;;
    esac
}

# Check if Docker is available
check_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        die "Docker is not installed or not in PATH"
    fi

    if ! docker info >/dev/null 2>&1; then
        die "Docker daemon is not running or permission denied"
    fi
}

# Sanitize numeric values
sanitize_num() {
    v=$(printf '%s' "$1" | tr -cd '0-9')
    [ -z "$v" ] && v=0
    printf '%s' "$v"
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Detection Functions
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Detect official Tor Project bridge containers
detect_official_containers() {
    docker ps -a --filter "ancestor=thetorproject/obfs4-bridge" --format "{{.Names}}" 2>/dev/null | head -1
}

# Extract environment variables from container
get_container_env() {
    container_name="$1"
    env_var="$2"
    docker inspect "$container_name" --format "{{range .Config.Env}}{{println .}}{{end}}" 2>/dev/null | \
        grep "^${env_var}=" | cut -d= -f2-
}

# Extract volume mounts from container
get_container_volumes() {
    container_name="$1"
    docker inspect "$container_name" --format '{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}}:{{.Destination}}{{println}}{{end}}{{end}}' 2>/dev/null
}

# Get fingerprint from volume
get_fingerprint_from_volume() {
    volume_name="$1"
    docker run --rm -v "${volume_name}:/data:ro" alpine:3.22.2 sh -c \
        'if [ -f /data/fingerprint ]; then cat /data/fingerprint; elif [ -f /data/keys/ed25519_master_id_public_key ]; then echo "Keys exist but fingerprint not yet generated"; else echo "NOT_FOUND"; fi' 2>/dev/null
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Validation Functions
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Check volume ownership
check_volume_ownership() {
    volume_name="$1"
    ownership=$(docker run --rm -v "${volume_name}:/data:ro" alpine:3.22.2 stat -c '%u:%g' /data 2>/dev/null)
    printf '%s' "$ownership"
}

# Wait for container to be healthy
wait_for_healthy() {
    container_name="$1"
    timeout="${2:-120}"

    log "Waiting for container to start (max ${timeout}s)..."

    counter=0
    while [ $counter -lt $timeout ]; do
        status=$(docker inspect "$container_name" --format '{{.State.Status}}' 2>/dev/null || echo "not_found")

        if [ "$status" = "running" ]; then
            success "Container is running"
            return 0
        elif [ "$status" = "exited" ] || [ "$status" = "dead" ]; then
            error "Container exited unexpectedly"
            docker logs "$container_name" 2>&1 | tail -20
            return 1
        fi

        sleep 2
        counter=$((counter + 2))
    done

    error "Timeout waiting for container to start"
    return 1
}

# Wait for Tor bootstrap
wait_for_bootstrap() {
    container_name="$1"
    timeout="${2:-300}"

    log "Waiting for Tor to bootstrap (max ${timeout}s)..."

    counter=0
    last_progress=""

    while [ $counter -lt $timeout ]; do
        # Try to get bootstrap progress from health tool
        bootstrap_output=$(docker exec "$container_name" health 2>/dev/null || echo "{}")
        bootstrap_pct=$(printf '%s' "$bootstrap_output" | grep -o '"bootstrap_percent":[0-9]*' | cut -d: -f2 | head -1)
        bootstrap_pct=$(sanitize_num "$bootstrap_pct")

        if [ "$bootstrap_pct" -ge 100 ]; then
            success "Tor fully bootstrapped (100%)"
            return 0
        elif [ "$bootstrap_pct" -gt 0 ]; then
            if [ "$bootstrap_pct" != "$last_progress" ]; then
                log "Bootstrap progress: ${bootstrap_pct}%"
                last_progress="$bootstrap_pct"
            fi
        fi

        # Check if Tor is actually running
        if ! docker exec "$container_name" pgrep -x tor >/dev/null 2>&1; then
            error "Tor process not running"
            docker logs "$container_name" 2>&1 | tail -20
            return 1
        fi

        sleep 5
        counter=$((counter + 5))
    done

    warn "Timeout waiting for bootstrap completion"
    log "Current progress: ${bootstrap_pct}%"
    return 1
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Migration Functions
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Backup volume before migration
backup_volume() {
    volume_name="$1"
    backup_dir="${2:-/tmp}"
    backup_file="${backup_dir}/tor-backup-$(date +%Y%m%d-%H%M%S).tar.gz"

    log "Creating backup of volume '${volume_name}'..."

    if ! docker run --rm -v "${volume_name}:/data:ro" -v "${backup_dir}:/backup" alpine:3.22.2 \
        tar czf "/backup/$(basename "$backup_file")" -C /data . 2>/dev/null; then
        error "Backup failed"
        return 1
    fi

    success "Backup created: ${backup_file}"
    printf '%s' "$backup_file"
    return 0
}

# Fix volume ownership (Debian UID 101 → Alpine UID 100)
fix_volume_ownership() {
    volume_name="$1"

    log "Fixing ownership: debian-tor (101) → tor (100)..."

    current_ownership=$(check_volume_ownership "$volume_name")
    log "Current ownership: ${current_ownership}"

    if ! docker run --rm -v "${volume_name}:/data" alpine:3.22.2 chown -R 100:101 /data 2>/dev/null; then
        error "Failed to fix ownership"
        return 1
    fi

    new_ownership=$(check_volume_ownership "$volume_name")
    log "New ownership: ${new_ownership}"

    if [ "$new_ownership" = "100:101" ]; then
        success "Ownership fixed successfully"
        return 0
    else
        error "Ownership verification failed (expected 100:101, got ${new_ownership})"
        return 1
    fi
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Main Migration Logic
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

show_banner() {
    printf "\n"
    printf "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "${BOLD}${CYAN}    Migration Assistant: Official Tor Bridge → Onion Relay${NC}\n"
    printf "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "\n"
    printf "This script automates migration from:\n"
    printf "  ${BOLD}Source:${NC} thetorproject/obfs4-bridge (Debian, UID 101)\n"
    printf "  ${BOLD}Target:${NC} ghcr.io/r3bo0tbx1/onion-relay (Alpine, UID 100)\n"
    printf "\n"
}

main() {
    show_banner

    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # Step 1: Pre-flight Checks
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    step "Step 1: Pre-flight Checks"

    check_docker
    success "Docker is available"

    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # Step 2: Detect Existing Setup
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    step "Step 2: Detect Existing Setup"

    OLD_CONTAINER=$(detect_official_containers)

    if [ -z "$OLD_CONTAINER" ]; then
        warn "No thetorproject/obfs4-bridge container found"
        log "This script is designed to migrate from the official bridge image"
        log "If you're setting up a new relay, use scripts/quick-start.sh instead"

        if ! confirm "Continue with manual configuration?"; then
            log "Migration cancelled"
            exit 0
        fi

        # Manual mode
        printf "\n${BOLD}Manual Configuration Mode${NC}\n"
        printf "Enter the volume name containing your Tor data: "
        read -r DATA_VOLUME

        if [ -z "$DATA_VOLUME" ]; then
            die "Volume name is required"
        fi

        if ! docker volume inspect "$DATA_VOLUME" >/dev/null 2>&1; then
            die "Volume '${DATA_VOLUME}' does not exist"
        fi

        printf "Enter the new container name (default: tor-bridge): "
        read -r NEW_CONTAINER
        NEW_CONTAINER="${NEW_CONTAINER:-tor-bridge}"

        printf "Enter OR_PORT (default: 9001): "
        read -r OR_PORT
        OR_PORT="${OR_PORT:-9001}"

        printf "Enter PT_PORT (default: 9002): "
        read -r PT_PORT
        PT_PORT="${PT_PORT:-9002}"

        printf "Enter NICKNAME: "
        read -r NICKNAME

        printf "Enter EMAIL: "
        read -r EMAIL

        if [ -z "$NICKNAME" ] || [ -z "$EMAIL" ]; then
            die "NICKNAME and EMAIL are required"
        fi

        OLD_CONTAINER=""

    else
        success "Found container: ${OLD_CONTAINER}"

        # Extract configuration
        NICKNAME=$(get_container_env "$OLD_CONTAINER" "NICKNAME")
        EMAIL=$(get_container_env "$OLD_CONTAINER" "EMAIL")
        OR_PORT=$(get_container_env "$OLD_CONTAINER" "OR_PORT")
        PT_PORT=$(get_container_env "$OLD_CONTAINER" "PT_PORT")

        log "Configuration detected:"
        log "  Nickname: ${NICKNAME:-not set}"
        log "  Email: ${EMAIL:-not set}"
        log "  OR Port: ${OR_PORT:-9001}"
        log "  PT Port: ${PT_PORT:-9002}"

        # Get volumes
        VOLUMES=$(get_container_volumes "$OLD_CONTAINER")
        DATA_VOLUME=""

        if [ -n "$VOLUMES" ]; then
            log "Volume mounts:"
            printf '%s\n' "$VOLUMES" | while IFS=: read -r vol_name vol_path; do
                log "  ${vol_name} → ${vol_path}"
                if [ "$vol_path" = "/var/lib/tor" ]; then
                    DATA_VOLUME="$vol_name"
                fi
            done

            # Extract first volume for data if specific mount not found
            if [ -z "$DATA_VOLUME" ]; then
                DATA_VOLUME=$(printf '%s\n' "$VOLUMES" | head -1 | cut -d: -f1)
            fi
        fi

        if [ -z "$DATA_VOLUME" ]; then
            warn "No volume detected for /var/lib/tor"
            printf "Enter the volume name containing Tor data: "
            read -r DATA_VOLUME

            if [ -z "$DATA_VOLUME" ]; then
                die "Volume name is required"
            fi
        fi

        # Get current fingerprint
        log "Checking current fingerprint..."
        OLD_FINGERPRINT=$(get_fingerprint_from_volume "$DATA_VOLUME")

        if [ "$OLD_FINGERPRINT" = "NOT_FOUND" ]; then
            warn "No identity keys found in volume"
        elif [ "$OLD_FINGERPRINT" = "Keys exist but fingerprint not yet generated" ]; then
            log "Identity keys exist, fingerprint will be generated after migration"
        else
            success "Current fingerprint: ${OLD_FINGERPRINT}"
        fi

        # Check container status
        CONTAINER_STATUS=$(docker inspect "$OLD_CONTAINER" --format '{{.State.Status}}' 2>/dev/null || echo "not_found")
        log "Container status: ${CONTAINER_STATUS}"

        # Confirm migration
        printf "\n"
        if ! confirm "Proceed with migration?"; then
            log "Migration cancelled"
            exit 0
        fi

        # Ask for new container name
        printf "\n"
        printf "Enter new container name (default: tor-bridge): "
        read -r NEW_CONTAINER
        NEW_CONTAINER="${NEW_CONTAINER:-tor-bridge}"
    fi

    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # Step 3: Backup Current Data
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    step "Step 3: Backup Current Data"

    if confirm "Create backup of volume '${DATA_VOLUME}'?"; then
        BACKUP_DIR="${HOME}/tor-backups"
        mkdir -p "$BACKUP_DIR" 2>/dev/null || BACKUP_DIR="/tmp"

        if BACKUP_FILE=$(backup_volume "$DATA_VOLUME" "$BACKUP_DIR"); then
            log "Backup location: ${BACKUP_FILE}"
        else
            warn "Backup failed, but continuing..."
        fi
    else
        warn "Skipping backup (not recommended)"
    fi

    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # Step 4: Stop Old Container
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    if [ -n "$OLD_CONTAINER" ]; then
        step "Step 4: Stop Old Container"

        log "Stopping container: ${OLD_CONTAINER}"

        if docker stop "$OLD_CONTAINER" >/dev/null 2>&1; then
            success "Container stopped"
        else
            warn "Container may not be running"
        fi

        if confirm "Remove old container '${OLD_CONTAINER}'? (keeps volumes)"; then
            if docker rm "$OLD_CONTAINER" >/dev/null 2>&1; then
                success "Container removed"
            else
                warn "Failed to remove container"
            fi
        fi
    else
        step "Step 4: Stop Old Container (Skipped)"
        log "No old container to stop"
    fi

    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # Step 5: Fix Volume Ownership
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    step "Step 5: Fix Volume Ownership"

    CURRENT_OWNERSHIP=$(check_volume_ownership "$DATA_VOLUME")
    log "Current ownership: ${CURRENT_OWNERSHIP}"

    if [ "$CURRENT_OWNERSHIP" = "100:101" ]; then
        success "Ownership already correct (100:101)"
    else
        if ! fix_volume_ownership "$DATA_VOLUME"; then
            die "Failed to fix ownership - migration aborted"
        fi
    fi

    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # Step 6: Deploy New Container
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    step "Step 6: Deploy New Container"

    # Check if container already exists
    if docker inspect "$NEW_CONTAINER" >/dev/null 2>&1; then
        warn "Container '${NEW_CONTAINER}' already exists"
        if confirm "Remove existing container and deploy new one?"; then
            docker rm -f "$NEW_CONTAINER" >/dev/null 2>&1 || true
        else
            die "Cannot proceed with existing container"
        fi
    fi

    log "Deploying new container: ${NEW_CONTAINER}"
    log "Image: ghcr.io/r3bo0tbx1/onion-relay:latest"

    # Build docker run command
    DOCKER_RUN_CMD="docker run -d \
  --name ${NEW_CONTAINER} \
  --network host \
  --restart unless-stopped \
  --security-opt no-new-privileges:true \
  --cap-drop ALL \
  --cap-add CHOWN \
  --cap-add SETUID \
  --cap-add SETGID \
  --cap-add DAC_OVERRIDE \
  -e NICKNAME=\"${NICKNAME}\" \
  -e EMAIL=\"${EMAIL}\" \
  -e OR_PORT=\"${OR_PORT:-9001}\" \
  -e PT_PORT=\"${PT_PORT:-9002}\" \
  -v ${DATA_VOLUME}:/var/lib/tor \
  ghcr.io/r3bo0tbx1/onion-relay:latest"

    log "Running command:"
    printf '%s\n' "$DOCKER_RUN_CMD" | sed 's/^/  /'

    if eval "$DOCKER_RUN_CMD"; then
        success "Container started"
    else
        die "Failed to start container"
    fi

    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # Step 7: Wait for Container to Start
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    step "Step 7: Wait for Container to Start"

    if ! wait_for_healthy "$NEW_CONTAINER" 60; then
        error "Container failed to start properly"
        log "Check logs with: docker logs ${NEW_CONTAINER}"
        die "Migration failed at container startup"
    fi

    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # Step 8: Wait for Tor Bootstrap
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    step "Step 8: Wait for Tor Bootstrap"

    if ! wait_for_bootstrap "$NEW_CONTAINER" 300; then
        warn "Bootstrap did not complete in time"
        log "This may be normal for first startup - Tor can take 5-10 minutes"

        if ! confirm "Continue with validation anyway?"; then
            die "Migration incomplete - container is running but not bootstrapped"
        fi
    fi

    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # Step 9: Validate Migration
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    step "Step 9: Validate Migration"

    # Check fingerprint
    log "Checking fingerprint..."
    NEW_FINGERPRINT=$(docker exec "$NEW_CONTAINER" fingerprint 2>/dev/null | grep -oE '[A-F0-9]{40}' | head -1 || echo "")

    if [ -n "$NEW_FINGERPRINT" ]; then
        success "Fingerprint: ${NEW_FINGERPRINT}"

        if [ -n "$OLD_FINGERPRINT" ] && [ "$OLD_FINGERPRINT" != "NOT_FOUND" ] && [ "$OLD_FINGERPRINT" != "Keys exist but fingerprint not yet generated" ]; then
            if [ "$NEW_FINGERPRINT" = "$OLD_FINGERPRINT" ]; then
                success "Fingerprint matches (relay identity preserved)"
            else
                error "Fingerprint mismatch!"
                error "  Old: ${OLD_FINGERPRINT}"
                error "  New: ${NEW_FINGERPRINT}"
                warn "This means your relay has a NEW identity - you lost reputation!"
            fi
        fi
    else
        warn "Fingerprint not yet available (may still be generating)"
    fi

    # Check bridge line
    log "Checking bridge line..."
    BRIDGE_LINE=$(docker exec "$NEW_CONTAINER" bridge-line 2>/dev/null || echo "")

    if [ -n "$BRIDGE_LINE" ]; then
        success "Bridge line generated successfully"
        log "Bridge line:"
        printf '%s\n' "$BRIDGE_LINE" | sed 's/^/  /'
    else
        warn "Bridge line not yet available (may still be generating)"
    fi

    # Check health status
    log "Checking health status..."
    HEALTH_OUTPUT=$(docker exec "$NEW_CONTAINER" health 2>/dev/null || echo "{}")

    if printf '%s' "$HEALTH_OUTPUT" | grep -q '"status":"healthy"'; then
        success "Health check passed"
    else
        warn "Health check shows issues"
        log "Run: docker exec ${NEW_CONTAINER} status"
    fi

    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # Step 10: Migration Complete
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    step "Migration Complete!"

    printf "\n${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "${GREEN}${BOLD}✅ Migration Successful${NC}\n"
    printf "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n\n"

    printf "${BOLD}Next Steps:${NC}\n\n"

    printf "1️⃣  Check container status:\n"
    printf "   ${CYAN}docker exec ${NEW_CONTAINER} status${NC}\n\n"

    printf "2️⃣  View logs:\n"
    printf "   ${CYAN}docker logs -f ${NEW_CONTAINER}${NC}\n\n"

    printf "3️⃣  Get bridge line (after bootstrap complete):\n"
    printf "   ${CYAN}docker exec ${NEW_CONTAINER} bridge-line${NC}\n\n"

    printf "4️⃣  Check fingerprint on Tor Metrics:\n"
    if [ -n "$NEW_FINGERPRINT" ]; then
        printf "   ${CYAN}https://metrics.torproject.org/rs.html#details/${NEW_FINGERPRINT}${NC}\n\n"
    else
        printf "   ${CYAN}docker exec ${NEW_CONTAINER} fingerprint${NC}\n\n"
    fi

    printf "5️⃣  Monitor resource usage:\n"
    printf "   ${CYAN}docker stats ${NEW_CONTAINER}${NC}\n\n"

    if [ -n "$BACKUP_FILE" ]; then
        printf "${BOLD}Backup Information:${NC}\n"
        printf "  Location: ${CYAN}${BACKUP_FILE}${NC}\n"
        printf "  Keep this backup until you verify the relay is working correctly\n\n"
    fi

    printf "${BOLD}Important Notes:${NC}\n"
    printf "  • Tor may take 5-10 minutes to fully bootstrap\n"
    printf "  • Bridge should appear in Tor Metrics within 24 hours\n"
    printf "  • Monitor logs for any errors: ${CYAN}docker logs ${NEW_CONTAINER}${NC}\n"
    printf "  • If issues occur, you can restore from backup\n\n"

    if [ -n "$OLD_CONTAINER" ] && docker ps -a --format '{{.Names}}' | grep -q "^${OLD_CONTAINER}\$"; then
        printf "${YELLOW}${BOLD}Old Container:${NC}\n"
        printf "  Container '${OLD_CONTAINER}' is still present (stopped)\n"
        printf "  After confirming migration success, remove it with:\n"
        printf "  ${CYAN}docker rm ${OLD_CONTAINER}${NC}\n\n"
    fi
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Entry Point
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    show_banner
    printf "Usage: %s [OPTIONS]\n\n" "$0"
    printf "Automated migration from thetorproject/obfs4-bridge to r3bo0tbx1/onion-relay\n\n"
    printf "This script:\n"
    printf "  • Detects existing official bridge container\n"
    printf "  • Backs up current data and fingerprint\n"
    printf "  • Fixes volume ownership (Debian UID 101 → Alpine UID 100)\n"
    printf "  • Deploys new container with same configuration\n"
    printf "  • Validates fingerprint preservation\n"
    printf "  • Provides rollback instructions if needed\n\n"
    printf "Options:\n"
    printf "  -h, --help    Show this help message\n\n"
    printf "Examples:\n"
    printf "  %s                    # Interactive migration\n\n" "$0"
    exit 0
fi

main "$@"
