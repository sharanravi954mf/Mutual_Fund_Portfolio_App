"""Private host adapter, installed behind the EXISTING webhook consumer only.

No Supabase deployment, financial controls, Docker or service restarts here.
"""
import argparse
import fcntl
import hashlib
import io
import json
import os
import shutil
import subprocess
import tarfile
import tempfile
from pathlib import Path

from contract import Rejected, git, load_policy, public_defines, require, revision, target
from observe import identity, read_json


def digest_tree(root):
    digest = hashlib.sha256()
    for path in sorted(root.rglob('*')):
        require(not path.is_symlink(), 'artifact_symlink_rejected')
        if path.is_file() and path.name != 'deployment.json':
            digest.update(path.relative_to(root).as_posix().encode() + b'\0')
            digest.update(hashlib.sha256(path.read_bytes()).digest())
    return digest.hexdigest()


def activate(root, env, sha, policy, latest, ancestor, build, config_digest):
    """Caller holds one environment lock across build AND final compare/activation."""
    revision(sha)
    p = target(env, policy)
    require(p['deployment_enabled'] is True, 'environment_not_commissioned')
    releases = root / 'releases'
    releases.mkdir(parents=True, exist_ok=True)
    current = root / 'current'
    if latest() != sha:
        return {'state': 'superseded', 'git_commit': sha}
    if current.exists():
        require(current.is_symlink() and current.resolve().parent == releases.resolve(), 'unsafe_current_path')
        old = json.loads((current / 'deployment.json').read_text())
        previous = revision(old.get('git_commit'))
        identity(old, env, previous, policy)
        require(ancestor(previous, sha), 'rollback_rejected')
    release = releases / sha
    if release.exists():
        require(not release.is_symlink(), 'unsafe_release_path')
        data = json.loads((release / 'deployment.json').read_text())
        identity(data, env, sha, policy)
        require(data.get('configuration_digest') == config_digest, 'immutable_configuration_changed')
        require(data.get('artifact_digest') == digest_tree(release), 'immutable_release_corrupt')
    else:
        # Same filesystem as release: no partially published immutable directories.
        with tempfile.TemporaryDirectory(prefix='.build-', dir=releases) as tmp:
            stage = Path(tmp)
            build(sha, stage)
            require((stage / 'index.html').is_file() and (stage / 'main.dart.js').is_file(), 'incomplete_build')
            (stage / 'release-health.json').write_text(json.dumps({'git_commit': sha, 'healthy': True}))
            data = {'schema_version': 1, 'application': 'MoneyBowl', 'environment': env.upper(),
                    'git_commit': sha, 'git_branch': p['branch'], 'supabase_project': p['project_ref'],
                    'artifact_digest': digest_tree(stage), 'configuration_digest': config_digest,
                    'assets': {name: hashlib.sha256((stage / name).read_bytes()).hexdigest()
                               for name in ('index.html', 'main.dart.js')}}
            (stage / 'deployment.json').write_text(json.dumps(data, sort_keys=True) + '\n')
            # TemporaryDirectory is 0700: published files must be readable by the web server.
            # No executable or writable-by-others asset modes survive publication.
            for path in stage.rglob('*'):
                path.chmod(0o755 if path.is_dir() else 0o644)
            stage.chmod(0o755)
            os.rename(stage, release)
    if latest() != sha:
        return {'state': 'superseded', 'git_commit': sha}
    temporary_link = root / '.current-next'
    temporary_link.unlink(missing_ok=True)
    temporary_link.symlink_to('releases/' + sha)
    os.replace(temporary_link, current)
    identity(json.loads((current / 'deployment.json').read_text()), env, sha, policy)
    return {'state': 'deployed', 'git_commit': sha, 'artifact_digest': data['artifact_digest']}


