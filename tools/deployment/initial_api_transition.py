"""One-time DEV API transition. Prepare, activate and verify are separate invocations.

Unknown legacy provenance is never imported into the regular owner's history.
No build, push, financial operation, retry, rollback or service start runs on import.
"""
import argparse
import hashlib
import json
import os
import re
import time
from pathlib import Path

import compose_inventory as inventory
import initial_private_inputs as private_inputs
from contract import DEV_PROJECT, Rejected, load_policy, manifest, require, revision, target
from ingestion_owner import API_COMMAND, DockerOwner
from observe import Pending, ancestor
from owner_common import envelope, latest, sha256, source_tree
from private_registry import Registry
from protected_io import deployment_lock, protected, publish, read_private, root_controlled
from service_manifest import service_manifest

SOURCE = '8afa04f9db4a3429fdfeef503d4ebaf6abf18aa5'
SOURCE_DIGEST = '5f06254a13cb666449336425b1a66d31fa8db4afbb30d78d0bc7687dd67d5fd5'
CANDIDATE = 'sha256:257c0fd51f3d47a8d24031fd90333945c804a159ad6779301226edcd3fc80945'
LEGACY = 'sha256:1c38aa4946fdb961ed7b0983edb6925988961891c91a0b9e296d84ac8a59286f'
LEGACY_CONTAINER = '7267a578f4bae1df47d18c838b6e59a2c2b4b31522fe4e90946f4cc5d8f034c6'
JOURNAL = 'initial-transition.json'
APPROVAL_AUTHORITY = 'root-operated-cutover-v1'


def cutover_authority(config):
    # The normal moneybowl-ingestion-deploy service is deliberately not this authority.
    require(os.getuid() == 0 and os.geteuid() == 0, 'cutover_requires_root_operator')
    require(config.get('initial_transition', {}).get('approval_authority') == APPROVAL_AUTHORITY,
            'approval_authority_not_configured')
    root_controlled(config['initial_transition']['approval_root'], directory=True)


class InitialDockerOwner(DockerOwner):
    """Only the exact approved legacy identity or planned replacement is accepted."""
    def __init__(self, config, command=None):
        cutover_authority(config)
        super().__init__(config, command)
        self.planned = None

    def image(self, image):
        # This richer bootstrap inspector is separate from PR #209's regular inspector.
        raw = self.command(self.base + ['image', 'inspect', '--format',
            '{"id":{{json .Id}},"digests":{{json .RepoDigests}},"labels":{{json .Config.Labels}},'
            '"command":{{json .Config.Cmd}},"entrypoint":{{json (index .Config "Entrypoint")}},'
            '"user":{{json .Config.User}},"architecture":{{json .Architecture}},"os":{{json .Os}}}', image])
        value = json.loads(raw)
        require(re.fullmatch(r'sha256:[0-9a-f]{64}', value['id']), 'invalid_image_id')
        return value

    def validate_current(self, current):
        if self.planned is None:
            require(current['id'] == LEGACY_CONTAINER and current['image'] == LEGACY
                    and not current['labels'].get('org.opencontainers.image.revision'),
                    'initial_legacy_identity_changed')
            super().validate_current(current)  # Relationship/config gates, no initial_revision call.
        else:
            proof, override = self.planned
            require(self.verified(proof, override) == current, 'api_changed_during_verification')
            require(current['labels'].get('moneybowl.source_digest') == proof['source_digest'],
                    'running_source_digest_mismatch')
            require(current['security']['user'] == '10001:10001'
                    and inventory.runtime_identity(current) ==
                    self.config['compose_services']['api']['runtime_sha256'], 'running_relationship_drift')
            require(current['labels'].get('com.docker.compose.project.config_files') ==
                    ','.join([layer['path'] for layer in self.config['compose_layers']] + [str(override)]),
                    'container_compose_files_mismatch')

    def snapshot(self, source, proof=None, override=None):
        self.planned = None if proof is None else (proof, override)
        self.capacity()
        unrelated = self.infrastructure(source)
        current = self.current()
        require(current is not None, 'api_baseline_missing')
        self.validate_current(current)
        retired = self.container(self.config['retired_containers'][0])
        return {'api': current, 'unrelated': unrelated, 'retired': retired}

    def override_hashes(self, override):
        result = {}
        for service in inventory.services(self.config):
            result[service] = self.config_hash(service, override)
            if service != 'api':
                require(result[service] == self.config_hash(service), 'override_changes_unrelated_service')
        return result

    def replace_api(self, override):
        cutover_authority(self.config)
        self.command(self.prefix + ['-f', str(override), 'up', '--detach', '--no-deps', '--no-build',
                                   '--pull', 'never', '--scale', 'api=1', '--wait',
                                   '--wait-timeout', '120', 'api'], timeout=180)


