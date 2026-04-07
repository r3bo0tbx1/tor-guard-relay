#!/bin/sh
# docker-entrypoint.sh - Tor Guard Relay initialization and process management
set -e

[ -n "${NICKNAME:-}" ] && TOR_NICKNAME="$NICKNAME"
[ -n "${EMAIL:-}" ] && TOR_CONTACT_INFO="$EMAIL"
[ -n "${OR_PORT:-}" ] && TOR_ORPORT="$OR_PORT"
[ -n "${PT_PORT:-}" ] && TOR_OBFS4_PORT="$PT_PORT"

if [ -n "${PT_PORT:-}" ] && [ "${TOR_RELAY_MODE:-guard}" = "guard" ]; then
  TOR_RELAY_MODE="bridge"
fi

readonly TOR_CONFIG="${TOR_CONFIG:-/etc/tor/torrc}"
readonly TOR_DATA_DIR="${TOR_DATA_DIR:-/var/lib/tor}"
readonly TOR_LOG_DIR="${TOR_LOG_DIR:-/var/log/tor}"
readonly TOR_RELAY_MODE="${TOR_RELAY_MODE:-guard}"

TOR_PID=""
TAIL_PID=""

log() { printf "%s\n" "$1"; }
info() { printf "   ℹ️  %s\n" "$1"; }
success() { printf "✅ %s\n" "$1"; }
warn() { printf "🛑 %s\n" "$1"; }
die() { printf "🛑 ERROR: %s\n" "$1"; exit 1; }

trap 'cleanup_and_exit' TERM INT

cleanup_and_exit() {
  log ""
  warn "Shutdown signal received. Stopping Tor relay..."

  if [ -n "$TAIL_PID" ] && kill -0 "$TAIL_PID" 2>/dev/null; then
    kill -TERM "$TAIL_PID" 2>/dev/null || true
  fi

  if [ -n "$TOR_PID" ] && kill -0 "$TOR_PID" 2>/dev/null; then
    log "   Sending SIGTERM to Tor (PID: $TOR_PID)..."
    kill -TERM "$TOR_PID" 2>/dev/null || true
    wait "$TOR_PID" 2>/dev/null || true
  fi

  success "Tor relay stopped cleanly."
  log ""
  log "   Relay stopped at $(date -u '+%Y-%m-%d %H:%M:%S') UTC"
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  exit 0
}

