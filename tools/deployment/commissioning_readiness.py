"""Bounded DEV input commissioning; never invokes initial PREPARE or service mutation.

Observation, independent baseline approval and publication authority are separate.
All privileged entrypoints require sealed installed code and real/effective root.
"""
import argparse
import copy
import grp
import json
import math
import os
import re
import stat
import time
from pathlib import Path

import compose_inventory as inventory
import initial_api_transition as initial
import initial_private_inputs as private
import initial_transition_integrity as integrity
from contract import DEV_PROJECT, REPOSITORY, Rejected, load_policy, require
from ingestion_owner import DockerOwner
from owner_common import Command, pinned_executable, sha256
from protected_io import deployment_lock, root_controlled, sync_directory

ORIGINAL_ENV = '/etc/moneybowl-deployment/runtime-inputs/ingestion-compose.env'
FINAL_ENV = '/etc/moneybowl-deployment/runtime-inputs/ingestion-compose-m4.env'
FINAL_CONFIG = '/etc/moneybowl-deployment/initial-mailback-dev.json'
OWNER_CONFIG = '/etc/moneybowl-deployment/ingestion.json'
ROOT = '/var/lib/moneybowl-m4-initial-dev'
CADDY_HISTORY = ROOT + '/caddy-receipts-cutover-20261014-v1'
HISTORY = {
    'disabled_owner': OWNER_CONFIG,
    'caddy_journal': CADDY_HISTORY + '/journal.json',
    'caddy_reconciliation': CADDY_HISTORY + '/postcutover-reconciliation-20261014.json',
    'recovery_override': ROOT + '/recovery/recovery-api.compose.json',
    'recovery_archive': ROOT + '/recovery/legacy-api-image.tar',
    'recovery_record': ROOT + '/recovery/RECOVERY.json',
}
M3B = {
    'M3B_WAKE_GID': '985',
    'M3B_RECEIVER_IMAGE': 'moneybowl/m3b-receiver@sha256:400d88fd63e353b331519b66a494b3d5c22528b923948518822e96880965cff8',
    'M3B_RECEIVER_SECRET_FILE': '/etc/moneybowl-director/m3b-webhook-secret',
    'M3B_RECEIVER_STATE_DIR': '/var/lib/moneybowl-director-m3b/receiver',
    'M3B_WAKE_SPOOL_DIR': '/var/lib/moneybowl-director-m3b/wake-spool/pending',
    'M3B_INGRESS_ADAPTER_IMAGE': 'moneybowl/m3b-ingress-adapter:fc58b2c964b8173483af8cf47c40251b4f686bc4',
}
SIX = ('api', 'caddy', 'clamav', 'github-webhook', 'm3b-receiver', 'm3b-ingress-adapter')
LIMIT = 1024 * 1024


def root_operator():
    require(os.getuid() == os.geteuid() == 0, 'commissioning_requires_root_operator')


def json_bytes(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), allow_nan=False).encode() + b'\n'


def parse_json(raw):
    def unique(pairs):
        value = {}
        for key, item in pairs:
            require(key not in value, 'commissioning_duplicate_json_key')
            value[key] = item
        return value
    def invalid(_):
        raise Rejected('commissioning_json_invalid')
    return json.loads(raw, object_pairs_hook=unique, parse_constant=invalid)


def root_bytes(path, expected=None):
    root_controlled(path)
    path, info = private.trusted_path(path)
    with private.checked_file(path, info) as fd:
        raw = b''
        while len(raw) <= LIMIT:
            block = os.read(fd, min(65536, LIMIT + 1 - len(raw)))
            if not block:
                break
            raw += block
    require(len(raw) <= LIMIT, 'commissioning_input_oversized')
    require(expected is None or sha256(raw) == expected, 'commissioning_artifact_changed')
    return raw


def root_json(path, expected=None):
    return parse_json(root_bytes(path, expected))