def inputs(config):
    """Recheck private inputs without ever publishing their contents."""
    initial = config['initial_transition']
    items = initial.get('protected_inputs', [])
    require(isinstance(items, list) and items and all(isinstance(item, dict) for item in items)
            and len({item.get('path') for item in items}) == len(items)
            and any(item.get('path') == config['compose_env']
                    and item.get('policy', 'root-private-v1') == 'root-private-v1' for item in items),
            'private_inputs_unapproved')
    result = {}
    for item in items:
        result[item['path']] = private_inputs.binding(item)
    auth = protected(Path(config['docker_config']) / 'config.json')
    result['registry_auth'] = sha256(auth.read_bytes())
    recovery = initial.get('recovery', {})
    archive = protected(recovery['archive'])
    # Stream a potentially large archive; no extraction/loading or inferred source history.
    digest = hashlib.sha256()
    with archive.open('rb') as stream:
        while block := stream.read(1024 * 1024):
            digest.update(block)
    require(recovery.get('approval') and digest.hexdigest() == recovery.get('sha256')
            and archive.stat().st_size == recovery.get('size') and recovery.get('image_id') == LEGACY,
            'recovery_archive_changed')
    record = read_private(recovery['record'])
    require(record.get('image_id') == LEGACY and record.get('git_commit') is None
            and sha256(protected(recovery['record']).read_bytes()) == recovery.get('record_sha256'),
            'recovery_record_invalid')
    return {**result, 'recovery_archive': digest.hexdigest(), 'recovery_record': recovery['record_sha256']}


def bind_inputs(config, snapshot):
    """Private file mounts cannot be omitted from the reviewed input hashes."""
    public = {str(Path(config['compose_root']) / 'Caddyfile'),
              *[item['path'] for item in config['compose_artifacts']],
              *[item['path'] for item in config['compose_layers']]}
    items = config['initial_transition']['protected_inputs']
    private = {item['path'] for item in items}
    containers = [snapshot['api'], *snapshot['unrelated'].values()]
    private_inputs.bind_mounts(items, containers)
    for container in containers:
        for mount in container.get('mounts', []):
            if mount.get('Type') != 'bind':
                continue
            path = Path(mount['Source'])
            require(path.is_absolute(), 'private_bind_input_unapproved')
            if path.is_file():
                require(str(path) in public | private and path.resolve() == path,
                        'private_bind_input_unapproved')


def validate_config(config, policy):
    cutover_authority(config)
    require(config.get('environment') == 'dev' and config.get('project_ref') == DEV_PROJECT,
            'initial_environment_invalid')
    p = target('dev', policy)
    require(policy['dev']['deployment_enabled'] is True and p['branch'] == 'develop', 'initial_environment_invalid')
    initial = config.get('initial_transition', {})
    require(initial.get('acceptance_required') is True, 'initial_acceptance_gate_required')
    require(initial.get('enabled') is True and initial.get('source_revision') == SOURCE
            and initial.get('source_digest') == SOURCE_DIGEST and initial.get('candidate_image_id') == CANDIDATE,
            'initial_source_unapproved')
    revision(initial.get('approved_branch_head'))
    require(len(inventory.layout(config)) == 5, 'five_compose_layers_required')
    repo = Path(config['repository'])
    require(repo.is_absolute() and repo.resolve() == repo, 'repository_path_invalid')
    for key in ('state_root', 'report_root', 'docker_config'):
        path = protected(config[key], directory=True)
        require(path != repo and repo not in path.parents, 'owner_path_in_source')
    approvals = protected(initial['approval_root'], directory=True)
    require(approvals != repo and repo not in approvals.parents
            and approvals != Path(config['state_root']), 'approval_path_invalid')
    return p


def proof_for(config):
    initial = config['initial_transition']
    return dict(image=initial['image'], image_id=CANDIDATE, git_commit=SOURCE, source_digest=SOURCE_DIGEST)


