"""Sealed root API-only adapter: pull, one activation, independent observations.

Not installed. No caller-controlled Compose paths or command transport is exposed
by the production launcher. Tests replace OS transports, not admission decisions.
"""
import contextlib
import fcntl
import io
import json
import os
import re
import selectors
import signal
import stat
import subprocess
import time
import zipfile
from pathlib import Path

from contract import DEV_PROJECT, REPOSITORY, Rejected, require, revision
from initial_private_inputs import checked_file, trusted_path, identity, file_digest, binding, bind_mounts
from owner_common import sha256, envelope
from protected_io import root_controlled, read_private
from ingestion_owner import DockerOwner, API_COMMAND, DEV_RETIRED_CONTAINER, DEV_RETIRED_SERVICES, DEV_RETIRED_TIMER
from oci_delivery import IMAGE, WORKFLOW, PREDICATE
from observe import read_json
import initial_transition_integrity
import compose_inventory as inventory

SOCKET_PATH = '/run/moneybowl-api-executor/reconcile.sock'
POLICY_PATH = Path('/etc/moneybowl-deployment/api-executor-v2.json')
INITIAL_SOURCE = '8afa04f9db4a3429fdfeef503d4ebaf6abf18aa5'
INITIAL_IMAGE = IMAGE + '@sha256:257c0fd51f3d47a8d24031fd90333945c804a159ad6779301226edcd3fc80945'
INITIAL_COMPONENT = '5f06254a13cb666449336425b1a66d31fa8db4afbb30d78d0bc7687dd67d5fd5'
REVIEWED_SOURCE_FILES = {WORKFLOW, 'services/ingestion-support/compose.yaml',
    'services/ingestion-support/compose.hosted.yaml', 'services/ingestion-support/Caddyfile'}
UNRELATED = {'caddy', 'clamav', 'github-webhook', 'm3b-receiver', 'm3b-ingress-adapter'}


def _sealed_read(item, limit=1024 * 1024, public_code=False):
    """An approved root inode and checked descriptor, including all ancestors/ACLs."""
    path = Path(item['path']) if public_code else root_controlled(item['path'])
    _, info = trusted_path(path)
    if public_code:
        require(info.st_uid == info.st_gid == 0 and stat.S_IMODE(info.st_mode) in (0o400, 0o444), 'executor_code_permissions_invalid')
    require(identity(info) == item['identity'], 'runtime_file_identity_changed')
    with checked_file(path, info) as fd:
        raw = b''
        while len(raw) <= limit:
            block = os.read(fd, min(65536, limit + 1 - len(raw)))
            if not block:
                break
            raw += block
    require(len(raw) <= limit and sha256(raw) == item['sha256'], 'runtime_file_changed')
    return raw


def sealed_read(item, limit=1024 * 1024, public_code=False):
    try:
        return _sealed_read(item, limit, public_code)
    except OSError:
        raise Rejected('runtime_file_unavailable') from None


