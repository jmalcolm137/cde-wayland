# CDE on Wayland — Design Document

**Status:** draft / living document
**Target:** A Common Desktop Environment (CDE) session that runs natively on
Wayland: unmodified CDE Motif programs on the Xlib-for-Wayland shim, with CoW
(River) as the window manager/compositor.

---

## 1. Summary

CDE is a large body of Motif programs and libraries (`dtterm`, `dtfile`,
`dtpad`, `dtcalc`, `dtstyle`, `dtsession`, `dthelp`, `dtmail`, …). Motif only
knows Xlib. We already have a project that makes Motif speak Wayland directly,
without an X server or Xwayland:

```
xlib-wayland — a Wayland-native, ABI-compatible implementation of libX11
```

The plan is therefore not to port CDE. It is to **run stock CDE on
xlib-wayland**, and to supply the parts of a desktop that CDE expects from the
X server and its window manager from Wayland instead:

* **Xlib → Wayland**: provided by `xlib-wayland`.
* **Window manager / compositor**: provided by **CoW**, a stacking WM that runs
  as a client of the **River** compositor (River owns the display; CoW owns
  window-management policy, decorations and IPC).
* **Everything else** (session, panel-less desktop, applications, help, data):
  stock CDE from `lkujaw/cde` (the imake CDE tree).

We change CDE as little as possible — ideally not at all. Any change that turns
out to be unavoidable is either a *configuration* change to CDE's sanctioned
local-config file (`host.def`) or, better, an accommodation added to
`xlib-wayland`.

---

## 2. The stack

```
┌───────────────────────────────────────────────────────────────────────────┐
│  CDE desktop layer (stock, minimal/no source changes)                      │
│  dtsession · dtfile · dtterm · dtpad · dtcalc · dtstyle · dthelp · dtcm …  │
├───────────────────────────────────────────────────────────────────────────┤
│  CDE libraries (stock)   libDtSvc · libDtWidget · libDtHelp · libDtTerm …  │
├───────────────────────────────────────────────────────────────────────────┤
│  Open Motif (libXm) + libXt                 (built against the shim)       │
├───────────────────────────────────────────────────────────────────────────┤
│  libX11 (Wayland shim)  ← xlib-wayland      (the only platform layer)      │
├───────────────────────────────────────────────────────────────────────────┤
│  Wayland client: wl_surface / xdg_toplevel per top-level X window          │
└───────────────▲───────────────────────────────────────────────────────────┘
                │  Wayland protocol
┌───────────────┴───────────────────────────────────────────────────────────┐
│  River  (compositor, display/input/surface authority)                       │
│     ▲ river-window-management-v1                                            │
│  CoW    (stacking WM: policy, stacking, desks/pages, menus, decorations)    │
│  modules: cowbar · cowpager · cowiconman · moocow · cowbuttons              │
└───────────────────────────────────────────────────────────────────────────┘
```

Evidence that the lower half works is already in `xlib-wayland`: stock libXt,
Open Motif, XV and NEdit build unmodified and run under a bundled headless
compositor. CDE is "more Motif", so the same layer applies; the new work is at
the desktop/session layer and in the X-server-role functions the shim must
impersonate.

---

## 3. The pivotal constraint: there is no shared X server

`xlib-wayland` is an **in-process** implementation of Xlib. Every application
process gets its own copy of the library, its own root window, its own atom
table and property store, and its own window tree. State does not exist
server-side and is not shared between processes.

This is the single most important fact in this design, and it shapes
everything:

### 3.1 What still works (single-client semantics)

* Every Motif program behaves as it would against a private X server: widgets,
  drawing, fonts, colours, images, input, menus, popups, timers.
* `xdg_toplevel` windows, `xdg_popup` menus and grabs.
* Client-side/wayland-side decorations coordinated with CoW.
* In-process selection, DnD and properties (e.g. a file manager dragging its
  own icons).
* Clipboard between an X client and Wayland clients: already bridged through
  `wl_data_device` in `src/wayland/clipboard.c`.

### 3.2 What does **not** work without help

