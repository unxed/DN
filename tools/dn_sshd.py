"""A sshd of the tests on localhost (unxed/dn#90): tools/dn-linux-ssh.py, tools/dn-linux-shelllink.py.
The host "dnhost" of the ssh configuration that sshd_start writes is that sshd; "dnnone" is a port of 127.0.0.1 where nothing listens."""
import os, shutil, socket, subprocess, time


def sshd_start(d):
    """a sshd of this user on a free port; returns (process, path of the ssh config, path of the log) or None when sshd is not installed"""
    sshd = shutil.which('sshd') or ('/usr/sbin/sshd' if os.path.exists('/usr/sbin/sshd') else None)
    if not sshd:
        return None
    sftp = next((p for p in ('/usr/lib/openssh/sftp-server', '/usr/libexec/openssh/sftp-server', '/usr/libexec/sftp-server',
                             '/usr/lib/ssh/sftp-server') if os.path.exists(p)), None)
    k = os.path.join(d, 'k')
    os.makedirs(k)
    for name in ('host', 'user'):
        subprocess.run(['ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-f', os.path.join(k, name)], check=True)
    shutil.copy(os.path.join(k, 'user.pub'), os.path.join(k, 'authorized_keys'))
    with socket.socket() as s:
        s.bind(('127.0.0.1', 0))
        port = s.getsockname()[1]
    open(os.path.join(k, 'sshd_config'), 'w').write(
        'Port %d\nListenAddress 127.0.0.1\nHostKey %s/host\nPidFile %s/sshd.pid\nAuthorizedKeysFile %s/authorized_keys\n'
        'UsePAM no\nPasswordAuthentication no\nKbdInteractiveAuthentication no\nPubkeyAuthentication yes\nStrictModes no\n' % (port, k, k, k)
        + ('Subsystem sftp %s\n' % sftp if sftp else ''))
    common = ('  IdentityFile %s/user\n  IdentitiesOnly yes\n  StrictHostKeyChecking no\n  UserKnownHostsFile /dev/null\n  BatchMode yes\n'
              '  LogLevel ERROR\n' % k)
    open(os.path.join(k, 'cfg'), 'w').write(
        'Host dnhost\n  HostName 127.0.0.1\n  Port %d\n' % port + common +
        'Host dnnone\n  HostName 127.0.0.1\n  Port 1\n' + common)
    log = os.path.join(k, 'sshd.log')
    proc = subprocess.Popen([sshd, '-D', '-e', '-f', os.path.join(k, 'sshd_config')], stdout=open(log, 'w'), stderr=subprocess.STDOUT)
    end = time.time() + 15
    while time.time() < end and proc.poll() is None:
        try:
            socket.create_connection(('127.0.0.1', port), 0.5).close()
            return proc, os.path.join(k, 'cfg'), log
        except OSError:
            time.sleep(0.2)
    return proc, os.path.join(k, 'cfg'), log
