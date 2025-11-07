#!/bin/sh
# metrics - Prometheus-compatible metrics exporter for Tor relay
# Usage: docker exec guard-relay metrics [--json|--help]

set -e

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
Usage:
    metrics [--prometheus|--json|--help]

Options:
    --prometheus    Output in Prometheus format (default)
    --json          Output metrics as JSON
    --help, -h      Show this message

Environment:
    METRICS_PREFIX     Prefix for metric names
    INCLUDE_LABELS     Include labels in output (true/false)
    METRICS_FORMAT     prometheus or json
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
      exit 0 ;;
    --prometheus) METRICS_FORMAT="prometheus" ;;
    --json) METRICS_FORMAT="json" ;;
    -*) echo "# ERROR: Unknown option: $arg" >&2; exit 2 ;;
  esac
done

# Initialize
RELAY_UP=0
BOOTSTRAP_PERCENT=0
IS_REACHABLE=0
UPTIME_SECONDS=0
ERROR_COUNT=0
WARNING_COUNT=0
BANDWIDTH_READ=0
BANDWIDTH_WRITE=0
CIRCUITS_ACTIVE=0
NICKNAME="unknown"
FINGERPRINT=""
VERSION_INFO="unknown"

# Identity
if [ -f /var/lib/tor/fingerprint ]; then
  NICKNAME=$(awk '{print $1}' /var/lib/tor/fingerprint 2>/dev/null || echo "unknown")
  FINGERPRINT=$(awk '{print $2}' /var/lib/tor/fingerprint 2>/dev/null || echo "")
fi

# Process state
if pgrep -x tor >/dev/null 2>&1; then
  RELAY_UP=1
  PID=$(pgrep -x tor | head -1)
  if [ -n "$PID" ] && [ -r /proc/$PID/stat ]; then
    START_TICKS=$(awk '{print $22}' /proc/$PID/stat)
    HZ=$(getconf CLK_TCK 2>/dev/null || echo 100)
    SYSTEM_UPTIME=$(awk '{print int($1)}' /proc/uptime)
    PROC_UPTIME=$((SYSTEM_UPTIME - START_TICKS / HZ))
    [ "$PROC_UPTIME" -ge 0 ] 2>/dev/null && UPTIME_SECONDS=$PROC_UPTIME || UPTIME_SECONDS=0
  fi
fi

# Logs
if [ -f /var/log/tor/notices.log ]; then
  BOOTSTRAP_LINE=$(grep "Bootstrapped" /var/log/tor/notices.log 2>/dev/null | tail -1)
  BOOTSTRAP_PERCENT=$(echo "$BOOTSTRAP_LINE" | grep -oE '[0-9]+' | tail -1)
  BOOTSTRAP_PERCENT=$(printf '%s' "$BOOTSTRAP_PERCENT" | tr -cd '0-9')
  [ -z "$BOOTSTRAP_PERCENT" ] && BOOTSTRAP_PERCENT=0

  grep -q "reachable from the outside" /var/log/tor/notices.log 2>/dev/null && IS_REACHABLE=1

  ERROR_COUNT=$(grep -ciE "\[err\]|\[error\]" /var/log/tor/notices.log 2>/dev/null || echo 0)
  WARNING_COUNT=$(grep -ciE "\[warn\]|\[warning\]" /var/log/tor/notices.log 2>/dev/null || echo 0)
fi

# Bandwidth
if [ -f /var/lib/tor/state ]; then
  BANDWIDTH_READ=$(awk '/AccountingBytesReadInterval/ {print $2}' /var/lib/tor/state | tail -1)
  BANDWIDTH_WRITE=$(awk '/AccountingBytesWrittenInterval/ {print $2}' /var/lib/tor/state | tail -1)
  BANDWIDTH_READ=${BANDWIDTH_READ:-0}
  BANDWIDTH_WRITE=${BANDWIDTH_WRITE:-0}
fi

# Version
if [ -f /build-info.txt ]; then
  VERSION_INFO=$(awk -F: '/Version/ {print $2}' /build-info.txt | tr -d ' ')
  VERSION_INFO=${VERSION_INFO:-unknown}
fi

# Timestamp (ms)
TIMESTAMP=$(($(date +%s) * 1000))

# Output
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
    echo "# HELP ${METRICS_PREFIX}_up Tor relay status (1 = up, 0 = down)"
    echo "# TYPE ${METRICS_PREFIX}_up gauge"
    [ "$INCLUDE_LABELS" = "true" ] && \
      echo "${METRICS_PREFIX}_up{nickname=\"$NICKNAME\",fingerprint=\"$FINGERPRINT\"} $RELAY_UP" || \
      echo "${METRICS_PREFIX}_up $RELAY_UP"

    echo "# HELP ${METRICS_PREFIX}_bootstrap_percent Bootstrap completion percentage"
    echo "# TYPE ${METRICS_PREFIX}_bootstrap_percent gauge"
    echo "${METRICS_PREFIX}_bootstrap_percent $BOOTSTRAP_PERCENT"

    echo "# HELP ${METRICS_PREFIX}_reachable Relay reachability status"
    echo "# TYPE ${METRICS_PREFIX}_reachable gauge"
    echo "${METRICS_PREFIX}_reachable $IS_REACHABLE"

    echo "# HELP ${METRICS_PREFIX}_uptime_seconds Relay process uptime in seconds"
    echo "# TYPE ${METRICS_PREFIX}_uptime_seconds counter"
    echo "${METRICS_PREFIX}_uptime_seconds $UPTIME_SECONDS"

    echo "# HELP ${METRICS_PREFIX}_errors_total Total number of errors"
    echo "# TYPE ${METRICS_PREFIX}_errors_total counter"
    echo "${METRICS_PREFIX}_errors_total $ERROR_COUNT"

    echo "# HELP ${METRICS_PREFIX}_warnings_total Total number of warnings"
    echo "# TYPE ${METRICS_PREFIX}_warnings_total counter"
    echo "${METRICS_PREFIX}_warnings_total $WARNING_COUNT"

    echo "# HELP ${METRICS_PREFIX}_bandwidth_read_bytes Bytes read during current interval"
    echo "# TYPE ${METRICS_PREFIX}_bandwidth_read_bytes counter"
    echo "${METRICS_PREFIX}_bandwidth_read_bytes $BANDWIDTH_READ"

    echo "# HELP ${METRICS_PREFIX}_bandwidth_write_bytes Bytes written during current interval"
    echo "# TYPE ${METRICS_PREFIX}_bandwidth_write_bytes counter"
    echo "${METRICS_PREFIX}_bandwidth_write_bytes $BANDWIDTH_WRITE"

    echo "# HELP ${METRICS_PREFIX}_circuits_total Active circuit count (placeholder)"
    echo "# TYPE ${METRICS_PREFIX}_circuits_total gauge"
    echo "${METRICS_PREFIX}_circuits_total $CIRCUITS_ACTIVE"

    echo "# HELP ${METRICS_PREFIX}_info Relay information"
    echo "# TYPE ${METRICS_PREFIX}_info gauge"
    echo "${METRICS_PREFIX}_info{nickname=\"$NICKNAME\",version=\"$VERSION_INFO\"} 1"
    ;;
esac
