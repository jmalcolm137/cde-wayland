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
Right-clicking the desktop must open the CDE Workspace Manager menu, not CoW's
`CDEApps` menu. CDE's own root menu (`DtRootMenu`, bound to `<Btn3Down> root`)
is the primary place the Workspace Manager presents itself:

* **Workspace Menu** title;
* **Previous Workspace** / **Next Workspace** (`f.circle_up` / `f.circle_down`);
* **Refresh** (`f.refresh`), **Minimize/Restore Front Panel**
  (`f.toggle_frontpanel`), **Restart Workspace Manager…** (`f.restart`),
  **Log out…** (`f.action ExitSession`).

Implementation options, in order of preference:
1. Have CoW's menu system load dtwm's `builtinRootMenu`/`sys.dtwmrc` menu
   definition and dispatch its entries to the WSM (switch/add/delete) and CoW
   (window ops). This keeps one menu engine.
2. Bridge CoW's root menu to the WSM: build an equivalent CDE-styled menu and
   route the workspace entries over `DtWsm`. **In use:** `config/cow.conf`
   defines the `CDEWorkspace` menu and binds `mouse R:0+right` to it; its
   Previous/Next entries `exec cde-wsm prev|next`, and `cde-wsm` asks dtwm (the
   WSM) to change workspaces via `DtWsmSetCurrentWorkspace`, so the Front Panel
   follows. `Refresh`/`Restart`/`Log out` are dtwm functions with no WSM
   equivalent yet and are still open.
3. Run real dtwm's menu on the desktop: dtwm cannot see the root (private X
   server), so this needs the shim to hand dtwm the root menu's clicks — only if
   1 and 2 prove too limited.

**3b. CDE titlebar menu (done).** CoW's `CDEWindow` menu (`config/cow.conf`)
mirrors dtwm's `builtinSystemMenu`: Restore / Move / Size / Minimize / Maximize
/ Lower, a separator, Occupy Workspace… (CoW's dynamic `SendToDesk` submenu) /
Occupy All Workspaces, a separator, Close. It is posted by the left titlebar
button (`bind-decoration 1`) and by Alt+Space, and its actions target the
decorated window.

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

## Progress log

* **Shim — synthetic WM window (done).** A WM window is a direct child of the
  root with `_MOTIF_WM_INFO` on the root and `_DT_WORKSPACE_LIST` /
  `_DT_WORKSPACE_CURRENT` on it, so `DtWsmGetWorkspaceList` /
  `DtWsmGetCurrentWorkspace` succeed. dtwm opts out with `CDE_NO_WM_INFO` (it
  checks `_MOTIF_WM_INFO` to decide whether a WM is already running).
* **Shim — shared atoms (done).** Custom atoms are stored in a name<->id table
  under `$XDG_RUNTIME_DIR` and loaded/extended by every client, so an atom id
  passed between processes keeps its meaning. Without this dtwm read the
  client's `ws2` as a different atom and never resolved the workspace.
* **dtwm WSM + bridge (done).** `dtwm` runs with ToolTalk (its WSM pattern
  registers; verified), and `ChangeToWorkspace()` runs `cde-wsm-desk <n>`, which
  records the current workspace for the shim. A `DtWsmSetCurrentWorkspace` is
  delivered, resolved (`ws2` -> the workspace) and handled.
* **CoW desk switch + backdrop (done).** `cde-wsm-desk` runs `moocow desk -d N`,
  which moves the visible desk (windows on the old desk are hidden). dtwm maps a
  per-workspace **backdrop** as a full-screen override-redirect window on each
  switch; the shim now keeps a screen-covering override-redirect window out of
  the Wayland tree instead of promoting it as a popup (it was painting the whole
  output white). The Front Panel's switch highlight follows the change too.
* **Step 1 done.** Switching workspaces from the Front Panel moves CoW's desk,
  the panel reflects it, and every client's `DtWsmGetCurrentWorkspace` agrees.
* **Step 3b — CDE window menu (done).** The `CDEWindow` menu mirrors dtwm's
  `builtinSystemMenu` (Restore/Move/Size/Minimize/Maximize/Lower/Occupy
  Workspace…/Occupy All Workspaces/Close) and is posted by the left titlebar
  button and Alt+Space. Verified: *Close* in the menu closed the dtterm it was
  opened on.
* **Step 3a — desktop Workspace Manager menu (core done).** Right-clicking the
  desktop now posts a CDE-style **Workspace Menu** (CoW's `CDEWorkspace` menu in
  `config/cow.conf`, replacing the app menu on Btn3). Its **Previous/Next
  Workspace** entries run `cde-wsm` (`tools/cde-wsm.c`), which lists the
  workspaces via `DtWsmGetWorkspaceList` and changes with
  `DtWsmSetCurrentWorkspace` — so dtwm performs the switch and the Front Panel
  highlight follows, rather than CoW moving on its own. Verified: clicking
  *Next Workspace* moved `current` ws1→ws2 and CoW's desk with it.

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
