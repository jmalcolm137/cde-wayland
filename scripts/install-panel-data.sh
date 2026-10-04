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
        strip_nls "$f" > "$CDE_ROOT/appconfig/types/C/$b"
        # Also the locale-independent directory: DTDATABASESEARCHPATH's default
        # includes appconfig/types, and %L may not resolve to a directory we
        # installed (e.g. en_CA.UTF-8).  Without this, actions such as Terminal
        # are "not found".
        cp "$CDE_ROOT/appconfig/types/C/$b" "$CDE_ROOT/appconfig/types/$b"
    done
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

ok "panel data installed"
