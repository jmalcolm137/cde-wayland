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

**A working CDE desktop on Wayland.** River (compositor) + CoW (window manager)
+ the **real CDE Front Panel** (`dtwm`, contained) + real CDE applications, all
as native Wayland clients — verified nested inside a KWin session, and able to
run on a real seat. CoW manages the CDE windows (decorations, stacking, icon
box) while the Front Panel launches them.

What runs today:

* **Front Panel** — the real `dtwm` as a contained panel, docked flush to the
  bottom of the screen, with its sub-panels docking on its top edge.
* **Applications** — `dtterm`, `dtfile` (File Manager), `dtpad`, `dtcalc`,
  `dtstyle`, `dtcm`, `dtprintinfo`, `dticon`, `dthelpview`/`dthelp`, `dtinfo`.
* **Workspace Manager** — the panel's One/Two/Three/Four buttons drive CoW's
  desks, the `DtWsm` protocol is served to applications, and CDE's workspace and
  titlebar menus are provided as CoW menus. Plan and protocol notes:
  [docs/WORKSPACE-MANAGER.md](docs/WORKSPACE-MANAGER.md).
* **Style Manager** — Backdrop (per workspace), Keyboard (auto-repeat, shared
  with every client), Font, Startup and Color modules are wired to the session.
* **Application Manager** — `dtappgather` gathers CDE's application groups
  (Desktop_Apps, Desktop_Tools, Information, System_Admin, ...) and their
  entries show as action icons, so a File Manager double-click works.
* **Desktop** — per-workspace CDE backdrops (the Sun logo on workspace 0, then
  WaterDrops / RicePaper / Pebbles) and MWM-style cascading placement.
* **Drag and drop** — Motif DnD is bridged through the compositor's drag and the
  cross-process selection broker: a file icon dragged from the File Manager into
  an application (`dtpad`, `dticon`) or onto a Front Panel control works, in
  both directions.
* **ToolTalk** — the session runs under `ttsession -c` inside an unprivileged
  user+network namespace with our own `tt-portmapper`, so no root and no system
  `rpcbind` are needed; CDE's process types are compiled into the user database
  by `install-panel-data.sh`.
* **Input methods** — the shim's XIM is a real bridge to the compositor's
  `zwp_text_input_v3`, and `config/river-init` starts `ibus` (whose
  `ibus-wayland` module registers with River as an `input-method-v2` server), so
  CDE's Motif text widgets compose accented Latin and CJK text. Set `CDE_IME=0`
  to skip starting the input method.
* **Session save/restore** — done on the Wayland/Linux side: there is no shared
  X server, so XSMP cannot see the other clients. Every application launched by
  the session inherits `CDE_SESSION_TAG`/`CDE_SESSION_DIR` (see
  `config/cde-env.sh`), so the running clients are the processes carrying that
  marker; `scripts/cde-session-save.sh` records their command line and working
  directory at logout and `config/cde-session.sh` replays them on the next start
  (`scripts/cde-session-restore.sh`). The data lives under
  `$XDG_STATE_HOME/cde-wayland/sessions/<type>` (`current` or `home`), not
  `~/.dt/sessions`, which dtsession recreates from its own XSMP data. Set
  `CDE_RESTORE=0` to start clean.

### How actions are executed

CDE runs an action by handing it to the *Command Invoker*, which execs
`dtexec` and falls back to the SPC daemon (`dtspcd`) for a host it considers
remote. That path cannot run here — `dtspcd` is an inetd-style, per-connection
daemon we do not run, so the invocation simply blocks. Instead, actions are
resolved and started locally (`patches/dt-action-local-exec.patch`): the action
name is looked up in the `.dt` databases (matching `ARG_COUNT` and `ARG_TYPE`),
its command line is expanded (`%Arg_n%`, `%(class)Arg_n`, continuation lines)
and executed. That is what makes a File Manager double-click and a file dropped
on a panel control work. See *What's left*.

| M | Scope | State |
|---|---|---|
| M0 | repo + fetch + shim + CoW/River build | ✅ shim + Xt/Motif + CoW build (River: install distro package) |
| M1 | CDE `include/` + `lib/` build unmodified | ✅ **done** — all `libDt*`/`tt`/`csa` link against the shim |
| M2 | first CDE app (`dtcalc`/`dtpad`) under headless compositor | ✅ **done** — `dtcalc` renders in CDE colours on the shim |
| M3 | core desktop apps (dtterm, dtfile, dtstyle, …) | ✅ dtterm, dtfile, dtpad, dtcalc, dtstyle, dtcm, dtprintinfo, dticon, dthelpview, dtinfo |
| M4 | real River+CoW session with the CDE Front Panel | ✅ panel docked at the screen bottom; workspaces, menus and Style Manager wired |
| M5 | CoW panel/theme, backdrops, resources | ✅ CDE backdrops per workspace, MWM palette and cascade placement, icon box |
| M6 | cross-process broker (DnD, XSMP) | ✅ Motif DnD both ways (compositor drag + selection broker); Wayland-side session save/restore replaces XSMP |
| M7 | login manager (`dtlogin`) | ⬜ parked — needs a Wayland greeter; stock `dtlogin` spawns an X server |

