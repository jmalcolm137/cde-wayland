#!/usr/bin/env bash
# install-panel-data.sh — install the data the real CDE Front Panel needs.
#
# The Front Panel is dtwm's (see DESIGN.md §5.2).  Running it as a contained
# panel needs the pieces CDE normally installs system-wide, relocated under our
# prefix:
#
#   - the Dtwm application defaults (useFrontPanel, panel layout, icons)
#   - the front-panel database  dtwm.fp  (controls/boxes/subpanels)
#   - the icon pixmaps          $CDE_ROOT/appconfig/icons/C/
#   - the system dtwm config    $CDE_ROOT/config/sys.dtwmrc
#   - the ToolTalk session daemon ttsession
#
# Source artefacts come from the CDE build tree produced by build-cde.sh.
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib.sh"

[ -d "$CDE_BUILD" ] || die "no CDE build tree at $CDE_BUILD; run scripts/build-cde.sh"

DTWM_DIR="$CDE_BUILD/programs/dtwm"
TYPES_DIR="$CDE_BUILD/programs/types"
ICONS_DIR="$CDE_BUILD/programs/icons"

log "installing CDE Front Panel data"
printf '    prefix : %s\n' "$CDE_PREFIX"
printf '    root   : %s\n' "$CDE_ROOT"

# 0. The panel is dtwm itself, run as a contained panel (see DESIGN.md §5.2),
#    plus the ToolTalk session daemon it talks to.
if [ -x "$DTWM_DIR/dtwm" ]; then
    install -D -m 0755 "$DTWM_DIR/dtwm" "$CDE_PREFIX/bin/dtwm"
    ok "installed dtwm (Front Panel)"
else
    die "dtwm not built; run the 'panel' stage of build-cde.sh"
fi
[ -x "$DTWM_DIR/dtfplist" ] && install -D -m 0755 "$DTWM_DIR/dtfplist" \
    "$CDE_PREFIX/bin/dtfplist"

# Workspace Manager bridge: dtwm's workspace changes switch CoW's desks and
# record the current workspace for the shim's synthetic WM window.
if [ -f "$PROJECT_ROOT/scripts/cde-wsm-desk.sh" ]; then
    install -D -m 0755 "$PROJECT_ROOT/scripts/cde-wsm-desk.sh" \
        "$CDE_PREFIX/bin/cde-wsm-desk"
    ok "installed cde-wsm-desk (Workspace Manager bridge)"
fi

# Workspace Manager client: runs dtwm's own workspace functions (the root
# menu's Previous/Next Workspace) by asking the WSM to change, so the Front
# Panel and every other client stay in step.  Compiled here rather than added
# to the CDE tree because it is a cde-wayland helper, not part of CDE.
if [ -f "$PROJECT_ROOT/tools/cde-wsm.c" ]; then
    if "${CC:-gcc}" -o "$CDE_PREFIX/bin/cde-wsm" "$PROJECT_ROOT/tools/cde-wsm.c" \
            -I"$CDE_PREFIX/dt/include" -I"$CDE_PREFIX/include" -I/usr/include/tirpc \
            -L"$CDE_PREFIX/dt/lib" -L"$CDE_PREFIX/lib" \
            -lDtSvc -ltt -lXm -lXt -lX11 \
            -Wl,-rpath,"$CDE_PREFIX/lib:$CDE_PREFIX/dt/lib" 2>/dev/null; then
        ok "installed cde-wsm (Workspace Manager client)"
    else
        warn "could not build cde-wsm; CoW's workspace menu will not work"
    fi
fi

# Root-menu helpers: "Restart Workspace Manager..." and "Log out...".
for h in cde-restart-dtwm.sh cde-logout.sh cde-toggle-frontpanel.sh cde-wsm-backdrop.sh cde-motif-apply.sh; do
    [ -f "$PROJECT_ROOT/scripts/$h" ] || continue
    install -D -m 0755 "$PROJECT_ROOT/scripts/$h" \
        "$CDE_ROOT/bin/$(basename "$h" .sh)"
done
ok "installed root-menu helpers (restart / logout)"

