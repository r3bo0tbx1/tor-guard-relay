#!/bin/sh
# healthcheck.sh - Docker HEALTHCHECK wrapper
# Validates Tor configuration regardless of source (mounted file or ENV vars)

set -e

TOR_CONFIG="${TOR_CONFIG:-/etc/tor/torrc}"

# Check if config file exists and is readable
if [ ! -f "$TOR_CONFIG" ]; then
  echo "ERROR: Config file not found: $TOR_CONFIG"
  exit 1
fi

if [ ! -r "$TOR_CONFIG" ]; then
  echo "ERROR: Config file not readable: $TOR_CONFIG"
  exit 1
fi

# Verify Tor configuration
if tor --verify-config -f "$TOR_CONFIG" >/dev/null 2>&1; then
  # Config is valid
  exit 0
else
  echo "ERROR: Invalid Tor configuration"
  exit 1
fi
