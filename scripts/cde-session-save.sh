#!/usr/bin/env bash
# cde-session-save.sh — record the CDE session's running applications.
#
# There is no shared X server, so the X session protocol (XSMP over ICE) cannot
# see the other clients: each application is its own X server and its own
# Wayland client.  Instead the session is captured on the Wayland/Linux side:
# every application launched by the session inherits CDE_SESSION_DIR (set in
# cde-env.sh), so the running applications are exactly the processes carrying
# that marker.  Their command line and working directory are what a session
# manager needs to bring them back.
#
# The result is written to $CDE_SESSION_DIR/session, one client per line:
#
#     <cwd> TAB <shell-quoted argv...>
#
# cde-session.sh replays it on the next start (cde-session-restore.sh).
set -euo pipefail

log() { printf "cde-session: %s\n" "$*" >&2; }

: "${CDE_SESSION_DIR:=${XDG_STATE_HOME:-$HOME/.local/state}/cde-wayland/sessions/current}"
: "${CDE_SESSION_TAG:=cde-wayland-session}"
dir="$CDE_SESSION_DIR"
file="$dir/session"
mkdir -p "$dir"

# Infrastructure that carries the marker but is not a session client.
is_infra() {
    case "$1" in
        river|cow|dtwm|dtsession|ttsession|tt-portmapper|rpc.cmsd|dsdm|moocow) return 0 ;;
        ibus-daemon|ibus-dconf|ibus-extension-gtk3|ibus-wayland|ibus-engine-simple) return 0 ;;
        dbus-daemon|dbus-launch|dbus-run-session|xembedsniproxy) return 0 ;;
        cde-session.sh|cde-session-save.sh|cde-session-restore.sh|cde-logout.sh) return 0 ;;
        cde-wsm|cde-wsm-desk|cde-wsm-backdrop|cde-motif-apply|cde-panel) return 0 ;;
        # The palette watcher polls with sleep, and both would otherwise be
        # recorded as session clients (it lives in the session's process tree,
        # so it inherits the marker like any other application).
        cde-palette-watch|sleep) return 0 ;;
        bash|sh|env) return 0 ;;
        *) return 1 ;;
    esac
}

tmp="$(mktemp "${TMPDIR:-/tmp}/cde-session.XXXXXX")"
trap 'rm -f "$tmp"' EXIT

count=0
for envf in /proc/[0-9]*/environ; do
    pid="${envf#/proc/}"; pid="${pid%/environ}"
    # Only processes that belong to this session.  grep opens the file itself,
    # so another user's /proc entry fails quietly instead of the shell reporting
    # the redirection error.
    grep -zqx "CDE_SESSION_TAG=$CDE_SESSION_TAG" "$envf" 2>/dev/null || continue
    # Command line and cwd of the client.
    cmdline="$(tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null || true)"
    [ -n "$cmdline" ] || continue
    cwd="$(readlink "/proc/$pid/cwd" 2>/dev/null || echo "$HOME")"
    # argv[0] base name, for the infrastructure filter.
    argv0="${cmdline%% *}"
    is_infra "$(basename "$argv0")" && continue

    # Shell-quote argv so the replay re-execs exactly what ran.
    mapfile -d '' -t argv <"/proc/$pid/cmdline" 2>/dev/null || continue
    [ "${#argv[@]}" -gt 0 ] || continue
    quoted=""
    for a in "${argv[@]}"; do quoted+="$(printf '%q ' "$a")"; done
    printf '%s\t%s\n' "$cwd" "${quoted% }" >>"$tmp"
    count=$((count + 1))
done

# De-duplicate (two processes with the same command in the same directory are
# the same restored client) and write atomically.
sort -u "$tmp" >"$file"
printf 'cde-session-save: %d running client(s) saved to %s\n' "$count" "$file" >&2
cat "$file" >&2
