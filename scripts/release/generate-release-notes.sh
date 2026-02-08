#!/bin/sh
# Auto-generate release notes from git commits using conventional commit format
# Supports: feat, fix, docs, chore, refactor, test, perf, ci, build, style
# Falls back to all commits if no conventional commits found

set -e

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Color Output
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log() { printf "${BLUE}ℹ${NC} %s\n" "$*"; }
success() { printf "${GREEN}✅${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}⚠${NC} %s\n" "$*"; }
error() { printf "${RED}❌${NC} %s\n" "$*"; }
die() { error "$*"; exit 1; }

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Usage
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS] <version> [previous_version]

Auto-generate release notes from git commits using conventional commit format.

Arguments:
  version            The new version (e.g., 1.1.1 or v1.1.1)
  previous_version   Previous version to compare from (optional, auto-detected)

Options:
  -o, --output FILE  Output file (default: stdout)
  -f, --format FMT   Output format: markdown (default), github, plain
  --no-emoji         Disable emojis in output
  --breaking-only    Show only breaking changes
  -h, --help         Show this help

Examples:
  $(basename "$0") 1.1.1
  $(basename "$0") 1.1.1 1.1.0
  $(basename "$0") -o RELEASE_NOTES.md 1.2.0
  $(basename "$0") --format github 1.2.0 > notes.md

Conventional Commit Types:
  feat:      ✨ New features
  fix:       🐛 Bug fixes
  docs:      📚 Documentation changes
  perf:      ⚡ Performance improvements
  refactor:  ♻️  Code refactoring
  test:      ✅ Testing changes
  build:     🏗️  Build system changes
  ci:        👷 CI/CD changes
  chore:     🔧 Maintenance tasks
  style:     💄 Code style changes
  revert:    ⏪ Reverts

Breaking Changes:
  Any commit with "BREAKING CHANGE:" in body or "!" after type
  Example: feat!: remove legacy API

EOF
    exit 0
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Argument Parsing
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

OUTPUT_FILE=""
FORMAT="markdown"
USE_EMOJI=1
BREAKING_ONLY=0
VERSION=""
PREV_VERSION=""

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            usage
            ;;
        -o|--output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -f|--format)
            FORMAT="$2"
            shift 2
            ;;
        --no-emoji)
            USE_EMOJI=0
            shift
            ;;
        --breaking-only)
            BREAKING_ONLY=1
            shift
            ;;
        -*)
            die "Unknown option: $1 (use --help for usage)"
            ;;
        *)
            if [ -z "$VERSION" ]; then
                VERSION="$1"
            elif [ -z "$PREV_VERSION" ]; then
                PREV_VERSION="$1"
            else
                die "Too many arguments (use --help for usage)"
            fi
            shift
            ;;
    esac
done

if [ -z "$VERSION" ]; then
    die "Version is required (use --help for usage)"
fi

VERSION="${VERSION#v}"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Git Validation
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

if ! git rev-parse --git-dir >/dev/null 2>&1; then
    die "Not a git repository"
fi

if [ -z "$PREV_VERSION" ]; then
    PREV_VERSION=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
    if [ -z "$PREV_VERSION" ]; then
        PREV_VERSION=$(git rev-list --max-parents=0 HEAD)
        log "No previous tags found, using initial commit: ${PREV_VERSION:0:8}"
    else
        log "Auto-detected previous version: ${PREV_VERSION}"
    fi
else
    if ! git rev-parse "v${PREV_VERSION}" >/dev/null 2>&1; then
        if ! git rev-parse "${PREV_VERSION}" >/dev/null 2>&1; then
            die "Previous version '${PREV_VERSION}' not found in git history"
        fi
    else
        PREV_VERSION="v${PREV_VERSION}"
    fi
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Commit Parsing
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

COMMIT_RANGE="${PREV_VERSION}..HEAD"
log "Generating release notes from: ${COMMIT_RANGE}"

COMMITS=$(git log "${COMMIT_RANGE}" --pretty=format:'%H|||%s|||%b|||%an|||%ae' 2>/dev/null || echo "")

if [ -z "$COMMITS" ]; then
    warn "No commits found in range ${COMMIT_RANGE}"
