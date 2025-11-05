#!/bin/sh
# docker-entrypoint.sh - Tor Guard Relay initialization and process management
# Handles startup sequence: preflight checks → configuration validation → health monitoring →
# metrics exposure → main Tor process, with proper signal handling and background process management

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

# 🔒 NEW: Global PID tracking for cleanup
TOR_PID=""
METRICS_PID=""
HEALTH_PID=""

# 🔒 NEW: Improved signal handler with comprehensive cleanup
trap 'cleanup_and_exit' SIGTERM SIGINT

cleanup_and_exit() {
  echo ""
  echo "🛑 Shutdown signal received. Stopping all services..."
  
  # Kill background services first (reverse order of startup)
  if [ -n "$HEALTH_PID" ] && kill -0 "$HEALTH_PID" 2>/dev/null; then
    echo "   Stopping health monitor (PID: $HEALTH_PID)..."
    kill -TERM "$HEALTH_PID" 2>/dev/null || true
    # Give it a moment to exit gracefully
    sleep 1
    # Force kill if still running
    kill -9 "$HEALTH_PID" 2>/dev/null || true
  fi
  
  if [ -n "$METRICS_PID" ] && kill -0 "$METRICS_PID" 2>/dev/null; then
    echo "   Stopping metrics service (PID: $METRICS_PID)..."
    kill -TERM "$METRICS_PID" 2>/dev/null || true
    sleep 1
    kill -9 "$METRICS_PID" 2>/dev/null || true
  fi
  
  # Finally, stop Tor relay
  if [ -n "$TOR_PID" ] && kill -0 "$TOR_PID" 2>/dev/null; then
    echo "   Stopping Tor relay (PID: $TOR_PID)..."
    kill -TERM "$TOR_PID" 2>/dev/null || true
    # Wait for Tor to shut down gracefully (up to 30 seconds)
    wait "$TOR_PID" 2>/dev/null || true
  fi
  
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
  echo "   🗂️  Created required directories and /tmp ensured"
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
    echo "   📝 Using minimal placeholder (configure before use)"
    echo "# Placeholder - mount your relay.conf at $TOR_CONFIG" > "$TOR_CONFIG"
  else
    echo "   ✓ Configuration found"
  fi
  echo ""
}

# Validation phase: Configuration and preflight checks
validation_phase() {
  echo "🧩 Phase 4: Configuration Validation"

  # Ensure Tor binary is accessible
  if ! command -v tor >/dev/null 2>&1; then
    echo "❌ ERROR: Tor binary not found in PATH."
    echo "   Verify that Tor is installed and executable."
    exit 1
  fi

  TOR_VERSION=$(tor --version | head -n1 || echo "unknown")
  echo "   🧱 Tor Version: $TOR_VERSION"

  # Check configuration presence and size
  if [ ! -f "$TOR_CONFIG" ]; then
    echo "⚠️  No configuration file found at $TOR_CONFIG"
    echo "   📝 Mount your relay.conf or torrc before running."
    exit 1
  elif [ ! -s "$TOR_CONFIG" ]; then
    echo "⚠️  Configuration file exists but is empty!"
  else
    echo "   ✓ Configuration file detected"
  fi

  # Show config preview in debug mode
  if [ "${DEBUG:-false}" = "true" ]; then
    echo "   🧩 Config Preview (first 10 lines):"
    head -n 10 "$TOR_CONFIG" | sed 's/^/   /'
    echo ""
  fi

  echo "   🔎 Validating syntax..."
  if ! tor --verify-config -f "$TOR_CONFIG" >/tmp/tor-verify.log 2>&1; then
    echo ""
    echo "❌ ERROR: Tor configuration validation failed!"
    echo "   Review /tmp/tor-verify.log for details."
    if [ "${DEBUG:-false}" = "true" ]; then
      echo ""
      echo "   🧩 Error Output:"
      sed 's/^/   /' /tmp/tor-verify.log | head -n 15
    fi
    echo ""
    exit 1
  fi
  echo "   ✓ Configuration is valid"
  echo ""

  echo "🔍 Phase 5: Preflight Diagnostics"
  echo "   🌐 Checking basic network connectivity..."
  if ping -c1 -W2 ipv4.icanhazip.com >/dev/null 2>&1; then
    echo "   ✓ IPv4 connectivity OK"
  else
    echo "   ⚠️ IPv4 connectivity unavailable"
  fi

  if ping6 -c1 -W2 ipv6.icanhazip.com >/dev/null 2>&1; then
    echo "   ✓ IPv6 connectivity OK"
  else
    echo "   ⚠️ IPv6 connectivity unavailable"
  fi

  # Extended diagnostics via net-check (with timeout)
  if [ "${ENABLE_NET_CHECK:-false}" = "true" ] && command -v net-check >/dev/null 2>&1; then
    echo ""
    echo "   Running extended network diagnostics..."
    if timeout 15s net-check --text 2>&1 | sed 's/^/   /'; then
      echo "   ✓ Network diagnostics completed successfully"
    else
      echo "   ⚠️ Network diagnostics encountered warnings or timeouts"
    fi
  else
    echo "   ⏭️  Skipping extended network diagnostics (ENABLE_NET_CHECK=false)"
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
    echo "   ⚠️  No build-info.txt found, version unknown."
  fi

  if [ "${DEBUG:-false}" = "true" ]; then
    echo ""
    echo "   🧩 Environment Snapshot:"
    echo "   • User: $(whoami)"
    echo "   • UID:GID: $(id -u):$(id -g)"
    echo "   • Hostname: $(hostname)"
    echo "   • Date: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    echo "   • Arch: $(uname -m)"
  fi
  echo ""
}