Any CDE feature that relies on a *different process* observing X server state:

| CDE feature | Mechanism | Status under the shim |
|---|---|---|
| `Xm`/X inter-client clipboard | CLIPBOARD selection | works via `wl_data_device` (text) |
| Motif drag-and-drop between apps | `_MOTIF_DRAG_*` X properties + selections | **not shared**; in-process only |
| `dtsession` session management | XSMP over ICE, plus `_DT_SM_*` root properties | **needs a session layer** |
| Workspace/front-panel coordination | `_DT_WORKSPACE_*`, `_MOTIF_WM_*` root props | becomes CoW's job |
| X resources for all apps | `RESOURCE_MANAGER` root property | per-process; each reads files directly |
| Inter-client `XSendEvent` | events to another client's window | not possible cross-process |

### 3.3 Strategy

1. **Wayland is the coordination bus where a binding exists.** Clipboard already
   uses `wl_data_device`; window/desk/workspace state uses CoW's command and
   status sockets.
2. **A small optional broker** (`cde-broker`, a future `xlib-wayland`
   component) can multiplex atom/property/selection semantics between shim
   processes over a Unix socket, for the few protocols that truly need it
   (XSMP, Motif DnD). This is the clean place to put it: it is platform code,
   not CDE code.
3. **v1 ships single-process-correct behaviour.** Cross-process DnD and full
   session restore are explicitly later milestones, not prerequisites.

> **Corollary: `dtwm`/`mwm` cannot be the window manager.** A window manager is
> an X client that manages *other clients'* windows; each shim process has its
> own private root, so `dtwm` would see only itself. The window manager must be
> a real Wayland WM — hence CoW.

---

## 4. Window management with CoW on River

River is the compositor. It owns the display, input routing, outputs and the
surface tree, and exposes `river-window-management-v1`. CoW connects as an
ordinary Wayland client and provides MWM/FVWM-style policy: stacking,
decorations, desks and pages, menus, rules/styles, and an IPC socket.

Each top-level X window in a CDE app becomes an `xdg_toplevel`. CoW treats it
like any other Wayland window. The mapping of X/ICCCM concepts therefore splits
differently than on X11:

| X11/CDE concept | Provided by |
|---|---|
| Window manager (`dtwm`/`mwm`) | **CoW** (replaces `dtwm`'s WM role) |
| Title, icon name, class | shim maps `WM_NAME`/`_NET_WM_NAME`/`WM_CLASS` → `xdg_toplevel` |
| Move / resize / maximize / iconify | shim → `xdg_toplevel`; CoW → River |
| ICCCM WM hints | shim reads properties and translates; CoW need not see them |
| Override-redirect menus/tooltips | shim → `xdg_popup` |
| Window menu (Alt-Space) | CoW menus/bindings |
| Workspaces | CoW **desks** (and pages) |
| Front Panel | **not in v1** — see §5.2 |
| Decorations | CoW server-side decorations (themeable toward CDE/MWM) |
| Raise/lower | CoW stacking policy |
| Focus | River/CoW policy (click-to-focus / focus-follows-mouse) |

### 4.1 Decorations

CoW draws server-side decorations. `xlib-wayland` currently draws its own
client-side titlebar when the compositor offers none; under River+CoW it should
request **server-side** decorations and leave chrome to CoW. A CDE/MWM-styled
CoW theme (teal, beveled titlebar, the classic window menu button) is the visual
target and is pure CoW configuration — no C code.

### 4.2 MWM hints

Motif asks for specific MWM decorations via `_MOTIF_WM_HINTS` (no titlebar, no
resize, etc.). The shim already owns window properties, so it can translate
`_MOTIF_WM_HINTS` and `WM_NORMAL_HINTS` into `xdg_toplevel` requests
(`set_max_size`, `set_min_size`) and, where River/CoW supports per-window
decoration hints, into those. This is a shim accommodation, not a CDE change.

---

## 5. CDE component strategy

### 5.1 Build the libraries and applications stock

CDE's unit of build is the tree under `cde/` (`lib/`, `programs/`, `include/`,
`databases/`, `config/`). We build it with its bundled imake tooling against our
prefix. The source tree stays pristine; see §6.

