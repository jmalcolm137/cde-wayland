#!/usr/bin/env bash
#
# test-dt-database.sh — guard the generated CDE action/datatype databases.
#
# build-cde.sh generates programs/types/*.dt by running cpp over *.dt.src.  cpp
# joins backslash-continuation lines, so a field whose value spans several lines
# -- a multi-word DESCRIPTION, an EXEC_STRING split over lines -- comes out as a
# single line with the continuation indentation left in the middle of the value
# as a long run of spaces.  CDE's .dt reader then takes the words after that run
# for field names and logs, for every occurrence,
#
#     The action definition "Open" in the file ".../miscImages.dt" contains
#     the following unrecognized field name and value: "Cannot":"(null)"
#
# and rejects the action.  That is what fills ~/.dt/errorlog, and when it hits a
# file the File Manager depends on the double-click resolves no action.
#
# The signature is exact: apart from the single alignment run after a field
# name, a run of >=8 spaces inside a value can only have come from a joined
# continuation.  scripts/install-panel-data.sh re-wraps those runs (see
# dt_rejoin()); this test fails if any are left, so a build regression cannot
# get as far as a session.
#
#   scripts/test-dt-database.sh [TYPES_DIR]
#
set -euo pipefail
here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=lib.sh
source "$here/lib.sh"

dir="${1:-$CDE_ROOT/appconfig/types/C}"
[ -d "$dir" ] || die "no .dt directory: $dir"

python3 - "$dir" <<'PY'
import glob, os, re, sys
d = sys.argv[1]
field = re.compile(r'^(\s*)([A-Za-z_][A-Za-z0-9_]*)(\s+)(.*)$')
bad = []
for f in sorted(glob.glob(os.path.join(d, '*.dt'))):
    for i, ln in enumerate(open(f, encoding='utf-8', errors='replace'), 1):
        ln = ln.rstrip('\n')
        if ln.lstrip().startswith('#'):
            continue
        m = field.match(ln)
        val = m.group(4) if m else ln.strip()
        if re.search(r' {8,}', val):
            bad.append((os.path.basename(f), i, ln.strip()[:80]))
if bad:
    sys.stderr.write("FAIL: %d .dt field line(s) look like cpp-joined continuations:\n" % len(bad))
    for name, i, text in bad[:20]:
        sys.stderr.write("  %s:%d  %s\n" % (name, i, text))
    sys.stderr.write("The .dt files must keep their '\\' continuations for multi-line values.\n")
    sys.exit(1)
print("ok: %s (%d .dt files, no joined continuations)" %
      (d, len(glob.glob(os.path.join(d, '*.dt')))))
PY
