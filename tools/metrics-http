#!/bin/sh
# metrics-http - HTTP server for Prometheus metrics endpoint
# Usage: metrics-http [--port PORT] [--help]

set -e

# Configuration
VERSION="1.1.1"
METRICS_PORT="${METRICS_PORT:-9052}"
METRICS_BIND="${METRICS_BIND:-127.0.0.1}"  # ⚠️ CHANGED: Secure default
METRICS_PATH="${METRICS_PATH:-/metrics}"
ENABLE_METRICS="${ENABLE_METRICS:-true}"
RESPONSE_TIMEOUT="${RESPONSE_TIMEOUT:-10}"
MAX_CONNECTIONS="${MAX_CONNECTIONS:-10}"  # 🔒 NEW: Rate limiting

# Trap for clean exit
trap 'cleanup' INT TERM

cleanup() {
  echo ""
  echo "🛑 Metrics HTTP server shutting down..."
  exit 0
}

# Parse arguments
for arg in "$@"; do
  case "$arg" in
    --help|-h)
      cat << EOF
🌐 Tor-Guard-Relay Metrics HTTP Server v${VERSION}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

USAGE:
    metrics-http [OPTIONS]

OPTIONS:
    --port PORT     Listen port (default: 9052)
    --bind ADDR     Bind address (default: 127.0.0.1)
    --path PATH     Metrics path (default: /metrics)
    --daemon        Run as daemon
    --help, -h      Show this help message

ENVIRONMENT VARIABLES:
    METRICS_PORT         Port to listen on (default: 9052)
    METRICS_BIND         Address to bind (default: 127.0.0.1)
    METRICS_PATH         URL path for metrics (default: /metrics)
    ENABLE_METRICS       Enable metrics server (true/false)
    RESPONSE_TIMEOUT     Response timeout in seconds
    MAX_CONNECTIONS      Max concurrent connections (default: 10)

⚠️  SECURITY NOTICE:
    Default binding is 127.0.0.1 (localhost only).
    To expose externally for Prometheus scraping, explicitly set:
      METRICS_BIND=0.0.0.0
    
    ⚠️  WARNING: Metrics may contain sensitive relay information!
    Recommendations for production:
      1. Use network-level access controls (firewall rules)
      2. Deploy Prometheus in same network/VPN
      3. Use TLS termination proxy (nginx with client certs)
      4. Never expose directly to public internet

ENDPOINTS:
    http://localhost:9052/metrics    Prometheus metrics
    http://localhost:9052/health     Health check endpoint
    http://localhost:9052/           Status page

PROMETHEUS CONFIG:
    scrape_configs:
      - job_name: 'tor-relay'
        static_configs:
          - targets: ['relay:9052']
        metrics_path: '/metrics'
        scrape_interval: 30s

DOCKER INTEGRATION:
    # For localhost access only (secure):
    ports:
      - "127.0.0.1:9052:9052"
    
    # For Prometheus in same Docker network:
    networks:
      - monitoring
    # No port exposure needed!
    
    # For external Prometheus (use with caution):
    environment:
      - METRICS_BIND=0.0.0.0
    ports:
      - "9052:9052"

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
      exit 0
      ;;
    --port)
      shift
      METRICS_PORT="$1"
      shift
      ;;
    --bind)
      shift
      METRICS_BIND="$1"
      shift
      ;;
    --path)
      shift
      METRICS_PATH="$1"
      shift
      ;;
    --daemon)
      DAEMON_MODE="true"
      ;;
    -*) 
      echo "❌ Unknown option: $arg"
      echo "💡 Use --help for usage information"
      exit 2
      ;;
  esac
done

# Check if metrics are enabled
if [ "$ENABLE_METRICS" != "true" ]; then
  echo "📊 Metrics HTTP server is disabled"
  echo "💡 Set ENABLE_METRICS=true to enable"
  exit 0
fi

# Security warning for external binding
if [ "$METRICS_BIND" = "0.0.0.0" ]; then
  echo "⚠️  WARNING: Metrics server is bound to 0.0.0.0 (all interfaces)"
  echo "⚠️  Relay metrics may contain sensitive information!"
  echo "⚠️  Ensure proper firewall rules or use a secure network."
  echo ""
fi

# Check for netcat
if ! command -v nc > /dev/null 2>&1; then
  echo "❌ Error: netcat (nc) is required but not installed"
  echo "💡 Install with: apk add netcat-openbsd"
  exit 1
fi

# Connection counter for basic rate limiting
CONNECTION_COUNT=0
LAST_RESET=$(date +%s)

# Function to generate HTTP response
generate_response() {
  REQUEST_PATH="$1"
  
  case "$REQUEST_PATH" in
    "$METRICS_PATH")
      # Generate metrics
      METRICS_OUTPUT=$(/usr/local/bin/metrics 2>/dev/null || echo "# Error generating metrics")
      CONTENT_LENGTH=$(echo -n "$METRICS_OUTPUT" | wc -c)
      
      cat << EOF
HTTP/1.1 200 OK
Content-Type: text/plain; version=0.0.4
Content-Length: $CONTENT_LENGTH
Cache-Control: no-cache
Connection: close
X-Content-Type-Options: nosniff

