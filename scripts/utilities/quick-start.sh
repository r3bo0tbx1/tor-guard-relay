#!/bin/sh
# quick-start.sh - Interactive Tor relay deployment script
# Helps beginners set up guard, exit, or bridge relays

set -e

# Color output helpers (if terminal supports it)
if [ -t 1 ]; then
    BOLD='\033[1m'
    GREEN='\033[0;32m'
    BLUE='\033[0;34m'
    YELLOW='\033[1;33m'
    RED='\033[0;31m'
    NC='\033[0m' # No Color
else
    BOLD=''
    GREEN=''
    BLUE=''
    YELLOW=''
    RED=''
    NC=''
fi

# Logging helpers
log() { printf "${BOLD}%s${NC}\n" "$1"; }
info() { printf "   ${BLUE}ℹ️  %s${NC}\n" "$1"; }
success() { printf "${GREEN}✅ %s${NC}\n" "$1"; }
warn() { printf "${YELLOW}⚠️  %s${NC}\n" "$1"; }
error() { printf "${RED}🛑 ERROR: %s${NC}\n" "$1"; exit 1; }

# Banner
show_banner() {
    cat << "EOF"
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🧅 Tor Guard Relay - Quick Start Setup
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

This script will help you deploy a Tor relay in minutes!

EOF
}

# Prompt for input with default value
prompt() {
    prompt_text="$1"
    default_val="$2"
    var_name="$3"

    if [ -n "$default_val" ]; then
        printf "${BOLD}%s${NC} [${GREEN}%s${NC}]: " "$prompt_text" "$default_val"
    else
        printf "${BOLD}%s${NC}: " "$prompt_text"
    fi

    read -r input
    if [ -z "$input" ]; then
        input="$default_val"
    fi

    eval "$var_name=\"\$input\""
}

# Validate nickname
validate_nickname() {
    nickname="$1"

    # Length check (1-19 characters)
    nickname_len=$(printf "%s" "$nickname" | wc -c)
    if [ "$nickname_len" -lt 1 ] || [ "$nickname_len" -gt 19 ]; then
        warn "Nickname must be 1-19 characters (you entered: $nickname_len)"
        return 1
    fi

    # Alphanumeric only
    if ! printf "%s" "$nickname" | grep -qE '^[a-zA-Z0-9]+$'; then
        warn "Nickname must contain only letters and numbers"
        return 1
    fi

    # Reserved names
    case "$(printf "%s" "$nickname" | tr '[:upper:]' '[:lower:]')" in
        unnamed|noname|default|tor|relay|bridge|exit)
            warn "Cannot use reserved name: $nickname"
            return 1
            ;;
    esac

    return 0
}

# Validate email
validate_email() {
    email="$1"

    # Basic length check
    email_len=$(printf "%s" "$email" | wc -c)
    if [ "$email_len" -lt 5 ]; then
        warn "Email must be at least 5 characters"
        return 1
    fi

    # Very basic email format check
    if ! printf "%s" "$email" | grep -qE '^[^@]+@[^@]+\.[^@]+$'; then
        warn "Email format appears invalid (should be: name@domain.com)"
        return 1
    fi

    return 0
}

# Validate port
validate_port() {
    port="$1"
    port_name="$2"

    # Integer check
    if ! printf "%s" "$port" | grep -qE '^[0-9]+$'; then
        warn "$port_name must be a valid number"
        return 1
    fi

    # Range check
    if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        warn "$port_name must be between 1-65535"
        return 1
    fi

    # Warn about privileged ports
    if [ "$port" -lt 1024 ]; then
        warn "$port_name is a privileged port (<1024) - may require CAP_NET_BIND_SERVICE capability"
    fi

    return 0
}

