#!/bin/sh
# cde-session.sh — bring up the CDE session under CoW.
#
# CoW is the real window manager for every application.  The CDE Front Panel
# is dtwm, run here as a *contained panel*: because the shim gives each process
# a private X server, dtwm only ever sees and manages its own windows, so its
# window-manager role cannot touch the CDE apps (separate processes) that CoW
# manages.  See DESIGN.md §5.2.
set -eu

: "${CDE_PREFIX:=${HOME}/.local/cde-wayland}"

# Prefer the installed environment; fall back to the one next to this script
# (running from the source tree).
_dir="$(cd -- "$(dirname -- "$0")" && pwd -P)"
if [ -f "$_dir/cde-env.sh" ]; then
    . "$_dir/cde-env.sh"
fi
if [ -f "$CDE_PREFIX/share/cde-wayland/cde-env.sh" ]; then
    . "$CDE_PREFIX/share/cde-wayland/cde-env.sh"
fi

log() { printf 'cde-session: %s\n' "$*" >&2; }

if [ -z "${TT_SESSION:-}" ]; then
    log "warning: no ToolTalk session; CDE apps may show ToolTalk errors."
    log "         run-session.sh starts one with 'ttsession -c'."
fi

# Calendar Manager service (rpc.cmsd), dtcm's backend.  The patched daemon runs
# as the user with a private spool directory, so it needs no root; without it
# dtcm shows "rpc.cmsd is not responding".
if command -v rpc.cmsd >/dev/null 2>&1; then
    log "starting the Calendar Manager service (rpc.cmsd)"
    _cmsd_log="${XDG_RUNTIME_DIR:-/tmp}/cde-wayland/rpc-cmsd.log"
    mkdir -p "$(dirname "$_cmsd_log")" 2>/dev/null || true
    CDE_CMSD_DIR="${CDE_CMSD_DIR:-$HOME/.calendar}" \
        rpc.cmsd >"$_cmsd_log" 2>&1 &
fi

# Application Manager.  dtappgather gathers the CDE application groups
# (Desktop_Apps, Desktop_Tools, ...) into TARGET_APPMAN_DIR, which cde-env.sh
# points at a writable directory.  With -r it only adds entries that are
# missing, so re-running it each session is harmless; the ReloadApps action
# re-runs it too.
if command -v dtappgather >/dev/null 2>&1; then
    log "gathering the Application Manager groups (dtappgather)"
    mkdir -p "${XDG_RUNTIME_DIR:-/tmp}/cde-wayland" 2>/dev/null || true
    dtappgather -r >"${XDG_RUNTIME_DIR:-/tmp}/cde-wayland/dtappgather.log" 2>&1 \
        || log "warning: dtappgather failed (see the log)"
else
    log "warning: dtappgather not found; the Application Manager will be empty"
fi

# The CDE session manager (real dtsession).  It provides the session protocol
# (the ToolTalk SM ops and the _DT_SM_* window/properties that Style Manager's
# Startup panel looks for) and, via InitializeDtcolor(), the Dtcolor colour
# server that the Style Manager's Color module talks to.  CoW is the window
# manager, so wmStartupCommand is pointed at /bin/true: dtsession must not start
# a WM (and, since there is no saved session, it starts nothing else).  Started
# before the Front Panel so the panel can see the manager.
if command -v dtsession >/dev/null 2>&1; then
    log "starting the CDE session manager (dtsession)"
    _ds_log="${XDG_RUNTIME_DIR:-/tmp}/cde-wayland/dtsession.log"
    mkdir -p "$(dirname "$_ds_log")" 2>/dev/null || true
    dtsession -xrm 'Dtsession*wmStartupCommand: /bin/true' >"$_ds_log" 2>&1 &
else
    log "warning: dtsession not found; the Startup/Color modules will be limited"
fi

# Clients read their resource database when they start, and dtsession's colour
# server publishes the CDE palette as RESOURCE_MANAGER only once it is up, so
# anything started immediately after dtsession would miss it.  Wait for the
# shim's shared-property store to carry the palette before bringing up the
# panel (bounded, and skipped when the property is not being relayed).
case ",${XLIB_WAYLAND_SHARE_PROPERTIES-}," in
    *,RESOURCE_MANAGER,*)
        _shp="${XDG_RUNTIME_DIR:-/tmp}/xlib-wayland/smprops"
        _waited=0
        while [ "$_waited" -lt 100 ]; do
            grep -q '^RESOURCE_MANAGER' "$_shp" 2>/dev/null && break
            sleep 0.1
            _waited=$((_waited + 1))
        done
        if [ "$_waited" -ge 100 ]; then
            log "warning: no CDE palette after 10s; clients use the fallback colours"
        fi
        ;;
esac

# The CDE Front Panel (real dtwm, contained).  dtwm skips its own ToolTalk
# messaging: registering as the workspace/window manager is wrong here (CoW is
# the WM) and it stopped the Front Panel from being created.
if command -v dtwm >/dev/null 2>&1; then
    log "starting the CDE Front Panel (dtwm, contained)"
    # CDE_NO_WM_INFO: do not let the shim publish the synthetic _MOTIF_WM_INFO;
    # dtwm checks it to decide whether a window manager is already running.
    CDE_NO_WM_INFO=1 dtwm -xrm '*useFrontPanel: True' &
    # Apply the first workspace's backdrop: dtwm only runs the bridge on a
    # workspace *change*, so the initial backdrop is set here.
    if command -v cde-wsm-desk >/dev/null 2>&1; then
        cde-wsm-desk 0 &
    fi
else
    log "error: dtwm not found; run scripts/install-panel-data.sh"
fi

# Bring back the applications from the last session (recorded by
# cde-session-save.sh at logout; see config/cde-env.sh).  CDE_RESTORE=0 starts
# clean instead.
if [ "${CDE_RESTORE:-1}" = 1 ] && command -v cde-session-restore.sh >/dev/null 2>&1; then
    cde-session-restore.sh &
fi

# Optional startup hook: a command run once, in the background, after the panel
# is up and the ToolTalk session is available.  scripts/test-nested.sh points
# this at scripts/wsm-smoke.sh to exercise the Workspace Manager.
if [ -n "${CDE_STARTUP_HOOK:-}" ]; then
    if [ -x "$CDE_STARTUP_HOOK" ]; then
        log "running startup hook: $CDE_STARTUP_HOOK"
        "$CDE_STARTUP_HOOK" &
    else
        log "warning: CDE_STARTUP_HOOK is not executable: $CDE_STARTUP_HOOK"
    fi
fi

# The panel launches the rest; keep the session alive until logout.
wait
