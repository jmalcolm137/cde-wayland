#!/usr/bin/env bash
# demo-steps.sh — storyboard for scripts/demo-record.sh.
#
# Sourced by demo-record.sh, which exports $BIN (the prefix's bin dir).  Drives
# the nested CDE session with the input helpers built by build-demo-input.sh.
# Coordinates are for the 1280x720 output.
#
#   Workspace menu -> Terminal -> dtcalc -> File Manager -> open a text file by
#   double-click -> drag an icon onto the Front Panel's Icon Editor.
#
# Not executable on its own; it needs the session and $BIN.

B="$BIN"
M="$B/moocow"

# --- the desktop -----------------------------------------------------------
sleep 2

# --- 1. the workspace (root) menu ------------------------------------------
# A right-click on the root window opens CDE's Workspace Menu.  "Terminal" is
# the tenth item; for a menu opened at y=300 that is y=515.
"$B/vmouse" rclick 700 300
sleep 2.0

# --- 2. Terminal -----------------------------------------------------------
"$B/vmouse" click 700 515
sleep 3.5
"$M" focus -t '%dtterm' >/dev/null 2>&1 || true
"$M" window-move -x 8 -y 350 >/dev/null 2>&1
"$M" window-resize -w 555 -h 285 >/dev/null 2>&1
sleep 1.2

# --- 3. dtcalc, launched from the terminal ---------------------------------
"$B/vmouse" click 280 420
sleep 0.6
"$B/vkey" 'dtcalc &\n'
sleep 5
"$M" focus -t '%dtcalc' >/dev/null 2>&1 || true
"$M" window-move -x 958 -y 25 >/dev/null 2>&1   # move only; dtcalc keeps its size
sleep 1.5

# --- 4. File Manager -------------------------------------------------------
"$M" exec dtfile -dir "$DEMO_DIR" >/dev/null 2>&1
sleep 5
"$M" focus -t '%File Manager - demo' >/dev/null 2>&1 || true
"$M" window-move -x 8 -y 25 >/dev/null 2>&1
"$M" window-resize -w 555 -h 300 >/dev/null 2>&1
sleep 1.5

# --- 5. open the text file by double-click ---------------------------------
# testfile.txt is the third icon in the view.
"$B/vmouse" dclick 399 177
sleep 4.5
"$M" focus -t '%Text Editor - testfile.txt' >/dev/null 2>&1 || true
"$M" window-move -x 560 -y 120 >/dev/null 2>&1
"$M" window-resize -w 610 -h 420 >/dev/null 2>&1
sleep 1.5

# --- 6. drag pic2.xpm onto the Front Panel's Icon Editor -------------------
# The up-arrow above the leftmost personal-applications control opens the
# sub-panel; its "Icon Editor" control opens dticon when a file is dropped on
# it.  pic2.xpm is the second icon in the File Manager's view.
"$B/vmouse" click 375 648
sleep 1.5
"$B/vmouse" drag 158 178 415 618 30
sleep 5
"$M" focus -t '%dticon' >/dev/null 2>&1 || true
"$M" window-move -x 8 -y 25 >/dev/null 2>&1
sleep 1.5