def create(path, data):
    """Exclusive inode creation, root:root 0400, file and parent directory fsync.

    A partial/uncertain write is retained for inspection; never delete and retry it.
    The parent is root-controlled, so unprivileged path substitution is impossible.
    """
    root_operator()
    path = Path(path)
    root_controlled(path.parent, directory=True)
    private.no_acl(path.parent)
    require(path.name not in ('', '.', '..'), 'commissioning_path_invalid')
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC, 0o400)
    try:
        os.fchown(fd, 0, 0)
        os.fchmod(fd, 0o400)
        with os.fdopen(fd, 'wb', closefd=False) as stream:
            stream.write(data)
            stream.flush()
            os.fsync(fd)
    finally:
        os.close(fd)
    sync_directory(path.parent)
    require(root_bytes(path) == data, 'commissioning_written_content_changed')
    return private.identity(path.lstat())


def append_m3b(original, settings):
    require(settings == M3B, 'm3b_settings_missing_or_unreviewed')
    require(len(original) <= LIMIT and b'\x00' not in original, 'commissioning_env_invalid')
    # Conservative duplicate detection also rejects export/bare declarations and
    # declarations inside multiline values. Compose itself checks interpolation.
    for line in original.splitlines():
        match = re.match(rb'\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*(?:=|:|$)',
                         line.removeprefix(b'\xef\xbb\xbf'))
        require(not match or match[1].decode() not in M3B, 'm3b_variable_already_present')
    suffix = ''.join(key + '=' + settings[key] + '\n' for key in sorted(M3B)).encode()
    return original + (b'\n' if original and not original.endswith(b'\n') else b'') + suffix


def check_env(raw, settings):
    require(settings == M3B, 'm3b_settings_missing_or_unreviewed')
    found = {}
    for line in raw.splitlines():
        match = re.match(rb'\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*(?:=|:|$)',
                         line.removeprefix(b'\xef\xbb\xbf'))
        if match and match[1].decode() in M3B:
            name = match[1].decode()
            require(name not in found, 'm3b_variable_duplicate')
            require(line == (name + '=' + settings[name]).encode(), 'm3b_variable_invalid')
            found[name] = settings[name]
    require(found == settings, 'm3b_variable_missing')


def check_binding(item):
    private.binding(item)  # Includes identity, ancestry, ACL, policy and digest gates.


def preserve(request):
    require(set(request['preserved']) == set(HISTORY), 'commissioning_history_inventory_invalid')
    for role, path in HISTORY.items():
        item = request['preserved'][role]
        require(item['path'] == path and item.get('policy', 'root-private-v1') == 'root-private-v1',
                'commissioning_history_path_invalid')
        check_binding(item)
    check_binding(request['original_input'])
    owner = root_json(OWNER_CONFIG)
    require(owner.get('commissioned') is False, 'regular_owner_already_enabled')
    # Never reinterpret or modify the historical Caddy failure/reconciliation.


def bounded_request(request):
    require(request['kind'] == 'moneybowl-m4-commissioning-request-v1', 'commissioning_request_invalid')
    require(request['original_input']['path'] == ORIGINAL_ENV
            and request['original_input'].get('policy', 'root-private-v1') == 'root-private-v1',
            'commissioning_original_input_invalid')
    require(request['m3b'] == M3B, 'm3b_settings_missing_or_unreviewed')
    config = request['config']
    require(config['commissioned'] is False and config['environment'] == 'dev'
            and config['project_ref'] == DEV_PROJECT and config['compose_env'] == FINAL_ENV
            and config['initial_transition']['enabled'] is False
            and config['initial_transition']['acceptance_required'] is True
            and 'initial_provenance' not in config, 'commissioning_draft_invalid')
    require(len(config['compose_layers']) == 5 and set(config['compose_services']) == set(SIX),
            'commissioning_inventory_invalid')
    require(config['initial_transition']['image'] ==
            'ghcr.io/sharanravi954mf/moneybowl-ingestion-dev@' + initial.CANDIDATE,
            'commissioning_candidate_invalid')
    items = config['initial_transition']['protected_inputs']
    require(len(items) == 3 and {i['path'] for i in items} ==
            {FINAL_ENV, *[r['path'] for r in private.EXTERNAL_SECRETS.values()]},
            'commissioning_private_inventory_invalid')
    return config