startup_banner() {
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log "🧅 Tor Guard Relay v1.1.8 - Initialization"
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

  # Check for Happy Family key files
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

validate_relay_config() {
  if [ -n "${TOR_RELAY_MODE:-}" ]; then
    case "$TOR_RELAY_MODE" in
      guard|middle|exit|bridge)
        :
        ;;
      *)
        die "TOR_RELAY_MODE must be: guard, middle, exit, or bridge (got: $TOR_RELAY_MODE)"
        ;;
    esac
  fi

  if [ -n "${TOR_NICKNAME:-}" ]; then
    nickname_len=$(printf "%s" "$TOR_NICKNAME" | wc -c)
    if [ "$nickname_len" -lt 1 ] || [ "$nickname_len" -gt 19 ]; then
      die "TOR_NICKNAME must be 1-19 characters (got: $nickname_len)"
    fi
    if ! printf "%s" "$TOR_NICKNAME" | grep -qE '^[a-zA-Z0-9]+$'; then
      die "TOR_NICKNAME must contain only alphanumeric characters"
    fi
    case "$(printf "%s" "$TOR_NICKNAME" | tr '[:upper:]' '[:lower:]')" in
      unnamed|noname|default|tor|relay|bridge|exit)
        die "TOR_NICKNAME cannot use reserved name: $TOR_NICKNAME"
        ;;
    esac
  fi

  if [ -n "${TOR_CONTACT_INFO:-}" ]; then
    TOR_CONTACT_INFO="$(printf "%s" "$TOR_CONTACT_INFO" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

    contact_len=$(printf "%s" "$TOR_CONTACT_INFO" | wc -c)
    if [ "$contact_len" -lt 3 ]; then
      die "TOR_CONTACT_INFO must be at least 3 characters"
    fi
    line_count=$(printf "%s" "$TOR_CONTACT_INFO" | wc -l)
    if [ "$line_count" -gt 0 ]; then
      die "TOR_CONTACT_INFO cannot contain newlines (got $line_count lines)"
    fi
  fi

  for port_var in TOR_ORPORT TOR_DIRPORT TOR_OBFS4_PORT; do
    eval "port_val=\${$port_var:-}"
    if [ -n "$port_val" ]; then
      if ! printf "%s" "$port_val" | grep -qE '^[0-9]+$'; then
        die "$port_var must be a valid port number (got: $port_val)"
      fi
      if [ "$port_var" = "TOR_DIRPORT" ] && [ "$port_val" -eq 0 ]; then
        :
      elif [ "$port_val" -lt 1 ] || [ "$port_val" -gt 65535 ]; then
        die "$port_var must be between 1-65535 (got: $port_val)"
      fi
      if [ "$port_val" -lt 1024 ] && [ "$port_val" -ne 0 ]; then
        warn "$port_var using privileged port $port_val (may require CAP_NET_BIND_SERVICE)"
      fi
    fi
  done

  for bw_var in TOR_BANDWIDTH_RATE TOR_BANDWIDTH_BURST; do
    eval "bw_val=\${$bw_var:-}"
    if [ -n "$bw_val" ]; then
      if ! printf "%s" "$bw_val" | grep -qE '^[0-9]+ ?(Bytes?|KBytes?|MBytes?|GBytes?|TBytes?|KB?|MB?|GB?|TB?)$'; then
        die "$bw_var has invalid format (got: $bw_val, expected: '10 MB' or '1 GB')"
      fi
    fi
  done

  if [ -n "${TOR_FAMILY_ID:-}" ]; then
    family_id_len=$(printf "%s" "$TOR_FAMILY_ID" | wc -c)
    if [ "$family_id_len" -ne 52 ]; then
      die "TOR_FAMILY_ID must be exactly 52 characters (got: $family_id_len)"
    fi
    if ! printf "%s" "$TOR_FAMILY_ID" | grep -qE '^[A-Z2-7]{52}$'; then
      die "TOR_FAMILY_ID must be base32-encoded (uppercase A-Z and digits 2-7 only)"
    fi
  fi
}

phase_3_configuration() {
  log "🔧 Phase 3: Configuration Setup"

  if [ -f "$TOR_CONFIG" ] && [ -s "$TOR_CONFIG" ]; then
    success "Using mounted configuration: $TOR_CONFIG"
    CONFIG_SOURCE="mounted"
  elif [ -n "${TOR_NICKNAME:-}" ] && [ -n "${TOR_CONTACT_INFO:-}" ]; then
    log "   Generating configuration from environment variables..."
    validate_relay_config
    generate_config_from_env
    CONFIG_SOURCE="environment"
    success "Configuration generated from ENV vars"
  else
    die "No configuration found. Mount a torrc file or provide TOR_NICKNAME and TOR_CONTACT_INFO environment variables."
  fi

  log ""
}

generate_config_from_env() {
  cat > "$TOR_CONFIG" << EOF
# Generated Tor configuration for ${TOR_RELAY_MODE} relay
# Generated at: $(date -u '+%Y-%m-%d %H:%M:%S') UTC

# Basic relay information
Nickname ${TOR_NICKNAME}
ContactInfo ${TOR_CONTACT_INFO}

# Network configuration
ORPort ${TOR_ORPORT:-9001}
SocksPort 0

# Data directories
DataDirectory ${TOR_DATA_DIR}

# Logging (file + stdout for container logs)
Log notice file ${TOR_LOG_DIR}/notices.log
Log notice stdout

EOF

  case "$TOR_RELAY_MODE" in
    guard|middle)
      cat >> "$TOR_CONFIG" << EOF
