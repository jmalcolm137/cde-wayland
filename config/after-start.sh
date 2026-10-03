#!/bin/sh
# after-start.sh — sourced/run by cow-start once CoW is up.
#
# CoW's start.sh looks for ~/.config/cow/after-start.sh and sources it.  We use
# it to bring up the CDE session now that the window manager exists.

set -eu

: "${CDE_PREFIX:=${HOME}/.local/cde-wayland}"
export CDE_PREFIX
export PATH="${CDE_PREFIX}/dt/bin:${CDE_PREFIX}/bin:${PATH}"

exec "${CDE_PREFIX}/share/cde-wayland/cde-session.sh"