# Calendar Manager service for dtcm.  The build overlay (patches/) lets it run
# as the user with a private spool directory.
if [ -x "$CDE_BUILD/programs/dtcm/server/rpc.cmsd" ]; then
    install -D -m 0755 "$CDE_BUILD/programs/dtcm/server/rpc.cmsd" \
        "$CDE_ROOT/bin/rpc.cmsd"
    ok "installed rpc.cmsd (Calendar Manager service)"
else
    warn "rpc.cmsd not built; dtcm will report the calendar service missing"
fi

if [ -x "$CDE_BUILD/lib/tt/bin/ttsession/ttsession" ]; then
    install -D -m 0755 "$CDE_BUILD/lib/tt/bin/ttsession/ttsession" \
        "$CDE_PREFIX/bin/ttsession"
    ok "installed ttsession"
else
    warn "ttsession not built; run the 'panel' stage of build-cde.sh"
fi

# 1. Application defaults.  Xt looks the class up by filename, so Dtwm.defs
#    becomes .../app-defaults/Dtwm.
# CDE wraps translatable strings as %|nls-N-#Text#| (or %|nls-N-VALUE^hint|).
# Without the message catalogs the wrapper is shown literally, so resolve it to
# the embedded default text at install time.
strip_nls() {
    sed -E -e 's/%\|nls-[0-9]+-#([^#]*)#\|/\1/g' \
           -e 's/%\|nls-[0-9]+-([^^|]*)\^[^|]*\|/\1/g' "$1"
}

mkdir -p "$CDE_PREFIX/share/X11/app-defaults"
if [ -s "$DTWM_DIR/Dtwm.defs" ]; then
    strip_nls "$DTWM_DIR/Dtwm.defs" > "$CDE_PREFIX/share/X11/app-defaults/Dtwm"
    chmod 0644 "$CDE_PREFIX/share/X11/app-defaults/Dtwm"
    ok "installed Dtwm app-defaults (nls labels resolved)"
else
    die "Dtwm.defs is missing/empty; run the 'panel' stage of build-cde.sh"
fi

