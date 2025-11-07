#!/bin/sh
# setup - Interactive configuration wizard for Tor relay
# Version: 1.1.0
# Usage: setup [--auto|--help|--json|--apply]

set -e

VERSION="1.1.0"
CONFIG_FILE="${CONFIG_FILE:-/etc/tor/torrc}"
RELAY_TYPE="${RELAY_TYPE:-guard}"
AUTO_MODE="${AUTO_MODE:-false}"
APPLY_MODE="false"
DEFAULT_NICKNAME="${DEFAULT_NICKNAME:-MyTorRelay}"
DEFAULT_CONTACT="${DEFAULT_CONTACT:-admin@example.com}"
DEFAULT_ORPORT="${DEFAULT_ORPORT:-9001}"
DEFAULT_DIRPORT="${DEFAULT_DIRPORT:-9030}"
DEFAULT_BANDWIDTH="${DEFAULT_BANDWIDTH:-1024}"
CREATE_BACKUP="${CREATE_BACKUP:-true}"
OUTPUT_FORMAT="${OUTPUT_FORMAT:-text}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

safe() { "$@" 2>/dev/null || true; }

trap 'cleanup' INT TERM

cleanup() {
  echo ""
  if [ -z "$CONFIG_WRITTEN" ]; then
    echo -e "${YELLOW}Setup cancelled by user${NC}"
  else
    echo -e "${YELLOW}Setup interrupted after configuration${NC}"
  fi
  exit 130
}

# Argument parsing
for arg in "$@"; do
  case "$arg" in
    --help|-h)
      cat << EOF
🧙 Tor-Guard-Relay Setup Wizard v${VERSION}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
USAGE:
    setup [--auto|--json|--apply|--type bridge|--no-backup]

OPTIONS:
    --auto          Use defaults for all prompts
    --apply         Automatically apply /tmp config to /etc/tor/torrc
    --type TYPE     Relay type: guard|exit|bridge
    --config FILE   Custom torrc path
    --no-backup     Skip backup creation
    --json          Output summary as JSON
    --help, -h      Show this message
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
      exit 0 ;;
    --auto) AUTO_MODE="true" ;;
    --apply) APPLY_MODE="true" ;;
    --type) shift; RELAY_TYPE="$1"; shift ;;
    --config) shift; CONFIG_FILE="$1"; shift ;;
    --no-backup) CREATE_BACKUP="false" ;;
    --json) OUTPUT_FORMAT="json" ;;
    -*) echo "❌ Unknown option: $arg"; exit 2 ;;
  esac
done

# Validation helpers
validate_nickname() { echo "$1" | grep -qE "^[a-zA-Z0-9]{1,19}$"; }
validate_email() { echo "$1" | grep -qE "^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$"; }
validate_port() { [ "$1" -ge 1 ] && [ "$1" -le 65535 ] 2>/dev/null; }
validate_bandwidth() { [ "$1" -ge 256 ] 2>/dev/null; }

# Backup creation
create_config_backup() {
  if [ -f "$CONFIG_FILE" ] && [ "$CREATE_BACKUP" = "true" ]; then
    BACKUP_TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_FILE="${CONFIG_FILE}.backup.${BACKUP_TIMESTAMP}"
    echo -e "${BLUE}📦 Creating backup...${NC}"
    if safe cp "$CONFIG_FILE" "$BACKUP_FILE"; then
      echo -e "${GREEN}✅ Backup created: $BACKUP_FILE${NC}"
      BACKUP_COUNT=$(safe ls -1 "${CONFIG_FILE}.backup."* | wc -l)
      if [ "$BACKUP_COUNT" -gt 5 ]; then
        echo -e "${YELLOW}🧹 Cleaning old backups (keeping last 5)...${NC}"
        safe ls -1t "${CONFIG_FILE}.backup."* | tail -n +6 | safe xargs rm -f
      fi
    else
      echo -e "${YELLOW}⚠️  Could not create backup${NC}"
    fi
  fi
}

restore_from_backup() {
  LATEST_BACKUP=$(safe ls -1t "${CONFIG_FILE}.backup."* | head -1)
  if [ -n "$LATEST_BACKUP" ]; then
    echo -e "${YELLOW}❌ Setup failed. Restoring backup...${NC}"
    if safe cp "$LATEST_BACKUP" "$CONFIG_FILE"; then
      echo -e "${GREEN}✅ Restored from: $LATEST_BACKUP${NC}"
    else
      echo -e "${RED}❌ Restore failed${NC}"
    fi
  fi
}

# UI helpers
print_header() {
  echo ""
  echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BLUE}$1${NC}"
  echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
}
print_step() { echo -e "${GREEN}[$1/6]${NC} $2"; }