def check_source(config, head):
    require(head() == config['initial_transition']['approved_branch_head'], 'branch_changed')
    require(ancestor(config['repository'], SOURCE, config['initial_transition']['approved_branch_head']),
            'source_not_on_develop')
    require(manifest(config['repository'], SOURCE)['ingestion_support'] == SOURCE_DIGEST, 'source_digest_mismatch')


def check_image(docker, proof):
    docker.verify_image(proof)
    image = docker.image(proof['image'])
    require(image.get('user') == '10001:10001' and image.get('architecture') == 'arm64'
            and image.get('os') == 'linux', 'candidate_runtime_invalid')
    require(docker.image(LEGACY)['id'] == LEGACY, 'rollback_image_missing')


def prepare(config, policy, docker, head, registry, now=time.time):
    p = validate_config(config, policy)
    state = Path(config['state_root'])
    with deployment_lock(state):
        require(not (state / JOURNAL).exists() and not (state / 'initial-plan.json').exists(),
                'initial_transition_already_prepared')
        check_source(config, head)
        proof = proof_for(config)
        check_image(docker, proof)
        remote = registry.verify(proof)  # Required remote content proof, never local RepoDigest alone.
        private_inputs = inputs(config)
        override = service_manifest('dev', SOURCE, proof['image'], policy)
        override_path = state / (SOURCE + '.compose.json')
        require(not (state / (SOURCE + '.provenance.json')).exists(), 'initial_ledger_already_exists')
        journal = {'state': 'PREPARING', 'plan_digest': None,
                   'activation_attempted': False, 'observed_at': now()}
        publish(state / JOURNAL, journal)
        try:
            publish(override_path, override, immutable=True)
            with source_tree(config['repository'], SOURCE) as source:
                before = docker.snapshot(source)
                bind_inputs(config, before)
                require(before['api']['security']['user'] == '10001:10001',
                        'candidate_relationship_requires_review')
                hashes = docker.override_hashes(override_path)
            check_source(config, head)
            plan = {'schema_version': 1, **envelope('dev', p, SOURCE), 'created_at': now(),
                    'config_digest': inventory.digest(config),
                    'branch_head': config['initial_transition']['approved_branch_head'], 'proof': proof,
                    'remote': remote, 'private_inputs': private_inputs, 'before': before,
                    'legacy_provenance': {'git_commit': None, 'source_digest': None, 'status': 'unknown'},
                    'after': {'image_id': CANDIDATE, 'override': override,
                              'override_hashes': hashes, 'runtime_sha256': inventory.runtime_identity(before['api']),
                              'user': '10001:10001', 'command': API_COMMAND},
                    'activation_target': 'api', 'rollback': 'separate_owner_authorization_required'}
            plan_digest = inventory.digest(plan)
            publish(state / 'initial-plan.json', plan, immutable=True)
            publish(state / JOURNAL, {'state': 'PREPARED', 'plan_digest': plan_digest,
                                     'activation_attempted': False, 'observed_at': now()})
            return {'state': 'PREPARED', 'plan_digest': plan_digest, 'activation_attempted': False}
        except Exception as error:
            failure(state, journal, error, False, now)
            raise


def load_plan(config, policy):
    validate_config(config, policy)
    state = Path(config['state_root'])
    journal = read_private(state / JOURNAL)
    plan = read_private(state / 'initial-plan.json')
    require(inventory.digest(plan) == journal['plan_digest']
            and inventory.digest(config) == plan['config_digest'], 'plan_integrity_failed')
    override = state / (SOURCE + '.compose.json')
    require(read_private(override) == plan['after']['override'] ==
            service_manifest('dev', SOURCE, plan['proof']['image'], policy), 'api_override_unapproved')
    return state, journal, plan, override


def approve(config, journal, plan, approval, now):
    cutover_authority(config)
    path = root_controlled(approval)
    require(path.parent == Path(config['initial_transition']['approval_root']), 'approval_path_invalid')
    value = read_private(path)
    require(value.get('kind') == 'moneybowl-initial-api-activation-v1'
            and value.get('plan_digest') == journal['plan_digest'] and value.get('environment') == 'dev'
            and value.get('project_ref') == DEV_PROJECT and value.get('target') == 'api'
            # owner is only a human review reference; root filesystem authority authorizes.
            and value.get('branch_head') == plan['branch_head'] and value.get('owner')
            and re.fullmatch(r'[0-9a-f]{64}', value.get('nonce', ''))
            and type(value.get('expires_at')) in (int, float) and now() < value['expires_at'] <= now() + 3600,
            'owner_approval_invalid')
    return value


