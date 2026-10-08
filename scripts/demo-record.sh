#!/usr/bin/env bash
#
# demo-record.sh — record the nested session's output (the CoW desktop) to an
# animated GIF (and an MP4) for documentation.
#
# The nested session's compositor output *is* the CoW window contents, so this
# captures that output directly with grim; no outer-window cropping is needed.
#
# Usage:
#   scripts/demo-record.sh --out demo.gif [--fps 8] [--scale 960] [--steps steps.sh]
#
# The steps file is a shell script executed while the capture runs.  Use the
# helpers below to drive the desktop:
#
#   sleep 1                       # hold a beat (also used by the capturer)
#   act click X Y                 # pointer click        (vclick)
#   act dclick X Y                # double click         (vdclick)
#   act drag X1 Y1 X2 Y2          # slow drag            (vdrag)  <- Motif DnD
#   act move X Y                  # move the pointer     (vmove)
#   act type 'text\n'             # type text            (vkey)
#   act focus '%app_id'           # focus a window       (moocow focus)
#   act place '%app_id' X Y W H   # move+resize a window (moocow window-move/window-resize)
#   act shell 'cd /dir && dtfile' # start a client in the session (moocow exec)
#   act menu_terminal             # Workspace Menu -> Terminal
#   act menu_files                # Workspace Menu -> Files
#
# ($BIN and the low-level tools are exported too, so a steps file can drive
# the session directly, e.g. "$BIN/vmouse drag ...".)
#
# Input injection needs the wlroots virtual pointer / keyboard protocols; the
# tools are built by scripts/build-demo-input.sh into $CDE_PREFIX/bin.
#
# Env: CDE_PREFIX (default ~/.local/motif-wayland), WAYLAND_DISPLAY (the
# session's compositor socket, e.g. wayland-1).
set -eu

CDE_PREFIX="${CDE_PREFIX:-$HOME/.local/motif-wayland}"
WAYLAND_DISPLAY="${WAYLAND_DISPLAY:?set WAYLAND_DISPLAY to the session compositor (e.g. wayland-1)}"
export WAYLAND_DISPLAY
BIN="$CDE_PREFIX/bin"

out=demo.gif
fps=8
scale=960
steps=""
region=""
while [ $# -gt 0 ]; do
    case "$1" in
        --out)   out="$2";   shift 2;;
        --fps)   fps="$2";   shift 2;;
        --scale) scale="$2"; shift 2;;
        --steps) steps="$2"; shift 2;;
        --region) region="$2"; shift 2;;
        -h|--help) sed -n '2,40p' "$0"; exit 0;;
        *) echo "demo-record: unknown option $1" >&2; exit 2;;
    esac
done

frames="$(mktemp -d "${TMPDIR:-/tmp}/cde-demo.XXXXXX")"
grab_pid=""
cleanup() { [ -n "$grab_pid" ] && kill "$grab_pid" 2>/dev/null || true; }
trap cleanup EXIT

# ---- capture loop --------------------------------------------------------
delay=$(awk -v f="$fps" 'BEGIN{printf "%.3f", 1/f}')
(
    n=0
    while :; do
        f=$(printf '%s/%06d.png' "$frames" "$n")
        # -c makes grim draw the pointer into the frame.  Without it the mouse
        # is invisible: it is a compositor cursor, not part of the scene, and a
        # drag then looks like the icons move by themselves.
        grim -c ${region:+-g "$region"} -t png "$f" 2>/dev/null || true
        n=$((n + 1))
        sleep "$delay"
    done
) &
grab_pid=$!

# ---- helpers the steps file can call ------------------------------------
function act() {
    case "$1" in
        click)  shift; "$BIN/vclick" "$@";;
        dclick) shift; "$BIN/vdclick" "$@";;
        drag)   shift; "$BIN/vdrag" "$@";;
        move)   shift; "$BIN/vmove" "$@";;
        type)   shift; "$BIN/vkey" "$@";;
        focus)  shift; "$BIN/moocow" focus -t "$1";;
        place)  shift; a="$1"; x="$2"; y="$3"; w="$4"; h="$5"
                "$BIN/moocow" focus -t "$a"; sleep 0.2
                "$BIN/moocow" window-move -x "$x" -y "$y"
                "$BIN/moocow" window-resize -w "$w" -h "$h";;
        shell)  shift; "$BIN/moocow" exec /bin/sh -c "$1";;
        menu_terminal) "$BIN/vclick" 1000 300; sleep 0.8; "$BIN/vclick" 1000 515;;
        menu_files)    "$BIN/vclick" 1000 300; sleep 0.8; "$BIN/vclick" 1000 539;;
        *) echo "demo-record: unknown act $1" >&2;;
    esac
}
export -f act
export BIN

# ---- run the steps -------------------------------------------------------
t0=$(date +%s.%N)
if [ -n "$steps" ]; then
    # shellcheck disable=SC1090
    . "$steps"
fi

sleep 0.3
cleanup
grab_pid=""
t1=$(date +%s.%N)

# ---- assemble ------------------------------------------------------------
# grim and the PNG encoder take longer than the requested interval, so the
# capture runs slower than --fps; playing the frames back at --fps would speed
# the demo up.  Derive the real rate from the frames actually captured and the
# wall-clock time the steps took.
n_frames=$(ls "$frames" | wc -l)
eff_fps=$(awk -v n="$n_frames" -v a="$t0" -v b="$t1" \
    'BEGIN { d = b - a; if (d <= 0) d = 1; f = n / d; if (f < 1) f = 1; printf "%.4f", f }')
echo "captured $n_frames frames in $(awk -v a="$t0" -v b="$t1" 'BEGIN{printf "%.1f", b-a}')s -> ${eff_fps} fps"
scale_filter="scale=${scale}:-1:flags=lanczos"

ffmpeg -y -loglevel error -framerate "$eff_fps" -i "$frames/%06d.png" \
    -vf "$scale_filter" -c:v libx264 -pix_fmt yuv420p -crf 20 -movflags +faststart \
    "${out%.*}.mp4"

# GIF via a generated palette (much better than ffmpeg's default for UI art)
pal="$(mktemp --suffix=.png)"
ffmpeg -y -loglevel error -framerate "$eff_fps" -i "$frames/%06d.png" \
    -vf "$scale_filter,palettegen=stats_mode=diff" "$pal"
ffmpeg -y -loglevel error -framerate "$eff_fps" -i "$frames/%06d.png" -i "$pal" \
    -lavfi "$scale_filter[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=3:diff_mode=rectangle" \
    -loop 0 "$out"
rm -f "$pal"

echo "wrote $out and ${out%.*}.mp4"
echo "frames kept in $frames (remove when done)"
