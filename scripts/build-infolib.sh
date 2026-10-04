#!/usr/bin/env bash
# build-infolib.sh — build the CDE "cde" documentation infolib for dtinfo.
#
# dtinfo (the Information Manager) browses MMDB infolibs, not the SDL help
# volumes that dthelpview uses.  The CDE guides under doc/<locale>/guides are
# SGML; running their imake-generated Makefile through dtinfogen produces
# doc/C/cde.dti, which install-panel-data.sh then installs under
# appconfig/infolib/<locale>/cde.dti.
#
# Needs a CDE build tree (scripts/build-cde.sh libs) and nsgmls (opensp).
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/lib.sh"

[ -d "$CDE_BUILD" ] || die "no CDE build tree at $CDE_BUILD; run scripts/build-cde.sh"
GUIDES="$CDE_BUILD/doc/C/guides"
[ -f "$GUIDES/Imakefile" ] || die "no $GUIDES/Imakefile"
command -v nsgmls >/dev/null 2>&1 || die "nsgmls not found (install opensp)"

# The same compiler workarounds build-cde.sh uses; the doc Makefile still
# compiles a few helpers with cc.
CCOPT="-std=gnu17 -fcommon -Wno-implicit-function-declaration -Wno-int-conversion \
-Wno-incompatible-pointer-types -Wno-return-mismatch -Wno-implicit-int \
-Wno-builtin-declaration-mismatch"

log "building the InfoManager toolchain"
for d in programs/dtinfo/tools programs/dtinfo/DtMmdb programs/dtinfo/mmdb \
         programs/dtinfo/dtinfogen programs/dtinfo/dtinfo; do
    [ -d "$CDE_BUILD/$d" ] || continue
    log "  make -C $d"
    ( cd "$CDE_BUILD/$d" && make "CCOPTIONS=$CCOPT" "CDEBUGFLAGS=-O2 -g" \
        "AR=ar crs" -j"$JOBS" >/dev/null 2>&1 ) \
        || warn "$d failed (the infolib build may still work)"
done

log "generating $GUIDES/Makefile"
( cd "$GUIDES" && "$CDE_BUILD/config/imake/imake" -I"$CDE_BUILD/config/cf" \
    -DTOPDIR=../../.. -DCURDIR=doc/C/guides >/dev/null )

log "building doc/C/cde.dti (this takes a few minutes)"
( cd "$GUIDES" && make "CCOPTIONS=$CCOPT" "CDEBUGFLAGS=-O2 -g" "AR=ar crs" all )

[ -d "$CDE_BUILD/doc/C/cde.dti" ] || die "the infolib was not produced"
ok "infolib built at $CDE_BUILD/doc/C/cde.dti"
