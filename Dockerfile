# syntax=docker/dockerfile:1.7
# ============================================================================
# Tor Guard Relay - Hardened relay with diagnostics and auto-healing
# Base: Alpine 3.22.2 | Multi-arch: amd64, arm64
# ============================================================================

FROM alpine:3.22.2

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
      org.opencontainers.image.base.name="docker.io/library/alpine:3.22.2" \
      org.opencontainers.image.revision="${TARGETARCH}"

# Install core dependencies
# tor: relay daemon | bash: entrypoint | tini: init system (PID 1)
# curl: diagnostics | jq: JSON parsing | bind-tools: DNS (dig/nslookup)
# netcat-openbsd: port checking | coreutils/grep: utilities
RUN apk add --no-cache \
    tor \
    bash \
    tini \
    curl \
    jq \
    grep \
    coreutils \
    bind-tools \
    netcat-openbsd && \
    rm -rf /var/cache/apk/*

# Setup directories with proper permissions
# /var/lib/tor: data (keys, state) - 700 for security
# /var/log/tor: logs - 755 for diagnostics
# /run/tor: runtime (PID, socket) - 755 for health checks
RUN mkdir -p /var/lib/tor /var/log/tor /run/tor && \
    chown -R tor:tor /var/lib/tor /var/log/tor /run/tor && \
    chmod 700 /var/lib/tor && \
    chmod 755 /var/log/tor /run/tor

# Default configuration placeholder (mount your own at runtime)
RUN echo "# 🧅 Tor configuration is mounted at runtime" > /etc/tor/torrc

# Embed build metadata
RUN printf "Version: %s\nBuild Date: %s\nArchitecture: %s\n" \
    "${BUILD_VERSION:-dev}" "${BUILD_DATE:-unknown}" "${TARGETARCH:-amd64}" > /build-info.txt

# Copy application files
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
COPY tools/ /usr/local/bin/

# Normalize scripts: remove CRLF, BOM, and set permissions
RUN set -eux; \
  for f in /usr/local/bin/*; do \
    [ -f "$f" ] || continue; \
    tr -d '\r' < "$f" > "$f.tmp" && mv "$f.tmp" "$f"; \
    sed -i '1s/^\xEF\xBB\xBF//' "$f" || true; \
    chmod +x "$f"; \
  done; \
  echo "🧩 Installed tools:"; \
  ls -1 /usr/local/bin | grep -E 'docker-entrypoint|net-check|metrics|health|view-logs|status|fingerprint|setup|dashboard' || true

# Environment configuration
ENV TOR_DATA_DIR=/var/lib/tor \
    TOR_LOG_DIR=/var/log/tor \
    TOR_CONFIG=/etc/tor/torrc \
    ENABLE_METRICS=false \
    ENABLE_HEALTH_CHECK=true \
    ENABLE_NET_CHECK=false \
    PATH="/usr/local/bin:$PATH"

# Cleanup to minimize image size
RUN rm -rf /usr/share/man /tmp/* /var/tmp/* /root/.cache/*

# Ensure runtime directory writable by tor user
RUN mkdir -p /run/tor && \
    chown -R tor:tor /run/tor && \
    chmod 770 /run/tor

# Switch to non-root user
USER tor

# Expose network ports
# 9001: ORPort - Tor relay traffic (REQUIRED, PUBLIC)
# 9030: DirPort - Directory service (OPTIONAL, PUBLIC)
# 9035: Metrics - Prometheus endpoint (OPTIONAL, localhost recommended)
# 9036: Health - Status endpoint (OPTIONAL, localhost recommended)
EXPOSE 9001 9030

# Health check - validates Tor config every 10 minutes
HEALTHCHECK --interval=10m --timeout=15s --start-period=30s --retries=3 \
  CMD tor --verify-config -f "$TOR_CONFIG" || exit 1

# Use tini for signal handling, entrypoint for initialization
ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/docker-entrypoint.sh"]
CMD ["tor", "-f", "/etc/tor/torrc"]