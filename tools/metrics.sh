#!/bin/sh
# metrics - Prometheus-compatible metrics exporter for Tor relay
# Usage: docker exec guard-relay metrics [--help]

set -e

# Configuration
VERSION="1.1.0"
METRICS_PREFIX="${METRICS_PREFIX:-tor_relay}"
INCLUDE_LABELS="${INCLUDE_LABELS:-true}"
METRICS_FORMAT="${METRICS_FORMAT:-prometheus}"

# Parse arguments
for arg in "$@"; do
  case "$arg" in
    --help|-h)
      cat << EOF
📊 Tor-Guard-Relay Metrics Exporter v${VERSION}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

USAGE:
    metrics [OPTIONS]

OPTIONS:
    --prometheus    Output in Prometheus format (default)
    --json         Output metrics as JSON
    --help, -h     Show this help message

ENVIRONMENT VARIABLES:
    METRICS_PREFIX     Prefix for metric names (default: tor_relay)
    INCLUDE_LABELS     Include labels in output (true/false)
    METRICS_FORMAT     Output format (prometheus/json)

METRICS EXPORTED:
    • ${METRICS_PREFIX}_up                    Relay status (0/1)
    • ${METRICS_PREFIX}_bootstrap_percent     Bootstrap progress
    • ${METRICS_PREFIX}_reachable             Reachability status
    • ${METRICS_PREFIX}_uptime_seconds        Process uptime
    • ${METRICS_PREFIX}_errors_total          Total error count
    • ${METRICS_PREFIX}_warnings_total        Total warning count
    • ${METRICS_PREFIX}_bandwidth_read_bytes  Bytes read
    • ${METRICS_PREFIX}_bandwidth_write_bytes Bytes written
    • ${METRICS_PREFIX}_circuits_total        Active circuits

PROMETHEUS INTEGRATION:
    # prometheus.yml
    scrape_configs:
      - job_name: 'tor-relay'
        static_configs:
          - targets: ['relay:9052']

EXAMPLES:
    metrics                    # Prometheus format output
    metrics --json            # JSON metrics
    curl localhost:9052/metrics  # HTTP endpoint

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
      exit 0
      ;;
    --prometheus) METRICS_FORMAT="prometheus" ;;
    --json) METRICS_FORMAT="json" ;;
    -*) 
      echo "# ERROR: Unknown option: $arg"
      echo "# Use --help for usage information"
      exit 2
      ;;
  esac
done

# Initialize metrics
RELAY_UP=0
BOOTSTRAP_PERCENT=0
IS_REACHABLE=0
UPTIME_SECONDS=0
ERROR_COUNT=0
WARNING_COUNT=0
BANDWIDTH_READ=0
BANDWIDTH_WRITE=0
CIRCUITS_ACTIVE=0
NICKNAME=""
FINGERPRINT=""
VERSION_INFO=""

# Get relay identity
if [ -f /var/lib/tor/fingerprint ]; then
  NICKNAME=$(awk '{print $1}' /var/lib/tor/fingerprint 2>/dev/null || echo "unknown")
  FINGERPRINT=$(awk '{print $2}' /var/lib/tor/fingerprint 2>/dev/null || echo "")
fi

# Check if Tor is running
if pgrep -x tor > /dev/null 2>&1; then
  RELAY_UP=1
  
  # Calculate uptime in seconds
  PID=$(pgrep -x tor | head -1)
  if [ -n "$PID" ]; then
    # Get process start time
    if [ -f "/proc/$PID/stat" ]; then
      STARTTIME=$(awk '{print $22}' "/proc/$PID/stat" 2>/dev/null || echo 0)
      UPTIME_TICKS=$(($(cat /proc/uptime | cut -d. -f1) * 100))
      if [ "$STARTTIME" -gt 0 ]; then
        UPTIME_SECONDS=$(((UPTIME_TICKS - STARTTIME) / 100))
      fi
    fi
  fi
fi

# Parse bootstrap percentage
if [ -f /var/log/tor/notices.log ]; then
  BOOTSTRAP_LINE=$(grep "Bootstrapped" /var/log/tor/notices.log 2>/dev/null | tail -1)
  if [ -n "$BOOTSTRAP_LINE" ]; then
    BOOTSTRAP_PERCENT=$(echo "$BOOTSTRAP_LINE" | grep -oE '[0-9]+%' | tr -d '%' | tail -1)
    [ -z "$BOOTSTRAP_PERCENT" ] && BOOTSTRAP_PERCENT=0
  fi
  
  # Check reachability
  if grep -q "reachable from the outside" /var/log/tor/notices.log 2>/dev/null; then
    IS_REACHABLE=1
  fi
  
  # Count errors and warnings
  ERROR_COUNT=$(grep -cE "\[err\]|\[error\]" /var/log/tor/notices.log 2>/dev/null || echo 0)
  WARNING_COUNT=$(grep -cE "\[warn\]|\[warning\]" /var/log/tor/notices.log 2>/dev/null || echo 0)
