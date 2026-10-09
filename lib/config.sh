#!/bin/sh
config_die() { printf 'ERROR: %s\n' "$1" >&2; exit 1; }
die() { config_die "$@"; }
warn() { printf 'Warning: %s\n' "$1" >&2; }
validate_relay_config() {
  for variable in TOR_NICKNAME TOR_CONTACT_INFO TOR_EXIT_POLICY TOR_MY_FAMILY TOR_DATA_DIR TOR_LOG_DIR; do
    content=''
    eval "content=\${$variable:-}"
    if printf '%s' "$content" | LC_ALL=C grep -q '[[:cntrl:]]'; then die "$variable contains control characters"; fi
  done
  if [ -n "${TOR_RELAY_MODE:-}" ]; then
    case "$TOR_RELAY_MODE" in
      guard|middle|exit|bridge)
        :
        ;;
      *)
        die "TOR_RELAY_MODE must be: guard, middle, exit, or bridge (got: $TOR_RELAY_MODE)"
        ;;
    esac
  fi

  if [ -n "${TOR_NICKNAME:-}" ]; then
    nickname_len=$(printf "%s" "$TOR_NICKNAME" | wc -c)
    if [ "$nickname_len" -lt 1 ] || [ "$nickname_len" -gt 19 ]; then
      die "TOR_NICKNAME must be 1-19 characters (got: $nickname_len)"
    fi
    if ! printf "%s" "$TOR_NICKNAME" | grep -qE '^[a-zA-Z0-9]+$'; then
      die "TOR_NICKNAME must contain only alphanumeric characters"
    fi
    case "$(printf "%s" "$TOR_NICKNAME" | tr '[:upper:]' '[:lower:]')" in
      unnamed|noname|default|tor|relay|bridge|exit)
        die "TOR_NICKNAME cannot use reserved name: $TOR_NICKNAME"
        ;;
    esac
  fi

  if [ -n "${TOR_CONTACT_INFO:-}" ]; then
    TOR_CONTACT_INFO="$(printf "%s" "$TOR_CONTACT_INFO" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

    contact_len=$(printf "%s" "$TOR_CONTACT_INFO" | wc -c)
    if [ "$contact_len" -lt 3 ]; then
      die "TOR_CONTACT_INFO must be at least 3 characters"
    fi
    line_count=$(printf "%s" "$TOR_CONTACT_INFO" | wc -l)
    if [ "$line_count" -gt 0 ]; then
      die "TOR_CONTACT_INFO cannot contain newlines (got $line_count lines)"
    fi
  fi

  for port_var in TOR_ORPORT TOR_DIRPORT TOR_OBFS4_PORT; do
    eval "port_val=\${$port_var:-}"
    if [ -n "$port_val" ]; then
      if ! printf "%s" "$port_val" | grep -qE '^[0-9]+$'; then
        die "$port_var must be a valid port number (got: $port_val)"
      fi
      if [ "$port_var" = "TOR_DIRPORT" ] && [ "$port_val" -eq 0 ]; then
        :
      elif [ "$port_val" -lt 1 ] || [ "$port_val" -gt 65535 ]; then
        die "$port_var must be between 1-65535 (got: $port_val)"
      fi
      if [ "$port_val" -lt 1024 ] && [ "$port_val" -ne 0 ]; then
        warn "$port_var using privileged port $port_val (may require CAP_NET_BIND_SERVICE)"
      fi
    fi
  done

  for bw_var in TOR_BANDWIDTH_RATE TOR_BANDWIDTH_BURST; do
    eval "bw_val=\${$bw_var:-}"
    if [ -n "$bw_val" ]; then
      if ! printf "%s" "$bw_val" | grep -qE '^[0-9]+ ?(Bytes?|KBytes?|MBytes?|GBytes?|TBytes?|KB?|MB?|GB?|TB?)$'; then
        die "$bw_var has invalid format (got: $bw_val, expected: '10 MB' or '1 GB')"
      fi
    fi
  done

  if [ -n "${TOR_FAMILY_ID:-}" ]; then
    family_id_len=$(printf "%s" "$TOR_FAMILY_ID" | wc -c)
    if [ "$family_id_len" -ne 43 ]; then
      die "TOR_FAMILY_ID must be exactly 43 characters (got: $family_id_len)"
    fi
    if ! printf "%s" "$TOR_FAMILY_ID" | grep -qE '^[A-Za-z0-9+/]{43}$'; then
      die "TOR_FAMILY_ID must be an unpadded base64-encoded Ed25519 public-key digest"
    fi
  fi
}

