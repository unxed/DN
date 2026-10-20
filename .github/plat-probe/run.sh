#!/bin/sh
# Probe of unxed/dn#166 (temporary branch, not for main): builds DN with the native fpc (tools/build.sh linux64 = the fpc of the host)
# and runs .github/plat-probe/smoke.py on it. Variants: A = the options of linux64 (-dLINUX, as the freebsd64 target of unxed/dn#167),
# B = the same without -dLINUX (the Unix of the FPC: the run backend DNRunOther, no pty of TvPty). Usage: run.sh "A B"
set -u
cd "$(dirname "$0")/../.."
echo "== system: $(uname -a)"
command -v fpc >/dev/null 2>&1 || { echo "PROBE: NO_FPC (no fpc in the packages)"; exit 1; }
echo "== fpc $(fpc -iV) target $(fpc -iTP)-$(fpc -iTO)"
command -v python3 >/dev/null 2>&1 || { echo "PROBE: NO_PYTHON3"; exit 1; }
python3 --version
rc=0
for v in ${1:-A}; do
    echo "=================== variant $v"
    if [ "$v" = B ]; then
        sed -i.bak 's/^DN_OPT_linux64=.*/DN_OPT_linux64="-gl -dDPMI32"/' dn/build.env
        grep '^DN_OPT_linux64' dn/build.env
    fi
    s=$(date +%s)
    if DN_OBJ="${TMPDIR:-/tmp}/probe-obj-$v" tools/build.sh linux64 "out/$v" > "build-$v.log" 2>&1; then
        echo "PROBE $v: BUILD OK in $(( $(date +%s) - s )) s"
        tail -3 "build-$v.log"
        ls -l "out/$v" | head -20
        file "out/$v/dn" 2>/dev/null || true
        if python3 .github/plat-probe/smoke.py "out/$v"; then echo "PROBE $v: SMOKE OK"; else echo "PROBE $v: SMOKE FAILED"; rc=1; fi
    else
        echo "PROBE $v: BUILD FAILED in $(( $(date +%s) - s )) s"
        grep -a -E 'Error|Fatal|rror:|undefined|not found|No such' "build-$v.log" | head -40
        tail -40 "build-$v.log"
        for l in "${TMPDIR:-/tmp}/probe-obj-$v"/*.log; do [ -f "$l" ] && { echo "--- $l"; grep -a -E 'Error|Fatal|undefined' "$l" | head -30; tail -15 "$l"; }; done
        rc=1
    fi
    [ "$v" = B ] && mv dn/build.env.bak dn/build.env
done
exit $rc
