#!/bin/sh
# status - Comprehensive relay status dashboard
# Usage: docker exec guard-relay status [--json|--help]

set -e

# Configuration
VERSION="1.1.0"
OUTPUT_FORMAT="${OUTPUT_FORMAT:-text}"
SHOW_ALL="${SHOW_ALL:-true}"
CHECK_NETWORK="${CHECK_NETWORK:-true}"

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

SECTIONS:
    • Build Information
    • Bootstrap Progress
    • Reachability Status
    • Relay Identity
    • Network Configuration
    • Performance Metrics
    • Recent Activity
    • Error Summary

EXAMPLES:
    status              # Full status report
    status --json       # JSON output for monitoring
    status --quick      # Quick status without network
    status --plain      # Machine-readable format

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
  # Process status
  IS_RUNNING="false"
  if pgrep -x tor > /dev/null 2>&1; then
    IS_RUNNING="true"
    PID=$(pgrep -x tor | head -1)
    UPTIME=$(ps -o etime= -p "$PID" 2>/dev/null | tr -d ' ' || echo "0")
  fi
  
  # Bootstrap status
  BOOTSTRAP_PERCENT=0
  BOOTSTRAP_MESSAGE=""
  if [ -f /var/log/tor/notices.log ]; then
    BOOTSTRAP_LINE=$(grep "Bootstrapped" /var/log/tor/notices.log 2>/dev/null | tail -1)
    if [ -n "$BOOTSTRAP_LINE" ]; then
      BOOTSTRAP_PERCENT=$(echo "$BOOTSTRAP_LINE" | grep -oE '[0-9]+%' | tr -d '%' | tail -1)
      BOOTSTRAP_MESSAGE=$(echo "$BOOTSTRAP_LINE" | sed 's/.*Bootstrapped [0-9]*%[: ]*//')
    fi
  fi
  
  # Reachability
  IS_REACHABLE="false"
  REACHABILITY_MESSAGE=""
  if [ -f /var/log/tor/notices.log ]; then
    REACHABLE_LINE=$(grep -E "reachable|self-testing" /var/log/tor/notices.log 2>/dev/null | tail -1)
    if echo "$REACHABLE_LINE" | grep -q "reachable from the outside"; then
      IS_REACHABLE="true"
      REACHABILITY_MESSAGE="ORPort is reachable from the outside"
    elif [ -n "$REACHABLE_LINE" ]; then
      REACHABILITY_MESSAGE=$(echo "$REACHABLE_LINE" | sed 's/.*] //')
    fi
  fi
  
  # Relay identity
  NICKNAME=""
  FINGERPRINT=""
  if [ -f /var/lib/tor/fingerprint ]; then
    NICKNAME=$(awk '{print $1}' /var/lib/tor/fingerprint 2>/dev/null)
    FINGERPRINT=$(awk '{print $2}' /var/lib/tor/fingerprint 2>/dev/null)
  fi
  
  # Configuration
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
  
  # Errors and warnings
  ERROR_COUNT=0
  WARNING_COUNT=0
  RECENT_ERRORS=""
  if [ -f /var/log/tor/notices.log ]; then
    ERROR_COUNT=$(grep -cE "\[err\]|\[error\]" /var/log/tor/notices.log 2>/dev/null || echo 0)
    WARNING_COUNT=$(grep -cE "\[warn\]|\[warning\]" /var/log/tor/notices.log 2>/dev/null || echo 0)
    RECENT_ERRORS=$(grep -E "\[err\]|\[error\]" /var/log/tor/notices.log 2>/dev/null | tail -3)
  fi
  
  # Version info
  VERSION_INFO=""
  BUILD_TIME=""
  if [ -f /build-info.txt ]; then
    VERSION_INFO=$(grep "Version:" /build-info.txt 2>/dev/null | cut -d: -f2- | tr -d ' ')
    BUILD_TIME=$(grep "Built:" /build-info.txt 2>/dev/null | cut -d: -f2- | tr -d ' ')
  fi
  
  # Network info (if enabled)
  PUBLIC_IP=""
  if [ "$CHECK_NETWORK" = "true" ] && command -v curl > /dev/null 2>&1; then
    PUBLIC_IP=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || echo "")
  fi
}

# Gather all information
gather_status

# Generate timestamp
TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date '+%Y-%m-%d %H:%M:%S')

# Determine overall status
if [ "$IS_RUNNING" = "false" ]; then
  OVERALL_STATUS="down"
elif [ "$BOOTSTRAP_PERCENT" -eq 100 ] && [ "$IS_REACHABLE" = "true" ]; then
  OVERALL_STATUS="healthy"
elif [ "$BOOTSTRAP_PERCENT" -eq 100 ]; then
  OVERALL_STATUS="running"
elif [ "$BOOTSTRAP_PERCENT" -gt 0 ]; then
  OVERALL_STATUS="starting"