# 1b. The other CDE applications' own defaults.  These matter for behaviour, not
# just looks: Dtfile's `Dtfile*DtIcon*behavior: icon_drag` is what makes the
# File Manager open a folder on double-click (without it the DtIcon widget
# defaults to XmICON_BUTTON and fires XmCR_ACTIVATE, which dtfile ignores).  The
# build leaves the C-locale files in localized/C/app-defaults; each starts with
# `#include "Dt"` for the shared desktop defaults, but the shim's Xrm parser
# ignores #directives, so inline that include here.  Dtwm is installed above.
_ap_src="$CDE_BUILD/programs/localized/C/app-defaults"
if [ -d "$_ap_src" ]; then
    for _f in "$_ap_src"/*; do
        _b="$(basename "$_f")"
        case "$_b" in
            *.nls|*.tmsg|Imakefile|Makefile|Makefile.bak|Dtwm) continue ;;
        esac
        [ -f "$_f" ] || continue
        _ap_tmp="$(mktemp)"
        awk -v dir="$_ap_src" '
            /^#include[ \t]+"/ {
                name = $0
                sub(/^#include[ \t]+"/, "", name)
                sub(/".*$/, "", name)
                while ((getline line < (dir "/" name)) > 0) print line
                close(dir "/" name)
                next
            }
            { print }
        ' "$_f" > "$_ap_tmp"
        strip_nls "$_ap_tmp" > "$CDE_PREFIX/share/X11/app-defaults/$_b"
        chmod 0644 "$CDE_PREFIX/share/X11/app-defaults/$_b"
        rm -f "$_ap_tmp"
    done
    ok "installed CDE application defaults (Dtfile, Dtterm, ...)"
fi

# 2. Front panel database.  _DtGetDatabaseDirPaths() searches
#    $CDE_ROOT/appconfig/types[/%L]; FrontPanelReadDatabases additionally
#    prepends $HOME/.dt/types/fp_dynamic.
if [ ! -s "$TYPES_DIR/dtwm.fp" ]; then
    ( cd "$TYPES_DIR" && rm -f dtwm.fp && \
      make CCOPTIONS="-std=gnu17" CDEBUGFLAGS="-O2 -g" dtwm.fp ) \
        || die "could not generate dtwm.fp"
fi
# Without CDE's message catalogs, `%|nls-NNNNN-#Text#|` labels would show
# literally.  Strip the wrapper so the default text is used.
_fp_tmp="$(mktemp)"
strip_nls "$TYPES_DIR/dtwm.fp" > "$_fp_tmp"
install -D -m 0644 "$_fp_tmp" "$CDE_ROOT/appconfig/types/C/dtwm.fp"
install -D -m 0644 "$_fp_tmp" "$CDE_ROOT/appconfig/types/dtwm.fp"
rm -f "$_fp_tmp"
mkdir -p "$HOME/.dt/types/fp_dynamic"
ok "installed dtwm.fp (nls labels resolved)"

# 2b. Regenerate any zero-length .dt.  These are produced by cpp from .dt.src;
#     an earlier build (before the CppCmd fix) left several empty, so actions
#     such as Terminal/TextEditor were undefined and the panel could not launch
#     anything.
_CPP="$(command -v cpp || true)"
if [ -n "$_CPP" ]; then
    for src in "$TYPES_DIR"/*.dt.src; do
        [ -f "$src" ] || continue
        out="${src%.src}"
        if [ ! -s "$out" ]; then
            "$_CPP" -DCDE_INSTALLATION_TOP="$CDE_ROOT" \
                    -DCDE_CONFIGURATION_TOP="$CDE_ROOT/config" < "$src" \
              | sed -e '/^#[line]* *[0-9][0-9]*  *.*$/d' \
                    -e '/^XCOMM$/s//#/' \
                    -e '/^XCOMM[^a-zA-Z0-9_]/s/^XCOMM/#/' > "$out"
            ok "regenerated $(basename "$out")"
        fi
    done
fi

# 2c. Action/datatype databases.  The panel controls name actions
#     (PUSH_ACTION Terminal, DtfileHome, ...); those are defined in .dt files
#     that _DtDbRead() looks up under $CDE_ROOT/appconfig/types.
if ls "$TYPES_DIR"/*.dt >/dev/null 2>&1; then
    mkdir -p "$CDE_ROOT/appconfig/types/C"
    for f in "$TYPES_DIR"/*.dt; do
        b="$(basename "$f")"
        # Action definitions hardcode the classic CDE prefix /usr/dt; rewrite
        # it to this installation's root so Dthelpview, DtPrint etc. find
        # their programs.
        strip_nls "$f" | sed "s|/usr/dt/|$CDE_ROOT/|g" \
            > "$CDE_ROOT/appconfig/types/C/$b"
        # Also the locale-independent directory: DTDATABASESEARCHPATH's default
        # includes appconfig/types, and %L may not resolve to a directory we
        # installed (e.g. en_CA.UTF-8).  Without this, actions such as Terminal
        # are "not found".
        cp "$CDE_ROOT/appconfig/types/C/$b" "$CDE_ROOT/appconfig/types/$b"
    done
    # LockDisplay is a ToolTalk request to dtsession (Display_Lock), which we do
    # not run.  Rewrite the action in the installed databases to start the
    # Wayland screen locker instead (River provides ext_session_lock_manager_v1,
    # which waylock uses).  A user-database override alone did not win for this
    # action.
    python3 - "$CDE_ROOT" <<'PY'
import os, re, sys
root = sys.argv[1]
new = ("ACTION LockDisplay\n{\n    LABEL Lock\n    TYPE COMMAND\n"
       "    WINDOW_TYPE NO_STDIO\n    EXEC_STRING /bin/sh -c 'exec waylock'\n}\n")
pat = re.compile(r'ACTION\s+LockDisplay\s*\{[^{}]*\}')
count = 0
for dirpath, _, files in os.walk(os.path.join(root, 'appconfig', 'types')):
    for fn in files:
        if not fn.endswith('.dt'):
            continue
        p = os.path.join(dirpath, fn)
        s = open(p).read()
        if 'LockDisplay' not in s:
            continue
        s2 = pat.sub(new, s)
        if s2 != s:
            open(p, 'w').write(s2)
            count += 1
print("      rewrote LockDisplay in %d database file(s)" % count)
PY
    ok "installed $(ls "$TYPES_DIR"/*.dt | wc -l) action/datatype databases"
else
    warn "no .dt databases in $TYPES_DIR; panel actions may not resolve"
fi

# 2d. ToolTalk static process types.  ttsession loads these (".xdr" database)
#     from /etc/tt/types.xdr or $HOME/.tt/types.xdr; without them every CDE
#     ptype (DtFile, DtMail, ...) is unknown and clients fail with
#     TT_ERR_PTYPE ("not the name of a process type").
if [ -s "$CDE_BUILD/programs/tttypes/types.xdr" ]; then
    install -D -m 0644 "$CDE_BUILD/programs/tttypes/types.xdr" \
        "$HOME/.tt/types.xdr"
    ok "installed ToolTalk process types (~/.tt/types.xdr)"
else
    warn "types.xdr not built; ToolTalk apps may report unknown process types"
fi

# 3. Icons.  The default XMICONSEARCHPATH built by _DtEnvControl() expands to
#    $CDE_ROOT/appconfig/icons/%L/%B%M.pm, where %B is the base name and %M the
#    size modifier (l/m/s/t).
if [ -d "$ICONS_DIR" ]; then
    mkdir -p "$CDE_ROOT/appconfig/icons/C"
    cp -a "$ICONS_DIR/." "$CDE_ROOT/appconfig/icons/C/" 2>/dev/null || true
    ok "installed icons ($(ls "$CDE_ROOT/appconfig/icons/C" | wc -l) files)"
else
    warn "no icons directory in the build tree"
fi

# 4. System dtwm config (button bindings etc.).  Optional: the panel works
#    without it, but it holds the standard window-menu definitions.
for c in "$DTWM_DIR/sys.dtwmrc" "$DTWM_DIR/sys.dtwmrc.src"; do
    if [ -s "$c" ]; then
        mkdir -p "$CDE_ROOT/config"
        strip_nls "$c" > "$CDE_ROOT/config/sys.dtwmrc"
        chmod 0644 "$CDE_ROOT/config/sys.dtwmrc"
        ok "installed sys.dtwmrc from $(basename "$c") (nls labels resolved)"
        break
    fi
done

# Per-workspace backdrop map, applied by the WSM bridge (cde-wsm-desk).
if [ -f "$PROJECT_ROOT/config/backdrops.conf" ]; then
    install -D -m 0644 "$PROJECT_ROOT/config/backdrops.conf" \
        "$CDE_ROOT/config/backdrops.conf"
    ok "installed per-workspace backdrops"
fi

# Backdrop images + descriptions for the Style Manager (dtstyle).  dtstyle
# looks in /usr/dt/backdrops and $HOME/.dt/backdrops; we cannot write /usr/dt,
# so install into the user directory it also reads.
if [ -d "$CDE_BUILD/programs/backdrops" ]; then
    install -d "$HOME/.dt/backdrops" "$CDE_ROOT/backdrops"
    cp -f "$CDE_BUILD/programs/backdrops"/* "$HOME/.dt/backdrops/" 2>/dev/null || true
    cp -f "$CDE_BUILD/programs/backdrops"/* "$CDE_ROOT/backdrops/" 2>/dev/null || true
    # CDE's .pm backdrops are XPM format; CoW only accepts .xpm, so keep a copy
    # with that extension (cde-wsm-backdrop maps .pm -> .xpm).
    for f in "$CDE_BUILD/programs/backdrops"/*.pm; do
        [ -f "$f" ] || continue
        cp -f "$f" "$HOME/.dt/backdrops/$(basename "$f" .pm).xpm"
        cp -f "$f" "$CDE_ROOT/backdrops/$(basename "$f" .pm).xpm"
    done
    if [ -s "$CDE_BUILD/programs/dtstyle/Backdrops" ]; then
        strip_nls "$CDE_BUILD/programs/dtstyle/Backdrops" \
            > "$HOME/.dt/backdrops/desc.backdrops"
    fi
    ok "installed Style Manager backdrops ($(ls "$HOME/.dt/backdrops" | wc -l) files)"
fi

# 5. Help volumes.  DTHELPSEARCHPATH is $CDE_ROOT/help/%L/%T/%N%S with
#    %T == "volumes", so the SDL volumes live in help[/<locale>]/volumes/.
#    Build them with scripts/build-help.sh (needs ksh + nsgmls).
if ls "$CDE_BUILD/doc/help-sdl"/*.sdl >/dev/null 2>&1; then
    mkdir -p "$CDE_ROOT/help/volumes" "$CDE_ROOT/help/C/volumes"
    cp "$CDE_BUILD/doc/help-sdl"/*.sdl "$CDE_ROOT/help/volumes/"
    cp "$CDE_BUILD/doc/help-sdl"/*.sdl "$CDE_ROOT/help/C/volumes/"
    # The SDL references its art as "./<Volume>/graphics/<file>", so each
    # volume's graphics live in a sibling directory named after the volume.
    for g in "$CDE_BUILD/doc/C/help"/*/graphics; do
        [ -d "$g" ] || continue
        v="$(basename "$(dirname "$g")")"
        mkdir -p "$CDE_ROOT/help/volumes/$v/graphics" \
                 "$CDE_ROOT/help/C/volumes/$v/graphics"
        cp -a "$g/." "$CDE_ROOT/help/volumes/$v/graphics/"
        cp -a "$g/." "$CDE_ROOT/help/C/volumes/$v/graphics/"
    done
    ok "installed $(ls "$CDE_ROOT/help/volumes"/*.sdl 2>/dev/null | wc -l) help volumes + graphics"
