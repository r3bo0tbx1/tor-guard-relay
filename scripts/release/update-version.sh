#!/bin/sh
# Auto-update version numbers across all documentation and templates
# Updates: README.md, templates/*.yml, templates/*.json, docs/*.md, CHANGELOG.md

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
Usage: $(basename "$0") [OPTIONS] <new_version>

Auto-update version numbers across all documentation and templates.

Arguments:
  new_version        New version number (e.g., 1.1.2 or v1.1.2)

Options:
  --dry-run          Show what would be changed without modifying files
  --no-backup        Don't create .bak files before modifying
  -h, --help         Show this help

Examples:
  $(basename "$0") 1.1.2
  $(basename "$0") --dry-run 1.2.0
  $(basename "$0") --no-backup v1.1.2

Files Updated:
  - README.md (version badges, examples)
  - CHANGELOG.md (unreleased section header)
  - templates/*.yml (image tags)
  - templates/*.json (image tags in Cosmos templates)
  - docs/*.md (version references)
  - CLAUDE.md (version references)

EOF
    exit 0
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Argument Parsing
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

DRY_RUN=0
CREATE_BACKUP=1
NEW_VERSION=""

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            usage
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --no-backup)
            CREATE_BACKUP=0
            shift
            ;;
        -*)
            die "Unknown option: $1 (use --help for usage)"
            ;;
        *)
            if [ -z "$NEW_VERSION" ]; then
                NEW_VERSION="$1"
            else
                die "Too many arguments (use --help for usage)"
            fi
            shift
            ;;
    esac
done

if [ -z "$NEW_VERSION" ]; then
    die "Version is required (use --help for usage)"
fi

# Strip 'v' prefix if present
NEW_VERSION="${NEW_VERSION#v}"

# Validate version format (semver)
if ! printf '%s' "$NEW_VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$'; then
    die "Invalid version format: ${NEW_VERSION} (expected: X.Y.Z or X.Y.Z-suffix)"
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Get Current Version
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Try to get current version from git tags
if git rev-parse --git-dir >/dev/null 2>&1; then
    CURRENT_VERSION=$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo "")
else
    CURRENT_VERSION=""
fi

# If no git tags, try to extract from README.md
if [ -z "$CURRENT_VERSION" ] && [ -f "README.md" ]; then
    CURRENT_VERSION=$(grep -oE 'onion-relay:[0-9]+\.[0-9]+\.[0-9]+' README.md | head -1 | cut -d: -f2 || echo "")
fi

if [ -z "$CURRENT_VERSION" ]; then
    warn "Could not detect current version, will replace all version-like patterns"
    CURRENT_VERSION="X.Y.Z"
else
    log "Current version detected: ${CURRENT_VERSION}"
fi

log "New version: ${NEW_VERSION}"

if [ "$DRY_RUN" = "1" ]; then
    warn "DRY RUN MODE - No files will be modified"
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# File Update Functions
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

update_file() {
    file="$1"

    if [ ! -f "$file" ]; then
        warn "File not found: ${file}"
        return 1
    fi

    if [ "$DRY_RUN" = "1" ]; then
        log "[DRY RUN] Would update: ${file}"
        # Show what would change
        if [ "$CURRENT_VERSION" != "X.Y.Z" ]; then
            matches=$(grep -c "${CURRENT_VERSION}" "$file" 2>/dev/null || echo "0")
            if [ "$matches" -gt 0 ]; then
                log "  Found ${matches} occurrence(s) of ${CURRENT_VERSION}"
            fi
        fi
        return 0
    fi

    # Create backup if enabled
    if [ "$CREATE_BACKUP" = "1" ]; then
        cp "$file" "${file}.bak"
    fi

    # Replace version numbers
    # Pattern 1: onion-relay:X.Y.Z → onion-relay:NEW_VERSION
    sed -i "s|onion-relay:${CURRENT_VERSION}|onion-relay:${NEW_VERSION}|g" "$file" 2>/dev/null || true

    # Pattern 2: /onion-relay:X.Y.Z → /onion-relay:NEW_VERSION
    sed -i "s|/onion-relay:${CURRENT_VERSION}|/onion-relay:${NEW_VERSION}|g" "$file" 2>/dev/null || true

    # Pattern 3: vX.Y.Z (in headings, badges, etc.)
    sed -i "s|v${CURRENT_VERSION}|v${NEW_VERSION}|g" "$file" 2>/dev/null || true

    # Pattern 4: Version X.Y.Z
    sed -i "s|Version ${CURRENT_VERSION}|Version ${NEW_VERSION}|g" "$file" 2>/dev/null || true

    # Pattern 5: version: "X.Y.Z" (YAML)
    sed -i "s|version: \"${CURRENT_VERSION}\"|version: \"${NEW_VERSION}\"|g" "$file" 2>/dev/null || true

    # Pattern 6: [vX.Y.Z] (changelog format)
    sed -i "s|\[v${CURRENT_VERSION}\]|[v${NEW_VERSION}]|g" "$file" 2>/dev/null || true

    success "Updated: ${file}"
    return 0
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Main Update Logic
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

update_count=0
skip_count=0

# Update README.md
if [ -f "README.md" ]; then
    log "Updating README.md..."
    if update_file "README.md"; then
        update_count=$((update_count + 1))
    else
        skip_count=$((skip_count + 1))
    fi
fi

# Update CHANGELOG.md (add new version header if doesn't exist)
if [ -f "CHANGELOG.md" ]; then
    log "Updating CHANGELOG.md..."

    if [ "$DRY_RUN" = "1" ]; then
        log "[DRY RUN] Would add version header to CHANGELOG.md"
    else
        # Check if version already exists
        if grep -q "## \[v${NEW_VERSION}\]" CHANGELOG.md || grep -q "## v${NEW_VERSION}" CHANGELOG.md; then
            log "Version ${NEW_VERSION} already in CHANGELOG.md"
        else
            # Insert new version header after ## [Unreleased] section
            if grep -q "## \[Unreleased\]" CHANGELOG.md; then
                # Create backup
                if [ "$CREATE_BACKUP" = "1" ]; then
                    cp CHANGELOG.md CHANGELOG.md.bak
                fi

                # Insert new version after Unreleased section
                awk -v version="$NEW_VERSION" -v date="$(date +%Y-%m-%d)" '
                    /^## \[Unreleased\]/ {
                        print
                        print ""
                        print "## [v" version "] - " date
                        next
                    }
                    { print }
                ' CHANGELOG.md > CHANGELOG.md.tmp && mv CHANGELOG.md.tmp CHANGELOG.md

                success "Added version ${NEW_VERSION} to CHANGELOG.md"
            else
                warn "No [Unreleased] section found in CHANGELOG.md"
            fi
        fi
    fi
    update_count=$((update_count + 1))
fi

# Update templates/*.yml
if [ -d "templates" ]; then
    log "Updating Docker Compose templates..."
    for file in templates/*.yml; do
        [ -f "$file" ] || continue
        if update_file "$file"; then
            update_count=$((update_count + 1))
        else
            skip_count=$((skip_count + 1))
        fi
    done
fi

# Update templates/*.json (Cosmos templates)
if [ -d "templates" ]; then
    log "Updating Cosmos Cloud templates..."
    for file in templates/*.json; do
        [ -f "$file" ] || continue
        if update_file "$file"; then
            update_count=$((update_count + 1))
        else
            skip_count=$((skip_count + 1))
        fi
    done
fi

# Update docs/*.md
if [ -d "docs" ]; then
    log "Updating documentation files..."
    for file in docs/*.md; do
        [ -f "$file" ] || continue
        if update_file "$file"; then
            update_count=$((update_count + 1))
        else
            skip_count=$((skip_count + 1))
        fi
    done
fi

# Update CLAUDE.md
if [ -f "CLAUDE.md" ]; then
    log "Updating CLAUDE.md..."
    if update_file "CLAUDE.md"; then
        update_count=$((update_count + 1))
    else
        skip_count=$((skip_count + 1))
    fi
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Summary
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

printf "\n"
printf "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
if [ "$DRY_RUN" = "1" ]; then
    printf "${CYAN}${BOLD}Version Update Summary (DRY RUN)${NC}\n"
else
    printf "${GREEN}${BOLD}Version Update Complete${NC}\n"
fi
printf "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n\n"

printf "  ${BOLD}Current Version:${NC} %s\n" "$CURRENT_VERSION"
printf "  ${BOLD}New Version:${NC}     %s\n" "$NEW_VERSION"
printf "  ${BOLD}Files Updated:${NC}   %d\n" "$update_count"
if [ "$skip_count" -gt 0 ]; then
    printf "  ${BOLD}Files Skipped:${NC}   %d\n" "$skip_count"
fi

if [ "$DRY_RUN" = "1" ]; then
    printf "\n${YELLOW}To apply changes, run without --dry-run${NC}\n"
elif [ "$CREATE_BACKUP" = "1" ]; then
    printf "\n${BLUE}Backup files created with .bak extension${NC}\n"
    printf "${BLUE}To restore: for f in *.bak; do mv \"\$f\" \"\${f%.bak}\"; done${NC}\n"
fi

printf "\n${BOLD}Next Steps:${NC}\n"
printf "  1. Review changes: ${CYAN}git diff${NC}\n"
printf "  2. Update CHANGELOG.md with release notes\n"
printf "  3. Commit changes: ${CYAN}git add -A && git commit -m \"chore: bump version to ${NEW_VERSION}\"${NC}\n"
printf "  4. Create tag: ${CYAN}git tag -a v${NEW_VERSION} -m \"Release v${NEW_VERSION}\"${NC}\n"
printf "  5. Push: ${CYAN}git push && git push --tags${NC}\n"
printf "\n"
