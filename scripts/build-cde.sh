#!/usr/bin/env bash
# build-cde.sh — build CDE (the imake tree) against the Wayland libX11 shim.
#
# The pristine CDE source is never modified: we rsync it into $CDE_BUILD and do
# all work there.  The only CDE "configuration" is host.def (imake's sanctioned
# local-config file), generated from config/cde-host.def.in.
#
# Usage:
#   build-cde.sh [--refresh] [--prefix=DIR] [STAGE...]
#
# Stages (default: libs):
#   prepare     rsync source -> build tree, write host.def
#   imake       build CDE's bundled imake (unless a system imake exists)
#   makefiles   run imake to generate Makefiles everywhere
#   includes    install CDE headers into the build tree
#   libs        build include/ and lib/
#   programs    build the leaf applications that work without dtsession
#   panel       build the real CDE Front Panel (dtwm) + its data + ttsession
#   install     install what has been built into $CDE_ROOT
#   all         prepare imake makefiles includes libs
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib.sh"

REFRESH=0
STAGES=()
for arg in "$@"; do
    case "$arg" in
        --refresh)  REFRESH=1 ;;
        --prefix=*) CDE_PREFIX="${arg#*=}"; export CDE_PREFIX
                    CDE_ROOT="$CDE_PREFIX/dt"; export CDE_ROOT ;;
        -h|--help)  sed -n '2,28p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*)         die "unknown option: $arg" ;;
        *)          STAGES+=("$arg") ;;
    esac
done
[ "${#STAGES[@]}" -eq 0 ] && STAGES=(libs)

# Tools unpacked by fetch-sources.sh (e.g. rpcgen) live in the prefix.
[ -d "$CDE_PREFIX/tools" ] && export PATH="$CDE_PREFIX/tools:$PATH"

# The lkujaw/cde repository root contains the CDE tree in a `cde/` subdirectory.
CDE_TREE="$CDE_SRC"
[ -d "$CDE_TREE/cde" ] && CDE_TREE="$CDE_SRC/cde"
[ -f "$CDE_TREE/Imakefile" ] || die "no CDE Imakefile under $CDE_SRC (run fetch-sources.sh)"

CPP_BIN="${CPP_BIN:-$(command -v /usr/bin/cpp || command -v cpp || true)}"
[ -n "$CPP_BIN" ] || die "no C preprocessor found"

# Modern GCC made several C89-era diagnostics hard errors.  CDE is K&R-era
# code and also needs -fcommon (tentative definitions), so we override the
# vendor CCOPTIONS (-ansi) on the make command line rather than editing CDE.
CDE_CCOPTIONS="-std=gnu17 -fcommon -Wno-implicit-function-declaration \
-Wno-int-conversion -Wno-incompatible-pointer-types -Wno-return-mismatch \
-Wno-implicit-int -Wno-builtin-declaration-mismatch"
CDE_CXXOPTIONS="-std=gnu++17 -fcommon -fpermissive \
-Wno-implicit-function-declaration -Wno-int-conversion \
-Wno-incompatible-pointer-types -Wno-return-mismatch"
CDE_CDEBUGFLAGS="-O2 -g -fno-strict-aliasing"
CDE_CXXDEBUGFLAGS="-O2 -g -fno-strict-aliasing"

# Command-line make variables propagate to every recursive make via MAKEFLAGS.
# AR: GNU binutils 2.47 repurposed the `l` modifier to take an argument, so
# the classic `ar clq` (imake's default) no longer parses; `ar crs` is the
# modern equivalent and still creates the index.
MAKE_OVERRIDES=(
    "CCOPTIONS=$CDE_CCOPTIONS"
    "CXXOPTIONS=$CDE_CXXOPTIONS"
    "CDEBUGFLAGS=$CDE_CDEBUGFLAGS"
    "CXXDEBUGFLAGS=$CDE_CXXDEBUGFLAGS"
    "AR=ar crs"
)

