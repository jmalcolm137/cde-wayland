#!/usr/bin/env bash
# fetch-sources.sh — clone the upstream sources (and fetch imake if missing).
#
# Reads pinned revisions from versions.lock. Idempotent: existing checkouts are
# updated to the pinned revision.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

# shellcheck source=/dev/null
source "$PROJECT_ROOT/versions.lock"

log "CDE-on-Wayland source fetch"
printf '    cache : %s\n' "$CDE_CACHE"
printf '    xlib  : %s @ %s\n' "$XLIB_WAYLAND_REPO" "$XLIB_WAYLAND_REF"
printf '    cde   : %s @ %s\n' "$CDE_REPO" "$CDE_REF"
printf '    cow   : %s @ %s\n' "$COW_REPO" "$COW_REF"
printf '    river : %s @ %s\n' "$RIVER_REPO" "$RIVER_REF"

require_cmd git
mkdir -p "$CDE_CACHE/src"

# xlib-wayland lives in its own repository; only fetch it when we are not
# already pointed at a local checkout (e.g. a sibling working tree).
if [ ! -f "$XLIB_WAYLAND/meson.build" ]; then
    fetch_src "$XLIB_WAYLAND_REPO" "$XLIB_WAYLAND_REF" "$XLIB_WAYLAND"
else
    log "using local xlib-wayland checkout: $XLIB_WAYLAND"
fi

fetch_src "$CDE_REPO"   "$CDE_REF"   "$CDE_SRC"
fetch_src "$COW_REPO"   "$COW_REF"   "$COW_SRC"
fetch_src "$RIVER_REPO" "$RIVER_REF" "$RIVER_SRC"

# ---------------------------------------------------------------------------
# imake: CDE ships its own bootstrap, so the distro package is only a fallback
# and a convenience for the non-root case. If `imake` is absent, unpack the
# distro package into $CDE_PREFIX/tools without root (Arch/most distros).
# ---------------------------------------------------------------------------
if command -v imake >/dev/null 2>&1; then
    ok "system imake found: $(command -v imake)"
else
    warn "no system imake; CDE's bundled imake will be bootstrapped instead."
    warn "build-cde.sh handles this automatically."
fi

ok "sources ready"
