#!/bin/sh
# wsm-smoke.sh — smoke-test the CDE Workspace Manager through cde-wsm.
#
# Run this *inside* a running CDE session: it needs the ToolTalk session (the
# Workspace Manager is dtwm) and the shim's synthetic workspace properties.
# scripts/test-nested.sh starts a nested session with CDE_STARTUP_HOOK pointing
# here; the panel's Terminal can also run it by hand.
#
# It waits for the Workspace Manager to answer, then lists, switches, adds and
# deletes a workspace, checking the workspace list after each step.  The last
# line of $CDE_WSM_SMOKE_LOG is PASS or FAIL, and the exit status agrees.
set -u

log="${CDE_WSM_SMOKE_LOG:-/tmp/cde-wsm-smoke.log}"
wsm="${CDE_PREFIX:-/usr}/bin/cde-wsm"
[ -x "$wsm" ] || wsm=cde-wsm

: > "$log"
say() { printf '%s\n' "$*" >>"$log"; }
fail=0

count()   { "$wsm" list 2>>"$log" | grep -c '^'; }
current() { "$wsm" list 2>>"$log" | sed -n 's/.*[[:space:]]\([^ ]*\)[[:space:]]\*$/\1/p'; }

# Wait for the Workspace Manager (dtwm) to be ready.
i=0
while [ "$i" -lt 30 ]; do
    "$wsm" list >/dev/null 2>&1 && break
    i=$((i + 1))
    sleep 1
done
if ! "$wsm" list >/dev/null 2>&1; then
    say "FAIL: the Workspace Manager did not answer (is dtwm running?)"
    exit 1
fi

n0=$(count)
c0=$(current)
say "initial: n=$n0 current=$c0"

"$wsm" next >>"$log" 2>&1 || { say "FAIL: cde-wsm next"; fail=1; }
sleep 1
c1=$(current)
say "after next: current=$c1"
[ "$c1" != "$c0" ] || { say "FAIL: next did not change the current workspace"; fail=1; }

"$wsm" add "Smoke" >>"$log" 2>&1 || { say "FAIL: cde-wsm add"; fail=1; }
sleep 1
n1=$(count)
say "after add: n=$n1"
[ "$n1" -eq "$((n0 + 1))" ] || { say "FAIL: add did not grow the workspace list"; fail=1; }

# The added workspace is appended, so it is index n0.
"$wsm" delete "$n0" >>"$log" 2>&1 || { say "FAIL: cde-wsm delete"; fail=1; }
sleep 1
n2=$(count)
say "after delete: n=$n2"
[ "$n2" -eq "$n0" ] || { say "FAIL: delete did not restore the workspace list"; fail=1; }

if [ "$fail" -eq 0 ]; then
    say "PASS"
else
    say "FAIL"
fi
exit "$fail"
