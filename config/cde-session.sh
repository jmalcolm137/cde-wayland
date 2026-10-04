#!/bin/sh
# cde-session.sh — bring up the CDE session under CoW.
#
# CoW is the real window manager for every application.  The CDE Front Panel
# is dtwm, run here as a *contained panel*: because the shim gives each process
# a private X server, dtwm only ever sees and manages its own windows, so its
# window-manager role cannot touch the CDE apps (separate processes) that CoW
# manages.  See DESIGN.md §5.2.
set -eu

: "${CDE_PREFIX:=${HOME}/.local/cde-wayland}"

# Prefer the installed environment; fall back to the one next to this script
# (running from the source tree).
_dir="$(cd -- "$(dirname -- "$0")" && pwd -P)"
if [ -f "$_dir/cde-env.sh" ]; then
    . "$_dir/cde-env.sh"
fi
if [ -f "$CDE_PREFIX/share/cde-wayland/cde-env.sh" ]; then
    . "$CDE_PREFIX/share/cde-wayland/cde-env.sh"
fi

log() { printf 'cde-session: %s\n' "$*" >&2; }

if [ -z "${TT_SESSION:-}" ]; then
    log "warning: no ToolTalk session; CDE apps may show ToolTalk errors."
    log "         run-session.sh starts one with 'ttsession -c'."
fi

# Calendar Manager service (rpc.cmsd), dtcm's backend.  The patched daemon runs
# as the user with a private spool directory, so it needs no root; without it
# dtcm shows "rpc.cmsd is not responding".
if command -v rpc.cmsd >/dev/null 2>&1; then
    log "starting the Calendar Manager service (rpc.cmsd)"
    CDE_CMSD_DIR="${CDE_CMSD_DIR:-$HOME/.calendar}" \
        rpc.cmsd >/dev/null 2>&1 &
fi

# The CDE Front Panel (real dtwm, contained).  dtwm skips its own ToolTalk
# messaging: registering as the workspace/window manager is wrong here (CoW is
# the WM) and it stopped the Front Panel from being created.
if command -v dtwm >/dev/null 2>&1; then
    log "starting the CDE Front Panel (dtwm, contained)"
    CDE_NO_TOOLTALK=1 dtwm -xrm '*useFrontPanel: True' &
else
    log "error: dtwm not found; run scripts/install-panel-data.sh"
fi

# The panel launches the rest; keep the session alive until logout.
wait
