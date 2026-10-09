#!/bin/sh
# Retired validator: its legacy plaintext recovery procedure is unsupported.
printf '%s\n' 'Use docs/MIGRATION.md, current health/doctor tools and relay-inventory.sh. The old plaintext-backup validator is retired.' >&2
exit 1
