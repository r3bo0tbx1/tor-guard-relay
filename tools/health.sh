#!/bin/sh
# health - Comprehensive Tor relay health check (hybrid stable version)
# Combines full structured output with simplified inline logic (Alpine-safe)

set -e

# ──────────────────────────────────────────────
# Configuration
# ──────────────────────────────────────────────
VERSION="1.1.0"
OUTPUT_FORMAT="${OUTPUT_FORMAT:-text}"
ENABLE_HEALTH_CHECK="${ENABLE_HEALTH_CHECK:-true}"
HEALTH_WEBHOOK_URL="${HEALTH_WEBHOOK_URL:-}"
CHECK_TIMEOUT="${CHECK_TIMEOUT:-5}"
VERBOSE="${VERBOSE:-false}"
LOG_LEVEL="${LOG_LEVEL:-warning}"  # error, warning, info

# ──────────────────────────────────────────────
# Utility functions
# ──────────────────────────────────────────────

# Safe execution with error handling
safe() { "$@" 2>/dev/null || true; }

# Log messages based on verbosity level
log() {
  level="$1"
  message="$2"
  
  if [ "$VERBOSE" = "true" ] || [ "$level" = "error" ]; then
    case "$level" in
      error) echo "❌ ERROR: $message" >&2 ;;
      warn)  echo "⚠️  WARNING: $message" >&2 ;;
      info)  echo "ℹ️  INFO: $message" >&2 ;;
    esac
  fi
}

# Format status with appropriate emoji
format_status() {
  case "$1" in
    ok|OK) echo "🟢 OK" ;;
    failed|closed|error|FAIL|not_available) echo "🔴 FAIL" ;;
    skipped|unknown) echo "⏭️ SKIPPED" ;;
    *) echo "$1" ;;
  esac
}

# Format IP status with address
format_ip_status() {
  type="$1"
  status="$2"
  addr="$3"

  if [ "$status" = "ok" ] && [ -n "$addr" ]; then
    echo "🟢 OK ($addr)"
  elif [ "$status" = "ok" ]; then
    echo "🟢 OK"
  elif [ "$status" = "failed" ] || [ "$status" = "not_available" ]; then
    echo "🔴 No ${type} connectivity"
  elif [ "$status" = "skipped" ]; then
    echo "⏭️ ${type} check skipped"
  else
    echo "$(format_status "$status")"
  fi
}

