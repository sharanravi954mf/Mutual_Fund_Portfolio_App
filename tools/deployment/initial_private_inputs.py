"""Root-operated cutover inputs; no general protected-path exemptions or migration.

Only these two independently approved runtime secrets may be group-readable.
The GitHub path is a proposed protected migration destination, never the old home path.
"""
import contextlib
import hashlib
import json
import os
import stat
from pathlib import Path

from contract import DEV_PROJECT, Rejected, require
from protected_io import root_controlled

EXTERNAL_SECRETS = {
    'm3b-webhook-v1': dict(path='/etc/moneybowl-director/m3b-webhook-secret',
        gid=10001, service='m3b-receiver', destination='/run/secrets/m3b_webhook_secret',
        runtime_user='10001:10001'),
    'github-webhook-v1': dict(path='/etc/moneybowl-deployment/runtime-secrets/github-webhook-secret',
        gid=1001, service='github-webhook', destination='/run/secrets/github_webhook_secret',
        runtime_user='1001:1001'),
}
IDENTITY_KEYS = {'device', 'inode', 'uid', 'gid', 'mode'}


def identity(info):
    return dict(device=info.st_dev, inode=info.st_ino, uid=info.st_uid,
                gid=info.st_gid, mode=stat.S_IMODE(info.st_mode))


def no_acl(path):
    # A named ACL reader could otherwise hide behind the approved group mode.
    require(not {'system.posix_acl_access', 'system.posix_acl_default'} &
            set(os.listxattr(path, follow_symlinks=False)), 'private_input_acl_unapproved')


def trusted_path(path):
    path = Path(path)
    require(path.is_absolute() and path.resolve() == path, 'private_input_path_invalid')
    for parent in reversed(path.parents):
        info = parent.lstat()
        require(stat.S_ISDIR(info.st_mode) and info.st_uid == 0 and not info.st_mode & 0o022,
                'private_input_parent_invalid')
        no_acl(parent)
    info = path.lstat()
    require(stat.S_ISREG(info.st_mode) and info.st_nlink == 1, 'private_input_file_invalid')
    no_acl(path)
    return path, info


def signature(info):
    return (identity(info), info.st_nlink, info.st_size, info.st_mtime_ns, info.st_ctime_ns)


@contextlib.contextmanager
def checked_file(path, info):
    """Read only the checked inode; reject substitution before reading any bytes."""
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC)
    try:
        require(signature(os.fstat(fd)) == signature(info), 'private_input_identity_changed')
        yield fd
        require(signature(os.fstat(fd)) == signature(info), 'private_input_changed_during_read')
        _, after = trusted_path(path)
        require(signature(after) == signature(info), 'private_input_identity_changed')
    finally:
        os.close(fd)


def file_digest(path, info):
    with checked_file(path, info) as fd:
        digest = hashlib.sha256()
        while block := os.read(fd, 1024 * 1024):
            digest.update(block)
    return digest.hexdigest()


def checked_input(item):
    """Metadata/policy verification only. Caller must already have real root authority."""
    require(os.getuid() == os.geteuid() == 0, 'cutover_requires_root_operator')
    require(isinstance(item, dict) and item.get('approval') and
            isinstance(item.get('sha256'), str) and len(item['sha256']) == 64
            and all(c in '0123456789abcdef' for c in item['sha256']), 'private_inputs_unapproved')
    expected = item.get('identity')
    require(isinstance(expected, dict) and set(expected) == IDENTITY_KEYS
            and all(type(v) is int and v >= 0 for v in expected.values())
            and expected['inode'] > 0, 'private_input_identity_unapproved')
    policy = item.get('policy', 'root-private-v1')
    rule = EXTERNAL_SECRETS.get(policy)
    require(policy == 'root-private-v1' or rule is not None, 'external_secret_policy_unapproved')
    if rule is None:
        require('policy_record' not in item, 'external_secret_policy_unapproved')
        root_controlled(item['path'])  # Same root-only authority; private modes stay strict.
    else:
        require(item['path'] == rule['path'], 'external_secret_path_unapproved')
    path, info = trusted_path(item['path'])
    require(identity(info) == expected, 'private_input_identity_changed')
    policy_digest = None
    if rule is not None:
        require(info.st_uid == 0 and info.st_gid == rule['gid']
                and stat.S_IMODE(info.st_mode) == 0o440, 'external_secret_permissions_invalid')
        record = item.get('policy_record', {})
        require(isinstance(record, dict) and set(record) == {'path', 'sha256'},
                'external_secret_policy_unapproved')
        policy_path = root_controlled(record['path'])
        _, policy_info = trusted_path(policy_path)
        with checked_file(policy_path, policy_info) as fd:
            raw = b''
            while len(raw) < 65537:
                block = os.read(fd, 65537 - len(raw))
                if not block:
                    break
                raw += block
        policy_digest = hashlib.sha256(raw).hexdigest()
        require(len(raw) <= 65536 and policy_digest == record['sha256'], 'external_secret_policy_changed')
        value = json.loads(raw)
        review = value.get('owner_review')
        require(isinstance(review, str) and bool(review.strip()) and value == dict(
            kind='moneybowl-external-secret-policy-v1', environment='dev', project_ref=DEV_PROJECT,
            policy=policy, **rule, uid=0, mode=0o440, read_only=True,
            identity=expected, sha256=item['sha256'], owner_review=review),
            'external_secret_policy_unapproved')
    return path, info, rule, policy_digest


def binding(item):
    path, info, _, policy_digest = checked_input(item)
    require(file_digest(path, info) == item['sha256'], 'private_input_changed')
    return dict(sha256=item['sha256'], identity=identity(info), policy_sha256=policy_digest)


def bind_mounts(items, containers):
    """Reject direct/ancestor exposure; only an exact approved external file reader is allowed."""
    binds = []
    for container in containers:
        for mount in container.get('mounts', []):
            if mount.get('Type') != 'bind':
                continue
            source = mount.get('Source')
            require(isinstance(source, str) and Path(source).is_absolute(), 'private_bind_source_unverifiable')
            try:
                canonical = Path(source).resolve(strict=True)
            except (OSError, RuntimeError, ValueError):
                raise Rejected('private_bind_source_unverifiable') from None
            binds.append((container, mount, canonical))
    for item in items:
        path, _, rule, _ = checked_input(item)
        mounts = [(container, mount) for container, mount, source in binds
                  if source == path or source in path.parents]
        # Root-private inputs authorize host use only, never a container reader.
        require(rule is not None or not mounts, 'private_input_mount_unapproved')
        require(all(mount.get('RW') is False for _, mount in mounts), 'private_input_mount_writable')
        if rule is not None:
            require(len(mounts) == 1, 'external_secret_mount_unapproved')
            container, mount = mounts[0]
            require(mount.get('Source') == str(path)
                    and container['labels'].get('com.docker.compose.service') == rule['service']
                    and container['security'].get('user') == rule['runtime_user']
                    and mount.get('Destination') == rule['destination'], 'external_secret_mount_unapproved')
