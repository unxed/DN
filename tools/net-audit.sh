#!/bin/sh
# Looks for network code in the sources of DN (dn/src, dn/compat): a unit or an identifier of a socket library or of a remote protocol
# (ftp, sftp, ssh, telnet, fish, sockets, ssockets, winsock, netdb). Plan of the network protocols: https://github.com/unxed/dn/issues/90.
# No match: prints "net-audit: no network code" and exits 0. A match in a file that is not listed in tools/net-audit.allow (one path
# relative to the root per line, '#' starts a comment) is printed and the exit code is 1: the module that brings the network in must name itself there.
# usage: tools/net-audit.sh [root]      (default: the root of the repository)       (MIT, see LICENSE)
set -u
root=${1:-$(cd "$(dirname "$0")/.." && pwd)}
cd "$root" || exit 2
allow=tools/net-audit.allow
words='ftp|sftp|ssh|telnet|fish|sockets|ssockets|winsock|winsock2|netdb'
fail=0
found=0
for dir in dn/src dn/compat; do
    [ -d "$dir" ] || { echo "net-audit: $dir is missing" >&2; exit 2; }
done
hits=$(grep -rniE -I --include='*.pas' --include='*.inc' --include='*.dpr' --include='*.lpr' -w "$words" dn/src dn/compat | sort)
if [ -n "$hits" ]; then
    found=1
    files=$(printf '%s\n' "$hits" | cut -d: -f1 | sort -u)
    for f in $files; do
        if [ -f "$allow" ] && sed 's/#.*//; s/[ \t]*$//' "$allow" | grep -qxF "$f"; then
            echo "net-audit: $f is allowed by $allow"
        else
            fail=1
            printf '%s\n' "$hits" | grep "^$f:" | head -5
            echo "net-audit: $f has network code and is not listed in $allow" >&2
        fi
    done
fi
[ "$found" = 0 ] && echo "net-audit: no network code in dn/src and dn/compat"
exit $fail