generate_config_from_env() {
  cat > "$TOR_CONFIG" << EOF
# Generated Tor configuration for ${TOR_RELAY_MODE} relay
# Generated at: $(date -u '+%Y-%m-%d %H:%M:%S') UTC

# Basic relay information
Nickname ${TOR_NICKNAME}
ContactInfo ${TOR_CONTACT_INFO}

# Network configuration
ORPort ${TOR_ORPORT:-9001}
SocksPort 0

# Data directories
DataDirectory ${TOR_DATA_DIR}

# Logging (file only; the entrypoint streams this once)
Log notice file ${TOR_LOG_DIR}/notices.log

EOF

  for option in AccountingMax AccountingStart ORPortIPv6 ExitPolicyIPv6 AddressDisableIPv6 IPv6Exit; do
    case "$option" in
      AccountingMax) val=${TOR_ACCOUNTING_MAX:-} ;;
      AccountingStart) val=${TOR_ACCOUNTING_START:-} ;;
      ORPortIPv6) val=${TOR_ORPORT_IPV6:-} ;;
      ExitPolicyIPv6) val=${TOR_EXIT_POLICY_IPV6:-} ;;
      AddressDisableIPv6) val=${TOR_ADDRESS_DISABLE_IPV6:-} ;;
      IPv6Exit) val=${TOR_IPV6_EXIT:-} ;;
    esac
    [ -n "$val" ] || continue
    if printf '%s' "$val" | LC_ALL=C grep -q '[[:cntrl:]]'; then die "$option contains control characters"; fi
    [ "$option" != ORPortIPv6 ] || option=ORPort
    [ "$option" != ExitPolicyIPv6 ] || option=ExitPolicy
    printf '%s %s\n' "$option" "$val" >> "$TOR_CONFIG"
  done

  case "$TOR_RELAY_MODE" in
    guard|middle)
      cat >> "$TOR_CONFIG" << EOF
# Guard/Middle relay configuration
DirPort ${TOR_DIRPORT:-0}
ExitRelay 0
BridgeRelay 0

# Bandwidth (optional)
EOF
      [ -n "${TOR_BANDWIDTH_RATE:-}" ] && echo "RelayBandwidthRate ${TOR_BANDWIDTH_RATE}" >> "$TOR_CONFIG"
      [ -n "${TOR_BANDWIDTH_BURST:-}" ] && echo "RelayBandwidthBurst ${TOR_BANDWIDTH_BURST}" >> "$TOR_CONFIG"
      [ -n "${TOR_FAMILY_ID:-}" ] && echo "" >> "$TOR_CONFIG" && echo "# Happy Family (Tor 0.4.9.2-alpha or later)" >> "$TOR_CONFIG" && echo "FamilyId ${TOR_FAMILY_ID}" >> "$TOR_CONFIG"

      if [ -n "${TOR_MY_FAMILY:-}" ]; then
        echo "" >> "$TOR_CONFIG"
        echo "# MyFamily (legacy - keep during transition to Happy Family)" >> "$TOR_CONFIG"
        echo "$TOR_MY_FAMILY" | tr ',' '\n' | while IFS= read -r fp; do
          fp=$(printf "%s" "$fp" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
          [ -n "$fp" ] && echo "MyFamily $fp" >> "$TOR_CONFIG"
        done
      fi
      ;;

    exit)
      cat >> "$TOR_CONFIG" << EOF
# Exit relay configuration
DirPort ${TOR_DIRPORT:-0}
ExitRelay 1
BridgeRelay 0

# Exit policy (default: reduced exit)
ExitPolicy ${TOR_EXIT_POLICY:-reject *:*}

