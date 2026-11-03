"""Fixed root-owned one-shot API deployer. No broker, shell, caller-selected path or installer.

The only entrypoint reads a fixed configuration and bounded signed release request.
Existing M4 installations, authority and journals are never edited by this component.
"""
import contextlib
import hashlib
import json
import os
import re
import stat
import subprocess
import time
from pathlib import Path

from api_executor import sealed_read, sealed_memfd, runtime_model
from compose_inventory import capacity, runtime_identity
from contract import DEV_PROJECT, REPOSITORY, Rejected, require, revision
from ingestion_owner import API_COMMAND, DockerOwner
from initial_private_inputs import binding, bind_mounts, file_digest, identity, no_acl, signature, trusted_path
from protected_io import deployment_lock, publish, root_controlled
from shared_contract import IMAGE, INFRASTRUCTURE, WORKFLOW, api_artifact, decoded, encoded, request, target

CONFIG = Path('/etc/moneybowl-shared-deploy/host.json')
INBOX = Path('/var/spool/moneybowl-shared-deploy/inbox/request.json')
RESULT = Path('/run/moneybowl-shared-deploy/result.json')
SUPPORT = {'caddy', 'clamav', 'github-webhook', 'm3b-receiver', 'm3b-ingress-adapter'}


def executable(seal):
    path, info = trusted_path(seal['path'])
    require(info.st_uid == 0 and not info.st_mode & 0o022 and info.st_mode & 0o111
            and identity(info) == seal['identity'] and file_digest(path, info) == seal['sha256'],
            'shared_host_executable_changed')


def verified_subject(raw, expected):
    results = decoded(raw)
    require(type(results) is list and 0 < len(results) <= 10, 'shared_host_attestation_missing')
    require(any(type(row) is dict and row.get('verificationResult', {}).get('signature')
                and any(subject.get('digest', {}).get('sha256') == expected
                        for subject in row['verificationResult'].get('statement', {}).get('subject', []))
                for row in results), 'shared_host_attestation_subject_mismatch')


def public_relationship(item):
    """An explicitly approved public bind file may have existing non-root ancestry.

    Preserve its exact inode/owner/mode and bytes through a checked descriptor.
    Never treat this as authority for private/group-readable runtime secrets.
    """
    path = Path(item['path'])
    require(path.is_absolute() and path.resolve() == path, 'shared_host_bind_path_invalid')
    before = path.lstat()
    require(stat.S_ISREG(before.st_mode) and before.st_nlink == 1 and not before.st_mode & 0o022
            and identity(before) == item['identity'], 'shared_host_bind_identity_changed')
    no_acl(path)
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    try:
        require(signature(os.fstat(fd)) == signature(before), 'shared_host_bind_identity_changed')
        raw = os.read(fd, 2 * 1024 * 1024 + 1)
        require(len(raw) <= 2 * 1024 * 1024 and hashlib.sha256(raw).hexdigest() == item['sha256']
                and signature(os.fstat(fd)) == signature(before)
                and signature(path.lstat()) == signature(before), 'shared_host_bind_content_changed')
    finally:
        os.close(fd)