def failure(state, journal, error, attempted, now, *, uncertain=False, docker=None):
    # A command timeout/crash cannot establish what Docker changed. Never blind retry.
    reason = str(error) if isinstance(error, Rejected) else 'transition_measurement_unavailable'
    uncertain = (uncertain or not isinstance(error, Rejected) or isinstance(error, Pending)
                 or reason in ('owner_command_failed', 'registry_unavailable', 'git_failed'))
    status = 'UNKNOWN' if attempted and uncertain else 'FAILED'
    diagnostics = {'plan_digest': journal.get('plan_digest'), 'state': status,
                   'reason': reason, 'activation_attempted': attempted, 'observed_at': now()}
    if docker is not None:
        for name, read in (('api', docker.current), ('retirement', docker.retirement)):
            try:
                diagnostics[name] = read()
            except Exception as measurement:
                diagnostics[name] = {'state': 'unavailable', 'reason': str(measurement)
                                     if isinstance(measurement, Rejected) else 'measurement_unavailable'}
    try:
        publish(state / 'initial-failure.json', diagnostics, immutable=True)
    except Exception:
        # Intent/journal remain authoritative even when diagnostic storage is unavailable.
        diagnostics = None
    publish(state / JOURNAL, {**journal, 'state': status, 'activation_attempted': attempted,
                             'reason': reason, 'observed_at': now(), 'recovery': 'review_required',
                             'diagnostics_recorded': diagnostics is not None})
    return {'state': status, 'reason': reason, 'activation_attempted': attempted}


def activate(config, policy, docker, head, registry, approval, now=time.time):
    cutover_authority(config)
    state = Path(config['state_root'])
    with deployment_lock(state):
        state, journal, plan, override = load_plan(config, policy)
        require(journal['state'] == 'PREPARED', 'activation_not_retryable')
        attempted = False
        try:
            authority = approve(config, journal, plan, approval, now)
            consumed = state / ('approval-' + authority['nonce'] + '.consumed.json')
            require(not consumed.exists(), 'owner_approval_reused')
            check_source(config, head); check_image(docker, plan['proof'])
            require(registry.verify(plan['proof']) == plan['remote'], 'remote_registry_changed')
            require(inputs(config) == plan['private_inputs'], 'private_inputs_changed')
            with source_tree(config['repository'], SOURCE) as source:
                require(docker.snapshot(source) == plan['before'], 'before_state_changed')
                require(docker.override_hashes(override) == plan['after']['override_hashes'], 'compose_configuration_changed')
                check_source(config, head)
                require(read_private(override) == plan['after']['override'], 'api_override_unapproved')
                require(approve(config, journal, plan, approval, now) == authority, 'owner_approval_changed')
                # Consume permission and persist intent BEFORE the one external mutation.
                publish(consumed, {'plan_digest': journal['plan_digest'], 'nonce': authority['nonce']}, immutable=True)
                journal = {**journal, 'state': 'ACTIVATION_ATTEMPTED', 'activation_attempted': True,
                           'approval_digest': sha256(protected(approval).read_bytes()), 'observed_at': now()}
                publish(state / JOURNAL, journal)
                attempted = True
                docker.replace_api(override)
            publish(state / JOURNAL, {**journal, 'state': 'ACTIVATED_NOT_VERIFIED', 'observed_at': now()})
            return {'state': 'ACTIVATED_NOT_VERIFIED', 'activation_attempted': True}
        except Exception as error:
            return failure(state, journal, error, attempted, now, uncertain=attempted, docker=docker)


