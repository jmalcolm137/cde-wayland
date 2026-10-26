#!/usr/bin/env bash
#
# build-demo-input.sh — build the input-injection helpers used by
# scripts/demo-record.sh.  They speak the wlroots virtual pointer /
# virtual keyboard protocols, which River implements, so they drive the nested
# session exactly like a local mouse and keyboard.
#
#   vclick  X Y [w h]        single click
#   vdclick X Y [gap_ms]     double click
#   vdrag   X1 Y1 X2 Y2      slow drag (Motif drag-and-drop needs the press to
#                            settle before the motion leaves the icon)
#   vmove   X Y [w h]        move the pointer
#   vkey    [-d ms] TEXT     type text (\n Return, \t Tab, \e Escape)
#
# All coordinates are in the session compositor's output space (same space that
# grim captures and `moocow show -a window` reports).
#
# NOTE: create_virtual_pointer must be given the real wl_seat.  With a NULL seat
# the compositor delivers the events only to its own (WM) menus and never to the
# shim's client surfaces, which is very confusing to debug.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
src="$here/../tools/demo-input"
prefix="${CDE_PREFIX:-$HOME/.local/motif-wayland}"
bindir="$prefix/bin"

command -v wayland-scanner >/dev/null || { echo "wayland-scanner not found" >&2; exit 1; }
pkg-config --exists wayland-client xkbcommon || { echo "need wayland-client + xkbcommon" >&2; exit 1; }

install -d "$bindir"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# wlroots virtual pointer (generated code is kept in the tree)
cp "$src/vptr.h" "$src/vptr.c" "$tmp/"
# virtual keyboard: regenerate from the small protocol description
wayland-scanner client-header "$src/vkbd.xml" "$tmp/vkbd.h"
wayland-scanner private-code  "$src/vkbd.xml" "$tmp/vkbd.c"

CFLAGS="$(pkg-config --cflags wayland-client xkbcommon)"
LIBS="$(pkg-config --libs wayland-client xkbcommon)"

for t in vclick vdclick vdrag vmove vmouse; do
    cc -O2 $CFLAGS -o "$bindir/$t" "$src/$t.c" "$tmp/vptr.c" "$tmp/vptr.h" -I"$tmp" $LIBS
    echo "  $t -> $bindir/$t"
done
cc -O2 -D_GNU_SOURCE $CFLAGS -o "$bindir/vkey" "$src/vkey.c" "$tmp/vkbd.c" -I"$tmp" $LIBS
echo "  vkey -> $bindir/vkey"
