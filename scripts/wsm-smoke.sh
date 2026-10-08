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

# A CDE client's own rendering.  The File Manager draws its icons through a
# clip mask, so a clip/damage regression in the shim leaves its body blank while
# every other check still passes -- xlib-wayland 5e5c051 ("implement clip
# masks") did exactly that, and it then also broke double-click because the
# stalled repaint outran DtIconGadget's multi-click timer.  Open a File Manager
# on a directory with entries and check its body actually paints.
if command -v moocow >/dev/null 2>&1 && command -v grim >/dev/null 2>&1 \
   && command -v python3 >/dev/null 2>&1; then
    _d=$(mktemp -d)
    : >"$_d/one" ; : >"$_d/two" ; : >"$_d/three"
    moocow exec /bin/sh -c "cd '$_d' && dtfile" >>"$log" 2>&1
    sleep 4
    # A resize forces a full expose; the 5e5c051 regression left the icons
    # unpainted after one, so paint the window and then look at it.
    _id=$(moocow show -a window 2>/dev/null | python3 -c '
import json,sys
for w in json.load(sys.stdin)["data"]:
    if w["app_id"].startswith("File Manager"):
        print(w["id"]); break' 2>/dev/null)
    if [ -n "$_id" ]; then
        moocow focus -i "$_id" >/dev/null 2>&1
        moocow window-resize -w 600 -h 400 >/dev/null 2>&1
        sleep 2
    fi
    _shot=$(mktemp --suffix=.png)
    grim -t png "$_shot" >/dev/null 2>&1
    _n=$(python3 - "$_shot" 2>>"$log" <<'PY'
import json, subprocess, sys
try:
    from PIL import Image
except Exception:
    print(-1); raise SystemExit
try:
    im = Image.open(sys.argv[1]).convert("RGB")
    out = subprocess.run(["moocow", "show", "-a", "window"],
                         capture_output=True, text=True).stdout
    for w in json.loads(out)["data"]:
        if w["app_id"].startswith("File Manager"):
            x, y, ww, hh = w["x"], w["y"], w["width"], w["height"]
            body = im.crop((x + 8, y + 60, x + ww - 8, y + hh - 30))
            cols = body.getcolors(maxcolors=1 << 20) or []
            print(sum(n for n, _ in cols) and len(cols))
            break
    else:
        print(-1)
except Exception as e:
    print(-1)
PY
)
    rm -f "$_shot"; rm -rf "$_d"
    case "$_n" in
        ''|*[!0-9]*) _n=-1 ;;
    esac
    if [ "$_n" = -1 ]; then
        say "render: skipped (no File Manager window or no Pillow)"
    elif [ "$_n" -lt 4 ]; then
        say "render: FAIL: the File Manager body is blank ($_n colours); a shim clip/damage regression?"
        fail=1
    else
        say "render: the File Manager body paints ($_n colours)"
    fi
else
    say "render: skipped (moocow/grim/python3 not available)"
fi

# A File Manager double-click must open the folder under the pointer.  This is
# the functional counterpart of the render check above: when a shim rendering
# regression stalls the repaint, it outruns DtIconGadget's multi-click timer and
# the double-click is delivered as a plain select, so nothing opens
# (xlib-wayland 5e5c051).  The input helpers are built by build-demo-input.sh.
if command -v vmouse >/dev/null 2>&1 && command -v grim >/dev/null 2>&1 \
   && command -v moocow >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
    moocow exec dtfile >>"$log" 2>&1
    sleep 4
    _id=$(moocow show -a window 2>/dev/null | python3 -c '
import json,sys
for w in json.load(sys.stdin)["data"]:
    if w["app_id"].startswith("File Manager"):
        print(w["id"]); break' 2>/dev/null)
    if [ -n "$_id" ]; then
        moocow focus -i "$_id" >/dev/null 2>&1; sleep 0.3
        moocow window-move -x 8 -y 324 >/dev/null 2>&1
        moocow window-resize -w 620 -h 306 >/dev/null 2>&1; sleep 2
        _f=$(mktemp --suffix=.png); _g=$(mktemp --suffix=.png)
        grim -t png "$_f" >/dev/null 2>&1
        # ".. (go up)" is the first icon; the first entry is the next one.
        vmouse dclick 163 488 >>"$log" 2>&1
        sleep 2
        grim -t png "$_g" >/dev/null 2>&1
        _diff=$(python3 - "$_f" "$_g" "$_id" 2>>"$log" <<'PY'
import json, subprocess, sys
try:
    from PIL import Image, ImageChops
except Exception:
    print(-1); raise SystemExit
a = Image.open(sys.argv[1]).convert("RGB")
b = Image.open(sys.argv[2]).convert("RGB")
out = subprocess.run(["moocow", "show", "-a", "window"],
                     capture_output=True, text=True).stdout
for w in json.loads(out)["data"]:
    if w["id"] == sys.argv[3]:
        x, y, ww, hh = w["x"], w["y"], w["width"], w["height"]
        box = (x + 8, y + 60, x + ww - 8, y + hh - 30)
        print(1 if ImageChops.difference(a.crop(box), b.crop(box)).getbbox() else 0)
        break
else:
    print(-1)
PY
)
        rm -f "$_f" "$_g"
        case "$_diff" in ''|*[!0-9-]*) _diff=-1 ;; esac
        if [ "$_diff" = 1 ]; then
            say "double-click: the File Manager opened the entry"
        elif [ "$_diff" = 0 ]; then
            say "double-click: FAIL: the view did not change"
            fail=1
        else
            say "double-click: skipped (no window or no Pillow)"
        fi
    else
        say "double-click: skipped (no File Manager window)"
    fi
else
    say "double-click: skipped (vmouse/grim/moocow/python3 not available)"
fi

if [ "$fail" -eq 0 ]; then
    say "PASS"
else
    say "FAIL"
fi
exit "$fail"