def verify(config, policy, docker, head, registry, now=time.time):
    cutover_authority(config)
    state = Path(config['state_root'])
    with deployment_lock(state):
        state, journal, plan, override = load_plan(config, policy)
        require(journal['state'] == 'ACTIVATED_NOT_VERIFIED', 'verification_not_authorized')
        try:
            # Persist the no-retry boundary even when termination bypasses Exception handlers.
            journal = {**journal, 'state': 'VERIFYING', 'observed_at': now()}
            publish(state / JOURNAL, journal)
            check_source(config, head); check_image(docker, plan['proof'])
            require(registry.verify(plan['proof']) == plan['remote'], 'remote_registry_changed')
            require(inputs(config) == plan['private_inputs'], 'private_inputs_changed')
            with source_tree(config['repository'], SOURCE) as source:
                after = docker.snapshot(source, plan['proof'], override)
                require(after['unrelated'] == plan['before']['unrelated'] and
                        after['retired'] == plan['before']['retired'], 'support_infrastructure_changed')
                current = after['api']
                require(current['id'] != plan['before']['api']['id'] and current['image'] == CANDIDATE
                        and inventory.runtime_identity(current) == plan['after']['runtime_sha256'],
                        'replacement_identity_invalid')
                require(docker.override_hashes(override) == plan['after']['override_hashes'], 'compose_configuration_changed')
            check_source(config, head)
            receipt = {**envelope('dev', target('dev', policy), SOURCE), 'observed_at': now(),
                       'oracle_dispatcher': 'retired', 'component': {'state': 'deployed',
                       'proof': 'running_image', 'healthy': True, 'source_digest': SOURCE_DIGEST},
                       'image': plan['proof']['image'], 'image_id': CANDIDATE}
            # Private diagnostics first, trusted ledger second, sanitized receipt last.
            verification = {'plan_digest': journal['plan_digest'],
                    'after': after, 'remote': plan['remote'], 'receipt': receipt,
                    'receipt_digest': inventory.digest(receipt)}
            publish(state / 'initial-verification.json', verification, immutable=True)
            publish(state / (SOURCE + '.provenance.json'), plan['proof'], immutable=True)
            # Permanent initial receipt is distinct from the regular owner's evolving report.
            publish(state / 'initial-service-receipt.json', receipt, immutable=True)
            # No success is exported to the regular report root during this transaction.
            # That owner publishes fresh measurements only after completed acceptance.
            # Completion is last; every consumer must also independently check these bindings.
            publish(state / JOURNAL, {**journal, 'state': 'VERIFIED', 'observed_at': now(),
                    'completion_version': 1, 'verification_digest': inventory.digest(verification),
                    'provenance_digest': inventory.digest(plan['proof']),
                    'receipt_digest': inventory.digest(receipt)})
            return {'state': 'VERIFIED', 'activation_attempted': True, 'git_commit': SOURCE}
        except Exception as error:
            return failure(state, journal, error, True, now, docker=docker)


def installed_code():
    """The privileged CLI may only execute a sealed root-owned installation."""
    directory = Path(__file__).resolve().parent
    require(Path(__file__).absolute() == Path(__file__).resolve(), 'privileged_code_not_installed')
    for path in [directory, *directory.parents, *directory.glob('*.py'), directory / 'environments.json']:
        info = path.lstat()
        require(info.st_uid == 0 and not info.st_mode & 0o022 and not path.is_symlink(),
                'privileged_code_not_installed')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('phase', choices=('prepare', 'activate', 'verify'))
    parser.add_argument('--config', required=True)
    parser.add_argument('--approval')
    args = parser.parse_args()
    try:
        installed_code()
        require(os.getuid() == 0 and os.geteuid() == 0, 'cutover_requires_root_operator')
        config = read_private(root_controlled(args.config))
        require(Path(config['repository']) not in Path(args.config).parents, 'owner_config_in_source')
        policy = load_policy()
        validate_config(config, policy)
        registry = Registry(config)
        docker = InitialDockerOwner(config)
        head = lambda: latest(config['repository'], 'develop')
        if args.phase == 'activate':
            require(args.approval is not None, 'owner_approval_missing')
            result = activate(config, policy, docker, head, registry, args.approval)
        else:
            action = prepare if args.phase == 'prepare' else verify
            result = action(config, policy, docker, head, registry)
    except Exception as error:
        result = {'state': 'BLOCKED', 'reason': str(error) if isinstance(error, Rejected) else 'prerequisite_unavailable'}
    print(json.dumps(result, sort_keys=True))
    return 0 if result['state'] in ('PREPARED', 'ACTIVATED_NOT_VERIFIED', 'VERIFIED') else 1


if __name__ == '__main__':
    raise SystemExit(main())
