# Patch overlays

Small diffs applied by [`../scripts/build-cde.sh`](../scripts/build-cde.sh) to a
pristine source tree:

    patch -p1 --forward --batch -d "$CDE_BUILD" < <patch>

The source tree is never edited in place, and the long-term goal is to carry
none of these — they exist to be landed upstream.

Each patch modifies **another project**, so it carries *that* project's licence
rather than this repository's MIT.  The SPDX tag and a change notice are at the
top of every file.

## CDE patches — `LGPL-2.0-or-later`

CDE is released under the GNU Lesser General Public License, version 2.0 or (at
your option) any later version, and its `COPYING` states plainly that
modifications to CDE must be made available under the same terms.  These
patches do so.

| Patch | Modification |
|---|---|
| `dtappgather-target.patch` | let `dtappgather` gather into a writable directory |
| `dtsession-vfork-exit.patch` | `_exit` in `vfork` children (libpixman destructor crash) |
| `dtstyle-startup.patch` | record the Style Manager Startup choices where the Wayland session and `cde-logout` can read them, and save the home session Wayland-side |
| `dtsvc-backdrop.patch` | run `cde-wsm-backdrop` when the Style Manager changes the backdrop |
| `dtsvc-logfiles-top.patch` | allow `CDE_LOGFILES_TOP` from the environment (`dtspcd`) |
| `dtwm-empty-clientlist.patch` | do not dereference an empty client list |
| `dtwm-subpanel-unpost.patch` | unmap a sub-panel instead of `CallWmFunction(F_Kill)` |
| `dtwm-wsm-desk.patch` | drive CoW's desks from dtwm |
| `dtwm-wsm-list.patch` | read CoW's desks from dtwm |
| `rpccmsd-nonroot.patch` | key the private calendar spool off `CDE_CMSD_DIR`, not `euid` |
| `srvpalette-pixel-set.patch` | the colour server publishes the current pixel set instead of appending, so applications get a usable palette |

## CoW patches — `ISC`

CoW is released under the ISC License (Copyright (c) 2026 Thomas Adam).  The
patches retain the upstream notice and are made available under the same terms.

| Patch | Modification |
|---|---|
| `cow-decoration-hint.patch` | honour MWM decoration hints |
| `cow-transient-stacking.patch` | transient stacking |
