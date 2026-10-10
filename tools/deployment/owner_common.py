"""Private-owner primitives. Installed code/configuration are outside writable application Git."""
import contextlib
import fcntl
import hashlib
import io
import json
import os
import subprocess
import tarfile
import tempfile
from pathlib import Path

from contract import REPOSITORY, git, require, revision, target


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def binding(config, policy):
    env = config.get('environment')
    require(env in ('dev', 'qa'), 'invalid_environment')
    require(policy[env]['deployment_enabled'] is True, 'environment_not_commissioned')
    require(config.get('commissioned') is True, 'owner_not_commissioned')
    p = target(env, policy)
    require(config.get('project_ref') == p['project_ref'], 'wrong_project_binding')
    return env, p


def envelope(env, p, sha):
    return dict(schema_version=1, environment=env.upper(), git_commit=revision(sha),
                git_branch=p['branch'], supabase_project=p['project_ref'])


def latest(repo, branch):
    require(git(repo, 'remote', 'get-url', 'origin').decode().strip() in (
        'https://github.com/' + REPOSITORY + '.git', 'git@github.com:' + REPOSITORY + '.git'),
        'wrong_repository')
    git(repo, 'fetch', '--quiet', 'origin', branch)
    return revision(git(repo, 'rev-parse', 'FETCH_HEAD').decode().strip())


def atomic_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix='.pending-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as out:
            json.dump(value, out, sort_keys=True)
            out.write('\n')
            out.flush()
            os.fsync(out.fileno())
        os.chmod(temporary, 0o644)
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


@contextlib.contextmanager
def lock(root):
    root = Path(root)
    root.mkdir(parents=True, exist_ok=True)
    with (root / '.owner.lock').open('a') as handle:
        fcntl.flock(handle, fcntl.LOCK_EX)
        yield


@contextlib.contextmanager
def source_tree(repo, sha):
    with tempfile.TemporaryDirectory(prefix='m4-owner-source-') as tmp:
        with tarfile.open(fileobj=io.BytesIO(git(repo, 'archive', revision(sha)))) as archive:
            require(all(member.isfile() or member.isdir() for member in archive.getmembers()),
                    'source_link_rejected')
            archive.extractall(tmp, filter='data')
        yield Path(tmp)


def private_config(path):
    path = Path(path)
    require(path.is_absolute() and not path.is_symlink(), 'owner_config_path_invalid')
    require(path.stat().st_uid in (0, os.getuid()) and path.stat().st_mode & 0o077 == 0,
            'owner_config_permissions_invalid')
    value = json.loads(path.read_text())
    repo = Path(value['repository']).resolve()
    require(repo not in path.resolve().parents, 'owner_config_in_source')
    for name in ('state_root', 'report_root', 'release_status_root', 'compose_root'):
        if name in value:
            location = Path(value[name])
            require(location.is_absolute() and not location.is_symlink() and
                    location.resolve() != repo and repo not in location.resolve().parents,
                    'owner_path_in_source')
    return value


class Command:
    """No shell, no inherited application credentials, no child output in diagnostics."""
    def __init__(self, extra_env=None):
        self.env = {'PATH': '/usr/local/bin:/usr/bin:/bin', 'LANG': 'C.UTF-8', **(extra_env or {})}

    def __call__(self, argv, cwd=None, timeout=180):
        from contract import Rejected
        require(Path(argv[0]).is_absolute(), 'executable_not_absolute')
        try:
            with tempfile.TemporaryFile() as output:
                subprocess.run(argv, cwd=cwd, env=self.env, stdout=output, stderr=subprocess.DEVNULL,
                               timeout=timeout, check=True)
                output.seek(0)
                data = output.read(16 * 1024 * 1024 + 1)
                require(len(data) <= 16 * 1024 * 1024, 'owner_output_oversized')
                return data
        except (OSError, subprocess.SubprocessError):
            raise Rejected('owner_command_failed') from None


def pinned_executable(config, key):
    path = Path(config[key])
    require(path.is_absolute() and not path.is_symlink() and path.is_file(), 'invalid_owner_executable')
    require(sha256(path.read_bytes()) == config[key + '_sha256'], 'owner_executable_changed')
    return str(path)
