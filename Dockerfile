# syntax=docker/dockerfile:1.7
# ============================================================================
# Tor Guard Relay - Hardened relay with diagnostics and auto-healing
# Base: Alpine 3.21.5 | Multi-arch: amd64, arm64
# ============================================================================

FROM alpine:3.21.5 AS builder

# Build arguments
ARG BUILD_DATE
ARG BUILD_VERSION
ARG TARGETARCH

# OCI labels
LABEL maintainer="rE-Bo0t.bx1 <r3bo0tbx1@brokenbotnet.com>" \
      org.opencontainers.image.title="Tor Guard Relay" \
      org.opencontainers.image.description="🧅 Hardened Tor Guard Relay with diagnostics & auto-healing" \
      org.opencontainers.image.version="${BUILD_VERSION}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.source="https://github.com/r3bo0tbx1/tor-guard-relay" \
      org.opencontainers.image.documentation="https://github.com/r3bo0tbx1/tor-guard-relay#readme" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.vendor="r3bo0tbx1" \
      org.opencontainers.image.authors="rE-Bo0t.bx1 <r3bo0tbx1@brokenbotnet.com>" \
      org.opencontainers.image.url="https://github.com/r3bo0tbx1/tor-guard-relay" \
      org.opencontainers.image.base.name="docker.io/library/alpine:3.21.5" \
      org.opencontainers.image.revision="${TARGETARCH}"

# ============================================================================
# Shell configuration
# ============================================================================
SHELL ["/bin/ash", "-eo", "pipefail", "-c"]

# ============================================================================
# Install core dependencies and perform base setup
# hadolint ignore=DL3018,DL3059
# ============================================================================
RUN set -eux \
 && apk add --no-cache \
    tor=0.4.8.19-r0 \
    bash=5.2.37-r0 \
    tini=0.19.0-r3 \
    curl=8.14.1-r2 \
    jq=1.8.0-r0 \
    grep=3.12-r0 \
    coreutils=9.7-r1 \
    bind-tools=9.20.15-r0 \
    netcat-openbsd=1.229.1-r0 \
 && mkdir -p /var/lib/tor /var/log/tor /run/tor \
 && chown -R tor:tor /var/lib/tor /var/log/tor /run/tor \
 && chmod 700 /var/lib/tor \
 && chmod 755 /var/log/tor /run/tor \
 && echo "# 🧅 Tor configuration is mounted at runtime" > /etc/tor/torrc \
 && printf "Version: %s\nBuild Date: %s\nArchitecture: %s\n" \
    "${BUILD_VERSION:-dev}" "${BUILD_DATE:-unknown}" "${TARGETARCH:-amd64}" > /build-info.txt \
 && rm -rf /var/cache/apk/*

# ============================================================================
# Copy scripts and utilities
# ============================================================================
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
COPY tools/ /usr/local/bin/

# ============================================================================
# Normalize, harden, and alias tools
# ============================================================================
RUN set -eux \
 && apk add --no-cache dos2unix=7.5.2-r0 \
 && echo "🧩 Normalizing line endings and fixing permissions..." \
 && find /usr/local/bin -type f -name "*.sh" -exec dos2unix {} \; || true \
 && dos2unix /usr/local/bin/docker-entrypoint.sh || true \
 && chmod +x /usr/local/bin/*.sh /usr/local/bin/docker-entrypoint.sh \
 && echo "🔗 Creating symlinks for no-extension tool compatibility..." \
 && for f in /usr/local/bin/*.sh; do ln -sf "$f" "${f%.sh}"; done \
 && echo "✅ Tools normalized, executable, and aliased." \
 && echo "🧩 Registered tools:" \
 && for tool in docker-entrypoint net-check metrics health view-logs status fingerprint setup dashboard; do \
      [ -e "/usr/local/bin/$tool" ] && echo "  ↳ $tool"; \
    done \
 && apk del dos2unix \
 && rm -rf /var/cache/apk/*

# ============================================================================
# Environment configuration
# ============================================================================
ENV TOR_DATA_DIR=/var/lib/tor \
    TOR_LOG_DIR=/var/log/tor \
    TOR_CONFIG=/etc/tor/torrc \
    ENABLE_METRICS=false \
    ENABLE_HEALTH_CHECK=true \
    ENABLE_NET_CHECK=false \
    PATH="/usr/local/bin:$PATH"

# ============================================================================
# Cleanup
# ============================================================================
RUN rm -rf /usr/share/man /tmp/* /var/tmp/* /root/.cache/*

# ============================================================================
# Ensure runtime directory writable by non-root
# ============================================================================
RUN mkdir -p /run/tor \
 && chown -R tor:tor /run/tor \
 && chmod 770 /run/tor

# ============================================================================
# Switch to non-root user
# ============================================================================
USER tor

# ============================================================================
# Expose ports
# ============================================================================
EXPOSE 9001 9030

# ============================================================================
# Health check (verify configuration every 10 minutes)
# ============================================================================
HEALTHCHECK --interval=10m --timeout=15s --start-period=30s --retries=3 \
  CMD tor --verify-config -f "$TOR_CONFIG" || exit 1

# ============================================================================
# Entrypoint
# ============================================================================
ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/docker-entrypoint.sh"]
CMD ["tor", "-f", "/etc/tor/torrc"]