# 🔒 IMPROVED: Metrics service with PID tracking
start_metrics_service() {
  if [ "$ENABLE_METRICS" != "true" ]; then
    echo "📊 Phase 7: Metrics Service disabled (ENABLE_METRICS=false)"
    echo ""
    return 0
  fi

  echo "📊 Phase 7: Starting Metrics Service"
  if ! command -v metrics-http &>/dev/null; then
    echo "   ⚠️  metrics-http tool not found, skipping."
    echo ""
    return 0
  fi

  # Start metrics service and capture PID
  metrics-http "$METRICS_PORT" &
  METRICS_PID=$!
  
  # Verify process started successfully
  sleep 1
  if kill -0 "$METRICS_PID" 2>/dev/null; then
    echo "   ✓ Metrics service active on port $METRICS_PORT (PID: $METRICS_PID)"
  else
    echo "   ⚠️  Metrics service failed to start"
    METRICS_PID=""
  fi
  echo ""
}

# 🔒 IMPROVED: Health check service with PID tracking
start_health_service() {
  if [ "$ENABLE_HEALTH_CHECK" != "true" ]; then
    echo "💚 Phase 8: Health Check Service disabled (ENABLE_HEALTH_CHECK=false)"
    echo ""
    return 0
  fi

  echo "💚 Phase 8: Starting Health Check Service"
  
  # Start health monitor in background and capture PID
  (
    while true; do
      sleep 30
      if command -v health &>/dev/null; then
        HEALTH_JSON=$(health 2>&1 || echo '{}')
        HEALTH_STATUS=$(echo "$HEALTH_JSON" | grep -o '"status":"[^"]*"' | cut -d'"' -f4 || echo "unknown")
        if [ "$HEALTH_STATUS" = "error" ]; then
          echo "⚠️  Health check failed: $HEALTH_STATUS"
        elif [ "${DEBUG:-false}" = "true" ]; then
          echo "   🩺 Health OK at $(date -u +"%H:%M:%S")"
        fi
      fi
    done
  ) &
  HEALTH_PID=$!
  
  # Verify process started successfully
  sleep 1
  if kill -0 "$HEALTH_PID" 2>/dev/null; then
    echo "   ✓ Health monitor active (PID: $HEALTH_PID)"
  else
    echo "   ⚠️  Health monitor failed to start"
    HEALTH_PID=""
  fi
  echo ""
}

# Main startup message
startup_message() {
  echo "🚀 Phase 9: Launching Tor Relay"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "💡 Available Diagnostic Commands:"
  echo "   docker exec <container> status        - Full health report"
  echo "   docker exec <container> fingerprint   - Relay fingerprint"
  echo "   docker exec <container> view-logs     - Stream Tor logs"
  echo "   docker exec <container> health        - JSON health check"
  if [ "$ENABLE_METRICS" = "true" ]; then
    echo "   curl http://<host>:$METRICS_PORT/metrics   - Prometheus metrics"
  fi
  echo ""
  echo "🧅 Tor relay starting..."
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
}

# 🔒 IMPROVED: Tor process launcher with PID tracking
run_tor() {
  # Start Tor in background so we can track its PID
  "$@" &
  TOR_PID=$!
  
  echo "   ✓ Tor relay started (PID: $TOR_PID)"
  echo ""
  
  # Wait for Tor process to complete
  # This blocks until Tor exits or signal is received
  wait "$TOR_PID"
  
  # If we reach here, Tor exited on its own (not from signal)
  TOR_EXIT_CODE=$?
  
  echo ""
  echo "🛑 Tor process exited with code: $TOR_EXIT_CODE"
  
  # Cleanup background services
  cleanup_and_exit
}

# Main execution flow
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