def absent_destinations(stage=None):
    for value in (FINAL_ENV, FINAL_CONFIG):
        path = Path(value)
        root_controlled(path.parent, directory=True)
        private.no_acl(path.parent)
        require(not path.exists() and not path.is_symlink(), 'commissioning_destination_exists')
        if stage is not None:
            require(path.parent.stat().st_dev == Path(stage).stat().st_dev,
                    'commissioning_same_filesystem_required')


def safe_git(config, *args, remote=False):
    command = Command({'GIT_CONFIG_NOSYSTEM': '1', 'GIT_CONFIG_GLOBAL': '/dev/null',
                       'GIT_TERMINAL_PROMPT': '0'})
    prefix = [pinned_executable(config, 'git'), '-c', 'core.hooksPath=/dev/null',
              '-c', 'core.fsmonitor=false', '-c', 'credential.helper=']
    if not remote:
        prefix += ['-C', config['repository']]
    return command(prefix + list(args), cwd=config['repository'])


def source(config):
    repo = root_controlled(config['repository'], directory=True)
    # A root-owned leaf inside application-controlled Git is not a source mirror.
    for path in repo.rglob('*'):
        info = path.lstat()
        require(not path.is_symlink() and info.st_uid == 0 and not info.st_mode & 0o022
                and (stat.S_ISDIR(info.st_mode) or stat.S_ISREG(info.st_mode)),
                'commissioning_source_authority_invalid')
        private.no_acl(path)
    require(safe_git(config, 'remote', 'get-url', 'origin').decode().strip() ==
            'https://github.com/' + REPOSITORY + '.git', 'wrong_repository')
    head = config['initial_transition']['approved_branch_head']
    require(safe_git(config, 'rev-parse', 'refs/heads/develop').decode().strip() == head,
            'commissioning_source_mirror_stale')
    remote = safe_git(config, 'ls-remote', 'https://github.com/' + REPOSITORY + '.git',
                      'refs/heads/develop', remote=True).decode().split()
    require(remote == [head, 'refs/heads/develop'], 'branch_changed')
    safe_git(config, 'merge-base', '--is-ancestor', initial.SOURCE, head)
    require(sha256(safe_git(config, 'ls-tree', '-r', initial.SOURCE, '--',
                            'services/ingestion-support')) == initial.SOURCE_DIGEST,
            'source_digest_mismatch')

    class GitFile:
        # inventory.files needs only path joining and read_bytes. No archive,
        # checkout, fetch, tempfile or journal is created by this preflight.
        def __init__(self, path=''):
            self.path = path
        def __truediv__(self, part):
            return GitFile(self.path + ('/' if self.path else '') + str(part))
        def read_bytes(self):
            return safe_git(config, 'show', initial.SOURCE + ':' + self.path)
    return GitFile()


def m3b_relationships(docker, snapshot, settings):
    require(settings == M3B, 'm3b_settings_missing_or_unreviewed')
    receiver = snapshot['unrelated']['m3b-receiver']
    adapter = snapshot['unrelated']['m3b-ingress-adapter']
    require(grp.getgrgid(int(settings['M3B_WAKE_GID'])).gr_name == 'moneybowl-director-wake',
            'm3b_wake_group_changed')
    for container, ref in ((receiver, settings['M3B_RECEIVER_IMAGE']),
                           (adapter, settings['M3B_INGRESS_ADAPTER_IMAGE'])):
        raw = docker.command(docker.base + ['inspect', '--format',
            '{"groups":{{json .HostConfig.GroupAdd}},"configured_image":{{json .Config.Image}}}', container['id']])
        extra = parse_json(raw)
        require(extra['configured_image'] == ref and docker.image(ref)['id'] == container['image'],
                'm3b_image_binding_changed')
        if container is receiver:
            require(extra['groups'] == [settings['M3B_WAKE_GID']], 'm3b_wake_group_changed')
    for key, destination, writable, mode, uid, gid in (
        ('M3B_RECEIVER_SECRET_FILE', '/run/secrets/m3b_webhook_secret', False, 0o440, 0, 10001),
        ('M3B_RECEIVER_STATE_DIR', '/state', True, 0o700, 10001, 10001),
        ('M3B_WAKE_SPOOL_DIR', '/spool', True, 0o2770, 0, int(settings['M3B_WAKE_GID'])),
    ):
        path = Path(settings[key])
        require(path.resolve(strict=True) == path, 'm3b_mount_path_changed')
        info = path.lstat()
        require(info.st_uid == uid and info.st_gid == gid and stat.S_IMODE(info.st_mode) == mode,
                'm3b_mount_permissions_changed')
        private.no_acl(path)
        mounts = [m for m in receiver['mounts'] if m['Destination'] == destination]
        require(mounts == [dict(Type='bind', Name=None, Source=str(path),
                               Destination=destination, RW=writable)], 'm3b_mount_relationship_changed')
    receipt = dict(Type='bind', Name=None, Source='/srv/moneybowl-m4-receipts',
                   Destination='/srv/moneybowl-m4-receipts', RW=False)
    require(receipt in snapshot['unrelated']['caddy']['mounts'], 'caddy_receipt_mount_changed')