# Get public IP with multiple fallback methods (from status script)
get_public_ip() {
  ip_type=$1  # "ipv4" or "ipv6"
  ip=""
  
  # Try multiple services in order of preference
  if [ "$ip_type" = "ipv4" ]; then
    # Try curl with multiple services
    if command -v curl >/dev/null 2>&1; then
      ip=$(curl -4 -s --max-time 5 --connect-timeout 3 https://api.ipify.org 2>/dev/null || true)
      [ -z "$ip" ] && ip=$(curl -4 -s --max-time 5 --connect-timeout 3 https://ipinfo.io/ip 2>/dev/null || true)
      [ -z "$ip" ] && ip=$(curl -4 -s --max-time 5 --connect-timeout 3 https://ipv4.icanhazip.com 2>/dev/null || true)
    # Fallback to wget
    elif command -v wget >/dev/null 2>&1; then
      ip=$(wget -4 -q -O - --timeout=5 https://api.ipify.org 2>/dev/null || true)
      [ -z "$ip" ] && ip=$(wget -4 -q -O - --timeout=5 https://ipinfo.io/ip 2>/dev/null || true)
      [ -z "$ip" ] && ip=$(wget -4 -q -O - --timeout=5 https://ipv4.icanhazip.com 2>/dev/null || true)
    fi
    
    # Validate IPv4 format
    if printf '%s' "$ip" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
      printf '%s' "$ip"
    fi
  else  # IPv6
    # Try curl with multiple services
    if command -v curl >/dev/null 2>&1; then
      ip=$(curl -6 -s --max-time 5 --connect-timeout 3 https://api6.ipify.org 2>/dev/null || true)
      [ -z "$ip" ] && ip=$(curl -6 -s --max-time 5 --connect-timeout 3 https://ipv6.icanhazip.com 2>/dev/null || true)
    # Fallback to wget
    elif command -v wget >/dev/null 2>&1; then
      ip=$(wget -6 -q -O - --timeout=5 https://api6.ipify.org 2>/dev/null || true)
      [ -z "$ip" ] && ip=$(wget -6 -q -O - --timeout=5 https://ipv6.icanhazip.com 2>/dev/null || true)
    fi
    
    # Basic IPv6 validation (simplified)
    if printf '%s' "$ip" | grep -Eq '^[0-9a-fA-F:]+$'; then
      printf '%s' "$ip"
    fi
  fi
}

# Check if a value is numeric
is_numeric() { echo "$1" | grep -qE '^[0-9]+$'; }

# Validate IP address format
validate_ip() {
  type="$1"
  ip="$2"
  
  if [ -z "$ip" ]; then
    return 1
  fi
  
  case "$type" in
    ipv4)
      echo "$ip" | grep -qE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$'
      ;;
    ipv6)
      echo "$ip" | grep -qE '^[0-9a-fA-F:]+$'
      ;;
    *)
      return 1
      ;;
  esac
}

# Get port status
check_port_status() {
  port="$1"
  host="$2"
  
  if [ -z "$port" ] || [ "$port" = "0" ]; then
    echo "not_configured"
    return
  fi
  
  if command -v nc >/dev/null 2>&1; then
    if nc -z -w "$CHECK_TIMEOUT" "$host" "$port" 2>/dev/null; then
      echo "open"
    else
      echo "closed"
    fi
  else
    echo "skipped"
  fi
}

# ──────────────────────────────────────────────
# Argument parsing
# ──────────────────────────────────────────────
for arg in "$@"; do
  case "$arg" in
    --help|-h)
      cat << EOF
🧅 Tor-Guard-Relay Health Check v${VERSION}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
USAGE:
    health [--json|--plain|--text|--webhook|--verbose]

OPTIONS:
    --json          Output in JSON format
    --plain         Plain text output (key=value)
    --text          Formatted text output (default)
    --webhook       Send health status to webhook
    --verbose       Show detailed execution information
    --log-level     Set log level (error|warning|info)
    --help, -h      Show this help message

ENVIRONMENT VARIABLES:
    OUTPUT_FORMAT      Output format (text/json/plain)
    ENABLE_HEALTH_CHECK Enable health checks (true/false)
    HEALTH_WEBHOOK_URL Webhook URL for health notifications
    CHECK_TIMEOUT     Network check timeout in seconds (default: 5)
    VERBOSE           Show verbose output (true/false)
    LOG_LEVEL        Minimum log level (error/warning/info)

EXIT CODES:
    0    Relay is healthy or starting
    1    Relay is down or has critical issues
    2    Configuration or execution error

EXAMPLES:
    health                    # Basic health check
    health --json             # JSON output
    health --verbose           # Verbose output
    health --webhook           # Send to webhook

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
      exit 0
      ;;
    --json) OUTPUT_FORMAT="json" ;;
    --plain) OUTPUT_FORMAT="plain" ;;
    --text) OUTPUT_FORMAT="text" ;;
    --webhook) SEND_WEBHOOK="true" ;;
    --verbose) VERBOSE="true" ;;
    --log-level)
      shift
      LOG_LEVEL="$1"
      shift
      ;;
    -*) 
      echo "❌ Unknown option: $arg" >&2
      echo "💡 Use --help for usage information" >&2
      exit 2
      ;;
  esac
done

# ──────────────────────────────────────────────
# Early exit if disabled
# ──────────────────────────────────────────────
if [ "$ENABLE_HEALTH_CHECK" != "true" ]; then
  log "info" "Health checking is disabled"
  case "$OUTPUT_FORMAT" in
    json) echo '{"status":"disabled"}' ;;
    plain) echo "DISABLED" ;;
    *) echo "⏸️  Health checking disabled" ;;
  esac
  exit 0
fi

log "info" "Starting health check with format: $OUTPUT_FORMAT"

# ──────────────────────────────────────────────
# Initialize variables
# ──────────────────────────────────────────────
STATUS="unknown"
BOOTSTRAP_PERCENT=0
IS_RUNNING=false
IS_REACHABLE=false
FINGERPRINT=""
NICKNAME=""
UPTIME="0"
ERRORS=0
WARNINGS=0
VERSION_INFO=""
ORPORT=""
DIRPORT=""
RELAY_TYPE="guard"
PUBLIC_IP=""
PUBLIC_IP6=""
ORPORT_STATUS="unknown"
DIRPORT_STATUS="unknown"

