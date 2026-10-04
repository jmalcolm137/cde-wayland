#!/bin/sh
# cde-restart-dtwm — restart the CDE Front Panel (dtwm).
#
# The root menu's "Restart Workspace Manager..." item.  dtwm is normally started
# by cde-session.sh and is not supervised, so kill it and start it again with
# the same options the session uses.  Installed as $CDE_ROOT/bin/cde-restart-dtwm
# and run by CoW in the session environment.
set -u
: "${CDE_ROOT:=/usr/dt}"
export PATH="$CDE_ROOT/bin:$PATH"

# dtwm handles SIGTERM for session save, so ask politely and then force it.
pkill -x dtwm 2>/dev/null
for _ in 1 2 3 4 5 6; do
    pgrep -x dtwm >/dev/null 2>&1 || break
    sleep 0.5
done
pkill -9 -x dtwm 2>/dev/null
sleep 1
# Detach so dtwm outlives this helper.
CDE_NO_WM_INFO=1 setsid dtwm -xrm '*useFrontPanel: True' >/dev/null 2>&1 &