def policy(config):
    t = target('refs/heads/' + config['branch'])
    require(config.get('kind') == 'moneybowl-shared-host-v1' and config.get('commissioned') is True,
            'shared_host_uncommissioned')
    require(config.get('environment') == t['environment'] and config.get('image_repository') == IMAGE,
            'shared_host_environment_invalid')
    project = config.get('project_ref', '')
    require(re.fullmatch('[a-z]{20}', project) and ((t['environment'] == 'dev') == (project == DEV_PROJECT)),
            'shared_host_project_invalid')
    require(config.get('runtime_environment') == t['runtime_environment']
            and config.get('supabase_owner') == 'existing-github-integration', 'shared_host_binding_invalid')
    require(re.fullmatch('[a-z0-9][a-z0-9_-]+', config.get('compose_project', '')),
            'shared_host_project_invalid')
    require(type(config.get('unrelated')) is dict and config['unrelated']
            and all(re.fullmatch('[a-z0-9][a-z0-9-]*', name) and name not in ('api', 'outbox-dispatcher')
                    for name in config['unrelated']), 'shared_host_support_inventory_invalid')
    if t['environment'] == 'dev':
        require(set(config['unrelated']) == SUPPORT, 'shared_host_support_inventory_invalid')
    bindings = config.get('environment_projects', {})
    require(bindings.get(t['environment']) == project and len(set(v for v in bindings.values() if v)) ==
            len([v for v in bindings.values() if v]), 'shared_host_project_isolation_invalid')
    if t['environment'] == 'dev':
        from api_executor import INITIAL_COMPONENT, INITIAL_IMAGE, INITIAL_SOURCE
        require(api_artifact(config.get('baseline_api_release')) == dict(image=INITIAL_IMAGE,
            build_sha=INITIAL_SOURCE, component_digest=INITIAL_COMPONENT, activation_sha=INITIAL_SOURCE,
            proof='initial_acceptance'), 'shared_host_dev_baseline_missing')
        require(config.get('compose_project') == 'moneybowl-ingestion-support'
                and config.get('state_root') == '/var/lib/moneybowl-m4-initial-dev/state'
                and config.get('initial_owner_config_seal'), 'shared_host_dev_baseline_missing')
    else:
        require(api_artifact(config.get('baseline_api_release'))['proof'] == 'shared_attestation',
                'shared_host_isolation_unapproved')
        require(config.get('isolation_review') and config.get('production_ready') is (t['environment'] == 'production')
                and config.get('state_root') != '/var/lib/moneybowl-m4-initial-dev/state',
                'shared_host_isolation_unapproved')
    require(type(config.get('journal_root')) is str and config['journal_root'] ==
            '/var/lib/moneybowl-shared-deploy/' + t['environment'], 'shared_host_journal_invalid')
    require(set(config.get('executables', {})) == {'docker', 'compose_plugin', 'systemctl', 'gh', 'git'},
            'shared_host_executables_missing')
    require(set(config.get('infrastructure_pins', {})) == set(INFRASTRUCTURE)
            and all(re.fullmatch('[0-9a-f]{64}', v) for v in config['infrastructure_pins'].values()),
            'shared_host_infrastructure_unapproved')
    required_seals = {config['runtime_seal']['path'], config['trusted_root_seal']['path'],
                      config['docker_config'] + '/config.json', config['state_root'] + '/.owner.lock'}
    if t['environment'] == 'dev':
        required_seals.add(config['initial_owner_config_seal']['path'])
    require(required_seals <= {v['path'] for v in config.get('protected_seals', [])}
            and config.get('code_seals'), 'shared_host_input_seals_missing')
    require(type(config.get('private_inputs')) is list and type(config.get('public_bind_files')) is list,
            'shared_host_mount_policy_missing')
    if t['environment'] == 'dev':
        from compose_inventory import DEV_ARTIFACTS
        require(set(DEV_ARTIFACTS) <= {v['path'] for v in config['public_bind_files']}
                and {'m3b-webhook-v1', 'github-webhook-v1'} <= {v.get('policy') for v in config['private_inputs']},
                'shared_host_dev_mount_policy_missing')
    else:
        require(all(v.get('policy') == 'root-private' for v in config['private_inputs']),
                'shared_host_dev_secret_policy_in_other_environment')
    return t


def installed_config():
    require(os.getuid() == os.geteuid() == 0, 'shared_host_requires_root')
    root_controlled(CONFIG)
    trusted_path(CONFIG)
    raw = CONFIG.read_bytes()
    config = decoded(raw)
    config['_policy_digest'] = hashlib.sha256(raw).hexdigest()
    policy(config)
    directory = Path(__file__).resolve().parent
    require(str(directory) == '/opt/moneybowl-shared-deploy/' + config['installed_source'] + '/tools/deployment',
            'shared_host_source_path_invalid')
    seals = config['code_seals']
    require({v['path'] for v in seals} == {str(p) for p in directory.glob('*.py')} |
            {str(directory / 'environments.json')}, 'shared_host_code_closure_invalid')
    revision(config['installed_source'])
    for value in seals:
        sealed_read(value, public_code=True)
    for value in config['protected_seals']:
        sealed_read(value)
    for name in ('state_root', 'journal_root', 'docker_config'):
        root_controlled(config[name], directory=True)
        no_acl(config[name])
    seal = config['machine_id_seal']
    require(seal['path'] == '/etc/machine-id', 'shared_host_machine_seal_invalid')
    path, info = trusted_path(seal['path'])
    require(info.st_uid == 0 and not info.st_mode & 0o022 and identity(info) == seal['identity']
            and file_digest(path, info) == seal['sha256'] and path.read_text().strip() == config['machine_id'],
            'shared_host_wrong_machine')
    return config


