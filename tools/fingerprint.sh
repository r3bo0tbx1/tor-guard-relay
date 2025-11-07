#!/bin/sh
# fingerprint - Display and manage Tor relay fingerprint
# Usage: docker exec guard-relay fingerprint [--json|--help]

set -e

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
Usage:
    fingerprint [OPTIONS]

Options:
    --json          Output in JSON format
    --plain         Plain text output
    --copy          Output for easy copying
    --links         Show monitoring links (default)
    --no-links      Hide monitoring links
    --help, -h      Show this help message

Environment:
    OUTPUT_FORMAT      Output format (text/json/plain)
    FINGERPRINT_FILE   Path to fingerprint file
    SHOW_LINKS         Show monitoring links (true/false)

Examples:
    fingerprint              # Display formatted fingerprint
    fingerprint --json       # JSON output
    fingerprint --copy       # Copy-friendly format
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
      exit 0 ;;
    --json) OUTPUT_FORMAT="json" ;;
    --plain) OUTPUT_FORMAT="plain" ;;
    --copy) OUTPUT_FORMAT="copy" ;;
    --links) SHOW_LINKS="true" ;;
    --no-links) SHOW_LINKS="false" ;;
    -*) echo "❌ Unknown option: $arg" >&2; exit 2 ;;
  esac
done

# Check file existence
if [ ! -f "$FINGERPRINT_FILE" ]; then
  case "$OUTPUT_FORMAT" in
    json)
      printf '{ "status":"not_ready", "message":"Fingerprint not yet generated" }\n' ;;
    plain) echo "NOT_READY" ;;
    *) echo "⚠️  Fingerprint not yet generated."
       echo "📍 Tor is still bootstrapping or generating keys."
       echo "💡 Check back in a few minutes." ;;
  esac
  exit 1
fi

# Extract data safely
NICKNAME=$(awk 'NF {print $1; exit}' "$FINGERPRINT_FILE" 2>/dev/null || echo "")
FINGERPRINT=$(awk 'NF {print $2; exit}' "$FINGERPRINT_FILE" 2>/dev/null || echo "")

# Validate fingerprint format (accept uppercase and lowercase)
if ! echo "$FINGERPRINT" | grep -qE '^[A-Fa-f0-9]{40}$'; then
  case "$OUTPUT_FORMAT" in
    json) printf '{ "status":"invalid", "message":"Invalid fingerprint format" }\n' ;;
    plain) echo "INVALID" ;;
    *) echo "❌ Invalid fingerprint format detected" ;;
  esac
  exit 1
fi

# Generate formatted variants
FINGERPRINT_SPACED=$(echo "$FINGERPRINT" | sed 's/\(..\)/\1 /g; s/ $//')
FINGERPRINT_COLON=$(echo "$FINGERPRINT" | sed 's/\(..\)/\1:/g; s/:$//')

# Get creation time (portable fallback)
CREATION_TIME=""
if command -v stat >/dev/null 2>&1; then
  CREATION_TIME=$(stat -c %y "$FINGERPRINT_FILE" 2>/dev/null | cut -d'.' -f1 || true)
elif command -v date >/dev/null 2>&1; then
  CREATION_TIME=$(date -r "$FINGERPRINT_FILE" 2>/dev/null || true)
fi

# Escape JSON strings
escape_json() { printf '%s' "$1" | sed 's/"/\\"/g'; }

# Output formats
case "$OUTPUT_FORMAT" in
  json)
    cat << EOF
{
  "status": "ready",
  "nickname": "$(escape_json "$NICKNAME")",
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
    echo "$NICKNAME $FINGERPRINT" ;;
  copy)
    echo "$FINGERPRINT"
    echo ""
    echo "# Spaced: $FINGERPRINT_SPACED"
    echo "# Colon:  $FINGERPRINT_COLON" ;;
  *)
    echo "🔑 Tor Relay Fingerprint"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "📝 Nickname:    $NICKNAME"
    echo "🆔 Fingerprint: $FINGERPRINT"
    echo ""
    echo "📋 Formatted versions:"
    echo "   Spaced: $FINGERPRINT_SPACED"
    echo "   Colon:  $FINGERPRINT_COLON"
    [ -n "$CREATION_TIME" ] && {
      echo ""
      echo "🕒 Created: $CREATION_TIME"
    }
    if [ "$SHOW_LINKS" = "true" ]; then
      echo ""
      echo "🌐 Monitor your relay:"
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
