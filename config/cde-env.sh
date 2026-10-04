#!/bin/sh
# cde-env.sh — shared CDE environment for the whole session.
#
# Sourced by river-init (so CoW and anything it execs inherit it) and by
# cde-session.sh.  Everything is relocatable under $CDE_PREFIX; there is no
# /usr/dt.
#
# Deliberately small: CDE's own _DtEnvControl() constructs the icon, database
# and locale search paths from the compiled-in CDE_INSTALLATION_TOP (our
# $CDE_ROOT), so overriding XMICONSEARCHPATH/DTDATABASESEARCHPATH here breaks
# icon and database lookup rather than helping.

: "${CDE_PREFIX:=${HOME}/.local/cde-wayland}"
: "${CDE_ROOT:=${CDE_PREFIX}/dt}"
export CDE_PREFIX CDE_ROOT
export DT_HOME="$CDE_ROOT"
export PATH="$CDE_ROOT/bin:$CDE_PREFIX/bin:$PATH"

# CDE help data, and the application defaults directory that holds Dtwm.
export DTHELPSEARCHPATH="$CDE_ROOT/help/%L/%T/%N%S:$CDE_ROOT/help/%T/%N%S"
export DTUSERSEARCHPATH="$HOME/.dt/%T/%N%S"
export XAPPLRESDIR="$CDE_PREFIX/share/X11/app-defaults"

# The shim synthesises the root RESOURCE_MANAGER from files.  Point it at our
# CDE-ish resources unless the user already has their own.
if [ -z "${XENVIRONMENT:-}" ] && [ -f "$CDE_PREFIX/share/cde-wayland/Xresources" ]; then
    export XENVIRONMENT="$CDE_PREFIX/share/cde-wayland/Xresources"
fi

# ToolTalk: the real CDE desktop (and the Front Panel's application launching)
# uses it.  ttsession needs a portmapper; run-session.sh provides either the
# system rpcbind or our unprivileged tools/tt-portmapper.  Best-effort: if no
# portmapper is reachable ttsession just fails and apps still run.
if [ -z "${TT_SESSION:-}" ] && command -v ttsession >/dev/null 2>&1; then
    # Loopback/TCP sessions cannot use Unix-credential or DES auth; use none.
    : "${TOOLTALK_AUTH_LEVEL:=none}"
    export TOOLTALK_AUTH_LEVEL
    _tt="$(ttsession -p 2>/dev/null | head -1 || true)"
    if [ -n "$_tt" ]; then
        export TT_SESSION="$_tt"
    fi
    unset _tt
fi
