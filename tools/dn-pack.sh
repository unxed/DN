#!/bin/sh
# Packs a build of DN for a GitHub release: tools/dn-pack.sh OUTDIR NAME KIND DEST [VERSION]
#   OUTDIR   the directory that tools/build.sh made (dn or dn.exe, *.lng, *.dlg, *.hlp, xlt/, cwsdpmi.exe for DOS)
#   NAME     the target as shown in the file name (linux64, linux-aarch64, freebsd64, linux32, win64, win32, dos, dos-utf8)
#   KIND     tar (tar.gz) or zip
#   DEST     the directory for the archive: DEST/dn-VERSION-NAME.tar.gz or .zip
#   VERSION  the tag of a release (workflow release); without it: the short commit, a nightly build (workflow nightly)
# Linux archives install directly under /usr/local: bin/dn, lib/dn/ and share/.
# Other targets retain a single top-level directory with the program and resources.
# The archive also has the layout tables, the default dn.ini, licence texts and README.TXT.
# (tools/dn-notices.sh) and BUILD.TXT (the commit, the date). The builds are published as releases, never committed.
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
out=$1; name=$2; kind=$3; dest=$4; version=${5:-}
sha=$(git -C "$here" rev-parse HEAD)
label=${version:-$(git -C "$here" rev-parse --short HEAD)}
mkdir -p "$dest"; dest=$(cd "$dest" && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
stage=$tmp/dn-$label-$name
case "$name" in
    linux|linux32|linux64|linux-aarch64|freebsd64)
        mkdir -p "$stage/bin" "$stage/lib/dn" "$stage/share/applications" \
            "$stage/share/icons/hicolor/scalable/apps"
        [ -f "$out/dn" ] || { echo "dn-pack: no dn in $out" >&2; exit 1; }
        cp "$out/dn" "$stage/lib/dn/dn"
        cp "$out"/*.lng "$out"/*.dlg "$out"/*.hlp "$stage/lib/dn/"
        cp "$here/dn/third-party/f4-fish/helper.sh" "$stage/lib/dn/fishhelper.sh"     # the FISH+ helper that DN sends to the remote sh (dn#90 step 5)
        cp -r "$here/dn/data/xlt" "$stage/lib/dn/xlt"
        cp "$here/dn/data/dn.ini" "$stage/lib/dn/"
        cp "$here/dn/data/dn.ext.linux" "$stage/lib/dn/dn.ext"     # the commands of Enter for the common types (xdg-open)
        cp "$here/tools/dn-autoupdate.sh" "$stage/lib/dn/"
        cat > "$stage/bin/dn" <<'EOF'
#!/bin/sh
PREFIX=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
LIB="$PREFIX/lib/dn"
export DNDLG="$LIB" DN_LIB="$LIB"
if [ -x "$LIB/dn-autoupdate.sh" ]; then
    "$LIB/dn-autoupdate.sh" || true
fi
exec "$LIB/dn" "$@"
EOF
        chmod 755 "$stage/bin/dn"
        cp "$here/dn/data/desktop/dn.desktop" "$stage/share/applications/dn.desktop"
        cp "$here/dn/data/desktop/dn.svg" "$stage/share/icons/hicolor/scalable/apps/dn.svg"
        notices=$stage/lib/dn
        ;;
    *)
        mkdir -p "$stage"
        for f in dn dn.exe cwsdpmi.exe; do if [ -f "$out/$f" ]; then cp "$out/$f" "$stage/"; fi; done
        [ -f "$stage/dn" ] || [ -f "$stage/dn.exe" ] || { echo "dn-pack: no dn or dn.exe in $out" >&2; exit 1; }
        cp "$out"/*.lng "$out"/*.dlg "$out"/*.hlp "$stage/"
        cp "$here/dn/third-party/f4-fish/helper.sh" "$stage/fishhelper.sh"     # the FISH+ helper that DN sends to the remote sh (dn#90 step 5)
        cp -r "$here/dn/data/xlt" "$stage/xlt"
        cp "$here/dn/data/dn.ini" "$stage/"
        case "$name" in dos*) [ -f "$stage/cwsdpmi.exe" ] || { echo "dn-pack: no cwsdpmi.exe in $out" >&2; exit 1; };; esac
        notices=$stage
        ;;
esac
"$here/tools/dn-notices.sh" "$notices" "$name"
{
    if [ -n "$version" ]; then echo "DN $version"; else echo "DN nightly build"; fi
    echo "commit:  $sha"
    echo "date:    $(git -C "$here" log -1 --format=%cI)"
    echo "target:  $name"
    echo "source:  https://github.com/unxed/dn"
    [ -n "$version" ] || echo "This is the build of a commit of the branch main: it may be unfinished."
} > "$stage/BUILD.TXT"
case "$kind" in
    tar) tar -C "$tmp" -czf "$dest/dn-$label-$name.tar.gz" "dn-$label-$name" ;;
    zip) (cd "$tmp" && zip -qr "$dest/dn-$label-$name.zip" "dn-$label-$name") ;;
    *) echo "KIND: tar or zip" >&2; exit 2 ;;
esac
ls -l "$dest"
