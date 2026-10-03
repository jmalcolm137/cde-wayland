#!/bin/sh
# cde-session.sh — bring up a CDE session on the Wayland shim.
#
# v1 launches the desktop applications directly.  dtsession's XSMP-based
# coordination is cross-process (the shim has no shared X server), so it is a
# later milestone; see DESIGN.md §3.3 and §5.3.

set -eu

: "${CDE_PREFIX:=${HOME}/.local/cde-wayland}"
: "${CDE_ROOT:=${CDE_PREFIX}/dt}"

export CDE_PREFIX CDE_ROOT
export DT_HOME="$CDE_ROOT"
export PATH="$CDE_ROOT/bin:$CDE_PREFIX/bin:$PATH"

# CDE resource/help/icon search paths.  The %L/%l/%T/%N%S tokens are expanded
# by CDE's own lookup routines (DtSvc), matching the classic /usr/dt layout.
export DTDATABASESEARCHPATH="$CDE_ROOT/lib/%L/%T/%N%S:$CDE_ROOT/lib/%l/%T/%N%S:$CDE_ROOT/lib/%T/%N%S"
export DTHELPSEARCHPATH="$CDE_ROOT/help/%L/%T/%N%S:$CDE_ROOT/help/%T/%N%S"
export DTUSERSEARCHPATH="$HOME/.dt/%T/%N%S"
export XMICONSEARCHPATH="$CDE_ROOT/icons/%L/%T/%N%S:$CDE_ROOT/icons/%T/%N%S"
export XMICONBMSEARCHPATH="$CDE_ROOT/icons/%L/%T/%N%S:$CDE_ROOT/icons/%T/%N%S"
export XFILESEARCHPATH="$CDE_ROOT/lib/%L/%T/%N%S:$CDE_ROOT/lib/%T/%N%S"
export XAPPLRESDIR="$CDE_ROOT/lib/%L/%N:$CDE_ROOT/lib/%N"

# The shim synthesises RESOURCE_MANAGER from files; point it at our CDE-ish
# resources if the user has none of their own.
if [ -z "${XENVIRONMENT:-}" ] && [ -f "$CDE_PREFIX/share/cde-wayland/Xresources" ]; then
    export XENVIRONMENT="$CDE_PREFIX/share/cde-wayland/Xresources"
fi

# Start the desktop.  Each program is a native Wayland client on the shim.
# Backgrounded so the session script itself stays alive as the session's
# anchor.
start() {
    if command -v "$1" >/dev/null 2>&1; then
        "$@" &
    else
        echo "cde-session: not found: $1" >&2
    fi
}

start dtfile -
start dtterm

# If dtsession is available, let it own the session; otherwise stay alive as
# the session anchor while the backgrounded clients run.
if command -v dtsession >/dev/null 2>&1; then
    exec dtsession
fi
wait
