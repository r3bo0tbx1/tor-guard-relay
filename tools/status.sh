#!/bin/sh
# status - Comprehensive relay status dashboard
# Usage: docker exec guard-relay status [--json|--help]

set -e

# Configuration
VERSION="1.0.9"
OUTPUT_FORMAT="${OUTPUT_FORMAT:-text}"
SHOW_ALL="${SHOW_ALL:-true}"
CHECK_NETWORK="${CHECK_NETWORK:-true}"

format_status() {
  case "$1" in
    ok|OK) echo "🟢 OK" ;;
    failed|closed|error|FAIL|not_available) echo "🔴 FAIL" ;;
    skipped|unknown) echo "⏭️ SKIPPED" ;;
    *) echo "$1" ;;
  esac
}

format_ip_status() {
  local type="$1"
  local value="$2"
  if [ -n "$value" ]; then
    echo "🟢 OK ($value)"
  else
    echo "🔴 No ${type} connectivity"
  fi
}

# Safe integer check
is_integer() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

# Parse arguments
for arg in "$@"; do
  case "$arg" in
    --help|-h)
      cat << EOF
🧅 Tor-Guard-Relay Status Dashboard v${VERSION}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

USAGE:
    status [OPTIONS]

OPTIONS:
    --json          Output in JSON format
    --plain         Plain text output
    --quick         Quick status check (skip network tests)
    --full          Full status report (default)
    --help, -h      Show this help message

ENVIRONMENT VARIABLES:
    OUTPUT_FORMAT     Output format (text/json/plain)
    SHOW_ALL         Show all sections (true/false)
    CHECK_NETWORK    Include network checks (true/false)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
      exit 0
      ;;
    --json) OUTPUT_FORMAT="json" ;;
    --plain) OUTPUT_FORMAT="plain" ;;
    --quick) CHECK_NETWORK="false" ;;
    --full)
      SHOW_ALL="true"
      CHECK_NETWORK="true"
      ;;
    -*)
      echo "❌ Unknown option: $arg"
      echo "💡 Use --help for usage information"
      exit 2
      ;;
  esac
done