Target set, in dependency order:

1. **`include/`** — public CDE headers (`Dt/*.h`).
2. **`lib/`** — `tt`, `DtSvc`, `DtSearch`, `DtWidget`, `DtHelp`, `DtPrint`,
   `DtTerm`, `DtMrm`, `csa`.
3. **`programs/`** — start with leaf apps (`dtcalc`, `dtpad`, `dthello`), then
   `dtterm`, `dtfile`, `dtstyle`, `dtcm`, `dthelp`, `dtprintinfo`, `dticon`.
4. **Desktop shell** — `dtsession` (session/startup); `dtwm` is **not** used as
   the WM.

### 5.2 The Front Panel problem

In CDE, the Front Panel and workspace switching live inside `dtwm` (the Desktop
Window Manager). Since CoW replaces `dtwm`'s WM role, the Front Panel does not
come along for free. Options, in preference order:

1. **Use CoW's own panel/launcher** (`cowbuttons`, CoW menus) configured with
   CDE application entries and a CDE-ish theme. No CDE changes. This is the v1
   answer.
2. **A small standalone panel** built from CDE widgets (`libDtWidget`) that
   drives CoW through `moocow`, reusing CDE's icons and actions. This is a new
   program in *our* repo, not a CDE patch.
3. **Last resort:** a minimal patch to `dtwm` to run as a "panel-only" client
   with WM disabled. Only if 1 and 2 prove insufficient.

The same reasoning applies to CDE's desktop backdrop and icon handling: CoW (or
a tiny Wayland layer-shell helper) owns the root, and CDE's XPM backdrops can be
displayed by a helper.

### 5.3 Session startup

`dtsession` is the natural session entry point. A v1 session script starts:

```
river -c cde-session
   └─ cow-start                      (WM policy + modules)
   └─ cde-session                    (our script)
        ├─ export CDE search paths  (DTDATABASESEARCHPATH, DTHELPSEARCHPATH, …)
        ├─ publish X resources       (RESOURCE_MANAGER equivalent)
        ├─ dtsession                 (if it comes up; else launch apps directly)
        └─ initial apps              (dtfile, dtterm, dthelp, …)
```

Because `dtsession`'s XSMP coordination is cross-process (§3.2), v1 may launch
the initial applications directly from `cde-session` and leave `dtsession` as a
follow-up once a session broker exists.

---

## 6. Keeping CDE source pristine

Imake generates Makefiles **in the source tree**. To avoid polluting the
checkout:

* The pristine tree lives under `$CDE_SRC` (read-only intent).
* `scripts/build-cde.sh` makes a **build tree** (copy, or `lndir` symlink farm)
  under `$CDE_BUILD`, then:
  * installs our `host.def` into `config/cf/` (imake's sanctioned local-config
    file — empty upstream, meant to be filled in),
  * points `ProjectRoot`, `X11ProjectRoot`, `MotifProjectRoot`,
    `XAppLoadDir`, locale dirs, etc. at `$CDE_PREFIX`,
  * runs CDE's bundled imake bootstrap (`make World` or the staged
    `Makefiles`/`includes`/`depend`/`all`),
  * builds and installs.
* Any *code* patch that proves unavoidable is kept as a numbered file under
  `patches/` and applied to the build tree only, with a comment explaining why
  and a pointer to the shim change that would let us drop it.

The rule: **if it can be a shim change, it is a shim change.** A build-tree
`host.def` change is configuration. A patch is a last resort and a bug report
against `xlib-wayland`.

### 6.1 The shim lives in its own repository

`xlib-wayland` is a standalone upstream project, published at
<https://github.com/jmalcolm137/xlib-wayland>. **Every shim accommodation goes
there**, committed and pushed in that repository first; this repository only
consumes the result and records the revision in `versions.lock`. Nothing in
this tree patches, vendors or forks the shim.

So the workflow for a new CDE requirement is:

