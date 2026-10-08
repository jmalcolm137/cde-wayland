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
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib.sh"

LOG="${CDE_TEST_LOG:-/tmp/cde-wayland-test.log}"
SMOKE_LOG="${CDE_WSM_SMOKE_LOG:-/tmp/cde-wsm-smoke.log}"

if [ "${1:-}" = "--stop" ]; then
    pkill -f '^/bin/sh .*/cde-palette-watch$' 2>/dev/null || true
    pkill -x dtsession 2>/dev/null || true
    pkill -x dtwm 2>/dev/null || true
    pkill -x cow 2>/dev/null || true
    pkill -x river 2>/dev/null || true
    pkill -x ttsession 2>/dev/null || true
    pkill -x tt-portmapper 2>/dev/null || true
    log "stopped the nested session"
    exit 0
fi

require_cmd river
command -v cow >/dev/null 2>&1 || die "cow not found; run scripts/build-cow.sh"

export CDE_STARTUP_HOOK="$PROJECT_ROOT/scripts/wsm-smoke.sh"
export CDE_WSM_SMOKE_LOG="$SMOKE_LOG"
export CDE_NESTED=1

log "starting a nested session (session log: $LOG)"
rm -f "$SMOKE_LOG" "$LOG"
( "$PROJECT_ROOT/scripts/run-session.sh" --nested >>"$LOG" 2>&1 & )

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