# Guard/Middle relay configuration
DirPort ${TOR_DIRPORT:-9030}
ExitRelay 0
BridgeRelay 0

# Bandwidth (optional)
EOF
      [ -n "${TOR_BANDWIDTH_RATE:-}" ] && echo "RelayBandwidthRate ${TOR_BANDWIDTH_RATE}" >> "$TOR_CONFIG"
      [ -n "${TOR_BANDWIDTH_BURST:-}" ] && echo "RelayBandwidthBurst ${TOR_BANDWIDTH_BURST}" >> "$TOR_CONFIG"

      # Happy Family (Tor 0.4.9+)
      [ -n "${TOR_FAMILY_ID:-}" ] && echo "" >> "$TOR_CONFIG" && echo "# Happy Family (Tor 0.4.9+)" >> "$TOR_CONFIG" && echo "FamilyId ${TOR_FAMILY_ID}" >> "$TOR_CONFIG"

      # MyFamily (legacy, keep during transition)
      if [ -n "${TOR_MY_FAMILY:-}" ]; then
        echo "" >> "$TOR_CONFIG"
        echo "# MyFamily (legacy - keep during transition to Happy Family)" >> "$TOR_CONFIG"
        echo "$TOR_MY_FAMILY" | tr ',' '\n' | while IFS= read -r fp; do
          fp=$(printf "%s" "$fp" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
          [ -n "$fp" ] && echo "MyFamily $fp" >> "$TOR_CONFIG"
        done
      fi
      ;;

    exit)
      cat >> "$TOR_CONFIG" << EOF
# Exit relay configuration
DirPort ${TOR_DIRPORT:-9030}
ExitRelay 1
BridgeRelay 0

# Exit policy (default: reduced exit)
ExitPolicy ${TOR_EXIT_POLICY:-reject *:*}

# Bandwidth (optional)
EOF
      [ -n "${TOR_BANDWIDTH_RATE:-}" ] && echo "RelayBandwidthRate ${TOR_BANDWIDTH_RATE}" >> "$TOR_CONFIG"
      [ -n "${TOR_BANDWIDTH_BURST:-}" ] && echo "RelayBandwidthBurst ${TOR_BANDWIDTH_BURST}" >> "$TOR_CONFIG"

      # Happy Family (Tor 0.4.9+)
      [ -n "${TOR_FAMILY_ID:-}" ] && echo "" >> "$TOR_CONFIG" && echo "# Happy Family (Tor 0.4.9+)" >> "$TOR_CONFIG" && echo "FamilyId ${TOR_FAMILY_ID}" >> "$TOR_CONFIG"

      # MyFamily (legacy, keep during transition)
      if [ -n "${TOR_MY_FAMILY:-}" ]; then
        echo "" >> "$TOR_CONFIG"
        echo "# MyFamily (legacy - keep during transition to Happy Family)" >> "$TOR_CONFIG"
        echo "$TOR_MY_FAMILY" | tr ',' '\n' | while IFS= read -r fp; do
          fp=$(printf "%s" "$fp" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
          [ -n "$fp" ] && echo "MyFamily $fp" >> "$TOR_CONFIG"
        done
      fi
      ;;

    bridge)
      cat >> "$TOR_CONFIG" << EOF
# Bridge relay configuration
BridgeRelay 1
PublishServerDescriptor bridge

# obfs4 pluggable transport
ServerTransportPlugin obfs4 exec /usr/bin/lyrebird
ServerTransportListenAddr obfs4 0.0.0.0:${TOR_OBFS4_PORT:-9002}
ExtORPort auto