stage_prepare() {
    log "preparing CDE build tree"
    printf '    source : %s\n' "$CDE_TREE"
    printf '    build  : %s\n' "$CDE_BUILD"

    local rev="unknown"
    command -v git >/dev/null 2>&1 && rev="$(git -C "$CDE_SRC" rev-parse HEAD 2>/dev/null || echo unknown)"

    if [ "$REFRESH" -eq 1 ] || [ ! -f "$CDE_BUILD/.source-rev" ] || \
       [ "$(cat "$CDE_BUILD/.source-rev" 2>/dev/null)" != "$rev" ]; then
        require_cmd rsync
        mkdir -p "$CDE_BUILD"
        rsync -a --delete --exclude '.git/' "$CDE_TREE/" "$CDE_BUILD/"
        printf '%s\n' "$rev" > "$CDE_BUILD/.source-rev"
    else
        log "build tree is current ($rev); use --refresh to re-copy"
    fi

    sed -e "s|@CDE_PREFIX@|$CDE_PREFIX|g" \
        -e "s|@CDE_ROOT@|$CDE_ROOT|g" \
        -e "s|@CPP@|$CPP_BIN|g" \
        "$PROJECT_ROOT/config/cde-host.def.in" > "$CDE_BUILD/config/cf/host.def"

    # linux.cf defines CppCmd /lib/cpp unconditionally, after host.def is
    # read, so the generated Makefiles bake in a path that does not exist on
    # modern systems.  Fix it in the build tree (pristine source untouched).
    sed -i -E "s|^([[:space:]]*#define[[:space:]]+CppCmd[[:space:]]+).*|\\1$CPP_BIN|" \
        "$CDE_BUILD/config/cf/linux.cf"

    # Some CDE programs (dtcm, dthello) #include Open Motif's Xm bitmaps
    # (X11/bitmaps/xm_error, xm_information, ...).  Motif's install does not
    # always install them, so copy them from the Motif source into the prefix.
    local mb="$MOTIF_SRC/bitmaps"
    if [ -d "$mb" ]; then
        mkdir -p "$CDE_PREFIX/include/X11/bitmaps"
        cp -n "$mb"/* "$CDE_PREFIX/include/X11/bitmaps/" 2>/dev/null || true
        ok "host.def written; CppCmd -> $CPP_BIN; Motif bitmaps copied"
    else
        warn "no Motif bitmaps at $mb; dtcm/dthello may fail to compile"
        ok "host.def written; CppCmd -> $CPP_BIN"
    fi

    # The only CDE source changes: the build overlays under patches/.  They let
    # the Front Panel run without ToolTalk (skip dtwm's messaging init; execute
    # actions locally).  Applied to the build tree only; source stays pristine.
    local p
    for p in "$PROJECT_ROOT"/patches/*.patch; do
        [ -f "$p" ] || continue
        if patch -p1 --forward --batch -d "$CDE_BUILD" < "$p" >/dev/null 2>&1; then
            ok "applied $(basename "$p")"
        else
            warn "patch $(basename "$p") did not apply (already applied?)"
        fi
    done
}

IMAKE_BIN=""

# ensure_imake: reuse an existing build, else bootstrap; fall back to a system
# imake if one is present and the bundled one cannot be built.
ensure_imake() {
    if [ -n "$IMAKE_BIN" ] && [ -x "$IMAKE_BIN" ]; then return; fi
    if [ -x "$CDE_BUILD/config/imake/imake" ]; then
        IMAKE_BIN="$CDE_BUILD/config/imake/imake"
        return
    fi
    if command -v imake >/dev/null 2>&1; then
        warn "using system imake: $(command -v imake)"
        IMAKE_BIN="$(command -v imake)"
        return
    fi
    stage_imake
}

stage_imake() {
    log "building CDE's bundled imake"
    local src="$CDE_BUILD/config/imake"
    # BOOTSTRAPCFLAGS is exactly how imake's own bootstrap is told where cpp
    # is; the vendor config hardcodes /lib/cpp, which does not exist here.
    make -C "$src" -f Makefile.ini clean >/dev/null 2>&1 || true
    # The inner quotes must reach the compiler as part of the macro's
    # replacement text (imake.c does `DEFAULT_CPP CPP_PROGRAM`), so escape
    # them twice: once for make, once for the shell running the recipe.
    make -C "$src" -f Makefile.ini \
        CC="${CC:-gcc}" CDEBUGFLAGS="-O2" \
        BOOTSTRAPCFLAGS="-DCPP_PROGRAM=\\\"$CPP_BIN\\\"" 2>&1 | sed 's/^/    /'
    IMAKE_BIN="$src/imake"
    [ -x "$IMAKE_BIN" ] || die "imake bootstrap failed"
    ok "imake built at $IMAKE_BIN"
}

imake_cmd() {
    # Mirrors the top Makefile's IMAKE_CMD: -I<rulesrc> -DTOPDIR -DCURDIR.
    "$IMAKE_BIN" -I"$CDE_BUILD/config/cf" -DTOPDIR=. -DCURDIR=. "$@"
}

stage_makefiles() {
    ensure_imake
    log "generating xmakefile and all Makefiles"
    ( cd "$CDE_BUILD" && imake_cmd -s xmakefile )
    ( cd "$CDE_BUILD" && make -f xmakefile Makefiles )
    ok "Makefiles generated"
}

stage_includes() {
    log "installing CDE headers"
    ( cd "$CDE_BUILD" && make "${MAKE_OVERRIDES[@]}" -f xmakefile includes )
    ok "headers installed"
}

stage_libs() {
    log "building CDE base libraries (include/ + lib/)"
    # lib/csa's rpcgen outputs (agent.h/agent_xdr.c and the rtable*/cm client
    # and XDR stubs) are generated by rules with no prerequisites, so a stale
    # half-written file -- e.g. one produced before rpcgen was available -- is
    # never rebuilt, leaving libcsa (and therefore dtcm) without its XDR
    # symbols.  Remove them and let make regenerate them now.
    rm -f "$CDE_BUILD/lib/csa/agent.h" "$CDE_BUILD/lib/csa/agent_xdr.c" \
          "$CDE_BUILD/lib/csa"/rtable2_xdr.c "$CDE_BUILD/lib/csa"/rtable3_xdr.c \
          "$CDE_BUILD/lib/csa"/rtable4_xdr.c \
          "$CDE_BUILD/lib/csa"/rtable2_clnt.c "$CDE_BUILD/lib/csa"/rtable3_clnt.c \
          "$CDE_BUILD/lib/csa"/rtable4_clnt.c "$CDE_BUILD/lib/csa"/cm_clnt.c \
          "$CDE_BUILD/lib/csa"/reparser.c "$CDE_BUILD/lib/csa"/reparser.h
    ( cd "$CDE_BUILD/include" && make "${MAKE_OVERRIDES[@]}" )
    ( cd "$CDE_BUILD/lib"     && make "${MAKE_OVERRIDES[@]}" -j"$JOBS" )
    ok "CDE libraries built"
}