def load_authority():
    require(os.getuid() == os.geteuid() == 0 and os.getgid() == os.getegid() == 0, 'executor_requires_root')
    from initial_api_transition import installed_code
    installed_code()
    root_controlled(POLICY_PATH)
    _, info = trusted_path(POLICY_PATH)
    with checked_file(POLICY_PATH, info) as fd:
        from restricted_execution import decoded
        raw = os.read(fd, 65537)
        value = decoded(raw)
    require(value.get('kind') == 'moneybowl-api-executor-v2'
            and value.get('enabled') is True and value.get('owner_review'), 'executor_disabled')
    require(value.get('repository') == REPOSITORY and value.get('image_repository') == IMAGE
            and value.get('project_ref') == DEV_PROJECT and value.get('branch') == 'develop'
            and value.get('publication_disclosure_approved') is True, 'executor_policy_invalid')
    require(value.get('initial_source') == INITIAL_SOURCE and value.get('initial_image') == INITIAL_IMAGE
            and value.get('initial_component') == INITIAL_COMPONENT, 'executor_initial_policy_invalid')
    require(value.get('namespace') == 'host-user-and-pid-v1'
            and value.get('owner_cgroup') == '/system.slice/moneybowl-ingestion-deploy.service', 'executor_peer_policy_invalid')
    require(type(value.get('github_repository_id')) is int and value['github_repository_id'] > 0
            and type(value.get('approved_reviewers')) is dict and value['approved_reviewers']
            and all(type(v) is str and re.fullmatch('[a-zA-Z0-9-]{1,39}', v) and type(uid) is int and uid > 0
                    for v, uid in value['approved_reviewers'].items()),
            'executor_source_review_policy_invalid')
    directory = Path(__file__).resolve().parent
    code = value.get('code_seals', [])
    require({item['path'] for item in code} == {str(p) for p in directory.glob('*.py')} | {str(directory/'environments.json')},
            'executor_code_seals_missing')
    for item in code:
        sealed_read(item, public_code=True)
    config = json.loads(sealed_read(value['owner_config_seal']))
    value['owner_config'] = config
    require(config.get('initial_transition', {}).get('acceptance_required') is True
            and config['state_root'] == value['state_root']
            and config['initial_transition']['image'] == INITIAL_IMAGE
            and config['initial_transition']['source_revision'] == INITIAL_SOURCE
            and config['initial_transition']['source_digest'] == INITIAL_COMPONENT
            and config['initial_transition']['candidate_image_id'] == INITIAL_IMAGE.split('@')[1],
            'executor_initial_policy_invalid')
    root_controlled(value['state_root'], directory=True)
    root_controlled(value['journal_root'], directory=True)
    root_controlled(value['receipt_root'], directory=True)
    root_controlled(value['source_mirror'], directory=True)
    # Private registry authority must not be writable/readable by UID 993.
    require(config.get('environment') == 'dev' and config.get('project_ref') == DEV_PROJECT
            and config.get('image_repository') == IMAGE and config.get('registry', {}).get('private') is True,
            'executor_owner_policy_invalid')
    root_controlled(config['docker_config'], directory=True)
    auth_path = str(Path(config['docker_config']) / 'config.json')
    root_controlled(auth_path)
    require({item['path'] for item in value['credential_seals']} >= {auth_path}, 'executor_credentials_unsealed')
    for item in value['credential_seals']:
        sealed_read(item)
    return value, raw


