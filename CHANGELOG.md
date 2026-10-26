# Changelog

## 1.0.0-rc1 — 2026-10-26

First release candidate.  A working CDE desktop on Wayland: River as the
compositor, CoW as the window manager, the real CDE Front Panel (`dtwm`,
contained) and CDE's applications, all native Wayland clients — no X server and
no Xwayland.

### Included

- **Shim** — `xlib-wayland`, a Wayland-native, ABI-compatible `libX11`, built
  here together with libXt and Open Motif.  Validated against stock libXt,
  Open Motif, XV, NEdit, GTK2/MATE, GIMP and Firefox.
- **Desktop** — Front Panel with its sub-panels, application launches through
  ToolTalk, per-workspace backdrops, the CDE palette relayed to every client and
  to CoW's own chrome, MWM-style cascading placement, minimized-window icons.
- **Workspace Manager** — the panel's One/Two/Three/Four buttons drive CoW's
  desks; the `DtWsm` protocol is served to applications; CDE's workspace and
  titlebar menus are provided as CoW menus.
- **Style Manager** — Backdrop, Keyboard, Font, Colour and Startup modules are
  wired to the session.
- **Drag and drop** — Motif DnD bridged through the compositor's drag and the
  cross-process selection broker, in both directions.
- **Reproducible build** — `versions.lock` pins every upstream to an exact
  commit (or, for River, a release tag); `make` builds the whole stack;
  `scripts/verify-pins.sh` and CI check that every pin still resolves.

### Pinned revisions

| Component | Revision |
|---|---|
| `xlib-wayland` | `bf07693` (main, 2026-10-15) |
| CDE (`lkujaw/cde`) | `e4b43aa1` (master) |
| CoW | `fd999be` (0.4 + version commit, 2026-10-25) |
| River | `v0.5.0` (tested as the Arch package, 0.5.0-1.1) |

### Known limitations

- **No login manager.**  `dtlogin` is not wired up; start the session from a TTY
  or another Wayland session.  A Wayland-hosted greeter reusing `dtgreet` is the
  intended shape.
- **Session restore is coarse.**  The Startup module picks the `current`/`home`
  store, but a session saves only a Wayland-side process marker — not window
  geometry or desks.
- **Mailer.**  `dtmail` needs a setgid `mail` group or a non-spool mailbox; a
  packaging item.
- **Front Panel Lock control** does not fire under CoW (the Workspace Menu's
  *Lock Screen* works).
- **Workspace Menu → Refresh** has no WSM equivalent; it is a no-op.
- **`.bm` backdrops** have no PNG conversion, so selecting one does nothing.
- **Application Manager** lists groups whose applications this tree does not
  ship.
- **Input methods** — only `ibus-engine-simple` is exercised; no real engine.
- **Shim gaps** — a few core entry points (`XSetAuthorization`, `XAddPixel`,
  `XSubImage`, …) and the `Xss`, multi-screen Xinerama and `Xp` extensions.
- **XEmbed** cross-process embedding remains a Wayland limit.
- Validated nested inside a Wayland session; a real-seat (DRM/input) run is not
  yet part of CI.

### Reproducing

```sh
git clone https://github.com/jmalcolm137/cde-wayland
cd cde-wayland
make            # fetch the pinned sources, build and install the stack
```

Everything installs under `$HOME/.local/cde-wayland`; no root is required.
