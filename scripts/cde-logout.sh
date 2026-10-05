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

pkill -x dtsession 2>/dev/null
pkill -x dtwm      2>/dev/null
pkill -x rpc.cmsd  2>/dev/null
pkill -x cow       2>/dev/null
sleep 1
pkill -x river     2>/dev/null
pkill -x ttsession 2>/dev/null