fi

# Parse bandwidth from state file
if [ -f /var/lib/tor/state ]; then
  BANDWIDTH_READ=$(grep "^AccountingBytesReadInterval" /var/lib/tor/state 2>/dev/null | awk '{print $2}' || echo 0)
  BANDWIDTH_WRITE=$(grep "^AccountingBytesWrittenInterval" /var/lib/tor/state 2>/dev/null | awk '{print $2}' || echo 0)
fi

# Get version info
if [ -f /build-info.txt ]; then
  VERSION_INFO=$(head -1 /build-info.txt 2>/dev/null | cut -d: -f2- | tr -d ' ' || echo "unknown")
fi

# Generate timestamp
TIMESTAMP=$(date +%s)000

# Output based on format
case "$METRICS_FORMAT" in
  json)
    cat << EOF
{
  "timestamp": $TIMESTAMP,
  "metrics": {
    "up": $RELAY_UP,
    "bootstrap_percent": $BOOTSTRAP_PERCENT,
    "reachable": $IS_REACHABLE,
    "uptime_seconds": $UPTIME_SECONDS,
    "errors_total": $ERROR_COUNT,
    "warnings_total": $WARNING_COUNT,
    "bandwidth_read_bytes": $BANDWIDTH_READ,
    "bandwidth_write_bytes": $BANDWIDTH_WRITE,
    "circuits_total": $CIRCUITS_ACTIVE
  },
  "labels": {
    "nickname": "$NICKNAME",
    "fingerprint": "$FINGERPRINT",
    "version": "$VERSION_INFO"
  }
}
EOF
    ;;
    
  *)
    # Prometheus format (default)
    echo "# HELP ${METRICS_PREFIX}_up Tor relay status (1 = up, 0 = down)"
    echo "# TYPE ${METRICS_PREFIX}_up gauge"
    if [ "$INCLUDE_LABELS" = "true" ] && [ -n "$NICKNAME" ]; then
      echo "${METRICS_PREFIX}_up{nickname=\"$NICKNAME\",fingerprint=\"$FINGERPRINT\"} $RELAY_UP"
    else
      echo "${METRICS_PREFIX}_up $RELAY_UP"
    fi
    
    echo "# HELP ${METRICS_PREFIX}_bootstrap_percent Bootstrap completion percentage"
    echo "# TYPE ${METRICS_PREFIX}_bootstrap_percent gauge"
    echo "${METRICS_PREFIX}_bootstrap_percent $BOOTSTRAP_PERCENT"
    
    echo "# HELP ${METRICS_PREFIX}_reachable Relay reachability status"
    echo "# TYPE ${METRICS_PREFIX}_reachable gauge"
    echo "${METRICS_PREFIX}_reachable $IS_REACHABLE"
    
    echo "# HELP ${METRICS_PREFIX}_uptime_seconds Relay process uptime in seconds"
    echo "# TYPE ${METRICS_PREFIX}_uptime_seconds counter"
    echo "${METRICS_PREFIX}_uptime_seconds $UPTIME_SECONDS"
    
    echo "# HELP ${METRICS_PREFIX}_errors_total Total number of errors in log"
    echo "# TYPE ${METRICS_PREFIX}_errors_total counter"
    echo "${METRICS_PREFIX}_errors_total $ERROR_COUNT"
    
    echo "# HELP ${METRICS_PREFIX}_warnings_total Total number of warnings in log"
    echo "# TYPE ${METRICS_PREFIX}_warnings_total counter"
    echo "${METRICS_PREFIX}_warnings_total $WARNING_COUNT"
    
    echo "# HELP ${METRICS_PREFIX}_bandwidth_read_bytes Total bytes read"
    echo "# TYPE ${METRICS_PREFIX}_bandwidth_read_bytes counter"
    echo "${METRICS_PREFIX}_bandwidth_read_bytes $BANDWIDTH_READ"
    
    echo "# HELP ${METRICS_PREFIX}_bandwidth_write_bytes Total bytes written"
    echo "# TYPE ${METRICS_PREFIX}_bandwidth_write_bytes counter"
    echo "${METRICS_PREFIX}_bandwidth_write_bytes $BANDWIDTH_WRITE"
    
    echo "# HELP ${METRICS_PREFIX}_circuits_total Active circuit count"
    echo "# TYPE ${METRICS_PREFIX}_circuits_total gauge"
    echo "${METRICS_PREFIX}_circuits_total $CIRCUITS_ACTIVE"
    
    echo "# HELP ${METRICS_PREFIX}_info Relay information"
    echo "# TYPE ${METRICS_PREFIX}_info gauge"
    echo "${METRICS_PREFIX}_info{nickname=\"$NICKNAME\",version=\"$VERSION_INFO\"} 1"
    ;;
esac