# Header
clear
echo ""
echo -e "${PURPLE}╔══════════════════════════════════════════════════════════╗${NC}"
echo "🧅 Tor-Guard-Relay Setup Wizard v${VERSION}"
echo "            Configure your Tor relay in 6 steps"
echo -e "${PURPLE}╚══════════════════════════════════════════════════════════╝${NC}"
echo "Press Ctrl+C to cancel safely at any time."
echo ""

safe mkdir -p "$(dirname "$CONFIG_FILE")"

# Check existing config
if [ -f "$CONFIG_FILE" ]; then
  echo ""
  echo -e "${YELLOW}⚠️  Existing configuration found at:${NC} $CONFIG_FILE"
  if [ "$CREATE_BACKUP" = "true" ]; then
    echo -e "${GREEN}🔒 Backup will be created.${NC}"
  else
    echo -e "${RED}⚠️  Backup disabled.${NC}"
  fi
  if [ "$AUTO_MODE" != "true" ]; then
    printf "Continue and overwrite existing config? [y/N]: "
    read CONFIRM
    case "$CONFIRM" in
      [yY]) echo -e "${GREEN}✔ Proceeding with overwrite.${NC}" ;;
      *) echo -e "${YELLOW}Cancelled.${NC}"; exit 0 ;;
    esac
  fi
fi

# Step 1 – Nickname
print_header "Step 1: Relay Nickname"
print_step 1 "Choose a nickname"
if [ "$AUTO_MODE" = "true" ]; then
  NICKNAME="$DEFAULT_NICKNAME"
  echo -e "${GREEN}✓ Using default: $NICKNAME${NC}"
else
  while true; do
    printf "Enter nickname [${DEFAULT_NICKNAME}]: "
    read NICKNAME
    if [ -z "$NICKNAME" ]; then
      echo -e "${YELLOW}⚠ Empty input, using default: ${DEFAULT_NICKNAME}${NC}"
      NICKNAME="$DEFAULT_NICKNAME"
    fi
    if validate_nickname "$NICKNAME"; then
      echo -e "${GREEN}✓ Accepted: ${NICKNAME}${NC}"
      break
    else
      echo -e "${RED}✗ Invalid nickname (must be alphanumeric, ≤19 chars)${NC}"
    fi
  done
fi

# Step 2 – Contact
print_header "Step 2: Contact Information"
print_step 2 "Provide email (public)"
if [ "$AUTO_MODE" = "true" ]; then
  CONTACT="$DEFAULT_CONTACT"
  echo -e "${GREEN}✓ Using default: $CONTACT${NC}"
else
  while true; do
    printf "Enter email [${DEFAULT_CONTACT}]: "
    read CONTACT
    if [ -z "$CONTACT" ]; then
      echo -e "${YELLOW}⚠ Empty input, using default: ${DEFAULT_CONTACT}${NC}"
      CONTACT="$DEFAULT_CONTACT"
    fi
    if validate_email "$CONTACT"; then
      echo -e "${GREEN}✓ Accepted: ${CONTACT}${NC}"
      break
    else
      echo -e "${YELLOW}⚠ Nonstandard email format, continuing anyway.${NC}"
      break
    fi
  done
fi

# Step 3 – Ports
print_header "Step 3: Port Configuration"
print_step 3 "Configure ORPort and DirPort"
if [ "$AUTO_MODE" = "true" ]; then
  ORPORT="$DEFAULT_ORPORT"; DIRPORT="$DEFAULT_DIRPORT"
  echo -e "${GREEN}✓ Defaults: ORPort=$ORPORT DirPort=$DIRPORT${NC}"
else
  while true; do
    printf "Enter ORPort [${DEFAULT_ORPORT}]: "
    read ORPORT
    [ -z "$ORPORT" ] && { echo -e "${YELLOW}⚠ Using default ORPort: ${DEFAULT_ORPORT}${NC}"; ORPORT="$DEFAULT_ORPORT"; }
    validate_port "$ORPORT" && break || echo -e "${RED}✗ Invalid port${NC}"
  done
  while true; do
    printf "Enter DirPort [${DEFAULT_DIRPORT}]: "
    read DIRPORT
    [ -z "$DIRPORT" ] && { echo -e "${YELLOW}⚠ Using default DirPort: ${DEFAULT_DIRPORT}${NC}"; DIRPORT="$DEFAULT_DIRPORT"; }
    validate_port "$DIRPORT" && break || echo -e "${RED}✗ Invalid port${NC}"
  done
fi

# Step 4 – Bandwidth
print_header "Step 4: Bandwidth Allocation"
print_step 4 "Set bandwidth limit (KB/s)"
if [ "$AUTO_MODE" = "true" ]; then
  BANDWIDTH="$DEFAULT_BANDWIDTH"
  echo -e "${GREEN}✓ Using default: $BANDWIDTH KB/s${NC}"
