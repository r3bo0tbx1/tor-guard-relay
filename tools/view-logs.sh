#!/bin/sh
# view-logs - Advanced Tor relay log viewer with filtering and analysis
# Usage: docker exec guard-relay view-logs [--follow|--errors|--help]

set -e

VERSION="1.1.0"
LOG_FILE="${LOG_FILE:-/var/log/tor/notices.log}"
LOG_LINES="${LOG_LINES:-50}"
FOLLOW_MODE="false"
FILTER_MODE="all"
OUTPUT_FORMAT="text"
COLOR_OUTPUT="true"

# Force color by default
FORCE_COLOR="${FORCE_COLOR:-true}"
[ "$FORCE_COLOR" = "true" ] && COLOR_OUTPUT="true"

# Colours
ESC="$(printf '\033')"
RED="${ESC}[0;31m"
YELLOW="${ESC}[1;33m"
GREEN="${ESC}[0;32m"
BLUE="${ESC}[0;34m"
CYAN="${ESC}[0;36m"
MAGENTA="${ESC}[0;35m"
BOLD="${ESC}[1m"
NC="${ESC}[0m"

is_integer() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

# Argument parsing
while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h)
      cat << EOF
📜 Tor-Guard-Relay Log Viewer v${VERSION}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
USAGE: view-logs [OPTIONS]

OPTIONS:
  --follow, -f     Follow log output (tail -f)
  --all            Show all log entries (default)
  --errors         Show only errors
  --warnings       Show only warnings
  --info           Show only info messages
  --bootstrap      Show bootstrap progress
  --network        Show network/connectivity logs
  --last N         Show last N lines (default: 50)
  --no-color       Disable color output
  --json           Output as JSON
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
      exit 0 ;;
    --follow|-f) FOLLOW_MODE="true"; shift ;;
    --all) FILTER_MODE="all"; shift ;;
    --errors) FILTER_MODE="errors"; shift ;;
    --warnings) FILTER_MODE="warnings"; shift ;;
    --info) FILTER_MODE="info"; shift ;;
    --bootstrap) FILTER_MODE="bootstrap"; shift ;;
    --network) FILTER_MODE="network"; shift ;;
    --last)
      shift
      if is_integer "$1"; then LOG_LINES="$1"; shift
      else echo "❌ Invalid number for --last: $1"; exit 2; fi ;;
    --no-color) COLOR_OUTPUT="false"; shift ;;
    --json) OUTPUT_FORMAT="json"; shift ;;
    -*) echo "❌ Unknown option: $1"; exit 2 ;;
  esac
done

# Verify file
if [ ! -f "$LOG_FILE" ]; then
  case "$OUTPUT_FORMAT" in
    json) printf '{"error":"Log file not found","path":"%s"}\n' "$LOG_FILE" ;;
    *) echo "⚠️  Log file not found: $LOG_FILE"
       echo "📍 Tor might still be starting or logging elsewhere."
       echo "💡 Check again shortly." ;;
  esac
  exit 1
fi

# Read identity
FP_NICKNAME=""
FP_FINGERPRINT=""
if [ -f /var/lib/tor/fingerprint ]; then
  FP_NICKNAME=$(awk '{print $1}' /var/lib/tor/fingerprint 2>/dev/null || true)
  FP_FINGERPRINT=$(awk '{print $2}' /var/lib/tor/fingerprint 2>/dev/null || true)
  FP_NICKNAME=$(printf '%s' "$FP_NICKNAME" | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  FP_FINGERPRINT=$(printf '%s' "$FP_FINGERPRINT" | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
fi

# Filter expressions
case "$FILTER_MODE" in
  errors) FILTER_EXPR='\[err\]|\[error\]|failed|failure|critical' ;;
  warnings) FILTER_EXPR='\[warn\]|\[warning\]' ;;
  info) FILTER_EXPR='\[notice\]|\[info\]' ;;
  bootstrap) FILTER_EXPR='bootstrapped|starting|loading|establishing' ;;
  network) FILTER_EXPR='reachable|connection|network|port|address' ;;
  *) FILTER_EXPR='' ;;
esac

# Stats
if [ "$FILTER_MODE" = "all" ]; then
  TOTAL_MATCHES=$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)
  ERROR_COUNT=$(grep -ciE '\[err\]|\[error\]' "$LOG_FILE" 2>/dev/null || echo 0)
  WARNING_COUNT=$(grep -ciE '\[warn\]|\[warning\]' "$LOG_FILE" 2>/dev/null || echo 0)
