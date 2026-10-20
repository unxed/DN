#!/usr/bin/env python3
"""A remote place in a panel (Linux, a pty): tools/dn-linux-shelllink.py OUTDIR   (unxed/dn#90, step 7)
A sshd of its own on localhost (tools/dn_sshd.py); the ssh that DN starts is found in PATH, where the test puts a wrapper that gives ssh the
configuration of the test. The helper of FISH is put beside dn as tools/dn-pack.sh does.
  - `cd sh://dnhost/DIR` in the command line: the panel shows the files of DIR on the remote side and the address in its title;
  - Enter on a directory goes into it, Enter on ".." goes back;
  - `cd sftp://dnhost/DIR`: the same over SFTP;
  - `cd LOCAL`: the panel is a local one again;
  - Disk | Shell link: the address typed in its dialog opens in the panel;
  - an address where no server answers: a message, DN goes on."""
import os, shutil, stat, sys, tempfile
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dn_wait import DnTerm
from dn_sshd import sshd_start

bad = 0
here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def check(ok, what, info=''):
    global bad
    print(('PASS ' if ok else 'FAIL ') + what, flush=True)
    if not ok:
        bad += 1
        if info:
            print('    | ' + info[-1500:].replace('\n', '\n    | '), flush=True)


def install(out):
    d = tempfile.mkdtemp(prefix='dnlink-')
    for f in os.listdir(out):
        if f == 'dn' or f.lower().endswith(('.lng', '.dlg', '.hlp')) or f == 'xlt':
            src = os.path.join(out, f)
            (shutil.copytree if os.path.isdir(src) else shutil.copy)(src, os.path.join(d, f))
    shutil.copy(os.path.join(here, 'dn', 'third-party', 'f4-fish', 'helper.sh'), os.path.join(d, 'fishhelper.sh'))
    w = os.path.join(d, 'work')
    os.makedirs(w)
    return d, w


def ssh_wrapper(d, cfg):
    """a directory with an "ssh" that runs the real one with the configuration of the test"""
    real = shutil.which('ssh') or '/usr/bin/ssh'
    b = os.path.join(d, 'bin')
    os.makedirs(b)
    p = os.path.join(b, 'ssh')
    open(p, 'w').write('#!/bin/sh\nexec "%s" -F "%s" "$@"\n' % (real, cfg))
    os.chmod(p, os.stat(p).st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    return b


def start(d, w, b):
    e = {'DNLNG': 'ENGLISH', 'DN2': d, 'DN_RUN_PAUSE': '1', 'PATH': b + os.pathsep + os.environ.get('PATH', '')}
    t = DnTerm(['./dn'], 100, 30, cwd=w, exe=os.path.join(d, 'dn'), env=e)
    t.started()
    t.send('\x1b', 0.5)
    return t


def command(t, text):
    t.send(text, 0.3)
    t.send('\r', 1.0)


out = os.path.abspath(sys.argv[1])
dirs = []
sshd = None
try:
    d, w = install(out); dirs.append(d)
    if os.geteuid() == 0:
        os.makedirs('/run/sshd', exist_ok=True)      # sshd run by root wants its directory of privilege separation
    sshd = sshd_start(d)
    check(sshd is not None and sshd[0].poll() is None, 'sshd of the test is running on localhost',
          '' if sshd is None else open(sshd[2]).read())
    if sshd is not None and sshd[0].poll() is None:
        b = ssh_wrapper(d, sshd[1])
        tree = os.path.join(d, 'remote-tree')
        os.makedirs(os.path.join(tree, 'subdir'))
        open(os.path.join(tree, 'alpha-remote.txt'), 'w').write('alpha\n')
        open(os.path.join(tree, 'subdir', 'beta-inner.txt'), 'w').write('beta\n')
        t = start(d, w, b)

        # the panel shows a name and its extension in two columns: "alpha-remote  txt"
        command(t, 'cd sh://dnhost' + tree)
        t.wait_text('alpha-remote', 30)
        text = t.text()
        check('alpha-remote' in text and 'subdir' in text, 'cd sh://host/dir: the panel shows the remote files', text)
        check('sh://dnhost' in text, 'the title of the panel is the address', text)

        # the list: "..", then the directory, then the file; the cursor is on ".."
        t.send('\x1b[B', 0.5)
        t.send('\r', 1.0)
        t.wait_text('beta-inner', 20)
        text = t.text()
        check('beta-inner' in text and 'alpha-remote' not in text, 'Enter on a directory goes into it', text)
        t.send('\x1b[H', 0.5)
        t.send('\r', 1.0)
        t.wait_text('alpha-remote', 20)
        check('alpha-remote' in t.text(), 'Enter on ".." goes back', t.text())

        command(t, 'cd sftp://dnhost' + tree + '/subdir')
        t.wait_text('sftp://dnhost', 30)
        text = t.text()
        check('sftp://dnhost' in text and 'beta-inner' in text, 'cd sftp://host/dir: the same over SFTP', text)

        open(os.path.join(w, 'local-marker.txt'), 'w').write('x\n')
        command(t, 'cd ' + w)
        t.wait_text('local-marker', 20)
        text = t.text()
        check('local-marker' in text and 'sftp://' not in text, 'cd to a local directory: the panel is local again', text)

        # Disk | Shell link: the dialog takes the address ("sh://" is there already)
        t.send('\x1b[21~', 0.8)
        t.send('d', 0.8)
        t.send('l', 1.0)
        t.wait_text('Address', 10)
        check('Shell link' in t.text() and 'Address' in t.text(), 'Disk | Shell link opens the dialog of the address', t.text())
        t.send('\x1b[F', 0.3)
        t.send('dnhost' + tree, 0.3)
        t.send('\r', 1.0)
        t.wait_text('alpha-remote', 30)
        text = t.text()
        check('alpha-remote' in text and 'sh://dnhost' in text, 'the address of the dialog opens in the panel', text)
        command(t, 'cd ' + w)
        t.wait_text('local-marker', 20)

        command(t, 'cd sh://dnnone/')
        t.wait_text('Cannot open', 30)
        text = t.text()
        check('Cannot open' in text, 'no server: a message tells it', text)
        t.send('\x1b', 1.0)
        check(t.alive() and 'Fatal' not in t.text(), 'DN goes on after the message', t.text())
        t.close(0.3)
    if bad and sshd is not None:
        print('--- sshd.log ---\n' + open(sshd[2]).read()[-2000:], flush=True)
finally:
    if sshd is not None and sshd[0].poll() is None:
        sshd[0].terminate()
    for d in dirs:
        shutil.rmtree(d, ignore_errors=True)
sys.exit(1 if bad else 0)
