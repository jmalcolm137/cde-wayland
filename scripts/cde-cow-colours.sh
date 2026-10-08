#!/bin/sh
# cde-cow-colours — give CoW the CDE palette's colours for its own chrome.
#
# CoW draws the window frames, the window/workspace menus and the minimized
# icons, but it is a Wayland compositor and not an X client, so it cannot read
# the palette dtsession's colour server publishes.  cde-palette-colours reads
# that palette the way CDE's own dtwm does (the active, inactive and primary
# pixel sets behind XmeGetPixelData) and prints the colours; this hands them to
# CoW, so the whole desktop follows a palette change instead of keeping the
# hand-picked colours in config/cow.conf.
#
#   frames : active set for the focused window, inactive set for the rest
#   menus  : the client colours, with the active set for menu titles
#
# Run by cde-session.sh once the palette is up, and by cde-palette-watch.sh
# whenever it changes.
set -u
: "${CDE_ROOT:=/usr/dt}"
export PATH="$CDE_ROOT/bin:$PATH"

command -v moocow >/dev/null 2>&1 || exit 0
[ -x "$CDE_ROOT/bin/cde-palette-colours" ] || exit 0

# KEY=#rrggbb lines only, so an incidental message cannot be eval'd.
vals="$(cde-palette-colours 2>/dev/null | grep -E '^[a-z_]+=#[0-9a-fA-F]{6}$')" || exit 0
[ -n "$vals" ] || exit 0
eval "$vals"
[ -n "${active_bg:-}" ] && [ -n "${inactive_bg:-}" ] && [ -n "${primary_bg:-}" ] || exit 0

hex() { printf '0x%s' "${1#\#}"; }

# Frames and minimized icons.
moocow decor -d default titlebar.active_colour   "$(hex "$active_bg")"    >/dev/null 2>&1
moocow decor -d default titlebar.fg_active       "$(hex "$active_fg")"    >/dev/null 2>&1
moocow decor -d default titlebar.inactive_colour "$(hex "$inactive_bg")"  >/dev/null 2>&1
moocow decor -d default titlebar.fg_inactive     "$(hex "$inactive_fg")"  >/dev/null 2>&1
moocow decor -d default border.colour            "$(hex "$active_bg")"    >/dev/null 2>&1
moocow decor -d default icon.background          "$(hex "$active_bg")"    >/dev/null 2>&1
moocow decor -d default icon.foreground          "$(hex "$active_fg")"    >/dev/null 2>&1
moocow decor -d default icon.active.background   "$(hex "$active_bg")"    >/dev/null 2>&1
moocow decor -d default icon.active.foreground   "$(hex "$active_fg")"    >/dev/null 2>&1
moocow decor -a default >/dev/null 2>&1

# Menus: the client colours, with the active set for titles and the inactive set
# for the separators and disabled entries.
moocow menu-style bg             "$(hex "$primary_bg")"    >/dev/null 2>&1
moocow menu-style fg             "$(hex "$primary_fg")"    >/dev/null 2>&1
moocow menu-style title.bg       "$(hex "$active_bg")"     >/dev/null 2>&1
moocow menu-style title.fg       "$(hex "$active_fg")"     >/dev/null 2>&1
moocow menu-style border.colour  "$(hex "$active_bg")"     >/dev/null 2>&1
moocow menu-style separator      "$(hex "$inactive_bg")"   >/dev/null 2>&1
moocow menu-style disabled       "$(hex "$inactive_bg")"   >/dev/null 2>&1
# Explicitly leave the side strip off: it is drawn only when it has a colour,
# and it is 24px wide (side.width), so giving it one makes every menu wider.
moocow menu-style side.colour    none                      >/dev/null 2>&1
