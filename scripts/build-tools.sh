#!/usr/bin/env bash
# build-tools.sh — build the small helper programs in tools/ (tt-portmapper).
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib.sh"

log "building cde-wayland tools"
require_cmd gcc
mkdir -p "$CDE_PREFIX/bin"

# tt-portmapper: a minimal rpcbind-compatible portmapper so ToolTalk can run
# without root (see tools/tt-portmapper.c and scripts/run-session.sh).
TIRPC_CFLAGS="$(pkg-config --cflags libtirpc 2>/dev/null || echo -I/usr/include/tirpc)"
TIRPC_LIBS="$(pkg-config --libs libtirpc 2>/dev/null || echo -ltirpc)"
gcc -O2 -g -Wall $TIRPC_CFLAGS \
    -o "$CDE_PREFIX/bin/tt-portmapper" \
    "$PROJECT_ROOT/tools/tt-portmapper.c" \
    $TIRPC_LIBS
ok "installed $CDE_PREFIX/bin/tt-portmapper"