def locked_deploy(root, **kwargs):
    root.mkdir(parents=True, exist_ok=True)
    with (root / '.deployment.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        return activate(root=root, **kwargs)


def flutter_builder(repo, flutter, defines):
    def build(sha, stage):
        with tempfile.TemporaryDirectory(prefix='moneybowl-source-') as tmp:
            source = Path(tmp) / 'source'
            source.mkdir()
            archive = git(repo, 'archive', sha)
            with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
                tar.extractall(source, filter='data')
            settings = Path(tmp) / 'public-defines.json'
            settings.write_text(json.dumps(defines))
            home = Path(tmp) / 'home'
            home.mkdir()
            # Do not inherit backend secrets, proxies, arbitrary dart defines or build hooks.
            process_env = {'PATH': str(flutter.parent) + ':/usr/local/bin:/usr/bin:/bin',
                           'HOME': str(home), 'CI': 'true', 'LANG': 'C.UTF-8'}
            for arguments in (['pub', 'get', '--enforce-lockfile'],
                              ['analyze', '--no-fatal-warnings', '--no-fatal-infos'], ['test'],
                              ['build', 'web', '--release', '--dart-define-from-file=' + str(settings)]):
                try:
                    subprocess.run([str(flutter), *arguments], cwd=source, env=process_env,
                                   check=True, timeout=1800, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                except (subprocess.SubprocessError, OSError):
                    raise Rejected('flutter_build_failed') from None
            shutil.copytree(source / 'build/web', stage, dirs_exist_ok=True)
    return build


def run(config, policy, requested=None):
    env = config['environment']
    require(env in ('dev', 'qa'), 'invalid_environment')
    require(policy[env]['deployment_enabled'] is True, 'environment_not_commissioned')
    p = target(env, policy)
    require(config['host_authority'] == p['host_authority'], 'wrong_host_authority')
    repo, root, flutter = (Path(config[key]).resolve() for key in ('repository', 'release_root', 'flutter'))
    require(root != repo and repo not in root.parents and root not in repo.parents, 'unsafe_release_root')
    defines = public_defines(json.loads(Path(config['public_defines']).read_text()), env, policy)
    require(git(repo, 'remote', 'get-url', 'origin').decode().strip() in (
        'https://github.com/sharanravi954mf/Mutual_Fund_Portfolio_App.git',
        'git@github.com:sharanravi954mf/Mutual_Fund_Portfolio_App.git'), 'wrong_repository')

    def latest():
        git(repo, 'fetch', '--quiet', 'origin', p['branch'])
        return revision(git(repo, 'rev-parse', 'FETCH_HEAD').decode().strip())

    def ancestor(old, new):
        try:
            git(repo, 'merge-base', '--is-ancestor', old, new)
            return True
        except Rejected:
            return False

    if requested is not None:
        revision(requested)
    # Existing spool calls with no SHA; each iteration converges toward current branch.
    # A separately installed timer re-drives failures/missed deliveries with this same lock.
    for _ in range(4):
        sha = requested or latest()
        result = locked_deploy(root, env=env, sha=sha, policy=policy, latest=latest,
                               ancestor=ancestor, build=flutter_builder(repo, flutter, defines),
                               config_digest=hashlib.sha256(json.dumps(defines, sort_keys=True).encode()).hexdigest())
        if result['state'] == 'superseded':
            if requested:
                return result
            continue
        public = read_json(config['frontend_origin'].rstrip('/') + '/deployment.json?revision=' + sha)
        identity(public, env, sha, policy)
        require(public.get('artifact_digest') == result['artifact_digest'], 'public_artifact_mismatch')
        if latest() != sha:
            if requested:
                return {'state': 'superseded', 'git_commit': sha}
            continue
        return result
    raise Rejected('branch_busy_reconciliation_required')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', required=True)
    parser.add_argument('--revision')
    args = parser.parse_args()
    try:
        report = run(json.loads(Path(args.config).read_text()), load_policy(), args.revision)
    except Rejected as error:
        report = {'state': 'failed', 'reason': str(error)}
    except Exception:
        report = {'state': 'failed', 'reason': 'host_deployment_failed'}
    print(json.dumps(report, sort_keys=True))
    return 1 if report['state'] == 'failed' else 0


if __name__ == '__main__':
    raise SystemExit(main())
