# syntax=docker/dockerfile:1.20
# ============================================================================
# Builder Stage: Compile Lyrebird with latest Go to fix CVEs
# ============================================================================
FROM golang:1.25-alpine AS builder

# Install git to fetch source
RUN apk add --no-cache git

# Build Lyrebird (obfs4) from official Tor Project repo
# We use -ldflags="-s -w" to strip debug symbols and reduce binary size
# We go get -u to update dependencies to fix CVEs in crypto/net/etc.
WORKDIR /go/src/lyrebird
RUN git clone https://gitlab.torproject.org/tpo/anti-censorship/pluggable-transports/lyrebird.git . \
 && go get -u ./... \
 && go mod tidy \
 && CGO_ENABLED=0 go build -ldflags="-s -w" -o /usr/bin/lyrebird ./cmd/lyrebird

# ============================================================================
# Final Stage: Tor Guard Relay - Ultra-optimized ~16.8 MB container
# ============================================================================
FROM alpine:3.22.2

ARG BUILD_DATE
ARG BUILD_VERSION
ARG TARGETARCH

LABEL maintainer="rE-Bo0t.bx1 <r3bo0tbx1@brokenbotnet.com>" \
      org.opencontainers.image.title="Tor Guard Relay" \
      org.opencontainers.image.description="🧅 Ultra-optimized Tor Guard/Exit/Bridge Relay AIO (~16.8 MB)" \
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

# Note: 'lyrebird' removed from apk add, copying it from builder instead
RUN set -eux \
 && apk upgrade --no-cache \
 && apk add --no-cache \
    tor \
    tini \
 && mkdir -p /var/lib/tor /var/log/tor /run/tor /etc/tor \
 && chown -R tor:tor /var/lib/tor /var/log/tor /run/tor /etc/tor \
 && chmod 700 /var/lib/tor \
 && chmod 755 /var/log/tor /run/tor /etc/tor \
 && rm -f /etc/tor/torrc \
 && printf "Version: %s\nBuild Date: %s\nArchitecture: %s\n" \
    "${BUILD_VERSION:-unversioned}" "${BUILD_DATE:-unknown}" "${TARGETARCH:-amd64}" > /build-info.txt \
 && rm -rf /var/cache/apk/*

# Copy compiled Lyrebird from builder stage
COPY --from=builder /usr/bin/lyrebird /usr/bin/lyrebird

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