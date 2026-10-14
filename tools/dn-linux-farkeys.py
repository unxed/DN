#!/usr/bin/env python3
"""The keys DN already shares with Far, checked in a pty with [FilePanels]
FarUxMode=1, so that the Far UX mode does not take them away: F1-F8 and F10,
Shift+F1/F2/F5/F6/F8 and Alt+F1/F2/F7/F8 open their window, dialog or menu
over the panels, Esc (F10 for the menus) returns to the panels and DN stays
alive; Ctrl+Enter in the command history (Alt+F8) puts the command into the
command line. The keys go over the win32 input mode (TV_WIN32_INPUT=1).
usage: tools/dn-linux-farkeys.py OUTDIR"""
import os
import shutil
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pty_screen import PtyTerm

SHIFT, CTRL, ALT = 16, 8, 2


def w32(vk, uc=0, cs=0, sc=0):
    """a press and a release of a key"""
    return '\x1b[%d;%d;%d;1;%d;1_\x1b[%d;%d;%d;0;%d;1_' % (vk, sc, uc, cs, vk, sc, uc, cs)


def start(out):
    d = tempfile.mkdtemp(prefix='dnfark-')
    for f in os.listdir(out):
        if f == 'dn' or f.upper().endswith(('.LNG', '.DLG', '.HLP')):
            shutil.copy(os.path.join(out, f), d)
        elif f == 'xlt':
            shutil.copytree(os.path.join(out, f), os.path.join(d, f))
    with open(os.path.join(d, 'dn.ini'), 'w') as f:
        f.write('[FilePanels]\nFarUxMode=1\n')
    w = os.path.join(d, 'work')
    os.makedirs(w)
    open(os.path.join(w, 'alpha1.txt'), 'w').write('first\n')
    open(os.path.join(w, 'beta.txt'), 'w').write('second\n')
    t = PtyTerm(['./dn'], 100, 30, env={'TV_WIN32_INPUT': '1'}, cwd=w, exe=os.path.join(d, 'dn'))
    t.pump(1.5, 6)
    t.send(w32(0x1B), 1.0)                       # Esc closes the start box
    return d, t


def quit_dn(t):
    t.send(w32(0x58, ord('x'), ALT), 0.5)        # Alt-X
    t.send(w32(0x0D, 13), 1.5)                   # Enter confirms
    return t.close(4)


def cmdline_row(t):
    return '\n'.join(''.join(c for c, _ in row)
                     for row in t.screen.cells[27:29])


def to_alpha1(t):
    t.send('\x1b[H', 0.5)                       # Home
    t.send('\x1b[B', 0.5)                       # Down -> alpha1.txt


out = os.path.abspath(sys.argv[1])
fails = 0


def check(ok, msg, t=None):
    global fails
    print(('PASS ' if ok else 'FAIL ') + msg)
    if not ok:
        fails += 1
        if t is not None:
            print(t.text())


# (name, virtual key, control state, keys that close what the key opened)
KEYS = [
    ('F1', 0x70, 0, [0x1B]),
    ('F2', 0x71, 0, [0x1B]),
    ('F3', 0x72, 0, [0x1B]),
    ('F4', 0x73, 0, [0x1B]),
    ('F5', 0x74, 0, [0x1B]),
    ('F6', 0x75, 0, [0x1B]),
    ('F7', 0x76, 0, [0x1B]),
    ('F8', 0x77, 0, [0x1B]),
    ('F10', 0x79, 0, [0x1B]),
    ('Shift+F1', 0x70, SHIFT, [0x1B]),
    ('Shift+F2', 0x71, SHIFT, [0x1B]),
    ('Shift+F5', 0x74, SHIFT, [0x1B]),
    ('Shift+F6', 0x75, SHIFT, [0x1B]),
    ('Shift+F8', 0x77, SHIFT, [0x1B]),
    ('Alt+F1', 0x70, ALT, [0x1B]),
    ('Alt+F2', 0x71, ALT, [0x1B]),
    ('Alt+F7', 0x76, ALT, [0x1B]),
    ('Alt+F8', 0x77, ALT, [0x1B]),
]

d, t = start(out)
try:
    for name, vk, cs, close in KEYS:
        to_alpha1(t)
        before = t.text()
        t.send(w32(vk, 0, cs), 1.5)
        check(t.alive() and t.text() != before, 'FarUx on: %s opens its window' % name, t)
        for k in close:
            t.send(w32(k), 1.0)
        t.pump(0.5)
        if 'alpha1' not in t.text():
            t.send(w32(0x1B), 1.0)               # a second Esc for a nested box
        check(t.alive() and 'alpha1' in t.text() and 'beta' in t.text(),
              'FarUx on: Esc after %s returns to the panels' % name, t)
        if 'alpha1.txt' not in os.listdir(os.path.join(d, 'work')):
            check(False, 'FarUx on: %s left alpha1.txt in place' % name, t)
            break
    t.send('echo farkeys1', 0.5)                 # a command for the history
    t.send(w32(0x0D, 13), 2.0)                   # Enter runs it
    t.pump(1.0)
    check('Press Enter' in t.text(), 'FarUx on: the command ran and DN waits for Enter', t)
    t.send(w32(0x0D, 13), 1.5)                   # Enter brings the panels back
    check(t.alive() and 'alpha1' in t.text() and 'Press Enter' not in t.text(),
          'FarUx on: the panels are back after the command', t)
    t.send(w32(0x77, 0, ALT), 1.5)               # Alt+F8: the command history
    check('farkeys1' in t.text(), 'FarUx on: Alt+F8 lists the command', t)
    t.send(w32(0x0D, 13, 4), 1.0)                # Ctrl+Enter (RIGHT_CTRL, as in dn-linux-farux.py)
    check('farkeys1' in cmdline_row(t),
          'FarUx on: Ctrl+Enter in the history puts the command into the command line', t)
    t.send(w32(0x1B), 0.6)                       # Esc clears the command line
    check(quit_dn(t) == 0, 'FarUx on: DN ends with 0')
finally:
    shutil.rmtree(d, ignore_errors=True)

print('%d failed' % fails)
sys.exit(1 if fails else 0)
