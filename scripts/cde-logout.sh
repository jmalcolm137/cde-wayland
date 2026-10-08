#!/bin/sh
# cde-logout — end the CDE session.
#
# Run for the Front Panel's Exit control (the ExitSession action is rewritten to
# this in install-panel-data.sh) and for the root menu's "Log out..." item.
# dtsession's own XSession_Exit flow assumes it owns the whole session, which it
# does not under the shim, so end the session here instead: stop the components
# most-dependent first -- the session manager, Front Panel, calendar service,
# then the window manager, compositor and ToolTalk session.
set -u

# Ask for confirmation first, unless the user turned the dialog off.  The Style
# Manager's Startup module records that in $CDE_STARTUP_PREF (see
# patches/dtstyle-startup.patch); CDE_LOGOUT_CONFIRM=0/1 overrides it.
want_confirm=0
case "${CDE_LOGOUT_CONFIRM:-}" in
    1) want_confirm=1 ;;
    0) want_confirm=0 ;;
    *) pref="${CDE_STARTUP_PREF:-}"
       [ -n "$pref" ] || \
           pref="${CDE_SESSION_ROOT:-${XDG_STATE_HOME:-$HOME/.local/state}/cde-wayland/sessions}/startup"
       [ "$(sed -n '2p' "$pref" 2>/dev/null)" = "on" ] && want_confirm=1 ;;
esac
if [ "$want_confirm" = 1 ] && command -v cde-confirm >/dev/null 2>&1; then
    cde-confirm "Log out" "Do you want to end your session?" || exit 0
fi

# Record what is running before tearing the session down, so the next start can
# bring it back (cde-session.sh runs cde-session-restore.sh).
if command -v cde-session-save.sh >/dev/null 2>&1; then
    cde-session-save.sh >/dev/null 2>&1 || true
fi

pkill -x dtsession 2>/dev/null
pkill -x dtwm      2>/dev/null
pkill -x rpc.cmsd  2>/dev/null
pkill -x cow       2>/dev/null
sleep 1
pkill -x river     2>/dev/null
pkill -x ttsession 2>/dev/null