else
  OVERALL_STATUS="unknown"
fi

# Output based on format
case "$OUTPUT_FORMAT" in
  json)
    cat << EOF
{
  "timestamp": "$TIMESTAMP",
  "status": "$OVERALL_STATUS",
  "process": {
    "running": $IS_RUNNING,
    "uptime": "$UPTIME"
  },
  "bootstrap": {
    "percent": $BOOTSTRAP_PERCENT,
    "message": "$BOOTSTRAP_MESSAGE"
  },
  "reachability": {
    "reachable": $IS_REACHABLE,
    "message": "$REACHABILITY_MESSAGE"
  },
  "identity": {
    "nickname": "$NICKNAME",
    "fingerprint": "$FINGERPRINT"
  },
  "configuration": {
    "orport": "$ORPORT",
    "dirport": "$DIRPORT",
    "exit_relay": $EXIT_RELAY,
    "bridge_relay": $BRIDGE_RELAY,
    "bandwidth": "$BANDWIDTH_RATE"
  },
  "network": {
    "public_ip": "$PUBLIC_IP"
  },
  "issues": {
    "errors": $ERROR_COUNT,
    "warnings": $WARNING_COUNT
  },
  "version": {
    "software": "$VERSION_INFO",
    "build_time": "$BUILD_TIME"
  }
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
    ;;
    
  *)
    # Default text format with emojis
    echo "🧅 Tor Relay Status Report"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # Overall status
    case "$OVERALL_STATUS" in
      healthy)
        echo "⭐ Overall Status: ✅ HEALTHY - Relay is fully operational"
        ;;
      running)
        echo "⭐ Overall Status: 🟡 RUNNING - Awaiting reachability confirmation"
        ;;
      starting)
        echo "⭐ Overall Status: 🔄 STARTING - Bootstrap in progress ($BOOTSTRAP_PERCENT%)"
        ;;
      down)
        echo "⭐ Overall Status: ❌ DOWN - Tor process not running"
        ;;
      *)
        echo "⭐ Overall Status: ❓ UNKNOWN"
        ;;
    esac
    echo ""
    
    # Build info
    if [ -n "$VERSION_INFO" ] || [ -n "$BUILD_TIME" ]; then
      echo "📦 Build Information:"
      [ -n "$VERSION_INFO" ] && echo "   Version: $VERSION_INFO"
      [ -n "$BUILD_TIME" ] && echo "   Built: $BUILD_TIME"
      echo ""
    fi
    
    # Bootstrap progress
    echo "🚀 Bootstrap Progress:"
    if [ "$BOOTSTRAP_PERCENT" -eq 100 ]; then
      echo "   ✅ Fully bootstrapped (100%)"
      [ -n "$BOOTSTRAP_MESSAGE" ] && echo "   Status: $BOOTSTRAP_MESSAGE"
    elif [ "$BOOTSTRAP_PERCENT" -gt 0 ]; then
      echo "   🔄 Bootstrapping: $BOOTSTRAP_PERCENT%"
      [ -n "$BOOTSTRAP_MESSAGE" ] && echo "   Status: $BOOTSTRAP_MESSAGE"
    else
      echo "   ⏳ Not started yet"
    fi
    echo ""
    
    # Reachability status
    echo "🌍 Reachability Status:"
    if [ "$IS_REACHABLE" = "true" ]; then
      echo "   ✅ Relay is reachable from the outside"
    elif [ -n "$REACHABILITY_MESSAGE" ]; then
      echo "   🔄 $REACHABILITY_MESSAGE"
    else
      echo "   ⏳ No reachability test results yet"
    fi
    echo ""
    
    # Relay identity
    if [ -n "$NICKNAME" ] || [ -n "$FINGERPRINT" ]; then
      echo "🔑 Relay Identity:"
      [ -n "$NICKNAME" ] && echo "   📝 Nickname: $NICKNAME"
      [ -n "$FINGERPRINT" ] && echo "   🆔 Fingerprint: $FINGERPRINT"
      echo ""
    fi
    
    # Network configuration
    echo "🔌 Network Configuration:"
    [ -n "$ORPORT" ] && echo "   ORPort: $ORPORT"
    [ -n "$DIRPORT" ] && echo "   DirPort: $DIRPORT"
    [ -n "$PUBLIC_IP" ] && echo "   Public IP: $PUBLIC_IP"
    [ -n "$BANDWIDTH_RATE" ] && echo "   Bandwidth: $BANDWIDTH_RATE"
    
    if [ "$EXIT_RELAY" = "true" ]; then
      echo "   Type: 🚪 Exit Relay"
    elif [ "$BRIDGE_RELAY" = "true" ]; then
      echo "   Type: 🌉 Bridge Relay"
    else
      echo "   Type: 🔒 Guard/Middle Relay"
    fi
    echo ""
    
    # Issues summary
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