$METRICS_OUTPUT
EOF
      ;;
      
    "/health")
      # Health check endpoint
      HEALTH_JSON=$(/usr/local/bin/health --json 2>/dev/null || echo '{"status":"error"}')
      CONTENT_LENGTH=$(echo -n "$HEALTH_JSON" | wc -c)
      
      cat << EOF
HTTP/1.1 200 OK
Content-Type: application/json
Content-Length: $CONTENT_LENGTH
Cache-Control: no-cache
Connection: close

$HEALTH_JSON
EOF
      ;;
      
    "/")
      # Status page
      HTML_CONTENT="<!DOCTYPE html>
<html>
<head>
    <title>Tor Relay Metrics</title>
    <meta charset=\"utf-8\">
    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">
    <style>
        body { font-family: sans-serif; margin: 40px; background: #f5f5f5; }
        h1 { color: #7d4698; }
        .status { padding: 20px; background: white; border-radius: 8px; margin: 20px 0; }
        .endpoint { background: #f0f0f0; padding: 10px; margin: 10px 0; border-radius: 4px; }
        a { color: #7d4698; text-decoration: none; }
        a:hover { text-decoration: underline; }
        .warning { background: #fff3cd; border-left: 4px solid #ffc107; padding: 15px; margin: 20px 0; }
    </style>
</head>
<body>
    <h1>🧅 Tor Relay Metrics Server</h1>
    
    <div class=\"warning\">
        <strong>⚠️ Security Notice:</strong> This server exposes relay metrics. 
        Ensure it's only accessible from trusted networks (Prometheus, monitoring systems).
    </div>
    
    <div class=\"status\">
        <h2>Available Endpoints:</h2>
        <div class=\"endpoint\">
            📊 <a href=\"$METRICS_PATH\">$METRICS_PATH</a> - Prometheus metrics
        </div>
        <div class=\"endpoint\">
            💚 <a href=\"/health\">/health</a> - Health check (JSON)
        </div>
        <div class=\"endpoint\">
            🏠 <a href=\"/\">/</a> - This status page
        </div>
    </div>
    
    <div class=\"status\">
        <h2>Configuration:</h2>
        <p><strong>Bind Address:</strong> $METRICS_BIND</p>
        <p><strong>Port:</strong> $METRICS_PORT</p>
        <p><strong>Version:</strong> $VERSION</p>
        <p><strong>Rate Limit:</strong> $MAX_CONNECTIONS connections/window</p>
    </div>
    
    <div class=\"status\">
        <h2>Integration:</h2>
        <p>Add to your <code>prometheus.yml</code>:</p>
        <pre style=\"background: #f0f0f0; padding: 15px; border-radius: 4px; overflow-x: auto;\">
scrape_configs:
  - job_name: 'tor-relay'
    static_configs:
      - targets: ['$METRICS_BIND:$METRICS_PORT']
    metrics_path: '$METRICS_PATH'
    scrape_interval: 30s</pre>
    </div>
</body>
</html>"
      
      CONTENT_LENGTH=$(echo -n "$HTML_CONTENT" | wc -c)
      
      cat << EOF
HTTP/1.1 200 OK
Content-Type: text/html; charset=utf-8
Content-Length: $CONTENT_LENGTH
Cache-Control: no-cache
Connection: close

$HTML_CONTENT
EOF
      ;;
      
    *)
      # 404 Not Found
      ERROR_MSG="404 - Not Found"
      CONTENT_LENGTH=$(echo -n "$ERROR_MSG" | wc -c)
      
      cat << EOF
HTTP/1.1 404 Not Found
Content-Type: text/plain
Content-Length: $CONTENT_LENGTH
Connection: close

$ERROR_MSG
EOF
      ;;
  esac
}

# Start server
echo "📊 Starting Tor Relay Metrics HTTP Server v${VERSION}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🌐 Listening on: http://$METRICS_BIND:$METRICS_PORT"
echo "📍 Metrics path: $METRICS_PATH"
echo "🔒 Max connections: $MAX_CONNECTIONS/window"
echo "💡 Press Ctrl+C to stop"
echo ""

# Main server loop with connection limiting
while true; do
  # Reset counter every 60 seconds
  CURRENT_TIME=$(date +%s)
  if [ $((CURRENT_TIME - LAST_RESET)) -ge 60 ]; then
    CONNECTION_COUNT=0
    LAST_RESET=$CURRENT_TIME
  fi
  
  # Basic rate limiting
  if [ "$CONNECTION_COUNT" -ge "$MAX_CONNECTIONS" ]; then
    sleep 1
    continue
  fi
  
  # Wait for connection and parse request
  REQUEST=$(echo "" | nc -l -p "$METRICS_PORT" -s "$METRICS_BIND" -w "$RESPONSE_TIMEOUT" 2>/dev/null | head -1)
  
  if [ -n "$REQUEST" ]; then
    CONNECTION_COUNT=$((CONNECTION_COUNT + 1))
    
    # Extract path from request
    REQUEST_PATH=$(echo "$REQUEST" | awk '{print $2}')
    
    # Log request (without sensitive info)
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $REQUEST_PATH ($CONNECTION_COUNT/$MAX_CONNECTIONS)"
    
    # Generate and send response in background
    (generate_response "$REQUEST_PATH" | nc -l -p "$METRICS_PORT" -s "$METRICS_BIND" -w 1 > /dev/null 2>&1) &
  fi
done