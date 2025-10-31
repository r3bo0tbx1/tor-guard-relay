# syntax=docker/dockerfile:1.7
FROM alpine:edge

#Metadata Arguments
ARG BUILD_DATE
ARG BUILD_VERSION
ARG TARGETARCH

# Image Labels
LABEL maintainer="rE-Bo0t.bx1 <r3bo0tbx1@brokenbotnet.com>" \
      org.opencontainers.image.title="Tor Guard Relay" \
      org.opencontainers.image.description="🧅 Hardened Tor Guard Relay with diagnostics & auto-healing" \
      org.opencontainers.image.version="${BUILD_VERSION}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.source="https://github.com/r3bo0tbx1/tor-guard-relay" \
      org.opencontainers.image.documentation="https://github.com/r3bo0tbx1/tor-guard-relay#readme" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.revision="${TARGETARCH}"

# Base Install
RUN apk add --no-cache \
    tor \
    bash \
    tini \
    grep \
    coreutils && \
    rm -rf /var/cache/apk/*

# Directory Setup
RUN mkdir -p /var/lib/tor /var/log/tor /run/tor && \
    chown -R tor:tor /var/lib/tor /var/log/tor /run/tor && \
    chmod 700 /var/lib/tor && \
    chmod 755 /var/log/tor

# Default Configuration
RUN echo "# Tor configuration is mounted at runtime" > /etc/tor/torrc

# Build Metadata File
RUN echo "Version: ${BUILD_VERSION}" > /build-info.txt && \
    echo "Build Date: ${BUILD_DATE}" >> /build-info.txt && \
    echo "Architecture: ${TARGETARCH}" >> /build-info.txt

# Copy Entrypoint and Tools
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
COPY tools/ /usr/local/bin/

RUN chmod +x /usr/local/bin/docker-entrypoint.sh && \
    find /usr/local/bin -type f -exec chmod +x {} \; && \
    ls -la /usr/local/bin/

# Environment
ENV TOR_DATA_DIR=/var/lib/tor \
    TOR_LOG_DIR=/var/log/tor \
    PATH="/usr/local/bin:$PATH"

# Security Cleanup
RUN rm -rf /usr/share/man /tmp/* /var/tmp/*

# Runtime Settings
USER tor
EXPOSE 9001

HEALTHCHECK --interval=10m --timeout=15s --start-period=30s --retries=3 \
  CMD tor --verify-config -f /etc/tor/torrc || exit 1

ENTRYPOINT ["/sbin/tini", "--", "docker-entrypoint.sh"]
CMD ["tor", "-f", "/etc/tor/torrc"]
