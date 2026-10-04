#!/bin/sh
# cde-wsm-desk — bridge a CDE Workspace Manager desk change to CoW.
#
# dtwm changes its active workspace in ChangeToWorkspace(); this is run from
# there to make CoW show the matching desk and to record the workspace state
# that the shim publishes on its synthetic WM window (see
# docs/WORKSPACE-MANAGER.md).
#
# Usage: cde-wsm-desk INDEX [NAMES]
#   INDEX  zero-based desk index
#   NAMES  comma-separated workspace names (optional)
set -u

idx="${1:-0}"
names="${2:-One,Two,Three,Four}"
state_dir="${XDG_RUNTIME_DIR:-/tmp}/cde-wayland"
mkdir -p "$state_dir" 2>/dev/null || true
printf 'names=%s\ncurrent=%s\n' "$names" "$idx" > "$state_dir/workspace"

# Switch CoW's desk, if CoW is running and reachable.
if command -v moocow >/dev/null 2>&1; then
    moocow desk -d "$idx" >/dev/null 2>&1 || true
fi
