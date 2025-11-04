#!/bin/sh
# fingerprint - Display and manage Tor relay fingerprint
# Usage: docker exec guard-relay fingerprint [--json|--help]

set -e

# Configuration
VERSION="1.1.0"
OUTPUT_FORMAT="${OUTPUT_FORMAT:-text}"
FINGERPRINT_FILE="${FINGERPRINT_FILE:-/var/lib/tor/fingerprint}"
SHOW_LINKS="${SHOW_LINKS:-true}"

# Parse arguments
for arg in "$@"; do
  case "$arg" in
    --help|-h)
      cat << EOF
🔑 Tor-Guard-Relay Fingerprint Tool v${VERSION}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

USAGE:
    fingerprint [OPTIONS]

OPTIONS:
    --json          Output in JSON format
    --plain         Plain text output
    --copy          Output for easy copying
    --links         Show monitoring links (default)
    --no-links      Hide monitoring links
    --help, -h      Show this help message

ENVIRONMENT VARIABLES:
    OUTPUT_FORMAT      Output format (text/json/plain)
    FINGERPRINT_FILE   Path to fingerprint file
    SHOW_LINKS         Show monitoring links (true/false)

OUTPUT FORMATS:
    text    Human-readable with emojis and links
    json    Machine-readable JSON
    plain   Simple text for scripts
    copy    Formatted for clipboard copying

MONITORING LINKS:
    • Tor Metrics (clearnet)
    • Onion Metrics (Tor Browser only)

EXAMPLES:
    fingerprint              # Display with links
    fingerprint --json       # JSON output
    fingerprint --copy       # Copy-friendly format
    fingerprint --plain      # Script-friendly output

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
      exit 0
      ;;
    --json) OUTPUT_FORMAT="json" ;;
    --plain) OUTPUT_FORMAT="plain" ;;
    --copy) OUTPUT_FORMAT="copy" ;;
    --links) SHOW_LINKS="true" ;;
    --no-links) SHOW_LINKS="false" ;;
    -*)
      echo "❌ Unknown option: $arg"
      echo "💡 Use --help for usage information"
      exit 2
      ;;
  esac
done

# Check if fingerprint exists
if [ ! -f "$FINGERPRINT_FILE" ]; then
  case "$OUTPUT_FORMAT" in
    json)
      cat << EOF
{
  "status": "not_ready",
  "message": "Fingerprint not yet generated",
  "fingerprint": null,
  "nickname": null
}
EOF
      ;;
    plain)
      echo "NOT_READY"
      ;;
    *)
      echo "⚠️  Fingerprint not yet generated."
      echo "📍 Tor is still bootstrapping or generating keys."
      echo "💡 Check back in a few minutes."
      ;;
  esac
  exit 1
fi

# Read fingerprint
NICKNAME=$(awk '{print $1}' "$FINGERPRINT_FILE" 2>/dev/null || echo "")
FINGERPRINT=$(awk '{print $2}' "$FINGERPRINT_FILE" 2>/dev/null || echo "")

# Validate fingerprint format (40 hex characters)
if ! echo "$FINGERPRINT" | grep -qE "^[A-F0-9]{40}$"; then
  case "$OUTPUT_FORMAT" in
    json)
      echo '{"status":"invalid","message":"Invalid fingerprint format"}'
      ;;
    plain)
      echo "INVALID"
      ;;
    *)
      echo "❌ Invalid fingerprint format detected"
      ;;
  esac
  exit 1
fi

# Generate formatted versions
FINGERPRINT_SPACED=$(echo "$FINGERPRINT" | sed 's/\(..\)/\1 /g' | sed 's/ $//')
FINGERPRINT_COLON=$(echo "$FINGERPRINT" | sed 's/\(..\)/\1:/g' | sed 's/:$//')

# Get additional info if available
CREATION_TIME=""
if [ -f "$FINGERPRINT_FILE" ]; then
  CREATION_TIME=$(stat -c %y "$FINGERPRINT_FILE" 2>/dev/null | cut -d' ' -f1,2 | cut -d'.' -f1 || echo "")
fi

# Output based on format
case "$OUTPUT_FORMAT" in
  json)
    cat << EOF
{
  "status": "ready",
  "nickname": "$NICKNAME",
  "fingerprint": "$FINGERPRINT",
  "fingerprint_spaced": "$FINGERPRINT_SPACED",
  "fingerprint_colon": "$FINGERPRINT_COLON",
  "created": "$CREATION_TIME",
  "links": {
    "metrics": "https://metrics.torproject.org/rs.html#search/$FINGERPRINT",
    "onion_metrics": "http://hctxrvjzfpvmzh2jllqhgvvkoepxb4kfzdjm6h7egcwlumggtktiftid.onion/rs.html#search/$FINGERPRINT"
  }
}
EOF
    ;;
    
  plain)
    echo "$NICKNAME $FINGERPRINT"
    ;;
    
  copy)
    echo "$FINGERPRINT"
    echo ""
    echo "# Formatted versions:"
    echo "# Spaced: $FINGERPRINT_SPACED"
    echo "# Colon:  $FINGERPRINT_COLON"
    ;;
    
  *)
    # Default text format with emojis
    echo "🔑 Tor Relay Fingerprint"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "📝 Nickname:    $NICKNAME"
    echo "🆔 Fingerprint: $FINGERPRINT"
    echo ""
    echo "📋 Formatted versions:"
    echo "   Spaced: $FINGERPRINT_SPACED"
    echo "   Colon:  $FINGERPRINT_COLON"
    
    if [ -n "$CREATION_TIME" ]; then
      echo ""
      echo "🕒 Created: $CREATION_TIME"
    fi
    
    if [ "$SHOW_LINKS" = "true" ]; then
      echo ""
      echo "🌐 Monitor your relay:"
      echo ""
      echo "   📊 Tor Metrics:"
      echo "      https://metrics.torproject.org/rs.html#search/$FINGERPRINT"
      echo ""
      echo "   🧅 Onion Metrics (Tor Browser only):"
      echo "      http://hctxrvjzfpvmzh2jllqhgvvkoepxb4kfzdjm6h7egcwlumggtktiftid.onion/rs.html#search/$FINGERPRINT"
    fi
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "💡 Tip: Use 'fingerprint --copy' for easy copying"
    ;;
esac
