#!/bin/sh
# docker-entrypoint.sh - Tor Guard Relay initialization and process management
set -e
. "${RELAY_LIB:-/usr/local/lib/relay}/runtime.sh"
. "${RELAY_LIB:-/usr/local/lib/relay}/config.sh"

[ -n "${NICKNAME:-}" ] && TOR_NICKNAME="$NICKNAME"
[ -n "${EMAIL:-}" ] && TOR_CONTACT_INFO="$EMAIL"
[ -n "${OR_PORT:-}" ] && TOR_ORPORT="$OR_PORT"
[ -n "${PT_PORT:-}" ] && TOR_OBFS4_PORT="$PT_PORT"

if [ -n "${PT_PORT:-}" ] && [ "${TOR_RELAY_MODE:-guard}" = "guard" ]; then
  TOR_RELAY_MODE="bridge"
fi

TOR_CONFIG="${TOR_CONFIG:-/etc/tor/torrc}"
readonly TOR_DATA_DIR="${TOR_DATA_DIR:-/var/lib/tor}"
readonly TOR_LOG_DIR="${TOR_LOG_DIR:-/var/log/tor}"
readonly TOR_RELAY_MODE="${TOR_RELAY_MODE:-guard}"

export TOR_ORPORT TOR_OBFS4_PORT
TOR_PID=""
TAIL_PID=""

if ! { [ "$#" -eq 3 ] && [ "$1" = tor ] && [ "$2" = -f ] && [ "$3" = /etc/tor/torrc ]; }; then
  next_config=0
  for argument in "$@"; do
    if [ "$next_config" -eq 1 ]; then TOR_CONFIG=$argument; next_config=0; fi
    case "$argument" in -f|--torrc-file) next_config=1 ;; esac
  done
fi

if [ "$#" -gt 0 ] && [ "$1" != "tor" ]; then
  exec "$@"
fi

log() { printf "%s\n" "$1"; }
info() { printf "   ℹ️  %s\n" "$1"; }
success() { printf "✅ %s\n" "$1"; }
warn() { printf "🛑 %s\n" "$1"; }
die() { printf "🛑 ERROR: %s\n" "$1"; exit 1; }

trap 'cleanup_and_exit' TERM INT

cleanup_and_exit() {
  trap '' TERM INT
  shutdown_code=0
  [ -z "$TAIL_PID" ] || kill -TERM "$TAIL_PID" 2>/dev/null || true
  if [ -n "$TOR_PID" ] && kill -0 "$TOR_PID" 2>/dev/null; then
    kill -TERM "$TOR_PID" 2>/dev/null || true
    limit=${TOR_SHUTDOWN_TIMEOUT:-30}
    case "$limit" in ''|*[!0-9]*) limit=30 ;; esac
    elapsed=0
    while kill -0 "$TOR_PID" 2>/dev/null && [ "$elapsed" -lt "$limit" ]; do
      state=$(awk '{print $3}' "/proc/$TOR_PID/stat" 2>/dev/null || true)
      [ "$state" != Z ] || break
      sleep 1; elapsed=$((elapsed + 1))
    done
    if kill -0 "$TOR_PID" 2>/dev/null && [ "$elapsed" -ge "$limit" ]; then
      kill -KILL "$TOR_PID" 2>/dev/null || true
      shutdown_code=137
      warn "Tor exceeded shutdown timeout"
    fi
    wait "$TOR_PID" 2>/dev/null || true
  fi
  exit "$shutdown_code"
}

startup_banner() {
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log "🧅 Tor Guard Relay v2.2.0 - Initialization"
  log "https://github.com/r3bo0tbx1/tor-guard-relay"
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log ""
}

phase_1_directories() {
  log "🗂️  Phase 1: Directory Structure"
  mkdir -p "$TOR_DATA_DIR" "$TOR_LOG_DIR" /run/tor /tmp

  log "   Created directories:"
  log "   • Data:  $TOR_DATA_DIR"
  log "   • Logs:  $TOR_LOG_DIR"
  log "   • Run:   /run/tor"

  if command -v df >/dev/null 2>&1; then
    available=$(df -h "$TOR_DATA_DIR" 2>/dev/null | tail -n 1 | awk '{print $4}' || echo "unknown")
    log "   💽 Available disk space: $available"
  fi
  log ""
}

