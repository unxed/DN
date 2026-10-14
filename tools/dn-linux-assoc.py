#!/usr/bin/env python3
"""Enter on a file runs the command of its extension from dn.ext: tools/dn-linux-assoc.py OUTDIR
dn.ext of the directory where DN starts holds `txt{touch !.!.done}`; Enter on a.txt must make a.txt.done
(`!.!` is the name with the extension). DN writes the command into a file $DN<n>$.CMD of TEMP and runs that file."""
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


if __name__ == '__main__':
    sys.exit(1 if main(sys.argv[1]) else 0)
