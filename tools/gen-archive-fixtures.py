#!/usr/bin/env python3
"""Generate a small reproducible archive fixture tree for DN archive-matrix tests.

Usage:
  python3 tools/gen-archive-fixtures.py [OUTDIR]

Creates OUTDIR (default: a temp directory) with simple and nested archives.
Skips formats whose packer is missing. Prints the output path on stdout.
"""
from __future__ import annotations

import argparse
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import zipfile


def have(cmd: str) -> bool:
    return shutil.which(cmd) is not None


def run(cmd, cwd=None):
    subprocess.check_call(cmd, cwd=cwd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def write_member(dirpath: str, name: str = 'inside.txt', body: str = 'hello from fixture\n') -> str:
    path = os.path.join(dirpath, name)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(body)
    return name


def write_zoo(path: str, name: str, body: bytes) -> None:
    """a ZOO archive with one stored member (no packer needed): the header of 34 bytes, a directory entry of type 2 and the
    entry that ends the list (an empty name)"""
    magic = 0xFDC4A7DC
    start = 34
    entry_len = 38 + 13 + 7            # the fixed part, the 8.3 name, then var_dir_len, tz, dir_crc, namlen, dirlen
    data_at = start + entry_len
    end_at = data_at + len(body)
    date, time_ = (2026 - 1980) << 9 | 10 << 5 | 14, 12 << 11

    def entry(fname: bytes, next_at: int, offset: int, size: int) -> bytes:
        return (struct.pack('<IBBIIHHHIIBBBBIH', magic, 2, 0, next_at, offset, date, time_, 0, size, size, 2, 0, 0, 0, 0, 0)
                + fname.ljust(13, b'\0') + struct.pack('<HBHBB', 0, 127, 0, 0, 0))

    with open(path, 'wb') as f:
        f.write(b'ZOO 2.10 Archive.\x1a\0\0' + struct.pack('<IIiBB', magic, start, -start, 2, 0))
        f.write(entry(name.encode('ascii'), end_at, data_at, len(body)))
        f.write(body)
        f.write(entry(b'', 0, 0, 0))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('outdir', nargs='?', default='')
    args = ap.parse_args()
    out = args.outdir or tempfile.mkdtemp(prefix='dn-arc-fix-')
    os.makedirs(out, exist_ok=True)
    stage = os.path.join(out, '_stage')
    os.makedirs(stage, exist_ok=True)
    write_member(stage)

    made = []

    # zip (stdlib)
    zpath = os.path.join(out, 'simple.zip')
    with zipfile.ZipFile(zpath, 'w') as zf:
        zf.write(os.path.join(stage, 'inside.txt'), 'inside.txt')
    made.append('simple.zip')

    # zip with directory
    z2 = os.path.join(out, 'dirs.zip')
    with zipfile.ZipFile(z2, 'w') as zf:
        zf.writestr('sub/inside.txt', 'in sub\n')
        zf.writestr('root.txt', 'root\n')
    made.append('dirs.zip')

    if have('tar'):
        run(['tar', '-cf', os.path.join(out, 'simple.tar'), 'inside.txt'], cwd=stage)
        made.append('simple.tar')
        run(['tar', '-czf', os.path.join(out, 'simple.tgz'), 'inside.txt'], cwd=stage)
        made.append('simple.tgz')
        run(['tar', '-czf', os.path.join(out, 'simple.tar.gz'), 'inside.txt'], cwd=stage)
        made.append('simple.tar.gz')
        if have('bzip2'):
            run(['tar', '-cjf', os.path.join(out, 'simple.tar.bz2'), 'inside.txt'], cwd=stage)
            made.append('simple.tar.bz2')
        if have('xz'):
            run(['tar', '-cJf', os.path.join(out, 'simple.tar.xz'), 'inside.txt'], cwd=stage)
            made.append('simple.tar.xz')
            # .txz is the short compound alias (same payload)
            shutil.copy(
                os.path.join(out, 'simple.tar.xz'),
                os.path.join(out, 'simple.txz'),
            )
            made.append('simple.txz')

    if have('gzip'):
        shutil.copy(os.path.join(stage, 'inside.txt'), os.path.join(out, 'plain.txt'))
        run(['gzip', '-n', '-f', 'plain.txt'], cwd=out)
        # gzip -n keeps name; result plain.txt.gz
        if os.path.exists(os.path.join(out, 'plain.txt.gz')):
            made.append('plain.txt.gz')

    # zoo (written here: the format is simple and the packer is rarely installed)
    write_zoo(os.path.join(out, 'simple.zoo'), 'inside.txt', b'hello from fixture\n')
    made.append('simple.zoo')

    if have('7z'):
        run(['7z', 'a', '-bd', '-y', os.path.join(out, 'simple.7z'), 'inside.txt'], cwd=stage)
        made.append('simple.7z')

    # zip-in-zip
    inner = os.path.join(stage, 'inner.zip')
    with zipfile.ZipFile(inner, 'w') as zf:
        zf.writestr('nested.txt', 'nested\n')
    with zipfile.ZipFile(os.path.join(out, 'outer.zip'), 'w') as zf:
        zf.write(inner, 'inner.zip')
    made.append('outer.zip')

    shutil.rmtree(stage)
    meta = os.path.join(out, 'MANIFEST.txt')
    with open(meta, 'w', encoding='utf-8') as f:
        f.write('\n'.join(made) + '\n')
    print(out)
    for m in made:
        print(' ', m, file=sys.stderr)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())