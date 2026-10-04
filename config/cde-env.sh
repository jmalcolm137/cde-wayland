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

# CDE help data and the application defaults that hold Dtwm.  The action and
# datatype database path is *not* set here: the library builds it from the
# compiled-in CDE_INSTALLATION_TOP (our $CDE_ROOT), and its separator is a
# comma, not a colon.  Overriding it (especially colon-separated) collapses the
# whole list into one bogus directory and the Front Panel finds no database.
export DTHELPSEARCHPATH="$CDE_ROOT/help/%L/%T/%N%S:$CDE_ROOT/help/%T/%N%S"
export DTUSERSEARCHPATH="$HOME/.dt/%T/%N%S"
export XAPPLRESDIR="$CDE_PREFIX/share/X11/app-defaults"

# The shim synthesises the root RESOURCE_MANAGER from files.  Point it at our
# CDE-ish resources unless the user already has their own.
if [ -z "${XENVIRONMENT:-}" ] && [ -f "$CDE_PREFIX/share/cde-wayland/Xresources" ]; then
    export XENVIRONMENT="$CDE_PREFIX/share/cde-wayland/Xresources"
fi

# ToolTalk-free launching.  CDE's Front Panel normally runs actions through
# ToolTalk, but ToolTalk both needs a portmapper and (when it initialises)
# stops dtwm from creating the Front Panel.  We ship a small build overlay
# (patches/) that (a) skips dtwm's ToolTalk init so the panel is created and
# (b) makes DtActionInvoke execute the action's command locally.  Setting
# CDE_NO_TOOLTALK selects (a); no ttsession is started, so the action library
# takes (b).
export CDE_NO_TOOLTALK=1
unset TT_SESSION