else
  TOTAL_MATCHES=$(grep -ciE "$FILTER_EXPR" "$LOG_FILE" 2>/dev/null || echo 0)
  ERROR_COUNT=$(grep -iE "$FILTER_EXPR" "$LOG_FILE" 2>/dev/null | grep -ciE '\[err\]|\[error\]' || echo 0)
  WARNING_COUNT=$(grep -iE "$FILTER_EXPR" "$LOG_FILE" 2>/dev/null | grep -ciE '\[warn\]|\[warning\]' || echo 0)
fi

sanitize_num() { printf '%s' "$1" | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'; }
TOTAL_MATCHES=$(sanitize_num "$TOTAL_MATCHES")
ERROR_COUNT=$(sanitize_num "$ERROR_COUNT")
WARNING_COUNT=$(sanitize_num "$WARNING_COUNT")

sanitize_stream() { sed "s|${ESC}\[[0-9;]*[mK]||g; s/\r$//"; }

# Colorize output
colorize_line() {
  if [ "$COLOR_OUTPUT" != "true" ]; then cat; return; fi
  sed -E \
    -e "s/\[err\]/${RED}[err]${NC}/Ig" \
    -e "s/\[error\]/${RED}[error]${NC}/Ig" \
    -e "s/\[warn\]/${YELLOW}[warn]${NC}/Ig" \
    -e "s/\[warning\]/${YELLOW}[warning]${NC}/Ig" \
    -e "s/\[notice\]/${GREEN}[notice]${NC}/Ig" \
    -e "s/\[info\]/${BLUE}[info]${NC}/Ig" \
    -e "s/Bootstrapped[[:space:]]*[0-9]{1,3}%/${GREEN}&${NC}/Ig" \
    -e "s/(Your Tor server's identity key fingerprint is ')[[:space:]]*([^[:space:]]+)[[:space:]]+([A-F0-9]{16,})(')/\1${CYAN}\2${NC} ${MAGENTA}\3${NC}\4/Ig" \
    -e "s/(Your Tor server's identity key ed25519 fingerprint is ')[[:space:]]*([^[:space:]]+)[[:space:]]+([A-Za-z0-9+\/=]{32,})(')/\1${CYAN}\2${NC} ${MAGENTA}\3${NC}\4/Ig" \
    -e "s/([A-F0-9]{10,})([[:space:]]*[A-F0-9]{2,})*/${MAGENTA}&${NC}/Ig" \
    -e "s/([A-Za-z0-9+\/]{40,}={0,2})/${MAGENTA}&${NC}/Ig"
}

# Header
echo "📜 Tor Relay Logs"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📁 File: $LOG_FILE"
echo "🔍 Filter: $FILTER_MODE"
printf "📊 Stats: %s total | %s errors | %s warnings\n" "$TOTAL_MATCHES" "$ERROR_COUNT" "$WARNING_COUNT"

if [ -n "$FP_FINGERPRINT" ] || [ -n "$FP_NICKNAME" ]; then
  if [ "$COLOR_OUTPUT" = "true" ]; then
    echo "🔑 Identity:"
    printf "   Nickname ✨: %s\n" "${CYAN}${FP_NICKNAME:-unknown}${NC}"
    printf "   Fingerprint 🫆: %s\n" "${MAGENTA}${FP_FINGERPRINT:-unknown}${NC}"
  else
    echo "🔑 Identity:"
    echo "   Nickname ✨: ${FP_NICKNAME:-unknown}"
    echo "   Fingerprint 🫆: ${FP_FINGERPRINT:-unknown}"
  fi
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Stream logs
if [ "$FOLLOW_MODE" = "true" ]; then
  echo "🔄 Following live output (Ctrl+C to stop)..."
  echo ""
  if [ "$FILTER_MODE" = "all" ]; then
    tail -n "$LOG_LINES" -f "$LOG_FILE" | sanitize_stream | colorize_line
  else
    tail -n "$LOG_LINES" -f "$LOG_FILE" | sanitize_stream | grep -iE "$FILTER_EXPR" 2>/dev/null | colorize_line
  fi
else
  if [ "$FILTER_MODE" = "all" ]; then
    tail -n "$LOG_LINES" "$LOG_FILE" | sanitize_stream | colorize_line
  else
    tail -n "$LOG_LINES" "$LOG_FILE" | sanitize_stream | grep -iE "$FILTER_EXPR" 2>/dev/null | colorize_line
  fi
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "💡 Use 'view-logs --follow' for live updates"
fi
