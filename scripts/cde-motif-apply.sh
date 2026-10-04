#!/bin/sh
# cde-motif-apply — run a CoW command, retrying briefly until it succeeds.
#
# xlib-wayland relays _MOTIF_WM_HINTS right after a window maps, which can be
# before CoW has registered the window's title.  A selector that matches nothing
# yet makes CoW report {"ok": false}, so retry until the window appears (it does
# within a frame or two).  Arguments are passed straight through to moocow.
#
# Usage: cde-motif-apply decor -a PROFILE -t SELECTOR
set -u

i=0
while [ "$i" -lt 40 ]; do
    out=$(moocow "$@" 2>/dev/null)
    case "$out" in
        *'"ok":'*true*) exit 0 ;;
    esac
    i=$((i + 1))
    sleep 0.05
done
exit 0
