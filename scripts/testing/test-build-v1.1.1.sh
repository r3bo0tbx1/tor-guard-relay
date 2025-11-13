#!/bin/bash
# test-build-v1.1.1.sh - Build and push v1.1.1 to localhost registry for testing

set -euo pipefail

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Configuration
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

LOCALHOST_REGISTRY="localhost:5000"
IMAGE_NAME="r3bo0tbx1/onion-relay"
VERSION="1.1.1"
BUILD_DATE=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Logging
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

log() { printf "%s\n" "$1"; }
info() { printf "   ℹ️  %s\n" "$1"; }
success() { printf "✅ %s\n" "$1"; }
fail() { printf "❌ %s\n" "$1"; exit 1; }
warn() { printf "⚠️  %s\n" "$1"; }
section() {
  log ""
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log "$1"
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Check prerequisites
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

check_docker() {
  if ! command -v docker &> /dev/null; then
    fail "Docker is not installed"
  fi
  success "Docker is available"
}

check_registry() {
  section "🔍 Checking Localhost Registry"

  if docker ps --format '{{.Names}}' | grep -q "registry"; then
    success "Registry container is running"
    return 0
  fi

  warn "Registry container not found"
  log ""
  log "Starting localhost registry on port 5000..."
  log ""

  if docker run -d -p 5000:5000 --name registry registry:2 2>/dev/null; then
    success "Registry started successfully"
    sleep 2
  else
    # Registry might already exist but stopped
    if docker ps -a --format '{{.Names}}' | grep -q "^registry$"; then
      log "Found existing registry container, starting it..."
      docker start registry
      sleep 2
      success "Registry restarted"
    else
      fail "Could not start registry"
    fi
  fi
}

check_dockerfile() {
  if [[ ! -f "$SCRIPT_DIR/Dockerfile" ]]; then
    fail "Dockerfile not found in $SCRIPT_DIR"
  fi
  success "Dockerfile found"
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Build and push
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

build_image() {
  section "🔨 Building v1.1.1 Image"

  log ""
  info "Image: ${LOCALHOST_REGISTRY}/${IMAGE_NAME}:${VERSION}"
  info "Build date: $BUILD_DATE"
  info "Build context: $SCRIPT_DIR"
  log ""

  log "Building Docker image..."
  log ""

  docker build \
    --build-arg BUILD_VERSION="$VERSION" \
    --build-arg BUILD_DATE="$BUILD_DATE" \
    --tag "${LOCALHOST_REGISTRY}/${IMAGE_NAME}:${VERSION}" \
    --tag "${LOCALHOST_REGISTRY}/${IMAGE_NAME}:latest" \
    --tag "${IMAGE_NAME}:${VERSION}" \
    --tag "${IMAGE_NAME}:latest" \
    "$SCRIPT_DIR"

  success "Image built successfully"
}

push_to_registry() {
  section "📤 Pushing to Localhost Registry"

  log ""
  log "Pushing ${LOCALHOST_REGISTRY}/${IMAGE_NAME}:${VERSION}..."
  docker push "${LOCALHOST_REGISTRY}/${IMAGE_NAME}:${VERSION}"
  success "Pushed version tag"

  log ""
  log "Pushing ${LOCALHOST_REGISTRY}/${IMAGE_NAME}:latest..."
  docker push "${LOCALHOST_REGISTRY}/${IMAGE_NAME}:latest"
  success "Pushed latest tag"

  log ""
  success "All tags pushed to registry"
}

verify_push() {
  section "✅ Verification"

  log ""
  log "Checking registry catalog..."

  # Check if we can query the registry
  if command -v curl &> /dev/null; then
    CATALOG=$(curl -s http://localhost:5000/v2/_catalog 2>/dev/null || echo "")
    if echo "$CATALOG" | grep -q "onion-relay"; then
      success "Image found in registry catalog"
      info "$CATALOG"
    else
      warn "Could not verify image in catalog"
    fi

    log ""
    log "Checking image tags..."
    TAGS=$(curl -s "http://localhost:5000/v2/${IMAGE_NAME}/tags/list" 2>/dev/null || echo "")
    if echo "$TAGS" | grep -q "1.1.1"; then
      success "Version 1.1.1 tag confirmed"
      info "$TAGS"
    else
      warn "Could not verify tags"
    fi
  else
    warn "curl not installed, skipping registry verification"
  fi

  log ""
  log "Checking local Docker images..."
  docker images | grep -E "REPOSITORY|onion-relay" | grep -E "REPOSITORY|1.1.1|latest"

  log ""
  success "Build verification complete"
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Main
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

main() {
  section "🐳 Build v1.1.1 for Local Testing"

  log ""
  log "This will build the current Dockerfile as v1.1.1 and push to localhost:5000"
  log ""

  # Run checks
  check_docker
  check_dockerfile
  check_registry

  # Build and push
  build_image
  push_to_registry
  verify_push

  # Final summary
  section "🎉 BUILD COMPLETE"

  log ""
  success "v1.1.1 is ready for testing!"
  log ""
  log "📦 Images available:"
  log "  ${LOCALHOST_REGISTRY}/${IMAGE_NAME}:${VERSION}"
  log "  ${LOCALHOST_REGISTRY}/${IMAGE_NAME}:latest"
  log "  ${IMAGE_NAME}:${VERSION}"
  log "  ${IMAGE_NAME}:latest"
  log ""
  log "🔍 Verify:"
  log "  docker images | grep onion-relay"
  log "  curl http://localhost:5000/v2/${IMAGE_NAME}/tags/list"
  log ""
  log "📋 Next Steps:"
  log "  1. Ensure test v1.1.0 environment is running:"
  log "     ./test-setup-v1.1.0.sh"
  log ""
  log "  2. Run test migration:"
  log "     ./test-migration.sh pre-migration"
  log "     ./test-migration.sh migrate"
  log "     ./test-migration.sh post-migration"
  log ""
}

main "$@"