# Bandwidth (optional)
EOF
      [ -n "${TOR_BANDWIDTH_RATE:-}" ] && echo "RelayBandwidthRate ${TOR_BANDWIDTH_RATE}" >> "$TOR_CONFIG"
      [ -n "${TOR_BANDWIDTH_BURST:-}" ] && echo "RelayBandwidthBurst ${TOR_BANDWIDTH_BURST}" >> "$TOR_CONFIG"

      if [ "${OBFS4_ENABLE_ADDITIONAL_VARIABLES:-0}" = "1" ]; then
        echo "" >> "$TOR_CONFIG"
        echo "# Additional torrc options from OBFS4V_* environment variables" >> "$TOR_CONFIG"

        env | grep '^OBFS4V_' | sort | while IFS='=' read -r key value; do
          torrc_key="${key#OBFS4V_}"
          if ! printf "%s" "$torrc_key" | grep -qE '^[a-zA-Z][a-zA-Z0-9_]*$'; then
            warn "Skipping invalid OBFS4V variable name: $key (must be alphanumeric)"
            continue
          fi
          line_count=$(printf "%s" "$value" | wc -l)
          if [ "$line_count" -gt 0 ]; then
            warn "Skipping $key: value contains newlines ($line_count lines)"
            continue
          fi
          if printf "%s" "$value" | tr -d '[ -~]' | grep -q .; then
            warn "Skipping $key: value contains control characters"
            continue
          fi
          case "$torrc_key" in
            AccountingMax|AccountingStart|Address|AddressDisableIPv6|\
            BandwidthBurst|BandwidthRate|RelayBandwidthBurst|RelayBandwidthRate|\
            ContactInfo|DirPort|MaxMemInQueues|NumCPUs|ORPort|\
            OutboundBindAddress|OutboundBindAddressOR|Nickname|\
            ServerDNSAllowBrokenConfig|ServerDNSDetectHijacking)
              printf "%s %s\n" "$torrc_key" "$value" >> "$TOR_CONFIG"
              ;;
            *)
              warn "Skipping $key: torrc option '$torrc_key' not in whitelist"
              warn "  If you need this option, mount a custom torrc file instead"
              ;;
          esac
        done
      fi
      ;;

    *)
      die "Invalid TOR_RELAY_MODE: $TOR_RELAY_MODE (must be: guard, exit, or bridge)"
      ;;
  esac
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
  log "   • docker exec <container> fingerprint   - Relay fingerprint"
  [ "$TOR_RELAY_MODE" = "bridge" ] && log "   • docker exec <container> bridge-line   - obfs4 bridge line"
  log ""
}

launch_tor() {
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  success "Starting Tor relay..."
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log ""

  tor -f "$TOR_CONFIG" &
  TOR_PID=$!

  log "🚀 Tor relay started (PID: $TOR_PID)"
  log ""
  log "📋 Tor bootstrap logs:"
  log ""

  log_wait=0
  while [ ! -f "$TOR_LOG_DIR/notices.log" ] && [ $log_wait -lt 50 ]; do
    sleep 0.1
    log_wait=$((log_wait + 1))
  done

  if [ -f "$TOR_LOG_DIR/notices.log" ]; then
    tail -F "$TOR_LOG_DIR/notices.log" 2>/dev/null &
    TAIL_PID=$!
  else
    warn "Log file not created yet, bootstrap messages will not be shown"
  fi

  wait "$TOR_PID"
  TOR_EXIT_CODE=$?

  if [ -n "$TAIL_PID" ] && kill -0 "$TAIL_PID" 2>/dev/null; then
    kill -TERM "$TAIL_PID" 2>/dev/null || true
  fi

  log ""
  warn "Tor process exited with code: $TOR_EXIT_CODE"
  cleanup_and_exit
}

main() {
  startup_banner
  phase_1_directories
  phase_2_permissions
  phase_3_configuration
  phase_4_validation
  phase_5_build_info
  phase_6_diagnostics
  launch_tor
}

main "$@"