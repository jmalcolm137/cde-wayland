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

**M0 — harness.** The repository, source fetch, build scripts and design are in
place; the CDE build is being brought up. See [DESIGN.md §9](DESIGN.md#9-milestones).

| M | Scope | State |
|---|---|---|
| M0 | repo + fetch + shim + CoW/River build | 🚧 in progress |
| M1 | CDE `include/` + `lib/` build unmodified | 🚧 imake + Makefiles + headers done; libraries building |
| M2 | first CDE app (`dtcalc`/`dtpad`) under headless compositor | ⬜ |
| M3 | core desktop apps (dtterm, dtfile, dtstyle, …) | ⬜ |
| M4 | real River+CoW session | ⬜ |
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
```

Everything installs relocatably under `$CDE_PREFIX`
(default `$HOME/.local/cde-wayland`), so no root is required. The shim and the
Xt/Motif stack install into the same prefix, and CDE installs under
`$CDE_PREFIX/dt`.

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
