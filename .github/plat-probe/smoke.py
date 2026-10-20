#!/usr/bin/env python3
"""Probe of unxed/dn#166 (temporary branch, not for main): starts a built DN on a pty and checks that it draws the panels
and that a command typed on the command line runs. Usage: smoke.py OUTDIR"""
import os
import shutil
import sys
import tempfile
import time

here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(here)), 'tools'))
from pty_screen import PtyTerm  # noqa: E402

out = os.path.abspath(sys.argv[1])
fails = 0


def check(cond, name, info=''):
    global fails
    print(('PASS ' if cond else 'FAIL ') + name, flush=True)
    if not cond:
        fails += 1
        if info:
            print(info, flush=True)


d = tempfile.mkdtemp(prefix='dnsmoke-')
for f in os.listdir(out):
    if f == 'dn' or f.lower().endswith(('.lng', '.dlg', '.hlp')):
        shutil.copy(os.path.join(out, f), d)
    elif f == 'xlt':
        shutil.copytree(os.path.join(out, f), os.path.join(d, 'xlt'))
w = os.path.join(d, 'work')
os.makedirs(w)
os.makedirs(os.path.join(d, 'tmp'))
open(os.path.join(w, 'a.txt'), 'w').write('x\n')
t = PtyTerm(['./dn'], 100, 30, cwd=w, exe=os.path.join(d, 'dn'),
            env={'DN_RUN_PAUSE': '0', 'TEMP': os.path.join(d, 'tmp'), 'HOME': d})
end = time.time() + 60
while not t.text().strip() and time.time() < end and t.alive():
    t.pump(0.5, 2)
t.settle(1.5, 20)
scr = t.text()
check(t.alive(), 'dn is running after the start', 'status %r\n%s' % (t.status, scr))
check(('txt' in scr) and ('..' in scr or 'a.txt' in scr or 'a ' in scr), 'the panels show the directory', scr)
t.key('echo probe_ok > probe.txt\r', 1.5, 15)
p = os.path.join(w, 'probe.txt')
end = time.time() + 15
while not os.path.exists(p) and time.time() < end:
    t.pump(0.5, 1)
ok = os.path.exists(p) and 'probe_ok' in open(p).read()
check(ok, 'a command of the command line runs (echo > probe.txt)', t.text())
t.settle(1.0, 5)
check(t.alive(), 'dn is running after the command', 'status %r\n%s' % (t.status, t.text()))
print('--- screen ---\n' + t.text(), flush=True)
t.close(2)
print('SMOKE OK' if not fails else 'SMOKE: %d FAILED' % fails, flush=True)
sys.exit(1 if fails else 0)
