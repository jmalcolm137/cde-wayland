#!/usr/bin/env bash
# run-app.sh — run one CDE application under the bundled headless compositor
# and capture a PNG frame.  The application is a native Wayland client on the
# shim; no X server is involved.
#
# Usage: run-app.sh APP [ARG...]
#   APP may be a bare name (resolved via $CDE_ROOT/bin and $PATH) or a path.
#
# Environment:
#   CDE_FRAME_SIZE     WxH     (default 1024x768)
#   CDE_FRAME_TIMEOUT  seconds (default 4)
#   CDE_FRAME_OUT      PNG path (default ./APP.png)
#   CDE_INPUT          input script for the compositor (optional)
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib.sh"

[ "$#" -ge 1 ] || die "usage: run-app.sh APP [ARG...]"
app="$1"; shift || true

if [ -x "$app" ]; then
    app_path="$app"
elif [ -x "$CDE_ROOT/bin/$app" ]; then
    app_path="$CDE_ROOT/bin/$app"
elif command -v "$app" >/dev/null 2>&1; then
    app_path="$(command -v "$app")"
else
    die "application not found: $app"
fi

HC="${HEADLESS_COMPOSITOR:-$XLIB_WAYLAND/build/headless-compositor}"
[ -x "$HC" ] || die "headless compositor not built; run scripts/build-shim.sh ($HC)"

runtime="$(mktemp -d "${TMPDIR:-/tmp}/cde-hc.XXXXXX")"
sock="cde-$$"
out="${CDE_FRAME_OUT:-$PWD/$(basename "$app").png}"
size="${CDE_FRAME_SIZE:-1024x768}"
timeout_s="${CDE_FRAME_TIMEOUT:-6}"
ready="$runtime/ready"

hc_args=(--socket "$sock" --size "$size" --timeout "$timeout_s" --output "$out")
if [ -n "${CDE_INPUT:-}" ]; then
    hc_args+=(--input "$CDE_INPUT")
fi

log "starting headless compositor ($size, ${timeout_s}s) -> $out"
XDG_RUNTIME_DIR="$runtime" "$HC" "${hc_args[@]}" >"$ready" 2>"$runtime/hc.err" &
hc_pid=$!
for _ in $(seq 1 100); do
    grep -q READY "$ready" 2>/dev/null && break
    sleep 0.05
done
grep -q READY "$ready" 2>/dev/null || { cat "$runtime/hc.err" >&2; die "compositor failed to start"; }

# Run the application as a Wayland client of the headless compositor.
export XDG_RUNTIME_DIR="$runtime"
export WAYLAND_DISPLAY="$sock"
export DISPLAY=":0"                      # the shim ignores this, Xt needs it set
# Shim + Motif, the installed CDE libs, and (for an uninstalled tree) the
# build-tree exports.
_cde_libpath="$CDE_PREFIX/lib:$CDE_ROOT/lib${CDE_BUILD:+:$CDE_BUILD/exports/lib}"
export LD_LIBRARY_PATH="$_cde_libpath${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export PATH="$CDE_ROOT/bin:$CDE_PREFIX/bin:$PATH"
export XENVIRONMENT="${XENVIRONMENT:-$PROJECT_ROOT/config/Xresources}"

log "running $app_path $*"
"$app_path" "$@" >"$runtime/app.out" 2>"$runtime/app.err" &
app_pid=$!

# The compositor exits after --timeout having written the frame; the app is a
# long-lived GUI process, so stop it once the compositor is done.
wait "$hc_pid" 2>/dev/null || true
kill "$app_pid" 2>/dev/null || true
wait "$app_pid" 2>/dev/null || true

[ -f "$out" ] || die "no frame captured (see $runtime/hc.err)"
ok "frame written to $out"
printf '    app stderr tail:\n' >&2
tail -8 "$runtime/app.err" >&2 || true