def preflight(config, settings, env_path=None, *, docker=None, source_view=None):
    """Same InitialDockerOwner/Command transport and input validators as PREPARE.

    Injectable transports are for synthetic tests only. The CLI never injects one.
    Never returns rendered Compose, container environments or credentials.
    """
    root_operator()
    initial.validate_config(config, load_policy())
    require(config['commissioned'] is False and 'initial_provenance' not in config,
            'commissioning_draft_invalid')
    runtime = copy.deepcopy(config)
    if env_path is not None:
        runtime['compose_env'] = str(env_path)
        for item in runtime['initial_transition']['protected_inputs']:
            if item['path'] == FINAL_ENV:
                item['path'] = str(env_path)
    raw = root_bytes(runtime['compose_env'])
    check_env(raw, settings)
    initial.inputs(runtime)
    docker = docker or initial.InitialDockerOwner(runtime)
    require(docker.config == runtime, 'commissioning_transport_config_mismatch')
    view = source_view if source_view is not None else source(runtime)
    before = docker.snapshot(view)
    initial.bind_inputs(runtime, before)
    hashes = {}
    for name in SIX:
        current = before['api'] if name == 'api' else before['unrelated'][name]
        approved = config['compose_services'][name]
        hashes[name] = docker.config_hash(name)
        require(hashes[name] == approved['config_hash'] ==
                current['labels']['com.docker.compose.config-hash'], 'running_configuration_drift')
        require(current['id'] == approved['container_id'] and current['image'] == approved['image_id'],
                'commissioning_container_drift')
    m3b_relationships(docker, before, settings)
    initial.check_image(docker, initial.proof_for(config))
    return dict(effective_hashes=hashes, snapshot_sha256=inventory.digest(before),
                tag_immutability_review_required=True, legacy_provenance='unknown',
                controller_prepare_invoked=False, automatic_docker_broker='uncommissioned')


def inspect(request):
    root_operator()
    config = bounded_request(request)
    preserve(request)
    absent_destinations()
    original = root_bytes(ORIGINAL_ENV, request['original_input']['sha256'])
    candidate = append_m3b(original, request['m3b'])
    # Inspection has no approved baseline and does not impersonate the owner.
    # Reuse only its secret-free Engine projections, with pinned read-only commands.
    class EngineObservation:
        container = DockerOwner.container
        image = initial.InitialDockerOwner.image
        def __init__(self):
            self.command = Command({'DOCKER_CONFIG': '/dev/null'})
            require(config['docker_socket'] == 'unix:///var/run/docker.sock', 'remote_docker_forbidden')
            self.base = [pinned_executable(config, 'docker'), '--host', config['docker_socket']]
    engine = EngineObservation()
    live = {name: engine.container(config['compose_services'][name]['container_id']) for name in SIX}
    for name, container in live.items():
        require(container['id'] == config['compose_services'][name]['container_id']
                and container['image'] == config['compose_services'][name]['image_id']
                and container['labels']['com.docker.compose.service'] == name
                and container['labels']['com.docker.compose.project'] == config['compose_project'],
                'commissioning_container_drift')
    before = dict(api=live['api'], unrelated={k: v for k, v in live.items() if k != 'api'})
    require(live['api']['id'] == initial.LEGACY_CONTAINER and live['api']['image'] == initial.LEGACY
            and not live['api']['labels'].get('org.opencontainers.image.revision'),
            'initial_legacy_identity_changed')
    m3b_relationships(engine, before, request['m3b'])
    for item in config['initial_transition']['protected_inputs']:
        if item['path'] != FINAL_ENV:
            private.checked_input(item)  # Policy/identity only; never reads secret bytes here.
    # No temporary environment, root directories or controller journals are made.
    return dict(state='INSPECTED_UNAPPROVED', original_sha256=sha256(original),
                proposed_env_sha256=sha256(candidate), added_variables=sorted(M3B),
                draft_config_sha256=inventory.digest(config), live_preflight='REQUIRES_STAGED_INPUT_AND_INDEPENDENT_BASELINE',
                m3b_runtime_verified=True, baseline_approved=False, publication_authorized=False)


