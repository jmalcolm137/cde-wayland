#!/usr/bin/env bash
# lib.sh — shared environment and helpers for the CDE-on-Wayland scripts.
# Source this; do not execute it directly.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"

# --- prefix / sources ------------------------------------------------------
CDE_PREFIX="${CDE_PREFIX:-$HOME/.local/cde-wayland}"
CDE_CACHE="${CDE_CACHE:-$HOME/.cache/cde-wayland}"

# xlib-wayland is a separate upstream project (the Wayland libX11 shim); it is
# not vendored here.  By default we use a checkout in the cache, but a local
# sibling checkout is used automatically if one exists.
if [ -z "${XLIB_WAYLAND:-}" ]; then
    if [ -d "$PROJECT_ROOT/../xlib-wayland/meson.build" ]; then
        XLIB_WAYLAND="$PROJECT_ROOT/../xlib-wayland"
    else
        XLIB_WAYLAND="$CDE_CACHE/src/xlib-wayland"
    fi
fi
XLIB_WAYLAND_REPO="${XLIB_WAYLAND_REPO:-https://github.com/jmalcolm137/xlib-wayland.git}"
XLIB_WAYLAND_REF="${XLIB_WAYLAND_REF:-main}"

# Upstream libXt + Open Motif sources.  fetch-sources.sh unpacks the pinned
# tarballs here, build-shim.sh builds them against the shim, and build-cde.sh
# reads Motif's bitmaps from $MOTIF_SRC/bitmaps when Motif did not install them.
MW_SRC="${MW_SRC:-$CDE_CACHE/src/xlib-wayland}"
LIBXT_SRC="${LIBXT_SRC:-$MW_SRC/libxt}"
MOTIF_SRC="${MOTIF_SRC:-$MW_SRC/motif}"

CDE_SRC="${CDE_SRC:-$CDE_CACHE/src/cde}"
CDE_BUILD="${CDE_BUILD:-$CDE_PREFIX/build/cde}"
COW_SRC="${COW_SRC:-$CDE_CACHE/src/cow}"
RIVER_SRC="${RIVER_SRC:-$CDE_CACHE/src/river}"

# CDE installs under $CDE_PREFIX/dt and reports that as ProjectRoot.
CDE_ROOT="${CDE_ROOT:-$CDE_PREFIX/dt}"

# CoW installs into the same prefix (bin/, lib/, share/).
COW_PREFIX="${COW_PREFIX:-$CDE_PREFIX}"

if [ -n "${JOBS:-}" ]; then
    :
elif command -v nproc >/dev/null 2>&1; then
    JOBS="$(nproc)"
else
    JOBS=4
fi

export CDE_PREFIX CDE_CACHE XLIB_WAYLAND CDE_SRC CDE_BUILD COW_SRC RIVER_SRC
export MW_SRC LIBXT_SRC MOTIF_SRC
export CDE_ROOT COW_PREFIX JOBS
export XLIB_WAYLAND_REPO XLIB_WAYLAND_REF

# --- output ----------------------------------------------------------------
if [ -t 2 ]; then
    _c_reset=$'\033[0m'; _c_blue=$'\033[1;34m'; _c_yellow=$'\033[1;33m'
    _c_red=$'\033[1;31m'; _c_green=$'\033[1;32m'
else
    _c_reset=""; _c_blue=""; _c_yellow=""; _c_red=""; _c_green=""
fi

log()  { printf '\n%s==>%s %s\n' "$_c_blue" "$_c_reset" "$*" >&2; }
ok()   { printf '%s ok %s %s\n'   "$_c_green" "$_c_reset" "$*" >&2; }
warn() { printf '%swarning:%s %s\n' "$_c_yellow" "$_c_reset" "$*" >&2; }
die()  { printf '%serror:%s %s\n'   "$_c_red" "$_c_reset" "$*" >&2; exit 1; }

# --- helpers ---------------------------------------------------------------
require_cmd() {
    command -v "$1" >/dev/null 2>&1 || \
        die "required tool '$1' not found in PATH"
}

require_any_cmd() {
    local c
    for c in "$@"; do command -v "$c" >/dev/null 2>&1 && return 0; done
    die "none of these tools found in PATH: $*"
}

# fetch_src <repo> <ref> <dest> — clone if missing, else fetch/reset.
fetch_src() {
    local repo="$1" ref="$2" dest="$3"
    if [ ! -d "$dest/.git" ]; then
        log "cloning $repo ($ref)"
        mkdir -p "$(dirname "$dest")"
        git init -q "$dest"
        git -C "$dest" remote add origin "$repo"
    else
        log "updating $(basename "$dest") ($ref)"
    fi
    # Fetch the ref, then check it out detached.  Doing it this way (rather than
    # `clone --branch`) accepts a bare commit SHA as well as a branch or tag,
    # which is what versions.lock pins.  -f discards the patch overlays a
    # previous build applied in place; build-cow.sh re-applies them.
    git -C "$dest" fetch -q --depth 1 origin "$ref"
    git -C "$dest" checkout -q -f FETCH_HEAD
}