else
  while true; do
    printf "Enter bandwidth [${DEFAULT_BANDWIDTH}]: "
    read BANDWIDTH
    if [ -z "$BANDWIDTH" ]; then
      echo -e "${YELLOW}⚠ Using default bandwidth: ${DEFAULT_BANDWIDTH}${NC}"
      BANDWIDTH="$DEFAULT_BANDWIDTH"
    fi
    validate_bandwidth "$BANDWIDTH" && break || echo -e "${RED}✗ Too low, must be ≥256 KB/s${NC}"
  done
fi

# Step 5 – Relay Type
print_header "Step 5: Relay Type"
print_step 5 "Choose relay type"
if [ "$AUTO_MODE" = "true" ]; then
  echo -e "${GREEN}✓ Using default: $RELAY_TYPE${NC}"
else
  printf "Enter type [guard/exit/bridge] [${RELAY_TYPE}]: "
  read TYPE_INPUT
  [ -n "$TYPE_INPUT" ] && RELAY_TYPE="$TYPE_INPUT"
  case "$RELAY_TYPE" in
    guard|exit|bridge) echo -e "${GREEN}✓ Type: $RELAY_TYPE${NC}" ;;
    *) echo -e "${YELLOW}⚠ Unknown type, defaulting to guard${NC}"; RELAY_TYPE="guard" ;;
  esac
fi

# Step 6 – Config Generation
print_header "Step 6: Generating Configuration"
print_step 6 "Writing torrc file"
create_config_backup
CONFIG_WRITTEN=true

# Non-root fallback
if [ "$(id -u)" != "0" ]; then
  TMP_PATH="/tmp/torrc.$(date +%s)"
  echo -e "${YELLOW}⚠️  Non-root user detected, writing config to: $TMP_PATH${NC}"
  echo -e "${YELLOW}💡 To apply it: sudo mv $TMP_PATH /etc/tor/torrc${NC}"
  CONFIG_FILE="$TMP_PATH"
fi

# Write configuration
if ! cat > "$CONFIG_FILE" << EOF
# Tor Relay Configuration
# Generated by Tor-Guard-Relay Setup Wizard v${VERSION}
# Date: $(date '+%Y-%m-%d %H:%M:%S')

Nickname $NICKNAME
ContactInfo $CONTACT
ORPort $ORPORT
DirPort $DIRPORT

RelayBandwidthRate $BANDWIDTH KB
RelayBandwidthBurst $((BANDWIDTH * 2)) KB
EOF
then
  echo -e "${RED}❌ Write failed${NC}"
  restore_from_backup
  exit 1
fi

# Relay type directives
case "$RELAY_TYPE" in
  guard) echo "ExitRelay 0" >> "$CONFIG_FILE"; echo "BridgeRelay 0" >> "$CONFIG_FILE" ;;
  exit)  echo "ExitRelay 1" >> "$CONFIG_FILE"; echo "BridgeRelay 0" >> "$CONFIG_FILE" ;;
  bridge) echo "BridgeRelay 1" >> "$CONFIG_FILE"; echo "ExitRelay 0" >> "$CONFIG_FILE" ;;
esac

cat <<EOF >> "$CONFIG_FILE"
RunAsDaemon 1
SocksPort 0
ControlPort 9051
DataDirectory /var/lib/tor
EOF

# Auto-apply if root and --apply used
if [ "$APPLY_MODE" = "true" ] && [ "$(id -u)" = "0" ] && [ "$CONFIG_FILE" != "/etc/tor/torrc" ]; then
  echo -e "${BLUE}🔧 Applying generated config to /etc/tor/torrc...${NC}"
  mv "$CONFIG_FILE" /etc/tor/torrc && echo -e "${GREEN}✅ Applied successfully.${NC}" || echo -e "${RED}❌ Apply failed.${NC}"
fi

echo -e "${GREEN}✅ Configuration saved: $CONFIG_FILE${NC}"

# Summary
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📄 Configuration Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📁 File: $CONFIG_FILE"
echo "🧅 Nickname: $NICKNAME"
echo "📧 Contact: $CONTACT"
echo "🔌 ORPort: $ORPORT"
echo "📡 DirPort: $DIRPORT"
echo "📈 Bandwidth: $BANDWIDTH KB/s"
echo "🏷️ Type: $RELAY_TYPE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Setup complete. You can now restart your relay."
echo ""

if [ "$OUTPUT_FORMAT" = "json" ]; then
  cat <<EOF
{
  "nickname": "$NICKNAME",
  "contact": "$CONTACT",
  "orport": "$ORPORT",
  "dirport": "$DIRPORT",
  "bandwidth": "$BANDWIDTH",
  "relay_type": "$RELAY_TYPE",
  "config_file": "$CONFIG_FILE"
}
EOF
fi
