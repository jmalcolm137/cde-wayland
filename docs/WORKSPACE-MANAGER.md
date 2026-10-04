# Workspace Manager plan

**Status:** agreed direction, implementation not started
**Decision:** keep CoW as the Window Manager; make the CDE **Workspace Manager**
(WSM) real. A full "dtwm-for-Wayland" rewrite is a later option, not a
prerequisite. Real `dtwm` stays as the Front Panel; only the WM core is
eventually reimplemented, and only incrementally.

---

## Why this exists

In CDE the Workspace Manager *is* `dtwm`. It provides the user-facing
workspace UI and the `DtWsm` service that applications call. In this port CoW
is the window manager, so none of that is connected:

* the Front Panel's One/Two/Three/Four **switch does nothing** — its buttons
  call `DtWsmSetCurrentWorkspace`, which changes dtwm's *internal* workspace,
  and dtwm cannot see the real windows (the shim gives every process a private
  X server);
* the **desktop/root menu** and **titlebar menu** are CoW's, not CDE's;
* applications that call `DtWsm…` misbehave (see "Findings").

## Architecture

* Real `dtwm` keeps running as the **Front Panel** (`cde-session.sh`), unchanged.
* The Workspace Manager is provided by (a) the shim answering the workspace
  **X-property** queries and (b) a **ToolTalk** service answering the WSM
  request ops, bridged to CoW's desks.
* The panel and applications talk to it over the protocol real dtwm already
  speaks, so no CDE UI rewrite is needed.

## The two protocol channels

### 1. X properties (queries)

These are read from the **WM window**, found via `_DtGetMwmWindow()`:
`_GetMwmWindow()` reads the root's `_MOTIF_WM_INFO` property (type
`_MOTIF_WM_INFO`, format 32, 2 elements: `flags`, `wmWindow`) and requires the
WM window to be a **direct child of the root**.

On the WM window:

| property | type | format | contents |
|---|---|---|---|
| `_DT_WORKSPACE_LIST` | `XA_ATOM` | 32 | array of workspace-name atoms |
| `_DT_WORKSPACE_CURRENT` | `XA_ATOM` | 32 | the current workspace atom |
| `_DT_WORKSPACE_INFO` | string | 8 | per-workspace metadata (name/backdrop), read by `WmGWsInfo.c` |
| `_DT_WORKSPACE_HINTS` / `_DT_WORKSPACE_PRESENCE` | | | per-client workspace membership |

Because every client has its **own private X root**, these properties cannot be
shared between processes. The shim must therefore **synthesize** a WM window and
these properties per client, from a shared workspace-state source.

### 2. ToolTalk (commands + notifications)

Served by `dtInitializeMessaging()` in `programs/dtwm/WmIPC.c` (session-scoped
patterns, `TT_REQUEST` / notices):

| op | args | notes |
|---|---|---|
| `DtWorkspace_SetCurrent` | int screen, string atom | switch desk |
| `DtWorkspace_Title_Set` | int screen, string atom, string name | rename desk |
| `DtWorkspace_Add` | string title | create desk |
| `DtWorkspace_Delete` | string atom | delete desk |
| `GetWsmClients` | — | list clients per workspace |
| `DtPanel_Restore` | — | restart the panel |
| `DtWorkspace_Modified` | notice | published when the workspace model changes |

Clients register a `TT_OBSERVE` pattern for `DtWorkspace_Modified` via
`DtWsmAddWorkspaceModifiedCallback`, and read the workspace list/current via the
X-property channel above.

## Findings so far

* `dtfile` builds its desktop/workspace list in `LoadDesktopInfo()`
  (`programs/dtfile/Desktop.c`), calling `DtWsmGetWorkspaceList()` in a retry
  loop that `sleep(2)`s up to `retryLoadDesktopInfo` times, then falls back to a
  single workspace named "One". With no WM window the query always fails, so the
  File Manager stalls and never presents a real view.
* `dtfile` (and others) block in `_DtWsmAddMarqueeSelectionCallback`
  (`lib/DtSvc/DtUtil1/WmMarquee.c`) when the WSM is absent — it registers a
  `TT_OBSERVE` pattern for `DtMarquee_Selection`. Re-enabling dtwm's ToolTalk
  did **not** by itself unblock it; needs more digging (see open questions).
* The shim's `XPutImage`/background-pixmap/cursor/output-size fixes are
  independent of this work.