1. Reproduce the missing/incorrect behaviour on the shim (`xlib-wayland`).
2. Add the fix and a test there; commit and push.
3. Bump `XLIB_WAYLAND_REF` (or record the commit) in `versions.lock` here and
   rebuild via `scripts/build-shim.sh`.

The only files in *this* repository that are CDE-specific are the build
configuration (`config/cde-host.def.in`) and the session/WM configuration
(`config/`), plus the orchestrating scripts. There are no CDE source patches.

---

## 7. Shim accommodation backlog

Measured against the shim's current exports (`nm -D libX11.so.6`), CDE calls
about **374 Xlib-family functions**; the shim already exports **320** of them.
The remaining surface is small and concentrated in extensions and rarely used
entry points. Known gaps:

> **M1 result (measured):** after building every CDE shared library
> (`libDtSvc`, `libDtWidget`, `libDtHelp`, `libDtSearch`, `libDtPrint`,
> `libDtTerm`, `libDtMrm`, `libcsa`, `libtt`, `libDtXinerama`) against the shim,
> the set of undefined Xlib-family symbols they reference (125) is **fully
> covered by the shim — zero missing**. The extension gaps below apply to the
> window manager, session and login programs, which we build later.

### 7.1 Extensions used by specific CDE programs

| Extension | Used by | v1 approach |
|---|---|---|
| **XScreenSaver** (`XScreenSaver…`, `libXss`) | `dtsession`, `dtscreen`, `dtwm` | report absent via `XQueryExtension`; `dtscreen` falls back / is deferred |
| **Xinerama** (`libXinerama`, `libDtXinerama`) | `DtXinerama`, `DtSvc`, `dtsession`, `dtfile` | report absent → single screen; `DtXinerama` returns the one X screen |
| **allplanes** (`XAllPlanes…`) | `dtstyle`/backdrops | not needed for v1 |
| **XPrint** (`Xp…`) | `dtprintinfo`, `dtterm` (`USE_XHPLIB`) | not built in v1 |
| **XShape** | CDE panels/backdrops | already implemented |
| **Xrandr** | some CDE code | already implemented |

### 7.2 Core entry points not yet exported

From the same comparison: `XAddPixel`, `XSubImage`, `XSetAuthorization`,
`XStringToContext`, `XTextHeight`, `XTextHeight16`, `XCreateHsbColormap`,
`XAllocIDs`, and the XV-style `XReadPixmapFile`/`XWritePixmapFile`. Each is
small; they are added to `xlib-wayland` (`src/xlib/…`) as needed, with tests.

### 7.3 Auxiliary X libraries

CDE links `libXmu`, `libXpm`, `libXext`, `libXrender`, `libXinerama`, `libXss`.
These sit on Xlib's *internal* ABI (which the shim already provides:
`src/xlib/xlibint.c`). v1 links the distro copies but arranges that
`libX11.so.6` resolves to the shim (rpath / `LD_LIBRARY_PATH`), so they bind to
our Xlib. Where that proves fragile, we build the auxiliary library against the
shim exactly as `libXft` is already built in `xlib-wayland`.

### 7.4 Server-role behaviours to add for a desktop

These are the shim's "be the X server" duties that CDE (rather than NEdit/XV)
exercises:

* `_MOTIF_WM_HINTS` → `xdg_toplevel` decoration/size requests (§4.2).
* `XIconifyWindow`, `XWithdrawWindow`, `XReconfigureWMWindow` semantics.
* Root-window properties: `RESOURCE_MANAGER` (done), plus `_DT_*`,
  `_MOTIF_*`, `_NET_*` that CDE writes and reads within one process or that we
  map onto CoW state.
* Screen saver / idle behaviour (Xss) — decide per app.
* Session-management surface (XSMP/ICE): out of v1; broker later.

### 7.5 Findings from the first application (dtcalc)

