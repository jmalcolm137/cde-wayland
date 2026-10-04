#!/bin/sh
# cde-wsm-backdrop — apply a backdrop chosen in the Style Manager (dtstyle).
#
# dtstyle's Backdrop module calls _DtWsmChangeBackdrop(), which appends a
# CHANGE_BACKDROP request to the WM window's _DT_WM_REQUEST property.  That
# property lives in the client's private X server and cannot reach dtwm, so the
# DtSvc overlay (patches/dtsvc-backdrop.patch) also runs this helper with the
# chosen backdrop path.  It sets CoW's output background and records the choice
# per workspace, so cde-wsm-desk restores it when the workspace is shown again.
#
# Usage: cde-wsm-backdrop PATH
set -u

path="${1:-}"
[ -n "$path" ] || exit 0

state_dir="${XDG_RUNTIME_DIR:-/tmp}/cde-wayland"
mkdir -p "$state_dir" 2>/dev/null || true
# Diagnostic: record what dtstyle asked for (handy when a backdrop does nothing).
printf '%s\n' "$path" >> "$state_dir/backdrop.calls" 2>/dev/null || true

# dtstyle passes just the bitmap name (no directory, often no extension);
# resolve it against the backdrop directories, preferring the .xpm CoW needs.
if [ ! -f "$path" ]; then
    base="$path"
    found=""
    for d in "${CDE_ROOT:-/usr/dt}/backdrops" "$HOME/.dt/backdrops"; do
        for ext in .xpm .pm .png .svg; do
            if [ -f "$d/$base$ext" ]; then found="$d/$base$ext"; break 2; fi
        done
        if [ -f "$d/$base" ]; then found="$d/$base"; break; fi
    done
    [ -n "$found" ] && path="$found"
fi

idx=$(sed -n 's/^current=//p' "$state_dir/workspace" 2>/dev/null)
idx="${idx:-0}"

command -v moocow >/dev/null 2>&1 || exit 0

# CDE's .pm backdrops are XPM format but CoW only accepts the .xpm extension;
# install-panel-data.sh keeps a .xpm copy alongside each .pm.
case "$path" in
    *.pm) [ -f "${path%.pm}.xpm" ] && path="${path%.pm}.xpm" ;;
esac

case "$path" in
    *NoBackdrop*)
        moocow set output.image.background none >/dev/null 2>&1 ;;
    *)
        if [ -f "$path" ]; then
            moocow set output.image.background "$path" >/dev/null 2>&1
        else
            exit 0
        fi ;;
esac

printf '%s\n' "$path" > "$state_dir/backdrop.$idx"
