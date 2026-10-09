#!/bin/sh
set -eu
exec python3 "$(dirname "$0")/relay_inventory.py" "$@"