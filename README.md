# CDE on Wayland

[![CI](https://github.com/jmalcolm137/cde-wayland/actions/workflows/ci.yml/badge.svg)](https://github.com/jmalcolm137/cde-wayland/actions/workflows/ci.yml)

Run the **Common Desktop Environment** natively on Wayland:

* Motif applications speak Wayland through
  [xlib-wayland](https://github.com/jmalcolm137/xlib-wayland), a Wayland-native,
  ABI-compatible `libX11`. No X server, no Xwayland.
* Window management and decorations come from
  [CoW](https://codeberg.org/cow-wm/cow), a stacking WM running on the
  [River](https://codeberg.org/river/river) compositor (built unpatched).
* Everything else is stock [CDE](https://github.com/lkujaw/cde).

## Demo

![The CDE desktop on Wayland](docs/demo.gif)

The Workspace Menu starts the Terminal, `dtcalc` is launched from it, the File
Manager opens a text file on a double-click, and dragging `pic2.xpm` onto the
Front Panel's Icon Editor launches `dticon`.

## Quick Start

Fetch the pinned sources, build, and install everything under
`$HOME/.local/cde-wayland` (no root required):

```sh
git clone https://github.com/jmalcolm137/cde-wayland
cd cde-wayland
make
```

Start a session (needs a seat/DRM; normally from a TTY):

```sh
session/run-session.sh
```

Inside another Wayland session, run it nested and drive it with the smoke test:

```sh
tests/test-nested.sh          # start + smoke-test, leaves it running
tests/test-nested.sh --stop   # stop it
```

## Documentation

* [docs/DESIGN.md](docs/DESIGN.md) — architecture, in-process Xlib constraints,
  and component strategy
* [docs/WORKSPACE-MANAGER.md](docs/WORKSPACE-MANAGER.md) — Front Panel, CoW
  desks, backdrops, and `DtWsm` integration
* [docs/WAYLAND-ADVANTAGES.md](docs/WAYLAND-ADVANTAGES.md) — what improves over
  classic X11 CDE
* [patches/README.md](patches/README.md) — the CDE patch overlays and licensing

## Repository Layout

| Directory | Contents |
|---|---|
| `build/` | source fetch, build scripts, `imake` overlay (`cde-host.def.in`) |
| `session/` | session launcher (`run-session.sh`) and runtime `cde-*` helpers |
| `config/` | runtime CoW, River, Xresources, backdrop, and `.dt` configs |
| `tools/` | C helper programs (`tt-portmapper`, `xrdb`, `cde-wsm`, `cde-confirm`, `cde-palette-colours`) |
| `patches/` | minimal CDE source overlays (`LGPL-2.0-or-later`) |
| `tests/` | smoke tests, `.dt` database guard, and pin verification |
| `demo/` | demo recording scripts, virtual input helpers, and sample assets |
| `docs/` | architecture notes and demo media |

### Prerequisites

Arch package names; equivalents can be found on other distros.

* **Build tools** — `base-devel`, `git`, `meson`, `ninja`, `cmake`, `pkgconf`,
  `rsync`, `ksh`, `bison`, `flex`, `rpcsvc-proto` (for `rpcgen`).
* **Libraries** — `wayland`, `wayland-protocols`, `libxkbcommon`, `cairo`,
  `freetype2`, `fontconfig`, `pango`, `libxrender`, `libxcb`, `libxi`,
  `libxft`, `libpng`, `pixman`, `libbsd`, `libevent`, `libxml2`, `xorgproto`,
  `xbitmaps` (Motif needs the X bitmaps), `opensp`, `tcl` and `imagemagick`
  (help volumes and backdrop conversion).
* **Session** — `river` (the compositor; a distro package is preferred) and a
  Wayland session, or a real seat for the DRM backend.
* **Runtime** — `ibus` is optional; `waylock` is used by the Lock Screen
  actions.

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

## License

This repository's own work is **MIT** (see [LICENSE](LICENSE)).

The overlays under `patches/` are not: each one modifies another project and
carries that project's licence instead.

* The **CDE patches** modify [CDE](https://github.com/lkujaw/cde), which is
  released under the **LGPL-2.0-or-later**. CDE's `COPYING` requires that
  modifications to it be made available under the same terms, so those patches
  are licensed the same way and carry a change notice each.

See [`patches/README.md`](patches/README.md) for the full list.

No CDE source is redistributed here — the overlays are diffs, applied to
a pristine tree by `build-cde.sh` — so CDE's media clause (icons, images and
documentation under CC BY-SA 3.0, attribution "The Open Group") does not apply.
