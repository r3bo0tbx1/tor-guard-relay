#!/bin/sh
# status - Tor Guard Relay status dashboard
# Usage: docker exec TorGuardRelay status [--short|--json|--plain|--quick|--full|--help]

set -eu

VERSION="1.1.0"
OUTPUT_FORMAT=""
CHECK_NETWORK="true"

# ───────────────────────────
# Helper Functions
# ───────────────────────────
is_integer() { case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }
sanitize_num() { v=$(printf '%s' "$1" | tr -cd '0-9'); [ -z "$v" ] && v=0; printf '%s' "$v"; }
format_ip_status() { [ -n "$2" ] && printf '🟢 %s' "$2" || printf '🔴 No %s connectivity' "$1"; }
separator() { printf '%s\n' "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; }

# Convert seconds → human-readable Dd Hh Mm
secs_to_human() {
  s=${1:-0}
  days=$((s / 86400))
  hours=$(( (s % 86400) / 3600 ))
  mins=$(( (s % 3600) / 60 ))
  
  if [ "$days" -gt 0 ]; then
    printf '%dd %dh %dm' "$days" "$hours" "$mins"
  elif [ "$hours" -gt 0 ]; then
    printf '%dh %dm' "$hours" "$mins"
  else
    printf '%dm' "$mins"
  fi
}

# Convert ps etime ("2-14:30:00") → seconds
etime_to_seconds() {
  raw=${1:-}
  [ -z "$raw" ] && { printf '%d' 0; return; }
  
  days=0; hh=0; mm=0; ss=0
  
  # Handle format with days (DD-HH:MM:SS or DD-HH:MM)
  case "$raw" in
    *-*) 
      days=${raw%%-*}
      raw=${raw#*-}
      ;;
  esac
  
  # Parse the time part
  IFS=:; set -- $raw
  case $# in
    3) hh=$1; mm=$2; ss=$3 ;;
    2) hh=$1; mm=$2 ;;
    1) ss=$1 ;;
  esac
  
  # Default to 0 if any value is empty
  hh=${hh:-0}; mm=${mm:-0}; ss=${ss:-0}; days=${days:-0}
  
  # Calculate total seconds
  printf '%d' $((days*86400 + hh*3600 + mm*60 + ss))
}

# Get public IP with multiple fallback methods
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

# Check if port is open
check_port() {
  host=$1
  port=$2
  timeout=$3
  
  if command -v nc >/dev/null 2>&1; then
    # Use netcat if available
    if nc -z -w "$timeout" "$host" "$port" 2>/dev/null; then
      return 0
    fi
  elif command -v timeout >/dev/null 2>&1 && command -v bash >/dev/null 2>&1; then
    # Use timeout with bash's built-in TCP feature
    if timeout "$timeout" bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null; then
      return 0
    fi
  fi
  return 1
}

# ───────────────────────────
# Parse arguments
# ───────────────────────────
for arg in "$@"; do
  case "$arg" in
    --help|-h)
      cat <<EOF
🧅 Tor-Guard-Relay Status Dashboard v${VERSION}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
USAGE:
  status [OPTIONS]

OPTIONS:
  --short         Compact summary output
  --json          JSON format
  --plain         Key=value format
  --quick         Skip network checks
  --full          Detailed dashboard (default)
  --help, -h      Show this message
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
      exit 0 ;;
    --short) OUTPUT_FORMAT="short" ;;
    --json) OUTPUT_FORMAT="json" ;;
    --plain) OUTPUT_FORMAT="plain" ;;
    --quick) CHECK_NETWORK="false" ;;
    --full) OUTPUT_FORMAT="text" ;;
    *)
      if [ "${arg#-}" != "$arg" ]; then
        printf '❌ Unknown option: %s\n' "$arg" >&2
        printf '💡 Use --help for usage information\n' >&2
        exit 2
      fi
      ;;
  esac
done
[ -z "${OUTPUT_FORMAT}" ] && OUTPUT_FORMAT="text"