# Gather all status information
gather_status() {
  IS_RUNNING="false"
  if pgrep -x tor >/dev/null 2>&1; then
    IS_RUNNING="true"
    PID=$(pgrep -x tor | head -1)
    UPTIME=$(ps -o etime= -p "$PID" 2>/dev/null | tr -d ' ' || echo "0")
  fi

  BOOTSTRAP_PERCENT=0
  BOOTSTRAP_MESSAGE=""
  if [ -f /var/log/tor/notices.log ]; then
    BOOTSTRAP_LINE=$(grep "Bootstrapped" /var/log/tor/notices.log 2>/dev/null | tail -1 || true)
    if [ -n "$BOOTSTRAP_LINE" ]; then
      # Extract clean integer only
      BOOTSTRAP_PERCENT=$(echo "$BOOTSTRAP_LINE" | grep -oE '[0-9]+' | tail -1 | tr -d '\r' || echo 0)
      BOOTSTRAP_PERCENT=${BOOTSTRAP_PERCENT:-0}
      BOOTSTRAP_MESSAGE=$(echo "$BOOTSTRAP_LINE" | sed 's/.*Bootstrapped [0-9]*%[: ]*//')
    fi
  fi

  IS_REACHABLE="false"
  REACHABILITY_MESSAGE=""
  if [ -f /var/log/tor/notices.log ]; then
    REACHABLE_LINE=$(grep -E "reachable|self-testing" /var/log/tor/notices.log 2>/dev/null | tail -1 || true)
    if echo "$REACHABLE_LINE" | grep -q "reachable from the outside" 2>/dev/null; then
      IS_REACHABLE="true"
      REACHABILITY_MESSAGE="ORPort is reachable from the outside"
    elif [ -n "$REACHABLE_LINE" ]; then
      REACHABILITY_MESSAGE=$(echo "$REACHABLE_LINE" | sed 's/.*] //')
    fi
  fi

  NICKNAME=""
  FINGERPRINT=""
  if [ -f /var/lib/tor/fingerprint ]; then
    NICKNAME=$(awk '{print $1}' /var/lib/tor/fingerprint 2>/dev/null)
    FINGERPRINT=$(awk '{print $2}' /var/lib/tor/fingerprint 2>/dev/null)
  fi

  ORPORT=""
  DIRPORT=""
  EXIT_RELAY="false"
  BRIDGE_RELAY="false"
  BANDWIDTH_RATE=""
  if [ -f /etc/tor/torrc ]; then
    ORPORT=$(grep -E "^ORPort" /etc/tor/torrc 2>/dev/null | awk '{print $2}' | head -1)
    DIRPORT=$(grep -E "^DirPort" /etc/tor/torrc 2>/dev/null | awk '{print $2}' | head -1)
    grep -qE "^ExitRelay\s+1" /etc/tor/torrc 2>/dev/null && EXIT_RELAY="true"
    grep -qE "^BridgeRelay\s+1" /etc/tor/torrc 2>/dev/null && BRIDGE_RELAY="true"
    BANDWIDTH_RATE=$(grep -E "^RelayBandwidthRate" /etc/tor/torrc 2>/dev/null | awk '{print $2,$3}')
  fi

  ERROR_COUNT=0
  WARNING_COUNT=0
  RECENT_ERRORS=""
  if [ -f /var/log/tor/notices.log ]; then
    ERROR_COUNT=$(grep -cE "\[err\]|\[error\]" /var/log/tor/notices.log 2>/dev/null || echo 0)
    WARNING_COUNT=$(grep -cE "\[warn\]|\[warning\]" /var/log/tor/notices.log 2>/dev/null || echo 0)
    RECENT_ERRORS=$(grep -E "\[err\]|\[error\]" /var/log/tor/notices.log 2>/dev/null | tail -3)
  fi

  VERSION_INFO=""
  BUILD_TIME=""
  if [ -f /build-info.txt ]; then
    VERSION_INFO=$(grep "Version:" /build-info.txt 2>/dev/null | cut -d: -f2- | tr -d ' ')
    BUILD_TIME=$(grep "Built:" /build-info.txt 2>/dev/null | cut -d: -f2- | tr -d ' ')
  fi

  PUBLIC_IP=""
  PUBLIC_IP6=""
  if [ "$CHECK_NETWORK" = "true" ] && command -v curl >/dev/null 2>&1; then
    PUBLIC_IP=$(curl -4 -s --max-time 5 https://ipv4.icanhazip.com 2>/dev/null | tr -d '\r')
    PUBLIC_IP6=$(curl -6 -s --max-time 5 https://ipv6.icanhazip.com 2>/dev/null | tr -d '\r')
  fi
}

gather_status

# Sanitize percent and timestamp
BOOTSTRAP_PERCENT=$(echo "$BOOTSTRAP_PERCENT" | tr -cd '0-9')
BOOTSTRAP_PERCENT=${BOOTSTRAP_PERCENT:-0}
TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date '+%Y-%m-%d %H:%M:%S')

# Determine overall status safely
if [ "$IS_RUNNING" = "false" ]; then
  OVERALL_STATUS="down"
elif is_integer "$BOOTSTRAP_PERCENT" && [ "$BOOTSTRAP_PERCENT" -eq 100 ] && [ "$IS_REACHABLE" = "true" ]; then
  OVERALL_STATUS="healthy"
elif is_integer "$BOOTSTRAP_PERCENT" && [ "$BOOTSTRAP_PERCENT" -eq 100 ]; then
  OVERALL_STATUS="running"
elif is_integer "$BOOTSTRAP_PERCENT" && [ "$BOOTSTRAP_PERCENT" -gt 0 ]; then
  OVERALL_STATUS="starting"
else
  OVERALL_STATUS="unknown"
fi

case "$OUTPUT_FORMAT" in
  json)
    cat << EOF
{
  "timestamp": "$TIMESTAMP",
  "status": "$OVERALL_STATUS",
  "process": { "running": $IS_RUNNING, "uptime": "$UPTIME" },
  "bootstrap": { "percent": $BOOTSTRAP_PERCENT, "message": "$BOOTSTRAP_MESSAGE" },
  "reachability": { "reachable": $IS_REACHABLE, "message": "$REACHABILITY_MESSAGE" },
  "identity": { "nickname": "$NICKNAME", "fingerprint": "$FINGERPRINT" },
  "configuration": {
    "orport": "$ORPORT",
    "dirport": "$DIRPORT",
    "exit_relay": $EXIT_RELAY,
    "bridge_relay": $BRIDGE_RELAY,
    "bandwidth": "$BANDWIDTH_RATE"
  },
  "network": { "ipv4": "$PUBLIC_IP", "ipv6": "$PUBLIC_IP6" },
  "issues": { "errors": $ERROR_COUNT, "warnings": $WARNING_COUNT },
  "version": { "software": "$VERSION_INFO", "build_time": "$BUILD_TIME" }
}
EOF
    ;;
  plain)
    echo "STATUS=$OVERALL_STATUS"
    echo "RUNNING=$IS_RUNNING"
    echo "UPTIME=$UPTIME"
    echo "BOOTSTRAP=$BOOTSTRAP_PERCENT"
    echo "REACHABLE=$IS_REACHABLE"
    echo "NICKNAME=$NICKNAME"
    echo "FINGERPRINT=$FINGERPRINT"
    echo "ORPORT=$ORPORT"
    echo "DIRPORT=$DIRPORT"
    echo "ERRORS=$ERROR_COUNT"
    echo "WARNINGS=$WARNING_COUNT"
    echo "PUBLIC_IP=$PUBLIC_IP"
    echo "PUBLIC_IP6=$PUBLIC_IP6"
    ;;
  *)
    echo "🧅 Tor Relay Status Report"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    case "$OVERALL_STATUS" in
      healthy) echo "⭐ Overall Status: 🟢 OK - Relay is fully operational" ;;
      running) echo "⭐ Overall Status: 🟡 RUNNING - Awaiting reachability confirmation" ;;
      starting) echo "⭐ Overall Status: 🔄 STARTING - Bootstrap in progress ($BOOTSTRAP_PERCENT%)" ;;
      down) echo "⭐ Overall Status: 🔴 FAIL - Tor process not running" ;;
      *) echo "⭐ Overall Status: ❓ UNKNOWN" ;;
    esac
    echo ""

    if [ -n "$VERSION_INFO" ] || [ -n "$BUILD_TIME" ]; then
      echo "📦 Build Information:"
      [ -n "$VERSION_INFO" ] && echo "   Version: $VERSION_INFO"
      [ -n "$BUILD_TIME" ] && echo "   Built: $BUILD_TIME"
      echo ""
    fi

    echo "🚀 Bootstrap Progress:"
    if is_integer "$BOOTSTRAP_PERCENT" && [ "$BOOTSTRAP_PERCENT" -eq 100 ]; then
      echo "   🟢 OK - Fully bootstrapped (100%)"
      [ -n "$BOOTSTRAP_MESSAGE" ] && echo "   Status: $BOOTSTRAP_MESSAGE"
    elif is_integer "$BOOTSTRAP_PERCENT" && [ "$BOOTSTRAP_PERCENT" -gt 0 ]; then
      echo "   🔄 Bootstrapping: $BOOTSTRAP_PERCENT%"
      [ -n "$BOOTSTRAP_MESSAGE" ] && echo "   Status: $BOOTSTRAP_MESSAGE"
    else
      echo "   ⏳ Not started yet"
    fi
    echo ""

    echo "🌍 Reachability:"
    if [ "$IS_REACHABLE" = "true" ]; then
      echo "   🌐 Reachability: 🟢 OK"
    elif [ -n "$REACHABILITY_MESSAGE" ]; then
      echo "   🌐 Reachability: 🔴 $REACHABILITY_MESSAGE"
    else
      echo "   🌐 Reachability: ⏳ Pending"
    fi
    echo ""

    if [ -n "$NICKNAME" ] || [ -n "$FINGERPRINT" ]; then
      echo "🔑 Relay Identity:"
      [ -n "$NICKNAME" ] && echo "   📝 Nickname: $NICKNAME"
      [ -n "$FINGERPRINT" ] && echo "   🆔 Fingerprint: $FINGERPRINT"
      echo ""
    fi

    echo "🔌 Network Configuration:"
    [ -n "$PUBLIC_IP" ] && echo "   IPv4: $(format_ip_status IPv4 "$PUBLIC_IP")" || echo "   IPv4: 🔴 No IPv4 connectivity"
    [ -n "$PUBLIC_IP6" ] && echo "   IPv6: $(format_ip_status IPv6 "$PUBLIC_IP6")" || echo "   IPv6: 🔴 No IPv6 connectivity"
    [ -n "$ORPORT" ] && echo "   ORPort: $ORPORT" || echo "   ORPort: 🔴 Not configured"
    [ -n "$DIRPORT" ] && echo "   DirPort: $DIRPORT" || echo "   DirPort: 🔴 Not configured"
    [ -n "$BANDWIDTH_RATE" ] && echo "   Bandwidth: $BANDWIDTH_RATE"
    if [ "$EXIT_RELAY" = "true" ]; then
      echo "   Type: 🚪 Exit Relay"
    elif [ "$BRIDGE_RELAY" = "true" ]; then
      echo "   Type: 🌉 Bridge Relay"
    else
      echo "   Type: 🔒 Guard/Middle Relay"
    fi
    echo ""

    if [ "$ERROR_COUNT" -gt 0 ] || [ "$WARNING_COUNT" -gt 0 ]; then
      echo "⚠️  Issues Summary:"
      [ "$ERROR_COUNT" -gt 0 ] && echo "   ❌ Errors: $ERROR_COUNT"
      [ "$WARNING_COUNT" -gt 0 ] && echo "   ⚠️  Warnings: $WARNING_COUNT"
      if [ -n "$RECENT_ERRORS" ] && [ "$ERROR_COUNT" -gt 0 ]; then
        echo ""
        echo "   Recent errors:"
        echo "$RECENT_ERRORS" | sed 's/^/      /'
      fi
      echo ""
    fi

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "💡 For live monitoring: docker logs -f <container-name>"
    echo "🔗 Search your relay: https://metrics.torproject.org/rs.html"
    [ -n "$FINGERPRINT" ] && echo "📊 Direct link: https://metrics.torproject.org/rs.html#search/$FINGERPRINT"
    echo "🕒 Last updated: $TIMESTAMP"
    ;;
esac
