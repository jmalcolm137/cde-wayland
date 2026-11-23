#!/usr/bin/env bash
# test-nested.sh — start a nested CDE session and smoke-test the Workspace
# Manager, leaving the session up for inspection.
#
#   scripts/test-nested.sh          start + smoke-test (leaves it running)
#   scripts/test-nested.sh --stop   stop a session started this way
#
# It is a thin wrapper around run-session.sh --nested: it points the session's
# CDE_STARTUP_HOOK at scripts/wsm-smoke.sh, waits for that to report PASS/FAIL,
# and leaves the panel running.  Requires river and cow on PATH and an outer
# Wayland session for the nested compositor (see README.md).
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)/build/lib.sh"

LOG="${CDE_TEST_LOG:-/tmp/cde-wayland-test.log}"
SMOKE_LOG="${CDE_WSM_SMOKE_LOG:-/tmp/cde-wsm-smoke.log}"
NESTED_PID_FILE="${XDG_RUNTIME_DIR:-/tmp}/cde-wayland/nested.pid"

if [ "${1:-}" = "--stop" ]; then
    _npid="$(cat "$NESTED_PID_FILE" 2>/dev/null || true)"
    if [ -n "$_npid" ] && kill -0 "$_npid" 2>/dev/null; then
        # Kill the nested session's process group so an outer River/CoW session
        # on the host is never touched.
        kill -- -"$_npid" 2>/dev/null || kill "$_npid" 2>/dev/null || true
        rm -f "$NESTED_PID_FILE"
    else
        pkill -f '^/bin/sh .*/cde-palette-watch$' 2>/dev/null || true
        pkill -x dtsession 2>/dev/null || true
        pkill -x dtwm 2>/dev/null || true
        pkill -x cow 2>/dev/null || true
        pkill -x river 2>/dev/null || true
        pkill -x ttsession 2>/dev/null || true
        pkill -x tt-portmapper 2>/dev/null || true
    fi
    log "stopped the nested session"
    exit 0
fi

require_cmd river
command -v cow >/dev/null 2>&1 || die "cow not found; run build/build-cow.sh"

export CDE_STARTUP_HOOK="$PROJECT_ROOT/tests/wsm-smoke.sh"
export CDE_WSM_SMOKE_LOG="$SMOKE_LOG"
export CDE_NESTED=1

log "starting a nested session (session log: $LOG)"
rm -f "$SMOKE_LOG" "$LOG"
mkdir -p "$(dirname "$NESTED_PID_FILE")" 2>/dev/null || true
if command -v setsid >/dev/null 2>&1; then
    setsid "$PROJECT_ROOT/session/run-session.sh" --nested >>"$LOG" 2>&1 &
    printf '%s\n' "$!" >"$NESTED_PID_FILE"
else
    ( "$PROJECT_ROOT/session/run-session.sh" --nested >>"$LOG" 2>&1 & )
fi

# Wait for the smoke test to finish (it prints PASS/FAIL as its last line).
for _ in $(seq 1 90); do
    [ -f "$SMOKE_LOG" ] && grep -qE '^(PASS|FAIL)' "$SMOKE_LOG" && break
    sleep 1
done

if grep -q '^PASS' "$SMOKE_LOG" 2>/dev/null; then
    ok "Workspace Manager smoke test passed"
    sed 's/^/    /' "$SMOKE_LOG"
    log "nested session left running; stop it with: $0 --stop"
else
    warn "Workspace Manager smoke test did not pass"
    [ -f "$SMOKE_LOG" ] && sed 's/^/    /' "$SMOKE_LOG"
    die "session log: $LOG"
fi