# ───────────────────────────
# Gather status info
# ───────────────────────────
gather_status() {
  IS_RUNNING="false"
  PID=""
  TOR_UPTIME_SECONDS=0
  CONTAINER_UPTIME_SECONDS=0
  TOR_UPTIME="0m"
  CONTAINER_UPTIME="0m"

  # Tor process uptime
  if pgrep -x tor >/dev/null 2>&1; then
    IS_RUNNING="true"
    PID=$(pgrep -x tor | head -n1)
    TOR_RAW=$(ps -o etime= -p "$PID" 2>/dev/null | awk '{$1=$1};1' || true)
    if [ -n "$TOR_RAW" ]; then
      TOR_UPTIME_SECONDS=$(etime_to_seconds "$TOR_RAW")
      TOR_UPTIME=$(secs_to_human "$TOR_UPTIME_SECONDS")
    fi
  fi

  # Container uptime
  if [ -r /proc/1/uptime ]; then
    sec=$(awk '{print int($1)}' /proc/1/uptime 2>/dev/null || echo 0)
    CONTAINER_UPTIME_SECONDS=$sec
    CONTAINER_UPTIME=$(secs_to_human "$sec")
  fi

  # Always display the most relevant uptime in a clean one-line format
  if [ "$IS_RUNNING" = "true" ] && [ "$TOR_UPTIME_SECONDS" -gt 0 ]; then
    UPTIME_DISPLAY="${TOR_UPTIME}"
    UPTIME_SOURCE="Tor process"
  else
    UPTIME_DISPLAY="${CONTAINER_UPTIME}"
    UPTIME_SOURCE="Container"
  fi

  # Bootstrap progress
  BOOTSTRAP_PERCENT=0
  if [ -f /var/log/tor/notices.log ]; then
    BOOTSTRAP_LINE=$(grep "Bootstrapped" /var/log/tor/notices.log 2>/dev/null | tail -n1 || true)
    [ -n "$BOOTSTRAP_LINE" ] && BOOTSTRAP_PERCENT=$(sanitize_num "$(printf '%s' "$BOOTSTRAP_LINE" | grep -oE '[0-9]+' | tail -n1)")
  fi

  # Reachability
  IS_REACHABLE="false"
  REACHABILITY_STATUS="Unknown"
  if [ -f /var/log/tor/notices.log ]; then
    if grep -q "reachable from the outside" /var/log/tor/notices.log 2>/dev/null; then
      IS_REACHABLE="true"
      REACHABILITY_STATUS="Reachable"
    else
      REACHABILITY_STATUS="Not reachable"
    fi
  fi

  # Relay identity
  NICKNAME="unknown"
  FINGERPRINT="N/A"
  if [ -f /var/lib/tor/fingerprint ]; then
    NICKNAME=$(awk '{print $1}' /var/lib/tor/fingerprint 2>/dev/null || echo "unknown")
    FINGERPRINT=$(awk '{print $2}' /var/lib/tor/fingerprint 2>/dev/null || echo "N/A")
  fi

  # Config
  ORPORT="N/A"
  DIRPORT="N/A"
  RELAY_TYPE="🔒 Guard/Middle Relay"
  CONTACT_INFO="N/A"
  
  if [ -f /etc/tor/torrc ]; then
    ORPORT=$(grep -E "^ORPort" /etc/tor/torrc 2>/dev/null | awk '{print $2}' | head -n1 || echo "N/A")
    DIRPORT=$(grep -E "^DirPort" /etc/tor/torrc 2>/dev/null | awk '{print $2}' | head -n1 || echo "N/A")
    CONTACT_INFO=$(grep -E "^ContactInfo" /etc/tor/torrc 2>/dev/null | cut -d' ' -f2- | head -n1 || echo "N/A")
    
    if grep -qE "^ExitRelay\s+1" /etc/tor/torrc 2>/dev/null; then
      RELAY_TYPE="🚪 Exit Relay"
    elif grep -qE "^BridgeRelay\s+1" /etc/tor/torrc 2>/dev/null; then
      RELAY_TYPE="🌉 Bridge Relay"
    fi
  fi

  # Logs
  ERROR_COUNT=0
  WARNING_COUNT=0
  if [ -f /var/log/tor/notices.log ]; then
    ERROR_COUNT=$(sanitize_num "$(grep -cE '\[err\]|\[error\]' /var/log/tor/notices.log 2>/dev/null || echo 0)")
    WARNING_COUNT=$(sanitize_num "$(grep -cE '\[warn\]|\[warning\]' /var/log/tor/notices.log 2>/dev/null || echo 0)")
  fi

  # Version and build info from build-info.txt
  VERSION_INFO=""
  BUILD_TIME=""
  if [ -f /build-info.txt ]; then
    VERSION_INFO=$(grep "Version:" /build-info.txt 2>/dev/null | cut -d: -f2- | tr -d ' ')
    BUILD_TIME=$(grep "Built:" /build-info.txt 2>/dev/null | cut -d: -f2- | tr -d ' ')
  fi
  
  # Fallback if build-info.txt doesn't exist or doesn't contain expected info
  if [ -z "$VERSION_INFO" ]; then
    if command -v tor >/dev/null 2>&1; then
      VERSION_INFO=$(tor --version 2>/dev/null | awk 'NR==1{for(i=1;i<=NF;i++) if ($i ~ /[0-9]+\.[0-9]+/) {print $i; exit}}' || echo "unknown")
    else
      VERSION_INFO="unknown"
    fi
  fi
  
  if [ -z "$BUILD_TIME" ]; then
    BUILD_TIME=$(date '+%Y-%m-%d' 2>/dev/null || echo "unknown")
  fi
  
  ARCH=$(uname -m 2>/dev/null || echo "unknown")
  
  # Format build info as requested
  BUILD_INFO="v${VERSION_INFO} (${BUILD_TIME}, ${ARCH})"

  # IPv4/IPv6 detection with improved reliability
  PUBLIC_IP=""
  PUBLIC_IP6=""
  IPV4_OK="false"
  IPV6_OK="false"
  ORPORT_OPEN="false"
  DIRPORT_OPEN="false"
  
  if [ "$CHECK_NETWORK" = "true" ]; then
    # Get IPv4
    ip4=$(get_public_ip "ipv4")
    if [ -n "$ip4" ]; then
      PUBLIC_IP="$ip4"
      IPV4_OK="true"
      
      # Check if ORPort is open (only if it's not the default 0)
      if [ "$ORPORT" != "N/A" ] && [ "$ORPORT" != "0" ]; then
        if check_port "$PUBLIC_IP" "$ORPORT" 3; then
          ORPORT_OPEN="true"
        fi
      fi
      
      # Check if DirPort is open (only if it's not the default 0)
      if [ "$DIRPORT" != "N/A" ] && [ "$DIRPORT" != "0" ]; then
        if check_port "$PUBLIC_IP" "$DIRPORT" 3; then
          DIRPORT_OPEN="true"
        fi
      fi
    fi
    
    # Get IPv6
    ip6=$(get_public_ip "ipv6")
    if [ -n "$ip6" ]; then
      PUBLIC_IP6="$ip6"
      IPV6_OK="true"
    fi
  fi

  TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
}