See **What's left** below for the work that remains inside M1–M6.

## Quick start

```sh
# 1. get the sources (CDE, CoW, River; imake if missing)
scripts/fetch-sources.sh

# 2. build the Wayland libX11 shim + libXt + Open Motif
scripts/build-shim.sh

# 3. build CoW (and River, if requested)
scripts/build-cow.sh

# 4. build the helper programs (tt-portmapper, so ToolTalk needs no root)
scripts/build-tools.sh

# 5. build and install CDE: bootstrap, libs, applications, then the Front Panel
scripts/build-cde.sh all
scripts/build-cde.sh programs
scripts/build-cde.sh panel      # dtwm + front-panel data + install-panel-data.sh
scripts/build-cde.sh install
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

The session re-runs itself inside an unprivileged user+network namespace with
our own `tt-portmapper` (built by `scripts/build-tools.sh`), so ToolTalk needs
neither root nor a system `rpcbind`.

Start a session (needs a seat/DRM; normally from a TTY):

```sh
scripts/run-session.sh
```

Inside another Wayland session, run it nested and drive it with the smoke test:

```sh
scripts/test-nested.sh          # start + smoke-test, leaves it running
scripts/test-nested.sh --stop   # stop it
```

Run one application against the bundled headless compositor:

```sh
scripts/run-app.sh dtcalc
```

## What's left

* **Real action execution.** Actions are resolved and started locally (see
  *How actions are executed*). Getting CDE's own path working means fixing
  `dtexecPath` — it is a stale `CmdProcess.o` compiled against an older install
  root — and giving the Command Invoker a usable SPC daemon: `dtspcd` is
  inetd-style, so it needs a portmapper that can `CALLIT`, or an inetd. That
  would let us drop `dt-action-local-exec`, `dtsvc-no-tooltalk`,
  `dtwm-no-tooltalk` and `libtt-no-autostart`.
* **Login (M7).** Stock `dtlogin` needs `XSetAuthorization` in the shim just to
  link, and spawns an X server to host its greeter — which does not fit an
  architecture where every client has a private root. A Wayland-hosted greeter
  reusing `dtgreet` is the realistic shape.
* **Style Manager → Startup.** "Resume current session", "Return to Home
  session" and "Set Home Session…" are inert; save/restore is the Wayland-side
  process marker only, with no window geometry or desk recorded.
* **Input methods.** Only `ibus-engine-simple` is installed — the XIM bridge
  works, but there is no real engine (pinyin, …) to compose with.
* **Mailer.** `dtmail` wants a setgid `mail` group (or a non-spool mailbox); a
  packaging item.
* **Colour.** Applying a palette in the Style Manager changes little: TrueColor
  plus cairo bypass the colour-server allocation model `InitializeDtcolor`
  implements.
* **Odds and ends.** The Front Panel's own **Lock** control does not fire under
  CoW (the Workspace Menu's *Lock Screen* works); the Workspace Menu's *Refresh*
  has no WSM equivalent; the `.bm` (X bitmap) backdrops have no PNG, so selecting
  one does nothing; the Application Manager lists groups whose applications we
  do not ship; and the shim still lacks `XSetAuthorization`, `XAddPixel`,
  `XSubImage`, `XStringToContext`, `XTextHeight`, `XTextHeight16`,
  `XCreateHsbColormap`, `XAllocIDs`, `XReadPixmapFile` and `XWritePixmapFile`,
  plus the `Xss`, multi-screen Xinerama and `Xp` extensions.

## Patches

The long-term goal is **unmodified sources**, so every CDE change lives in
`patches/` as a small overlay that `build-cde.sh` applies to the build tree — the
pristine source is never touched.

| Patch | Purpose |
|---|---|
| `dt-action-local-exec.patch` | resolve and run actions locally (see above) |
| `dtappgather-target.patch` | let `dtappgather` gather into a writable directory |
| `dtsvc-logfiles-top.patch` | allow `CDE_LOGFILES_TOP` from the environment (`dtspcd`) |
| `dtsvc-backdrop.patch` | run `cde-wsm-backdrop` when the Style Manager changes the backdrop |
| `dtsession-vfork-exit.patch` | `_exit` in `vfork` children (libpixman destructor crash) |
| `dtwm-subpanel-unpost.patch` | unmap a sub-panel instead of `CallWmFunction(F_Kill)` |
| `dtwm-wsm-desk.patch`, `dtwm-wsm-list.patch` | drive and read CoW's desks from dtwm |
| `dtwm-empty-clientlist.patch` | do not dereference an empty client list |
| `dtwm-no-tooltalk.patch`, `dtsvc-no-tooltalk.patch`, `libtt-no-autostart.patch` | keep ToolTalk out of panel/session startup |
| `rpccmsd-nonroot.patch` | key the private calendar spool off `CDE_CMSD_DIR`, not `euid` |
| `cow-decoration-hint.patch`, `cow-transient-stacking.patch` | CoW: honour MWM decoration hints and transient stacking |

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
