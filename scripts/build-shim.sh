#!/usr/bin/env bash
# build-shim.sh — build & install xlib-wayland (libX11, libXft) and then the
# Xt/Motif layer (libXt, Open Motif) into $CDE_PREFIX.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

log "building the Wayland libX11 shim"
printf '    shim   : %s\n' "$XLIB_WAYLAND"
printf '    prefix : %s\n' "$CDE_PREFIX"

[ -f "$XLIB_WAYLAND/meson.build" ] || die \
"xlib-wayland not found at $XLIB_WAYLAND
Run scripts/fetch-sources.sh first (it clones $XLIB_WAYLAND_REPO), or set
XLIB_WAYLAND to an existing checkout."

require_cmd meson
require_cmd ninja

# The shim's own scripts/build-stack.sh reads MW_PREFIX; keep one prefix.
export MW_PREFIX="$CDE_PREFIX"

log "meson: configure + install libX11/libXft into $CDE_PREFIX"
meson setup "$XLIB_WAYLAND/build" "$XLIB_WAYLAND" \
    --prefix="$CDE_PREFIX" --buildtype=release \
    --wipe >/dev/null
ninja -C "$XLIB_WAYLAND/build"
meson install -C "$XLIB_WAYLAND/build"

log "building libXt + Open Motif against the shim"
"$XLIB_WAYLAND/scripts/build-stack.sh" --prefix="$CDE_PREFIX"

ok "shim + Xt + Motif installed in $CDE_PREFIX"
