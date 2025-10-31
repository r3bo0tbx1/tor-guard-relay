#!/bin/bash
#
# relay-status.sh — Tor relay/bridge status checker
# Automatically detects Tor containers or uses specified container name
#

set -euo pipefail

# Configuration
CONTAINER="${1:-}"  # Accept container name as first argument
readonly FINGERPRINT_PATH="/var/lib/tor/fingerprint"
readonly TORRC_PATH="/etc/tor/torrc"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Helper functions
print_header() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_section() {
    echo -e "\n${CYAN}▶ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# Detect Tor container automatically
detect_tor_container() {
    local containers
    containers=$(sudo docker ps --format '{{.Names}}' | grep -iE 'tor|relay|bridge|onion' || true)
    
    if [[ -z "${containers}" ]]; then
        print_error "No Tor-related containers found running"
        echo
        print_info "Running containers:"
        sudo docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}' | sed 's/^/  /'
        echo
        print_info "Usage: $0 [container-name]"
        exit 1
    fi
    
    local count
    count=$(echo "${containers}" | wc -l)
    
    if [[ ${count} -eq 1 ]]; then
        CONTAINER="${containers}"
        print_success "Auto-detected container: ${CONTAINER}"
    else
        print_warning "Multiple Tor containers found:"
        echo "${containers}" | sed 's/^/  - /'
        echo
        print_info "Please specify which container to check:"
        print_info "Usage: $0 <container-name>"
        echo
        print_info "Example: $0 ${containers%$'\n'*}"
        exit 1
    fi
}

# Check if container is running
check_container() {
    print_section "Container Status"
    
    if ! sudo docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
        print_error "Container '${CONTAINER}' is not running"
        exit 1
    fi
    
    print_success "Container '${CONTAINER}' is running"
    
    # Show uptime
    local uptime
    uptime=$(sudo docker inspect -f '{{.State.StartedAt}}' "${CONTAINER}" 2>/dev/null)
    if [[ -n "${uptime}" ]]; then
        echo -e "  ${BLUE}Started:${NC} ${uptime}"
    fi
    
    # Show image version
    local image
    image=$(sudo docker inspect -f '{{.Config.Image}}' "${CONTAINER}" 2>/dev/null)
    if [[ -n "${image}" ]]; then
        echo -e "  ${BLUE}Image:${NC} ${image}"
    fi
}

# Display recent logs
show_logs() {
    print_section "Recent Logs (last 15 lines)"
    sudo docker logs --tail 15 "${CONTAINER}" 2>&1 | sed 's/^/  /'
}

# Show bootstrap progress
show_bootstrap() {
    print_section "Bootstrap Progress"
    
    local bootstrap_logs
    bootstrap_logs=$(sudo docker logs "${CONTAINER}" 2>&1 | grep "Bootstrapped" | tail -5)
    
    if [[ -n "${bootstrap_logs}" ]]; then
        echo "${bootstrap_logs}" | sed 's/^/  /'
        
        # Check if fully bootstrapped
        if echo "${bootstrap_logs}" | grep -q "Bootstrapped 100%"; then
            echo
            print_success "Relay is fully bootstrapped!"
        fi
    else
        print_warning "No bootstrap messages found in logs"
        print_info "Relay might still be starting up"
    fi
}

# Check if relay is reachable
check_reachability() {
    print_section "Reachability Status"
    
    local reachable_logs
    reachable_logs=$(sudo docker logs "${CONTAINER}" 2>&1 | grep -iE "reachable|self-testing" | tail -3)
    
    if [[ -n "${reachable_logs}" ]]; then
        echo "${reachable_logs}" | sed 's/^/  /'
        
        if echo "${reachable_logs}" | grep -q "reachable from the outside"; then
            echo
            print_success "ORPort is reachable!"
        fi
    else
        print_warning "No reachability test results yet"
    fi
}

# Display fingerprint
show_fingerprint() {
    print_section "Relay Fingerprint"
    
    if sudo docker exec "${CONTAINER}" test -f "${FINGERPRINT_PATH}" 2>/dev/null; then
        local fingerprint
        fingerprint=$(sudo docker exec "${CONTAINER}" cat "${FINGERPRINT_PATH}")
        echo -e "  ${GREEN}${fingerprint}${NC}"
        echo
        print_info "Search on Tor Metrics: https://metrics.torproject.org/rs.html"
        print_info "Search on Onion Metrics: http://hctxrvjzfpvmzh2jllqhgvvkoepxb4kfzdjm6h7egcwlumggtktiftid.onion/rs.html"
    else
        print_warning "Fingerprint not found yet"
        print_info "Tor might still be bootstrapping or generating keys"
    fi
}

# Show ORPort configuration
show_orport() {
    print_section "ORPort Configuration"
    
    local orport_config
    orport_config=$(sudo docker exec "${CONTAINER}" grep -iE "^(ORPort|DirPort|ObfsPort)" "${TORRC_PATH}" 2>/dev/null || true)
    
    if [[ -n "${orport_config}" ]]; then
        echo "${orport_config}" | sed 's/^/  /'
    else
        print_warning "No ORPort configuration found"
    fi
}

# Show relay type and settings
show_relay_info() {
    print_section "Relay Information"
    
    local relay_info
    relay_info=$(sudo docker exec "${CONTAINER}" grep -iE "^(Nickname|ContactInfo|ExitRelay|BridgeRelay)" "${TORRC_PATH}" 2>/dev/null || true)
    
    if [[ -n "${relay_info}" ]]; then
        echo "${relay_info}" | sed 's/^/  /'
    else
        print_warning "No relay information found in config"
    fi
}

# Check for errors
check_errors() {
    print_section "Recent Errors/Warnings"
    
    local errors
    errors=$(sudo docker logs "${CONTAINER}" 2>&1 | grep -iE "(error|warn|critical)" | tail -5)
    
    if [[ -n "${errors}" ]]; then
        echo "${errors}" | sed 's/^/  /'
    else
        print_success "No recent errors or warnings"
    fi
}

# Show resource usage
show_resources() {
    print_section "Resource Usage"
    
    if command -v docker &> /dev/null; then
        local stats
        stats=$(sudo docker stats "${CONTAINER}" --no-stream --format "table {{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}" 2>/dev/null || true)
        
        if [[ -n "${stats}" ]]; then
            echo "${stats}" | sed 's/^/  /'
        fi
    fi
}

# Show quick help
show_help() {
    cat << EOF
${BLUE}Tor Relay Status Checker${NC}

Usage: $0 [container-name]

If no container name is provided, the script will attempt to auto-detect
Tor containers by searching for containers with names containing:
  tor, relay, bridge, or onion

Examples:
  $0                    # Auto-detect Tor container
  $0 guard-relay        # Check specific container
  $0 my-tor-bridge      # Check bridge container

Options:
  -h, --help           Show this help message

EOF
}

# Main execution
main() {
    # Check for help flag
    if [[ "${1:-}" =~ ^(-h|--help)$ ]]; then
        show_help
        exit 0
    fi
    
    # Detect container if not specified
    if [[ -z "${CONTAINER}" ]]; then
        detect_tor_container
    fi
    
    print_header "🧅 Tor Relay Status Check: ${CONTAINER}"
    
    check_container
    show_relay_info
    show_logs
    show_bootstrap
    check_reachability
    show_fingerprint
    show_orport
    check_errors
    show_resources
    
    echo
    print_header "✅ Status Check Complete"
    echo
    print_info "For live monitoring, use: sudo docker logs -f ${CONTAINER}"
    echo
}

# Run main function
main "$@"