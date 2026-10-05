#!/usr/bin/env bash
# cde-session-restore.sh — bring back the applications recorded by
# cde-session-save.sh (see that script for why the session is captured this
# way).  Each line is <cwd> TAB <shell-quoted argv...>; the client is re-exec'd
# in that directory with the session's environment.
set -u

log() { printf "cde-session: %s\n" "$*" >&2; }

: "${CDE_SESSION_DIR:=${XDG_STATE_HOME:-$HOME/.local/state}/cde-wayland/sessions/current}"
file="$CDE_SESSION_DIR/session"

if [ ! -s "$file" ]; then
    log "no saved session to restore ($file)"
    exit 0
fi

n=0
while IFS=$'\t' read -r cwd argv || [ -n "${argv:-}" ]; do
    [ -n "${argv:-}" ] || continue
    # Skip a client whose program no longer exists.
    prog="${argv%% *}"
    prog="$(eval "printf '%s' $prog" 2>/dev/null || true)"
    [ -x "$prog" ] || continue
    ( cd "$cwd" 2>/dev/null || cd "$HOME"; eval "exec $argv" ) >/dev/null 2>&1 &
    n=$((n + 1))
done <"$file"

log "restored $n application(s) from $file"
