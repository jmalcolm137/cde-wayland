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

# Retry with exponential-ish backoff (~2s total, 16 tries instead of 40) so
# windows that register within a frame finish fast without hammering moocow.
for delay in 0.02 0.02 0.05 0.05 0.05 0.1 0.1 0.1 0.15 0.15 0.2 0.2 0.2 0.2 0.2 0.2; do
    out=$(moocow "$@" 2>/dev/null)
    case "$out" in
        *'"ok":'*true*) exit 0 ;;
    esac
    sleep "$delay"
done
exit 0
