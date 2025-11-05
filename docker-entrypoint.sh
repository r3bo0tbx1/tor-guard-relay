#!/bin/sh
# docker-entrypoint.sh - Tor Guard Relay initialization and process management
# 🆕 v1.1 - Smart log monitoring: triggers diagnostics after bandwidth self-test

set -e

# Configuration
readonly TOR_CONFIG="${TOR_CONFIG:-/etc/tor/torrc}"
readonly TOR_DATA_DIR="${TOR_DATA_DIR:-/var/lib/tor}"
readonly TOR_LOG_DIR="${TOR_LOG_DIR:-/var/log/tor}"
readonly METRICS_PORT="${METRICS_PORT:-9035}"
readonly HEALTH_PORT="${HEALTH_PORT:-9036}"
readonly ENABLE_METRICS="${ENABLE_METRICS:-false}"
readonly ENABLE_HEALTH_CHECK="${ENABLE_HEALTH_CHECK:-true}"
readonly ENABLE_NET_CHECK="${ENABLE_NET_CHECK:-false}"

# Global PID tracking for cleanup
TOR_PID=""
METRICS_PID=""
HEALTH_PID=""
LOG_MONITOR_PID=""

# Signal handler with comprehensive cleanup
trap 'cleanup_and_exit' SIGTERM SIGINT

cleanup_and_exit() {
  echo ""
  echo "🛑 Shutdown signal received. Stopping all services..."
  
  # Kill background services (reverse order of startup)
  [ -n "$LOG_MONITOR_PID" ] && kill -0 "$LOG_MONITOR_PID" 2>/dev/null && {
    echo "   Stopping log monitor (PID: $LOG_MONITOR_PID)..."
    kill -TERM "$LOG_MONITOR_PID" 2>/dev/null || true
    sleep 1
    kill -9 "$LOG_MONITOR_PID" 2>/dev/null || true
  }
  
  [ -n "$HEALTH_PID" ] && kill -0 "$HEALTH_PID" 2>/dev/null && {
    echo "   Stopping health monitor (PID: $HEALTH_PID)..."
    kill -TERM "$HEALTH_PID" 2>/dev/null || true
    sleep 1
    kill -9 "$HEALTH_PID" 2>/dev/null || true
  }
  
  [ -n "$METRICS_PID" ] && kill -0 "$METRICS_PID" 2>/dev/null && {
    echo "   Stopping metrics service (PID: $METRICS_PID)..."
    kill -TERM "$METRICS_PID" 2>/dev/null || true
    sleep 1
    kill -9 "$METRICS_PID" 2>/dev/null || true
  }
  
  # Finally, stop Tor relay
  [ -n "$TOR_PID" ] && kill -0 "$TOR_PID" 2>/dev/null && {
    echo "   Stopping Tor relay (PID: $TOR_PID)..."
    kill -TERM "$TOR_PID" 2>/dev/null || true
    wait "$TOR_PID" 2>/dev/null || true
  }
  
  echo "✅ All services stopped cleanly."
  exit 0
}

# Startup phase: Initialization
startup_phase_init() {
  echo "🧅 Tor Guard Relay - Initialization Sequence"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  
  echo "🔧 Phase 1: Directory Structure"
  mkdir -p "$TOR_DATA_DIR" "$TOR_LOG_DIR" /run/tor /tmp
  echo "   🗂️  Created required directories"
  echo "   💽 Available disk space:"
  df -h "$TOR_DATA_DIR" | tail -n 1 | awk '{printf "   • %s used of %s (%s available)\n", $3, $2, $4}'
  echo ""
  
  echo "🔐 Phase 2: Permission Hardening"
  chown -R tor:tor "$TOR_DATA_DIR" "$TOR_LOG_DIR" /run/tor 2>/dev/null || true
  chmod 700 "$TOR_DATA_DIR"
  chmod 755 "$TOR_LOG_DIR"
  echo "   ✓ Permissions set securely"
  
  echo "📁 Phase 3: Configuration Detection"
  if [ ! -f "$TOR_CONFIG" ]; then
    echo "   ⚠️  No configuration found at $TOR_CONFIG"
    echo "   📝 Using minimal placeholder"
    echo "# Placeholder - mount your relay.conf at $TOR_CONFIG" > "$TOR_CONFIG"
  else
    echo "   ✓ Configuration found"
  fi
  echo ""
}

