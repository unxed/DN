#!/usr/bin/env python3
"""Far UX fast find (Alt+letters) in a pty, checked on the screen: with
[FilePanels] FarUxMode=1 Alt+A moves the cursor to alpha1 (no menu opens),
Ctrl+Enter goes to the next match, Ctrl+Shift+Enter goes back, Esc leaves
the search; with the mode off Alt+A starts no search; the check box "Far UX
mode" of the File Manager setup switches the mode on at once and in dn.ini. The exact keys go
over the win32 input mode (TV_WIN32_INPUT=1), the Alt trigger additionally
over a plain ESC prefix. usage: tools/dn-linux-farux.py OUTDIR"""
import os
import shutil
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pty_screen import PtyTerm

CURSOR = (('i', 0), ('i', 6), 0)
SEL = (('i', 11), ('i', 8), 0)


def w32(vk, uc=0, cs=0, sc=0):
    """a press and a release of a key"""
    return '\x1b[%d;%d;%d;1;%d;1_\x1b[%d;%d;%d;0;%d;1_' % (vk, sc, uc, cs, vk, sc, uc, cs)


def start(out, farux):
    d = tempfile.mkdtemp(prefix='dnfar-')
    for f in os.listdir(out):
        if f == 'dn' or f.upper().endswith(('.LNG', '.DLG', '.HLP')):
            shutil.copy(os.path.join(out, f), d)
        elif f == 'xlt':
            shutil.copytree(os.path.join(out, f), os.path.join(d, f))
    if farux:
        with open(os.path.join(d, 'dn.ini'), 'w') as f:
            f.write('[FilePanels]\nFarUxMode=1\n')
    w = os.path.join(d, 'work')
    os.makedirs(w)
    open(os.path.join(w, 'alpha1.txt'), 'w').write('first\n')
    open(os.path.join(w, 'alpha2.txt'), 'w').write('other\n')
    open(os.path.join(w, 'beta.txt'), 'w').write('third\n')
    t = PtyTerm(['./dn'], 100, 30, env={'TV_WIN32_INPUT': '1'}, cwd=w, exe=os.path.join(d, 'dn'))
    t.pump(1.5, 6)
    t.send(w32(0x1B), 1.0)                       # Esc closes the start box
    return d, t


def cursor_file(t):
    for row in t.screen.cells:
        s = ''.join(c for c, _ in row)
        if ('alpha' in s or 'beta' in s) and CURSOR in set(a for _, a in row):
            return s.strip()[:12]
    return None


def selected_files(t):
    # selected rows carry ('i', 11) as the first attr element; the second
    # differs under the cursor (('i', 6) instead of ('i', 8))
    out = []
    for row in t.screen.cells:
        s = ''.join(c for c, _ in row)
        if (('alpha' in s or 'beta' in s)
                and any(a[0] == ('i', 11) for _, a in row)):
            out.append(s.strip()[:8])
    return out


def quit_dn(t):
    t.send(w32(0x58, ord('x'), 2), 0.5)           # Alt-X
    t.send(w32(0x0D, 13), 1.5)                   # Enter confirms
    return t.close(4)


def cmdline_row(t):
    return '\n'.join(''.join(c for c, _ in row)
                     for row in t.screen.cells[27:29])


out = os.path.abspath(sys.argv[1])
fails = 0


def check(ok, msg, t=None):
    global fails
    print(('PASS ' if ok else 'FAIL ') + msg)
    if not ok:
        fails += 1
        if t is not None:
            print(t.text())


