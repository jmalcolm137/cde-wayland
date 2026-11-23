#!/usr/bin/env bash
# build-tools.sh — build the C helper programs in tools/ via tools/Makefile.
#
#   build-tools.sh          build pre-CDE tools (tt-portmapper)
#   build-tools.sh --cde    build CDE/Motif/X11 tools (cde-wsm, cde-confirm,
#                           cde-palette-colours, xrdb)
#   build-tools.sh --all    build all tools
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib.sh"

TARGET="base"
case "${1:-}" in
    "")     TARGET="base" ;;
    --cde)  TARGET="cde" ;;
    --all)  TARGET="all" ;;
    *)      die "usage: $0 [--cde|--all]" ;;
esac

require_cmd make
require_cmd "${CC:-gcc}"

log "building cde-wayland tools ($TARGET)"
make --no-print-directory -C "$PROJECT_ROOT/tools" PREFIX="$CDE_PREFIX" "$TARGET"
ok "installed cde-wayland tools ($TARGET) in $CDE_PREFIX/bin"
