#!/usr/bin/env bash
# run-session.sh — start a real CDE session: River + CoW + the CDE apps.
#
# This needs a seat (DRM/input), so run it from a TTY or a display manager,
# not from inside another graphical session.  For a headless smoke test of a
# single application use scripts/run-app.sh instead.
#
# It builds a self-contained XDG_CONFIG_HOME in $XDG_CONFIG_HOME/cde-wayland
# from config/ and launches River with our init file.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib.sh"

require_cmd river
command -v cow >/dev/null 2>&1 || die "cow not found; run scripts/build-cow.sh"
[ -x "$CDE_PREFIX/bin/dtwm" ] || warn \
    "dtwm not installed (the CDE panel): run scripts/build-cde.sh panel"

# Real CDE's desktop services.  ToolTalk (and therefore dtwm's messaging) needs
# a portmapper; CoW and the apps still run without it, but the panel complains.
if command -v rpcinfo >/dev/null 2>&1 && ! rpcinfo -p >/dev/null 2>&1; then
    warn "rpcbind is not running; ToolTalk/ttsession will not start."
    warn "Real CDE needs it: sudo systemctl start rpcbind"
fi

conf_home="${XDG_CONFIG_HOME:-$HOME/.config}/cde-wayland"
log "installing session config into $conf_home"
mkdir -p "$conf_home/cow" "$conf_home/river"
cp "$PROJECT_ROOT/config/cow.conf"        "$conf_home/cow/cow.conf"
cp "$PROJECT_ROOT/config/after-start.sh"  "$conf_home/cow/after-start.sh"
cp "$PROJECT_ROOT/config/river-init"      "$conf_home/river/init"
chmod +x "$conf_home/cow/after-start.sh" "$conf_home/river/init"

# Make the shared environment and session script discoverable to cow-start.
install -d "$CDE_PREFIX/share/cde-wayland"
cp "$PROJECT_ROOT/config/cde-env.sh"      "$CDE_PREFIX/share/cde-wayland/cde-env.sh"
cp "$PROJECT_ROOT/config/cde-session.sh"  "$CDE_PREFIX/share/cde-wayland/cde-session.sh"
cp "$PROJECT_ROOT/config/Xresources"      "$CDE_PREFIX/share/cde-wayland/Xresources"
chmod +x "$CDE_PREFIX/share/cde-wayland/cde-session.sh"

export CDE_PREFIX CDE_ROOT
export PATH="$CDE_PREFIX/bin:$PATH"

log "starting River (init: $conf_home/river/init)"
exec env XDG_CONFIG_HOME="$conf_home" \
    CDE_PREFIX="$CDE_PREFIX" CDE_ROOT="$CDE_ROOT" \
    river -c "$conf_home/river/init"
