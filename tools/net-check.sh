#!/bin/sh
# net-check - Comprehensive network diagnostics for Tor relay (curl-only edition)
# Usage: docker exec guard-relay net-check [--json|--plain|--quick|--full|--help]

set -e

VERSION="1.1.0"
OUTPUT_FORMAT="text"
CHECK_IPV4="true"
CHECK_IPV6="true"
CHECK_DNS="true"
CHECK_CONSENSUS="false"  # Disabled by default
CHECK_PORTS="true"
DNS_SERVERS="194.242.2.2 94.140.14.14 9.9.9.9"
TEST_TIMEOUT="5"

# ──────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────
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

command_exists() { command -v "$1" >/dev/null 2>&1; }

# ──────────────────────────────────────────────
# Argument parsing
# ──────────────────────────────────────────────
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
    --plain      Minimal key=value output
    --text       Formatted output (default)
    --quick      Skip port and consensus tests
    --full       Run all checks including consensus
    --help       Show this help message
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
      exit 0 ;;
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

# ──────────────────────────────────────────────
# Initialize
# ──────────────────────────────────────────────
IPV4_STATUS="unknown"
IPV6_STATUS="unknown"
DNS_STATUS="unknown"
CONSENSUS_STATUS="unknown"
PORT_STATUS="unknown"
PUBLIC_IP=""
PUBLIC_IP6=""
FAILED_TESTS=0
TOTAL_TESTS=0

# ──────────────────────────────────────────────
# Check functions
# ──────────────────────────────────────────────
check_ipv4() {
  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  if [ "$CHECK_IPV4" = "true" ] && command_exists curl; then
    PUBLIC_IP=$(safe curl -4 -fsS --max-time "$TEST_TIMEOUT" https://ipv4.icanhazip.com | tr -d '\r')
    [ -n "$PUBLIC_IP" ] && IPV4_STATUS="ok" || { IPV4_STATUS="failed"; FAILED_TESTS=$((FAILED_TESTS + 1)); }
  else
    IPV4_STATUS="skipped"
  fi
}

check_ipv6() {
  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  if [ "$CHECK_IPV6" = "true" ] && command_exists curl; then
    PUBLIC_IP6=$(safe curl -6 -fsS --max-time "$TEST_TIMEOUT" https://ipv6.icanhazip.com | tr -d '\r')
    [ -n "$PUBLIC_IP6" ] && IPV6_STATUS="ok" || IPV6_STATUS="not_available"
  else
    IPV6_STATUS="skipped"
  fi
}

check_dns() {
  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  local DNS_WORKING="false"
  if [ "$CHECK_DNS" = "true" ]; then
    for dns_server in $DNS_SERVERS; do
      if command_exists nslookup && nslookup torproject.org "$dns_server" >/dev/null 2>&1; then DNS_WORKING="true"; break; fi
      if command_exists dig && dig @"$dns_server" torproject.org +short +time="$TEST_TIMEOUT" >/dev/null 2>&1; then DNS_WORKING="true"; break; fi
      if command_exists host && host -t A torproject.org "$dns_server" >/dev/null 2>&1; then DNS_WORKING="true"; break; fi
    done
    [ "$DNS_WORKING" = "true" ] && DNS_STATUS="ok" || { DNS_STATUS="failed"; FAILED_TESTS=$((FAILED_TESTS + 1)); }
  else
    DNS_STATUS="skipped"
  fi
}

check_consensus() {
  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  if [ "$CHECK_CONSENSUS" = "true" ] && command_exists curl; then
    if safe curl -fsS --max-time "$TEST_TIMEOUT" https://collector.torproject.org/index.json | grep -q "metrics"; then
      CONSENSUS_STATUS="ok"
    else
      CONSENSUS_STATUS="failed"; FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
  else
    CONSENSUS_STATUS="skipped"
  fi
}

check_ports() {
  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  if [ "$CHECK_PORTS" = "true" ]; then
    if ! command_exists nc; then PORT_STATUS="skipped"; return; fi
    if [ -f /etc/tor/torrc ]; then
      ORPORT=$(safe grep -E "^ORPort" /etc/tor/torrc | awk '{print $2}' | head -1)
      if [ -n "$ORPORT" ] && [ -n "$PUBLIC_IP" ]; then
        if safe nc -z -w "$TEST_TIMEOUT" "$PUBLIC_IP" "$ORPORT"; then
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

# ──────────────────────────────────────────────
# Run checks
# ──────────────────────────────────────────────
check_ipv4
check_ipv6
check_dns
# Consensus disabled by default
# check_consensus
check_ports

TOTAL_PASSED=$((TOTAL_TESTS - FAILED_TESTS))
if [ "$TOTAL_TESTS" -eq 0 ]; then
  SUCCESS_RATE=100
else
  SUCCESS_RATE=$((TOTAL_PASSED * 100 / TOTAL_TESTS))
fi
TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date)

# ──────────────────────────────────────────────
# Output
# ──────────────────────────────────────────────
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
    echo "timestamp=$TIMESTAMP"
    echo "success_rate=$SUCCESS_RATE"
    echo "ipv4_status=$IPV4_STATUS"
    echo "ipv4_address=$PUBLIC_IP"
    echo "ipv6_status=$IPV6_STATUS"
    echo "ipv6_address=$PUBLIC_IP6"
    echo "dns_status=$DNS_STATUS"
    echo "consensus_status=$CONSENSUS_STATUS"
    echo "ports_status=$PORT_STATUS"
    ;;
  *)
    echo "🌐 Tor Relay Network Check"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    if [ "$FAILED_TESTS" -eq 0 ]; then
      echo "📊 Overall: 🟢 OK - All checks passed ($SUCCESS_RATE%)"
    elif [ "$FAILED_TESTS" -lt "$TOTAL_TESTS" ]; then
      echo "📊 Overall: 🟡 PARTIAL - Some checks failed ($SUCCESS_RATE% passed)"
    else
      echo "📊 Overall: 🔴 FAIL - All checks failed ($SUCCESS_RATE% passed)"
    fi
    echo ""
    echo "🔌 Connectivity:"
    echo "   IPv4: $(format_ip_status IPv4 "$IPV4_STATUS" "$PUBLIC_IP")"
    echo "   IPv6: $(format_ip_status IPv6 "$IPV6_STATUS" "$PUBLIC_IP6")"
    echo ""
    echo "🧭 DNS & Consensus:"
    echo "   DNS: $(format_status "$DNS_STATUS")"
    echo "   Consensus: $(format_status "$CONSENSUS_STATUS")"
    echo ""
    echo "🚪 Ports:"
    echo "   $(format_status "$PORT_STATUS")"
    echo ""
    echo "🕒 Checked: $TIMESTAMP"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    ;;
esac

[ "$FAILED_TESTS" -eq 0 ] && exit 0 || exit 1
