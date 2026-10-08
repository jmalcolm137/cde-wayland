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

# The Information Manager (dtinfo) browses MMDB "infolibs", not the SDL help
# volumes dthelpview uses.  Its default infolib is "cde" (see dtsearchpath);
# install-panel-data.sh puts it under appconfig/infolib from doc/C/cde.dti.
export DTINFOLIBDEFAULT="${DTINFOLIBDEFAULT:-cde}"
export DTINFOLIBSEARCHPATH="$CDE_ROOT/appconfig/infolib/%L/%I.dti"

# The Application Manager.  dtappgather gathers the application groups out of
# <element>/appmanager/<lang>/ and symlinks them into TARGET_APPMAN_DIR.  CDE's
# default target is /var/dt/appconfig/appmanager/<session>, which an
# unprivileged session cannot create; install-panel-data.sh installs the groups
# under $CDE_ROOT/appconfig/appmanager/C and this points the gathered result
# beside them.
export DTAPPSEARCHPATH="${DTAPPSEARCHPATH:-$CDE_ROOT/appconfig/appmanager/C}"
export TARGET_APPMAN_DIR="${TARGET_APPMAN_DIR:-$CDE_ROOT/appconfig/appmanager/gathered}"

# The shim synthesises the root RESOURCE_MANAGER from files.  Point it at our
# CDE-ish resources unless the user already has their own.
if [ -z "${XENVIRONMENT:-}" ] && [ -f "$CDE_PREFIX/share/cde-wayland/Xresources" ]; then
    export XENVIRONMENT="$CDE_PREFIX/share/cde-wayland/Xresources"
fi

# ToolTalk.  run-session.sh starts the whole session under `ttsession -c`, so
# TT_SESSION is exported to every client and CDE apps get the ToolTalk services
# they expect (the File Manager, Mailer, etc. are ToolTalk programs; the Front
# Panel is dtwm, whose workspace-manager service is ToolTalk too).  Do not
# clobber TT_SESSION here.

# _MOTIF_WM_HINTS: the compositor's WM (CoW) cannot refuse a command for one
# window, so xlib-wayland relays the functions a client allows to CoW by hiding
# the matching titlebar buttons (config/cow.conf defines the cde-func-* decor
# profiles).  CDE_MOTIF_HELPER names the command the shim runs, once per
# disabled button; it retries until CoW knows the window.  Set it explicitly
# empty to disable the relay.
export CDE_MOTIF_HELPER="${CDE_MOTIF_HELPER-cde-motif-apply}"

# Input methods.  The shim's XIM is a bridge to the compositor's text-input
# protocol, so no separate XIM server name is needed; river-init starts ibus,
# whose Wayland module registers with River as an input-method-v2 server.
# XMODIFIERS is set for convention (clients built against a real Xlib consult
# it when choosing an input method).
export XMODIFIERS="${XMODIFIERS:-@im=ibus}"

# Cross-process selections.  Each shim process is its own X server, so an X
# selection owned by one client is invisible to the rest.  The shim's broker
# (xlib-wayland src/xlib/broker.c) shares the named selections over a Unix
# socket; the value is a comma-separated list of selection-name prefixes.  CDE's
# colour server (dtsession) owns "Customize Data:<screen>", which dtstyle asks
# for when opening the Style Manager's Color module.  Motif drag-and-drop
# carries its payload on a selection named _MOTIF_ATOM_n, so those are shared
# too: the drag itself is routed by the compositor, but the file/text transfer
# is an ordinary selection conversion between the two Motifs (see
# xlib-wayland src/xlib/dnd.c).
export XLIB_WAYLAND_SHARE_SELECTIONS="${XLIB_WAYLAND_SHARE_SELECTIONS-Customize Data:,_MOTIF_ATOM_}"

# Session-manager properties.  dtsession publishes _DT_SM_WINDOW_INFO on the
# root and _DT_SM_STATE_INFO / _DT_SM_SAVER_INFO on its window; dtstyle's Style
# Manager reads them (and warns about screen-saver settings without them).  Each
# shim process has its own root, so the shim republishes the named properties
# (xlib-wayland src/xlib/smprops.c).
export XLIB_WAYLAND_SHARE_PROPERTIES="${XLIB_WAYLAND_SHARE_PROPERTIES-_DT_SM_}"

# Keyboard layout.  Applications take their X keymap from the compositor; when
# it has no physical keyboard (the nested test session) the shim builds one from
# XKB_DEFAULT_*, and River uses the same names for its seat.  The "intl" variant
# adds the dead keys the shim now composes itself (dead_acute then e -> é),
# without needing an input method.  Set CDE_XKB_VARIANT= for a plain layout.
export XKB_DEFAULT_LAYOUT="${XKB_DEFAULT_LAYOUT:-us}"
export XKB_DEFAULT_VARIANT="${CDE_XKB_VARIANT-intl}"

# Session save/restore.  There is no shared X server, so XSMP cannot see the
# other clients; the session is instead captured on the Wayland/Linux side, from
# the processes that carry these markers (see scripts/cde-session-save.sh).
# Every application launched by the session inherits them.
#
# The Style Manager's Startup module records "Resume current session" / "Return
# to Home session" in $CDE_STARTUP_PREF instead of telling dtsession: there is no
# shared X server for its session-manager messages to travel over.  That choice
# selects which store is replayed here.
export CDE_SESSION_ROOT="${CDE_SESSION_ROOT:-${XDG_STATE_HOME:-$HOME/.local/state}/cde-wayland/sessions}"
export CDE_STARTUP_PREF="${CDE_STARTUP_PREF:-$CDE_SESSION_ROOT/startup}"
if [ -z "${CDE_SESSION_TYPE:-}" ] && [ -r "$CDE_STARTUP_PREF" ]; then
    case "$(sed -n '1p' "$CDE_STARTUP_PREF" 2>/dev/null)" in
        home)    CDE_SESSION_TYPE=home ;;
        current) CDE_SESSION_TYPE=current ;;
    esac
fi
export CDE_SESSION_TYPE="${CDE_SESSION_TYPE:-current}"
export CDE_SESSION_TAG="${CDE_SESSION_TAG:-cde-wayland-session}"
# Kept out of ~/.dt/sessions: that directory belongs to dtsession, which
# recreates it from its own (XSMP) session data on every start.
export CDE_SESSION_DIR="${CDE_SESSION_DIR:-$CDE_SESSION_ROOT/$CDE_SESSION_TYPE}"
mkdir -p "$CDE_SESSION_ROOT" 2>/dev/null || true
