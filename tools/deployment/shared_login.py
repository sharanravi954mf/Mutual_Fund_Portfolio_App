#!/usr/bin/python3.12 -I
"""Restricted login executable for SSH's fixed command; never a command shell.

Reviewed installation copies these bytes to /opt/moneybowl-shared-deploy/login
(root:root 0555) and uses that executable as UID 993's login shell. Existing
groups and credentials are unchanged. The code closure remains read-only 0444.
"""
import os
import stat
import sys
from pathlib import Path

sys.dont_write_bytecode = True
COMMAND = 'moneybowl-shared-deploy'
CLIENT = '/opt/moneybowl-shared-deploy/client.py'


def admitted(argv, environ, uid, euid, gid, egid, capabilities):
    return (argv[1:] == ['-c', COMMAND] and uid == euid == 993 and gid == egid == 983
            and capabilities == 0 and bool(environ.get('SSH_CONNECTION'))
            and not environ.get('SSH_ORIGINAL_COMMAND'))


def main():
    try:
        status = dict(line.split(':', 1) for line in Path('/proc/self/status').read_text().splitlines() if ':' in line)
        if not admitted(sys.argv, os.environ, os.getuid(), os.geteuid(), os.getgid(), os.getegid(),
                        int(status['CapEff'].strip(), 16)):
            return 1
        path = Path(CLIENT).resolve(strict=True)
        if not path.is_relative_to('/opt/moneybowl-shared-deploy'):
            return 1
        for item in [path, *path.parents]:
            info = item.lstat()
            if info.st_uid != 0 or info.st_mode & 0o022 or (
                {'system.posix_acl_access', 'system.posix_acl_default'} & set(os.listxattr(item, follow_symlinks=False))):
                return 1
        if not stat.S_ISREG(path.stat().st_mode):
            return 1
        os.execve('/usr/bin/python3.12', ['/usr/bin/python3.12', '-I', '-B', str(path)],
                  {'PATH': '/usr/bin:/bin', 'LANG': 'C.UTF-8'})
    except Exception:
        return 1
    return 1


if __name__ == '__main__':
    raise SystemExit(main())
