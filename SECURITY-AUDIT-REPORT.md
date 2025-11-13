# Security Audit Report - Tor Guard Relay Project
**Date**: 2025-11-13
**Auditor**: Claude Code Security Audit
**Scope**: Complete codebase security hardening review

---

## Executive Summary

A comprehensive line-by-line security audit was performed on the Tor Guard Relay project. This audit identified **32 security issues** ranging from CRITICAL to LOW severity.

**Statistics:**
- **CRITICAL**: 6 issues (must fix immediately)
- **HIGH**: 8 issues (should fix before release)
- **MEDIUM**: 10 issues (should address)
- **LOW**: 8 issues (nice to have)

---

## CRITICAL Issues (Must Fix Immediately)

### 1. Command Injection via OBFS4V_* Environment Variables
**File**: `docker-entrypoint.sh:238-242`
**Severity**: CRITICAL
**CWE**: CWE-78 (OS Command Injection), CWE-94 (Code Injection)

**Issue**:
```sh
env | grep '^OBFS4V_' | sort | while IFS='=' read -r key value; do
  torrc_key="${key#OBFS4V_}"
  echo "$torrc_key $value" >> "$TOR_CONFIG"
done
```

- No input validation on `$value`
- No quoting around variables in echo
- Allows injection of arbitrary torrc directives
- `env` output can be manipulated

**Impact**: Attacker can inject malicious torrc configuration, potentially:
- Redirect Tor traffic
- Disable security features
- Execute arbitrary commands via ControlPort directives

**Fix**: Implement strict input validation and proper escaping.

---

### 2. Health Check Failure on ENV-Based Deployments
**File**: `Dockerfile:108-109`
**Severity**: CRITICAL
**CWE**: CWE-703 (Improper Check or Handling of Exceptional Conditions)

**Issue**:
```dockerfile
HEALTHCHECK --interval=10m --timeout=15s --start-period=30s --retries=3 \
  CMD tor --verify-config -f /etc/tor/torrc || exit 1
```

Hardcoded path `/etc/tor/torrc` doesn't exist when using environment variables for configuration.

**Impact**:
- Health checks always fail for ENV-based deployments
- Orchestrators (Kubernetes, Docker Swarm) will restart healthy containers
- Service disruption

**Fix**: Make health check conditional or use a wrapper script.

---

### 3. Privilege Escalation Attempt with Silent Failure
**File**: `docker-entrypoint.sh:107-109`
**Severity**: CRITICAL
**CWE**: CWE-250 (Execution with Unnecessary Privileges)

**Issue**:
```sh
if command -v chown >/dev/null 2>&1; then
  chown -R tor:tor "$TOR_DATA_DIR" "$TOR_LOG_DIR" /run/tor 2>/dev/null || true
fi
```

Container runs as user `tor` (UID 100), but `chown` requires root. The `|| true` silently masks the failure.

**Impact**:
- Permissions won't be fixed
- Runtime failures due to permission issues
- Silent failure hides the problem from debugging

**Fix**: Remove the chown attempt (permissions should be set at build time or mount time).

---

### 4. Inadequate Input Validation
**File**: `docker-entrypoint.sh:120-140`
**Severity**: CRITICAL
**CWE**: CWE-20 (Improper Input Validation)

**Issue**: Minimal validation of critical configuration parameters:
- `TOR_NICKNAME`: Only checks length and alphanumeric, doesn't validate against reserved names
- `TOR_CONTACT_INFO`: Minimal length check, no format validation
- `TOR_ORPORT`, `TOR_DIRPORT`, `TOR_OBFS4_PORT`: No validation at all
- `TOR_RELAY_MODE`: Not validated in validation function
- No sanitization of special characters

**Impact**:
- Malformed torrc generation
- Potential injection attacks
- Invalid Tor configuration causing crashes

**Fix**: Implement comprehensive input validation with whitelisting.

---

### 5. Workflow Permission Over-Granting
**File**: `.github/workflows/release.yml:21-23`
**Severity**: CRITICAL
**CWE**: CWE-269 (Improper Privilege Management)

**Issue**:
```yaml
permissions:
  contents: write
  packages: write
```

Permissions granted globally to all jobs, violating principle of least privilege.

**Impact**:
- If earlier jobs are compromised, they can modify repository or packages
- Increased attack surface
- Compliance violations

**Fix**: Scope permissions per-job.

---

### 6. Temporary File Race Condition
**File**: `docker-entrypoint.sh:266-267`
**Severity**: CRITICAL
**CWE**: CWE-377 (Insecure Temporary File)

**Issue**:
```sh
VERIFY_TMP=$(mktemp)
trap 'rm -f "$VERIFY_TMP"' EXIT
```

Trap set AFTER mktemp, creating a window where signals can leave temp files.

**Impact**:
- Temp file leak
- Potential information disclosure if temp file contains sensitive data

**Fix**: Set trap immediately, use proper temp directory with restricted permissions.

---

## HIGH Severity Issues (Should Fix Before Release)

### 7. JSON Injection in Health Tool
**File**: `tools/health:58-69`
**Severity**: HIGH
**CWE**: CWE-116 (Improper Encoding or Escaping of Output)

**Issue**: JSON output doesn't escape special characters in fingerprint or nickname.

**Fix**: Implement proper JSON escaping or use jq for generation.

---

### 8. Bash-Specific Features in Portable Scripts
**Files**: `scripts/migration/*.sh`, `scripts/utilities/relay-status.sh`
**Severity**: HIGH
**CWE**: CWE-1104 (Use of Unmaintained Third Party Components)

**Issue**: Scripts use `#!/bin/bash` with bash-specific features (`[[`, `$EUID`, arrays) but project claims POSIX sh compatibility.

