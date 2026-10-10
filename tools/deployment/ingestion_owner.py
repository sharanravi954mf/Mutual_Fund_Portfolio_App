"""Private ingestion owner: exact-source build, API-only activation, independent remeasurement.

No deployment commands run on import. CLI requires an owner-controlled commissioned config.
"""
import argparse
import json
import re
import tempfile
import time
from pathlib import Path

from contract import Rejected, git, load_policy, manifest, require, revision
from observe import ancestor, read_json
from owner_common import (Command, atomic_json, binding, envelope, latest, lock,
                          pinned_executable, private_config, source_tree)
from service_manifest import service_manifest

DIGEST = re.compile(r'sha256:[0-9a-f]{64}')
INFRA_FILES = ('compose.yaml', 'compose.hosted.yaml', 'Caddyfile')
API_COMMAND = ['uvicorn', 'app.main:app', '--host', '0.0.0.0', '--port', '8080',
               '--no-access-log', '--workers', '1']


class DockerOwner:
    def __init__(self, config, command=None):
        self.config = config
        self.docker = pinned_executable(config, 'docker') if command is None else '/usr/bin/docker'
        self.systemctl = pinned_executable(config, 'systemctl') if command is None else '/usr/bin/systemctl'
        self.command = command or Command({'DOCKER_CONFIG': config['docker_config']})
        require(re.fullmatch('[a-z0-9][a-z0-9_-]+', config['compose_project']), 'invalid_compose_project')
        require(re.fullmatch('[a-z0-9][a-z0-9./_-]+', config['image_repository']), 'invalid_image_repository')
        self.root = Path(config['compose_root']).resolve()
        require(config.get('docker_socket') == 'unix:///var/run/docker.sock', 'remote_docker_forbidden')
        self.base = [self.docker, '--host', config['docker_socket']]
        self.prefix = self.base + ['compose', '--project-name', config['compose_project'],
                       '--project-directory', str(self.root), '--env-file', config['compose_env'],
                       '-f', str(self.root / 'compose.yaml'), '-f', str(self.root / 'compose.hosted.yaml')]

    def container(self, container_id):
        require(re.fullmatch('[a-zA-Z0-9][a-zA-Z0-9_.-]*', container_id), 'invalid_container_id')
        # Project only required fields: never retrieve Config.Env or Docker auth.
        template = '{"id":{{json .Id}},"image":{{json .Image}},"state":{{json .State}},"labels":{{json .Config.Labels}},"command":{{json .Config.Cmd}},"entrypoint":{{json .Config.Entrypoint}},"restart":{{json .HostConfig.RestartPolicy.Name}}}'
        return json.loads(self.command(self.base + ['inspect', '--format', template, container_id]))

    def containers(self, service):
        require(service in ('api', 'caddy', 'clamav'), 'service_not_allowlisted')
        ids = self.command(self.prefix + ['ps', '--all', '--quiet', service]).decode().split()
        result = [self.container(value) for value in ids]
        for item in result:
            labels = item['labels']
            require(labels.get('com.docker.compose.project') == self.config['compose_project']
                    and labels.get('com.docker.compose.service') == service, 'container_owner_mismatch')
        return result

    def retirement(self):
        names = self.command(self.base + ['ps', '--all', '--format', '{{.Names}}']).decode().splitlines()
        required = self.config['retired_containers']
        units = self.config['retired_units']
        require(required and units, 'retirement_inventory_missing')
        for name in required:
            require(re.fullmatch('[a-zA-Z0-9][a-zA-Z0-9_.-]*', name), 'invalid_retirement_inventory')
            if name in names:
                old = self.container(name)
                require(old['state']['Running'] is False and old['restart'] == 'no', 'legacy_dispatcher_not_retired')
        # Discover additional Compose legacy dispatchers, not just the commissioned names.
        ids = self.command(self.base + ['ps', '--all', '--quiet', '--filter',
                            'label=com.docker.compose.service=outbox-dispatcher']).decode().split()
        for value in ids:
            old = self.container(value)
            require(old['state']['Running'] is False and old['restart'] == 'no', 'legacy_dispatcher_not_retired')
        for unit in units:
            require(re.fullmatch(r'[a-zA-Z0-9][a-zA-Z0-9_.@-]*\.(service|timer)', unit), 'invalid_retirement_inventory')
            raw = self.command([self.systemctl, 'show', unit, '--property=LoadState,ActiveState,UnitFileState']).decode()
            fields = dict(line.split('=', 1) for line in raw.splitlines() if '=' in line)
            require(fields.get('ActiveState') in ('inactive', 'failed') and
                    (fields.get('LoadState') == 'not-found' or fields.get('UnitFileState') in ('masked', 'masked-runtime')),
                    'legacy_restart_owner_enabled')
        return 'retired'

    def config_hash(self, service, override=None):
        prefix = self.prefix + ([] if override is None else ['-f', str(override)])
        parts = self.command(prefix + ['config', '--hash', service]).decode().split()
        require(len(parts) == 2 and parts[0] == service and re.fullmatch('[0-9a-f]{64}', parts[1]), 'compose_hash_unverifiable')
        return parts[1]

    def infrastructure(self, source):
        require(self.command(self.base + ['info', '--format', '{{.ID}}']).decode().strip() == self.config['daemon_id'],
                'wrong_docker_daemon')
        for name in INFRA_FILES:
            actual = self.root / name
            require(not actual.is_symlink() and actual.read_bytes() == (source / 'services/ingestion-support' / name).read_bytes(),
                    'infrastructure_change_requires_commissioning')
        self.retirement()
        snapshot = {}
        for service in ('caddy', 'clamav'):
            values = self.containers(service)
            require(len(values) == 1 and values[0]['state']['Running'] is True, 'support_service_not_running')
            if service == 'clamav':
                require(values[0]['state'].get('Health', {}).get('Status') == 'healthy', 'clamav_not_healthy')
            require(values[0]['labels'].get('com.docker.compose.config-hash') == self.config_hash(service), 'running_configuration_drift')
            refs = self.command(self.prefix + ['config', '--images', service]).decode().split()
            require(len(refs) == 1 and '@sha256:' in refs[0], 'support_image_not_pinned')
            require(self.image(refs[0])['id'] == values[0]['image'], 'support_image_drift')
            snapshot[service] = {'id': values[0]['id'], 'image': values[0]['image']}
        return snapshot

    def image(self, image):
        data = json.loads(self.command(self.base + ['image', 'inspect', '--format',
            '{"id":{{json .Id}},"digests":{{json .RepoDigests}},"labels":{{json .Config.Labels}},"command":{{json .Config.Cmd}},"entrypoint":{{json .Config.Entrypoint}}}', image]))
        require(DIGEST.fullmatch(data['id']), 'invalid_image_id')
        return data

    def build(self, source, sha, source_digest):
        context = source / 'services/ingestion-support'
        require(not (context / '.env').exists(), 'secret_build_context_rejected')
        tag = self.config['image_repository'] + ':m4-' + sha
        with tempfile.TemporaryDirectory(prefix='m4-image-') as tmp:
            iidfile = Path(tmp) / 'id'
            self.command(self.base + ['build', '--target', 'runtime', '--iidfile', str(iidfile),
                          '--label', 'org.opencontainers.image.revision=' + sha,
                          '--label', 'moneybowl.source_digest=' + source_digest,
                          '--tag', tag, str(context)], timeout=1800)
            image_id = iidfile.read_text().strip()
            require(DIGEST.fullmatch(image_id), 'invalid_image_id')
        self.command(self.base + ['push', tag], timeout=600)
        image = self.image(tag)
        require(image['id'] == image_id, 'built_image_changed')
        refs = [ref for ref in image['digests'] if ref.startswith(self.config['image_repository'] + '@sha256:')]
        require(len(refs) == 1, 'registry_digest_unverified')
        return {'image': refs[0], 'image_id': image_id, 'git_commit': sha, 'source_digest': source_digest}

    def verify_image(self, provenance):
        image = self.image(provenance['image'])
        require(image['id'] == provenance['image_id'] and provenance['image'] in image['digests'], 'image_provenance_mismatch')
        require(image.get('command') == API_COMMAND and not image.get('entrypoint'), 'single_worker_command_required')
        require(image['labels'].get('org.opencontainers.image.revision') == provenance['git_commit'] and
                image['labels'].get('moneybowl.source_digest') == provenance['source_digest'], 'image_provenance_mismatch')

    def current(self):
        values = self.containers('api')
        require(len(values) <= 1, 'multiple_api_workers')
        return values[0] if values else None

    def activate(self, override):
        # Explicit service + no-deps: cannot start the legacy dispatcher, Caddy or ClamAV.
        self.command(self.prefix + ['-f', str(override), 'up', '--detach', '--no-deps', '--no-build',
                                    '--pull', 'never', '--scale', 'api=1', '--wait', '--wait-timeout', '120', 'api'], timeout=180)

    def verified(self, provenance, override):
        self.verify_image(provenance)
        current = self.current()
        require(current is not None and current['image'] == provenance['image_id'], 'running_image_mismatch')
        require(current.get('command') == API_COMMAND and not current.get('entrypoint'), 'single_worker_command_required')
        require(current['state']['Running'] is True and current['state'].get('Health', {}).get('Status') == 'healthy',
                'service_unhealthy')
        require(current['labels'].get('org.opencontainers.image.revision') == provenance['git_commit'] and
                current['labels'].get('moneybowl.environment') == self.config['environment'], 'running_revision_mismatch')
        require(current['labels'].get('com.docker.compose.config-hash') == self.config_hash('api', override), 'running_configuration_drift')
        require(read_json(self.config['service_origin'].rstrip('/') + '/ready') == {'status': 'ready'}, 'public_service_not_ready')
        return current