class Process:
    def __init__(self, config):
        self.config = config
        self.tools = {name: value['path'] for name, value in config['executables'].items()}
        for value in config['executables'].values():
            executable(value)
        self.env = {'PATH': '/usr/bin:/bin', 'LANG': 'C.UTF-8', 'HOME': '/nonexistent',
                    'DOCKER_CONFIG': config['docker_config'], 'GH_CONFIG_DIR': '/nonexistent',
                    'GH_PROMPT_DISABLED': '1'}

    def __call__(self, argv, timeout=180, pass_fds=()):
        require(argv[0] in self.tools.values(), 'shared_host_executable_forbidden')
        try:
            p = subprocess.run(argv, env=self.env, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                               timeout=timeout, check=True, pass_fds=pass_fds)
            require(len(p.stdout) <= 2 * 1024 * 1024, 'shared_host_output_oversized')
            return p.stdout
        except (OSError, subprocess.SubprocessError):
            raise Rejected('shared_host_command_failed') from None


class Engine:
    container = DockerOwner.container

    def __init__(self, config, process):
        self.config, self.command = config, process
        self.docker, self.systemctl = process.tools['docker'], process.tools['systemctl']
        self.base = [self.docker, '--host', 'unix:///var/run/docker.sock']
        self.planned = None

    def authority(self):
        policy(self.config)
        root_controlled(CONFIG)
        trusted_path(CONFIG)
        require(hashlib.sha256(CONFIG.read_bytes()).hexdigest() == self.config['_policy_digest'], 'shared_host_policy_changed')
        for seal in self.config['code_seals']:
            sealed_read(seal, public_code=True)
        for seal in self.config['protected_seals']:
            sealed_read(seal)
        for item in self.config['private_inputs']:
            binding(item)
        for item in self.config['public_bind_files']:
            public_relationship(item)
        for seal in self.config['executables'].values():
            executable(seal)
        if self.config['environment'] == 'dev':
            from initial_transition_integrity import completed
            from contract import load_policy
            initial = decoded(sealed_read(self.config['initial_owner_config_seal']))
            completed(initial, load_policy(), initial['repository'])
        require(self.command(self.base + ['info', '--format', '{{.ID}}']).decode().strip() ==
                self.config['daemon_id'], 'shared_host_daemon_changed')
        require(self.command(self.base + ['info', '--format', '{{.DockerRootDir}}']).decode().strip() ==
                self.config['docker_data_root'], 'shared_host_storage_changed')
        capacity(self.config)
        plugin = self.command(self.base + ['info', '--format',
            '{{range .ClientInfo.Plugins}}{{if eq .Name "compose"}}{{.Path}}{{end}}{{end}}']).decode().strip()
        require(plugin == self.command.tools['compose_plugin'], 'shared_host_compose_changed')

    def verify_authorization(self, value, bundle, clock=time.time):
        request(value, now=clock())
        require(value['environment'] == self.config['environment'] and value['branch'] == self.config['branch'] and value['project_ref'] == self.config['project_ref'],
                'shared_host_wrong_environment')
        require(value['infrastructure'] == self.config['infrastructure_pins'], 'shared_host_infrastructure_changed')
        gh = self.command.tools['gh']
        trust = self.config['trusted_root_seal']
        sealed_read(trust)
        common = ['--repo', REPOSITORY, '--signer-workflow', REPOSITORY + '/' + WORKFLOW,
                  '--deny-self-hosted-runners', '--custom-trusted-root', trust['path'], '--format', 'json']
        # Local-bundle verification consumes no Oracle GitHub repository token.
        with sealed_memfd(encoded(value)) as document, sealed_memfd(encoded(bundle)) as signature:
            prefix = '/proc/' + str(os.getpid()) + '/fd/'
            raw = self.command([gh, 'attestation', 'verify', prefix + str(document), '--bundle', prefix + str(signature),
                '--source-digest', value['deployment_sha'], '--source-ref', 'refs/heads/' + value['branch'],
                *common], pass_fds=(document, signature))
            verified_subject(raw, hashlib.sha256(encoded(value)).hexdigest())
        raw = self.command([gh, 'attestation', 'verify', 'oci://' + value['image'], '--bundle-from-oci',
                           '--source-digest', value['build_sha'], *common])
        verified_subject(raw, value['image'].split('@sha256:', 1)[1])

    def observation(self):
        self.authority()
        cfg = self.config
        names = set(cfg['unrelated']) | {'api'}
        raw = self.command(self.base + ['ps', '-aq', '--no-trunc', '--filter',
            'label=com.docker.compose.project=' + cfg['compose_project']]).decode().split()
        values = [self.container(v) for v in raw]
        result = {}
        for value in values:
            name = value['labels'].get('com.docker.compose.service')
            if name == 'outbox-dispatcher':
                continue
            require(name in names and name not in result and value['labels'].get('com.docker.compose.project') ==
                    cfg['compose_project'], 'shared_host_inventory_changed')
            require(value['state']['Running'] is True and value['state']['Status'] == 'running'
                    and not any(value['state'][k] for k in ('Paused', 'Dead', 'Restarting'))
                    and value['state'].get('Health', {}).get('Status') in
                    (('healthy',) if name in {'api', 'clamav', 'github-webhook', 'm3b-receiver'} else (None, 'healthy')),
                    'shared_host_service_unhealthy')
            if name != 'api':
                approved = cfg['unrelated'][name]
                require(value['id'] == approved['id'] and value['image'] == approved['image']
                        and runtime_identity(value) == approved['runtime_identity'], 'shared_host_support_changed')
            result[name] = value
        require(set(result) == names, 'shared_host_inventory_changed')
        bind_mounts(cfg['private_inputs'], list(result.values()))
        bound = {v['path'] for v in cfg['public_bind_files'] + cfg['private_inputs']}
        actual = {m['Source'] for v in result.values() for m in v['mounts']
                  if m['Type'] == 'bind' and Path(m['Source']).is_file()}
        require(actual <= bound, 'shared_host_unsealed_bind_file')
        if cfg['environment'] == 'dev':
            require(len(values) == 7, 'shared_host_inventory_changed')
            DockerOwner.retirement(self)
        else:
            require(len(values) == len(names), 'shared_host_inventory_changed')
            require(not self.command(self.base + ['ps', '-q', '--filter',
                    'label=com.docker.compose.service=outbox-dispatcher']).strip(), 'shared_host_dispatcher_running')
        api = result['api']
        require(runtime_identity(api) == cfg['api_runtime_identity'], 'shared_host_runtime_changed')
        actual_env = json.loads(self.command(self.base + ['inspect', '--format', '{{json .Config.Env}}', api['id']]))
        approved_env = decoded(sealed_read(cfg['runtime_seal']), 1024 * 1024)['services']['api']['environment']
        require(type(actual_env) is list and len(actual_env) == len(set(v.split('=', 1)[0] for v in actual_env))
                and dict(v.split('=', 1) for v in actual_env) == approved_env, 'shared_host_environment_changed')
        limits = json.loads(self.command(self.base + ['inspect', '--format',
            '{"cpu":{{json .HostConfig.NanoCpus}},"memory":{{json .HostConfig.Memory}},'
            '"pids":{{json .HostConfig.PidsLimit}},"tmpfs":{{json .HostConfig.Tmpfs}}}', api['id']]))
        require(limits == cfg['api_limits'], 'shared_host_limits_changed')
        # PID is mandatory on the actual Engine; preserve the independently diagnosed correction.
        lines = self.command(self.base + ['top', api['id'], '-eo', 'pid,uid,args']).decode().splitlines()
        require(len(lines) == 2, 'shared_host_process_invalid')
        pid, uid, arguments = lines[1].split(None, 2)
        require(pid.isdigit() and uid == '10001' and (arguments.split() == API_COMMAND or
            arguments.split() == ['/usr/local/bin/python', '/usr/local/bin/uvicorn', *API_COMMAND[1:]] or
            arguments.split() == ['/usr/local/bin/python3.12', '/usr/local/bin/uvicorn', *API_COMMAND[1:]]),
            'shared_host_process_invalid')
        return result

    def prepare(self, value):
        cfg = self.config
        proof = dict(image=value['image'], git_commit=value['deployment_sha'], source_digest=value['component_digest'])
        self.planned = runtime_model(sealed_read(cfg['runtime_seal']), proof,
            environment=cfg['environment'], project=cfg['compose_project'], baseline_image=cfg['baseline_image'])
        planned = decoded(self.planned, 1024 * 1024)['services']['api']['environment']
        require(planned.get('SUPABASE_URL') == 'https://' + cfg['project_ref'] + '.supabase.co', 'shared_host_runtime_project_mismatch')
        # Runtime values never enter results or the journal.

    def activate(self, value, before_activation):
        require(self.planned is not None, 'shared_host_not_prepared')
        self.command(self.base + ['image', 'pull', '--platform', 'linux/arm64', value['image']])
        info = json.loads(self.command(self.base + ['image', 'inspect', '--format',
            '{"id":{{json .Id}},"os":{{json .Os}},"arch":{{json .Architecture}},'
            '"user":{{json .Config.User}},"command":{{json .Config.Cmd}},"entrypoint":{{json .Config.Entrypoint}},'
            '"labels":{{json .Config.Labels}},"digests":{{json .RepoDigests}}}', value['image']]))
        require(info['os'] == 'linux' and info['arch'] == 'arm64' and info['user'] == '10001:10001'
                and info['command'] == API_COMMAND and not info['entrypoint'] and value['image'] in info['digests']
                and info['labels'].get('org.opencontainers.image.revision') == value['build_sha']
                and info['labels'].get('moneybowl.source_digest') == value['component_digest'], 'shared_host_image_invalid')
        before_activation()
        with sealed_memfd(self.planned) as fd:
            self.command(self.base + ['compose', '--project-name', self.config['compose_project'],
                '--project-directory', '/etc/moneybowl-shared-deploy', '--env-file', '/dev/null',
                '-f', '/proc/' + str(os.getpid()) + '/fd/' + str(fd), 'up', '--detach', '--no-deps',
                '--no-build', '--pull', 'never', '--scale', 'api=1', '--wait', '--wait-timeout', '120', 'api'],
                pass_fds=(fd,))
        return info['id']