# ──────────────────────────────────────────────
# Process check
# ──────────────────────────────────────────────
log "info" "Checking Tor process status"
if safe pgrep -x tor >/dev/null; then
  IS_RUNNING=true
  PID=$(safe pgrep -x tor | head -1)
  UPTIME=$(safe ps -p "$PID" -o time= | tr -d ' ')
  [ -z "$UPTIME" ] && UPTIME="0"
  log "info" "Tor process found (PID: $PID, uptime: $UPTIME)"
else
  log "error" "Tor process not found"
fi

# ──────────────────────────────────────────────
# Bootstrap progress
# ──────────────────────────────────────────────
log "info" "Checking bootstrap progress"
if [ -f /var/log/tor/notices.log ]; then
  BOOTSTRAP_LINE=$(safe grep "Bootstrapped" /var/log/tor/notices.log | tail -1)
  BOOTSTRAP_PERCENT=$(echo "$BOOTSTRAP_LINE" | grep -oE '[0-9]+%' | tr -d '%' | tail -1)
  BOOTSTRAP_PERCENT=${BOOTSTRAP_PERCENT:-0}
  log "info" "Bootstrap progress: $BOOTSTRAP_PERCENT%"
else
  log "warn" "Tor notices log not found"
fi

# ──────────────────────────────────────────────
# Reachability
# ──────────────────────────────────────────────
log "info" "Checking reachability"
if [ -f /var/log/tor/notices.log ]; then
  if safe grep -q "reachable from the outside" /var/log/tor/notices.log; then
    IS_REACHABLE=true
    log "info" "Relay is reachable from outside"
  else
    log "warn" "Relay may not be reachable from outside"
  fi
else
  log "warn" "Cannot check reachability without log file"
fi

# ──────────────────────────────────────────────
# Relay identity
# ──────────────────────────────────────────────
log "info" "Getting relay identity"
if [ -f /var/lib/tor/fingerprint ]; then
  NICKNAME=$(safe awk '{print $1}' /var/lib/tor/fingerprint)
  FINGERPRINT=$(safe awk '{print $2}' /var/lib/tor/fingerprint)
  log "info" "Relay identity: $NICKNAME ($FINGERPRINT)"
else
  log "warn" "Fingerprint file not found"
fi

# ──────────────────────────────────────────────
# Network configuration and relay type
# ──────────────────────────────────────────────
log "info" "Reading network configuration"
if [ -f /etc/tor/torrc ]; then
  ORPORT=$(safe grep -E "^ORPort" /etc/tor/torrc | awk '{print $2}' | head -1)
  DIRPORT=$(safe grep -E "^DirPort" /etc/tor/torrc | awk '{print $2}' | head -1)

  # Fixed relay type detection - check for exact matches
  if safe grep -qE "^ExitRelay\s+1" /etc/tor/torrc; then
    RELAY_TYPE="exit"
  elif safe grep -qE "^BridgeRelay\s+1" /etc/tor/torrc; then
    RELAY_TYPE="bridge"
  else
    RELAY_TYPE="guard"
  fi
  
  log "info" "Relay type: $RELAY_TYPE, ORPort: $ORPORT, DirPort: $DIRPORT"
else
  log "warn" "Tor configuration file not found"
fi

# ──────────────────────────────────────────────
# Version info
# ──────────────────────────────────────────────
log "info" "Getting version information"
if [ -f /build-info.txt ]; then
  VERSION_INFO=$(safe head -1 /build-info.txt | cut -d: -f2- | tr -d ' ')
  log "info" "Version: $VERSION_INFO"
else
  log "warn" "Build info file not found"
fi

# ──────────────────────────────────────────────
# Network IP checks (using failsafe method from status script)
# ──────────────────────────────────────────────
log "info" "Checking network connectivity"
if command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1; then
  PUBLIC_IP=$(get_public_ip "ipv4")
  PUBLIC_IP6=$(get_public_ip "ipv6")
  
  if [ -n "$PUBLIC_IP" ]; then
    log "info" "IPv4: $PUBLIC_IP"
  else
    log "warn" "Failed to get IPv4 address"
  fi
  
  if [ -n "$PUBLIC_IP6" ]; then
    log "info" "IPv6: $PUBLIC_IP6"
  else
    log "warn" "Failed to get IPv6 address"
  fi
else
  log "warn" "Neither curl nor wget available for network checks"
fi

# ──────────────────────────────────────────────
# Port status checks
# ──────────────────────────────────────────────
if [ -n "$PUBLIC_IP" ]; then
  log "info" "Checking port status"
  ORPORT_STATUS=$(check_port_status "$ORPORT" "$PUBLIC_IP")
  DIRPORT_STATUS=$(check_port_status "$DIRPORT" "$PUBLIC_IP")
  
  log "info" "ORPort status: $ORPORT_STATUS"
  log "info" "DirPort status: $DIRPORT_STATUS"
