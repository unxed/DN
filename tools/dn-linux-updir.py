#!/usr/bin/env python3
"""The line at the bottom of the panel shows the date of the parent directory on '..': tools/dn-linux-updir.py OUTDIR
DN starts in parent/child, the cursor stands on '..', the parent directory has the time 4 March 2011; the line of '..' (UP--DIR) must carry
that date, not the zero date 0.00.80 that the empty record of '..' gave."""
import os, re, shutil, sys, tempfile, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dn_wait import DnTerm


def main(out):
    d = tempfile.mkdtemp(prefix='dnupdir-')
    fails = 0
    try:
        for f in os.listdir(out):
            if f == 'dn' or f.lower().endswith(('.lng', '.dlg', '.hlp')):
                shutil.copy(os.path.join(out, f), d)
        parent = os.path.join(d, 'parent')
        child = os.path.join(parent, 'child')
        os.makedirs(child)
        stamp = time.mktime((2011, 3, 4, 5, 6, 0, 0, 0, -1))
        os.utime(parent, (stamp, stamp))
        os.environ['DNLNG'] = 'ENGLISH'
        t = DnTerm(['./dn'], 100, 30, cwd=child, exe=os.path.join(d, 'dn'))
        t.started()
        t.send('\x1b', 0.5)
        t.pump(0.5, 3)
        scr = t.text()
        line = next((l for l in scr.split('\n') if 'UP--DIR' in l), '')
        ok = bool(re.search(r'\b0?4\.03\.(20)?11\b', line)) and '0.00.80' not in line
        print(('PASS ' if ok else 'FAIL ') + "the line of '..' shows the date of the parent directory: " + repr(line))
        if not ok:
            fails += 1
            print('--- screen')
            print(scr)
        t.send('\x1b', 0.5)
        t.close()
    finally:
        shutil.rmtree(d, ignore_errors=True)
    return fails


if __name__ == '__main__':
    sys.exit(1 if main(sys.argv[1]) else 0)