# Main menu
show_menu() {
    log ""
    log "What type of Tor relay do you want to run?"
    log ""
    printf "  ${BOLD}1)${NC} ${GREEN}Guard/Middle Relay${NC}   - Safest option, routes traffic\n"
    printf "  ${BOLD}2)${NC} ${YELLOW}Exit Relay${NC}          - Advanced, requires legal compliance\n"
    printf "  ${BOLD}3)${NC} ${BLUE}Bridge Relay${NC}         - Helps users in censored regions (obfs4)\n"
    printf "  ${BOLD}4)${NC} ${RED}Quit${NC}\n"
    log ""
}

# Collect common information
collect_common_info() {
    log ""
    log "📋 Basic Relay Information"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log ""

    # Nickname
    while true; do
        prompt "Relay Nickname (1-19 alphanumeric)" "MyTorRelay" NICKNAME
        if validate_nickname "$NICKNAME"; then
            success "Nickname accepted: $NICKNAME"
            break
        fi
    done

    log ""

    # Email
    while true; do
        prompt "Contact Email" "admin@example.com" EMAIL
        if validate_email "$EMAIL"; then
            success "Email accepted: $EMAIL"
            break
        fi
    done

    log ""

    # ORPort
    while true; do
        if [ "$RELAY_MODE" = "guard" ]; then
            prompt "ORPort (recommended: 443 or 9001)" "9001" OR_PORT
        elif [ "$RELAY_MODE" = "exit" ]; then
            prompt "ORPort (recommended: 443)" "443" OR_PORT
        else
            prompt "ORPort (recommended: 443 or 9001)" "9001" OR_PORT
        fi

        if validate_port "$OR_PORT" "ORPort"; then
            success "ORPort set to: $OR_PORT"
            break
        fi
    done
}

# Guard relay specific
collect_guard_info() {
    log ""
    log "⚙️  Guard Relay Configuration"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log ""

    info "Guard relays provide directory services and route traffic."
    info "They are the safest and easiest type of relay to operate."
    log ""

    # DirPort
    while true; do
        prompt "DirPort (set to 0 to disable)" "9030" DIR_PORT

        if [ "$DIR_PORT" = "0" ]; then
            success "DirPort disabled"
            break
        fi

        if validate_port "$DIR_PORT" "DirPort"; then
            success "DirPort set to: $DIR_PORT"
            break
        fi
    done

    log ""

    # Bandwidth
    prompt "Bandwidth Rate (e.g., 50 MBytes, leave empty for unlimited)" "" BANDWIDTH_RATE
    if [ -n "$BANDWIDTH_RATE" ]; then
        prompt "Bandwidth Burst (e.g., 100 MBytes)" "" BANDWIDTH_BURST
    fi
}

# Exit relay specific
collect_exit_info() {
    log ""
    log "⚠️  Exit Relay Configuration"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log ""

    warn "EXIT RELAYS ARE ADVANCED AND HAVE LEGAL IMPLICATIONS!"
    log ""
    info "Exit relays route traffic to the public internet."
    info "You WILL receive abuse complaints and may need to respond to legal requests."
    info "Make sure you understand the risks and legal requirements."
    log ""

    # Confirmation
    prompt "Are you sure you want to run an exit relay? (yes/no)" "no" CONFIRM

    if [ "$CONFIRM" != "yes" ] && [ "$CONFIRM" != "YES" ]; then
        error "Exit relay setup cancelled. Consider running a guard or bridge relay instead."
    fi

    log ""

    # DirPort
    while true; do
        prompt "DirPort (set to 0 to disable)" "9030" DIR_PORT

        if [ "$DIR_PORT" = "0" ]; then
            success "DirPort disabled"
            break
        fi

        if validate_port "$DIR_PORT" "DirPort"; then
            success "DirPort set to: $DIR_PORT"
            break
        fi
    done

    log ""

    # Exit policy
    log "Exit Policy Options:"
    printf "  ${BOLD}1)${NC} Reduced exit (recommended) - allows common ports\n"
    printf "  ${BOLD}2)${NC} Reject all (safer) - effectively a guard relay\n"
    printf "  ${BOLD}3)${NC} Custom policy - you provide the policy\n"
    log ""

    prompt "Exit Policy Choice" "1" POLICY_CHOICE

    case "$POLICY_CHOICE" in
        1)
            EXIT_POLICY="ExitPolicy accept *:80\\nExitPolicy accept *:443\\nExitPolicy reject *:*"
            info "Using reduced exit policy (HTTP/HTTPS only)"
            ;;
        2)
            EXIT_POLICY="ExitPolicy reject *:*"
            info "Using reject all policy"
            ;;
        3)
            prompt "Enter custom exit policy (e.g., 'ExitPolicy reject *:*')" "ExitPolicy reject *:*" EXIT_POLICY
            ;;
        *)
            EXIT_POLICY="ExitPolicy reject *:*"
            warn "Invalid choice, using reject all"
            ;;
    esac

    log ""

    # Bandwidth
    prompt "Bandwidth Rate (e.g., 50 MBytes, leave empty for unlimited)" "" BANDWIDTH_RATE
    if [ -n "$BANDWIDTH_RATE" ]; then
        prompt "Bandwidth Burst (e.g., 100 MBytes)" "" BANDWIDTH_BURST
    fi
}