class Journal:
    def __init__(self, root, lock_root, engine, clock=time.time):
        self.root, self.lock_root, self.engine, self.clock = Path(root), Path(lock_root), engine, clock

    def records(self):
        files = {p.name for p in self.root.iterdir()}
        require(all(re.fullmatch('[0-9a-f]{40}\\.(intent|complete)\\.json', n) for n in files),
                'shared_host_journal_incomplete')
        intents = sorted(self.root.glob('*.intent.json'))
        require(len(files) == 2 * len(intents), 'shared_host_journal_incomplete')
        result = []
        for path in intents:
            root_controlled(path)
            intent = decoded(path.read_bytes())
            complete_path = self.root / (path.name[:40] + '.complete.json')
            root_controlled(complete_path)
            complete = decoded(complete_path.read_bytes())
            require(complete['intent_sha256'] == hashlib.sha256(encoded(intent)).hexdigest()
                    and complete['release'] == intent['release'], 'shared_host_journal_corrupt')
            actual = api_artifact(complete.get('api_release'))
            require(actual['component_digest'] == intent['release']['component_digest']
                    and complete['state'] == ('deployed' if intent['activation_may_be_attempted'] else 'unchanged'),
                    'shared_host_journal_corrupt')
            if intent['activation_may_be_attempted']:
                require(actual == dict(image=intent['release']['image'], build_sha=intent['release']['build_sha'],
                    component_digest=intent['release']['component_digest'],
                    activation_sha=intent['release']['deployment_sha'], proof='shared_attestation'),
                    'shared_host_journal_corrupt')
            result.append((intent, complete))
        require(sorted(v[0]['sequence'] for v in result) == list(range(1, len(result) + 1)),
                'shared_host_journal_corrupt')
        return sorted(result, key=lambda v: v[0]['sequence'])

    def deploy(self, value, bundle):
        request(value, now=self.clock())
        with deployment_lock(self.lock_root, existing=True):
            self.engine.verify_authorization(value, bundle, self.clock)
            records = self.records()
            before = self.engine.observation()
            if records:
                require(before['api']['id'] == records[-1][1]['api_id']
                        and before['api']['image'] == records[-1][1]['image_id'], 'shared_host_current_release_changed')
            else:
                cfg = self.engine.config
                require(before['api']['id'] == cfg['baseline_api_id'] and before['api']['image'] == cfg['baseline_image_id'],
                        'shared_host_baseline_changed')
            actual = api_artifact(records[-1][1]['api_release'] if records else self.engine.config['baseline_api_release'])
            require(before['api']['labels'].get('org.opencontainers.image.revision') == actual['activation_sha']
                    and before['api']['labels'].get('moneybowl.source_digest') == actual['component_digest'],
                    'shared_host_current_release_changed')
            old = [i for i, c in records if i['release']['deployment_sha'] == value['deployment_sha']]
            if old:
                require(len(old) == 1 and old[0]['release']['image'] == value['image']
                        and old[0]['release']['component_digest'] == value['component_digest'], 'shared_host_release_conflict')
                require(records[-1][0]['release']['deployment_sha'] == value['deployment_sha'], 'shared_host_replay_rejected')
                return dict(state='already_deployed', release=value, api_release=actual,
                            api_id=before['api']['id'], image_id=before['api']['image'])
            require(not records or value['issued_at'] >= records[-1][0]['release']['issued_at'], 'shared_host_replay_rejected')
            changed = actual['component_digest'] != value['component_digest']
            if changed:
                self.engine.prepare(value)
            require(self.engine.observation() == before, 'shared_host_pre_activation_drift')
            request(value, now=self.clock())
            intent = dict(kind='moneybowl-shared-intent-v1', sequence=len(records) + 1,
                          release=value, before=before, activation_may_be_attempted=changed)
            path = self.root / (value['deployment_sha'] + '.intent.json')
            publish(path, intent, immutable=True)
            # From this point every failure quarantines the intent. Never retry/rollback/erase.
            def recheck():
                request(value, now=self.clock())
                self.engine.authority()
                require(self.engine.observation() == before, 'shared_host_pre_activation_drift')
            if changed:
                image_id = self.engine.activate(value, recheck)
                actual = dict(image=value['image'], build_sha=value['build_sha'],
                    component_digest=value['component_digest'], activation_sha=value['deployment_sha'],
                    proof='shared_attestation')
            else:
                recheck()
                image_id = before['api']['image']
            after = self.engine.observation()
            require({k: v for k, v in after.items() if k != 'api'} ==
                    {k: v for k, v in before.items() if k != 'api'}, 'shared_host_support_changed')
            require(after['api']['image'] == image_id
                    and after['api']['labels'].get('org.opencontainers.image.revision') == actual['activation_sha']
                    and after['api']['labels'].get('moneybowl.source_digest') == value['component_digest'],
                    'shared_host_activation_unverified')
            require(changed or after == before, 'shared_host_unchanged_runtime_drift')
            complete = dict(state='deployed' if changed else 'unchanged', release=value, api_release=actual,
                            api_id=after['api']['id'], image_id=image_id,
                            intent_sha256=hashlib.sha256(encoded(intent)).hexdigest())
            publish(self.root / (value['deployment_sha'] + '.complete.json'), complete, immutable=True)
            return complete


