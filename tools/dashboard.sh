#!/bin/sh
# dashboard - Web-based relay monitoring dashboard
# Usage: dashboard [--port PORT] [--help]

set -e

# Configuration
VERSION="1.1.0"
DASHBOARD_PORT="${DASHBOARD_PORT:-8080}"
DASHBOARD_BIND="${DASHBOARD_BIND:-127.0.0.1}"  # ⚠️ CHANGED: Secure default
ENABLE_DASHBOARD="${ENABLE_DASHBOARD:-true}"
REFRESH_INTERVAL="${REFRESH_INTERVAL:-10}"
MULTI_RELAY="${MULTI_RELAY:-false}"
MAX_CONNECTIONS="${MAX_CONNECTIONS:-5}"  # 🔒 NEW: Rate limiting
API_TOKEN="${API_TOKEN:-}"  # 🔒 NEW: API authentication token
LOG_RETENTION="${LOG_RETENTION:-100}"  # 📝 NEW: Number of log lines to keep

# Trap for clean exit
trap 'cleanup' INT TERM

cleanup() {
  echo ""
  echo "🛑 Dashboard shutting down..."
  # Clean up any temporary files
  [ -f "/tmp/dashboard.html" ] && rm -f "/tmp/dashboard.html"
  [ -f "/tmp/dashboard.pid" ] && rm -f "/tmp/dashboard.pid"
  exit 0
}

# Enhanced error handling
handle_error() {
  echo "❌ Error: $1" >&2
  logger -t "dashboard" "Error: $1"
  exit 1
}

# Parse arguments
for arg in "$@"; do
  case "$arg" in
    --help|-h)
      cat << EOF
🎨 Tor-Guard-Relay Web Dashboard v${VERSION}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

USAGE:
    dashboard [OPTIONS]

OPTIONS:
    --port PORT     Dashboard port (default: 8080)
    --bind ADDR     Bind address (default: 127.0.0.1)
    --refresh SEC   Auto-refresh interval (default: 10)
    --multi         Enable multi-relay support
    --token TOKEN   API authentication token
    --help, -h      Show this help message

ENVIRONMENT VARIABLES:
    DASHBOARD_PORT       Port to listen on
    DASHBOARD_BIND       Address to bind (default: 127.0.0.1)
    ENABLE_DASHBOARD     Enable dashboard (true/false)
    REFRESH_INTERVAL     Auto-refresh in seconds
    MULTI_RELAY         Multi-relay mode (true/false)
    MAX_CONNECTIONS     Max concurrent connections (default: 5)
    API_TOKEN           API authentication token
    LOG_RETENTION       Number of log lines to keep (default: 100)

⚠️  SECURITY NOTICE:
    Default binding is 127.0.0.1 (localhost only).
    To expose externally, explicitly set:
      DASHBOARD_BIND=0.0.0.0
    
    ⚠️  WARNING: External exposure without authentication is NOT recommended!
    Use a reverse proxy (nginx/caddy) with authentication for production.
    
    🔒 SECURITY: Set API_TOKEN to protect API endpoints:
      API_TOKEN=your-secure-token

FEATURES:
    • Real-time relay status monitoring
    • Bootstrap progress visualization
    • Network diagnostics display
    • Performance metrics graphs
    • Error/warning alerts
    • Multi-relay management (optional)
    • Mobile-responsive design
    • API authentication (with token)

ENDPOINTS:
    http://localhost:8080/          Main dashboard
    http://localhost:8080/api/status   JSON API
    http://localhost:8080/api/metrics  Metrics API
    http://localhost:8080/api/logs     Recent logs

DOCKER INTEGRATION:
    # For localhost access only (secure):
    ports:
      - "127.0.0.1:8080:8080"
    
    # For external access (use with caution):
    environment:
      - DASHBOARD_BIND=0.0.0.0
      - API_TOKEN=your-secure-token
    ports:
      - "8080:8080"

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
      exit 0
      ;;
    --port)
      shift
      DASHBOARD_PORT="$1"
      shift
      ;;
    --bind)
      shift
      DASHBOARD_BIND="$1"
      shift
      ;;
    --refresh)
      shift
      REFRESH_INTERVAL="$1"
      shift
      ;;
    --token)
      shift
      API_TOKEN="$1"
      shift
      ;;
    --multi)
      MULTI_RELAY="true"
      ;;
    -*) 
      echo "❌ Unknown option: $arg"
      echo "💡 Use --help for usage information"
      exit 2
      ;;
  esac
done

# Check if dashboard is enabled
if [ "$ENABLE_DASHBOARD" != "true" ]; then
  echo "🎨 Dashboard is disabled"
  echo "💡 Set ENABLE_DASHBOARD=true to enable"
  exit 0
