#!/bin/sh
set -eu
case "${1:-}" in ''|-h|--help) echo 'Usage: update-version.sh X.Y.Z [--dry-run]'; exit 0 ;; esac
version=$1; shift
case "${1:-}" in '') exec python3 "$(dirname "$0")/check-versions.py" --version "$version" --write ;; --dry-run) exec python3 "$(dirname "$0")/check-versions.py" --version "$version" ;; *) exit 2 ;; esac