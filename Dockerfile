# syntax=docker/dockerfile:1.20
# ============================================================================
# Tor Guard Relay - Ultra-optimized ~17.1 MB container
# Base: Alpine 3.22.2 | Multi-arch: amd64, arm64
# v1.1.1 - Busybox-only, 4 diagnostic tools, multi-mode support
# ============================================================================

FROM alpine:3.22.2

ARG BUILD_DATE
ARG BUILD_VERSION
ARG TARGETARCH

LABEL maintainer="rE-Bo0t.bx1 <r3bo0tbx1@brokenbotnet.com>" \
      org.opencontainers.image.title="Tor Guard Relay" \
      org.opencontainers.image.description="🧅 Ultra-optimized Tor Guard/Exit/Bridge Relay (~17.1 MB)" \
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

SHELL ["/bin/ash", "-eo", "pipefail", "-c"]

RUN set -eux \
 && apk add --no-cache \
    tor \
    tini \
    lyrebird \
 && mkdir -p /var/lib/tor /var/log/tor /run/tor /etc/tor \
 && chown -R tor:tor /var/lib/tor /var/log/tor /run/tor /etc/tor \
 && chmod 700 /var/lib/tor \
 && chmod 755 /var/log/tor /run/tor /etc/tor \
 && rm -f /etc/tor/torrc \
 && printf "Version: %s\nBuild Date: %s\nArchitecture: %s\n" \
    "${BUILD_VERSION:-unversioned}" "${BUILD_DATE:-unknown}" "${TARGETARCH:-amd64}" > /build-info.txt \
 && rm -rf /var/cache/apk/*

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
COPY healthcheck.sh /usr/local/bin/healthcheck.sh
COPY tools/status /usr/local/bin/status
COPY tools/health /usr/local/bin/health
COPY tools/fingerprint /usr/local/bin/fingerprint
COPY tools/bridge-line /usr/local/bin/bridge-line

RUN set -eux \
 && chmod +x /usr/local/bin/docker-entrypoint.sh \
              /usr/local/bin/healthcheck.sh \
              /usr/local/bin/status \
              /usr/local/bin/health \
              /usr/local/bin/fingerprint \
              /usr/local/bin/bridge-line \
 && echo "🧩 Registered diagnostic tools:" \
 && ls -lh /usr/local/bin/status /usr/local/bin/health /usr/local/bin/fingerprint /usr/local/bin/bridge-line

ENV TOR_DATA_DIR=/var/lib/tor \
    TOR_LOG_DIR=/var/log/tor \
    TOR_CONFIG=/etc/tor/torrc \
    TOR_RELAY_MODE=guard \
    TOR_NICKNAME="" \
    TOR_CONTACT_INFO="" \
    TOR_ORPORT=9001 \
    TOR_DIRPORT=9030 \
    TOR_OBFS4_PORT=9002 \
    TOR_BANDWIDTH_RATE="" \
    TOR_BANDWIDTH_BURST="" \
    TOR_EXIT_POLICY="" \
    PATH="/usr/local/bin:$PATH"

RUN rm -rf /usr/share/man /tmp/* /var/tmp/* /root/.cache/*

USER tor

EXPOSE 9001 9030 9002

HEALTHCHECK --interval=10m --timeout=15s --start-period=30s --retries=3 \
  CMD /usr/local/bin/healthcheck.sh

ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/docker-entrypoint.sh"]
CMD ["tor", "-f", "/etc/tor/torrc"]