fi

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

BREAKING_FILE="${TMP_DIR}/breaking.txt"
FEAT_FILE="${TMP_DIR}/feat.txt"
FIX_FILE="${TMP_DIR}/fix.txt"
DOCS_FILE="${TMP_DIR}/docs.txt"
PERF_FILE="${TMP_DIR}/perf.txt"
REFACTOR_FILE="${TMP_DIR}/refactor.txt"
TEST_FILE="${TMP_DIR}/test.txt"
BUILD_FILE="${TMP_DIR}/build.txt"
CI_FILE="${TMP_DIR}/ci.txt"
CHORE_FILE="${TMP_DIR}/chore.txt"
STYLE_FILE="${TMP_DIR}/style.txt"
REVERT_FILE="${TMP_DIR}/revert.txt"
OTHER_FILE="${TMP_DIR}/other.txt"

touch "$BREAKING_FILE" "$FEAT_FILE" "$FIX_FILE" "$DOCS_FILE" "$PERF_FILE" \
      "$REFACTOR_FILE" "$TEST_FILE" "$BUILD_FILE" "$CI_FILE" "$CHORE_FILE" \
      "$STYLE_FILE" "$REVERT_FILE" "$OTHER_FILE"

while IFS='|||' read -r hash subject body author email; do
    [ -z "$hash" ] && continue

    is_breaking=0
    if printf '%s' "$subject" | grep -qE '^[a-z]+!:'; then
        is_breaking=1
    fi
    if printf '%s' "$body" | grep -qiE '^BREAKING CHANGE:'; then
        is_breaking=1
    fi

    commit_type=$(printf '%s' "$subject" | sed -nE 's/^([a-z]+)(!?):.*/\1/p')

    clean_subject=$(printf '%s' "$subject" | sed -E 's/^[a-z]+!?: *//')

    short_hash=$(printf '%s' "$hash" | cut -c1-8)
    formatted_commit="- ${clean_subject} (\`${short_hash}\`) by ${author}"

    if [ "$is_breaking" = "1" ]; then
        printf '%s\n' "$formatted_commit" >> "$BREAKING_FILE"
    fi

    case "$commit_type" in
        feat|feature)
            printf '%s\n' "$formatted_commit" >> "$FEAT_FILE"
            ;;
        fix)
            printf '%s\n' "$formatted_commit" >> "$FIX_FILE"
            ;;
        docs|doc)
            printf '%s\n' "$formatted_commit" >> "$DOCS_FILE"
            ;;
        perf|performance)
            printf '%s\n' "$formatted_commit" >> "$PERF_FILE"
            ;;
        refactor)
            printf '%s\n' "$formatted_commit" >> "$REFACTOR_FILE"
            ;;
        test|tests)
            printf '%s\n' "$formatted_commit" >> "$TEST_FILE"
            ;;
        build)
            printf '%s\n' "$formatted_commit" >> "$BUILD_FILE"
            ;;
        ci)
            printf '%s\n' "$formatted_commit" >> "$CI_FILE"
            ;;
        chore)
            printf '%s\n' "$formatted_commit" >> "$CHORE_FILE"
            ;;
        style)
            printf '%s\n' "$formatted_commit" >> "$STYLE_FILE"
            ;;
        revert)
            printf '%s\n' "$formatted_commit" >> "$REVERT_FILE"
            ;;
        *)

            printf '%s\n' "- ${subject} (\`${short_hash}\`) by ${author}" >> "$OTHER_FILE"
            ;;
    esac
done << EOF
$COMMITS
EOF

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Output Generation
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