class Process:
    def __init__(self, policy):
        self.policy = policy
        self.env = {'PATH': '/usr/bin:/bin', 'LANG': 'C.UTF-8', 'HOME': '/nonexistent',
                    'GIT_CONFIG_NOSYSTEM': '1', 'GIT_CONFIG_GLOBAL': '/dev/null',
                    'DOCKER_CONFIG': policy['owner_config']['docker_config'], 'GIT_NO_REPLACE_OBJECTS': '1'}
        # Optional independently provisioned read-only GitHub credential. No runtime
        # financial secrets are inherited. Its approved bytes never enter logs/argv.
        if policy.get('github_token_seal'):
            self.env['GH_TOKEN'] = sealed_read(policy['github_token_seal'], 4096).decode().strip()
        self.tools = {}
        for key in ('docker', 'compose_plugin', 'systemctl', 'gh', 'git'):
            item = policy['executables'][key]
            path, info = trusted_path(item['path'])
            require(info.st_uid == 0 and not info.st_mode & 0o022 and stat.S_ISREG(info.st_mode)
                    and identity(info) == item['identity'] and file_digest(path, info) == item['sha256'],
                    'executor_executable_changed')
            self.tools[key] = str(path)

    def __call__(self, argv, cwd=None, timeout=30, pass_fds=()):
        require(argv[0] in self.tools.values(), 'executor_executable_forbidden')
        try:
            process = subprocess.Popen(argv, cwd=cwd, env=self.env, stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL, pass_fds=pass_fds)
            deadline, output = time.monotonic() + min(timeout, 180), bytearray()
            try:
                with selectors.DefaultSelector() as selector:
                    selector.register(process.stdout, selectors.EVENT_READ)
                    while selector.get_map():
                        remaining = deadline - time.monotonic()
                        require(remaining > 0, 'executor_delivery_unknown')
                        ready = selector.select(min(remaining, 1))
                        for key, _ in ready:
                            block = os.read(key.fileobj.fileno(), 65536)
                            if not block:
                                selector.unregister(key.fileobj)
                            else:
                                output.extend(block)
                                require(len(output) <= 4 * 1024 * 1024, 'executor_output_oversized')
                require(process.wait(timeout=max(.01, deadline - time.monotonic())) == 0, 'executor_delivery_unknown')
                return bytes(output)
            finally:
                if process.poll() is None:
                    process.kill()
                process.wait()
                process.stdout.close()
                # Parent broker also kills the whole worker group, including Compose
                # descendants, on expiry or completion. No uncertain call is retried.
        except (OSError, subprocess.SubprocessError):
            raise Rejected('executor_delivery_unknown') from None

    def capacity(self):
        inventory.capacity(self.policy['owner_config'])

    def verify_attestation(self, image, sha):
        return self([self.tools['gh'], 'attestation', 'verify', 'oci://' + image,
            '--repo', REPOSITORY, '--signer-workflow', REPOSITORY + '/' + WORKFLOW,
            '--signer-digest', sha, '--source-digest', sha, '--source-ref', 'refs/heads/develop',
            '--cert-identity', 'https://github.com/' + REPOSITORY + '/' + WORKFLOW + '@refs/heads/develop',
            '--cert-oidc-issuer', 'https://token.actions.githubusercontent.com',
            '--deny-self-hosted-runners', '--predicate-type', PREDICATE, '--format', 'json'], timeout=60)

    def artifact(self, run_id, artifact_id):
        require(type(artifact_id) is int and artifact_id > 0, 'artifact_id_invalid')
        raw = self([self.tools['gh'], 'api', f'repos/{REPOSITORY}/actions/artifacts/{artifact_id}/zip'])
        with zipfile.ZipFile(io.BytesIO(raw)) as z:
            names = z.infolist()
            require(len(names) == 1 and names[0].filename == 'identity.json'
                    and names[0].file_size <= 4096 and names[0].compress_size <= 65536
                    and not names[0].flag_bits & 1
                    and stat.S_IFMT(names[0].external_attr >> 16) in (0, stat.S_IFREG), 'artifact_archive_invalid')
            from restricted_execution import decoded
            return decoded(z.read(names[0]))


class SealedSource:
    def __init__(self, policy, process):
        self.policy, self.process = policy, process
        self.repo = policy['source_mirror']
        self.sha = None

    def git(self, *args):
        return self.process([self.process.tools['git'], '--git-dir', self.repo,
            '-c', 'core.hooksPath=/dev/null', '-c', 'credential.helper=', '-c', 'core.fsmonitor=false',
            '-c', 'protocol.file.allow=never', '-c', 'protocol.ext.allow=never',
            '-c', 'fetch.recurseSubmodules=false', '-c', 'gc.auto=0', '-c', 'maintenance.auto=false', *args], timeout=60)

    def check(self, sha):
        revision(sha)
        root_controlled(self.repo, directory=True)
        for path in Path(self.repo).rglob('*'):
            info = path.lstat()
            require(info.st_uid == 0 and not info.st_mode & 0o022 and not path.is_symlink(), 'source_mirror_authority_changed')
            from initial_private_inputs import no_acl
            no_acl(path)
        require({item['path'] for item in self.policy['source_authority_seals']} >= {str(Path(self.repo)/'config')}
                and not any((Path(self.repo)/name).exists() for name in ('shallow', 'info/grafts', 'objects/info/alternates')),
                'source_mirror_policy_invalid')
        for item in self.policy['source_authority_seals']:
            sealed_read(item)
        config = self.git('config', '--local', '--no-includes', '--list').decode().splitlines()
        require('core.bare=true' in config and all(line.startswith(('core.repositoryformatversion=',
                'core.filemode=', 'core.bare=', 'core.logallrefupdates=', 'remote.origin.url=', 'remote.origin.fetch='))
                for line in config) and all(not line.startswith('remote.origin.url=') or
                    line == 'remote.origin.url=https://github.com/'+REPOSITORY+'.git' for line in config), 'source_git_config_invalid')
        self.git('fetch', '--no-tags', '--no-recurse-submodules', 'https://github.com/' + REPOSITORY + '.git', 'develop')
        require(self.git('rev-parse', 'FETCH_HEAD').decode().strip() == sha, 'source_head_changed')
        self.git('merge-base', '--is-ancestor', INITIAL_SOURCE, sha)
        require(set(self.policy['infrastructure_source_sha256']) >= REVIEWED_SOURCE_FILES, 'source_policy_seals_missing')
        for path, pin in self.policy['infrastructure_source_sha256'].items():
            require(sha256(self.git('show', sha + ':' + path)) == pin, 'source_policy_change_requires_review')
        self.sha = sha

    def component(self, sha):
        require(sha in (self.sha, INITIAL_SOURCE), 'source_not_checked')
        raw = self.git('ls-tree', '-r', sha, '--', 'services/ingestion-support')
        require(raw and all(line.split(b' ', 1)[0] in (b'100644', b'100755') for line in raw.splitlines()),
                'source_type_invalid')
        return sha256(raw)

    def initial(self):
        p = self.policy
        # Original helper reads immutable retained Git objects and the original
        # permanent plan/journal/verification/receipt tuple. Nothing is regenerated.
        initial_transition_integrity.completed(p['owner_config'], p['environment_policy'], self.repo,
            component_manifest=lambda repo, sha: {'ingestion_support': self.component(sha)})
        required = {'initial-transition.json', 'initial-plan.json', 'initial-verification.json',
                    'initial-service-receipt.json', INITIAL_SOURCE + '.provenance.json'}
        paths = {Path(item['path']) for item in p['initial_acceptance_seals']}
        state = Path(p['state_root'])
        require({state/name for name in required} <= paths
                and any(v.parent == state and re.fullmatch(r'approval-[0-9a-f]{64}\.consumed\.json', v.name) for v in paths),
                'initial_tuple_missing')
        for item in p['initial_acceptance_seals']:
            sealed_read(item)
        return read_private(state/'initial-verification.json')['after']['api']


