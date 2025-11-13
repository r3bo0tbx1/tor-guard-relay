#!/bin/sh
# docker-entrypoint.sh - Tor Guard Relay initialization and process management
# 🆕 v1.1.1 - Ultra-optimized 17.1MB build with multi-mode support

set -e

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# ENV Variable Compatibility Layer
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Supports BOTH naming conventions for maximum compatibility:
#
# 1. Our naming (TOR_* prefix):
#    - TOR_NICKNAME, TOR_CONTACT_INFO, TOR_ORPORT, TOR_OBFS4_PORT, etc.
#
# 2. Official Tor Project bridge naming (for compatibility):
#    - NICKNAME, EMAIL, OR_PORT, PT_PORT, OBFS4V_* (additional torrc options)
#
# Priority: Official names override TOR_* defaults (for drop-in compatibility)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Map official bridge ENV vars to our internal TOR_* prefix
# Official naming takes precedence over TOR_* defaults from Dockerfile
[ -n "${NICKNAME:-}" ] && TOR_NICKNAME="$NICKNAME"
[ -n "${EMAIL:-}" ] && TOR_CONTACT_INFO="$EMAIL"
[ -n "${OR_PORT:-}" ] && TOR_ORPORT="$OR_PORT"
[ -n "${PT_PORT:-}" ] && TOR_OBFS4_PORT="$PT_PORT"

# Auto-detect bridge mode if PT_PORT is set (official bridge convention)
if [ -n "${PT_PORT:-}" ] && [ "${TOR_RELAY_MODE:-guard}" = "guard" ]; then
  TOR_RELAY_MODE="bridge"
fi

# Configuration
readonly TOR_CONFIG="${TOR_CONFIG:-/etc/tor/torrc}"
readonly TOR_DATA_DIR="${TOR_DATA_DIR:-/var/lib/tor}"
readonly TOR_LOG_DIR="${TOR_LOG_DIR:-/var/log/tor}"
readonly TOR_RELAY_MODE="${TOR_RELAY_MODE:-guard}"

# Global PID tracking for cleanup
TOR_PID=""
TAIL_PID=""

# Emoji logging helpers (v1.1.0 style)
log() { printf "%s\n" "$1"; }
info() { printf "   ℹ️  %s\n" "$1"; }
success() { printf "✅ %s\n" "$1"; }
warn() { printf "🛑 %s\n" "$1"; }
die() { printf "🛑 ERROR: %s\n" "$1"; exit 1; }

# Signal handler for graceful shutdown
trap 'cleanup_and_exit' SIGTERM SIGINT

