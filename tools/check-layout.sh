#!/bin/sh
# Checks the separation of the projects in this repository (see README.md):
#  - tv/ does not use anything but its own units and the RTL;
#  - a tv/src unit that says "Translated from magiblot/tvision @" points to COPYRIGHT.magiblot;
#  - tv/ does not mention dn/;
#  - dn/ does not contain files of tv/ (same names) and no Borland sources by name;
#  - dn/PROVENANCE.md (the origin of the files of dn/src) is up to date.
# usage: tools/check-layout.sh      (from the root of the repository)
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
. "$here/tools/need-tv.sh"
fail=0
err() { echo "layout: $*" >&2; fail=1; }

# 1. units used by tv/
own=$(ls tv/src/*.pas tv/tests/*.pas | sed 's|.*/||; s|\.pas$||' | tr 'A-Z' 'a-z' | sort -u | tr '\n' ' ')
allowed="system sysutils dos go32 objpas math strings classes baseunix unix termio windows process"
for f in tv/src/*.pas tv/tests/*.pas tv/dostests/*.pas tv/demo/*.pas; do
    [ -f "$f" ] || continue
    # the "uses" clauses: from "uses" to the first ";"
    units=$(awk 'BEGIN{IGNORECASE=1} /^[ \t]*uses[ \t]*$|^[ \t]*uses[ \t]/{u=1} u{print} u&&/;/{u=0}' "$f" \
        | sed 's/{[^}]*}//g; s/(\*.*\*)//g; s/^[ \t]*uses//I' | tr ',;' '\n\n' | tr -d ' \t\r' \
        | tr 'A-Z' 'a-z' | grep -v '^$' | sort -u)
    for u in $units; do
        case " $own $allowed " in *" $u "*) ;; *) err "$f uses the unit '$u' that is not part of tv/ or the RTL";; esac
    done
done

# 2. origin notes
for f in tv/src/*.pas; do
    if grep -q 'Translated from magiblot/tvision @' "$f"; then
        grep -q 'COPYRIGHT.magiblot' "$f" || err "$f is translated but does not point to COPYRIGHT.magiblot"
    fi
done

# 3. tv/ does not know dn/
if grep -rIl --include='*.pas' --include='*.inc' -E '(^|[^A-Za-z])dn/|DOS Navigator|DNApp' tv/src tv/tests tv/dostests tv/demo 2>/dev/null | grep .; then
    err "tv/ sources mention dn/ or DOS Navigator (see the lines above)"
fi

# 4. dn/ is not a copy of tv/
if [ -d dn ]; then
    for f in tv/src/*.pas; do
        b=$(basename "$f")
        [ -e "dn/$b" ] && err "dn/$b has the name of a unit of tv/ (the projects keep their units apart)"
    done
    find dn -type d -name ref | grep . && err "dn/ must not hold a reference corpus"
fi

# 4b. no unit of DN, tv/ or tve/ has the name of a unit of Better Pascal (the submodule bp/, docs/BETTER-PASCAL.md): with DN_BP=1 the
#     compiler would take one for the other. Skipped when bp/ is not checked out.
if [ -f bp/bp.pas ]; then
    for f in bp/bp.pas bp/safe/*.pas bp/ext/*.pas; do
        b=$(basename "$f" | tr 'A-Z' 'a-z')
        for d in dn/src dn/archives dn/compat dn/compat/linux dn/lib/localecp dn/lib/zipcharset dn/tests tv/src tve/src; do
            [ -d "$d" ] || continue
            ls "$d" | tr 'A-Z' 'a-z' | grep -qx "$b" && err "$d has a unit named $b, the name of the unit $f of bp/"
        done
    done
fi

# 5. the manifest of the origin of the files of dn/src
python3 bootstrap/tools/dn-manifest.py --check >/dev/null || err "dn/PROVENANCE.md is not up to date (run bootstrap/tools/dn-manifest.py)"

# 6. the names of the commands and keys for the log of the flight recorder are made from the sources
python3 tools/gen-evnames.py --check || err "dn/src/evnames.pas is not up to date (run tools/gen-evnames.py)"

# 7. no new hand-spelled separators or drive letters (docs/PATHS.md)
python3 tools/check-paths.py || err "paths are spelled by hand; use DnPath"

[ "$fail" -eq 0 ] && echo "layout: ok"
exit "$fail"
