#!/bin/sh
# Superseded v1.1.x fixture: never run its old live-volume replacement steps.
printf '%s\n' 'Use scripts/testing/recovery-rehearsal.py --image LOCAL_IMAGE --bind-parent SCRATCH_DIRECTORY for isolated encrypted recovery tests.' >&2
exit 1
