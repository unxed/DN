#!/bin/sh
# Cross-compiles the NetProc unit test for the Windows runner used by dn-windows.
set -eu
compiler=$1
out=$2
here=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$out/obj" "$out/bin"
"$compiler" -Mobjfpc -Sh \
  -Fu"$here/dn/src" \
  -Fi"$here/dn/tests" \
  -FU"$out/obj" -FE"$out/bin" -o"$out/bin/t_netproc.exe" \
  "$here/dn/tests/t_netproc.pas"
