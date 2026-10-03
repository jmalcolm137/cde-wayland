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
# Build tools missing on a minimal/modern host.  We do not require root: on a
# pacman-based system we unpack the package into $CDE_PREFIX/tools, which the
# build scripts add to PATH.
# ---------------------------------------------------------------------------

# rpcgen: CDE generates XDR/RPC stubs at build time (lib/csa, lib/tt).
ensure_rpcgen() {
    if command -v rpcgen >/dev/null 2>&1; then
        ok "system rpcgen found: $(command -v rpcgen)"
        return 0
    fi
    if [ -x "$CDE_PREFIX/tools/rpcgen" ]; then
        ok "rpcgen already unpacked in $CDE_PREFIX/tools"
        return 0
    fi
    if command -v pacman >/dev/null 2>&1; then
        local url tmp
        url="$(pacman -Sp --print-format '%l' rpcsvc-proto 2>/dev/null | head -1)"
        if [ -n "$url" ]; then
            log "unpacking rpcsvc-proto (rpcgen) into $CDE_PREFIX/tools"
            tmp="$(mktemp -d)"
            curl -fsSL "$url" -o "$tmp/pkg.zst"
            tar --zstd -xf "$tmp/pkg.zst" -C "$tmp"
            mkdir -p "$CDE_PREFIX/tools"
            cp -a "$tmp/usr/bin/." "$CDE_PREFIX/tools/" 2>/dev/null || true
            rm -rf "$tmp"
            [ -x "$CDE_PREFIX/tools/rpcgen" ] && ok "rpcgen unpacked" && return 0
        fi
    fi
    warn "rpcgen not found and could not be unpacked automatically."
    warn "Install it (Arch: rpcsvc-proto) before build-cde.sh."
}

if command -v imake >/dev/null 2>&1; then
    ok "system imake found: $(command -v imake)"
else
    ok "no system imake; CDE's bundled imake will be bootstrapped (build-cde.sh)."
fi

ensure_rpcgen
ok "sources ready"