phase_2_permissions() {
  log "🔐 Phase 2: Permission Hardening"

  chmod 700 "$TOR_DATA_DIR" 2>/dev/null || warn "Failed to set data directory permissions (may be read-only mount)"
  chmod 755 "$TOR_LOG_DIR" 2>/dev/null || warn "Failed to set log directory permissions (may be read-only mount)"

  CURRENT_UID=$(id -u)
  CURRENT_GID=$(id -g)

  if [ ! -w "$TOR_DATA_DIR" ]; then
    warn "Data directory $TOR_DATA_DIR is not writable by tor user (UID $CURRENT_UID)"
    warn "If using host bind mounts, fix ownership on the host:"
    warn "  chown -R $CURRENT_UID:$CURRENT_GID <host-path>"
  fi

  if [ -d "$TOR_DATA_DIR/keys" ] && [ ! -w "$TOR_DATA_DIR/keys" ]; then
    warn "Keys directory $TOR_DATA_DIR/keys has wrong ownership!"
    KEYS_OWNER=$(stat -c '%u:%g' "$TOR_DATA_DIR/keys" 2>/dev/null || echo "unknown")
    warn "  Current owner: $KEYS_OWNER - Expected: $CURRENT_UID:$CURRENT_GID"
    warn "  Fix on the host: chown -R $CURRENT_UID:$CURRENT_GID <host-keys-path>"
  fi

  FAMILY_KEY_COUNT=0
  if [ -d "$TOR_DATA_DIR/keys" ]; then
    for fk in "$TOR_DATA_DIR/keys"/*.secret_family_key; do
      [ -f "$fk" ] || continue
      FAMILY_KEY_COUNT=$((FAMILY_KEY_COUNT + 1))
      FK_NAME=$(basename "$fk" .secret_family_key)
      info "Found Happy Family key: $FK_NAME"
    done
  fi
  if [ "$FAMILY_KEY_COUNT" -gt 0 ]; then
    success "$FAMILY_KEY_COUNT family key(s) detected in keys directory"
  fi

  success "Permissions configured securely"
  log ""
}

phase_3_configuration() {
  case "${TOR_CONFIG_SOURCE:-auto}" in
    mounted) [ -s "$TOR_CONFIG" ] || die "Mounted configuration missing"; CONFIG_SOURCE=mounted ;;
    environment) CONFIG_SOURCE=environment ;;
    auto)
      config_source
      if config_is_mounted; then
        CONFIG_SOURCE=mounted
      fi
      if [ "$CONFIG_SOURCE" = unknown ]; then CONFIG_SOURCE=environment; fi
      ;;
    *) die "TOR_CONFIG_SOURCE must be auto, mounted or environment" ;;
  esac
  if [ "$CONFIG_SOURCE" = environment ]; then
    [ -n "${TOR_NICKNAME:-}" ] && [ -n "${TOR_CONTACT_INFO:-}" ] || die "Provide TOR_NICKNAME and TOR_CONTACT_INFO"
    publish_env_config "$TOR_CONFIG"
  fi
  success "Configuration: $CONFIG_SOURCE ($TOR_CONFIG)"
}

phase_4_validation() {
  log "🔎 Phase 4: Configuration Validation"

  if ! command -v tor >/dev/null 2>&1; then
    die "Tor binary not found in PATH"
  fi

  TOR_VERSION=$(tor --version 2>/dev/null | head -n1 || echo "unknown")
  log "   📦 Tor version: $TOR_VERSION"

  log "   Validating torrc syntax..."

  VERIFY_TMP=""
  cleanup_verify_tmp() {
    [ -n "$VERIFY_TMP" ] && rm -f "$VERIFY_TMP"
  }
  trap cleanup_verify_tmp EXIT

  VERIFY_TMP=$(mktemp /tmp/tor-verify.XXXXXX)

  if ! tor --verify-config -f "$TOR_CONFIG" >"$VERIFY_TMP" 2>&1; then
    warn "Configuration validation failed!"
    DEBUG_LOWER=$(printf "%s" "${DEBUG:-false}" | tr '[:upper:]' '[:lower:]')
    if [ "$DEBUG_LOWER" = "true" ] || [ "$DEBUG_LOWER" = "1" ] || [ "$DEBUG_LOWER" = "yes" ]; then
      log "   Error output:"
      head -n 10 "$VERIFY_TMP" | sed 's/^/   /'
    fi
    cleanup_verify_tmp
    die "Invalid Tor configuration. Set DEBUG=true for details."
  fi

  cleanup_verify_tmp
  success "Configuration is valid"
  log ""
}

phase_5_build_info() {
  log "📊 Phase 5: Build Information"

  if [ -f /build-info.txt ]; then
    log "   Build metadata:"
    cat /build-info.txt | sed 's/^/   /'
  else
    warn "No build-info.txt found"
  fi

  log ""
  log "   🌐 Relay mode: $TOR_RELAY_MODE"
  log "   🔧 Config source: $CONFIG_SOURCE"
  log ""
}

phase_6_diagnostics() {
  log "🧩 Phase 6: Available Diagnostic Tools"
  log ""
  log "   Once Tor is running, use these commands:"
  log "   • docker exec <container> status        - Full health report"
  log "   • docker exec <container> health        - JSON health check"
  log "   • docker exec <container> refresh       - Reload Tor config"
  log "   • docker exec <container> fingerprint   - Relay fingerprint"
  [ "$TOR_RELAY_MODE" = "bridge" ] && log "   • docker exec <container> bridge-line   - obfs4 bridge line"
  log ""
}

launch_tor() {
  mkdir -p "$(dirname "$RELAY_STATE")"
  touch "$TOR_LOG_DIR/notices.log"
  offset=$(stat -c %s "$TOR_LOG_DIR/notices.log")
  inode=$(stat -c %i "$TOR_LOG_DIR/notices.log")
  if [ "$#" -eq 3 ] && [ "$1" = tor ] && [ "$2" = -f ] && [ "$3" = /etc/tor/torrc ]; then
    set -- tor -f "$TOR_CONFIG"
  fi
  if [ "$#" -eq 0 ]; then set -- tor -f "$TOR_CONFIG"; fi
  "$@" &
  TOR_PID=$!
  if ! started=$(process_start "$TOR_PID"); then
    code=0; wait "$TOR_PID" || code=$?; exit "$code"
  fi
  umask 077
  printf 'pid=%s\nstart=%s\noffset=%s\ninode=%s\nconfig=%s\n' "$TOR_PID" "$started" "$offset" "$inode" "$TOR_CONFIG" > "$RELAY_STATE"
  if ! grep -qi '^Log .*stdout' "$TOR_CONFIG"; then
    tail -c "+$((offset + 1))" -F "$TOR_LOG_DIR/notices.log" &
    TAIL_PID=$!
  fi
  code=0
  wait "$TOR_PID" || code=$?
  [ -z "$TAIL_PID" ] || kill -TERM "$TAIL_PID" 2>/dev/null || true
  exit "$code"
}

main() {
  startup_banner
  phase_1_directories
  phase_2_permissions
  phase_3_configuration
  phase_4_validation
  phase_5_build_info
  phase_6_diagnostics
  launch_tor "$@"
}

main "$@"