def read_inbox():
    fd = os.open(INBOX, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    try:
        info = os.fstat(fd)
        require(stat.S_ISREG(info.st_mode) and info.st_uid == 993 and info.st_gid == 983
                and stat.S_IMODE(info.st_mode) == 0o600 and info.st_nlink == 1, 'shared_host_inbox_invalid')
        raw = os.read(fd, 2 * 1024 * 1024 + 1)
        require(signature(os.fstat(fd)) == signature(info), 'shared_host_inbox_changed')
        value = decoded(raw)
        require(set(value) == {'release', 'bundle'}, 'shared_host_envelope_invalid')
        return raw, value
    finally:
        os.close(fd)


def main():
    try:
        config = installed_config()
        raw, envelope = read_inbox()
        engine = Engine(config, Process(config))
        result = Journal(config['journal_root'], config['state_root'], engine).deploy(envelope['release'], envelope['bundle'])
        result['request_sha256'] = hashlib.sha256(raw).hexdigest()
        # Fixed sanitized result readable by the deployment group, never the root policy/journal.
        parent = RESULT.parent.lstat()
        require(parent.st_uid == 0 and parent.st_gid == 983 and stat.S_IMODE(parent.st_mode) == 0o750
                and RESULT.parent.resolve() == RESULT.parent, 'shared_host_result_invalid')
        no_acl(RESULT.parent)
        require(not RESULT.is_symlink(), 'shared_host_result_invalid')
        if RESULT.exists():
            info = RESULT.lstat()
            require(stat.S_ISREG(info.st_mode) and info.st_uid == 0 and info.st_nlink == 1,
                    'shared_host_result_invalid')
        fd = os.open(RESULT, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW, 0o640)
        with os.fdopen(fd, 'wb') as out:
            os.fchown(out.fileno(), 0, 983); os.fchmod(out.fileno(), 0o640)
            out.write(encoded(result)); out.flush(); os.fsync(out.fileno())
        return 0
    except Rejected as error:
        code = str(error)
        if not re.fullmatch(r'(?:shared_host|executor|private_input|initial|approval|protected|external_secret|legacy)_[a-z0-9_]{1,80}', code):
            code = 'shared_host_stopped_review_required'
        print(json.dumps({'state': 'failed', 'reason': code}))
        return 1
    except Exception:
        print('{"state":"failed","reason":"shared_host_stopped_review_required"}')
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