def stage(request, destination):
    inspect(request)
    path = Path(destination)
    root_controlled(path.parent, directory=True)
    absent_destinations(path.parent)
    # Stage outside all existing state/history/config/source/approval paths.
    config = request['config']
    excluded = [Path(config[k]) for k in ('repository', 'state_root', 'report_root', 'docker_config')]
    excluded += [Path(config['initial_transition']['approval_root']), Path(ORIGINAL_ENV).parent,
                 Path(FINAL_CONFIG).parent, Path(CADDY_HISTORY), Path(ROOT + '/recovery')]
    require(all(path != p and p not in path.parents and path not in p.parents for p in excluded),
            'commissioning_stage_path_invalid')
    os.mkdir(path, 0o700)  # Existing stages are never resumed, repaired or overwritten.
    os.chown(path, 0, 0)
    sync_directory(path.parent)
    try:
        create(path / '00-intent.json', json_bytes(dict(state='STAGING', request=request)))
        raw = append_m3b(root_bytes(ORIGINAL_ENV, request['original_input']['sha256']), request['m3b'])
        identity = create(path / 'compose.env', raw)
        draft = copy.deepcopy(config)
        item = next(i for i in draft['initial_transition']['protected_inputs'] if i['path'] == FINAL_ENV)
        item.update(identity=identity, sha256=sha256(raw), approval=None)
        create(path / 'initial-mailback-dev.draft.json', json_bytes(draft))
        preserve(request)
        completed = dict(state='STAGED_UNAPPROVED', request=request, config=draft,
                         env_sha256=sha256(raw), env_identity=identity)
        create(path / '10-staged.json', json_bytes(completed))
        return dict(state=completed['state'], stage_sha256=inventory.digest(completed),
                    env_sha256=sha256(raw), env_identity=identity, publication_authorized=False)
    except Exception:
        # Append-only diagnostics; if storage also failed, intent or incomplete
        # directory remains. Both are terminal review conditions, never retry.
        try:
            create(path / '99-unknown.json', json_bytes(dict(state='UNKNOWN', recovery='independent_review_required')))
        except Exception:
            pass
        raise


def staged(path):
    root_controlled(path, directory=True)
    path = Path(path)
    require(not (path / '99-unknown.json').exists() and not (path / '99-unknown.json').is_symlink()
            and not (path / '30-publish-intent.json').exists() and not (path / '30-publish-intent.json').is_symlink(),
            'commissioning_outcome_requires_review')
    value = root_json(path / '10-staged.json')
    require(value['state'] == 'STAGED_UNAPPROVED' and
            root_json(path / '00-intent.json') == dict(state='STAGING', request=value['request']),
            'commissioning_stage_integrity_failed')
    require(root_json(path / 'initial-mailback-dev.draft.json') == value['config'],
            'commissioning_stage_integrity_failed')
    require(private.identity((path / 'compose.env').lstat()) == value['env_identity']
            and sha256(root_bytes(path / 'compose.env')) == value['env_sha256'],
            'commissioning_stage_env_changed')
    require(value['env_identity']['uid'] == value['env_identity']['gid'] == 0
            and value['env_identity']['mode'] == 0o400, 'commissioning_stage_env_changed')
    return value


def without_approvals(value):
    if isinstance(value, dict):
        return {k: without_approvals(v) for k, v in value.items() if k != 'approval'}
    if isinstance(value, list):
        return [without_approvals(v) for v in value]
    return value