@contextlib.contextmanager
def sealed_memfd(raw):
    fd = os.memfd_create('moneybowl-approved-api', os.MFD_CLOEXEC | os.MFD_ALLOW_SEALING)
    try:
        view = memoryview(raw)
        while view:
            size = os.write(fd, view)
            require(size > 0, 'executor_short_write')
            view = view[size:]
        os.lseek(fd, 0, os.SEEK_SET)
        fcntl.fcntl(fd, fcntl.F_ADD_SEALS, fcntl.F_SEAL_WRITE | fcntl.F_SEAL_GROW | fcntl.F_SEAL_SHRINK | fcntl.F_SEAL_SEAL)
        yield fd
    finally:
        os.close(fd)


def runtime_model(raw, proof):
    from restricted_execution import decoded
    model = decoded(raw, 1024 * 1024)
    require(set(model) <= {'name', 'services', 'networks', 'volumes'}
            and model.get('name') == 'moneybowl-ingestion-support'
            and set(model.get('services', {})) == {'api'}, 'executor_runtime_scope')
    api = model['services']['api']
    allowed = {'image', 'user', 'command', 'entrypoint', 'restart', 'environment', 'healthcheck',
               'cap_drop', 'cpus', 'mem_limit', 'pids_limit', 'security_opt', 'read_only',
               'tmpfs', 'networks', 'volumes', 'ports', 'labels', 'init', 'working_dir'}
    require(set(api) <= allowed and api.get('image') == INITIAL_IMAGE
            and api.get('user') == '10001:10001' and api.get('command') == API_COMMAND
            and api.get('entrypoint') == [] and api.get('cap_drop') == ['ALL']
            and api.get('security_opt') == ['no-new-privileges:true'] and api.get('read_only') is True
            and api.get('cpus') == 1.0 and api.get('mem_limit') == '512m'
            and api.get('pids_limit') == 128 and api.get('restart') == 'unless-stopped'
            and not api.get('init') and api.get('working_dir', '/app') == '/app', 'executor_runtime_security')
    require(type(api.get('environment')) is dict and api['environment']
            and all(type(k) is str and re.fullmatch('[A-Z][A-Z0-9_]{0,63}', k)
                    and type(v) is str and len(v) <= 4096 and '${' not in v for k, v in api['environment'].items()),
            'executor_runtime_environment')
    # Only pre-existing external resources; Compose cannot create dependencies.
    for kind in ('networks', 'volumes'):
        require(type(model.get(kind, {})) is dict and all(type(v) is dict and set(v) == {'external', 'name'}
                and v['external'] is True and re.fullmatch('[a-zA-Z0-9_.-]+', v['name'])
                for v in model.get(kind, {}).values()), 'executor_resource_scope')
    mounts = api.get('volumes', [])
    require(type(mounts) is list and all(type(v) is dict and set(v) == {'type', 'source', 'target', 'read_only'}
            and v['type'] == 'volume' and v['source'] in model.get('volumes', {})
            and v['target'] == '/tmp' and v['read_only'] is False for v in mounts), 'executor_mount_scope')
    require(api.get('tmpfs') in (['/tmp:size=16m,mode=1777'], None)
            and not (mounts and api.get('tmpfs')), 'executor_tmpfs_scope')
    require(type(api.get('networks')) is dict and set(api['networks']) <= set(model.get('networks', {}))
            and all(set(v) == {'aliases'} and v['aliases'] in ([], ['api']) for v in api['networks'].values()),
            'executor_network_scope')
    require(api.get('ports') == ['127.0.0.1:8080:8080'] and api.get('healthcheck') == {
        'test': ['CMD', 'python', '-c', "import urllib.request; urllib.request.urlopen('http://localhost:8080/ready', timeout=3).read()"],
        'interval': '10s', 'timeout': '5s', 'retries': 12, 'start_period': '10s'}, 'executor_probe_scope')
    require(api.get('labels') == {'moneybowl.environment': 'dev'}, 'executor_runtime_labels')
    api['image'] = proof['image']
    api['labels'].update({'org.opencontainers.image.revision': proof['git_commit'],
                          'moneybowl.source_digest': proof['source_digest']})
    # Compose interpolation remains active even for JSON. Escape all literal dollars;
    # no ambient environment or env_file is used by the sealed child process.
    def literal(value):
        if type(value) is str:
            return value.replace('$', '$$')
        if type(value) is dict:
            return {k: literal(v) for k, v in value.items()}
        if type(value) is list:
            return [literal(v) for v in value]
        return value
    return json.dumps(literal(model), sort_keys=True).encode()