# Bandwidth (optional)
EOF
      [ -n "${TOR_BANDWIDTH_RATE:-}" ] && echo "RelayBandwidthRate ${TOR_BANDWIDTH_RATE}" >> "$TOR_CONFIG"
      [ -n "${TOR_BANDWIDTH_BURST:-}" ] && echo "RelayBandwidthBurst ${TOR_BANDWIDTH_BURST}" >> "$TOR_CONFIG"
      [ -n "${TOR_FAMILY_ID:-}" ] && echo "" >> "$TOR_CONFIG" && echo "# Happy Family (Tor 0.4.9.2-alpha or later)" >> "$TOR_CONFIG" && echo "FamilyId ${TOR_FAMILY_ID}" >> "$TOR_CONFIG"

      if [ -n "${TOR_MY_FAMILY:-}" ]; then
        echo "" >> "$TOR_CONFIG"
        echo "# MyFamily (legacy - keep during transition to Happy Family)" >> "$TOR_CONFIG"
        echo "$TOR_MY_FAMILY" | tr ',' '\n' | while IFS= read -r fp; do
          fp=$(printf "%s" "$fp" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
          [ -n "$fp" ] && echo "MyFamily $fp" >> "$TOR_CONFIG"
        done
      fi
      ;;

    bridge)
      cat >> "$TOR_CONFIG" << EOF
# Bridge relay configuration
BridgeRelay 1
PublishServerDescriptor bridge

# obfs4 pluggable transport
ServerTransportPlugin obfs4 exec /usr/bin/lyrebird
ServerTransportListenAddr obfs4 0.0.0.0:${TOR_OBFS4_PORT:-9002}
ExtORPort auto

# Bandwidth (optional)
EOF
      [ -n "${TOR_BANDWIDTH_RATE:-}" ] && echo "RelayBandwidthRate ${TOR_BANDWIDTH_RATE}" >> "$TOR_CONFIG"
      [ -n "${TOR_BANDWIDTH_BURST:-}" ] && echo "RelayBandwidthBurst ${TOR_BANDWIDTH_BURST}" >> "$TOR_CONFIG"

      if [ "${OBFS4_ENABLE_ADDITIONAL_VARIABLES:-0}" = "1" ]; then
        echo "" >> "$TOR_CONFIG"
        echo "# Additional torrc options from OBFS4V_* environment variables" >> "$TOR_CONFIG"

        env | grep '^OBFS4V_' | sort | while IFS='=' read -r key value; do
          torrc_key="${key#OBFS4V_}"
          if ! printf "%s" "$torrc_key" | grep -qE '^[a-zA-Z][a-zA-Z0-9_]*$'; then
            warn "Skipping invalid OBFS4V variable name: $key (must be alphanumeric)"
            continue
          fi
          line_count=$(printf "%s" "$value" | wc -l)
          if [ "$line_count" -gt 0 ]; then
            warn "Skipping $key: value contains newlines ($line_count lines)"
            continue
          fi
          if printf "%s" "$value" | tr -d '[ -~]' | grep -q .; then
            warn "Skipping $key: value contains control characters"
            continue
          fi
          case "$torrc_key" in
            AccountingMax|AccountingStart|Address|AddressDisableIPv6|\
            BandwidthBurst|BandwidthRate|RelayBandwidthBurst|RelayBandwidthRate|\
            ContactInfo|DirPort|MaxMemInQueues|NumCPUs|ORPort|\
            OutboundBindAddress|OutboundBindAddressOR|Nickname|\
            ServerDNSAllowBrokenConfig|ServerDNSDetectHijacking)
              printf "%s %s\n" "$torrc_key" "$value" >> "$TOR_CONFIG"
              ;;
            *)
              warn "Skipping $key: torrc option '$torrc_key' not in whitelist"
              warn "  If you need this option, mount a custom torrc file instead"
              ;;
          esac
        done
      fi
      ;;

    *)
      die "Invalid TOR_RELAY_MODE: $TOR_RELAY_MODE (must be: guard, exit, or bridge)"
      ;;
  esac
}


render_config() (
  destination=$1
  TOR_CONFIG=$destination
  validate_relay_config
  generate_config_from_env
)
publish_env_config() (
  target=$1
  [ ! -L "$target" ] || die "Refusing symlink config"
  mkdir -p "$(dirname "$target")"
  umask 077
  candidate=$(mktemp "$(dirname "$target")/.torrc.XXXXXX")
  trap 'rm -f "$candidate"' 0
  render_config "$candidate"
  tor --verify-config -f "$candidate" >/dev/null 2>&1 || die "Generated configuration is invalid; original retained"
  mv "$candidate" "$target"
)