generate_output() {
    if [ "$FORMAT" = "github" ]; then
        printf "## 🧅 Tor Guard Relay v%s\n\n" "$VERSION"
    elif [ "$FORMAT" = "markdown" ]; then
        printf "## [v%s] - %s\n\n" "$VERSION" "$(date +%Y-%m-%d)"
    else
        printf "Tor Guard Relay v%s - Release Notes\n\n" "$VERSION"
    fi

    if [ -s "$BREAKING_FILE" ]; then
        if [ "$USE_EMOJI" = "1" ]; then
            printf "### 🚨 BREAKING CHANGES\n\n"
        else
            printf "### BREAKING CHANGES\n\n"
        fi
        cat "$BREAKING_FILE"
        printf "\n"
    fi

    if [ "$BREAKING_ONLY" = "1" ]; then
        return 0
    fi

    if [ -s "$FEAT_FILE" ]; then
        if [ "$USE_EMOJI" = "1" ]; then
            printf "### ✨ Features\n\n"
        else
            printf "### Features\n\n"
        fi
        cat "$FEAT_FILE"
        printf "\n"
    fi

    if [ -s "$FIX_FILE" ]; then
        if [ "$USE_EMOJI" = "1" ]; then
            printf "### 🐛 Bug Fixes\n\n"
        else
            printf "### Bug Fixes\n\n"
        fi
        cat "$FIX_FILE"
        printf "\n"
    fi

    if [ -s "$PERF_FILE" ]; then
        if [ "$USE_EMOJI" = "1" ]; then
            printf "### ⚡ Performance\n\n"
        else
            printf "### Performance\n\n"
        fi
        cat "$PERF_FILE"
        printf "\n"
    fi

    if [ -s "$DOCS_FILE" ]; then
        if [ "$USE_EMOJI" = "1" ]; then
            printf "### 📚 Documentation\n\n"
        else
            printf "### Documentation\n\n"
        fi
        cat "$DOCS_FILE"
        printf "\n"
    fi

    if [ -s "$REFACTOR_FILE" ]; then
        if [ "$USE_EMOJI" = "1" ]; then
            printf "### ♻️ Refactoring\n\n"
        else
            printf "### Refactoring\n\n"
        fi
        cat "$REFACTOR_FILE"
        printf "\n"
    fi

    if [ -s "$CI_FILE" ]; then
        if [ "$USE_EMOJI" = "1" ]; then
            printf "### 👷 CI/CD\n\n"
        else
            printf "### CI/CD\n\n"
        fi
        cat "$CI_FILE"
        printf "\n"
    fi

    if [ -s "$BUILD_FILE" ]; then
        if [ "$USE_EMOJI" = "1" ]; then
            printf "### 🏗️ Build System\n\n"
        else
            printf "### Build System\n\n"
        fi
        cat "$BUILD_FILE"
        printf "\n"
    fi

    if [ -s "$TEST_FILE" ]; then
        if [ "$USE_EMOJI" = "1" ]; then
            printf "### ✅ Testing\n\n"
        else
            printf "### Testing\n\n"
        fi
        cat "$TEST_FILE"
        printf "\n"
    fi

    if [ -s "$CHORE_FILE" ]; then
        if [ "$USE_EMOJI" = "1" ]; then
            printf "### 🔧 Maintenance\n\n"
        else
            printf "### Maintenance\n\n"
        fi
        cat "$CHORE_FILE"
        printf "\n"
    fi

    if [ -s "$STYLE_FILE" ]; then
        if [ "$USE_EMOJI" = "1" ]; then
            printf "### 💄 Style\n\n"
        else
            printf "### Style\n\n"
        fi
        cat "$STYLE_FILE"
        printf "\n"
    fi

    if [ -s "$REVERT_FILE" ]; then
        if [ "$USE_EMOJI" = "1" ]; then
            printf "### ⏪ Reverts\n\n"
        else
            printf "### Reverts\n\n"
        fi
        cat "$REVERT_FILE"
        printf "\n"
    fi

    if [ -s "$OTHER_FILE" ]; then
        if [ "$USE_EMOJI" = "1" ]; then
            printf "### 📦 Other Changes\n\n"
        else
            printf "### Other Changes\n\n"
        fi
        cat "$OTHER_FILE"
        printf "\n"
    fi

    if [ "$FORMAT" = "github" ] || [ "$FORMAT" = "markdown" ]; then
        printf "---\n\n"
        printf "**Full Changelog**: %s...v%s\n" "$PREV_VERSION" "$VERSION"
    fi
}

if [ -n "$OUTPUT_FILE" ]; then
    generate_output > "$OUTPUT_FILE"
    success "Release notes written to: ${OUTPUT_FILE}"
else
    generate_output
fi
