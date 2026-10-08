#!/bin/sh
# cde-appmgr — open the CDE Application Manager.
#
# CDE's Dtappmgr action is a ToolTalk request that asks the File Manager to show
# /var/dt/appconfig/appmanager/$DTUSERSESSION, which an unprivileged session
# cannot create (and would share between users).  dtappgather collects the
# application groups into TARGET_APPMAN_DIR instead — see config/cde-env.sh —
# so open that, gathering it first if it is not there yet.
#
# The Front Panel's Applications control runs this (config/dtwm-types/
# zz-appmgr.dt), and scripts/cde-wsm-desk.sh/desktop call it too.
set -u

here="$(cd -- "$(dirname -- "$0")" && pwd -P)"
if [ -z "${CDE_ROOT:-}" ]; then
    # Installed under $CDE_ROOT/bin, so the root is one level up.
    CDE_ROOT="$(cd -- "$here/.." && pwd -P)"
fi

dir="${TARGET_APPMAN_DIR:-$CDE_ROOT/appconfig/appmanager/gathered}"

if [ ! -d "$dir" ] && command -v dtappgather >/dev/null 2>&1; then
    DTAPPSEARCHPATH="${DTAPPSEARCHPATH:-$CDE_ROOT/appconfig/appmanager/C}" \
    TARGET_APPMAN_DIR="$dir" \
        dtappgather -r >/dev/null 2>&1 || true
fi

exec dtfile -title "Application Manager" -dir "$dir"
