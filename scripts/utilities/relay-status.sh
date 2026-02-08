#!/bin/bash
#
# relay-status.sh — Tor relay/bridge status checker with security validation
# Version: 1.1.6
# Automatically detects Tor containers or uses specified container name
#

set -euo pipefail

# Configuration
CONTAINER="${1:-}"  # Accept container name as first argument
readonly FINGERPRINT_PATH="/var/lib/tor/fingerprint"
readonly TORRC_PATH="/etc/tor/torrc"
readonly VERSION="1.1.6"

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
    
    # Check build info if available
    local build_info
    build_info=$(sudo docker exec "${CONTAINER}" cat /build-info.txt 2>/dev/null || echo "")
    if [[ -n "${build_info}" ]]; then
        echo -e "  ${BLUE}Build:${NC}"
        echo "${build_info}" | sed 's/^/    /'
    fi
}

# Validate port security configuration
check_port_security() {
    print_section "Port Security Validation"
    
    # Check exposed ports
    local exposed_ports
    exposed_ports=$(sudo docker port "${CONTAINER}" 2>/dev/null || echo "")
    
    if [[ -n "${exposed_ports}" ]]; then
        echo -e "  ${BLUE}Exposed ports:${NC}"
        echo "${exposed_ports}" | sed 's/^/    /'
        
        # Validate only 9001 and 9030 are exposed
        if echo "${exposed_ports}" | grep -qE "^9001/tcp"; then
            print_success "ORPort 9001 properly exposed"
        else
            print_warning "ORPort 9001 not exposed (may be using host network)"
        fi
        
        if echo "${exposed_ports}" | grep -qE "^9030/tcp"; then
            print_success "DirPort 9030 properly exposed"
        fi
        
        # Check for improperly exposed internal ports
        if echo "${exposed_ports}" | grep -qE "^903[5-9]/tcp"; then
            print_error "SECURITY ISSUE: Internal metrics port exposed externally!"
            echo -e "  ${RED}Fix: Ensure metrics bind to 127.0.0.1 only${NC}"
        fi
    else
        print_info "Using host network mode - checking port bindings..."
    fi
    
    # Check internal service bindings
    local internal_bindings
    internal_bindings=$(sudo docker exec "${CONTAINER}" netstat -tlnp 2>/dev/null | grep -E "9035|9036|9037" || echo "")
    
    if [[ -n "${internal_bindings}" ]]; then
        echo -e "\n  ${BLUE}Internal services:${NC}"
        
        # Validate localhost-only bindings
        while IFS= read -r line; do
            if echo "${line}" | grep -q "127.0.0.1"; then
                local port
                port=$(echo "${line}" | awk '{print $4}' | cut -d':' -f2)
                print_success "Port ${port} properly bound to localhost"
            else
                local port
                port=$(echo "${line}" | awk '{print $4}' | cut -d':' -f2)
                print_error "SECURITY ISSUE: Port ${port} not bound to localhost!"
            fi
        done <<< "${internal_bindings}"
    else
        print_info "No internal service ports detected"
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
        
        # Validate port numbers
        if echo "${orport_config}" | grep -q "ORPort 9001"; then
            print_success "ORPort configured correctly (9001)"
        fi
        
        if echo "${orport_config}" | grep -q "DirPort 9030"; then
            print_success "DirPort configured correctly (9030)"
        fi
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
        
        # Validate relay type
        if echo "${relay_info}" | grep -q "ExitRelay 0"; then
            print_success "Configured as guard/middle relay (not exit)"
        elif echo "${relay_info}" | grep -q "ExitRelay 1"; then
            print_warning "Configured as EXIT relay (higher legal risk)"
        fi
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

# Show network diagnostics
show_network_diagnostics() {
    print_section "Network Diagnostics"

    print_info "Basic network connectivity check..."

    # IPv4 check
    if sudo docker exec "${CONTAINER}" curl -4 -s --max-time 5 https://icanhazip.com &>/dev/null; then
        print_success "IPv4 connectivity OK"
    else
        print_warning "IPv4 connectivity issues"
    fi

    # IPv6 check
    if sudo docker exec "${CONTAINER}" curl -6 -s --max-time 5 https://icanhazip.com &>/dev/null; then
        print_success "IPv6 connectivity OK"
    else
        print_info "IPv6 not available or configured"
    fi
}

# Show quick help
show_help() {
    cat << EOF
${BLUE}Tor Relay Status Checker v${VERSION}${NC}

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
  -v, --version        Show version information

Security Checks:
  - Port exposure validation (9001/9030 only)
  - Internal service binding verification (127.0.0.1)
  - Bootstrap and reachability status
  - Error detection and reporting

EOF
}

# Show version
show_version() {
    echo "relay-status.sh version ${VERSION}"
    echo "Part of Tor Guard Relay v1.1.6"
}

# Main execution
main() {
    # Check for help flag
    if [[ "${1:-}" =~ ^(-h|--help)$ ]]; then
        show_help
        exit 0
    fi
    
    # Check for version flag
    if [[ "${1:-}" =~ ^(-v|--version)$ ]]; then
        show_version
        exit 0
    fi
    
    # Detect container if not specified
    if [[ -z "${CONTAINER}" ]]; then
        detect_tor_container
    fi
    
    print_header "🧅 Tor Relay Status Check: ${CONTAINER} (v${VERSION})"
    
    check_container
    check_port_security
    show_relay_info
    show_logs
    show_bootstrap
    check_reachability
    show_fingerprint
    show_orport
    check_errors
    show_resources
    show_network_diagnostics
    
    echo
    print_header "✅ Status Check Complete"
    echo
    print_info "For live monitoring, use: sudo docker logs -f ${CONTAINER}"
    print_info "For detailed diagnostics, use: sudo docker exec ${CONTAINER} status"
    echo
}

# Run main function
main "$@"