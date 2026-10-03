#!/usr/bin/env bash
# build-cow.sh — build & install CoW (the window manager), and optionally
# River (the compositor) from source.
#
# River is normally installed by the distro (Arch: `river` 0.4.x). Building it
# from source needs Zig; pass --with-river to do so. CoW itself needs:
#   wayland-client xkbcommon pangocairo cairo libbsd bison flex libevent
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib.sh"

WITH_RIVER=0
for arg in "$@"; do
    case "$arg" in
        --with-river) WITH_RIVER=1 ;;
        -h|--help) echo "usage: $0 [--with-river]"; exit 0 ;;
        *) die "unknown option: $arg" ;;
    esac
done

log "building CoW"
printf '    cow    : %s\n' "$COW_SRC"
printf '    prefix : %s\n' "$COW_PREFIX"

[ -d "$COW_SRC" ] || die "CoW source not found at $COW_SRC (run fetch-sources.sh)"
require_cmd meson
require_cmd ninja

if [ "$WITH_RIVER" -eq 1 ]; then
    log "building River (needs Zig)"
    require_cmd zig
    [ -d "$RIVER_SRC" ] || die "River source not found at $RIVER_SRC"
    # River's build is invoked by its own release tooling; this is a best-effort
    # placeholder until a version is pinned. The distro package is preferred.
    ( cd "$RIVER_SRC" && zig build -Doptimize=ReleaseSafe --prefix "$COW_PREFIX" )
fi

if ! command -v river >/dev/null 2>&1; then
    warn "the 'river' compositor binary was not found in PATH;"
    warn "install it (Arch: pacman -S river) or rerun with --with-river."
fi

meson setup "$COW_SRC/build" "$COW_SRC" \
    --prefix="$COW_PREFIX" --buildtype=release --wipe >/dev/null
ninja -C "$COW_SRC/build"
meson install -C "$COW_SRC/build"

ok "CoW installed in $COW_PREFIX"