fi

# Security warning for external binding
if [ "$DASHBOARD_BIND" = "0.0.0.0" ]; then
  echo "⚠️  WARNING: Dashboard is bound to 0.0.0.0 (all interfaces)"
  echo "⚠️  This exposes dashboard without authentication!"
  if [ -z "$API_TOKEN" ]; then
    echo "⚠️  Consider setting API_TOKEN for API protection."
  else
    echo "✅ API endpoints are protected with token authentication."
  fi
  echo "⚠️  Consider using a reverse proxy with authentication."
  echo ""
fi

# Check for netcat
if ! command -v nc > /dev/null 2>&1; then
  handle_error "netcat (nc) is required. Install with: apk add netcat-openbsd"
fi

# Connection counter (simple rate limiting)
CONNECTION_COUNT=0
echo $$ > /tmp/dashboard.pid

# Enhanced authentication check
check_api_auth() {
  AUTH_HEADER="$1"
  if [ -n "$API_TOKEN" ]; then
    # Extract token from Authorization header
    TOKEN=$(echo "$AUTH_HEADER" | sed -n 's/.*Bearer *\([^ ]*\).*/\1p')
    if [ "$TOKEN" != "$API_TOKEN" ]; then
      echo "HTTP/1.1 401 Unauthorized"
      echo "Content-Type: application/json"
      echo "Connection: close"
      echo ""
      echo '{"error":"Unauthorized"}'
      return 1
    fi
  fi
  return 0
}

