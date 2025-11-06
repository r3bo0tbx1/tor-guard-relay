#!/bin/sh
# health - Comprehensive Tor relay health check (hybrid stable version)
# Combines full structured output with simplified inline logic (Alpine-safe)

set -e

VERSION="1.1.0"
OUTPUT_FORMAT="${OUTPUT_FORMAT:-text}"
ENABLE_HEALTH_CHECK="${ENABLE_HEALTH_CHECK:-true}"
HEALTH_WEBHOOK_URL="${HEALTH_WEBHOOK_URL:-}"
CHECK_TIMEOUT="${CHECK_TIMEOUT:-5}"

safe() { "$@" 2>/dev/null || true; }

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
  local status="$2"
  local addr="$3"

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

for arg in "$@"; do
  case "$arg" in
    --help|-h)
      cat << EOF
🧅 Tor-Guard-Relay Health Check v${VERSION}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
USAGE:
    health [--json|--plain|--text|--webhook]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
      exit 0 ;;
    --json) OUTPUT_FORMAT="json" ;;
    --plain) OUTPUT_FORMAT="plain" ;;
    --text) OUTPUT_FORMAT="text" ;;
    --webhook) SEND_WEBHOOK="true" ;;
  esac
done

# Skip if disabled
if [ "$ENABLE_HEALTH_CHECK" != "true" ]; then
  case "$OUTPUT_FORMAT" in
    json) echo '{"status":"disabled"}' ;;
    plain) echo "DISABLED" ;;
    *) echo "⏸️  Health checking disabled" ;;
  esac
  exit 0
fi

# Initialize variables
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
EXIT_RELAY="false"
PUBLIC_IP=""
PUBLIC_IP6=""

# Inline Checks

# Tor process
if safe pgrep -x tor >/dev/null; then
  IS_RUNNING=true
  PID=$(safe pgrep -x tor | head -1)
  UPTIME=$(safe ps -p "$PID" -o time= | tr -d ' ')
  [ -z "$UPTIME" ] && UPTIME="0"
fi

# Bootstrap progress
if [ -f /var/log/tor/notices.log ]; then
  BOOTSTRAP_LINE=$(safe grep "Bootstrapped" /var/log/tor/notices.log | tail -1)
  BOOTSTRAP_PERCENT=$(echo "$BOOTSTRAP_LINE" | grep -oE '[0-9]+%' | tr -d '%' | tail -1)
  [ -z "$BOOTSTRAP_PERCENT" ] && BOOTSTRAP_PERCENT=0
fi

# Reachability
if [ -f /var/log/tor/notices.log ]; then
  if safe grep -q "reachable from the outside" /var/log/tor/notices.log; then
    IS_REACHABLE=true
  fi
fi

# Relay info
if [ -f /var/lib/tor/fingerprint ]; then
  NICKNAME=$(safe awk '{print $1}' /var/lib/tor/fingerprint)
  FINGERPRINT=$(safe awk '{print $2}' /var/lib/tor/fingerprint)
fi

if [ -f /etc/tor/torrc ]; then
  ORPORT=$(safe grep -E "^ORPort" /etc/tor/torrc | awk '{print $2}' | head -1)
  DIRPORT=$(safe grep -E "^DirPort" /etc/tor/torrc | awk '{print $2}' | head -1)
  if safe grep -qE "^ExitRelay\s+1" /etc/tor/torrc; then
    EXIT_RELAY="true"
  fi
fi

if [ -f /build-info.txt ]; then
  VERSION_INFO=$(safe head -1 /build-info.txt | cut -d: -f2- | tr -d ' ')
fi

# IPv4/IPv6 check (added for visual consistency)
if command -v curl >/dev/null 2>&1; then
  PUBLIC_IP=$(curl -4 -fsS --max-time "$CHECK_TIMEOUT" https://ipv4.icanhazip.com 2>/dev/null | tr -d '\r')
  PUBLIC_IP6=$(curl -6 -fsS --max-time "$CHECK_TIMEOUT" https://ipv6.icanhazip.com 2>/dev/null | tr -d '\r')
fi

# Count issues
if [ -f /var/log/tor/notices.log ]; then
  ERRORS=$(safe grep -ciE "\[err\]" /var/log/tor/notices.log)
  WARNINGS=$(safe grep -ciE "\[warn\]" /var/log/tor/notices.log)
fi

# Determine overall status
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

TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date)

# Output
case "$OUTPUT_FORMAT" in
  json)
    cat << EOF
{
  "status": "$STATUS",
  "timestamp": "$TIMESTAMP",
  "process": {
    "running": $IS_RUNNING,
    "uptime": "$UPTIME"
  },
  "bootstrap": {
    "percent": $BOOTSTRAP_PERCENT,
    "complete": $([ "$BOOTSTRAP_PERCENT" -eq 100 ] && echo "true" || echo "false")
  },
  "network": {
    "reachable": $IS_REACHABLE,
    "orport": "$ORPORT",
    "dirport": "$DIRPORT",
    "ipv4": "$PUBLIC_IP",
    "ipv6": "$PUBLIC_IP6"
  },
  "relay": {
    "nickname": "$NICKNAME",
    "fingerprint": "$FINGERPRINT",
    "exit_relay": $EXIT_RELAY,
    "version": "$VERSION_INFO"
  },
  "issues": {
    "errors": $ERRORS,
    "warnings": $WARNINGS
  }
}
EOF
    ;;
  plain)
    echo "STATUS=$STATUS"
    echo "RUNNING=$IS_RUNNING"
    echo "BOOTSTRAP=$BOOTSTRAP_PERCENT"
    echo "REACHABLE=$IS_REACHABLE"
    echo "NICKNAME=$NICKNAME"
    echo "FINGERPRINT=$FINGERPRINT"
    echo "ERRORS=$ERRORS"
    echo "WARNINGS=$WARNINGS"
    echo "UPTIME=$UPTIME"
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
    [ -n "$ORPORT" ] && echo "   📍 ORPort: $ORPORT" || echo "   📍 ORPort: 🔴 Not configured"
    [ -n "$DIRPORT" ] && echo "   📍 DirPort: $DIRPORT" || echo "   📍 DirPort: 🔴 Not configured"
    echo ""
    if [ -n "$NICKNAME" ] || [ -n "$FINGERPRINT" ]; then
      echo "🔑 Relay Identity:"
      [ -n "$NICKNAME" ] && echo "   📝 Nickname: $NICKNAME"
      [ -n "$FINGERPRINT" ] && echo "   🆔 Fingerprint: $FINGERPRINT"
      [ "$EXIT_RELAY" = "true" ] && echo "   🚪 Type: Exit Relay" || echo "   🔒 Type: Guard/Middle Relay"
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

# Optional webhook support
if [ "$SEND_WEBHOOK" = "true" ] && [ -n "$HEALTH_WEBHOOK_URL" ]; then
  if command -v curl >/dev/null 2>&1; then
    /usr/local/bin/health --json | curl -s -X POST "$HEALTH_WEBHOOK_URL" \
      -H "Content-Type: application/json" -d @- >/dev/null 2>&1
  fi
fi

case "$STATUS" in
  healthy|running|starting) exit 0 ;;
  *) exit 1 ;;
esac
