# syntax=docker/dockerfile:1.7
FROM alpine:latest

# Metadata Arguments
ARG BUILD_DATE
ARG BUILD_VERSION
ARG TARGETARCH

# Labels
LABEL maintainer="rE-Bo0t.bx1 <r3bo0tbx1@brokenbotnet.com>" \
      org.opencontainers.image.title="Tor Guard Relay" \
      org.opencontainers.image.description="🧅 Hardened Tor Guard Relay with diagnostics & auto-healing" \
      org.opencontainers.image.version="${BUILD_VERSION}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.source="https://github.com/r3bo0tbx1/tor-guard-relay" \
      org.opencontainers.image.documentation="https://github.com/r3bo0tbx1/tor-guard-relay#readme" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.revision="${TARGETARCH}"

# Core dependencies
# - tor: main service
# - bash: entrypoint logic
# - tini: init process manager
# - curl: for diagnostics and network checks
# - jq, grep, coreutils: JSON parsing & utils
# - bind-tools: provides nslookup/dig for DNS diagnostics
# - netcat-openbsd: for port checking in net-check
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

# Directory structure setup
RUN mkdir -p /var/lib/tor /var/log/tor /run/tor && \
    chown -R tor:tor /var/lib/tor /var/log/tor /run/tor && \
    chmod 700 /var/lib/tor && \
    chmod 755 /var/log/tor /run/tor

# Default configuration placeholder
RUN echo "# 🧅 Tor configuration is mounted at runtime" > /etc/tor/torrc

# Build metadata
RUN printf "Version: %s\nBuild Date: %s\nArchitecture: %s\n" \
    "${BUILD_VERSION:-dev}" "${BUILD_DATE:-unknown}" "${TARGETARCH:-amd64}" > /build-info.txt

# Copy entrypoint and diagnostic tools
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
COPY tools/ /usr/local/bin/

# Normalize scripts: remove CRLFs, BOMs, and fix permissions
RUN set -eux; \
  for f in /usr/local/bin/*; do \
    [ -f "$f" ] || continue; \
    tr -d '\r' < "$f" > "$f.tmp" && mv "$f.tmp" "$f"; \
    sed -i '1s/^\xEF\xBB\xBF//' "$f" || true; \
    chmod +x "$f"; \
  done; \
  echo "🧩 Installed tools:"; \
  ls -1 /usr/local/bin | grep -E 'docker-entrypoint|net-check|metrics|health|view-logs' || true

# Environment defaults
ENV TOR_DATA_DIR=/var/lib/tor \
    TOR_LOG_DIR=/var/log/tor \
    TOR_CONFIG=/etc/tor/torrc \
    ENABLE_METRICS=false \
    ENABLE_HEALTH_CHECK=true \
    ENABLE_NET_CHECK=true \
    PATH="/usr/local/bin:$PATH"

# Cleanup
RUN rm -rf /usr/share/man /tmp/* /var/tmp/* /root/.cache/*

# Runtime permissions (non-root safe)
RUN mkdir -p /run/tor && \
    chown -R tor:tor /run/tor && \
    chmod 770 /run/tor

# Non-root execution
USER tor

# Expose relay + diagnostics ports
EXPOSE 9001 9035 9036

# Healthcheck - ensures Tor config remains valid
HEALTHCHECK --interval=10m --timeout=15s --start-period=30s --retries=3 \
  CMD tor --verify-config -f "$TOR_CONFIG" || exit 1

# Entrypoint through tini
ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/docker-entrypoint.sh"]
CMD ["tor", "-f", "/etc/tor/torrc"]