# Bridge relay specific
collect_bridge_info() {
    log ""
    log "🌉 Bridge Relay Configuration"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log ""

    info "Bridge relays help users in censored regions access Tor."
    info "They use obfs4 pluggable transport to disguise Tor traffic."
    log ""

    # PT_PORT (obfs4 port)
    while true; do
        prompt "obfs4 Port (PT_PORT, recommended: 443 or 9002)" "9002" PT_PORT

        if validate_port "$PT_PORT" "PT_PORT"; then
            success "obfs4 Port set to: $PT_PORT"
            break
        fi
    done

    log ""

    # Bandwidth
    prompt "Bandwidth Rate (e.g., 50 MBytes, leave empty for unlimited)" "" BANDWIDTH_RATE
    if [ -n "$BANDWIDTH_RATE" ]; then
        prompt "Bandwidth Burst (e.g., 100 MBytes)" "" BANDWIDTH_BURST
    fi
}

# Generate docker run command
generate_docker_run() {
    log ""
    log "🐳 Docker Run Command"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log ""

    cat > /tmp/tor-relay-run.sh << EOF
#!/bin/sh
# Tor ${RELAY_MODE} Relay - Generated by quick-start.sh
# Run this script to start your Tor relay

docker run -d \\
  --name tor-${RELAY_MODE} \\
  --network host \\
  --restart unless-stopped \\
  --cap-drop ALL \\
  --cap-add NET_BIND_SERVICE \\
  --security-opt no-new-privileges \\
  -e NICKNAME="${NICKNAME}" \\
  -e EMAIL="${EMAIL}" \\
  -e OR_PORT=${OR_PORT} \\
EOF

    # Mode-specific additions
    if [ "$RELAY_MODE" = "guard" ]; then
        cat >> /tmp/tor-relay-run.sh << EOF
  -e TOR_RELAY_MODE=guard \\
  -e TOR_DIRPORT=${DIR_PORT} \\
EOF
    elif [ "$RELAY_MODE" = "exit" ]; then
        cat >> /tmp/tor-relay-run.sh << EOF
  -e TOR_RELAY_MODE=exit \\
  -e TOR_DIRPORT=${DIR_PORT} \\
  -e TOR_EXIT_POLICY="${EXIT_POLICY}" \\
EOF
    elif [ "$RELAY_MODE" = "bridge" ]; then
        cat >> /tmp/tor-relay-run.sh << EOF
  -e PT_PORT=${PT_PORT} \\
EOF
    fi

    # Bandwidth (if set)
    if [ -n "$BANDWIDTH_RATE" ]; then
        cat >> /tmp/tor-relay-run.sh << EOF
  -e TOR_BANDWIDTH_RATE="${BANDWIDTH_RATE}" \\
EOF
    fi

    if [ -n "$BANDWIDTH_BURST" ]; then
        cat >> /tmp/tor-relay-run.sh << EOF
  -e TOR_BANDWIDTH_BURST="${BANDWIDTH_BURST}" \\
EOF
    fi

    # Volumes and image
    cat >> /tmp/tor-relay-run.sh << EOF
  -v tor-${RELAY_MODE}-data:/var/lib/tor \\
  -v tor-${RELAY_MODE}-logs:/var/log/tor \\
  r3bo0tbx1/onion-relay:latest

# Wait for container to start
sleep 5

# Show container status
docker ps | grep tor-${RELAY_MODE}

echo ""
echo "✅ Tor ${RELAY_MODE} relay started!"
echo ""
echo "📋 Useful commands:"
echo "  docker logs tor-${RELAY_MODE}          - View logs"
echo "  docker exec tor-${RELAY_MODE} status   - Full health check"
echo "  docker exec tor-${RELAY_MODE} health   - JSON health API"
EOF

    if [ "$RELAY_MODE" = "bridge" ]; then
        cat >> /tmp/tor-relay-run.sh << EOF
echo "  docker exec tor-${RELAY_MODE} bridge-line - Get bridge line to share"
EOF
    else
        cat >> /tmp/tor-relay-run.sh << EOF
echo "  docker exec tor-${RELAY_MODE} fingerprint - Get relay fingerprint"
EOF
    fi

    chmod +x /tmp/tor-relay-run.sh

    success "Docker run script generated: /tmp/tor-relay-run.sh"
    log ""
    cat /tmp/tor-relay-run.sh
    log ""
}