else
    warn "no help volumes built; run scripts/build-help.sh to install Help"
fi

# 6. Information Manager.  dtinfo browses MMDB infolibs (built by
#    scripts/build-infolib.sh), not the SDL help volumes dthelpview uses.
#    Install the browser, its ToolTalk start helper and the cde infolib, and
#    give the Front Panel's InfoManager button an action that runs it (the
#    DtInfo ptype auto-start does not fire in this session).
if [ -x "$CDE_BUILD/programs/dtinfo/dtinfo/src/dtinfo" ]; then
    install -D -m 0755 "$CDE_BUILD/programs/dtinfo/dtinfo/src/dtinfo" \
        "$CDE_ROOT/bin/dtinfo"
    install -D -m 0755 "$CDE_BUILD/programs/dtinfo/clients/dtinfo_start/dtinfo_start" \
        "$CDE_ROOT/infolib/etc/dtinfo_start"
    if [ -d "$CDE_BUILD/doc/C/cde.dti" ]; then
        for loc in C ${LANG:-} en_US.UTF-8; do
            [ -n "$loc" ] || continue
            install -d "$CDE_ROOT/appconfig/infolib/$loc"
            rm -rf "$CDE_ROOT/appconfig/infolib/$loc/cde.dti"
            cp -a "$CDE_BUILD/doc/C/cde.dti" "$CDE_ROOT/appconfig/infolib/$loc/cde.dti"
        done
        ok "installed dtinfo + the cde infolib"
    else
        warn "cde.dti not built; run scripts/build-infolib.sh for the InfoManager"
    fi
    # Overlay action definitions (run programs we have locally instead of the
    # dtsession/ToolTalk services we do not run).
    for dt in "$PROJECT_ROOT"/config/dtwm-types/*.dt; do
        [ -f "$dt" ] || continue
        install -D -m 0644 "$dt" "$HOME/.dt/types/$(basename "$dt")"
    done
    ok "installed action overlays into ~/.dt/types"
    # dtinfo declares the DtInfo process type; the base types.xdr has no DtInfo
    # entry, and its start path is the classic /usr/dt.  Merge a copy with the
    # path rewritten to this prefix into the user database.
    _ttc="$CDE_ROOT/bin/tt_type_comp"
    _ptype="$CDE_BUILD/programs/tttypes/dtinfo.ptype"
    if [ -x "$_ttc" ] && [ -f "$_ptype" ]; then
        cpp -I"$CDE_BUILD/programs/tttypes" "$_ptype" 2>/dev/null \
            | sed "s|/usr/dt|$CDE_ROOT|g" > "$CDE_ROOT/infolib/etc/dtinfo.ptype"
        "$_ttc" -sd user -m "$CDE_ROOT/infolib/etc/dtinfo.ptype" >/dev/null 2>&1 \
            && ok "installed the DtInfo process type" \
            || warn "could not install the DtInfo process type"
    fi
else
    warn "dtinfo not built; the InfoManager button will do nothing"
fi

ok "panel data installed"
