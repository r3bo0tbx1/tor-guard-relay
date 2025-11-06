#!/bin/sh
# net-check - Comprehensive network diagnostics for Tor relay (curl-only edition)
# Usage: docker exec guard-relay net-check [--json|--plain|--quick|--full|--help]

set -e

VERSION="1.1.0"
OUTPUT_FORMAT="text"
CHECK_IPV4="true"
CHECK_IPV6="true"
CHECK_DNS="true"
CHECK_CONSENSUS="false"
CHECK_PORTS="true"
DNS_SERVERS="194.242.2.2 94.140.14.14 9.9.9.9"
TEST_TIMEOUT="5"

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

# Parse arguments
for arg in "$@"; do
  case "$arg" in
    --help|-h)
      cat << EOF
🌐 Tor-Guard-Relay Network Diagnostics v${VERSION}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
USAGE:
    net-check [--json|--plain|--quick|--full|--help]

OPTIONS:
    --json       Output JSON format
    --plain      Minimal output for scripts
    --text       Formatted output (default)
    --quick      Skip extended tests
    --full       Run all tests (default)
    --help       Show this help message
EOF
      exit 0
      ;;
    --json) OUTPUT_FORMAT="json" ;;
    --plain) OUTPUT_FORMAT="plain" ;;
    --text) OUTPUT_FORMAT="text" ;;
    --quick)
      CHECK_CONSENSUS="false"
      CHECK_PORTS="false"
      ;;
    --full)
      CHECK_IPV4="true"
      CHECK_IPV6="true"
      CHECK_DNS="true"
      CHECK_CONSENSUS="true"
      CHECK_PORTS="true"
      ;;
  esac
done

# Defaults
IPV4_STATUS="unknown"
IPV6_STATUS="unknown"
DNS_STATUS="unknown"
CONSENSUS_STATUS="unknown"
PORT_STATUS="unknown"
PUBLIC_IP=""
PUBLIC_IP6=""
FAILED_TESTS=0
TOTAL_TESTS=0

command_exists() { command -v "$1" >/dev/null 2>&1; }