stage_programs() {
    log "building CDE applications"
    local prog
    for prog in dtcalc dtpad dthello dtstyle dtcm dtterm dtfile dthelp dtprintinfo dtaction dtexec dtsearchpath; do
        [ -d "$CDE_BUILD/programs/$prog" ] || continue
        log "  make -C programs/$prog"
        # Some programs generate headers under the `includes` target that the
        # objects need but `make` (all) does not depend on (dtprintinfo's
        # dtprintinfo_msg.h), so build includes first.
        ( cd "$CDE_BUILD/programs/$prog" && make "${MAKE_OVERRIDES[@]}" includes >/dev/null 2>&1 || true )
        ( cd "$CDE_BUILD/programs/$prog" && make "${MAKE_OVERRIDES[@]}" -j"$JOBS" ) \
            || warn "programs/$prog failed (see the build log above)"
    done
}

# The CDE Front Panel is dtwm's; build it (unmodified) plus the panel database
# and the ToolTalk session daemon it needs.  dtwm runs as a contained panel
# under CoW, never as the session's window manager (see DESIGN.md §5.2).
stage_panel() {
    log "building the real CDE Front Panel (dtwm) and its data"
    # Remove stale half-generated files: the cpp rules only regenerate a target
    # that is missing, and an earlier build (before CppCmd was corrected) left
    # zero-length Dtwm.defs/dtwm.fp behind.
    rm -f "$CDE_BUILD/programs/dtwm/Dtwm.defs" \
          "$CDE_BUILD/programs/dtwm/sys.dtwmrc" \
          "$CDE_BUILD/programs/types/dtwm.fp"
    # Empty .dt files (cpp output lost before CppCmd was corrected) hide the
    # action definitions the panel needs.
    find "$CDE_BUILD/programs/types" -maxdepth 1 -name '*.dt' -size 0 -delete 2>/dev/null || true
    local sub
    for sub in programs/dtwm programs/types lib/tt/bin/ttsession; do
        [ -d "$CDE_BUILD/$sub" ] || continue
        log "  make -C $sub"
        ( cd "$CDE_BUILD/$sub" && make "${MAKE_OVERRIDES[@]}" -j"$JOBS" ) \
            || warn "$sub failed (see the build log above)"
    done
    ok "panel built (dtwm + dtwm.fp + ttsession)"
    # The Information Manager (dtinfo) browses the CDE documentation as an MMDB
    # infolib; build it so install-panel-data.sh can install it.  Best-effort:
    # the panel works without it.
    "$SCRIPT_DIR/build-infolib.sh" || warn "infolib build failed (InfoManager content)"
    log "installing panel data"
    "$SCRIPT_DIR/install-panel-data.sh" || warn "panel data install failed"
}

