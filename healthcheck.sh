#!/bin/sh
set -eu
. "${RELAY_LIB:-/usr/local/lib/relay}/runtime.sh"
inspect_process || exit 1
config_valid