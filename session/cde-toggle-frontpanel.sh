#!/bin/sh
# cde-toggle-frontpanel — minimize/restore the CDE Front Panel.
#
# The root menu's "Minimize/Restore Front Panel" (CDE's f.toggle_frontpanel).
# CoW cannot select the panel with `-t %FrontPanel` (a sticky, circulate-skip
# top-layer window is not in the target search), so find its window id first and
# iconify/de-iconify it by id (which toggles).
set -u

id=$(moocow show -a window 2>/dev/null | python3 -c '
import sys, json
try:
    data = json.load(sys.stdin)["data"]
except Exception:
    sys.exit(0)
for w in data:
    if w.get("app_id") == "FrontPanel":
        print(w["id"])
        break')

[ -n "$id" ] || exit 0
moocow winops -t "#$id" -i >/dev/null 2>&1