# Function to generate dashboard HTML
generate_dashboard() {
  # Get current status
  STATUS_JSON=$(/usr/local/bin/status --json 2>/dev/null || echo '{}')
  HEALTH_JSON=$(/usr/local/bin/health --json 2>/dev/null || echo '{}')
  
  # Cache the HTML to avoid regenerating on every request
  if [ -f "/tmp/dashboard.html" ] && [ $(find /tmp/dashboard.html -mmin -1 2>/dev/null) ]; then
    cat /tmp/dashboard.html
    return
  fi
  
  # Generate new HTML and cache it
  cat << 'EOF' > /tmp/dashboard.html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Tor Guard Relay Dashboard</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
        }
        
        .container {
            max-width: 1200px;
            margin: 0 auto;
        }
        
        .header {
            background: rgba(255, 255, 255, 0.95);
            border-radius: 15px;
            padding: 25px;
            margin-bottom: 25px;
            box-shadow: 0 10px 30px rgba(0, 0, 0, 0.1);
        }
        
        .header h1 {
            color: #764ba2;
            font-size: 28px;
            margin-bottom: 10px;
            display: flex;
            align-items: center;
            gap: 10px;
        }
        
        .status-badge {
            display: inline-block;
            padding: 5px 15px;
            border-radius: 20px;
            font-size: 14px;
            font-weight: 600;
            text-transform: uppercase;
        }
        
        .status-healthy { background: #10b981; color: white; }
        .status-running { background: #f59e0b; color: white; }
        .status-starting { background: #3b82f6; color: white; }
        .status-down { background: #ef4444; color: white; }
        .status-unknown { background: #6b7280; color: white; }
        
        .grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
            margin-bottom: 20px;
        }
        
        .card {
            background: rgba(255, 255, 255, 0.95);
            border-radius: 12px;
            padding: 20px;
            box-shadow: 0 5px 15px rgba(0, 0, 0, 0.1);
        }
        
        .card h2 {
            color: #4b5563;
            font-size: 16px;
            margin-bottom: 15px;
            display: flex;
            align-items: center;
            gap: 8px;
        }
        
        .metric {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 10px 0;
            border-bottom: 1px solid #e5e7eb;
        }
        
        .metric:last-child {
            border-bottom: none;
        }
        
        .metric-label {
            color: #6b7280;
            font-size: 14px;
        }
        
        .metric-value {
            font-weight: 600;
            color: #1f2937;
            font-size: 16px;
        }
        
        .progress-bar {
            width: 100%;
            height: 30px;
            background: #e5e7eb;
            border-radius: 15px;
            overflow: hidden;
            margin: 10px 0;
        }
        
        .progress-fill {
            height: 100%;
            background: linear-gradient(90deg, #667eea, #764ba2);
            transition: width 0.5s ease;
            display: flex;
            align-items: center;
            justify-content: center;
            color: white;
            font-weight: 600;
            font-size: 14px;
        }
        
        .fingerprint {
            font-family: 'Courier New', monospace;
            background: #f3f4f6;
            padding: 10px;
            border-radius: 8px;
            word-break: break-all;
            font-size: 13px;
            cursor: pointer;
            transition: background 0.2s;
        }
        
        .fingerprint:hover {
            background: #e5e7eb;
        }
        
        .alert {
            padding: 15px;
            border-radius: 8px;
            margin-bottom: 15px;
            display: flex;
            align-items: center;
            gap: 10px;
        }
        
        .alert-error {
            background: #fee2e2;
            color: #991b1b;
        }
        
        .alert-warning {
            background: #fef3c7;
            color: #92400e;
        }
        
        .alert-success {
            background: #d1fae5;
            color: #065f46;
        }
        
        .footer {
            text-align: center;
            color: white;
            margin-top: 40px;
            opacity: 0.9;
        }
        
        .footer a {
            color: white;
            text-decoration: none;
            border-bottom: 1px solid rgba(255, 255, 255, 0.5);
        }
        
        @media (max-width: 640px) {
            .grid {
                grid-template-columns: 1fr;
            }
            
            .header h1 {
                font-size: 22px;
            }
        }
        
        .refresh-timer {
            position: fixed;
            bottom: 20px;
            right: 20px;
            background: rgba(255, 255, 255, 0.95);
            padding: 10px 20px;
            border-radius: 20px;
            box-shadow: 0 5px 15px rgba(0, 0, 0, 0.1);
            font-size: 14px;
            color: #4b5563;
        }
        
        .notification {
            position: fixed;
            top: 20px;
            right: 20px;
            background: rgba(255, 255, 255, 0.95);
            padding: 15px 20px;
            border-radius: 8px;
            box-shadow: 0 5px 15px rgba(0, 0, 0, 0.1);
            max-width: 300px;
            transform: translateX(400px);
            transition: transform 0.3s ease;
        }
        
        .notification.show {
            transform: translateX(0);
        }
        
        .notification.error {
            border-left: 4px solid #ef4444;
        }
        
        .notification.success {
            border-left: 4px solid #10b981;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>
                🧅 Tor Guard Relay Dashboard
                <span class="status-badge status-healthy" id="overall-status">Healthy</span>
            </h1>
            <p style="color: #6b7280; margin-top: 5px;">Real-time monitoring and management</p>
        </div>
        
        <div class="grid">
            <div class="card">
                <h2>🚀 Bootstrap Progress</h2>
                <div class="progress-bar">
                    <div class="progress-fill" id="bootstrap-progress" style="width: 0%;">
                        0%
                    </div>
                </div>
                <p id="bootstrap-message" style="color: #6b7280; font-size: 14px; margin-top: 10px;">
                    Initializing...
                </p>
            </div>
            
            <div class="card">
                <h2>🌍 Network Status</h2>
                <div class="metric">
                    <span class="metric-label">Reachability</span>
                    <span class="metric-value" id="reachability">Checking...</span>
                </div>
                <div class="metric">
                    <span class="metric-label">Public IP</span>
                    <span class="metric-value" id="public-ip">Loading...</span>
                </div>
                <div class="metric">
                    <span class="metric-label">ORPort</span>
                    <span class="metric-value" id="orport">-</span>
                </div>
            </div>
            
            <div class="card">
                <h2>📊 Performance</h2>
                <div class="metric">
                    <span class="metric-label">Uptime</span>
                    <span class="metric-value" id="uptime">0h 0m</span>
                </div>
                <div class="metric">
                    <span class="metric-label">Bandwidth</span>
                    <span class="metric-value" id="bandwidth">- KB/s</span>
                </div>
                <div class="metric">
                    <span class="metric-label">Connections</span>
                    <span class="metric-value" id="connections">0</span>
                </div>
            </div>
            
            <div class="card">
                <h2>🔑 Relay Identity</h2>
                <div class="metric">
                    <span class="metric-label">Nickname</span>
                    <span class="metric-value" id="nickname">-</span>
                </div>
                <div class="metric" style="flex-direction: column; align-items: flex-start;">
                    <span class="metric-label" style="margin-bottom: 10px;">Fingerprint</span>
                    <div class="fingerprint" id="fingerprint" onclick="copyFingerprint()">
                        Click to copy
                    </div>
                </div>
            </div>
            
            <div class="card">
                <h2>⚠️ Health Monitor</h2>
                <div id="health-alerts">
                    <div class="alert alert-success">
                        ✅ All systems operational
                    </div>
                </div>
                <div class="metric">
                    <span class="metric-label">Errors</span>
                    <span class="metric-value" id="error-count">0</span>
                </div>
                <div class="metric">
                    <span class="metric-label">Warnings</span>
                    <span class="metric-value" id="warning-count">0</span>
                </div>
            </div>
            
            <div class="card">
                <h2>🔗 Quick Actions</h2>
                <div style="display: flex; flex-direction: column; gap: 10px;">
                    <button onclick="window.open('/api/status', '_blank')" style="padding: 10px; border: none; background: #667eea; color: white; border-radius: 8px; cursor: pointer;">
                        📄 View JSON Status
                    </button>
                    <button onclick="window.open('/api/metrics', '_blank')" style="padding: 10px; border: none; background: #764ba2; color: white; border-radius: 8px; cursor: pointer;">
                        📊 View Metrics
                    </button>
                    <button onclick="refreshData()" style="padding: 10px; border: none; background: #10b981; color: white; border-radius: 8px; cursor: pointer;">
                        🔄 Refresh Now
                    </button>
                </div>
            </div>
        </div>
        
        <div class="footer">
            <p>
                Tor-Guard-Relay v${VERSION} | 
                <a href="https://metrics.torproject.org" target="_blank">Tor Metrics</a> | 
                <a href="https://github.com/torproject/tor" target="_blank">GitHub</a>
            </p>
        </div>
    </div>
    
    <div class="refresh-timer">
        🔄 Auto-refresh: <span id="countdown">${REFRESH_INTERVAL}</span>s
    </div>
    
    <div class="notification" id="notification"></div>
    
    <script>
        let refreshInterval = ${REFRESH_INTERVAL};
        let countdown = refreshInterval;
        let lastStatus = null;
        
        function showNotification(message, type = 'success') {
            const notification = document.getElementById('notification');
            notification.textContent = message;
            notification.className = 'notification ' + type;
            notification.classList.add('show');
            
            setTimeout(() => {
                notification.classList.remove('show');
            }, 3000);
        }
        
        function updateStatus(data) {
            // Check for status changes
            if (lastStatus && lastStatus.status !== data.status) {
                showNotification('Status changed to: ' + data.status, 
                    data.status === 'healthy' ? 'success' : 'error');
            }
            lastStatus = data;
            
            // Update overall status
            const statusEl = document.getElementById('overall-status');
            statusEl.className = 'status-badge status-' + (data.status || 'unknown');
            statusEl.textContent = (data.status || 'Unknown').toUpperCase();
            
            // Update bootstrap progress
            const bootstrap = data.bootstrap || {};
            const progressEl = document.getElementById('bootstrap-progress');
            const percent = bootstrap.percent || 0;
            progressEl.style.width = percent + '%';
            progressEl.textContent = percent + '%';
            document.getElementById('bootstrap-message').textContent = 
                bootstrap.message || 'Waiting for bootstrap...';
            
            // Update network status
            const reachable = data.reachability?.reachable;
            document.getElementById('reachability').textContent = 
                reachable ? '✅ Reachable' : '⏳ Testing...';
            document.getElementById('public-ip').textContent = 
                data.network?.public_ip || 'Unknown';
            document.getElementById('orport').textContent = 
                data.configuration?.orport || '-';
            
            // Update performance
            document.getElementById('uptime').textContent = 
                data.process?.uptime || '0h 0m';
            document.getElementById('bandwidth').textContent = 
                data.configuration?.bandwidth || '- KB/s';
            
            // Update identity
            document.getElementById('nickname').textContent = 
                data.identity?.nickname || '-';
            document.getElementById('fingerprint').textContent = 
                data.identity?.fingerprint || 'Not available';
            
            // Update health
            const errors = data.issues?.errors || 0;
            const warnings = data.issues?.warnings || 0;
            document.getElementById('error-count').textContent = errors;
            document.getElementById('warning-count').textContent = warnings;
            
            // Update health alerts
            const alertsEl = document.getElementById('health-alerts');
            if (errors > 0) {
                alertsEl.innerHTML = '<div class="alert alert-error">❌ ' + errors + ' errors detected</div>';
            } else if (warnings > 0) {
                alertsEl.innerHTML = '<div class="alert alert-warning">⚠️ ' + warnings + ' warnings detected</div>';
            } else {
                alertsEl.innerHTML = '<div class="alert alert-success">✅ All systems operational</div>';
            }
        }
        
        function refreshData() {
            fetch('/api/status')
                .then(response => {
                    if (!response.ok) throw new Error('Network response was not ok');
                    return response.json();
                })
                .then(data => updateStatus(data))
                .catch(error => {
                    console.error('Error fetching status:', error);
                    showNotification('Failed to fetch status data', 'error');
                });
        }
        
        function copyFingerprint() {
            const fp = document.getElementById('fingerprint').textContent;
            if (fp && fp !== 'Not available' && fp !== 'Click to copy') {
                navigator.clipboard.writeText(fp).then(() => {
                    const el = document.getElementById('fingerprint');
                    const original = el.textContent;
                    el.textContent = '✅ Copied!';
                    setTimeout(() => el.textContent = original, 2000);
                    showNotification('Fingerprint copied to clipboard', 'success');
                }).catch(err => {
                    console.error('Failed to copy: ', err);
                    showNotification('Failed to copy fingerprint', 'error');
                });
            }
        }
        
        // Countdown timer
        setInterval(() => {
            countdown--;
            if (countdown <= 0) {
                countdown = refreshInterval;
                refreshData();
            }
            document.getElementById('countdown').textContent = countdown;
        }, 1000);
        
        // Initial load
        refreshData();
    </script>
</body>
</html>
EOF
  
  # Return the cached HTML
  cat /tmp/dashboard.html
}

# Function to handle API requests
handle_api() {
  REQUEST_PATH="$1"
  AUTH_HEADER="$2"
  
  # Check authentication for API endpoints
  if [ "$REQUEST_PATH" != "/" ] && ! check_api_auth "$AUTH_HEADER"; then
    return
  fi
  
  case "$REQUEST_PATH" in
    "/api/status")
      CONTENT=$(/usr/local/bin/status --json 2>/dev/null || echo '{"error":"Failed to get status"}')
      echo "HTTP/1.1 200 OK"
      echo "Content-Type: application/json"
      echo "Cache-Control: no-cache"
      echo "Connection: close"
      echo ""
      echo "$CONTENT"
      ;;
      
    "/api/metrics")
      CONTENT=$(/usr/local/bin/metrics 2>/dev/null || echo "# Error generating metrics")
      echo "HTTP/1.1 200 OK"
      echo "Content-Type: text/plain"
      echo "Cache-Control: no-cache"
      echo "Connection: close"
      echo ""
      echo "$CONTENT"
      ;;
      
    "/api/logs")
      CONTENT=$(/usr/local/bin/view-logs --json 2>/dev/null || echo '{"error":"Failed to get logs"}')
      echo "HTTP/1.1 200 OK"
      echo "Content-Type: application/json"
      echo "Cache-Control: no-cache"
      echo "Connection: close"
      echo ""
      echo "$CONTENT"
      ;;
      
    "/")
      HTML=$(generate_dashboard)
      CONTENT_LENGTH=$(echo -n "$HTML" | wc -c)
      
      echo "HTTP/1.1 200 OK"
      echo "Content-Type: text/html"
      echo "Content-Length: $CONTENT_LENGTH"
      echo "Cache-Control: no-cache"
      echo "Connection: close"
      echo ""
      echo "$HTML"
      ;;
      
    *)
      ERROR_MSG="404 - Not Found"
      CONTENT_LENGTH=$(echo -n "$ERROR_MSG" | wc -c)
      
      echo "HTTP/1.1 404 Not Found"
      echo "Content-Type: text/plain"
      echo "Content-Length: $CONTENT_LENGTH"
      echo "Connection: close"
      echo ""
      echo "$ERROR_MSG"
      ;;
  esac
}

