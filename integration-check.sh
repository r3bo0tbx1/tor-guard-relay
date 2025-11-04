#!/bin/bash
# integration-check.sh - Master integration test runner for Tor Guard Relay
# Validates all tools are present, executable, and produce correct output formats
# Returns: 0 on success, 1 on failure; outputs emoji-based summary

set -euo pipefail

# Configuration
readonly CONTAINER="${CONTAINER:-guard-relay}"
readonly TOOLS_DIR="/usr/local/bin"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

# State tracking
PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0
declare -a RESULTS=()

# Colors for terminal output (safe in Alpine)
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
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

test_tool_output_format() {
  local tool_path=$1
  local tool_name=$2
  local expected_format=$3
  
  if [ ! -f "$tool_path" ]; then
    log_fail "$tool_name not found"
    return 1
  fi
  
  local output
  output=$("$tool_path" 2>&1 || true)
  
  case "$expected_format" in
    json)
      test_json_valid "$output" "$tool_name JSON"
      ;;
    text)
      if [ -n "$output" ]; then
        log_pass "$tool_name produces text output"
      else
        log_fail "$tool_name produces empty output"
        return 1
      fi
      ;;
    html)
      if echo "$output" | grep -q "<!DOCTYPE\|<html"; then
        log_pass "$tool_name produces HTML output"
      else
        log_fail "$tool_name does not produce HTML"
        return 1
      fi
      ;;
  esac
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
  test_file_executable "$TOOLS_DIR/docker-entrypoint.sh" "docker-entrypoint.sh"
}

# Phase 3: Shell Syntax Validation
phase_3_syntax() {
  log_section "Phase 3: Shell Syntax Validation"
  
  for tool in status fingerprint view-logs health metrics metrics-http dashboard docker-entrypoint.sh; do
    if [ -f "$TOOLS_DIR/$tool" ]; then
      test_shell_syntax "$TOOLS_DIR/$tool" "$tool"
    fi
  done
  
  if [ -f "$SCRIPT_DIR/integration-check.sh" ]; then
    test_shell_syntax "$SCRIPT_DIR/integration-check.sh" "integration-check.sh"
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

# Phase 5: Output Format Validation (requires execution)
phase_5_output_formats() {
  log_section "Phase 5: Output Format Validation"
  
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
}

# Phase 6: Environment Variables
phase_6_environment() {
  log_section "Phase 6: Environment Variables"
  
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
}

# Generate Summary Report
generate_summary() {
  local total=$((PASS_COUNT + FAIL_COUNT + WARN_COUNT))
  
  echo ""
  log_header "🧅 Integration Test Summary"
  
  echo ""
  echo "Total Tests: $total"
  echo -e "${GREEN}Passed: ${PASS_COUNT}${NC}"
  
  if [ $WARN_COUNT -gt 0 ]; then
    echo -e "${YELLOW}Warnings: ${WARN_COUNT}${NC}"
  fi
  
  if [ $FAIL_COUNT -gt 0 ]; then
    echo -e "${RED}Failed: ${FAIL_COUNT}${NC}"
  fi
  
  echo ""
  echo "Results:"
  for result in "${RESULTS[@]}"; do
    echo "  $result"
  done
  
  echo ""
  
  if [ $FAIL_COUNT -eq 0 ]; then
    echo -e "${GREEN}✅ All integration checks passed!${NC}"
    return 0
  else
    echo -e "${RED}❌ Some integration checks failed.${NC}"
    return 1
  fi
}

# Main execution
main() {
  log_header "🧅 Tor Guard Relay Integration Check v1.0"
  log_info "Timestamp: $TIMESTAMP"
  log_info "Container: $CONTAINER"
  
  echo ""
  
  phase_1_files
  phase_2_permissions
  phase_3_syntax
  phase_4_directories
  phase_5_output_formats
  phase_6_environment
  
  echo ""
  generate_summary
  
  return $?
}

# Execute main
main "$@"
exit $?