# Validation phase
validation_phase() {
  echo "🧩 Phase 4: Configuration Validation"

  if ! command -v tor >/dev/null 2>&1; then
    echo "❌ ERROR: Tor binary not found in PATH."
    exit 1
  fi

  TOR_VERSION=$(tor --version | head -n1 || echo "unknown")
  echo "   🧱 Tor Version: $TOR_VERSION"

  if [ ! -f "$TOR_CONFIG" ]; then
    echo "⚠️  No configuration file found at $TOR_CONFIG"
    exit 1
  elif [ ! -s "$TOR_CONFIG" ]; then
    echo "⚠️  Configuration file exists but is empty!"
  else
    echo "   ✓ Configuration file detected"
  fi

  [ "${DEBUG:-false}" = "true" ] && {
    echo "   🧩 Config Preview (first 10 lines):"
    head -n 10 "$TOR_CONFIG" | sed 's/^/   /'
    echo ""
  }

  echo "   🔎 Validating syntax..."
  if ! tor --verify-config -f "$TOR_CONFIG" >/tmp/tor-verify.log 2>&1; then
    echo ""
    echo "❌ ERROR: Tor configuration validation failed!"
    [ "${DEBUG:-false}" = "true" ] && {
      echo "   🧩 Error Output:"
      sed 's/^/   /' /tmp/tor-verify.log | head -n 15
    }
    exit 1
  fi
  echo "   ✓ Configuration is valid"
  echo ""

  echo "🔍 Phase 5: Preflight Diagnostics"
  echo "   🌐 Checking basic network connectivity..."
  
  ping -c1 -W2 ipv4.icanhazip.com >/dev/null 2>&1 && echo "   ✓ IPv4 connectivity OK" || echo "   ⚠️ IPv4 unavailable"
  ping6 -c1 -W2 ipv6.icanhazip.com >/dev/null 2>&1 && echo "   ✓ IPv6 connectivity OK" || echo "   ⚠️ IPv6 unavailable"

  # Only basic checks at startup - Tor-specific checks wait for self-test
  if [ "${ENABLE_NET_CHECK:-false}" = "true" ] && command -v net-check >/dev/null 2>&1; then
    echo ""
    echo "   Running basic network diagnostics..."
    echo "   ℹ️  (Full diagnostics after Tor bandwidth self-test)"
    
    NET_CHECK_OUTPUT=$(timeout 15s net-check --text 2>&1 || true)
    echo "$NET_CHECK_OUTPUT" | grep -E "🔌 IPv4:|🔌 IPv6:|🔍 DNS:" | sed 's/^/   /' || true
    echo "   ✓ Basic network checks complete"
  else
    echo "   ⏭️  Extended diagnostics disabled (ENABLE_NET_CHECK=false)"
  fi

  echo ""
}

