#!/usr/bin/env bash
# run-session.sh — start a CDE session: River + CoW + the real CDE Front Panel.
#
# Normally run this from a TTY or a display manager (it needs a seat/DRM).  For
# testing inside another Wayland session, --nested runs River on wlroots'
# Wayland backend so the whole CDE desktop appears in a window.
#
# ToolTalk (used by the Front Panel to launch applications) needs a portmapper.
# If the system rpcbind is not running, this script re-runs itself inside an
# unprivileged user+network namespace with tools/tt-portmapper, so no root is
# required.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib.sh"

NESTED="${CDE_NESTED:-0}"
for arg in "$@"; do
    case "$arg" in
        --nested) NESTED=1 ;;
        -h|--help) echo "usage: $0 [--nested]"; exit 0 ;;
        *) die "unknown option: $arg" ;;
    esac
done

export CDE_PREFIX CDE_ROOT
export PATH="$CDE_PREFIX/bin:$CDE_ROOT/bin:$PATH"

require_cmd river
command -v cow >/dev/null 2>&1 || die "cow not found; run scripts/build-cow.sh"
[ -x "$CDE_PREFIX/bin/dtwm" ] || warn \
    "dtwm not installed (the CDE panel): run scripts/build-cde.sh panel"

# ---------------------------------------------------------------------------
# ToolTalk: a portmapper is required.  Prefer a running rpcbind; otherwise run
# our own tt-portmapper inside an unprivileged user+network namespace (where
# binding port 111 is allowed).
# ---------------------------------------------------------------------------
portmapper_ok() { rpcinfo -T tcp 127.0.0.1 >/dev/null 2>&1; }
PM_PID=""

if [ "${CDE_SESSION_NS:-0}" != 1 ] && ! portmapper_ok; then
    if command -v unshare >/dev/null 2>&1 && [ -x "$CDE_PREFIX/bin/tt-portmapper" ]; then
        log "no rpcbind; re-running in an unprivileged user+network namespace"
        _args=(--nested)
        [ "$NESTED" = 1 ] || _args=()
        exec env CDE_SESSION_NS=1 CDE_NESTED="$NESTED" \
            unshare --user --map-root-user --net -- \
            bash -c 'ip link set lo up 2>/dev/null || true; exec "$0" "$@"' \
            "$0" "${_args[@]}"
    fi
    warn "no portmapper reachable: the Front Panel will not launch applications."
    warn "Start rpcbind (sudo systemctl start rpcbind) or build scripts/build-tools.sh."
fi

if [ "${CDE_SESSION_NS:-0}" = 1 ]; then
    "$CDE_PREFIX/bin/tt-portmapper" >/tmp/tt-portmapper.log 2>&1 &
    PM_PID=$!
    sleep 1
fi
cleanup() { [ -n "$PM_PID" ] && kill "$PM_PID" 2>/dev/null || true; }
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Session configuration.
# ---------------------------------------------------------------------------
conf_home="${XDG_CONFIG_HOME:-$HOME/.config}/cde-wayland"
log "installing session config into $conf_home"
mkdir -p "$conf_home/cow" "$conf_home/river"
cp "$PROJECT_ROOT/config/cow.conf"        "$conf_home/cow/cow.conf"
cp "$PROJECT_ROOT/config/after-start.sh"  "$conf_home/cow/after-start.sh"
cp "$PROJECT_ROOT/config/river-init"      "$conf_home/river/init"
chmod +x "$conf_home/cow/after-start.sh" "$conf_home/river/init"

install -d "$CDE_PREFIX/share/cde-wayland"
cp "$PROJECT_ROOT/config/cde-env.sh"      "$CDE_PREFIX/share/cde-wayland/cde-env.sh"
cp "$PROJECT_ROOT/config/cde-session.sh"  "$CDE_PREFIX/share/cde-wayland/cde-session.sh"
cp "$PROJECT_ROOT/config/Xresources"      "$CDE_PREFIX/share/cde-wayland/Xresources"
chmod +x "$CDE_PREFIX/share/cde-wayland/cde-session.sh"

# The shim (xlib-wayland) reads this session resource file independently of
# XENVIRONMENT, so clients started without the CDE environment still get CDE's
# fontsets (DtTerm's *userFont) and app-defaults.  Without it, DtTerm falls back
# to a single core font and draws only a quarter of each multibyte string.
install -D -m 0644 "$PROJECT_ROOT/config/Xresources" \
    "$conf_home/xlib-wayland/Xresources"

export XDG_CONFIG_HOME="$conf_home"
if [ "$NESTED" = 1 ]; then
    log "nested mode: River on the wlroots Wayland backend"
    export WLR_BACKENDS=wayland WLR_LIBINPUT_NO_DEVICES=1
fi

# Our clients never connect to Xwayland: the shim ignores DISPLAY and speaks
# Wayland directly.  River may still start Xwayland for other tools, so we only
# disable it in the unprivileged namespace, where it cannot create its socket.
#
# Start the whole session inside a ToolTalk process-tree session.  ToolTalk
# advertises its session address through an X property, which cannot work here
# (the shim gives every client its own private X server); `ttsession -c`
# instead exports TT_SESSION (and the start token) to the process tree, so
# every CDE client joins the session directly.  This is what makes the
# ToolTalk-based apps (File Manager, Mailer, ...) work.
command -v ttsession >/dev/null 2>&1 || \
    die "ttsession not found; run scripts/install-panel-data.sh"

TT_ARGS=( -a unix -c river )
if [ "${CDE_SESSION_NS:-0}" = 1 ]; then
    TT_ARGS+=( -no-xwayland )
fi
TT_ARGS+=( -c "$conf_home/river/init" )

log "starting River under a ToolTalk session (init: $conf_home/river/init)"
exec ttsession "${TT_ARGS[@]}"
