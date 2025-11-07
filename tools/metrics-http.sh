#!/bin/sh
# metrics-http - HTTP server for Prometheus metrics endpoint

set -e

VERSION="1.1.0"
METRICS_PORT="${METRICS_PORT:-9052}"
METRICS_BIND="${METRICS_BIND:-127.0.0.1}"
METRICS_PATH="${METRICS_PATH:-/metrics}"
ENABLE_METRICS="${ENABLE_METRICS:-true}"
RESPONSE_TIMEOUT="${RESPONSE_TIMEOUT:-10}"
MAX_CONNECTIONS="${MAX_CONNECTIONS:-10}"

trap 'echo; echo "🛑 Metrics HTTP server shutting down..."; exit 0' INT TERM

if [ "$ENABLE_METRICS" != "true" ]; then
  echo "📊 Metrics HTTP server disabled"
  echo "💡 Set ENABLE_METRICS=true to enable"
  exit 0
fi

if ! command -v nc >/dev/null 2>&1; then
  echo "❌ Error: netcat (nc) not found"
  echo "💡 Install with: apk add netcat-openbsd"
  exit 1
fi

if [ "$METRICS_BIND" = "0.0.0.0" ]; then
  echo "⚠️  WARNING: Bound to all interfaces"
  echo "⚠️  Ensure firewall rules restrict access"
  echo ""
fi

echo "📊 Starting Tor Relay Metrics HTTP Server v${VERSION}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🌐 Listening on: http://$METRICS_BIND:$METRICS_PORT"
echo "📍 Metrics path: $METRICS_PATH"
echo "🔒 Max connections: $MAX_CONNECTIONS/min"
echo "💡 Press Ctrl+C to stop"
echo ""

CONNECTION_COUNT=0
LAST_RESET=$(date +%s)

handle_request() {
  REQ_PATH="$1"
  case "$REQ_PATH" in
    "$METRICS_PATH")
      METRICS=$(/usr/local/bin/metrics 2>/dev/null || echo "# Error generating metrics")
      printf "HTTP/1.1 200 OK\r\nContent-Type: text/plain; version=0.0.4\r\nConnection: close\r\n\r\n%s" "$METRICS"
      ;;
    "/health")
      HEALTH=$(/usr/local/bin/health --json 2>/dev/null || echo '{"status":"error"}')
      printf "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nConnection: close\r\n\r\n%s" "$HEALTH"
      ;;
    "/")
      HTML="<!DOCTYPE html><html><head><title>Tor Relay Metrics</title>
      <style>body{font-family:sans-serif;margin:40px;background:#f5f5f5}h1{color:#7d4698}
      .b{background:#fff;border-radius:8px;padding:20px;margin:20px 0}</style></head><body>
      <h1>🧅 Tor Relay Metrics Server</h1>
      <div class='b'><b>Metrics:</b> <a href='$METRICS_PATH'>$METRICS_PATH</a></div>
      <div class='b'><b>Health:</b> <a href='/health'>/health</a></div>
      <div class='b'><b>Version:</b> $VERSION</div>
      </body></html>"
      printf "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nConnection: close\r\n\r\n%s" "$HTML"
      ;;
    *)
      printf "HTTP/1.1 404 Not Found\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\n404 - Not Found"
      ;;
  esac
}

while true; do
  CURRENT=$(date +%s)
  [ $((CURRENT - LAST_RESET)) -ge 60 ] && CONNECTION_COUNT=0 && LAST_RESET=$CURRENT
  [ "$CONNECTION_COUNT" -ge "$MAX_CONNECTIONS" ] && sleep 1 && continue

  # Read request
  REQ_LINE=$(nc -lk -p "$METRICS_PORT" -s "$METRICS_BIND" -w "$RESPONSE_TIMEOUT" | head -n 1)
  if [ -n "$REQ_LINE" ]; then
    PATH_REQ=$(echo "$REQ_LINE" | awk '{print $2}')
    CONNECTION_COUNT=$((CONNECTION_COUNT + 1))
    echo "[$(date '+%H:%M:%S')] $PATH_REQ ($CONNECTION_COUNT/$MAX_CONNECTIONS)"
    handle_request "$PATH_REQ"
  fi
done
