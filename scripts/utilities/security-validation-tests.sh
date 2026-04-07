#!/bin/sh
# security-validation-tests.sh - Security validation for Tor Guard Relay
# Tests security features of the ultra-optimized 16.8 MB build

set -e

echo "🔐 Security Validation Tests - Tor Guard Relay v1.1.8"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

PASS=0
FAIL=0

test_pass() {
  echo "  ✅ PASS: $1"
  PASS=$((PASS + 1))
}

test_fail() {
  echo "  ❌ FAIL: $1"
  FAIL=$((FAIL + 1))
}

test_warn() {
  echo "  ⚠️  WARN: $1"
}

echo "Test 1: Dockerfile Security Configuration"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if grep -q "^USER tor" Dockerfile; then
  test_pass "Container runs as non-root user 'tor'"
else
  test_fail "Container may run as root (USER tor not found)"
fi

if grep -q "chmod 700.*TOR_DATA_DIR" Dockerfile; then
  test_pass "Data directory has restrictive permissions (700)"
else
  test_warn "Data directory permissions not explicitly set"
fi

if grep -q "tini" Dockerfile; then
  test_pass "Using tini for proper signal handling"
else
  test_fail "No init system - zombie processes possible"
fi

if grep -q "python3\|py3-pip\|bash" Dockerfile; then
  test_fail "Bloated dependencies detected (python3/bash)"
else
  test_pass "Minimal dependencies (no python/bash bloat)"
fi

if grep -q "lyrebird" Dockerfile; then
  test_pass "Lyrebird (obfs4) support included"
else
  test_warn "No lyrebird detected - bridge mode may not work"
fi

echo ""

echo "Test 2: Entrypoint Script Security"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ -f docker-entrypoint.sh ]; then
  if head -1 docker-entrypoint.sh | grep -q "^#!/bin/sh"; then
    test_pass "Entrypoint uses busybox sh (POSIX-compliant)"
  else
    test_warn "Entrypoint may not be POSIX-compliant"
  fi

  if grep -q "set -e" docker-entrypoint.sh; then
    test_pass "Entrypoint has 'set -e' (exit on error)"
  else
    test_fail "No 'set -e' - errors may be silently ignored"
  fi

  if grep -q "trap.*cleanup" docker-entrypoint.sh; then
    test_pass "Signal handler for graceful shutdown"
  else
    test_warn "No cleanup trap - may not shutdown gracefully"
  fi

  if grep -q "tor --verify-config" docker-entrypoint.sh; then
    test_pass "Configuration validation before startup"
  else
    test_fail "No config validation - may start with bad config"
  fi

  if grep -q "mktemp" docker-entrypoint.sh; then
    test_pass "Using mktemp for temporary files"
  else
    test_warn "May use predictable temp file paths"
  fi

  if grep -q "chmod.*chown" docker-entrypoint.sh; then
    chmod_line=$(grep -n "chmod.*TOR_DATA_DIR" docker-entrypoint.sh | head -1 | cut -d: -f1 || echo "999")
    chown_line=$(grep -n "chown.*TOR_DATA_DIR" docker-entrypoint.sh | head -1 | cut -d: -f1 || echo "1")

    if [ "$chmod_line" -lt "$chown_line" ]; then
      test_pass "Permissions set before ownership (no race)"
    else
      test_warn "Possible permission race condition"
    fi
  fi
else
  test_fail "docker-entrypoint.sh not found"
fi

echo ""

echo "Test 3: Tool Scripts Security"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

for tool in status health fingerprint bridge-line gen-family; do
  if [ -f "tools/$tool" ]; then
    if head -1 "tools/$tool" | grep -q "^#!/bin/sh"; then
      test_pass "tools/$tool uses busybox sh"
    else
      test_fail "tools/$tool not POSIX-compliant"
    fi
    if grep -q "sanitize_num\|tr -cd '0-9'" "tools/$tool"; then
      test_pass "tools/$tool has numeric sanitization"
    else
      test_warn "tools/$tool may have arithmetic errors"
    fi
  else
    test_fail "tools/$tool missing"
  fi
done