# Generate docker-compose.yml
generate_docker_compose() {
    log ""
    log "🐳 Docker Compose Configuration"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log ""

    cat > /tmp/docker-compose.yml << EOF
# Tor ${RELAY_MODE} Relay - Generated by quick-start.sh
# Deploy with: docker-compose up -d

version: '3.8'

services:
  tor-${RELAY_MODE}:
    image: r3bo0tbx1/onion-relay:latest
    container_name: tor-${RELAY_MODE}
    restart: unless-stopped
    network_mode: host

    # Security settings
    cap_drop:
      - ALL
    cap_add:
      - NET_BIND_SERVICE
    security_opt:
      - no-new-privileges:true

    # Environment variables
    environment:
      NICKNAME: "${NICKNAME}"
      EMAIL: "${EMAIL}"
      OR_PORT: ${OR_PORT}
EOF

    # Mode-specific additions
    if [ "$RELAY_MODE" = "guard" ]; then
        cat >> /tmp/docker-compose.yml << EOF
      TOR_RELAY_MODE: guard
      TOR_DIRPORT: ${DIR_PORT}
EOF
    elif [ "$RELAY_MODE" = "exit" ]; then
        cat >> /tmp/docker-compose.yml << EOF
      TOR_RELAY_MODE: exit
      TOR_DIRPORT: ${DIR_PORT}
      TOR_EXIT_POLICY: "${EXIT_POLICY}"
EOF
    elif [ "$RELAY_MODE" = "bridge" ]; then
        cat >> /tmp/docker-compose.yml << EOF
      PT_PORT: ${PT_PORT}
EOF
    fi

    # Bandwidth (if set)
    if [ -n "$BANDWIDTH_RATE" ]; then
        cat >> /tmp/docker-compose.yml << EOF
      TOR_BANDWIDTH_RATE: "${BANDWIDTH_RATE}"
EOF
    fi

    if [ -n "$BANDWIDTH_BURST" ]; then
        cat >> /tmp/docker-compose.yml << EOF
      TOR_BANDWIDTH_BURST: "${BANDWIDTH_BURST}"
EOF
    fi

    # Volumes
    cat >> /tmp/docker-compose.yml << EOF

    # Data persistence
    volumes:
      - tor-${RELAY_MODE}-data:/var/lib/tor
      - tor-${RELAY_MODE}-logs:/var/log/tor

volumes:
  tor-${RELAY_MODE}-data:
    driver: local
  tor-${RELAY_MODE}-logs:
    driver: local
EOF

    success "Docker Compose file generated: /tmp/docker-compose.yml"
    log ""
    cat /tmp/docker-compose.yml
    log ""
}

