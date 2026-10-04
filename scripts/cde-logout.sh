#!/bin/sh
# cde-logout — end the CDE session.
#
# The root menu's "Log out..." item (CDE runs the dtsession ExitSession action,
# which we do not run).  There is no session manager here, so end the session by
# stopping the components, most-dependent first: the Front Panel, the calendar
# service, then the window manager, compositor and ToolTalk session.
set -u

pkill -x dtwm      2>/dev/null
pkill -x rpc.cmsd  2>/dev/null
pkill -x cow       2>/dev/null
sleep 1
pkill -x river     2>/dev/null
pkill -x ttsession 2>/dev/null
