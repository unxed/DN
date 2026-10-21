#!/usr/bin/env python3
"""ssh from the command line of DN (the embedded terminal, Linux, a pty): tools/dn-linux-ssh.py OUTDIR   (unxed/dn#90, step 1)
There is no network layer in DN yet; a remote shell works by the command line only. This test keeps that true:
  - a sshd of its own (a free port on 127.0.0.1, a key without a password, no root, no PAM) answers `ssh host command` typed in the command line;
  - an interactive `ssh host` takes a command and `exit` returns to DN.
The remote side is told apart from the local one by SSH_CONNECTION, which only sshd sets."""
import os, shutil, sys, tempfile
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dn_wait import DnTerm
from dn_sshd import sshd_start

bad = 0


def check(ok, what, info=''):
    global bad
    print(('PASS ' if ok else 'FAIL ') + what, flush=True)
    if not ok:
        bad += 1
        if info:
            print('    | ' + info[-1500:].replace('\n', '\n    | '), flush=True)


def install(out):
    d = tempfile.mkdtemp(prefix='dnssh-')
    for f in os.listdir(out):
        if f == 'dn' or f.lower().endswith(('.lng', '.dlg', '.hlp')) or f == 'xlt':
            src = os.path.join(out, f)
            (shutil.copytree if os.path.isdir(src) else shutil.copy)(src, os.path.join(d, f))
    w = os.path.join(d, 'work')
    os.makedirs(w)
    return d, w


def start(d, w):
    e = {'DNLNG': 'ENGLISH', 'DN2': d, 'DN_RUN_PAUSE': '1'}
    t = DnTerm(['./dn'], 100, 30, cwd=w, exe=os.path.join(d, 'dn'), env=e)
    t.started()
    t.send('\x1b', 0.5)
    return t


def panels(text):
    return 'F10 Menu' in text and 'Name' in text


out = os.path.abspath(sys.argv[1])
dirs = []
sshd = None
try:
    d, w = install(out); dirs.append(d)
    sshd = sshd_start(d)
    check(sshd is not None and sshd[0].poll() is None, 'sshd of the test is running on localhost',
          '' if sshd is None else open(sshd[2]).read())
    if sshd is not None and sshd[0].poll() is None:
        cfg = sshd[1]
        t = start(d, w)

        # a command on the remote side: the output is shown, DN waits for Enter
        t.send("ssh -F %s dnhost 'echo REMOTE_${SSH_CONNECTION%%%% *}'" % cfg, 0.3); t.send('\r', 1.0)
        t.wait_text('REMOTE_127.0.0.1', 20)
        text = t.text()
        check('REMOTE_127.0.0.1' in text, 'ssh host command: the output of the remote shell is on the screen', text)
        t.send('\r', 1.0)
        check(panels(t.text()), 'Enter brings the panels back after the remote command', t.text())

        # an interactive session: a command and exit
        t.send('ssh -F %s dnhost' % cfg, 0.3); t.send('\r', 1.0)
        t.pump(3.0, 4.0)                                                  # the key exchange and the shell of the remote side
        t.send('echo REMOTE2_${SSH_CONNECTION%% *}', 0.3); t.send('\r', 1.0)
        t.wait_text('REMOTE2_127.0.0.1', 20)
        text = t.text()
        check('REMOTE2_127.0.0.1' in text, 'interactive ssh: a command typed to the remote shell is run there', text)
        t.send('exit', 0.3); t.send('\r', 1.5)
        check(t.alive() and 'Fatal' not in t.text(), 'exit of the remote shell: DN is alive', t.text())
        t.send('\r', 1.0)
        check(panels(t.text()), 'the panels are back after the interactive ssh', t.text())
        t.close(0.3)
    if bad and sshd is not None:
        print('--- sshd.log ---\n' + open(sshd[2]).read()[-2000:], flush=True)
finally:
    if sshd is not None and sshd[0].poll() is None:
        sshd[0].terminate()
    for d in dirs:
        shutil.rmtree(d, ignore_errors=True)
sys.exit(1 if bad else 0)