cleanup_and_exit() {
  log ""
  warn "Shutdown signal received. Stopping Tor relay..."

  # Stop log tail process first
  if [ -n "$TAIL_PID" ] && kill -0 "$TAIL_PID" 2>/dev/null; then
    kill -TERM "$TAIL_PID" 2>/dev/null || true
  fi

  # Stop Tor process
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

# Startup banner
startup_banner() {
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log "🧅 Tor Guard Relay v1.1.1 - Initialization"
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log ""
}

# Phase 1: Directory setup
phase_1_directories() {
  log "🗂️  Phase 1: Directory Structure"
  mkdir -p "$TOR_DATA_DIR" "$TOR_LOG_DIR" /run/tor /tmp

  log "   Created directories:"
  log "   • Data:  $TOR_DATA_DIR"
  log "   • Logs:  $TOR_LOG_DIR"
  log "   • Run:   /run/tor"

  # Show disk space
  if command -v df >/dev/null 2>&1; then
    available=$(df -h "$TOR_DATA_DIR" 2>/dev/null | tail -n 1 | awk '{print $4}' || echo "unknown")
    log "   💽 Available disk space: $available"
  fi
  log ""
}

# Phase 2: Permissions
phase_2_permissions() {
  log "🔐 Phase 2: Permission Hardening"

  # Note: Ownership is set at build time by Dockerfile (chown requires root)
  # Only set directory permissions (chmod doesn't require ownership)
  chmod 700 "$TOR_DATA_DIR" 2>/dev/null || warn "Failed to set data directory permissions (may be read-only mount)"
  chmod 755 "$TOR_LOG_DIR" 2>/dev/null || warn "Failed to set log directory permissions (may be read-only mount)"

  success "Permissions configured securely"
  log ""
}

# Validate relay configuration parameters
validate_relay_config() {
  # Validate relay mode
  if [ -n "${TOR_RELAY_MODE:-}" ]; then
    case "$TOR_RELAY_MODE" in
      guard|middle|exit|bridge)
        : # Valid
        ;;
      *)
        die "TOR_RELAY_MODE must be: guard, middle, exit, or bridge (got: $TOR_RELAY_MODE)"
        ;;
    esac
  fi

  # Validate nickname (1-19 alphanumeric characters)
  if [ -n "${TOR_NICKNAME:-}" ]; then
    nickname_len=$(printf "%s" "$TOR_NICKNAME" | wc -c)
    if [ "$nickname_len" -lt 1 ] || [ "$nickname_len" -gt 19 ]; then
      die "TOR_NICKNAME must be 1-19 characters (got: $nickname_len)"
    fi
    # Check for invalid characters (busybox-compatible)
    if ! printf "%s" "$TOR_NICKNAME" | grep -qE '^[a-zA-Z0-9]+$'; then
      die "TOR_NICKNAME must contain only alphanumeric characters"
    fi
    # Check for reserved names
    case "$(printf "%s" "$TOR_NICKNAME" | tr '[:upper:]' '[:lower:]')" in
      unnamed|noname|default|tor|relay|bridge|exit)
        die "TOR_NICKNAME cannot use reserved name: $TOR_NICKNAME"
        ;;
    esac
  fi

  # Validate contact info is not empty if set
  if [ -n "${TOR_CONTACT_INFO:-}" ]; then
    # Trim leading/trailing whitespace (fixes Cosmos ENV variable padding)
    TOR_CONTACT_INFO="$(printf "%s" "$TOR_CONTACT_INFO" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

    contact_len=$(printf "%s" "$TOR_CONTACT_INFO" | wc -c)
    if [ "$contact_len" -lt 3 ]; then
      die "TOR_CONTACT_INFO must be at least 3 characters"
    fi

    # Check for embedded newlines using wc -l (more reliable than grep with escape sequences)
    line_count=$(printf "%s" "$TOR_CONTACT_INFO" | wc -l)
    if [ "$line_count" -gt 0 ]; then
      die "TOR_CONTACT_INFO cannot contain newlines (got $line_count lines)"
    fi

    # Note: We don't check for null bytes as printf would truncate the string anyway
    # Email addresses are safe to use in torrc without additional escaping
  fi

  # Validate port numbers (1024-65535)
  for port_var in TOR_ORPORT TOR_DIRPORT TOR_OBFS4_PORT; do
    eval "port_val=\${$port_var:-}"
    if [ -n "$port_val" ]; then
      # Check if it's a valid integer
      if ! printf "%s" "$port_val" | grep -qE '^[0-9]+$'; then
        die "$port_var must be a valid port number (got: $port_val)"
      fi
      # Check range (allow 0 for DirPort to disable it)
      if [ "$port_var" = "TOR_DIRPORT" ] && [ "$port_val" -eq 0 ]; then
        : # Allow 0 for DirPort
      elif [ "$port_val" -lt 1 ] || [ "$port_val" -gt 65535 ]; then
        die "$port_var must be between 1-65535 (got: $port_val)"
      fi
      # Warn about privileged ports
      if [ "$port_val" -lt 1024 ] && [ "$port_val" -ne 0 ]; then
        warn "$port_var using privileged port $port_val (may require CAP_NET_BIND_SERVICE)"
      fi
    fi
  done

  # Validate bandwidth values if set
  for bw_var in TOR_BANDWIDTH_RATE TOR_BANDWIDTH_BURST; do
    eval "bw_val=\${$bw_var:-}"
    if [ -n "$bw_val" ]; then
      # Check for valid Tor bandwidth format (e.g., "10 MB", "1 GB")
      if ! printf "%s" "$bw_val" | grep -qE '^[0-9]+ ?(Bytes?|KBytes?|MBytes?|GBytes?|TBytes?|KB?|MB?|GB?|TB?)$'; then
        die "$bw_var has invalid format (got: $bw_val, expected: '10 MB' or '1 GB')"
      fi
    fi
  done
}

# Phase 3: Configuration
phase_3_configuration() {
  log "🔧 Phase 3: Configuration Setup"

  # Priority 1: Mounted config file
  if [ -f "$TOR_CONFIG" ] && [ -s "$TOR_CONFIG" ]; then
    success "Using mounted configuration: $TOR_CONFIG"
    CONFIG_SOURCE="mounted"
  # Priority 2: Environment variables
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

# Generate torrc from environment variables
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

  # Mode-specific configuration
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
      ;;

    exit)
      cat >> "$TOR_CONFIG" << EOF
# Exit relay configuration
DirPort ${TOR_DIRPORT:-9030}
ExitRelay 1
BridgeRelay 0

# Exit policy (default: reduced exit)
${TOR_EXIT_POLICY:-ExitPolicy reject *:*}

