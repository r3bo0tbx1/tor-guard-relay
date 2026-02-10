#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'
get_country_colors() {
    case "$1" in
        US) printf "${BLUE}U${RED}S${NC}" ;;
        DE) printf "${RED}D${YELLOW}E${NC}" ;;
        NL) printf "${RED}N${BLUE}L${NC}" ;;
        AT) printf "${RED}A${NC}T" ;;
        SE) printf "${BLUE}S${YELLOW}E${NC}" ;;
        CA) printf "${RED}C${NC}A" ;;
        *) printf "%s" "$1" ;;
    esac
}
declare -A authorities=(
    ["faravahar"]="216.218.219.41|443|80 2001:470:164:2::2|443|80"
    ["bastet"]="204.13.164.118|443|80 2620:13:4000:6000::1000:118|443|80"
    ["dannenberg"]="193.23.244.244|443|80 2001:678:558:1000::244|443|80"
    ["Serge"]="66.111.2.131|9001|9030 2610:1c0:0:5::131|9001|9030"
    ["dizum"]="45.66.35.11|443|80 2a09:61c0::1337|443|80"
    ["tor26"]="217.196.147.77|443|80 2a02:16a8:662:2203::1|443|80"
    ["maatuska"]="171.25.193.9|80|443 2001:67c:289c::9|80|443"
    ["moria1"]="128.31.0.39|9201|9231"
    ["gabelmoo"]="131.188.40.189|443|80 2001:638:a000:4140::ffff:189|443|80"
    ["longclaw"]="199.58.81.140|443|80"
)
AUTH_ORDER=(faravahar:US bastet:US dannenberg:DE Serge:US dizum:NL tor26:AT maatuska:SE moria1:US gabelmoo:DE longclaw:CA)
declare -a RELAY_IPV4_LIST RELAY_IPV6_LIST
declare -A results
total_tests=0 passed_tests=0 failed_tests=0
PORT_TEST_METHOD="none"
DELAY_BETWEEN_HOSTS=2
DELAY_BETWEEN_PORTS=0.5
MULTI_SOURCE=false
check_dependencies() {
    local missing=()
    command -v ip &>/dev/null || command -v ifconfig &>/dev/null || missing+=("ip or ifconfig")
    command -v ping &>/dev/null || missing+=("ping")
    for cmd in nc ncat nmap; do
        command -v "$cmd" &>/dev/null && PORT_TEST_METHOD="$cmd" && break
    done
    if [[ $PORT_TEST_METHOD == "none" ]]; then
        if bash -c 'echo >/dev/tcp/127.0.0.1/22' &>/dev/null 2>&1; then
            PORT_TEST_METHOD="bash"
        elif command -v curl &>/dev/null; then
            PORT_TEST_METHOD="curl"
        elif command -v python3 &>/dev/null; then
            PORT_TEST_METHOD="python3"
        fi
    fi
    if [[ $PORT_TEST_METHOD == "none" ]]; then
        echo -e "${RED}${BOLD}Error: No port-testing tool found!${NC}"
        echo -e "${YELLOW}Install one of: nc, ncat, nmap, curl, or python3${NC}"
        exit 1
    fi
    echo -e "${GREEN}Port test method:${NC} $PORT_TEST_METHOD"
    [[ ${#missing[@]} -gt 0 ]] && echo -e "${YELLOW}Warning: Missing tools: ${missing[*]}${NC}\n"
    if ! command -v timeout &>/dev/null; then
        echo -e "${YELLOW}Warning: 'timeout' not found, using built-in fallback.${NC}"
        timeout() {
            local duration=$1; shift
            "$@" & local pid=$!
            (sleep "$duration"; kill "$pid" 2>/dev/null) & local watcher=$!
            wait "$pid" 2>/dev/null; local ret=$?
            kill "$watcher" 2>/dev/null; wait "$watcher" 2>/dev/null
            return $ret
        }
    fi
}
print_header() {
    echo -e "${BOLD}${CYAN}"
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║    Tor Directory Authority Connectivity Check        ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}
detect_ipv4() {
    if command -v ip &>/dev/null; then
        ip -4 addr show 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '^127\.' | grep -v '^169\.254\.'
    elif command -v ifconfig &>/dev/null; then
        ifconfig 2>/dev/null | grep -oP 'inet\s+\K\d+(\.\d+){3}' | grep -v '^127\.' | grep -v '^169\.254\.'
    fi
}
detect_ipv6() {
    if command -v ip &>/dev/null; then
        ip -6 addr show scope global 2>/dev/null | grep -oP '(?<=inet6\s)[0-9a-f:]+' | grep -v '^::1' | grep -v '^fe80:'
    elif command -v ifconfig &>/dev/null; then
        ifconfig 2>/dev/null | grep -oP 'inet6\s+\K[0-9a-f:]+' | grep -v '^::1' | grep -v '^fe80:'
    fi
}
select_ips() {
    local label=$1 detect_fn=$2
    local -n _ip_list=$3
    local detected=()
    echo -e "${BOLD}${CYAN}═══ $label Configuration ═══${NC}"
    mapfile -t detected < <("$detect_fn")
    if [[ ${#detected[@]} -eq 0 ]]; then
        echo -e "${YELLOW}No $label addresses detected.${NC}"
        echo -ne "${CYAN}Enter $label address manually (or press Enter to skip): ${NC}"
        read -r manual_ip
        [[ -n "$manual_ip" ]] && _ip_list+=("$manual_ip")
    elif [[ ${#detected[@]} -eq 1 ]]; then
        echo -e "${GREEN}Detected $label: ${detected[0]}${NC}"
        echo -ne "${CYAN}Use this address? (Y/n): ${NC}"
        read -r confirm
        [[ $confirm =~ ^[Nn]$ ]] || _ip_list+=("${detected[0]}")
    else
        echo -e "${GREEN}Detected multiple $label addresses:${NC}"
        for i in "${!detected[@]}"; do
            echo -e "  ${CYAN}[$((i+1))]${NC} ${detected[$i]}"
        done
        echo -e "  ${CYAN}[A]${NC} Use all addresses\n"
        echo -ne "${CYAN}Select (1-${#detected[@]}/A, comma-separated): ${NC}"
        read -r choice
        if [[ $choice =~ ^[Aa]$ ]]; then
            _ip_list=("${detected[@]}")
        else
            IFS=',' read -ra indices <<< "$choice"
            for idx in "${indices[@]}"; do
                idx=$(echo "$idx" | xargs)
                if [[ $idx =~ ^([0-9]+)-([0-9]+)$ ]]; then
                    local start="${BASH_REMATCH[1]}" end="${BASH_REMATCH[2]}"
                    for ((n=start; n<=end; n++)); do
                        [[ $n -ge 1 && $n -le ${#detected[@]} ]] && _ip_list+=("${detected[$((n-1))]}")
                    done
                elif [[ $idx -ge 1 && $idx -le ${#detected[@]} ]]; then
                    _ip_list+=("${detected[$((idx-1))]}")
                fi
            done
        fi
    fi
}
get_user_ips() {
    clear
    print_header
    echo -e "${BOLD}${YELLOW}Detecting IP addresses...${NC}\n"
    select_ips "IPv4" detect_ipv4 RELAY_IPV4_LIST
    echo ""
    select_ips "IPv6" detect_ipv6 RELAY_IPV6_LIST
    echo ""
    if [[ ${#RELAY_IPV4_LIST[@]} -eq 0 && ${#RELAY_IPV6_LIST[@]} -eq 0 ]]; then
        echo -e "${RED}Error: No IP addresses configured!${NC}"
        exit 1
    fi
    [[ ${#RELAY_IPV4_LIST[@]} -gt 1 || ${#RELAY_IPV6_LIST[@]} -gt 1 ]] && MULTI_SOURCE=true
    echo -e "${BOLD}${GREEN}Configuration saved!${NC}"
    [[ ${#RELAY_IPV4_LIST[@]} -gt 0 ]] && echo -e "${BOLD}IPv4 (${#RELAY_IPV4_LIST[@]}):${NC} ${RELAY_IPV4_LIST[*]}"
    [[ ${#RELAY_IPV6_LIST[@]} -gt 0 ]] && echo -e "${BOLD}IPv6 (${#RELAY_IPV6_LIST[@]}):${NC} ${RELAY_IPV6_LIST[*]}"
    echo ""
}
test_port_connect() {
    local ip=$1 port=$2 proto=$3
    case "$PORT_TEST_METHOD" in
        nc|ncat)
            local opts="-z -w 2"
            [[ $proto == "IPv6" ]] && opts="$opts -6"
            timeout 3 "$PORT_TEST_METHOD" $opts "$ip" "$port" 2>/dev/null
            ;;
        nmap)
            timeout 5 nmap -Pn -p "$port" "$ip" 2>/dev/null | grep -q "^${port}/.*open"
            ;;
        bash)
            [[ $proto == "IPv6" ]] && return 1
            timeout 3 bash -c "echo >/dev/tcp/$ip/$port" 2>/dev/null
            ;;
        curl)
            local target="$ip"
            [[ $proto == "IPv6" ]] && target="[$ip]"
            timeout 3 curl -sf --connect-timeout 2 "http://${target}:$port" -o /dev/null 2>/dev/null
            local ret=$?
            [[ $ret -ne 7 && $ret -ne 28 ]]
            ;;
        python3)
            timeout 5 python3 -c "
import socket, sys
af = socket.AF_INET6 if ':' in '$ip' else socket.AF_INET
s = socket.socket(af, socket.SOCK_STREAM)
s.settimeout(3)
try: s.connect(('$ip', $port)); s.close(); sys.exit(0)
except: sys.exit(1)" 2>/dev/null
            ;;
    esac
}
test_port() {
    local ip=$1 port=$2 port_type=$3 proto=$4
    ((total_tests++))
    printf "${YELLOW}      │ PORT %-5s (%s): ${NC}Testing..." "$port" "$port_type"
    if test_port_connect "$ip" "$port" "$proto"; then
        printf "\r${GREEN}      │ PORT %-5s (%s): ✓ OPEN          ${NC}\n" "$port" "$port_type"
        ((passed_tests++))
        return 0
    else
        printf "\r${RED}      │ PORT %-5s (%s): ✗ CLOSED        ${NC}\n" "$port" "$port_type"
        ((failed_tests++))
        return 1
    fi
}
test_authority() {
    local auth_name=$1 endpoint=$2 source_ip=$3
    local ip port1 port2 proto
    IFS='|' read -r ip port1 port2 <<< "$endpoint"
    [[ $ip =~ : ]] && proto="IPv6" || proto="IPv4"
    [[ $MULTI_SOURCE == true ]] && echo -e "${BOLD}${BLUE}  └󰩠 $proto: $ip (from: $source_ip)${NC}" || echo -e "${BOLD}${BLUE}  └󰩠 $proto: $ip${NC}"
    local ping_cmd="ping -c 2 -W 2"
    [[ $proto == "IPv6" ]] && ping_cmd="ping -6 -c 2 -W 2"
    echo -ne "${YELLOW}      │ PING: ${NC}Testing..."
    $ping_cmd "$ip" >/dev/null 2>&1 && echo -e "\r${GREEN}      │ PING: ✓ REACHABLE          ${NC}" || echo -e "\r${YELLOW}      │ PING: ⚠ UNREACHABLE (info) ${NC}"
    sleep "$DELAY_BETWEEN_PORTS"
    test_port "$ip" "$port1" "OR" "$proto"
    local port1_result=$?
    local port2_result=0
    if [[ -n "$port2" ]]; then
        sleep "$DELAY_BETWEEN_PORTS"
        test_port "$ip" "$port2" "Dir" "$proto"
        port2_result=$?
    fi
    if [[ $port1_result -eq 0 && $port2_result -eq 0 ]]; then
        results["${auth_name}_${ip}_${source_ip}"]="OK"
    else
        results["${auth_name}_${ip}_${source_ip}"]="FAIL"
    fi
    echo ""
}
print_summary() {
    echo ""
    print_header
    echo -e "${BOLD}${CYAN}════════════════ TEST SUMMARY ════════════════${NC}\n"
    local success_rate=0
    [[ $total_tests -gt 0 ]] && success_rate=$((passed_tests * 100 / total_tests))
    echo -e "${BOLD}Port Tests:${NC}       $total_tests"
    echo -e "${GREEN}${BOLD}Passed:${NC}           $passed_tests"
    echo -e "${RED}${BOLD}Failed:${NC}           $failed_tests"
    echo -e "${BOLD}Success Rate:${NC}     ${success_rate}%"
    echo -e "${BOLD}Port Test Tool:${NC}   ${PORT_TEST_METHOD}"
    echo -e "${YELLOW}${BOLD}Note:${NC}             Ping is informational only (ICMP often blocked)\n"
    echo -e "${BOLD}${CYAN}═══════════ Authority Status ═══════════${NC}\n"
    for entry in "${AUTH_ORDER[@]}"; do
        local auth_name="${entry%%:*}" cc="${entry##*:}"
        local cc_colored=$(get_country_colors "$cc")
        echo -e "${BOLD}${MAGENTA}$auth_name${NC} ${CYAN}[${cc_colored}${CYAN}]${NC}${BOLD}:${NC}"
        local auth_ok=0 auth_total=0
        for key in "${!results[@]}"; do
            [[ $key == ${auth_name}_* ]] || continue
            ((auth_total++))
            local status=${results[$key]} ip_info=${key#${auth_name}_}
            [[ $status == "OK" ]] && { echo -e "  ${GREEN}✓${NC} ${ip_info//_/ → }"; ((auth_ok++)); } || echo -e "  ${RED}✗${NC} ${ip_info//_/ → }"
        done
        [[ $auth_total -eq $auth_ok && $auth_total -gt 0 ]] && echo -e "  ${GREEN}${BOLD}→ ALL PORTS OPEN${NC}" || [[ $auth_total -gt 0 ]] && echo -e "  ${YELLOW}${BOLD}→ $auth_ok/$auth_total ports reachable${NC}"
        echo ""
    done
    echo -e "${BOLD}${CYAN}══════════════════════════════════════════════${NC}"
    echo -e "${BOLD}Tested from:${NC}"
    [[ ${#RELAY_IPV4_LIST[@]} -gt 0 ]] && { echo -e "  ${CYAN}IPv4:${NC}"; for ip in "${RELAY_IPV4_LIST[@]}"; do echo "    → $ip"; done; }
    [[ ${#RELAY_IPV6_LIST[@]} -gt 0 ]] && { echo -e "  ${CYAN}IPv6:${NC}"; for ip in "${RELAY_IPV6_LIST[@]}"; do echo "    → $ip"; done; }
    echo -e "${BOLD}Completed:${NC} $(date '+%Y-%m-%d %H:%M:%S')\n"
}
check_dependencies
get_user_ips
echo -e "${BOLD}Testing configuration:${NC}"
[[ ${#RELAY_IPV4_LIST[@]} -gt 0 ]] && echo -e "  ${CYAN}IPv4 (${#RELAY_IPV4_LIST[@]}):${NC} ${RELAY_IPV4_LIST[*]}"
[[ ${#RELAY_IPV6_LIST[@]} -gt 0 ]] && echo -e "  ${CYAN}IPv6 (${#RELAY_IPV6_LIST[@]}):${NC} ${RELAY_IPV6_LIST[*]}"
echo -e "\n${YELLOW}⚠ Rate limiting: ${DELAY_BETWEEN_HOSTS}s between hosts, ${DELAY_BETWEEN_PORTS}s between ports${NC}\n"
read -rp "Press Enter to start testing..."
echo ""
for entry in "${AUTH_ORDER[@]}"; do
    auth_name="${entry%%:*}"
    cc="${entry##*:}"
    cc_colored=$(get_country_colors "$cc")
    echo -e "${BOLD}${MAGENTA}┌────────────────────────────────┐${NC}"
    echo -e "${BOLD}${MAGENTA}│ ${NC}${BOLD}Testing: ${CYAN}${auth_name}${NC} ${MAGENTA}[${cc_colored}${MAGENTA}]$(printf "%$((21-${#auth_name}-${#cc}))s" "") ${BOLD}${MAGENTA}│${NC}"
    echo -e "${BOLD}${MAGENTA}└────────────────────────────────┘${NC}"
    for endpoint in ${authorities[$auth_name]}; do
        IFS='|' read -r target_ip _ _ <<< "$endpoint"
        if [[ $target_ip =~ : ]]; then
            for source_ip in "${RELAY_IPV6_LIST[@]}"; do test_authority "$auth_name" "$endpoint" "$source_ip"; done
        else
            for source_ip in "${RELAY_IPV4_LIST[@]}"; do test_authority "$auth_name" "$endpoint" "$source_ip"; done
        fi
    done
    sleep "$DELAY_BETWEEN_HOSTS"
done
print_summary