The first real CDE program exposed a shim bug that no earlier client had
tripped over.  `XOpenDisplay` reported the raw Wayland socket name
(`wayland-0`) through `Display.display_name` / `XDisplayString`.  Xlib clients
conventionally parse that string as `host:display.screen`, and CDE's `DtSvc`
does exactly that in `GetDisplayName` (`SmCreateDirs.c`): it splits on `:` and
then calls `strlen()` on the remainder, so a colon-less name crashed `dtcalc`
with `strlen(NULL)` before its first window.

Fixed **upstream in xlib-wayland** (`b9a3142`): `XOpenDisplay` now derives the
reported name from its argument, then `$DISPLAY`, then a local `:0`, and keeps
using it as the open-display key.  This is the workflow §6.1 describes: the
fix lives in the shim repository, and this repository only records the tested
revision.

The lesson generalises: the shim must imitate Xlib's *observable values*, not
just its function surface.  Anywhere CDE reads a struct field or a string that
Xlib guarantees to be X-shaped, the shim has to produce an X-shaped value even
though the transport is Wayland.

The same session also fixed a second shim bug behind **dtterm's terminal grid
rendering only ~20 of every 80 columns**.  Two things were involved:

* **In the shim** (`a8c2a3e`): `XmbTextExtents` and `XwcTextExtents` filled
  `logical` with `*logical = *ink` after filling `ink` only when non-NULL.
  `ink` is optional — DtTerm calls `XwcTextExtents(fs, s, n, NULL, &ext)`
  — so the font-set path crashed with a NULL dereference.  Both outputs are
  now filled independently.
* **In the configuration** (`config/Xresources`): DtTerm only uses that
  font-set path when Motif gives it an `XmFONT_IS_FONTSET` entry.  With a
  plain `*fontList` font, DtTerm takes its single-font path and, in a
  multibyte locale, passes a **wide-character** buffer to `XDrawImageString`,
  which counts bytes — so only `len/4` glyphs appear.  CDE's own
  `sys.resources` avoids this by specifying `*userFont` with Motif's
  trailing-colon fontset syntax; we now ship the same in `Xresources`.

This is also the first case where the fix was not purely in the shim: the
shim bug had to be fixed *and* the missing CDE resource supplied.  Running in
the `C` locale masked the second half entirely (`MB_CUR_MAX == 1` uses byte
storage), which is why it took a while to isolate.

---

## 8. Runtime environment, resources and locales

CDE depends heavily on search paths and locale data being installed and
exported. `cde-session` sets, at minimum:

* `DTDATABASESEARCHPATH`, `DTUSERSEARCHPATH`, `DTHELPSEARCHPATH`,
  `DTSPCDSEARCHPATH`, `XMICONSEARCHPATH`, `XMICONBMSEARCHPATH`,
  `XFILESEARCHPATH`, `XAPPLRESDIR`, `DTPRINTSEARCHPATH`, `DTDTYPES`.
* `LANG` / `LC_ALL` from the user's environment.
* `RESOURCE_MANAGER` content: the shim synthesises the root property from
  `~/.Xresources`/`~/.Xdefaults`/`/etc/X11/Xresources`; we install a CDE
  `cdestyle`/`Xresources` set into `$CDE_PREFIX` and point the shim at it.

`admin/IntegTools/.../installCDE` (or the imake install targets) installs the
tree under `$ProjectRoot`. We use `$CDE_PREFIX/dt` so the whole desktop is
relocatable and needs no root.

---

## 9. Milestones

| M | Scope | Exit criterion |
|---|---|---|
| **M0** | Repo, source fetch, build harness; shim + CoW/River built | `scripts/fetch-sources.sh` then `scripts/build-shim.sh` green |
| **M1** | CDE `include/` + `lib/` build unmodified against the shim | all `libDt*`/`tt`/`csa` install into `$CDE_PREFIX` |
| **M2** | First CDE app | `dtcalc` (or `dtpad`) runs under the headless compositor and renders a golden frame |
| **M3** | Core desktop apps | `dtterm`, `dtfile`, `dtstyle`, `dtcm`, `dthelp` run; menus and text input work |
| **M4** | Real session under River+CoW | apps launch in a River/CoW session with CoW decorations and a CDE-ish theme |
| **M5** | Desktop integration | CoW panel/launcher with CDE entries; backdrops; icon handling; X resources propagated |
| **M6** | Cross-process features via broker | clipboard (have text), Motif DnD, XSMP session restore |
| **M7** | Polish/hardening | idle/screensaver, multiscreen via Xinerama mapping, soak/ASan |