# ───────────────────────────
# Gather data
# ───────────────────────────
gather_status

# Determine status
if [ "${IS_RUNNING}" = "false" ]; then
  OVERALL_STATUS="down"
elif [ "$BOOTSTRAP_PERCENT" -eq 100 ] && [ "${IS_REACHABLE}" = "true" ]; then
  OVERALL_STATUS="healthy"
elif [ "$BOOTSTRAP_PERCENT" -eq 100 ]; then
  OVERALL_STATUS="running"
elif [ "$BOOTSTRAP_PERCENT" -gt 0 ]; then
  OVERALL_STATUS="starting"
else
  OVERALL_STATUS="unknown"
fi

# ───────────────────────────
# Output
# ───────────────────────────
case "$OUTPUT_FORMAT" in
  short)
    printf '🧅 Tor Relay Status Summary\n'
    separator
    printf '📦 Build: %s\n' "${BUILD_INFO}"
    [ "$BOOTSTRAP_PERCENT" -eq 100 ] && printf '🚀 Bootstrap: ✅ 100%% Complete\n' || printf '🚀 Bootstrap: %s%%\n' "$BOOTSTRAP_PERCENT"
    [ "${IS_REACHABLE}" = "true" ] && printf '🌐 Reachable: ✅ %s\n' "${REACHABILITY_STATUS}" || printf '🌐 Reachable: ❌ %s\n' "${REACHABILITY_STATUS}"
    printf '📊 Uptime: %s (%s)\n' "${UPTIME_DISPLAY}" "${UPTIME_SOURCE}"
    printf '🔑 %s (%s)\n' "${NICKNAME}" "${FINGERPRINT}"
    printf '🔌 ORPort: %s | DirPort: %s\n' "${ORPORT}" "${DIRPORT}"
    printf '⚙️  Type: %s\n' "${RELAY_TYPE}"
    printf '⚠️  Errors: %02d | Warnings: %d\n' "${ERROR_COUNT}" "${WARNING_COUNT}"
    printf '🕒 %s\n\n' "${TIMESTAMP}"
    ;;

  json)
    cat <<EOF
{
  "timestamp": "${TIMESTAMP}",
  "status": "${OVERALL_STATUS}",
  "uptime": "${UPTIME_DISPLAY}",
  "uptime_source": "${UPTIME_SOURCE}",
  "bootstrap": ${BOOTSTRAP_PERCENT},
  "reachable": "${IS_REACHABLE}",
  "reachability_status": "${REACHABILITY_STATUS}",
  "ipv4": "${PUBLIC_IP}",
  "ipv6": "${PUBLIC_IP6}",
  "orport": "${ORPORT}",
  "dirport": "${DIRPORT}",
  "orport_open": "${ORPORT_OPEN}",
  "dirport_open": "${DIRPORT_OPEN}",
  "nickname": "${NICKNAME}",
  "fingerprint": "${FINGERPRINT}",
  "relay_type": "${RELAY_TYPE}",
  "contact_info": "${CONTACT_INFO}",
  "errors": ${ERROR_COUNT},
  "warnings": ${WARNING_COUNT},
  "version": "${VERSION_INFO}",
  "build_time": "${BUILD_TIME}",
  "arch": "${ARCH}",
  "build_info": "${BUILD_INFO}"
}
EOF
    ;;

  plain)
    printf 'timestamp=%s\n' "${TIMESTAMP}"
    printf 'status=%s\n' "${OVERALL_STATUS}"
    printf 'uptime=%s\n' "${UPTIME_DISPLAY}"
    printf 'uptime_source=%s\n' "${UPTIME_SOURCE}"
    printf 'bootstrap=%d\n' "${BOOTSTRAP_PERCENT}"
    printf 'reachable=%s\n' "${IS_REACHABLE}"
    printf 'reachability_status=%s\n' "${REACHABILITY_STATUS}"
    printf 'ipv4=%s\n' "${PUBLIC_IP}"
    printf 'ipv6=%s\n' "${PUBLIC_IP6}"
    printf 'orport=%s\n' "${ORPORT}"
    printf 'dirport=%s\n' "${DIRPORT}"
    printf 'orport_open=%s\n' "${ORPORT_OPEN}"
    printf 'dirport_open=%s\n' "${DIRPORT_OPEN}"
    printf 'nickname=%s\n' "${NICKNAME}"
    printf 'fingerprint=%s\n' "${FINGERPRINT}"
    printf 'relay_type=%s\n' "${RELAY_TYPE}"
    printf 'contact_info=%s\n' "${CONTACT_INFO}"
    printf 'errors=%d\n' "${ERROR_COUNT}"
    printf 'warnings=%d\n' "${WARNING_COUNT}"
    printf 'version=%s\n' "${VERSION_INFO}"
    printf 'build_time=%s\n' "${BUILD_TIME}"
    printf 'arch=%s\n' "${ARCH}"
    printf 'build_info=%s\n' "${BUILD_INFO}"
    ;;

  *)
    printf '🧅 Tor Relay Status Report\n'
    separator
    printf '\n⭐ Overall Status: '
    case "$OVERALL_STATUS" in
      healthy) printf '🟢 OK - Relay is fully operational\n' ;;
      running) printf '🟡 RUNNING - Awaiting reachability confirmation\n' ;;
      starting) printf '🔄 STARTING - Bootstrap in progress (%s%%)\n' "$BOOTSTRAP_PERCENT" ;;
      down) printf '🔴 FAIL - Tor process not running\n' ;;
      *) printf '❓ UNKNOWN\n' ;;
    esac

    printf '\n📦 Build: %s\n' "${BUILD_INFO}"

    printf '\n🚀 Bootstrap Progress:\n'
    [ "$BOOTSTRAP_PERCENT" -eq 100 ] && printf '   ✅ 100%% Complete\n' || printf '   🔄 %s%%\n' "$BOOTSTRAP_PERCENT"

    printf '\n🌐 Network Status:\n'
    [ "${IS_REACHABLE}" = "true" ] && printf '   🟢 Reachable: Yes - Relay can accept connections\n' || printf '   🔴 Reachable: No - Relay may be behind firewall/NAT\n'
    printf '   IPv4: %s\n' "$(format_ip_status IPv4 "$PUBLIC_IP")"
    printf '   IPv6: %s\n' "$(format_ip_status IPv6 "$PUBLIC_IP6")"
    
    if [ "$ORPORT" != "N/A" ] && [ "$ORPORT" != "0" ]; then
      [ "$ORPORT_OPEN" = "true" ] && printf '   🟢 ORPort %s: Open\n' "$ORPORT" || printf '   🔴 ORPort %s: Closed or filtered\n' "$ORPORT"
    fi
    
    if [ "$DIRPORT" != "N/A" ] && [ "$DIRPORT" != "0" ]; then
      [ "$DIRPORT_OPEN" = "true" ] && printf '   🟢 DirPort %s: Open\n' "$DIRPORT" || printf '   🔴 DirPort %s: Closed or filtered\n' "$DIRPORT"
    fi

    printf '\n🔑 Relay Identity:\n'
    printf '   📝 Nickname: %s\n' "${NICKNAME}"
    printf '   🆔 Fingerprint: %s\n' "${FINGERPRINT}"
    printf '   📧 Contact: %s\n' "${CONTACT_INFO}"

    printf '\n📊 Uptime:\n'
    printf '   %s (%s)\n' "${UPTIME_DISPLAY}" "${UPTIME_SOURCE}"

    printf '\n🔌 Configuration:\n'
    printf '   ORPort: %s | DirPort: %s\n' "${ORPORT}" "${DIRPORT}"
    printf '   Type: %s\n' "${RELAY_TYPE}"

    printf '\n⚠️  Errors: %d | Warnings: %d\n' "${ERROR_COUNT}" "${WARNING_COUNT}"

    printf '\n'
    separator
    printf '🕒 Last updated: %s\n' "${TIMESTAMP}"
    ;;
esac
