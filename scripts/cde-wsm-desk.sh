#!/bin/sh
# cde-wsm-desk — bridge a CDE Workspace Manager desk change to CoW.
#
# dtwm changes its active workspace in ChangeToWorkspace(); this is run from
# there to make CoW show the matching desk, record the workspace state that the
# shim publishes on its synthetic WM window, and apply the workspace's backdrop
# (see docs/WORKSPACE-MANAGER.md).
#
# Usage: cde-wsm-desk INDEX [NAMES]
#   INDEX  zero-based desk index
#   NAMES  comma-separated workspace names (optional)
set -u

idx="${1:-0}"
names="${2:-ws0,ws1,ws2,ws3}"
state_dir="${XDG_RUNTIME_DIR:-/tmp}/cde-wayland"
mkdir -p "$state_dir" 2>/dev/null || true
printf 'names=%s\ncurrent=%s\n' "$names" "$idx" > "$state_dir/workspace"

_has_moocow=0
command -v moocow >/dev/null 2>&1 && _has_moocow=1

# Switch CoW's desk, if CoW is running and reachable.
if [ "$_has_moocow" = 1 ]; then
    moocow desk -d "$idx" >/dev/null 2>&1 || true
fi

# Apply this workspace's backdrop (config/backdrops.conf: INDEX COLOUR [IMAGE]).
_conf="${CDE_ROOT:-/usr/dt}/config/backdrops.conf"
if [ "$_has_moocow" = 1 ] && [ -f "$_conf" ]; then
    line=$(awk -v i="$idx" '$1 == i { print; exit }' "$_conf" 2>/dev/null)
    colour=$(printf '%s\n' "$line" | awk '{ print $2 }')
    image=$(printf '%s\n' "$line" | awk '{ print $3 }')
    [ -n "$colour" ] && moocow set output.colour.background "$colour" >/dev/null 2>&1
    if [ -n "$image" ]; then
        moocow set output.image.background "$image" >/dev/null 2>&1
    elif [ -n "$colour" ]; then
        # Clearing the image so a previous workspace's image does not persist.
        moocow set output.image.background none >/dev/null 2>&1
    fi
fi