**Impact**: Won't work on systems without bash (Alpine, busybox, etc).

**Fix**: Rewrite using POSIX sh or document bash requirement.

---

### 9. Multiple Tor Process Handling
**File**: `tools/health:22`
**Severity**: HIGH
**CWE**: CWE-366 (Race Condition within a Thread)

**Issue**: `TOR_PID=$(pgrep -x tor)` doesn't handle multiple tor processes.

**Fix**: Add validation to ensure only one tor process.

---

### 10. Sudo Hardcoding in Utility Scripts
**File**: `scripts/utilities/relay-status.sh` (multiple locations)
**Severity**: HIGH
**CWE**: CWE-250 (Execution with Unnecessary Privileges)

**Issue**: Script hard codes `sudo` without checking if user has sudo privileges or if running as root.

**Fix**: Detect privilege level and use sudo only if needed.

---

### 11. Fingerprint Length Assumption
**File**: `tools/status:63-64`
**Severity**: HIGH
**CWE**: CWE-1284 (Improper Validation of Specified Quantity in Input)

**Issue**:
```sh
FP_START=$(printf "%s" "$FINGERPRINT" | cut -c1-8)
FP_END=$(printf "%s" "$FINGERPRINT" | cut -c33-40)
```

Assumes fingerprint is exactly 40 characters without validation.

**Fix**: Validate fingerprint length before substring extraction.

---

### 12. Bridge Line Information Disclosure
**File**: `tools/bridge-line:78-85`
**Severity**: HIGH
**CWE**: CWE-200 (Exposure of Sensitive Information)

**Issue**: Falls back to reading bridge line from logs which may be world-readable.

**Fix**: Remove fallback or add permission check.

---

### 13. Tor Startup Validation Missing
**File**: `docker-entrypoint.sh:320-322`
**Severity**: HIGH
**CWE**: CWE-754 (Improper Check for Unusual or Exceptional Conditions)

**Issue**:
```sh
tor -f "$TOR_CONFIG" &
TOR_PID=$!
```

No check if tor actually started successfully.

**Fix**: Add startup validation with timeout.

---

### 14. Workflow Syntax Validation Wrong Tool
**File**: `.github/workflows/validate.yml:85-86`
**Severity**: HIGH
**CWE**: CWE-1177 (Use of Prohibited Code)

**Issue**: Uses `bash -n` to validate POSIX sh scripts.

**Fix**: Use `sh -n` for POSIX compliance checking.

---

## MEDIUM Severity Issues (Should Address)

### 15. Integer Overflow in Loop Counter
**File**: `docker-entrypoint.sh:331`
**Severity**: MEDIUM
**Issue**: `log_wait` arithmetic could overflow on some systems.

### 16. Impro per Error Handling in Workflows
**File**: `.github/workflows/validate.yml:68`
**Severity**: MEDIUM
**Issue**: `|| true` prevents job failure on docker build errors.

### 17. No Secret Validation
**Files**: Multiple workflow files
**Severity**: MEDIUM
**Issue**: No validation of secret values before use.

### 18. Progress Extraction Fragility
**File**: `tools/status:42-43`
**Severity**: MEDIUM
**Issue**: sed extraction could fail with non-standard log formats.

### 19. Missing Disk Space Check
**File**: `.github/workflows/validate.yml:317`
**Severity**: MEDIUM
**Issue**: Image saved to `/tmp` without checking available disk space.

### 20. Hardcoded Package Installation
**File**: `.github/workflows/release.yml:140`
**Severity**: MEDIUM
**Issue**: No verification of dos2unix package integrity.

### 21. Bash Arrays in Tag Generation
**File**: `.github/workflows/release.yml:194-219`
**Severity**: MEDIUM
**Issue**: Uses bash arrays which breaks on minimal systems.

### 22. AWK Changelog Extraction Edge Cases
**File**: `.github/workflows/release.yml:264-268`
**Severity**: MEDIUM
**Issue**: Doesn't handle missing version sections properly.

### 23. No CRLF Protection
**Files**: All tool scripts
**Severity**: MEDIUM
**Issue**: If scripts get CRLF line endings, shebang `#!/bin/sh\r` will fail.

### 24. Bridge Mode Auto-Detection Fragility
**File**: `docker-entrypoint.sh:29`
**Severity**: MEDIUM
**Issue**: Auto-detection could be more robust.

---

## LOW Severity Issues (Nice to Have)

### 25-32. Code Quality & Maintainability
- Inconsistent error handling patterns
- Hardcoded paths without configurability
- No rate limiting for external calls
- Missing documentation for edge cases
- Resource limits not enabled by default in compose files
- Example .env lacks prominent "DO NOT COMMIT" warning
- `restart: unless-stopped` may not be appropriate for all deployments
- Hardcoded paths in migration scripts without validation

---

## Recommendations

1. **Immediate Actions**:
   - Fix all CRITICAL issues before any release
   - Implement input validation framework
   - Remove privilege escalation attempts
   - Fix health check for all deployment modes

2. **Short-term Actions**:
   - Address all HIGH severity issues
   - Implement proper JSON/shell escaping
   - Add comprehensive testing for edge cases
   - Document bash requirements or migrate to POSIX sh

3. **Long-term Actions**:
   - Implement automated security scanning in CI/CD
   - Add fuzz testing for input validation
   - Create security policy and disclosure process
   - Regular third-party security audits

---

## Conclusion

This audit identified significant security vulnerabilities that must be addressed before production use. The most critical issues involve command injection, improper privilege handling, and inadequate input validation. All CRITICAL and HIGH severity issues should be resolved immediately.

**Overall Risk Rating**: HIGH (before fixes)
**Recommendation**: Do not deploy to production until CRITICAL and HIGH issues are resolved.

---

*End of Report*
