#!/usr/bin/env bash
# build-help.sh — build the C-locale CDE help volumes (SDL) from the SGML
# sources in the CDE tree.
#
# CDE ships the help as DocBook SGML; it is converted to the SDL volumes the
# help viewer (dthelpview / DtHelpView) reads with the "dtdocbook" pipeline:
#
#     nsgmls  ->  instant  ->  dthelp_htag2
#
# That pipeline is part of CDE, but it needs two external tools that are not in
# the CDE tree: ksh (the dtdocbook driver is a ksh script) and an SGML parser
# (nsgmls, from OpenSP).  It also assumes /usr/dt paths and a locale
# translation database.  This script runs it unprivileged and relocated.
#
# The volumes are installed by install-panel-data.sh into
# $CDE_ROOT/help[/<locale>]/volumes/<Volume>.sdl, which is where
# DTHELPSEARCHPATH ("$CDE_ROOT/help/%L/%T/%N%S") points (%T == "volumes").
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib.sh"

[ -d "$CDE_BUILD" ] || die "no CDE build tree at $CDE_BUILD; run scripts/build-cde.sh"

DB="$CDE_BUILD/programs/dtdocbook"
DBK="$DB/doc2sdl"
SRC="$CDE_BUILD/doc/C/help"
OUT="$CDE_BUILD/doc/help-sdl"
HTAG2="$CDE_BUILD/programs/dthelp/parser/pass2/htag2/dthelp_htag2"

have() { command -v "$1" >/dev/null 2>&1; }
have ksh    || die "ksh is required by dtdocbook (install ksh)"
have nsgmls || die "nsgmls (OpenSP) is required to parse the help SGML (install opensp)"
[ -x "$DBK/dtdocbook" ] || die "dtdocbook not built; run scripts/build-cde.sh"
[ -x "$DB/instant/instant" ] || die "instant not built; run scripts/build-cde.sh"

# The final SDL enhancer/compressor is built from the pass2 parser.
if [ ! -x "$HTAG2" ]; then
    log "building dthelp_htag2 (the SDL enhancer)"
    make -C "$CDE_BUILD/programs/dthelp/parser/pass2/parser" -j"$(nproc)" \
        CCOPTIONS="-std=gnu17 -fcommon -Wno-implicit-function-declaration \
                   -Wno-int-conversion -Wno-incompatible-pointer-types \
                   -Wno-return-mismatch -Wno-implicit-int \
                   -Wno-builtin-declaration-mismatch" \
        CDEBUGFLAGS="-O2 -g -fno-strict-aliasing" AR="ar crs" >/dev/null 2>&1 \
        || die "could not build dthelp_htag2"
fi
[ -x "$HTAG2" ] || die "dthelp_htag2 not found at $HTAG2"

# The DocBook SGML declaration/DTD catalog and the locale translation database
# live in the build tree; point the tools at them instead of /usr/dt.
LCX="$CDE_BUILD/lib/DtHelp"

mkdir -p "$OUT"
built=0
# dtdocbook must run from the locale help directory: the volume sources use
# cwd-relative entity paths ("./FPanel/GEntity.sgm", "../../common/..."), which
# nsgmls resolves against SGML_SEARCH_PATH ".".
cd "$SRC"
for book in "$SRC"/*/book.sgm; do
    [ -f "$book" ] || continue
    vol="$(basename "$(dirname "$book")")"
    [ "$vol" = common ] && continue
    printf 'building help volume %-12s ' "$vol" >&2
    # -u: leave the SDL uncompressed (the compressor is the Unix "compress(1)",
    #     which is not part of CDE and may be absent).
    if env LANG=C SGML_SEARCH_PATH="." DTLCXSEARCHPATH="$LCX" \
         ksh "$DBK/dtdocbook" -u -t "$DBK" -I "$DB/instant/instant" \
             -L "$DB/xlate_locale/xlate_locale" -S "$(command -v nsgmls)" \
             -H "$HTAG2" -o "$OUT/$vol.sdl" "$vol/book.sgm" \
         >"/tmp/cde-wayland-help-$vol.log" 2>&1 && [ -s "$OUT/$vol.sdl" ]; then
        printf 'ok\n' >&2
        built=$((built + 1))
    else
        printf 'FAILED (see /tmp/cde-wayland-help-%s.log)\n' "$vol" >&2
    fi
done

[ "$built" -gt 0 ] || die "no help volumes were built"
ok "built $built help volumes into $OUT"