# IPv4 check
check_ipv4() {
  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  if [ "$CHECK_IPV4" = "true" ] && command_exists curl; then
    PUBLIC_IP=$(curl -4 -fsS --max-time "$TEST_TIMEOUT" https://ipv4.icanhazip.com 2>/dev/null | tr -d '\r')
    if [ -n "$PUBLIC_IP" ]; then
      IPV4_STATUS="ok"
    else
      IPV4_STATUS="failed"; FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
  else
    IPV4_STATUS="skipped"
  fi
}

# IPv6 check
check_ipv6() {
  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  if [ "$CHECK_IPV6" = "true" ] && command_exists curl; then
    PUBLIC_IP6=$(curl -6 -fsS --max-time "$TEST_TIMEOUT" https://ipv6.icanhazip.com 2>/dev/null | tr -d '\r')
    if [ -n "$PUBLIC_IP6" ]; then
      IPV6_STATUS="ok"
    else
      IPV6_STATUS="not_available"
    fi
  else
    IPV6_STATUS="skipped"
  fi
}

# DNS resolution check
check_dns() {
  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  DNS_WORKING=false
  if [ "$CHECK_DNS" = "true" ]; then
    for dns_server in $DNS_SERVERS; do
      if command_exists nslookup; then
        if nslookup torproject.org "$dns_server" >/dev/null 2>&1; then DNS_WORKING=true; break; fi
      elif command_exists dig; then
        if dig @"$dns_server" torproject.org +short +time="$TEST_TIMEOUT" >/dev/null 2>&1; then DNS_WORKING=true; break; fi
      elif command_exists host; then
        if host -t A torproject.org "$dns_server" >/dev/null 2>&1; then DNS_WORKING=true; break; fi
      fi
    done
    [ "$DNS_WORKING" = "true" ] && DNS_STATUS="ok" || { DNS_STATUS="failed"; FAILED_TESTS=$((FAILED_TESTS + 1)); }
  else
    DNS_STATUS="skipped"
  fi
}

# Tor network reachability
check_consensus() {
  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  if [ "$CHECK_CONSENSUS" = "true" ] && command_exists curl; then
    if curl -fsS --max-time "$TEST_TIMEOUT" https://collector.torproject.org/index.json | grep -q "metrics"; then
      CONSENSUS_STATUS="ok"
    else
      CONSENSUS_STATUS="failed"; FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
  else
    CONSENSUS_STATUS="skipped"
  fi
}

# Port accessibility (optional)
check_ports() {
  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  if [ "$CHECK_PORTS" = "true" ]; then
    if ! command_exists nc; then PORT_STATUS="skipped"; return; fi
    if [ -f /etc/tor/torrc ]; then
      ORPORT=$(grep -E "^ORPort" /etc/tor/torrc 2>/dev/null | awk '{print $2}' | head -1)
      if [ -n "$ORPORT" ] && [ -n "$PUBLIC_IP" ]; then
        if nc -z -w "$TEST_TIMEOUT" "$PUBLIC_IP" "$ORPORT" >/dev/null 2>&1; then
          PORT_STATUS="ok"
        else
          PORT_STATUS="closed"; FAILED_TESTS=$((FAILED_TESTS + 1))
        fi
      else
        PORT_STATUS="not_configured"
      fi
    else
      PORT_STATUS="not_configured"
    fi
  else
    PORT_STATUS="skipped"
  fi
}

# Run all
check_ipv4
check_ipv6
check_dns
# check_consensus
check_ports

TOTAL_PASSED=$((TOTAL_TESTS - FAILED_TESTS))
SUCCESS_RATE=$((TOTAL_PASSED * 100 / TOTAL_TESTS))
TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date '+%Y-%m-%d %H:%M:%S')

# Output
case "$OUTPUT_FORMAT" in
  json)
    cat <<EOF
{
  "timestamp": "$TIMESTAMP",
  "success_rate": $SUCCESS_RATE,
  "tests": { "total": $TOTAL_TESTS, "failed": $FAILED_TESTS },
  "ipv4": { "status": "$IPV4_STATUS", "address": "$PUBLIC_IP" },
  "ipv6": { "status": "$IPV6_STATUS", "address": "$PUBLIC_IP6" },
  "dns": { "status": "$DNS_STATUS", "servers": "$DNS_SERVERS" },
  "consensus": { "status": "$CONSENSUS_STATUS" },
  "ports": { "status": "$PORT_STATUS" }
}
EOF
    ;;
  plain)
    echo "TIMESTAMP=$TIMESTAMP"
    echo "SUCCESS_RATE=$SUCCESS_RATE"
    echo "IPV4_STATUS=$IPV4_STATUS"
    echo "IPV4_ADDRESS=$PUBLIC_IP"
    echo "IPV6_STATUS=$IPV6_STATUS"
    echo "IPV6_ADDRESS=$PUBLIC_IP6"
    echo "DNS_STATUS=$DNS_STATUS"
    echo "CONSENSUS_STATUS=$CONSENSUS_STATUS"
    echo "PORT_STATUS=$PORT_STATUS"
    ;;
  *)
    echo "🌐 Network Diagnostics v$VERSION"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    if [ "$FAILED_TESTS" -eq 0 ]; then
      echo "📊 Overall: ✅ All checks passed ($SUCCESS_RATE%)"
    elif [ "$FAILED_TESTS" -lt "$TOTAL_TESTS" ]; then
      echo "📊 Overall: ⚠️  Some issues detected ($SUCCESS_RATE% passed)"
    else
      echo "📊 Overall: ❌ Multiple failures ($SUCCESS_RATE% passed)"
    fi
    echo ""
    echo "🔌 IPv4: $(format_ip_status IPv4 "$IPV4_STATUS" "$PUBLIC_IP")"
    echo "🔌 IPv6: $(format_ip_status IPv6 "$IPV6_STATUS" "$PUBLIC_IP6")"
    echo "🔍 DNS: $(format_status "$DNS_STATUS")"
    echo "📋 Consensus: $(format_status "$CONSENSUS_STATUS")"
    echo "🚪 Ports: $(format_status "$PORT_STATUS")"
    echo ""
    echo "🕒 Tested at: $TIMESTAMP"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    ;;
esac

[ "$FAILED_TESTS" -eq 0 ] && exit 0 || exit 1
