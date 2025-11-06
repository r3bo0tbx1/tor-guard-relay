#!/bin/sh
# view-logs - Advanced log viewer with filtering and analysis
# Usage: docker exec guard-relay view-logs [--follow|--errors|--help]

set -e

# Configuration
VERSION="1.0.9"
LOG_FILE="${LOG_FILE:-/var/log/tor/notices.log}"
LOG_LINES="${LOG_LINES:-50}"
FOLLOW_MODE="${FOLLOW_MODE:-false}"
FILTER_MODE="${FILTER_MODE:-all}"
COLOR_OUTPUT="${COLOR_OUTPUT:-true}"

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

# Parse arguments
for arg in "$@"; do
  case "$arg" in
    --help|-h)
      cat << EOF
📜 Tor-Guard-Relay Log Viewer v${VERSION}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

USAGE:
    view-logs [OPTIONS]

OPTIONS:
    --follow, -f     Follow log output (tail -f)
    --all           Show all log entries (default)
    --errors        Show only errors
    --warnings      Show only warnings  
    --info          Show only info messages
    --bootstrap     Show bootstrap progress
    --last N        Show last N lines (default: 50)
    --no-color      Disable colored output
    --json          Output as JSON
    --help, -h      Show this help message

ENVIRONMENT VARIABLES:
    LOG_FILE        Path to log file
    LOG_LINES       Default number of lines to show
    COLOR_OUTPUT    Enable colored output (true/false)

FILTER MODES:
    all         All log entries
    errors      Error messages only
    warnings    Warning messages only
    info        Info/notice messages
    bootstrap   Bootstrap related messages
    network     Network/connectivity messages

EXAMPLES:
    view-logs                    # Last 50 lines
    view-logs --follow          # Follow new entries
    view-logs --errors          # Show only errors
    view-logs --last 100        # Show last 100 lines
    view-logs --bootstrap       # Bootstrap progress

LOG LEVELS:
    [err]    Error - Critical issues
    [warn]   Warning - Potential problems
    [notice] Notice - Normal operations
    [info]   Info - Detailed information

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
      exit 0
      ;;
    --follow|-f) FOLLOW_MODE="true" ;;
    --all) FILTER_MODE="all" ;;
    --errors) FILTER_MODE="errors" ;;
    --warnings) FILTER_MODE="warnings" ;;
    --info) FILTER_MODE="info" ;;
    --bootstrap) FILTER_MODE="bootstrap" ;;
    --network) FILTER_MODE="network" ;;
    --last)
      shift
      LOG_LINES="$1"
      shift
      ;;
    --no-color) COLOR_OUTPUT="false" ;;
    --json) OUTPUT_FORMAT="json" ;;
    -*) 
      echo "❌ Unknown option: $arg"
      echo "💡 Use --help for usage information"
      exit 2
      ;;
  esac
done

# Check if log file exists
if [ ! -f "$LOG_FILE" ]; then
  if [ "$OUTPUT_FORMAT" = "json" ]; then
    echo '{"error":"Log file not found","path":"'$LOG_FILE'"}'
  else
    echo "⚠️  Log file not found: $LOG_FILE"
    echo "📍 Tor might still be starting."
    echo "💡 Check back in a moment or verify Tor is running."
  fi
  exit 1
fi

# Function to colorize log lines
colorize_line() {
  if [ "$COLOR_OUTPUT" != "true" ]; then
    cat
    return
  fi
  
  sed -e "s/\[err\]/$(printf "${RED}[err]${NC}")/g" \
      -e "s/\[error\]/$(printf "${RED}[error]${NC}")/g" \
      -e "s/\[warn\]/$(printf "${YELLOW}[warn]${NC}")/g" \
      -e "s/\[warning\]/$(printf "${YELLOW}[warning]${NC}")/g" \
      -e "s/\[notice\]/$(printf "${GREEN}[notice]${NC}")/g" \
      -e "s/\[info\]/$(printf "${BLUE}[info]${NC}")/g" \
      -e "s/Bootstrapped [0-9]*%/$(printf "${GREEN}&${NC}")/g"
}

# Function to apply filters
apply_filter() {
  case "$FILTER_MODE" in
    errors)
      grep -iE "\[err\]|\[error\]|failed|failure|critical"
      ;;
    warnings)
      grep -iE "\[warn\]|\[warning\]"
      ;;
    info)
      grep -iE "\[notice\]|\[info\]"
      ;;
    bootstrap)
      grep -iE "bootstrap|starting|loading|opening|establishing"
      ;;
    network)
      grep -iE "reachable|connection|network|port|address"
      ;;
    *)
      cat
      ;;
  esac
}

# JSON output mode
if [ "$OUTPUT_FORMAT" = "json" ]; then
  TOTAL_LINES=$(wc -l < "$LOG_FILE")
  ERROR_COUNT=$(grep -cE "\[err\]|\[error\]" "$LOG_FILE" 2>/dev/null || echo 0)
  WARNING_COUNT=$(grep -cE "\[warn\]|\[warning\]" "$LOG_FILE" 2>/dev/null || echo 0)
  
  echo '{'
  echo '  "file": "'$LOG_FILE'",'
  echo '  "total_lines": '$TOTAL_LINES','
  echo '  "error_count": '$ERROR_COUNT','
  echo '  "warning_count": '$WARNING_COUNT','
  echo '  "entries": ['
  
  tail -n "$LOG_LINES" "$LOG_FILE" | apply_filter | while IFS= read -r line; do
    # Escape quotes and backslashes for JSON
    line=$(echo "$line" | sed 's/\\/\\\\/g; s/"/\\"/g')
    echo '    "'$line'",'
  done | sed '$ s/,$//'
  
  echo '  ]'
  echo '}'
  exit 0
fi

# Regular output mode
echo "📜 Tor Relay Logs"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📁 File: $LOG_FILE"
echo "🔍 Filter: $FILTER_MODE"

# Count log entries
if [ "$FILTER_MODE" = "all" ]; then
  TOTAL_LINES=$(wc -l < "$LOG_FILE")
  ERROR_COUNT=$(grep -cE "\[err\]|\[error\]" "$LOG_FILE" 2>/dev/null || echo 0)
  WARNING_COUNT=$(grep -cE "\[warn\]|\[warning\]" "$LOG_FILE" 2>/dev/null || echo 0)
  
  echo "📊 Stats: $TOTAL_LINES total | $ERROR_COUNT errors | $WARNING_COUNT warnings"
fi


echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Display logs
if [ "$FOLLOW_MODE" = "true" ]; then
  echo "🔄 Following log output (Ctrl+C to stop)..."
  echo ""
  tail -n "$LOG_LINES" -f "$LOG_FILE" | apply_filter | colorize_line
else
  tail -n "$LOG_LINES" "$LOG_FILE" | apply_filter | colorize_line
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "💡 Use 'view-logs --follow' for live updates"
fi