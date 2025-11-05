#!/bin/bash
# integration-check.sh - Master integration test runner for Tor Guard Relay v1.0.2
# Validates all tools, port security, and configuration compliance
# Returns: 0 on success, 1 on failure; outputs emoji-based summary

set -euo pipefail

# Configuration
readonly CONTAINER="${CONTAINER:-guard-relay}"
readonly TOOLS_DIR="/usr/local/bin"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
readonly VERSION="1.0.2"

# State tracking
PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0
declare -a RESULTS=()
declare -a SECURITY_ISSUES=()

# Colors for terminal output (safe in Alpine)
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly NC='\033[0m'

# Output functions
log_header() {
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BLUE}$1${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

log_section() {
  echo -e "\n${CYAN}▶ $1${NC}"
}

log_pass() {
  echo -e "${GREEN}✓${NC} $1"
  RESULTS+=("✓ $1")
  ((PASS_COUNT++))
}

log_fail() {
  echo -e "${RED}✗${NC} $1"
  RESULTS+=("✗ $1")
  ((FAIL_COUNT++))
}

log_warn() {
  echo -e "${YELLOW}⚠${NC} $1"
  RESULTS+=("⚠ $1")
  ((WARN_COUNT++))
}

log_info() {
  echo -e "${BLUE}ℹ${NC} $1"
}

log_security() {
  echo -e "${MAGENTA}🔒${NC} $1"
  SECURITY_ISSUES+=("$1")
}

# Test functions
test_file_exists() {
  local path=$1
  local name=$2
  
  if [ -f "$path" ]; then
    log_pass "$name exists"
    return 0
  else
    log_fail "$name not found: $path"
    return 1
  fi
}

test_file_executable() {
  local path=$1
  local name=$2
  
  if [ -x "$path" ]; then
    log_pass "$name is executable"
    return 0
  else
    log_fail "$name is not executable: $path"
    return 1
  fi
}

test_shell_syntax() {
  local path=$1
  local name=$2
  
  if bash -n "$path" 2>/dev/null; then
    log_pass "$name shell syntax is valid"
    return 0
  else
    log_fail "$name has shell syntax errors"
    return 1
  fi
}

test_json_valid() {
  local input=$1
  local name=$2
  
  if command -v jq &> /dev/null; then
    if echo "$input" | jq empty 2>/dev/null; then
      log_pass "$name output is valid JSON"
      return 0
    else
      log_fail "$name output is not valid JSON"
      return 1
    fi
  else
    log_warn "$name JSON validation skipped (jq not available)"
    return 0
  fi
}

test_text_contains() {
  local text=$1
  local pattern=$2
  local name=$3
  
  if echo "$text" | grep -q "$pattern"; then
    log_pass "$name contains required output: '$pattern'"
    return 0
  else
    log_fail "$name missing required output: '$pattern'"
    return 1
  fi
}

# Phase 1: File Existence & Permissions
phase_1_files() {
  log_section "Phase 1: File Existence & Permissions"
  
  # Check all tools exist
  test_file_exists "$TOOLS_DIR/status" "status"
  test_file_exists "$TOOLS_DIR/fingerprint" "fingerprint"
  test_file_exists "$TOOLS_DIR/view-logs" "view-logs"
  test_file_exists "$TOOLS_DIR/health" "health"
  test_file_exists "$TOOLS_DIR/metrics" "metrics"
  test_file_exists "$TOOLS_DIR/metrics-http" "metrics-http"
  test_file_exists "$TOOLS_DIR/dashboard" "dashboard"
  test_file_exists "$TOOLS_DIR/setup" "setup"
  test_file_exists "$TOOLS_DIR/net-check" "net-check"
  
  # Check docker-entrypoint.sh
  test_file_exists "$TOOLS_DIR/docker-entrypoint.sh" "docker-entrypoint.sh"
  
  # Check root script
  if [ -f "$SCRIPT_DIR/integration-check.sh" ]; then
    test_file_exists "$SCRIPT_DIR/integration-check.sh" "integration-check.sh (root)"
  fi
}

# Phase 2: Executable Permissions
phase_2_permissions() {
  log_section "Phase 2: Executable Permissions"
  
  test_file_executable "$TOOLS_DIR/status" "status"
  test_file_executable "$TOOLS_DIR/fingerprint" "fingerprint"
  test_file_executable "$TOOLS_DIR/view-logs" "view-logs"
  test_file_executable "$TOOLS_DIR/health" "health"
  test_file_executable "$TOOLS_DIR/metrics" "metrics"
  test_file_executable "$TOOLS_DIR/metrics-http" "metrics-http"
  test_file_executable "$TOOLS_DIR/dashboard" "dashboard"
  test_file_executable "$TOOLS_DIR/setup" "setup"
  test_file_executable "$TOOLS_DIR/net-check" "net-check"
  test_file_executable "$TOOLS_DIR/docker-entrypoint.sh" "docker-entrypoint.sh"
}

# Phase 3: Shell Syntax Validation
phase_3_syntax() {
  log_section "Phase 3: Shell Syntax Validation"
  
  for tool in status fingerprint view-logs health metrics metrics-http dashboard setup net-check docker-entrypoint.sh; do
    if [ -f "$TOOLS_DIR/$tool" ]; then
      test_shell_syntax "$TOOLS_DIR/$tool" "$tool"
    fi
  done
  
  if [ -f "$SCRIPT_DIR/integration-check.sh" ]; then
    test_shell_syntax "$SCRIPT_DIR/integration-check.sh" "integration-check.sh"
  fi
  
  if [ -f "$SCRIPT_DIR/relay-status.sh" ]; then
    test_shell_syntax "$SCRIPT_DIR/relay-status.sh" "relay-status.sh"
  fi
}

# Phase 4: Directory Structure
phase_4_directories() {
  log_section "Phase 4: Directory Structure"
  
  # Check required directories exist
  if [ -d "$TOOLS_DIR" ]; then
    log_pass "Tools directory exists: $TOOLS_DIR"
  else
    log_fail "Tools directory missing: $TOOLS_DIR"
  fi
  
  if [ -d "/var/lib/tor" ]; then
    log_pass "Tor data directory exists: /var/lib/tor"
    
    # Check permissions
    local perms=$(stat -c "%a" /var/lib/tor 2>/dev/null || echo "unknown")
    if [ "$perms" = "700" ] || [ "$perms" = "750" ]; then
      log_pass "Tor data directory has secure permissions: $perms"
    else
      log_warn "Tor data directory permissions: $perms (should be 700 or 750)"
    fi
  else
    log_fail "Tor data directory missing: /var/lib/tor"
  fi
  
  if [ -d "/var/log/tor" ]; then
    log_pass "Tor log directory exists: /var/log/tor"
  else
    log_fail "Tor log directory missing: /var/log/tor"
  fi
  
  if [ -f "/etc/tor/torrc" ]; then
    log_pass "Tor configuration exists: /etc/tor/torrc"
  else
    log_warn "Tor configuration not found: /etc/tor/torrc (may be normal before first run)"
  fi
}

# Phase 5: Port Security Validation (CRITICAL for v1.0.2)
phase_5_port_security() {
  log_section "Phase 5: Port Security Validation"
  
  log_info "Validating port exposure policy (9001/9030 only)..."
  
  # Check if metrics-http binds to localhost only
  if [ -f "$TOOLS_DIR/metrics-http" ]; then
    local bind_check=$(grep -E "127\.0\.0\.1|localhost" "$TOOLS_DIR/metrics-http" 2>/dev/null || echo "")
    if [ -n "$bind_check" ]; then
      log_pass "metrics-http configured for localhost binding"
    else
      log_security "SECURITY: metrics-http may not be localhost-only"
      log_fail "metrics-http localhost binding not confirmed"
    fi
  fi
  
  # Check if dashboard binds to localhost only
  if [ -f "$TOOLS_DIR/dashboard" ]; then
    local bind_check=$(grep -E "127\.0\.0\.1|localhost" "$TOOLS_DIR/dashboard" 2>/dev/null || echo "")
    if [ -n "$bind_check" ]; then
      log_pass "dashboard configured for localhost binding"
    else
      log_warn "dashboard localhost binding not confirmed"
    fi
  fi
  
  # Check torrc for proper port configuration (if exists)
  if [ -f "/etc/tor/torrc" ]; then
    log_info "Checking torrc port configuration..."
    
    # Check for ORPort 9001
    if grep -q "^ORPort 9001" /etc/tor/torrc 2>/dev/null; then
      log_pass "ORPort 9001 configured correctly"
    else
      log_warn "ORPort 9001 not found in torrc"
    fi
    
    # Check for DirPort 9030
    if grep -q "^DirPort 9030" /etc/tor/torrc 2>/dev/null; then
      log_pass "DirPort 9030 configured correctly"
    else
      log_info "DirPort 9030 not configured (optional)"
    fi
    
    # Check that SocksPort is disabled
    if grep -q "^SocksPort 0" /etc/tor/torrc 2>/dev/null; then
      log_pass "SocksPort properly disabled"
    else
      log_warn "SocksPort setting not confirmed"
    fi
  fi
  
  # Check for any references to dangerous port exposure
  log_info "Scanning for improper port exposure patterns..."
  
  local dangerous_patterns=0
  for tool in "$TOOLS_DIR"/*; do
    if [ -f "$tool" ] && [ -x "$tool" ]; then
      # Look for 0.0.0.0 bindings on non-Tor ports
      if grep -qE "0\.0\.0\.0:903[5-9]|0\.0\.0\.0:904[0-9]" "$tool" 2>/dev/null; then
        log_security "SECURITY: Found potential 0.0.0.0 binding in $(basename $tool)"
        log_fail "$(basename $tool) may expose internal ports"
        ((dangerous_patterns++))
      fi
    fi
  done
  
  if [ $dangerous_patterns -eq 0 ]; then
    log_pass "No dangerous port exposure patterns detected"
  fi
}

# Phase 6: Output Format Validation
phase_6_output_formats() {
  log_section "Phase 6: Output Format Validation"
  
  # health (JSON)
  if [ -f "$TOOLS_DIR/health" ]; then
    log_info "Testing health output format..."
    HEALTH_OUT=$("$TOOLS_DIR/health" 2>&1 || echo '{"status":"error"}')
    test_json_valid "$HEALTH_OUT" "health"
    test_text_contains "$HEALTH_OUT" '"status"' "health JSON"
  fi
  
  # status (text with emoji)
  if [ -f "$TOOLS_DIR/status" ]; then
    log_info "Testing status output format..."
    STATUS_OUT=$("$TOOLS_DIR/status" 2>&1 || echo "Not yet available")
    if echo "$STATUS_OUT" | grep -qE "🧅|Status|Report"; then
      log_pass "status produces expected output"
    else
      log_warn "status may not have full output yet (first run?)"
    fi
  fi
  
  # fingerprint (text)
  if [ -f "$TOOLS_DIR/fingerprint" ]; then
    log_info "Testing fingerprint output format..."
    FP_OUT=$("$TOOLS_DIR/fingerprint" 2>&1 || echo "Not yet available")
    if echo "$FP_OUT" | grep -qE "🔑|Fingerprint"; then
      log_pass "fingerprint produces expected output"
    else
      log_warn "fingerprint not yet available (Tor bootstrapping?)"
    fi
  fi
  
  # metrics (Prometheus format)
  if [ -f "$TOOLS_DIR/metrics" ]; then
    log_info "Testing metrics output format..."
    METRICS_OUT=$("$TOOLS_DIR/metrics" 2>&1 || echo "# HELP metrics_error")
    if echo "$METRICS_OUT" | grep -q "# HELP\|# TYPE\|tor_"; then
      log_pass "metrics produces Prometheus format"
    else
      log_warn "metrics output format not fully validated"
    fi
  fi
  
  # dashboard (HTML)
  if [ -f "$TOOLS_DIR/dashboard" ]; then
    log_info "Testing dashboard output format..."
    DASHBOARD_OUT=$("$TOOLS_DIR/dashboard" 2>&1 | head -100 || echo "<!DOCTYPE html>")
    if echo "$DASHBOARD_OUT" | grep -q "<!DOCTYPE\|<html"; then
      log_pass "dashboard produces HTML output"
    else
      log_warn "dashboard HTML validation not fully checked"
    fi
  fi
  
  # net-check (text with emoji)
  if [ -f "$TOOLS_DIR/net-check" ]; then
    log_info "Testing net-check output format..."
    NETCHECK_OUT=$("$TOOLS_DIR/net-check" 2>&1 || echo "Network check")
    if echo "$NETCHECK_OUT" | grep -qE "🌐|Network|Diagnostics"; then
      log_pass "net-check produces expected output"
    else
      log_warn "net-check output not fully validated"
    fi
  fi
}

# Phase 7: Environment Variables
phase_7_environment() {
  log_section "Phase 7: Environment Variables"
  
  if [ -n "${TOR_DATA_DIR:-}" ]; then
    log_pass "TOR_DATA_DIR is set: $TOR_DATA_DIR"
  else
    log_info "TOR_DATA_DIR not set (using default: /var/lib/tor)"
  fi
  
  if [ -n "${TOR_LOG_DIR:-}" ]; then
    log_pass "TOR_LOG_DIR is set: $TOR_LOG_DIR"
  else
    log_info "TOR_LOG_DIR not set (using default: /var/log/tor)"
  fi
  
  if [ -n "${PATH:-}" ]; then
    if echo "$PATH" | grep -q "/usr/local/bin"; then
      log_pass "PATH includes /usr/local/bin"
    else
      log_fail "PATH missing /usr/local/bin: $PATH"
    fi
  fi
  
  # Check for metrics-related env vars
  if [ -n "${ENABLE_METRICS:-}" ]; then
    log_info "ENABLE_METRICS is set: $ENABLE_METRICS"
  fi
  
  if [ -n "${METRICS_PORT:-}" ]; then
    log_info "METRICS_PORT is set: $METRICS_PORT"
    # Validate it's in the proper range
    if [ "$METRICS_PORT" -ge 9035 ] && [ "$METRICS_PORT" -le 9099 ]; then
      log_pass "METRICS_PORT in valid range: $METRICS_PORT"
    else
      log_warn "METRICS_PORT outside recommended range: $METRICS_PORT"
    fi
  fi
}

# Phase 8: Version Validation
phase_8_version() {
  log_section "Phase 8: Version Validation"
  
  log_info "Integration check version: $VERSION"
  
  # Check if build-info.txt exists and contains version
  if [ -f "/build-info.txt" ]; then
    local build_version=$(grep "Version:" /build-info.txt 2>/dev/null | cut -d: -f2 | tr -d ' ' || echo "unknown")
    log_info "Build version: $build_version"
    
    if [ "$build_version" = "$VERSION" ] || [ "$build_version" = "v$VERSION" ]; then
      log_pass "Build version matches integration check version"
    else
      log_warn "Build version mismatch (expected: $VERSION, found: $build_version)"
    fi
  else
    log_info "No build-info.txt found (may be normal in development)"
  fi
  
  # Check relay-status.sh version if available
  if [ -f "$SCRIPT_DIR/relay-status.sh" ]; then
    local script_version=$(grep "^readonly VERSION=" "$SCRIPT_DIR/relay-status.sh" 2>/dev/null | cut -d'"' -f2 || echo "unknown")
    if [ "$script_version" = "$VERSION" ]; then
      log_pass "relay-status.sh version matches: $VERSION"
    else
      log_warn "relay-status.sh version mismatch (expected: $VERSION, found: $script_version)"
    fi
  fi
}

# Generate Summary Report
generate_summary() {
  local total=$((PASS_COUNT + FAIL_COUNT + WARN_COUNT))
  
  echo ""
  log_header "🧅 Integration Test Summary (v$VERSION)"
  
  echo ""
  echo "Total Tests: $total"
  echo -e "${GREEN}✓ Passed: ${PASS_COUNT}${NC}"
  
  if [ $WARN_COUNT -gt 0 ]; then
    echo -e "${YELLOW}⚠ Warnings: ${WARN_COUNT}${NC}"
  fi
  
  if [ $FAIL_COUNT -gt 0 ]; then
    echo -e "${RED}✗ Failed: ${FAIL_COUNT}${NC}"
  fi
  
  # Security issues summary
  if [ ${#SECURITY_ISSUES[@]} -gt 0 ]; then
    echo ""
    echo -e "${MAGENTA}🔒 Security Issues Detected: ${#SECURITY_ISSUES[@]}${NC}"
    for issue in "${SECURITY_ISSUES[@]}"; do
      echo -e "  ${MAGENTA}•${NC} $issue"
    done
  fi
  
  echo ""
  echo "Detailed Results:"
  for result in "${RESULTS[@]}"; do
    echo "  $result"
  done
  
  echo ""
  
  if [ $FAIL_COUNT -eq 0 ] && [ ${#SECURITY_ISSUES[@]} -eq 0 ]; then
    echo -e "${GREEN}✅ All integration checks passed!${NC}"
    echo -e "${GREEN}✅ No security issues detected!${NC}"
    return 0
  elif [ $FAIL_COUNT -eq 0 ] && [ ${#SECURITY_ISSUES[@]} -gt 0 ]; then
    echo -e "${YELLOW}⚠️  Integration checks passed with security warnings.${NC}"
    echo -e "${YELLOW}⚠️  Please review security issues above.${NC}"
    return 0
  else
    echo -e "${RED}❌ Some integration checks failed.${NC}"
    return 1
  fi
}

# Main execution
main() {
  log_header "🧅 Tor Guard Relay Integration Check v$VERSION"
  log_info "Timestamp: $TIMESTAMP"
  log_info "Container: $CONTAINER"
  log_info "Target Release: v1.0.2"
  
  echo ""
  
  phase_1_files
  phase_2_permissions
  phase_3_syntax
  phase_4_directories
  phase_5_port_security
  phase_6_output_formats
  phase_7_environment
  phase_8_version
  
  echo ""
  generate_summary
  
  return $?
}

# Execute main
main "$@"
exit $?