stage_install() {
    log "installing CDE into $CDE_ROOT"
    ( cd "$CDE_BUILD/include" && make "${MAKE_OVERRIDES[@]}" install ) || warn "include install failed"
    ( cd "$CDE_BUILD/lib"     && make "${MAKE_OVERRIDES[@]}" install ) || warn "lib install failed"
    # The Front Panel launches these by name from PATH, so they must land in
    # $CDE_ROOT/bin.  dtaction is CDE's action-invocation CLI; dtexec is the
    # "command invoker" sub-process the action machinery execs for every
    # command action (<prefix>/bin/dtexec -open 0 -ttprocid ...).  Without it
    # no action that goes through the normal path can run.  dtsearchpath builds
    # dtsp (sets the DT*SEARCHPATH variables) and dtappgather (dtappg), which
    # builds the Application Manager's application groups.
    local p
    for p in dtcalc dtpad dthello dtstyle dtcm dtterm dtfile dthelp dtprintinfo dtaction dtexec dtsearchpath dtsession; do
        [ -d "$CDE_BUILD/programs/$p" ] || continue
        ( cd "$CDE_BUILD/programs/$p" && make "${MAKE_OVERRIDES[@]}" install ) \
            || warn "programs/$p install failed"
    done
    # dtsession execs this helper (CDE_INSTALLATION_TOP/bin/dtsession_res) to
    # (re)load the desktop RESOURCE_MANAGER at session start.  dtsession's own
    # Makefile builds it (dtloadresources) but has no install rule for it, and
    # without it the vfork() child's exec fails.
    if [ -f "$CDE_BUILD/programs/dtsession/dtloadresources" ]; then
        install -m 0755 "$CDE_BUILD/programs/dtsession/dtloadresources" \
            "$CDE_ROOT/bin/dtsession_res"
        ok "installed dtsession_res"
    fi
    ok "install attempted"
}

log "CDE-on-Wayland build"
printf '    prefix : %s\n' "$CDE_PREFIX"
printf '    root   : %s\n' "$CDE_ROOT"
printf '    cpp    : %s\n' "$CPP_BIN"
printf '    stages : %s\n' "${STAGES[*]}"

for st in "${STAGES[@]}"; do
    case "$st" in
        prepare)   stage_prepare ;;
        imake)     stage_imake ;;
        makefiles) stage_makefiles ;;
        includes)  stage_includes ;;
        libs)      stage_libs ;;
        programs)  stage_programs ;;
        panel)     stage_panel ;;
        install)   stage_install ;;
        all)       stage_prepare; stage_imake; stage_makefiles; stage_includes; stage_libs ;;
        *)         die "unknown stage: $st" ;;
    esac
done

ok "done"