class ApiEngine:
    """All Engine calls are constructed here from fixed semantics and root policy."""
    container = DockerOwner.container
    retirement = DockerOwner.retirement

    def __init__(self, policy, process):
        self.policy, self.command = policy, process
        self.config = policy['owner_config']
        self.docker, self.systemctl = process.tools['docker'], process.tools['systemctl']
        self.base = [self.docker, '--host', 'unix:///var/run/docker.sock']
        actual = process(self.base + ['info', '--format',
            '{{range .ClientInfo.Plugins}}{{if eq .Name "compose"}}{{.Path}}{{end}}{{end}}']).decode().strip()
        require(actual == process.tools['compose_plugin'], 'executor_compose_plugin_changed')
        self.planned = None

    def containers(self, service):
        require(service in UNRELATED | {'api'}, 'executor_service_forbidden')
        ids = self.command(self.base + ['ps', '--all', '--quiet', '--no-trunc', '--filter',
            'label=com.docker.compose.project=moneybowl-ingestion-support', '--filter',
            'label=com.docker.compose.service=' + service]).decode().split()
        require(len(ids) == 1 and re.fullmatch('[0-9a-f]{64}', ids[0]), 'executor_service_inventory')
        value = self.container(ids[0])
        require(value['labels'].get('com.docker.compose.project') == 'moneybowl-ingestion-support'
                and value['labels'].get('com.docker.compose.service') == service, 'executor_service_owner')
        return value

    def observation(self):
        require(self.command(self.base + ['info', '--format', '{{.ID}}']).decode().strip() == self.policy['daemon_id'],
                'executor_daemon_changed')
        require(self.command(self.base + ['info', '--format', '{{.DockerRootDir}}']).decode().strip() == self.config['docker_data_root'],
                'executor_storage_changed')
        self.command.capacity()
        self.retirement()
        result = {name: self.containers(name) for name in sorted(UNRELATED | {'api'})}
        ids = self.command(self.base + ['ps', '--all', '--quiet', '--no-trunc', '--filter',
                          'label=com.docker.compose.project=moneybowl-ingestion-support']).decode().split()
        require(len(ids) == 7 and set(ids) == {v['id'] for v in result.values()} | {self.config['retired_container_id']},
                'executor_project_inventory')
        for name, value in result.items():
            s = value['state']
            require(s['Running'] is True and s['Status'] == 'running' and s['Pid'] > 0
                    and not any(s[k] for k in ('Restarting', 'Paused', 'Dead'))
                    and s.get('Health', {}).get('Status') in (('healthy',) if name in
                        {'api', 'clamav', 'github-webhook', 'm3b-receiver'} else (None, 'healthy')),
                    'executor_service_unhealthy')
            require(inventory.runtime_identity(value) == self.policy['runtime_identities'][name], 'executor_runtime_drift')
            if name != 'api':
                require(value['id'] == self.policy['unrelated'][name]['id']
                        and value['image'] == self.policy['unrelated'][name]['image'], 'executor_unrelated_drift')
        api = result['api']
        # Compare actual environment privately against the sealed runtime input.
        # Values are kept only in root memory and never copied into observations,
        # journals, receipts, exceptions or stdout.
        from restricted_execution import decoded
        approved_env = decoded(sealed_read(self.policy['runtime_seal']), 1024 * 1024)['services']['api']['environment']
        actual_env = json.loads(self.command(self.base + ['inspect', '--format', '{{json .Config.Env}}', api['id']]))
        require(type(actual_env) is list and all(type(v) is str and '=' in v for v in actual_env), 'executor_api_environment_invalid')
        actual = dict(v.split('=', 1) for v in actual_env)
        image_keys = {'PATH', 'LANG', 'GPG_KEY', 'PYTHON_VERSION', 'PYTHON_SHA256',
                      'PYTHONDONTWRITEBYTECODE', 'PYTHONUNBUFFERED', 'PIP_DISABLE_PIP_VERSION_CHECK', 'PIP_NO_CACHE_DIR'}
        require(len(actual) == len(actual_env) and set(actual) <= set(approved_env) | image_keys
                and all(actual.get(k) == v for k, v in approved_env.items()), 'executor_api_environment_changed')
        require(api['security'] == {'readonly': True, 'privileged': False, 'caps': ['ALL'],
                'options': ['no-new-privileges:true'], 'user': '10001:10001'}
                and api['command'] == API_COMMAND and not api['entrypoint'], 'executor_api_security')
        # Verify actual process table: one non-root uvicorn worker, no shells or exec.
        raw = self.command(self.base + ['top', api['id'], '-eo', 'uid,args']).decode().splitlines()
        require(len(raw) == 2 and raw[1].split(None, 1)[0] == '10001', 'executor_api_process_invalid')
        args = raw[1].split(None, 1)[1].split()
        require(args == API_COMMAND or (len(args) == len(API_COMMAND)+1
                and re.fullmatch(r'/usr/local/bin/python(?:3(?:\.12)?)?', args[0])
                and args[1:] == ['/usr/local/bin/uvicorn', *API_COMMAND[1:]]), 'executor_api_process_invalid')
        # Project resources retain identity/config; endpoint membership changes are
        # intentionally excluded when the API container is replaced.
        require(set(self.policy['resources'].get('network', {})) == {name for v in result.values() for name in v['networks']}
                and set(self.policy['resources'].get('volume', {})) == {m['Name'] for v in result.values()
                    for m in v['mounts'] if m['Type'] == 'volume'}, 'executor_resource_inventory')
        resources = {}
        for kind, names in self.policy['resources'].items():
            require(kind in ('network', 'volume'), 'executor_resource_scope')
            for name, expected in names.items():
                require(re.fullmatch('[a-zA-Z0-9_.-]+', name), 'executor_resource_scope')
                raw = self.command(self.base + [kind, 'inspect', name])
                data = json.loads(raw)[0]
                actual = {k: data.get(k) for k in expected}
                require(actual == expected, 'executor_resource_drift')
                resources[kind + ':' + name] = actual
        for item in self.policy['protected_inputs']:
            binding(item)
        bind_mounts(self.policy['protected_inputs'], list(result.values()))
        bind_files = {m['Source'] for v in result.values() for m in v['mounts']
                      if m['Type'] == 'bind' and Path(m['Source']).is_file()}
        private_paths = {item['path'] for item in self.policy['protected_inputs']}
        require({item['path'] for item in self.policy['runtime_relationship_seals']} >= bind_files - private_paths,
                'executor_runtime_relationship_unsealed')
        for item in self.policy['runtime_relationship_seals']:
            sealed_read(item)
        require(read_json(self.policy['service_origin'].rstrip('/') + '/ready') == {'status': 'ready'}, 'executor_readiness_failed')
        limits = json.loads(self.command(self.base + ['inspect', '--format',
            '{"cpu":{{json .HostConfig.NanoCpus}},"memory":{{json .HostConfig.Memory}},'
            '"pids":{{json .HostConfig.PidsLimit}},"tmpfs":{{json .HostConfig.Tmpfs}}}', api['id']]))
        require(limits == self.policy['api_limits'], 'executor_api_limits_changed')
        result['resources'] = resources
        return result

    def prepare(self, proof):
        raw = sealed_read(self.policy['runtime_seal'])
        self.planned = runtime_model(raw, proof)
        model = json.loads(self.planned)
        api = self.containers('api')
        desired_networks = {model['networks'][key]['name'] for key in model['services']['api']['networks']}
        desired_volumes = {model['volumes'][m['source']]['name'] for m in model['services']['api'].get('volumes', [])}
        require(desired_networks == set(api['networks']) and desired_volumes ==
                {m['Name'] for m in api['mounts'] if m['Type'] == 'volume'}, 'executor_planned_relationship_changed')
        return sha256(self.planned)

    def activate(self, proof):
        require(self.planned is not None, 'executor_not_prepared')
        planned, self.planned = self.planned, None
        self.command(self.base + ['image', 'pull', '--platform', 'linux/arm64', proof['image']], timeout=180)
        raw = self.command(self.base + ['image', 'inspect', '--format',
            '{"id":{{json .Id}},"os":{{json .Os}},"architecture":{{json .Architecture}},'
            '"user":{{json .Config.User}},"command":{{json .Config.Cmd}},'
            '"entrypoint":{{json (index .Config "Entrypoint")}},"labels":{{json .Config.Labels}},'
            '"digests":{{json .RepoDigests}}}', proof['image']])
        actual = json.loads(raw)
        require(actual['id'] in (proof['config_digest'], proof['manifest_digest'])
                and proof['image'] in actual['digests'] and actual['os'] == 'linux'
                and actual['architecture'] == 'arm64' and actual['user'] == '10001:10001'
                and actual['command'] == API_COMMAND and not actual['entrypoint']
                and actual['labels'].get('org.opencontainers.image.revision') == proof['build_source']
                and actual['labels'].get('moneybowl.source_digest') == proof['source_digest'], 'executor_pulled_image_mismatch')
        with sealed_memfd(planned) as fd:
            self.command(self.base + ['compose', '--project-name', 'moneybowl-ingestion-support',
                '--project-directory', '/etc/moneybowl-deployment', '--env-file', '/dev/null',
                '-f', '/proc/' + str(os.getpid()) + '/fd/' + str(fd), 'up', '--detach', '--no-deps', '--no-build',
                '--pull', 'never', '--scale', 'api=1', '--wait', '--wait-timeout', '120', 'api'],
                timeout=180, pass_fds=(fd,))

    def verify_after(self, before, proof):
        after = self.observation()
        require({k: v for k, v in after.items() if k != 'api'} ==
                {k: v for k, v in before.items() if k != 'api'}, 'executor_unrelated_changed')
        api = after['api']
        require(api['id'] != before['api']['id'] and api['image'] in (proof['config_digest'], proof['manifest_digest'])
                and api['labels'].get('org.opencontainers.image.revision') == proof['release_source']
                and api['labels'].get('moneybowl.source_digest') == proof['source_digest'], 'executor_activation_unverified')
        return after
