#!/usr/bin/env bash
# verify-pins.sh — confirm that every revision in versions.lock still resolves
# upstream, and that a pinned commit is exactly the commit that comes back.
#
#   scripts/verify-pins.sh
#
# Run by `make verify-pins` and by CI on every push.  It works in throwaway
# repositories, so it neither needs nor disturbs the build cache.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib.sh"
# shellcheck source=/dev/null
source "$PROJECT_ROOT/versions.lock"

fails=0

is_sha() {
    case "$1" in
        *[!0-9a-f]*) return 1 ;;
    esac
    [ "${#1}" -eq 40 ]
}

verify() {
    local name="$1" repo="$2" ref="$3"
    local tmp got when subject

    tmp="$(mktemp -d)"
    git init -q "$tmp"
    git -C "$tmp" remote add origin "$repo"
    if ! git -C "$tmp" fetch -q --depth 1 origin "$ref" 2>/dev/null; then
        rm -rf "$tmp"
        warn "$name: cannot fetch '$ref' from $repo"
        fails=$((fails + 1))
        return 0
    fi
    got="$(git -C "$tmp" rev-parse 'FETCH_HEAD^{commit}')"
    when="$(git -C "$tmp" log -1 --format='%cs' "$got" 2>/dev/null || echo '?')"
    subject="$(git -C "$tmp" log -1 --format='%s' "$got" 2>/dev/null || echo '?')"
    rm -rf "$tmp"

    if is_sha "$ref" && [ "$got" != "$ref" ]; then
        warn "$name: pinned $ref but upstream gave $got"
        fails=$((fails + 1))
        return 0
    fi
    ok "$name: $got ($when) $subject"
}

verify "xlib-wayland" "$XLIB_WAYLAND_REPO" "$XLIB_WAYLAND_REF"
verify "cde"          "$CDE_REPO"          "$CDE_REF"
verify "cow"          "$COW_REPO"          "$COW_REF"
verify "river"        "$RIVER_REPO"        "$RIVER_REF"

if [ "$fails" -ne 0 ]; then
    die "$fails pin(s) did not verify"
fi
ok "all pins resolve"
