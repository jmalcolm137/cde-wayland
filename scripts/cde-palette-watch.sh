#!/bin/sh
# cde-palette-watch — follow a palette chosen in the Style Manager.
#
# Clients read their resource database once, when they start, so a palette
# change only reaches newly started clients.  That is CDE's own behaviour on a
# display without dynamic colour -- the Style Manager's colour editor shows
# "The selected palette will take effect at your next session." for exactly that
# reason -- but it leaves the desktop looking unchanged.
#
# dtsession's colour server republishes the palette as the _DT_SM_PREFERENCES
# property, and the shim relays that property between clients (see
# config/cde-env.sh), so the change can be seen from here.  When it changes,
# restart the colour server and the Front Panel:
#
#   * dtsession holds the colour pixel set that Motif's colour object fetches
#     (XmeGetPixelData, which the Front Panel builds its colours from), and a
#     restarted dtwm keeps getting the old set from it;
#   * dtwm then re-fetches that pixel set and repaints the panel.
#
# Applications are left alone and pick the palette up the next time they start,
# which is what CDE does at the next session.
set -u
: "${CDE_ROOT:=/usr/dt}"
export PATH="$CDE_ROOT/bin:$PATH"

store="${XDG_RUNTIME_DIR:-/tmp}/xlib-wayland/smprops"
ds_log="${XDG_RUNTIME_DIR:-/tmp}/cde-wayland/dtsession.log"

# The property holds just the palette (*0*ColorPalette, *background,
# *foreground), so comparing it whole is enough.  dtwm's own RESOURCE_MANAGER
# writes (workspace and backdrop resources) do not touch it, so they cannot
# trigger a restart.
sig() { grep -a '^_DT_SM_PREFERENCES' "$store" 2>/dev/null | head -1; }

# The panel watcher must not outlive the session: a leftover instance would see
# the next session's palette as a change and restart its colour server.  CoW is
# the session's window manager and is not restarted on its own, so use it as the
# liveness signal (a watcher orphaned by a hard session teardown exits here).
session_alive() { pgrep -x cow >/dev/null 2>&1; }

restart_colour_server_and_panel() {
    pkill -x dtsession 2>/dev/null
    for _ in 1 2 3 4 5 6; do
        pgrep -x dtsession >/dev/null 2>&1 || break
        sleep 0.5
    done
    pkill -9 -x dtsession 2>/dev/null
    sleep 1
    # Same invocation cde-session.sh uses: dtsession must not start a window
    # manager of its own, CoW is the one here.
    dtsession -xrm 'Dtsession*wmStartupCommand: /bin/true' >>"$ds_log" 2>&1 &
    # Let it come up and publish its palette before the panel asks for colours.
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        grep -qa '^_DT_SM_PREFERENCES' "$store" 2>/dev/null && break
        sleep 1
    done
    sleep 2
    if command -v cde-restart-dtwm >/dev/null 2>&1; then
        cde-restart-dtwm
    fi
}

# dtsession publishes its preferences more than once while it starts up, so wait
# for the value to settle before watching: otherwise the flurry at session start
# looks like a palette change and restarts the front-end for nothing.
prev=""
i=0
while [ -z "$prev" ] && [ "$i" -lt 150 ]; do
    prev="$(sig)"
    [ -n "$prev" ] && break
    sleep 0.2
    i=$((i + 1))
done
[ -n "$prev" ] || exit 0

stable=0
while [ "$stable" -lt 3 ]; do
    session_alive || exit 0
    sleep 2
    cur="$(sig)"
    if [ "$cur" = "$prev" ]; then
        stable=$((stable + 1))
    else
        prev="$cur"
        stable=0
    fi
done

while :; do
    session_alive || exit 0
    sleep 2
    cur="$(sig)"
    [ "$cur" = "$prev" ] && continue
    prev="$cur"
    restart_colour_server_and_panel
    # Absorb whatever the restarted components republish, so a re-published
    # palette cannot start a restart loop.
    stable=0
    while [ "$stable" -lt 3 ]; do
        session_alive || exit 0
        sleep 2
        cur="$(sig)"
        if [ "$cur" = "$prev" ]; then
            stable=$((stable + 1))
        else
            prev="$cur"
            stable=0
        fi
    done
done
