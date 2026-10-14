#!/usr/bin/env python3
"""Enter on a file runs the command of its extension from dn.ext: tools/dn-linux-assoc.py OUTDIR
dn.ext of the directory where DN starts holds `txt{touch !.!.done}`; Enter on a.txt must make a.txt.done
(`!.!` is the name with the extension). DN writes the command into a file $DN<n>$.CMD of TEMP (no execute bit, no `@echo off`) and runs it as `sh <file>`.
The item of dn.xrn chosen by its number (Ctrl+Shift+F1 for `>1`) goes the same way through a file $DN<n>$.BAT, which deletes itself at the end
(`rm -f '<file>'`: unquoted, sh would expand the `$DN<n>` of its name).
A mask `r:<regular expression>` of dn.ext is matched against the whole name (`r:^b.*\.log$` runs for b1.log; not in the mini build)."""
import os, shutil, sys, tempfile, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dn_wait import DnTerm


def main(out):
    d = tempfile.mkdtemp(prefix='dnassoc-')
    fails = 0
    try:
        for f in os.listdir(out):
            if f == 'dn' or f.lower().endswith(('.lng', '.dlg', '.hlp')):
                shutil.copy(os.path.join(out, f), d)
        w = os.path.join(d, 'work')
        os.makedirs(w)
        with open(os.path.join(w, 'dn.ext'), 'w') as f:
            f.write('txt{touch !.!.done}\n')
        with open(os.path.join(w, 'a.txt'), 'w') as f:
            f.write('text\n')
        os.environ['DNLNG'] = 'ENGLISH'
        t = DnTerm(['./dn'], 100, 30, cwd=w, exe=os.path.join(d, 'dn'))
        t.started()
        t.send('\x1b', 0.5)
        t.pump(0.5, 3)
        t.send('\x1b[F', 0.5)                      # End: a.txt, the last name (the panel sorts by the extension: dn.ext, a.txt)
        t.pump(0.5, 3)
        t.send('\r', 1.0)                          # Enter: the command of dn.ext
        done = os.path.join(w, 'a.txt.done')
        stop = time.time() + 10
        while not os.path.exists(done) and time.time() < stop:
            t.pump(0.5, 1)
        scr = t.text()
        ok = os.path.exists(done)
        print(('PASS ' if ok else 'FAIL ') + 'Enter on a.txt runs `touch !.!.done` of dn.ext: a.txt.done')
        if not ok:
            fails += 1
            print('--- screen')
            print(scr)
            tmp = os.path.join(d, 'tmp')
            for n in sorted(os.listdir(tmp)) if os.path.isdir(tmp) else []:
                p = os.path.join(tmp, n)
                if n.upper().endswith('.CMD') and os.path.isfile(p):
                    print('--- %s (mode %o)' % (n, os.stat(p).st_mode & 0o777))
                    with open(p, 'rb') as f:
                        print(f.read().decode('utf-8', 'replace'))
        t.send('\x1b', 0.5)
        t.close()
    finally:
        shutil.rmtree(d, ignore_errors=True)
    return fails


def w32(vk, uc=0, cs=0, sc=0):
    """a press and a release of a key in the win32 input mode (cs: 0x10 Shift, 0x04 Ctrl)"""
    return '\x1b[%d;%d;%d;1;%d;1_\x1b[%d;%d;%d;0;%d;1_' % (vk, sc, uc, cs, vk, sc, uc, cs)


def by_number(out):
    d = tempfile.mkdtemp(prefix='dnxrn-')
    fails = 0
    try:
        for f in os.listdir(out):
            if f == 'dn' or f.lower().endswith(('.lng', '.dlg', '.hlp')):
                shutil.copy(os.path.join(out, f), d)
        w = os.path.join(d, 'work')
        tmp = os.path.join(d, 'tmp')
        os.makedirs(w)
        os.makedirs(tmp)
        with open(os.path.join(w, 'dn.xrn'), 'w') as f:
            f.write('>1 ; quick one\ntouch quick.done\n')
        e = {'DNLNG': 'ENGLISH', 'DN2': d, 'HOME': d, 'TEMP': tmp, 'TMP': tmp, 'TMPDIR': tmp, 'DN_RUN_PAUSE': '0', 'TV_WIN32_INPUT': '1'}
        t = DnTerm(['./dn'], 100, 30, cwd=w, exe=os.path.join(d, 'dn'), env=e)
        t.started()
        t.send(w32(0x1B, 27), 0.8)                 # Esc closes the start box
        t.send(w32(0x70, 0, 0x14), 1.0)            # Ctrl+Shift+F1: the item >1 of dn.xrn
        done = os.path.join(w, 'quick.done')
        stop = time.time() + 10
        while not os.path.exists(done) and time.time() < stop:
            t.pump(0.5, 1)
        t.pump(0.5, 2)
        ok = os.path.exists(done)
        print(('PASS ' if ok else 'FAIL ') + 'Ctrl+Shift+F1 runs the item >1 of dn.xrn: quick.done')
        left = [n for n in os.listdir(tmp) if n.upper().startswith('$DN')]
        print(('PASS ' if not left else 'FAIL ') + 'the command file of the item deletes itself: %r' % left)
        fails += (not ok) + bool(left)
        if fails:
            print('--- screen')
            print(t.text())
        t.close()
    finally:
        shutil.rmtree(d, ignore_errors=True)
    return fails


def regex_mask(out):
    if os.environ.get('DN_MINI') == '1':
        print('SKIP r: masks of dn.ext: the mini build (DN_MINI=1) has no regular expressions', flush=True)
        return 0
    d = tempfile.mkdtemp(prefix='dnassocre-')
    fails = 0
    try:
        for f in os.listdir(out):
            if f == 'dn' or f.lower().endswith(('.lng', '.dlg', '.hlp')):
                shutil.copy(os.path.join(out, f), d)
        w = os.path.join(d, 'work')
        os.makedirs(w)
        with open(os.path.join(w, 'dn.ext'), 'w') as f:
            f.write('r:^b.*\\.log$ {touch !.!.done}\n')
        with open(os.path.join(w, 'b1.log'), 'w') as f:
            f.write('log\n')
        t = DnTerm(['./dn'], 100, 30, cwd=w, exe=os.path.join(d, 'dn'), env={'DNLNG': 'ENGLISH'})
        t.started()
        t.send('\x1b', 0.5)
        t.pump(0.5, 3)
        t.send('\x1b[F', 0.5)                      # End: b1.log (sorted by the extension: dn.ext, b1.log)
        t.pump(0.5, 3)
        t.send('\r', 1.0)                          # Enter: the r: line of dn.ext
        done = os.path.join(w, 'b1.log.done')
        stop = time.time() + 10
        while not os.path.exists(done) and time.time() < stop:
            t.pump(0.5, 1)
        ok = os.path.exists(done)
        print(('PASS ' if ok else 'FAIL ') + 'Enter on b1.log runs the line `r:^b.*\\.log$` of dn.ext: b1.log.done')
        if not ok:
            fails += 1
            print('--- screen')
            print(t.text())
        t.send('\x1b', 0.5)
        t.close()
    finally:
        shutil.rmtree(d, ignore_errors=True)
    return fails


if __name__ == '__main__':
    sys.exit(1 if main(sys.argv[1]) + by_number(sys.argv[1]) + regex_mask(sys.argv[1]) else 0)