fi

# ──────────────────────────────────────────────
# Error and warning counts
# ──────────────────────────────────────────────
log "info" "Counting errors and warnings"
if [ -f /var/log/tor/notices.log ]; then
  ERRORS=$(safe grep -ciE "\[err\]" /var/log/tor/notices.log)
  WARNINGS=$(safe grep -ciE "\[warn\]" /var/log/tor/notices.log)
  log "info" "Errors: $ERRORS, Warnings: $WARNINGS"
else
  log "warn" "Cannot count errors without log file"
fi

# ──────────────────────────────────────────────
# Determine overall status
# ──────────────────────────────────────────────
log "info" "Determining overall status"
if [ "$IS_RUNNING" = false ]; then
  STATUS="down"
elif [ "$BOOTSTRAP_PERCENT" -eq 100 ] && [ "$IS_REACHABLE" = true ]; then
  STATUS="healthy"
elif [ "$BOOTSTRAP_PERCENT" -eq 100 ]; then
  STATUS="running"
elif [ "$BOOTSTRAP_PERCENT" -gt 0 ]; then
  STATUS="starting"
else
  STATUS="unknown"
fi

log "info" "Overall status: $STATUS"

TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date)

# ──────────────────────────────────────────────
# Output formatting
# ──────────────────────────────────────────────
case "$OUTPUT_FORMAT" in
  json)
    cat << EOF
{
  "status": "$STATUS",
  "timestamp": "$TIMESTAMP",
  "process": { "running": $IS_RUNNING, "uptime": "$UPTIME" },
  "bootstrap": { "percent": $BOOTSTRAP_PERCENT, "complete": $([ "$BOOTSTRAP_PERCENT" -eq 100 ] && echo "true" || echo "false") },
  "network": { 
    "reachable": $IS_REACHABLE, 
    "orport": "$ORPORT", 
    "dirport": "$DIRPORT",
    "orport_status": "$ORPORT_STATUS",
    "dirport_status": "$DIRPORT_STATUS",
    "ipv4": "$PUBLIC_IP", 
    "ipv6": "$PUBLIC_IP6" 
  },
  "relay": { 
    "nickname": "$NICKNAME", 
    "fingerprint": "$FINGERPRINT", 
    "type": "$RELAY_TYPE", 
    "version": "$VERSION_INFO" 
  },
  "issues": { "errors": $ERRORS, "warnings": $WARNINGS }
}
EOF
    ;;
  plain)
    echo "STATUS=$STATUS"
    echo "TIMESTAMP=$TIMESTAMP"
    echo "RUNNING=$IS_RUNNING"
    echo "UPTIME=$UPTIME"
    echo "BOOTSTRAP=$BOOTSTRAP_PERCENT"
    echo "REACHABLE=$IS_REACHABLE"
    echo "NICKNAME=$NICKNAME"
    echo "FINGERPRINT=$FINGERPRINT"
    echo "RELAY_TYPE=$RELAY_TYPE"
    echo "ERRORS=$ERRORS"
    echo "WARNINGS=$WARNINGS"
    echo "ORPORT=$ORPORT"
    echo "DIRPORT=$DIRPORT"
    echo "ORPORT_STATUS=$ORPORT_STATUS"
    echo "DIRPORT_STATUS=$DIRPORT_STATUS"
    echo "IPV4=$PUBLIC_IP"
    echo "IPV6=$PUBLIC_IP6"
    ;;
  *)
    echo "🧅 Tor Relay Health Check"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    case "$STATUS" in
      healthy) echo "📊 Status: ✅ HEALTHY" ;;
      running) echo "📊 Status: 🟡 RUNNING (awaiting reachability)" ;;
      starting) echo "📊 Status: 🔄 STARTING ($BOOTSTRAP_PERCENT% bootstrapped)" ;;
      down) echo "📊 Status: ❌ DOWN" ;;
      *) echo "📊 Status: ❓ UNKNOWN" ;;
    esac
    echo ""
    echo "⚙️  Process:"
    if [ "$IS_RUNNING" = true ]; then
      echo "   🟢 OK - Tor is running (uptime: $UPTIME)"
    else
      echo "   🔴 FAIL - Tor process not found"
    fi
    echo ""
    echo "🚀 Bootstrap:"
    if [ "$BOOTSTRAP_PERCENT" -eq 100 ]; then
      echo "   🟢 OK - Fully bootstrapped (100%)"
    elif [ "$BOOTSTRAP_PERCENT" -gt 0 ]; then
      echo "   🔄 Bootstrapping... ($BOOTSTRAP_PERCENT%)"
    else
      echo "   ⏳ Not started"
    fi
    echo ""
    echo "🌍 Network:"
    if [ "$IS_REACHABLE" = true ]; then
      echo "   🌐 Reachability: 🟢 OK"
    else
      echo "   🌐 Reachability: 🔴 FAIL"
    fi
    [ -n "$PUBLIC_IP" ] && echo "   🌐 IPv4: 🟢 OK ($PUBLIC_IP)" || echo "   🌐 IPv4: 🔴 No IPv4 connectivity"
    [ -n "$PUBLIC_IP6" ] && echo "   🌐 IPv6: 🟢 OK ($PUBLIC_IP6)" || echo "   🌐 IPv6: 🔴 No IPv6 connectivity"
    
    # Port status with better formatting
    if [ -n "$ORPORT" ]; then
      case "$ORPORT_STATUS" in
        open) echo "   📍 ORPort: 🟢 Open ($ORPORT)" ;;
        closed) echo "   📍 ORPort: 🔴 Closed ($ORPORT)" ;;
        not_configured) echo "   📍 ORPort: ⏭️ Not configured" ;;
        *) echo "   📍 ORPort: ❓ Unknown ($ORPORT)" ;;
      esac
    else
      echo "   📍 ORPort: 🔴 Not configured"
    fi
    
    if [ -n "$DIRPORT" ]; then
      case "$DIRPORT_STATUS" in
        open) echo "   📍 DirPort: 🟢 Open ($DIRPORT)" ;;
        closed) echo "   📍 DirPort: 🔴 Closed ($DIRPORT)" ;;
        not_configured) echo "   📍 DirPort: ⏭️ Not configured" ;;
        *) echo "   📍 DirPort: ❓ Unknown ($DIRPORT)" ;;
      esac
    else
      echo "   📍 DirPort: 🔴 Not configured"
    fi
    echo ""
    if [ -n "$NICKNAME" ] || [ -n "$FINGERPRINT" ]; then
      echo "🔑 Relay Identity:"
      [ -n "$NICKNAME" ] && echo "   📝 Nickname: $NICKNAME"
      [ -n "$FINGERPRINT" ] && echo "   🆔 Fingerprint: $FINGERPRINT"
      case "$RELAY_TYPE" in
        bridge) echo "   🌉 Type: Bridge Relay" ;;
        exit)   echo "   🚪 Type: Exit Relay" ;;
        guard)  echo "   🔒 Type: Guard/Middle Relay" ;;
        *)      echo "   ❓ Type: Unknown" ;;
      esac
      echo ""
    fi
    if [ "$ERRORS" -gt 0 ] || [ "$WARNINGS" -gt 0 ]; then
      echo "⚠️  Issues:"
      [ "$ERRORS" -gt 0 ] && echo "   ❌ Errors: $ERRORS"
      [ "$WARNINGS" -gt 0 ] && echo "   ⚠️  Warnings: $WARNINGS"
      echo ""
    fi
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🕒 Checked: $TIMESTAMP"
    ;;
esac

# ──────────────────────────────────────────────
# Optional webhook support
# ──────────────────────────────────────────────
if [ "$SEND_WEBHOOK" = "true" ] && [ -n "$HEALTH_WEBHOOK_URL" ]; then
  log "info" "Sending health status to webhook"
  if command -v curl >/dev/null 2>&1; then
    /usr/local/bin/health --json | curl -s -X POST "$HEALTH_WEBHOOK_URL" \
      -H "Content-Type: application/json" -d @- >/dev/null 2>&1
    if [ $? -eq 0 ]; then
      log "info" "Webhook sent successfully"
    else
      log "error" "Failed to send webhook"
    fi
  else
    log "error" "curl not available for webhook"
  fi
fi

# ──────────────────────────────────────────────
# Exit code mapping
# ──────────────────────────────────────────────
log "info" "Health check completed with status: $STATUS"
case "$STATUS" in
  healthy|running|starting) 
    log "info" "Exiting with code 0 (healthy)"
    exit 0 
    ;;
  *) 
    log "error" "Exiting with code 1 (unhealthy)"
    exit 1 
    ;;
esac