# Build info phase
buildinfo_phase() {
  echo "📦 Phase 6: Build Information"
  if [ -f /build-info.txt ]; then
    echo "   🔖 Build metadata found:"
    cat /build-info.txt | sed 's/^/   /'
  else
    echo "   ⚠️  No build-info.txt found"
  fi

  [ "${DEBUG:-false}" = "true" ] && {
    echo ""
    echo "   🧩 Environment:"
    echo "   • User: $(whoami)"
    echo "   • UID:GID: $(id -u):$(id -g)"
    echo "   • Date: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  }
  echo ""
}

# Metrics service
start_metrics_service() {
  [ "$ENABLE_METRICS" != "true" ] && {
    echo "📊 Phase 7: Metrics Service disabled"
    echo ""
    return 0
  }

  echo "📊 Phase 7: Starting Metrics Service"
  command -v metrics-http &>/dev/null || {
    echo "   ⚠️  metrics-http not found"
    echo ""
    return 0
  }

  metrics-http "$METRICS_PORT" &
  METRICS_PID=$!
  
  sleep 1
  kill -0 "$METRICS_PID" 2>/dev/null && echo "   ✓ Metrics active on port $METRICS_PORT" || {
    echo "   ⚠️  Metrics failed to start"
    METRICS_PID=""
  }
  echo ""
}

# Health check service
start_health_service() {
  [ "$ENABLE_HEALTH_CHECK" != "true" ] && {
    echo "💚 Phase 8: Health Check disabled"
    echo ""
    return 0
  }

  echo "💚 Phase 8: Starting Health Check Service"
  
  (
    while true; do
      sleep 30
      command -v health &>/dev/null && {
        HEALTH_JSON=$(health 2>&1 || echo '{}')
        HEALTH_STATUS=$(echo "$HEALTH_JSON" | grep -o '"status":"[^"]*"' | cut -d'"' -f4 || echo "unknown")
        [ "$HEALTH_STATUS" = "error" ] && echo "⚠️  Health check failed"
        [ "${DEBUG:-false}" = "true" ] && echo "   🩺 Health OK at $(date -u +"%H:%M:%S")"
      }
    done
  ) &
  HEALTH_PID=$!
  
  sleep 1
  kill -0 "$HEALTH_PID" 2>/dev/null && echo "   ✓ Health monitor active" || {
    echo "   ⚠️  Health monitor failed"
    HEALTH_PID=""
  }
  echo ""
}

# Startup message
startup_message() {
  echo "🚀 Phase 9: Launching Tor Relay"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "💡 Available Diagnostic Commands:"
  echo "   docker exec <container> status        - Full health report"
  echo "   docker exec <container> fingerprint   - Relay fingerprint"
  echo "   docker exec <container> view-logs     - Stream Tor logs"
  [ "$ENABLE_NET_CHECK" = "true" ] && echo "   docker exec <container> net-check     - Network diagnostics"
  [ "$ENABLE_METRICS" = "true" ] && echo "   curl http://<host>:$METRICS_PORT/metrics   - Prometheus metrics"
  echo ""
  echo "🧅 Tor relay starting..."
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
}

# 🆕 SMART: Watch for bandwidth self-test completion, then run diagnostics
start_log_monitor() {
  [ "${ENABLE_NET_CHECK:-false}" != "true" ] && return 0
  command -v net-check >/dev/null 2>&1 || return 0

  (
    # Wait for Tor to complete bandwidth self-test
    # This is much smarter than a fixed delay!
    
    # Try to find Tor's log file
    LOG_FILE=""
    for log in "$TOR_LOG_DIR/notices.log" "/var/log/tor/notices.log" "$TOR_LOG_DIR/tor.log"; do
      [ -f "$log" ] && { LOG_FILE="$log"; break; }
    done

    # Maximum wait time: 10 minutes
    MAX_WAIT=600
    ELAPSED=0
    
    if [ -n "$LOG_FILE" ]; then
      # Monitor log file for the magic message
      while [ $ELAPSED -lt $MAX_WAIT ]; do
        if grep -q "Performing bandwidth self-test.*done" "$LOG_FILE" 2>/dev/null || \
           grep -q "Self-testing indicates your ORPort is reachable" "$LOG_FILE" 2>/dev/null; then
          break
        fi
        sleep 5
        ELAPSED=$((ELAPSED + 5))
      done
    else
      # Fallback: wait 3 minutes if we can't find log file
      sleep 180
    fi

    # Give Tor 10 more seconds to stabilize after self-test
    sleep 10

    # Now run full diagnostics - Tor is ready!
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🔍 Post-Bootstrap Network Diagnostics"
    echo "   Triggered by: Bandwidth self-test completion"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    net-check --text || true
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
  ) &
  LOG_MONITOR_PID=$!
}

# Tor process launcher
run_tor() {
  # Start Tor in background
  "$@" &
  TOR_PID=$!
  
  echo "   ✓ Tor relay started (PID: $TOR_PID)"
  echo ""
  
  # 🆕 Start smart log monitor
  start_log_monitor
  
  # Wait for Tor to exit
  wait "$TOR_PID"
  TOR_EXIT_CODE=$?
  
  echo ""
  echo "🛑 Tor process exited with code: $TOR_EXIT_CODE"
  
  cleanup_and_exit
}

# Main execution
main() {
  startup_phase_init
  validation_phase
  buildinfo_phase
  start_metrics_service
  start_health_service
  startup_message
  run_tor "$@"
}

main "$@"