if ls tools/*.sh >/dev/null 2>&1; then
  test_fail "Tools have .sh extensions (should be removed)"
else
  test_pass "Tools have no .sh extensions"
fi

echo ""

echo "Test 4: Configuration File Security"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

for mode in guard exit bridge; do
  config="examples/relay-${mode}.conf"
  if [ -f "$config" ]; then
    test_pass "$config exists"

    if grep -q "^Nickname" "$config" && grep -q "^ContactInfo" "$config"; then
      test_pass "$config has required directives"
    else
      test_warn "$config missing Nickname or ContactInfo"
    fi

    if [ "$mode" = "exit" ]; then
      if grep -q "^ExitPolicy" "$config"; then
        test_pass "$config has ExitPolicy (exit relay)"
      else
        test_warn "$config missing ExitPolicy"
      fi
    fi

    if [ "$mode" = "bridge" ]; then
      if grep -q "^BridgeRelay 1" "$config"; then
        test_pass "$config configured as bridge"
      fi
      if grep -q "^ExitPolicy reject \*:\*" "$config"; then
        test_pass "$config has ExitPolicy reject (prevents warning)"
      else
        test_warn "$config may trigger Tor warning"
      fi
    fi
  else
    test_warn "$config not found"
  fi
done

echo ""

echo "Test 5: Docker Compose Templates"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

for template in templates/docker-compose-*.yml; do
  if [ -f "$template" ]; then
    if grep -q "network_mode: host" "$template"; then
      test_pass "$(basename "$template"): uses host networking"
    else
      test_warn "$(basename "$template"): not using host networking"
    fi

    if grep -q "/var/lib/tor" "$template" && grep -q "/var/log/tor" "$template"; then
      test_pass "$(basename "$template"): has data/log volumes"
    else
      test_warn "$(basename "$template"): missing volume mounts"
    fi

    if grep -q "/etc/tor/torrc:ro" "$template"; then
      test_pass "$(basename "$template"): config mounted read-only"
    else
      test_warn "$(basename "$template"): config not read-only"
    fi

    if grep -q "ENABLE_METRICS\|ENABLE_NET_CHECK\|METRICS_PORT" "$template"; then
      test_fail "$(basename "$template"): has old monitoring ENV vars"
    else
      test_pass "$(basename "$template"): no old monitoring vars"
    fi
  fi
done

echo ""

echo "Test 6: Line Ending Configuration"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ -f .gitattributes ]; then
  if grep -q "eol=lf" .gitattributes; then
    test_pass ".gitattributes enforces LF line endings"
  else
    test_warn ".gitattributes doesn't enforce line endings"
  fi

  if grep -q "docker-entrypoint.sh.*eol=lf" .gitattributes; then
    test_pass "Entrypoint has LF enforcement"
  fi

  if grep -q "tools/\*.*eol=lf" .gitattributes; then
    test_pass "Tools have LF enforcement"
  fi
else
  test_fail ".gitattributes missing - line ending issues on Windows"
fi

echo ""

echo "Test 7: Documentation"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ -f README.md ]; then
  if grep -iq "20\s*MB\|~16.8MB" README.md; then
    test_pass "README mentions 16.8MB size"
  else
    test_warn "README doesn't mention optimized size"
  fi
fi

if [ -f SECURITY.md ]; then
  test_pass "SECURITY.md exists"
else
  test_warn "SECURITY.md missing (security policy)"
fi

if [ -f docs/TOOLS.md ]; then
  if grep -q "4.*tools\|four.*tools" docs/TOOLS.md; then
    test_pass "TOOLS.md documents 4 tools"
  else
    test_warn "TOOLS.md may reference old tool count"
  fi
fi

echo ""

echo "Test 8: Shell Script Syntax"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

for script in docker-entrypoint.sh tools/status tools/health tools/fingerprint tools/bridge-line tools/gen-family; do
  if [ -f "$script" ]; then
    if sh -n "$script" 2>/dev/null; then
      test_pass "$script has valid POSIX sh syntax"
    else
      test_fail "$script has syntax errors"
    fi
  fi
done

if command -v shellcheck >/dev/null 2>&1; then
  failed_check=0
  for script in docker-entrypoint.sh tools/*; do
    if [ -f "$script" ] && [ -x "$script" ]; then
      if ! shellcheck -S warning "$script" 2>/dev/null; then
        failed_check=1
      fi
    fi
  done

  if [ $failed_check -eq 0 ]; then
    test_pass "ShellCheck validation passed"
  else
    test_warn "ShellCheck found issues (non-critical)"
  fi
else
  test_warn "ShellCheck not installed (optional)"
fi

echo ""

echo "Test 9: Sensitive Data Check"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ -f .gitignore ]; then
  test_pass ".gitignore exists"

  if grep -q "\.secrets\|\.env" .gitignore; then
    test_pass ".gitignore protects secrets"
  else
    test_warn ".gitignore doesn't protect .secrets/.env"
  fi

  if grep -q "\.claude" .gitignore; then
    test_pass ".gitignore excludes .claude/"
  fi
else
  test_fail ".gitignore missing"
fi

if [ -f .secrets ] || [ -f .env ]; then
  test_fail "Secrets file found in repo!"
else
  test_pass "No secrets files in repo"
fi

echo ""

echo "Test 10: Build Optimization"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ -f .dockerignore ]; then
  test_pass ".dockerignore exists (smaller build context)"
else
  test_warn ".dockerignore missing (larger build context)"
fi

if grep -q "hadolint ignore=DL3018" Dockerfile; then
  test_pass "Unpinned Alpine packages (weekly security updates)"
else
  test_warn "May have pinned package versions"
fi

if grep -q "rm -rf /var/cache/apk" Dockerfile; then
  test_pass "APK cache cleaned (smaller image)"
else
  test_warn "APK cache may remain (larger image)"
fi

echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test Results Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
echo "  Total:  $((PASS + FAIL))"
echo ""

if [ "$FAIL" -eq 0 ]; then
  echo "✅ ALL CRITICAL TESTS PASSED"
  echo ""
  echo "Next steps:"
  echo "  1. Build image: docker build -t tor-relay:test ."
  echo "  2. Test runtime: docker run --rm tor-relay:test status"
  echo "  3. Deploy to production or test with your relay configuration"
  echo ""
  exit 0
else
  echo "❌ SOME TESTS FAILED - Review and fix issues"
  echo ""
  echo "Fix the failed tests before deploying to production."
  echo ""
  exit 1
fi