def reconcile(config, policy, docker, repo, current_head, now=time.time):
    env, p = binding(config, policy)
    state = Path(config['state_root'])
    with lock(state):
        sha = revision(current_head())
        report_path = Path(config['report_root']) / (sha + '.json')
        report_path.unlink(missing_ok=True)
        try:
            return deploy_locked(config, policy, docker, repo, current_head, now, env, p, state, sha, report_path)
        except Exception:
            atomic_json(report_path, {**envelope(env, p, sha), 'state': 'failed', 'reason': 'service_measurement_failed'})
            raise


def deploy_locked(config, policy, docker, repo, current_head, now, env, p, state, sha, report_path):
    expected = manifest(repo, sha)['ingestion_support']
    with source_tree(repo, sha) as source:
        before = docker.infrastructure(source)
        current = docker.current()
        if current:
            previous = current['labels'].get('org.opencontainers.image.revision')
            # Legacy image without a revision requires a separately reviewed initial binding.
            previous = previous or config.get('initial_revision')
            require(ancestor(repo, revision(previous), sha), 'service_rollback_rejected')
            if not current['labels'].get('org.opencontainers.image.revision'):
                require(current['image'] == config.get('initial_image_id'), 'initial_image_binding_mismatch')
        ledger_path = state / (sha + '.provenance.json')
        if ledger_path.exists():
            provenance = json.loads(ledger_path.read_text())
            require(provenance['git_commit'] == sha and provenance['source_digest'] == expected, 'ledger_mismatch')
        else:
            provenance = docker.build(source, sha, expected)
            require(provenance['git_commit'] == sha and provenance['source_digest'] == expected, 'builder_provenance_mismatch')
            docker.verify_image(provenance)
            atomic_json(ledger_path, provenance)
        override = service_manifest(env, sha, provenance['image'], policy)
        docker.verify_image(provenance)
        require(docker.infrastructure(source) == before, 'support_infrastructure_changed')
        fresh = docker.current()
        fingerprint = lambda value: None if value is None else (value.get('id'), value['image'], value['labels'])
        require(fingerprint(fresh) == fingerprint(current), 'api_changed_during_build')
        override_path = state / (sha + '.compose.json')
        atomic_json(override_path, override)
        if current_head() != sha:
            return {'state': 'superseded', 'git_commit': sha}
        if current is None or current['image'] != provenance['image_id'] or current['labels'].get('org.opencontainers.image.revision') != sha:
            docker.activate(override_path)  # One attempt. Never automatic rollback or restart retry.
        docker.verified(provenance, override_path)
        require(docker.infrastructure(source) == before, 'support_infrastructure_changed')
        if current_head() != sha:
            return {'state': 'superseded', 'git_commit': sha}
        result = {**envelope(env, p, sha), 'observed_at': now(), 'oracle_dispatcher': 'retired',
                  'component': {'state': 'deployed', 'proof': 'running_image', 'healthy': True,
                                'source_digest': expected}, 'image_id': provenance['image_id'],
                  'image': provenance['image']}
        atomic_json(report_path, result)
        return {'state': 'deployed', 'git_commit': sha}

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', required=True)
    args = parser.parse_args()
    try:
        config = private_config(args.config)
        env, p = binding(config, load_policy())
        repo = config['repository']
        result = reconcile(config, load_policy(), DockerOwner(config), repo, lambda: latest(repo, p['branch']))
    except Rejected as error:
        result = {'state': 'failed', 'reason': str(error)}
    except Exception:
        result = {'state': 'failed', 'reason': 'service_owner_failed'}
    print(json.dumps(result, sort_keys=True))
    return 0 if result['state'] in ('deployed', 'superseded') else 1


if __name__ == '__main__':
    raise SystemExit(main())