# Start server
echo "🎨 Starting Tor Relay Dashboard v${VERSION}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🌐 Listening on: http://$DASHBOARD_BIND:$DASHBOARD_PORT"
echo "🔒 Max connections: $MAX_CONNECTIONS"
if [ -n "$API_TOKEN" ]; then
  echo "🔐 API authentication: Enabled"
else
  echo "⚠️  API authentication: Disabled"
fi
echo "💡 Press Ctrl+C to stop"
echo ""

# Main server loop
while true; do
  CONNECTION_COUNT=$(( (CONNECTION_COUNT + 1) % MAX_CONNECTIONS ))

  # Reset counter if needed
  [ "$CONNECTION_COUNT" -eq 0 ] && sleep 1

  # Accept connection using a single listener
  nc -lk -p "$DASHBOARD_PORT" -s "$DASHBOARD_BIND" -w 5 | while read -r REQUEST; do
    # Only process first line
    PATH_REQ=$(echo "$REQUEST" | awk '{print $2}')
    
    # Extract Authorization header if present
    AUTH_HEADER=""
    while read -r header; do
      [ -z "$header" ] && break
      case "$header" in
        Authorization:*) AUTH_HEADER="$header" ;;
      esac
    done
    
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Request: $PATH_REQ"
    
    # Generate and send response directly
    handle_api "$PATH_REQ" "$AUTH_HEADER"
    break
  done
done
