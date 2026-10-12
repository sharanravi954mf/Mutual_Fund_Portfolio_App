"""Owner-only evidence and shared deployment lock; never follow protected links."""
import contextlib
import fcntl
import json
import os
import stat
import tempfile
from pathlib import Path

from contract import Rejected, require


def protected(path, *, directory=False, private=True):
    path = Path(path)
    require(path.is_absolute() and path.resolve() == path, 'protected_path_invalid')
    for parent in reversed(path.parents):
        info = parent.lstat()
        sticky_tmp = parent == Path('/tmp') and info.st_uid == 0 and info.st_mode & stat.S_ISVTX
        require(stat.S_ISDIR(info.st_mode) and info.st_uid in (0, os.getuid())
                and (not info.st_mode & 0o022 or sticky_tmp), 'protected_parent_invalid')
    info = path.lstat()
    require((stat.S_ISDIR(info.st_mode) if directory else stat.S_ISREG(info.st_mode))
            and info.st_uid in (0, os.getuid()) and not info.st_mode & (0o077 if private else 0o022)
            and (directory or info.st_nlink == 1), 'protected_permissions_invalid')
    return path


def read_private(path):
    return json.loads(protected(path).read_bytes())


def root_controlled(path, *, directory=False):
    """Approval/config authority is root, never the Docker service's own UID."""
    path = Path(path)
    require(path.is_absolute() and path.resolve() == path, 'approval_authority_invalid')
    for parent in reversed(path.parents):
        info = parent.lstat()
        require(stat.S_ISDIR(info.st_mode) and info.st_uid == 0
                and not info.st_mode & 0o022, 'approval_authority_invalid')
    info = path.lstat()
    require(info.st_uid == 0 and stat.S_IMODE(info.st_mode) in
            ((0o500, 0o700) if directory else (0o400, 0o600))
            and (stat.S_ISDIR(info.st_mode) if directory else
                 stat.S_ISREG(info.st_mode) and info.st_nlink == 1), 'approval_authority_invalid')
    return path


def publish(path, value, *, immutable=False):
    """Private, fsynced atomic publication. Immutable files cannot be overwritten."""
    path = Path(path)
    protected(path.parent, directory=True)
    require(path.name not in ('', '.', '..'), 'protected_path_invalid')
    if path.exists() or path.is_symlink():
        protected(path)
    fd, temporary = tempfile.mkstemp(prefix='.pending-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as out:
            if os.getuid() == 0:
                os.fchown(out.fileno(), path.parent.stat().st_uid, path.parent.stat().st_gid)
            json.dump(value, out, sort_keys=True, separators=(',', ':'), allow_nan=False)
            out.write('\n'); out.flush(); os.fsync(out.fileno())
            os.fchmod(out.fileno(), 0o400 if immutable else 0o600)
        if immutable:
            # link is an atomic no-clobber publication, then remove the temporary link.
            os.link(temporary, path, follow_symlinks=False)
        else:
            os.replace(temporary, path)
        Path(temporary).unlink(missing_ok=True)
        sync_directory(path.parent)
    finally:
        Path(temporary).unlink(missing_ok=True)


def sync_directory(path):
    fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


@contextlib.contextmanager
def deployment_lock(root):
    root = protected(root, directory=True)
    path = root / '.owner.lock'  # The regular ingestion owner uses this same inode.
    if path.exists() or path.is_symlink():
        protected(path)
    fd = os.open(path, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    try:
        require(os.fstat(fd).st_nlink == 1, 'protected_permissions_invalid')
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise Rejected('deployment_busy') from None
        yield
    finally:
        os.close(fd)