---

## 10. Risks and mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| No shared X server breaks CDE IPC (DnD, XSMP) | features missing, apps hang waiting | v1 avoids them; Wayland bridge where possible; broker later (§3.3) |
| `dtwm`/Front Panel cannot run | no classic panel/workspaces | CoW desks + `cowbuttons`/menus; optional standalone CDE panel (§5.2) |
| CDE imake tooling is 1990s-era | bootstrap/compile failures | use CDE's bundled imake, or distro `imake`; `host.def` overlay; build-tree isolation |
| Shim missing extension symbols | link/run failures | §7 backlog, fixed in `xlib-wayland` with tests |
| Distro `libXmu`/`libXpm` bind to system Xlib | two Xlibs in one process | force rpath to the shim; build aux libs against the shim if needed |
| River needs a real seat (DRM/input) | can't run the session in CI | headless compositor for tests; River+CoW validated on a desktop/TTY; `WLR_BACKENDS` where possible |
| River/CoW version skew | protocol mismatch | pin River and CoW versions; record the pair in `versions.lock` |
| CDE assumes `/usr/dt` and root install | path/resource breakage | `$CDE_PREFIX/dt`, `ProjectRoot` override, `cde-session` exports |
| Scope is enormous | never "done" | milestone-gated, leaf app first, one process at a time |

---

## 11. Repository layout (this repo)

```
cde-wayland/
├── DESIGN.md                 # this document
├── README.md                 # quick start + status
├── versions.lock             # pinned upstream revisions
├── config/
│   ├── cde-host.def          # imake host.def overlay (paths + options)
│   ├── cde-session.sh        # session entry point (exports + apps)
│   ├── cow.conf              # CoW config: CDE-ish theme, menus, binds
│   ├── river-init            # river init that starts cow-start
│   └── Xresources            # CDE look/feel resources
├── scripts/
│   ├── lib.sh                # shared env/log helpers
│   ├── fetch-sources.sh      # clone CDE/CoW/River; fetch imake
│   ├── build-shim.sh         # build & install xlib-wayland
│   ├── build-cow.sh          # build & install River (opt) + CoW
│   ├── build-cde.sh          # bootstrap/configure/build/install CDE
│   ├── run-app.sh            # run one CDE app under the headless compositor
│   ├── run-headless-tests.sh # golden frame / smoke tests
│   └── run-session.sh        # start River+CoW+cde-session on a real seat
└── patches/                  # last-resort CDE patches (should stay empty)
```

`xlib-wayland` is a sibling checkout (`$XLIB_WAYLAND`, default
`../xlib-wayland`); it is the home for every shim accommodation.

---

## 12. Appendix — evidence and how it was gathered

* **Shim capability**: `xlib-wayland/README.md`, `DESIGN.md`, and
  `scripts/run-tests.sh` (XV and NEdit built unmodified).
* **CDE call surface**: grep of `cde/lib` + `cde/programs` for `X*` calls,
  compared with `nm -D ~/.local/motif-wayland/lib/libX11.so.6.0.0`
  (374 called / 320 exported).
* **Extension usage**: `#include <X11/extensions/*.h>` frequency —
  `shape.h` ×6, `Print.h` ×4, `scrnsaver.h` ×2, `Xinerama.h` ×1,
  `allplanes.h` ×1.
* **CDE build system**: `cde/Imakefile`, `cde/Makefile`,
  `cde/config/cf/{site.def,linux.cf,X11.tmpl,Motif.tmpl}`, and the bundled
  `cde/config/{imake,makedepend}`; Debian packaging
  (`cde/debian/rules`) as a known-good Linux build shape.
* **CoW/River split**: CoW `architecture.md` and README (River is the
  compositor; CoW is a Wayland client owning policy, decorations and IPC).
