#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

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

declare -a RELAY_IPV4_LIST
declare -a RELAY_IPV6_LIST
DELAY_BETWEEN_HOSTS=2
DELAY_BETWEEN_PORTS=0.5
MULTI_SOURCE=false

declare -A results
total_tests=0
passed_tests=0
failed_tests=0

PORT_TEST_METHOD="none"

check_dependencies() {
    local missing=()

    if ! command -v ip &>/dev/null && ! command -v ifconfig &>/dev/null; then
        missing+=("ip or ifconfig (for address detection)")
    fi

    if ! command -v ping &>/dev/null; then
        missing+=("ping")
    fi

    for cmd in nc ncat nmap; do
        command -v "$cmd" &>/dev/null && PORT_TEST_METHOD="$cmd" && break
    done
    if [[ $PORT_TEST_METHOD == "none" ]]; then
        if [[ -e /dev/tcp ]] || bash -c 'echo >/dev/tcp/127.0.0.1/22' &>/dev/null 2>&1; then
            PORT_TEST_METHOD="bash"
        elif command -v curl &>/dev/null; then
            PORT_TEST_METHOD="curl"
        elif command -v python3 &>/dev/null; then
            PORT_TEST_METHOD="python3"
        fi
    fi

    if [[ $PORT_TEST_METHOD == "none" ]]; then
        echo -e "${RED}${BOLD}Error: No port-testing tool found!${NC}"
        echo -e "${YELLOW}Install one of the following:${NC}"
        echo -e "  ${CYAN}•${NC} nc / netcat      ${YELLOW}(apt install netcat-openbsd)${NC}"
        echo -e "  ${CYAN}•${NC} ncat              ${YELLOW}(apt install ncat)${NC}"
        echo -e "  ${CYAN}•${NC} nmap              ${YELLOW}(apt install nmap)${NC}"
        echo -e "  ${CYAN}•${NC} curl              ${YELLOW}(apt install curl)${NC}"
        echo -e "  ${CYAN}•${NC} python3           ${YELLOW}(apt install python3)${NC}"
        echo ""
        echo -e "${YELLOW}Alternatively, bash /dev/tcp may work on some systems.${NC}"
        exit 1
    fi

    echo -e "${GREEN}Port test method:${NC} $PORT_TEST_METHOD"

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo -e "${YELLOW}${BOLD}Warning: Missing optional tools:${NC}"
        for dep in "${missing[@]}"; do
            echo -e "  ${YELLOW}•${NC} $dep"
        done
        echo ""
    fi

    if ! command -v timeout &>/dev/null; then
        echo -e "${YELLOW}Warning: 'timeout' not found, using built-in fallback.${NC}"
        timeout() {
            local duration=$1
            shift
            "$@" &
            local pid=$!
            (
                sleep "$duration"
                kill "$pid" 2>/dev/null
            ) &
            local watcher=$!
            wait "$pid" 2>/dev/null
            local ret=$?
            kill "$watcher" 2>/dev/null
            wait "$watcher" 2>/dev/null
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

print_section() {
    local padded
    padded=$(printf "%-30s" "Testing: $1 [$2]")
    echo -e "${BOLD}${MAGENTA}┌────────────────────────────────┐${NC}"
    echo -e "${BOLD}${MAGENTA}│ ${padded} │${NC}"
    echo -e "${BOLD}${MAGENTA}└────────────────────────────────┘${NC}"
}

print_subsection() {
    echo -e "${BOLD}${BLUE}  ├─ $1${NC}"
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
    local label=$1
    local detect_fn=$2
    local -n _ip_list=$3

    echo -e "${BOLD}${CYAN}═══ $label Configuration ═══${NC}"

    local detected=()
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
        if [[ $confirm =~ ^[Nn]$ ]]; then
            echo -ne "${CYAN}Enter $label address manually: ${NC}"
            read -r manual_ip
            [[ -n "$manual_ip" ]] && _ip_list+=("$manual_ip")
        else
            _ip_list+=("${detected[0]}")
        fi
    else
        echo -e "${GREEN}Detected multiple $label addresses:${NC}"
        for i in "${!detected[@]}"; do
            echo -e "  ${CYAN}[$((i+1))]${NC} ${detected[$i]}"
        done
        echo -e "  ${CYAN}[A]${NC} Use all addresses"
        echo -e "  ${CYAN}[M]${NC} Enter manually"
        echo ""

        while true; do
            echo -ne "${CYAN}Select option (1-${#detected[@]}/A/M, e.g. 1,3 or 1-3): ${NC}"
            read -r choice

            if [[ $choice =~ ^[Aa]$ ]]; then
                _ip_list=("${detected[@]}")
                break
            elif [[ $choice =~ ^[Mm]$ ]]; then
                echo -ne "${CYAN}Enter $label addresses (comma-separated): ${NC}"
                read -r manual_ips
                IFS=',' read -ra _ip_list <<< "$manual_ips"
                for i in "${!_ip_list[@]}"; do
                    _ip_list[$i]=$(echo "${_ip_list[$i]}" | xargs)
                done
                break
            else
                local parsed=() valid=true
                IFS=',' read -ra tokens <<< "$choice"
                for token in "${tokens[@]}"; do
                    token=$(echo "$token" | xargs)
                    if [[ $token =~ ^([0-9]+)-([0-9]+)$ ]]; then
                        local range_start="${BASH_REMATCH[1]}" range_end="${BASH_REMATCH[2]}"
                        if [[ $range_start -ge 1 && $range_end -le ${#detected[@]} && $range_start -le $range_end ]]; then
                            for (( n=range_start; n<=range_end; n++ )); do
                                parsed+=("$n")
                            done
                        else
                            valid=false; break
                        fi
                    elif [[ $token =~ ^[0-9]+$ ]] && [[ $token -ge 1 ]] && [[ $token -le ${#detected[@]} ]]; then
                        parsed+=("$token")
                    else
                        valid=false; break
                    fi
                done
                if [[ $valid == true && ${#parsed[@]} -gt 0 ]]; then
                    local -A seen
                    for idx in "${parsed[@]}"; do
                        if [[ -z ${seen[$idx]+x} ]]; then
                            seen[$idx]=1
                            _ip_list+=("${detected[$((idx-1))]}")
                        fi
                    done
                    break
                else
                    echo -e "${RED}Invalid option. Please try again.${NC}"
                fi
            fi
        done
    fi
}

get_user_ips() {
    clear
    print_header

    echo -e "${BOLD}${YELLOW}Detecting IP addresses...${NC}"
    echo ""

    select_ips "IPv4" detect_ipv4 RELAY_IPV4_LIST
    echo ""
    select_ips "IPv6" detect_ipv6 RELAY_IPV6_LIST
    echo ""

    if [[ ${#RELAY_IPV4_LIST[@]} -eq 0 ]] && [[ ${#RELAY_IPV6_LIST[@]} -eq 0 ]]; then
        echo -e "${RED}Error: No IP addresses configured!${NC}"
        exit 1
    fi

    if [[ ${#RELAY_IPV4_LIST[@]} -gt 1 ]] || [[ ${#RELAY_IPV6_LIST[@]} -gt 1 ]]; then
        MULTI_SOURCE=true
    fi

    echo -e "${BOLD}${GREEN}Configuration saved!${NC}"
    for label_var in RELAY_IPV4_LIST RELAY_IPV6_LIST; do
        local -n _arr=$label_var
        if [[ ${#_arr[@]} -gt 0 ]]; then
            echo -e "${BOLD}${label_var//_/ } (${#_arr[@]}):${NC}"
            for ip in "${_arr[@]}"; do
                echo -e "  ${CYAN}→${NC} $ip"
            done
        fi
    done
    echo ""
}

test_ping() {
    local ip=$1
    local proto=$2

    local ping_cmd
    if [[ $proto == "IPv6" ]]; then
        ping_cmd="ping -6 -c 2 -W 2"
    else
        ping_cmd="ping -c 2 -W 2"
    fi

    echo -ne "${YELLOW}    │ PING: ${NC}Testing..."

    if $ping_cmd "$ip" >/dev/null 2>&1; then
        echo -e "\r${GREEN}    │ PING: ✓ REACHABLE          ${NC}"
    else
        echo -e "\r${YELLOW}    │ PING: ⚠ UNREACHABLE (info) ${NC}"
    fi
}

_curl_port_test() {
    local target="$1"
    [[ $3 == "IPv6" ]] && target="[$1]"
    local ret
    timeout 3 curl -sf --connect-timeout 2 "http://${target}:$2" -o /dev/null 2>/dev/null
    ret=$?
    [[ $ret -ne 7 && $ret -ne 28 ]]
}

_test_port_connect() {
    local ip=$1
    local port=$2
    local proto=$3

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
            if [[ $proto == "IPv6" ]]; then
                command -v curl &>/dev/null && _curl_port_test "$ip" "$port" "$proto" || return 1
            else
                timeout 3 bash -c "echo >/dev/tcp/$ip/$port" 2>/dev/null
            fi
            ;;
        curl)
            _curl_port_test "$ip" "$port" "$proto"
            ;;
        python3)
            local target_ip="$ip"
            timeout 5 python3 -c "
import socket, sys
try:
    af = socket.AF_INET6 if ':' in '$target_ip' else socket.AF_INET
    s = socket.socket(af, socket.SOCK_STREAM)
    s.settimeout(3)
    s.connect(('$target_ip', $port))
    s.close()
    sys.exit(0)
except Exception:
    sys.exit(1)
" 2>/dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

test_port() {
    local ip=$1
    local port=$2
    local port_type=$3
    local proto=$4

    ((total_tests++))

    printf "${YELLOW}    │ PORT %-5s (%3s): ${NC}Testing..." "$port" "$port_type"

    if _test_port_connect "$ip" "$port" "$proto"; then
        printf "\r${GREEN}    │ PORT %-5s (%3s): ✓ OPEN          ${NC}\n" "$port" "$port_type"
        ((passed_tests++))
        return 0
    else
        printf "\r${RED}    │ PORT %-5s (%3s): ✗ CLOSED        ${NC}\n" "$port" "$port_type"
        ((failed_tests++))
        return 1
    fi
}

test_authority() {
    local auth_name=$1
    local endpoint=$2
    local source_ip=$3

    local ip port1 port2
    IFS='|' read -r ip port1 port2 <<< "$endpoint"

    local proto
    if [[ $ip =~ : ]]; then
        proto="IPv6"
    else
        proto="IPv4"
    fi

    if [[ $MULTI_SOURCE == true ]]; then
        print_subsection "$proto: $ip (from: $source_ip)"
    else
        print_subsection "$proto: $ip"
    fi

    local key="${auth_name}_${ip}_${source_ip}"
    results[$key]="TESTING"

    test_ping "$ip" "$proto"

    sleep "$DELAY_BETWEEN_PORTS"

    test_port "$ip" "$port1" "OR" "$proto"
    local port1_result=$?

    local port2_result=0
    if [[ -n "$port2" ]]; then
        sleep "$DELAY_BETWEEN_PORTS"
        test_port "$ip" "$port2" "Dir" "$proto"
        port2_result=$?
    fi

    if [[ $port1_result -eq 0 ]] && [[ $port2_result -eq 0 ]]; then
        results[$key]="OK"
    else
        results[$key]="FAIL"
    fi

    echo ""
}

print_summary() {
    echo ""
    print_header
    echo -e "${BOLD}${CYAN}════════════════ TEST SUMMARY ════════════════${NC}"
    echo ""

    local success_rate=0
    [[ $total_tests -gt 0 ]] && success_rate=$((passed_tests * 100 / total_tests))

    echo -e "${BOLD}Port Tests:${NC}       $total_tests"
    echo -e "${GREEN}${BOLD}Passed:${NC}           $passed_tests"
    echo -e "${RED}${BOLD}Failed:${NC}           $failed_tests"
    echo -e "${BOLD}Success Rate:${NC}     ${success_rate}%"
    echo -e "${BOLD}Port Test Tool:${NC}   ${PORT_TEST_METHOD}"
    echo -e "${YELLOW}${BOLD}Note:${NC}             Ping is informational only (ICMP often blocked)"
    echo ""

    echo -e "${BOLD}${CYAN}═══════════ Authority Status ═══════════${NC}"
    echo ""

    for entry in "${AUTH_ORDER[@]}"; do
        local auth_name="${entry%%:*}" cc="${entry##*:}"
        echo -e "${BOLD}${MAGENTA}$auth_name${NC} ${CYAN}[$cc]${NC}${BOLD}:${NC}"

        local auth_ok=0 auth_total=0

        for key in "${!results[@]}"; do
            [[ $key == ${auth_name}_* ]] || continue
            ((auth_total++))
            local status=${results[$key]}
            local ip_info=${key#${auth_name}_}
            local color symbol

            if [[ $status == "OK" ]]; then
                color=$GREEN; symbol="✓"; ((auth_ok++))
            else
                color=$RED; symbol="✗"
            fi

            if [[ $MULTI_SOURCE == true ]]; then
                echo -e "  ${color}${symbol}${NC} ${ip_info//_/ → }"
            else
                echo -e "  ${color}${symbol}${NC} ${ip_info%%_*}"
            fi
        done

        if [[ $auth_total -eq $auth_ok ]] && [[ $auth_total -gt 0 ]]; then
            echo -e "  ${GREEN}${BOLD}→ ALL PORTS OPEN${NC}"
        elif [[ $auth_total -gt 0 ]]; then
            echo -e "  ${YELLOW}${BOLD}→ $auth_ok/$auth_total ports reachable${NC}"
        else
            echo -e "  ${YELLOW}→ SKIPPED (no matching source IP)${NC}"
        fi
        echo ""
    done

    echo -e "${BOLD}${CYAN}══════════════════════════════════════════════${NC}"
    echo -e "${BOLD}Tested from:${NC}"
    if [[ ${#RELAY_IPV4_LIST[@]} -gt 0 ]]; then
        echo -e "  ${CYAN}IPv4:${NC}"
        for ip in "${RELAY_IPV4_LIST[@]}"; do echo -e "    → $ip"; done
    fi
    if [[ ${#RELAY_IPV6_LIST[@]} -gt 0 ]]; then
        echo -e "  ${CYAN}IPv6:${NC}"
        for ip in "${RELAY_IPV6_LIST[@]}"; do echo -e "    → $ip"; done
    fi
    echo -e "${BOLD}Completed:${NC} $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
}

check_dependencies
get_user_ips

echo -e "${BOLD}Testing configuration:${NC}"
[[ ${#RELAY_IPV4_LIST[@]} -gt 0 ]] && echo -e "  ${CYAN}IPv4 (${#RELAY_IPV4_LIST[@]}):${NC} ${RELAY_IPV4_LIST[*]}"
[[ ${#RELAY_IPV6_LIST[@]} -gt 0 ]] && echo -e "  ${CYAN}IPv6 (${#RELAY_IPV6_LIST[@]}):${NC} ${RELAY_IPV6_LIST[*]}"
echo ""
echo -e "${YELLOW}⚠ Rate limiting: ${DELAY_BETWEEN_HOSTS}s between hosts, ${DELAY_BETWEEN_PORTS}s between ports${NC}"
echo ""

read -rp "Press Enter to start testing..."
echo ""

for entry in "${AUTH_ORDER[@]}"; do
    auth_name="${entry%%:*}"
    print_section "$auth_name" "${entry##*:}"

    for endpoint in ${authorities[$auth_name]}; do
        IFS='|' read -r target_ip _ _ <<< "$endpoint"

        if [[ $target_ip =~ : ]]; then
            for source_ip in "${RELAY_IPV6_LIST[@]}"; do
                test_authority "$auth_name" "$endpoint" "$source_ip"
            done
        else
            for source_ip in "${RELAY_IPV4_LIST[@]}"; do
                test_authority "$auth_name" "$endpoint" "$source_ip"
            done
        fi
    done

    sleep "$DELAY_BETWEEN_HOSTS"
done

print_summary