# What can this do that X11 CDE cannot?

**Status:** current behaviour
**Scope:** what this Wayland session can do that a classic X11 CDE session
cannot (without Xwayland in the loop). For the work that remains, see the
"What's left" section of the [README](../README.md).

---

Here's what the Wayland version can do that a classic X11 CDE session cannot.
This is deliberately stock CDE on a Wayland-native `libX11` shim, so most of
what is new is integration and environment rather than extra CDE widgets.

## Run in a Wayland session — no X server, no Xwayland

`xlib-wayland` gives each CDE binary a native Wayland connection
(`wl_surface`/`xdg_toplevel` per top-level X window). Concretely:

* CDE runs **inside any Wayland compositor**, including nested in a modern
  desktop (verified inside KWin) and under a bundled headless compositor for
  automated tests (`scripts/run-app.sh`, `scripts/test-nested.sh`).
* The CDE desktop and native Wayland applications are **peers on River**, not a
  separate X island.

## Exchange data with native Wayland applications

On a pure X11 CDE desktop, CDE applications can only exchange data with other
X11 clients. Here the shim bridges across the boundary: **clipboard/PRIMARY and
drag-and-drop work in both directions**, including Motif DnD to Wayland drops
and Wayland drags onto Motif drop sites (see *Drag and drop* in the
[README](../README.md); `DESIGN.md` §3.2; `XLIB_WAYLAND_SHARE_SELECTIONS` in
`config/cde-env.sh`). The shim also carries non-text clipboards. X11 CDE cannot
do this without Xwayland in the loop.

## Use the compositor's input-method stack

XIM in the shim is a real bridge to the compositor's `zwp_text_input_v3`, and
`ibus-wayland` registers as an `input-method-v2` server (`config/river-init`).
CDE's Motif text widgets therefore compose accented and CJK text through the
**compositor's IME stack** rather than a legacy standalone XIM server
(`versions.lock`, `cec9604`).

## Keep clients isolated

Every process is its own in-process X server, so CDE applications **cannot**
snoop each other's windows, properties or keystrokes, synthesize
`XSendEvent`s, or grab keys globally across applications. That is a security
property a shared X server cannot provide; it is also why XSMP and DnD needed
explicit bridges (`DESIGN.md` §3).

## Install and run rootless

* Everything installs under `$CDE_PREFIX` (default `~/.local/cde-wayland`): **no
  `/usr/dt`, no root**.
* The session runs in an **unprivileged user+network namespace with its own
  `tt-portmapper`**, so ToolTalk works with **no system `rpcbind`** and no
  privileged ports, and the Calendar daemon uses a private spool
  (`run-session.sh`, `rpccmsd-nonroot.patch`, `tools/tt-portmapper.c`).
* A complete CDE desktop can therefore run as an ordinary user, side by side
  with other sessions.

## Delegate window management to the compositor

CoW gives CDE windows Wayland-era management that is configured, not coded:
top-layer docking for the Front Panel and its sub-panels, a reserved work area,
click-to-focus, transient-aware stacking, server-side decorations, desks as
workspaces, and locking through `waylock`/`ext-session-lock`
(`config/cow.conf`, `docs/WORKSPACE-MANAGER.md`). Most of this is parity with
MWM, expressed as compositor configuration.
