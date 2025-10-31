#!/bin/bash
# docker-entrypoint.sh - Tor Guard Relay initialization script
# Ensures proper permissions and validates configuration before starting Tor

set -euo pipefail

echo "🧅 Tor Guard Relay - Starting initialization..."
echo ""

# Ensure directory structure exists
echo "🔧 Ensuring directory structure..."
mkdir -p /var/lib/tor /var/log/tor /run/tor

# Fix permissions (critical for security)
echo "🔐 Setting secure permissions..."
chown -R tor:tor /var/lib/tor /var/log/tor /run/tor 2>/dev/null || true
chmod 700 /var/lib/tor
chmod 755 /var/log/tor

# Check if torrc exists
if [ ! -f /etc/tor/torrc ]; then
  echo "⚠️  WARNING: No torrc mounted at /etc/tor/torrc"
  echo "📝 Using minimal placeholder configuration."
  echo "# Placeholder configuration - mount your relay.conf here" > /etc/tor/torrc
fi

# Validate configuration
echo "🧩 Validating Tor configuration..."
if ! tor --verify-config -f /etc/tor/torrc 2>&1; then
  echo ""
  echo "❌ ERROR: Invalid Tor configuration detected!"
  echo "Please check your mounted torrc file for syntax errors."
  echo ""
  exit 1
fi

echo "✅ Configuration validated successfully."
echo ""

# Display build information
if [ -f /build-info.txt ]; then
  echo "📦 Build Information:"
  cat /build-info.txt | sed 's/^/   /'
  echo ""
fi

# Display helpful commands
echo "💡 Helpful commands:"
echo "   docker exec <container> relay-status  - View full status"
echo "   docker exec <container> fingerprint   - Show fingerprint"
echo "   docker exec <container> view-logs     - Stream logs"
echo ""

echo "🚀 Launching Tor relay..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Execute the command passed to the container (typically "tor -f /etc/tor/torrc")
exec "$@"