d, t = start(out, True)
try:
    t.send(w32(0x41, ord('a'), 2), 1.0)           # Alt+A
    check('Search:' in t.text(), 'FarUx on: Alt+A shows the fast-find mask', t)
    check(cursor_file(t) is not None and 'alpha1' in cursor_file(t),
          'FarUx on: the cursor stands on alpha1, no menu opens', t)
    t.send(w32(0x0D, 13, 4), 1.0)                # Ctrl+Enter
    check(cursor_file(t) is not None and 'alpha2' in cursor_file(t),
          'FarUx on: Ctrl+Enter moves to the next match', t)
    t.send(w32(0x0D, 13, 20), 1.0)               # Ctrl+Shift+Enter
    check(cursor_file(t) is not None and 'alpha1' in cursor_file(t),
          'FarUx on: Ctrl+Shift+Enter moves back', t)
    t.send(w32(0x1B), 1.0)                       # Esc
    check('Search:' not in t.text(), 'FarUx on: Esc leaves the search', t)
    t.send(w32(0x6B, ord('+'), 16), 1.0)         # Shift+NumpadAdd
    check(len(selected_files(t)) == 3, 'FarUx on: Shift+Gray+ selects all', t)
    t.send(w32(0x6D, ord('-'), 16), 1.0)         # Shift+NumpadSub
    check(selected_files(t) == [], 'FarUx on: Shift+Gray- deselects all', t)
    t.send('\x1b[H', 0.5)                       # Home
    t.send('\x1b[B', 0.5)                       # Down -> alpha1
    t.send(w32(0x2D, 0, 6), 1.0)                 # Ctrl+Alt+Ins: full names
                                                     # (win32 Cs: $04 ctrl + $02 alt)
    t.send('\x1b[B', 0.5)
    t.send('\x1b[B', 0.5)                       # Down,Down -> beta.txt
    t.send(w32(0x73), 1.2)                       # F4 editor
    t.send(w32(0x2D, 0, 16), 1.0)                # Shift+Ins pastes
    t.pump(0.5)
    editor_text = t.text()
    editor_text = editor_text[editor_text.find('Edit -'):]
    check('work\\alpha1' in editor_text,
          'FarUx on: Ctrl+Alt+Ins puts the full name into the clipboard', t)
    t.send(w32(0x1B), 1.0)                       # Esc leaves the editor
    t.pump(0.5)
    if 'was modified' in t.text():
        t.send('n', 1.0)                         # No: do not save the paste
    check('Edit -' not in t.text(), 'FarUx on: the editor is closed', t)
    t.send('\x1b[H', 0.5)                       # Home
    t.send('\x1b[B', 0.5)                       # Down -> alpha1
    t.send('q', 0.8)                             # type into the command line
    t.send(w32(0x2D, 0, 4), 1.0)                 # Ctrl+Ins
    check('alpha1' in cmdline_row(t),
          'FarUx on: Ctrl+Ins with text inserts the name into the command line', t)
    check(quit_dn(t) == 0, 'FarUx on: DN ends with 0')
finally:
    shutil.rmtree(d, ignore_errors=True)

d, t = start(out, False)
try:
    t.send(w32(0x41, ord('a'), 2), 1.0)           # Alt+A
    check('Search:' not in t.text(), 'FarUx off: Alt+A starts no search', t)
    t.send(w32(0x6B, ord('+'), 16), 1.0)         # Shift+NumpadAdd
    check(selected_files(t) == [], 'FarUx off: Shift+Gray+ selects nothing', t)
    t.send('\x1b[H', 0.5)                       # Home
    t.send('\x1b[B', 0.5)                       # Down -> alpha1
    t.send('q', 0.8)
    t.send(w32(0x2D, 0, 4), 1.0)                 # Ctrl+Ins
    check('alpha1' not in cmdline_row(t),
          'FarUx off: Ctrl+Ins with text still goes to the clipboard', t)
    check(quit_dn(t) == 0, 'FarUx off: DN ends with 0')
finally:
    shutil.rmtree(d, ignore_errors=True)


d, t = start(out, False)
try:
    t.send(w32(0x4F, ord('o'), 2), 0.8)           # Alt+O: the menu Options
    t.send('f', 0.6)                             # File Manager
    t.send('s', 1.0)                             # Setup
    check('[ ] Far UX mode' in t.text(), 'the File Manager setup shows "Far UX mode", off', t)
    t.send(w32(0x58, ord('x'), 2), 0.6)           # Alt+X: its hot key
    check('[X] Far UX mode' in t.text(), 'Alt+X checks "Far UX mode"', t)
    t.send(w32(0x0D, 13), 1.0)                   # Enter: OK
    ini = open(os.path.join(d, 'dn.ini'), errors='replace').read() if os.path.isfile(os.path.join(d, 'dn.ini')) else ''
    check('FarUxMode=1' in ini, 'the setup writes FarUxMode=1 into dn.ini', t)
    t.send(w32(0x41, ord('a'), 2), 1.0)           # Alt+A
    check('Search:' in t.text() and cursor_file(t) is not None and 'alpha1' in cursor_file(t),
          'the mode works at once: Alt+A finds alpha1', t)
    t.send(w32(0x1B), 1.0)                       # Esc leaves the search
    check(quit_dn(t) == 0, 'setup: DN ends with 0')
finally:
    shutil.rmtree(d, ignore_errors=True)

print('ALL OK' if not fails else '%d FAILED' % fails)
sys.exit(1 if fails else 0)
