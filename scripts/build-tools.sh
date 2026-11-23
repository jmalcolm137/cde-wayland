#!/usr/bin/env bash
# build-tools.sh — build the C helper programs in tools/.
#
#   build-tools.sh          build pre-CDE tools (tt-portmapper)
#   build-tools.sh --cde    build CDE/Motif/X11 tools (cde-wsm, cde-confirm,
#                           cde-palette-colours, xrdb)
#   build-tools.sh --all    build all tools
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib.sh"

MODE="base"
case "${1:-}" in
    "")     MODE="base" ;;
    --cde)  MODE="cde" ;;
    --all)  MODE="all" ;;
    *)      die "usage: $0 [--cde|--all]" ;;
esac

CC="${CC:-gcc}"
CFLAGS=(-O2 -g -Wall -Wextra)
require_cmd "$CC"
mkdir -p "$CDE_PREFIX/bin"

build_base() {
    log "building cde-wayland base tools"
    # tt-portmapper: a minimal rpcbind-compatible portmapper so ToolTalk can run
    # without root (see tools/tt-portmapper.c and scripts/run-session.sh).
    local tirpc_cflags tirpc_libs
    tirpc_cflags="$(pkg-config --cflags libtirpc 2>/dev/null || echo -I/usr/include/tirpc)"
    tirpc_libs="$(pkg-config --libs libtirpc 2>/dev/null || echo -ltirpc)"
    # shellcheck disable=SC2086
    "$CC" "${CFLAGS[@]}" $tirpc_cflags \
        -o "$CDE_PREFIX/bin/tt-portmapper" \
        "$PROJECT_ROOT/tools/tt-portmapper.c" \
        $tirpc_libs
    ok "installed $CDE_PREFIX/bin/tt-portmapper"
}

build_cde_tools() {
    log "building cde-wayland CDE/Motif tools"
    local inc=(-I"$CDE_PREFIX/dt/include" -I"$CDE_PREFIX/include" -I/usr/include/tirpc)
    local lib=(-L"$CDE_PREFIX/dt/lib" -L"$CDE_PREFIX/lib")
    local rpath=(-Wl,-rpath,"$CDE_PREFIX/lib:$CDE_PREFIX/dt/lib")

    # Workspace Manager client (DtWsm -> dtwm).
    if [ -f "$PROJECT_ROOT/tools/cde-wsm.c" ]; then
        if "$CC" "${CFLAGS[@]}" "${inc[@]}" "${lib[@]}" \
                -o "$CDE_PREFIX/bin/cde-wsm" "$PROJECT_ROOT/tools/cde-wsm.c" \
                -lDtSvc -ltt -lXm -lXt -lX11 "${rpath[@]}"; then
            ok "installed cde-wsm (Workspace Manager client)"
        else
            warn "could not build cde-wsm; CoW's workspace menu will not work"
        fi
    fi

    # Logout confirmation dialog.
    if [ -f "$PROJECT_ROOT/tools/cde-confirm.c" ]; then
        if "$CC" "${CFLAGS[@]}" "${inc[@]}" "${lib[@]}" \
                -o "$CDE_PREFIX/bin/cde-confirm" "$PROJECT_ROOT/tools/cde-confirm.c" \
                -lXm -lXt -lX11 "${rpath[@]}"; then
            ok "installed cde-confirm (logout confirmation)"
        else
            warn "could not build cde-confirm; logout will not ask for confirmation"
        fi
    fi

    # Frame and menu colours for CoW.
    if [ -f "$PROJECT_ROOT/tools/cde-palette-colours.c" ]; then
        if "$CC" "${CFLAGS[@]}" "${inc[@]}" "${lib[@]}" \
                -o "$CDE_PREFIX/bin/cde-palette-colours" \
                "$PROJECT_ROOT/tools/cde-palette-colours.c" \
                -lXm -lXt -lX11 "${rpath[@]}"; then
            ok "installed cde-palette-colours (CDE frame/menu colours)"
        else
            warn "could not build cde-palette-colours; CoW keeps its own colours"
        fi
    fi

    # Shim-linked xrdb for dtsession_res.
    if [ -f "$PROJECT_ROOT/tools/xrdb.c" ]; then
        if "$CC" "${CFLAGS[@]}" -I"$CDE_PREFIX/include" -L"$CDE_PREFIX/lib" \
                -o "$CDE_PREFIX/bin/xrdb" "$PROJECT_ROOT/tools/xrdb.c" \
                -lX11 -Wl,-rpath,"$CDE_PREFIX/lib"; then
            ok "installed xrdb (dtsession_res can load resources)"
        else
            warn "could not build xrdb; dtsession_res will keep failing"
        fi
    fi
}

case "$MODE" in
    base) build_base ;;
    cde)  build_cde_tools ;;
    all)  build_base; build_cde_tools ;;
esac
