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
  with every client), Font, Color and Startup modules are wired to the session:
  Startup's "Resume current session"/"Return to Home session" picks which store
  is replayed, "Set Home Session…" saves the running session as home, and the
  "Logout Confirmation Dialog" choice gates the dialog `cde-logout` shows.
* **Application Manager** — `dtappgather` gathers CDE's application groups
  (Desktop_Apps, Desktop_Tools, Information, System_Admin, ...) and their
  entries show as action icons, so a File Manager double-click works.
* **Colour** — dtsession's colour server publishes the CDE palette as
  `RESOURCE_MANAGER` and the shim relays that property between clients, so
  applications take CDE's real colours (`Default.dp` colour set 4, `#c6b2a8` on
  a TrueColor display) rather than a hard-coded approximation. A palette chosen
  in the Style Manager is followed by the Front Panel: `cde-palette-watch` sees
  the relayed palette change, then restarts the colour server and the panel (the
  colour server caches the pixel set Motif's colour object fetches, so
  restarting the panel alone is not enough). Applications keep their colours and
  pick the palette up the next time they start — CDE's own behaviour on a
  display without dynamic colour, where its Style Manager says the change
  "will take effect at your next session". The choice is also kept in
  `$XDG_STATE_HOME/cde-wayland/resource-manager`, since the store the palette is
  relayed through lives under `XDG_RUNTIME_DIR` and does not survive a logout or
  reboot; `cde-session.sh` puts it back before dtsession starts. The frames,
  menus and minimized icons CoW draws follow the palette as well: it is not an X
  client, so `cde-palette-colours` reads the palette the way CDE's own dtwm does
  and `cde-cow-colours` hands the colours to CoW — immediately for a change made
  in the Style Manager (the palette file is named by the relayed resource
  database), with clients following on restart.
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
`dtexec`; that is what this session uses (a File Manager double-click and a
file dropped on a panel control both end up there). Two build details make it
work: `dtexecPath` is compiled from the install root — and `build-cde.sh` now
clears stale objects when the prefix changes — and the `.dt` databases are
regenerated on every panel build, because the cpp rules only rewrite a *missing*
target and a `.dt` generated before the `CppCmd` fix silently dropped every
`EXEC_STRING` continuation, and with it the action's arguments.

A few actions are overridden where CDE's definition does not suit a private-root
Wayland session. They live in `config/dtwm-types/*.dt` and are installed into
`~/.dt/types`:

| Action | Why |
|---|---|
| `Dtappmgr` | CDE asks the File Manager for `/var/dt/appconfig/appmanager/$DTUSERSESSION`, which an unprivileged session cannot create; ask it for the directory `dtappgather` collects instead (so a running File Manager is reused) |
| `DtLoadInfoLib` | start `dtinfo` directly rather than rely on ptype auto-start |
| `LockDisplay` | run `waylock` instead of a ToolTalk request to dtsession |

`ExitSession` is rewritten the same way by `install-panel-data.sh` (it runs
`cde-logout`).

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

## What can this do that X11 CDE cannot?

Stock CDE on the Wayland shim can do a few things a classic X11 CDE session
cannot: run natively in a Wayland session (no X server, no Xwayland), exchange
clipboard and drag-and-drop with native Wayland applications, use the
compositor's input-method stack, keep each client isolated, install and run
rootless, and delegate window management to the compositor. See
[docs/WAYLAND-ADVANTAGES.md](docs/WAYLAND-ADVANTAGES.md).

## What's left

* **Login (M7).** Stock `dtlogin` needs `XSetAuthorization` in the shim just to
  link, and spawns an X server to host its greeter — which does not fit an
  architecture where every client has a private root. A Wayland-hosted greeter
  reusing `dtgreet` is the realistic shape.
* **Session restore fidelity.** The Style Manager's Startup module now picks the
  store (`current`/`home`), sets the home session and gates the logout
  confirmation, but what is saved is still the Wayland-side process marker: no
  window geometry or desk is recorded.
* **Style Manager is slow to put its window up.** `dtstyle` is launched through
  `dtexec`/ToolTalk and has been seen to take tens of seconds to map (it was
  easy to mistake for "it did not start"), which makes the module feel
  unresponsive. Not investigated.
* **Input methods.** Only `ibus-engine-simple` is installed — the XIM bridge
  works, but there is no real engine (pinyin, …) to compose with.
* **Mailer.** `dtmail` wants a setgid `mail` group (or a non-spool mailbox); a
  packaging item.
* **CDE's own `sys.resources` is never applied.** `programs/dtsession` builds it
  with a `$(CPP)` rule that has no value in the generated Makefile, so the
  installed file is empty; `dtsession_res` would merge it, but it shells out to
  `xrdb`, which is not installed either. The one setting that matters here
  (`*ColorUse`) therefore lives in `config/Xresources`.
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
| `dtappgather-target.patch` | let `dtappgather` gather into a writable directory |
| `dtsvc-logfiles-top.patch` | allow `CDE_LOGFILES_TOP` from the environment (`dtspcd`) |
| `dtsvc-backdrop.patch` | run `cde-wsm-backdrop` when the Style Manager changes the backdrop |
| `dtstyle-startup.patch` | record the Style Manager Startup choices where the Wayland session and `cde-logout` can read them, and save the home session Wayland-side |
| `dtsession-vfork-exit.patch` | `_exit` in `vfork` children (libpixman destructor crash) |
| `dtwm-subpanel-unpost.patch` | unmap a sub-panel instead of `CallWmFunction(F_Kill)` |
| `dtwm-wsm-desk.patch`, `dtwm-wsm-list.patch` | drive and read CoW's desks from dtwm |
| `dtwm-empty-clientlist.patch` | do not dereference an empty client list |
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
