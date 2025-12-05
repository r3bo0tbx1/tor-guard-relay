#!/bin/sh
# Validates Tor configuration regardless of source (mounted file or ENV vars) 🐋💚

set -e

TOR_CONFIG="${TOR_CONFIG:-/etc/tor/torrc}"

if [ ! -f "$TOR_CONFIG" ]; then
  echo "ERROR: Config file not found: $TOR_CONFIG"
  exit 1
fi
if [ ! -r "$TOR_CONFIG" ]; then
  echo "ERROR: Config file not readable: $TOR_CONFIG"
  exit 1
fi
if tor --verify-config -f "$TOR_CONFIG" >/dev/null 2>&1; then
  exit 0
else
  echo "ERROR: Invalid Tor configuration"
  exit 1
fi