## Milestones

### Step 1 — WSM foundation (in progress)
1. **Shim:** synthesize a WM window as a direct child of the root, set root
   `_MOTIF_WM_INFO` → it, and set `_DT_WORKSPACE_LIST` /
   `_DT_WORKSPACE_CURRENT` / `_DT_WORKSPACE_INFO` on it from a shared state
   source (default: four workspaces `One`…`Four`, current `One`). This makes
   every client's workspace queries succeed.
2. **State source + bridge:** a small helper (or `cde-wsm` daemon) that owns the
   workspace model, writes the shared state, and switches CoW's desks in step.
3. **ToolTalk service:** answer `DtWorkspace_SetCurrent/Add/Delete/Title_Set`,
   `GetWsmClients`, and emit `DtWorkspace_Modified`. Wire the Front Panel switch
   to it (via dtwm's ToolTalk, or via the bridge).
4. **Verify:** the panel switch moves CoW's desks; `dtfile` no longer stalls.

### Step 2 — CDE window hints
* Extend the shim to convey `_MOTIF_WM_HINTS` (decorations: menu/title/border/
  resize/minimize/maximize), `WM_TRANSIENT_FOR`, window type, and
  `_DT_WORKSPACE_HINTS` for each toplevel.
* Teach CoW to honour them: true MWM decorations, undecorated/torn-off windows,
  per-workspace placement.

### Step 3 — CDE chrome (user-facing UI)

**3a. Desktop / root Workspace Manager menu (required).**
Clicking on the desktop (root window) must open the CDE Workspace Manager menu,
not CoW's `CDEApps` menu. This is dtwm's `builtinRootMenu` from
`sys.dtwmrc`, which we already install, and in CDE it is the primary place the
Workspace Manager presents itself to the user:

* a **Workspaces** submenu listing every desk (switch to it), with the current
  desk marked;
* **Add Workspace…** / **Delete Workspace…** / **Rename…** (the latter via the
  switch's inline rename field);
* **Window Ops**: Shuffle Up/Down, Refresh, Pack Icons, Restart Workspace
  Manager;
* the CDE/MWM look (colors, separators, check marks).

Implementation options, in order of preference:
1. Have CoW's menu system load dtwm's `builtinRootMenu`/`sys.dtwmrc` menu
   definition and dispatch its entries to the WSM (switch/add/delete) and CoW
   (window ops). This keeps one menu engine.
2. Bridge CoW's root menu to the WSM: build an equivalent CDE-styled menu and
   route the workspace entries over `DtWsm`.
3. Run real dtwm's menu on the desktop: dtwm cannot see the root (private X
   server), so this needs the shim to hand dtwm the root menu's clicks — only if
   1 and 2 prove too limited.

**3b. CDE titlebar menu.** Minimize / Occupy Workspace / Move / Resize / Close,
matching `sys.dtwmrc`'s `builtinSystemMenu`, instead of CoW's decoration menu.

**3c. Workspace titles** and the **icon box.**

### What the user will see (acceptance)
* Front Panel One/Two/Three/Four switches the desk.
* Clicking the desktop opens the **Workspace Manager menu** (switch / add /
  delete / rename workspace, window ops).
* Windows have CDE titlebar menus.
* Workspace titles and the icon box behave like CDE.

### Step 4 — optional: WM rewrite
* Only if "dtwm is literally the WM" is still wanted after steps 1–3: replace
  CoW with a dtwm-derived WM. By then the WSM, hints and menu data are in place,
  so the remaining work is the WM core (framing, focus, workspaces, output
  handling) — not the CDE UI.

## Open questions / risks

* What exactly blocks `_DtWsmAddMarqueeSelectionCallback` (Tttk type, the
  `TT_OBSERVE` `DtMarquee_Selection` pattern, or `_DtSvcInitToolTalk`)?
* CoW vs CDE workspace model mapping (CoW `desktop_size` vs CDE's set of named
  workspaces; how many desks, names, per-output).
* How to keep per-client synthesized properties up to date as the model changes
  (the shim builds them at connect time; live updates go through
  `DtWorkspace_Modified`).
* Whether the panel should talk to the WSM via dtwm's own ToolTalk (making dtwm
  the WSM) or via the bridge directly.

## Non-goals

* Do not modify the CDE Help Viewer or other CDE application source.
* Do not rewrite the Front Panel (`dtwm.fp`, its Motif UI).