def review(path, baseline_path, baseline_sha256):
    root_operator()
    value = staged(path)
    request = value['request']
    bounded_request(request)
    preserve(request)
    absent_destinations(path)
    require(root_bytes(Path(path) / 'compose.env') ==
            append_m3b(root_bytes(ORIGINAL_ENV, request['original_input']['sha256']), request['m3b']),
            'commissioning_original_bytes_not_preserved')
    baseline_path = Path(baseline_path)
    require(Path(path) not in baseline_path.parents, 'commissioning_baseline_not_independent')
    baseline = root_json(baseline_path, baseline_sha256)
    require(baseline['kind'] == 'moneybowl-m4-commissioning-baseline-v1' and baseline['owner_review']
            and baseline['stage_sha256'] == inventory.digest(value), 'commissioning_baseline_unapproved')
    config = baseline['config']
    expected = copy.deepcopy(value['config'])
    expected['initial_transition']['enabled'] = True
    require(without_approvals(config) == without_approvals(expected), 'commissioning_baseline_changes_draft')
    state = Path(config['state_root'])
    retained = [state / name for name in integrity.ARTIFACTS]
    retained += [state / (initial.SOURCE + suffix) for suffix in ('.compose.json', '.provenance.json')]
    require(all(not p.exists() and not p.is_symlink() for p in retained),
            'commissioning_initial_state_requires_review')
    recovery_binding = config['initial_transition']['recovery']
    require(recovery_binding['archive'] == HISTORY['recovery_archive']
            and recovery_binding['record'] == HISTORY['recovery_record']
            and recovery_binding['sha256'] == request['preserved']['recovery_archive']['sha256']
            and recovery_binding['record_sha256'] == request['preserved']['recovery_record']['sha256'],
            'commissioning_recovery_binding_invalid')
    require(all(item.get('approval') for item in config['compose_layers'] + config['compose_artifacts'] +
                config['initial_transition']['protected_inputs'])
            and config['registry'].get('approval') and config['initial_transition']['recovery'].get('approval'),
            'commissioning_baseline_unapproved')
    tag = baseline['ingress_tag_review']
    require(tag == dict(reference=M3B['M3B_INGRESS_ADAPTER_IMAGE'],
            image_id=config['compose_services']['m3b-ingress-adapter']['image_id'],
            owner_review=tag.get('owner_review'), preserve_without_pull=True)
            and tag['owner_review'], 'commissioning_tag_review_missing')
    recovery = baseline['recovery_review']
    require(recovery.get('offhost_retention_review') and recovery.get('restoration_readiness_review')
            and recovery.get('rollback_requires_separate_authorization') is True,
            'commissioning_recovery_review_missing')
    result = preflight(config, request['m3b'], Path(path) / 'compose.env')
    preserve(request)
    return dict(state='REVIEWED_REQUIRES_PUBLICATION_AUTHORITY', stage_sha256=inventory.digest(value),
                baseline_sha256=baseline_sha256, config_sha256=sha256(json_bytes(config)),
                env_sha256=value['env_sha256'], env_identity=value['env_identity'], preflight=result,
                changes=[dict(action='exclusive_create', path=FINAL_ENV, mode=0o400, uid=0, gid=0),
                         dict(action='exclusive_create', path=FINAL_CONFIG, mode=0o400, uid=0, gid=0)],
                preserved=request['preserved'], original_input=request['original_input'],
                activation_authorized=False)


def move_exclusive(source_path, destination):
    """Same-filesystem no-clobber transfer retaining the independently reviewed inode.

    The transient two-link state is never accepted by any input validator. A crash
    leaves a publication intent and blocks all retry until separate reconciliation.
    """
    source_path, destination = Path(source_path), Path(destination)
    root_controlled(source_path)
    root_controlled(destination.parent, directory=True)
    os.link(source_path, destination, follow_symlinks=False)
    sync_directory(destination.parent)
    source_path.unlink()
    _, info = private.trusted_path(destination)
    with private.checked_file(destination, info) as fd:
        os.fsync(fd)  # Persist the inode's final one-link metadata as well as entries.
    sync_directory(source_path.parent)
    sync_directory(destination.parent)