# Next steps
show_next_steps() {
    log ""
    log "🚀 Next Steps"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log ""

    log "1. Review the generated configuration:"
    info "   - Docker run script: /tmp/tor-relay-run.sh"
    info "   - Docker Compose file: /tmp/docker-compose.yml"
    log ""

    log "2. Deploy your relay:"
    info "   ${BOLD}Option A:${NC} Run the script"
    info "     sh /tmp/tor-relay-run.sh"
    log ""
    info "   ${BOLD}Option B:${NC} Use Docker Compose"
    info "     cp /tmp/docker-compose.yml ~/tor-relay/"
    info "     cd ~/tor-relay && docker-compose up -d"
    log ""

    log "3. Monitor your relay:"
    info "   docker logs tor-${RELAY_MODE}"
    info "   docker exec tor-${RELAY_MODE} status"
    log ""

    if [ "$RELAY_MODE" = "bridge" ]; then
        log "4. Share your bridge line:"
        info "   Wait 2-5 minutes for Tor to bootstrap (100%)"
        info "   docker exec tor-${RELAY_MODE} bridge-line"
        info "   Share the output with users in censored regions"
        log ""
    else
        log "4. Find your relay on Tor Metrics:"
        info "   Wait 24-48 hours for your relay to appear"
        info "   docker exec tor-${RELAY_MODE} fingerprint"
        info "   Visit the Tor Metrics URL shown"
        log ""
    fi

    if [ "$RELAY_MODE" = "exit" ]; then
        warn "IMPORTANT FOR EXIT RELAYS:"
        info "   - Monitor abuse complaints: ${EMAIL}"
        info "   - Set up reverse DNS (PTR record) for your IP"
        info "   - Consider getting AS number and WHOIS info"
        info "   - Read: https://community.torproject.org/relay/community-resources/tor-exit-guidelines/"
        log ""
    fi

    log "5. Documentation:"
    info "   - FAQ: https://github.com/r3bo0tbx1/tor-guard-relay/blob/main/docs/FAQ.md"
    info "   - Architecture: https://github.com/r3bo0tbx1/tor-guard-relay/blob/main/docs/ARCHITECTURE.md"
    info "   - Monitoring: https://github.com/r3bo0tbx1/tor-guard-relay/blob/main/docs/MONITORING.md"
    log ""

    success "Setup complete! Thank you for supporting the Tor network! 🧅"
    log ""
}

# Main execution
main() {
    show_banner

    # Main menu loop
    while true; do
        show_menu
        prompt "Choose an option" "1" CHOICE

        case "$CHOICE" in
            1)
                RELAY_MODE="guard"
                collect_common_info
                collect_guard_info
                generate_docker_run
                generate_docker_compose
                show_next_steps
                exit 0
                ;;
            2)
                RELAY_MODE="exit"
                collect_common_info
                collect_exit_info
                generate_docker_run
                generate_docker_compose
                show_next_steps
                exit 0
                ;;
            3)
                RELAY_MODE="bridge"
                collect_common_info
                collect_bridge_info
                generate_docker_run
                generate_docker_compose
                show_next_steps
                exit 0
                ;;
            4)
                log ""
                log "👋 Goodbye! Thank you for considering running a Tor relay."
                log ""
                exit 0
                ;;
            *)
                warn "Invalid choice. Please select 1-4."
                ;;
        esac
    done
}

main "$@"