# Bandwidth (optional)
EOF
      [ -n "${TOR_BANDWIDTH_RATE:-}" ] && echo "RelayBandwidthRate ${TOR_BANDWIDTH_RATE}" >> "$TOR_CONFIG"
      [ -n "${TOR_BANDWIDTH_BURST:-}" ] && echo "RelayBandwidthBurst ${TOR_BANDWIDTH_BURST}" >> "$TOR_CONFIG"
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

      # Process OBFS4V_* additional variables (official Tor Project bridge compatibility)
      # SECURITY: Strict validation to prevent injection attacks
      if [ "${OBFS4_ENABLE_ADDITIONAL_VARIABLES:-0}" = "1" ]; then
        echo "" >> "$TOR_CONFIG"
        echo "# Additional torrc options from OBFS4V_* environment variables" >> "$TOR_CONFIG"

        # Get OBFS4V_* variables safely
        env | grep '^OBFS4V_' | sort | while IFS='=' read -r key value; do
          # Strip OBFS4V_ prefix to get torrc option name
          torrc_key="${key#OBFS4V_}"

          # SECURITY: Validate torrc_key (must be alphanumeric with underscores)
          if ! printf "%s" "$torrc_key" | grep -qE '^[a-zA-Z][a-zA-Z0-9_]*$'; then
            warn "Skipping invalid OBFS4V variable name: $key (must be alphanumeric)"
            continue
          fi

          # SECURITY: Validate value doesn't contain dangerous characters
          # Reject actual newlines (not the literal \n), nulls, and control chars
          # Use wc -l to detect real newlines (busybox-compatible)
          line_count=$(printf "%s" "$value" | wc -l)
          if [ "$line_count" -gt 0 ]; then
            warn "Skipping $key: value contains newlines ($line_count lines)"
            continue
          fi
          # Check for null bytes or other control characters (ASCII < 32, except space)
          if printf "%s" "$value" | tr -d '[ -~]' | grep -q .; then
            warn "Skipping $key: value contains control characters"
            continue
          fi

          # SECURITY: Whitelist known safe torrc options for OBFS4V_*
          # Only allow specific torrc directives that are safe for bridges
          case "$torrc_key" in
            # Safe torrc options for bridges
            AccountingMax|AccountingStart|Address|AddressDisableIPv6|\
            BandwidthBurst|BandwidthRate|RelayBandwidthBurst|RelayBandwidthRate|\
            ContactInfo|DirPort|MaxMemInQueues|NumCPUs|ORPort|\
            OutboundBindAddress|OutboundBindAddressOR|Nickname|\
            ServerDNSAllowBrokenConfig|ServerDNSDetectHijacking)
              # Safe - write to config
              # Use printf to ensure proper escaping
              printf "%s %s\n" "$torrc_key" "$value" >> "$TOR_CONFIG"
              ;;
            *)
              # Unknown/potentially dangerous option - reject
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

# Phase 4: Validation
phase_4_validation() {
  log "🔎 Phase 4: Configuration Validation"

  # Check Tor binary
  if ! command -v tor >/dev/null 2>&1; then
    die "Tor binary not found in PATH"
  fi

  TOR_VERSION=$(tor --version 2>/dev/null | head -n1 || echo "unknown")
  log "   📦 Tor version: $TOR_VERSION"

  # Validate config syntax
  log "   Validating torrc syntax..."

  # SECURITY: Set trap BEFORE creating temp file to prevent leaks
  VERIFY_TMP=""
  cleanup_verify_tmp() {
    [ -n "$VERIFY_TMP" ] && rm -f "$VERIFY_TMP"
  }
  trap cleanup_verify_tmp EXIT INT TERM

  # Create temp file in secure location
  VERIFY_TMP=$(mktemp -t tor-verify.XXXXXX)

  if ! tor --verify-config -f "$TOR_CONFIG" >"$VERIFY_TMP" 2>&1; then
    warn "Configuration validation failed!"
    if [ "${DEBUG:-false}" = "true" ]; then
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

# Phase 5: Build info
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

# Phase 6: Diagnostic tools
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

# Launch Tor
launch_tor() {
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  success "Starting Tor relay..."
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log ""

  # Start Tor in background
  tor -f "$TOR_CONFIG" &
  TOR_PID=$!

  log "🚀 Tor relay started (PID: $TOR_PID)"
  log ""
  log "📋 Tor bootstrap logs:"
  log ""

  # Wait for log file to be created (max 5 seconds)
  log_wait=0
  while [ ! -f "$TOR_LOG_DIR/notices.log" ] && [ $log_wait -lt 50 ]; do
    sleep 0.1
    log_wait=$((log_wait + 1))
  done

  # Tail Tor logs to stdout in background (if log file exists)
  if [ -f "$TOR_LOG_DIR/notices.log" ]; then
    tail -F "$TOR_LOG_DIR/notices.log" 2>/dev/null &
    TAIL_PID=$!
  else
    warn "Log file not created yet, bootstrap messages will not be shown"
  fi

  # Wait for Tor process
  wait "$TOR_PID"
  TOR_EXIT_CODE=$?

  # Stop tail process if still running
  if [ -n "$TAIL_PID" ] && kill -0 "$TAIL_PID" 2>/dev/null; then
    kill -TERM "$TAIL_PID" 2>/dev/null || true
  fi

  log ""
  warn "Tor process exited with code: $TOR_EXIT_CODE"
  cleanup_and_exit
}

# Main execution
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