def publish_stage(path, baseline_path, baseline_sha256, approval_path, *, now=time.time):
    root_operator()
    value = staged(path)
    config = root_json(baseline_path, baseline_sha256)['config']
    approvals = root_controlled(config['initial_transition']['approval_root'], directory=True)
    approval_path = root_controlled(approval_path)
    require(approval_path.parent == approvals and Path(path) not in approval_path.parents,
            'commissioning_publication_authority_invalid')
    approval = root_json(approval_path)
    expiry = approval.get('expires_at')
    require(type(expiry) in (int, float) and math.isfinite(expiry) and now() < expiry <= now() + 3600
            and re.fullmatch('[0-9a-f]{64}', approval.get('nonce', '')) and approval.get('owner_review'),
            'commissioning_publication_approval_invalid')
    # Shared initial/regular controller lock; INSPECT/STAGE/REVIEW never acquire it.
    with deployment_lock(config['state_root']):
        report = review(path, baseline_path, baseline_sha256)
        require(approval == dict(kind='moneybowl-m4-commissioning-publication-v1', environment='dev',
                project_ref=DEV_PROJECT, review_sha256=inventory.digest(report),
                baseline_sha256=baseline_sha256, stage_sha256=inventory.digest(value),
                owner_review=approval['owner_review'], nonce=approval['nonce'], expires_at=expiry,
                targets=[FINAL_ENV, FINAL_CONFIG], api_activation_authorized=False),
                'commissioning_publication_approval_invalid')
        require(now() < expiry, 'commissioning_publication_approval_expired')
        # No mutations before authorization. Intent is durable before either target.
        create(Path(path) / '30-publish-intent.json', json_bytes(dict(state='PUBLISHING',
            approval_sha256=sha256(root_bytes(approval_path)), review=report)))
        try:
            move_exclusive(Path(path) / 'compose.env', FINAL_ENV)
            check_binding(next(i for i in config['initial_transition']['protected_inputs'] if i['path'] == FINAL_ENV))
            create(FINAL_CONFIG, json_bytes(config))
            preserve(value['request'])
            # Postpublication remeasurement is read-only; never starts PREPARE.
            preflight(config, value['request']['m3b'])
            create(Path(path) / '40-published.json', json_bytes(dict(state='PUBLISHED_NOT_PREPARED',
                config_sha256=report['config_sha256'], env_sha256=value['env_sha256'],
                env_identity=value['env_identity'], prepare_authorized=False)))
            return dict(state='PUBLISHED_NOT_PREPARED', config_sha256=report['config_sha256'])
        except Exception:
            try:
                create(Path(path) / '99-unknown.json', json_bytes(dict(state='UNKNOWN', recovery='independent_review_required')))
            except Exception:
                pass
            raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('phase', choices=('inspect', 'stage', 'review', 'publish'))
    parser.add_argument('--request')
    parser.add_argument('--stage')
    parser.add_argument('--baseline')
    parser.add_argument('--baseline-sha256')
    parser.add_argument('--approval')
    args = parser.parse_args()
    try:
        initial.installed_code()
        root_operator()
        if args.phase in ('inspect', 'stage'):
            require(args.request, 'commissioning_request_required')
            request = root_json(args.request)
            if args.phase == 'inspect':
                result = inspect(request)
            else:
                require(args.stage, 'commissioning_stage_required')
                result = stage(request, args.stage)
        else:
            require(args.stage and args.baseline and args.baseline_sha256, 'commissioning_review_inputs_required')
            if args.phase == 'review':
                result = review(args.stage, args.baseline, args.baseline_sha256)
            else:
                require(args.approval, 'commissioning_publication_approval_required')
                result = publish_stage(args.stage, args.baseline, args.baseline_sha256, args.approval)
    except Exception as error:
        # Never interpolate exception/child output containing private data.
        result = dict(state='BLOCKED', reason=str(error) if isinstance(error, Rejected)
                      else 'commissioning_prerequisite_or_outcome_unavailable')
    print(json.dumps(result, sort_keys=True))
    return 1 if result['state'] == 'BLOCKED' else 0


if __name__ == '__main__':
    raise SystemExit(main())
