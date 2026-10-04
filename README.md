# CDE on Wayland

Run the **Common Desktop Environment** natively on Wayland:

* Motif applications speak Wayland through
  [xlib-wayland](../xlib-wayland) — a Wayland-native, ABI-compatible `libX11`.
  No X server, no Xwayland.
* Window management and decorations come from
  [CoW](https://codeberg.org/cow-wm/cow), a stacking WM running on the
  [River](https://codeberg.org/river/river) compositor.
* Everything else is stock [CDE](https://github.com/lkujaw/cde).

See [DESIGN.md](DESIGN.md) for the architecture, the constraints of an
in-process Xlib, the CDE component strategy, and the milestone plan.

## Where changes live

`xlib-wayland` is a **separate upstream project** and is where every shim
accommodation for CDE belongs. This repository only:

* orchestrates building the stack,
* carries the CDE-specific **build configuration** (`config/cde-host.def.in`,
  i.e. imake's `host.def`),
* carries the session/window-manager configuration (CoW/River) and the session
  script.

We consume `xlib-wayland` from
<https://github.com/jmalcolm137/xlib-wayland>; fix and extend it there, then
push here the version bump in `versions.lock`. Do not fork or patch the shim
from this tree.

## Status

**A CDE desktop on Wayland.** River (compositor) + CoW (window manager) + the
**real CDE Front Panel** (`dtwm`, contained) + real CDE applications
(`dtterm`, `dtfile`, `dtpad`, `dtcalc`, `dtstyle`), all as native Wayland
clients — verified running nested inside a KWin session. CoW manages the CDE
windows (decorations, stacking) while the Front Panel launches them. See
[DESIGN.md §5.2 and §9](DESIGN.md#9-milestones).

**Current work:** the CDE Workspace Manager — making the panel's workspace
switch live, serving the `DtWsm` protocol to applications, and adding CDE's
workspace/desktop/titlebar menus. Plan and protocol notes:
[docs/WORKSPACE-MANAGER.md](docs/WORKSPACE-MANAGER.md).

The Style Manager (`dtstyle`) is wired to the session as well: its Backdrop
module sets the CoW desktop background per workspace, and its Keyboard module's
Auto Repeat toggle is shared with every client (the shim gates the key repeat it
synthesises on it).

| M | Scope | State |
|---|---|---|
| M0 | repo + fetch + shim + CoW/River build | ✅ shim + Xt/Motif + CoW build (River: install distro package) |
| M1 | CDE `include/` + `lib/` build unmodified | ✅ **done** — all `libDt*`/`tt`/`csa` link against the shim |
| M2 | first CDE app (`dtcalc`/`dtpad`) under headless compositor | ✅ **done** — `dtcalc` renders in CDE colours on the shim |
| M3 | core desktop apps (dtterm, dtfile, dtstyle, …) | 🚧 dtcalc, dtterm, dtpad, dtfile, dtstyle build and run |
| M4 | real River+CoW session with the CDE Front Panel | 🚧 real `dtwm` panel renders under the shim; CoW/session config written |
| M5 | CoW panel/theme, backdrops, resources | ⬜ |
| M6 | cross-process broker (DnD, XSMP) | ⬜ |

## Quick start

```sh
# 1. get the sources (CDE, CoW, River; imake if missing)
scripts/fetch-sources.sh

# 2. build the Wayland libX11 shim + libXt + Open Motif
scripts/build-shim.sh

# 3. build CoW (and River, if requested)
scripts/build-cow.sh

# 4. build CDE against the prefix
scripts/build-cde.sh

# 5. build + install the real CDE Front Panel (dtwm) and its data
scripts/build-cde.sh panel
```

Everything installs relocatably under `$CDE_PREFIX`
(default `$HOME/.local/cde-wayland`), so no root is required. The shim and the
Xt/Motif stack install into the same prefix, and CDE installs under
`$CDE_PREFIX/dt`.

## The CDE Front Panel

CDE's Front Panel is compiled into `dtwm`; there is no standalone panel binary.
We run the **real, unmodified `dtwm`** as a *contained panel*: because the shim
gives each process a private X server, dtwm can only ever see and manage its own
windows, so its window-manager role is inert and cannot touch the CDE apps
(separate processes) that CoW manages. `scripts/build-cde.sh panel` builds it,
its front-panel database and icons, and CDE's `ttsession`.

Real CDE's ToolTalk needs a running portmapper, so start it once:

```sh
sudo systemctl start rpcbind
```

Then a session is `scripts/run-session.sh` (River + CoW + the panel).

Run one application against the bundled headless compositor:

```sh
scripts/run-app.sh dtcalc
```

Start a real session (needs a seat/DRM; normally from a TTY):

```sh
scripts/run-session.sh
```

## Environment

| Variable | Default | Meaning |
|---|---|---|
| `CDE_PREFIX` | `$HOME/.local/cde-wayland` | install prefix (shim, Motif, CDE) |
| `XLIB_WAYLAND` | sibling `../xlib-wayland`, else cache | the shim checkout |
| `XLIB_WAYLAND_REPO` | `github.com/jmalcolm137/xlib-wayland` | shim upstream |
| `XLIB_WAYLAND_REF` | `main` | shim revision |
| `CDE_CACHE` | `$HOME/.cache/cde-wayland` | downloaded/cloned sources |
| `CDE_SRC` | `$CDE_CACHE/src/cde` | pristine CDE source tree |
| `CDE_BUILD` | `$CDE_PREFIX/build/cde` | CDE out-of-tree build copy |
| `COW_SRC` / `RIVER_SRC` | `$CDE_CACHE/src/cow` / `.../river` | WM + compositor sources |
| `JOBS` | `nproc` | parallel build jobs |
