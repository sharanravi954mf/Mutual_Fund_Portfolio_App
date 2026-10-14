"""Private ingestion owner: exact-source build, API-only activation, independent remeasurement.

No deployment commands run on import. CLI requires an owner-controlled commissioned config.
"""
import argparse
import json
import os
import re
import tempfile
import time
from pathlib import Path

from contract import Rejected, git, load_policy, manifest, require, revision
from observe import ancestor, read_json
from owner_common import (Command, atomic_json, binding, envelope, latest, lock,
                          pinned_executable, private_config, source_tree)
from service_manifest import service_manifest
from private_registry import Registry
from protected_io import deployment_lock
import initial_transition_integrity as initial_integrity
import compose_inventory as inventory

DIGEST = re.compile(r'sha256:[0-9a-f]{64}')
IMAGE_REFERENCE = re.compile(
    r'(?:[a-z0-9]+(?:[.-][a-z0-9]+)*(?::[0-9]+)?/)?'
    r'[a-z0-9]+(?:(?:[._]|__|-+)[a-z0-9]+)*'
    r'(?:/[a-z0-9]+(?:(?:[._]|__|-+)[a-z0-9]+)*)*'
    r'(?::[A-Za-z0-9_][A-Za-z0-9_.-]{0,127})?(?:@sha256:[0-9a-f]{64})?')
DEV_RETIRED_CONTAINER = 'moneybowl-ingestion-support-outbox-dispatcher-1'
DEV_RECONCILER = 'moneybowl-outbox-dispatcher-reconcile'
DEV_RETIRED_SERVICES = [DEV_RECONCILER + '.service', DEV_RECONCILER + '@.service']
DEV_RETIRED_TIMER = DEV_RECONCILER + '.timer'
API_COMMAND = ['uvicorn', 'app.main:app', '--host', '0.0.0.0', '--port', '8080',
               '--no-access-log', '--workers', '1']


class DockerOwner:
    def __init__(self, config, command=None, registry=None):
        self.config = config
        inventory.layout(config)
        if command is not None:
            require(not isinstance(command, Command), 'live_command_injection_forbidden')
        if command is None:
            # Raw Engine access is root-equivalent, even for inspection. No non-root
            # execution boundary has been commissioned; a Docker-group grant is not one.
            require(os.getuid() == os.geteuid() == 0, 'docker_execution_boundary_uncommissioned')
        self._offline_transport = command is not None
        # Production always requires independently provisioned private registry access.
        # Injected command transports permit offline tests without live credentials.
        self.registry = Registry(config) if command is None else registry
        if command is None:
            self.registry.credential()  # Validate Docker auth location before any plugin discovery.
        self.docker = pinned_executable(config, 'docker') if command is None else '/usr/bin/docker'
        self.systemctl = pinned_executable(config, 'systemctl') if command is None else '/usr/bin/systemctl'
        self.command = command or Command({'DOCKER_CONFIG': config['docker_config']})
        require(re.fullmatch('[a-z0-9][a-z0-9_-]+', config['compose_project']), 'invalid_compose_project')
        require(re.fullmatch('[a-z0-9][a-z0-9./_-]+', config['image_repository']), 'invalid_image_repository')
        self.root = Path(config['compose_root']).resolve()
        require(config.get('docker_socket') == 'unix:///var/run/docker.sock', 'remote_docker_forbidden')
        self.base = [self.docker, '--host', config['docker_socket']]
        if command is None:
            plugin = pinned_executable(config, 'compose_plugin')
            actual = self.command(self.base + ['info', '--format',
                '{{range .ClientInfo.Plugins}}{{if eq .Name "compose"}}{{.Path}}{{end}}{{end}}']).decode().strip()
            require(actual == plugin, 'compose_plugin_binding_invalid')
        self.prefix = self.base + ['compose', '--project-name', config['compose_project'],
                       '--project-directory', str(self.root), '--env-file', config['compose_env'],
                       *[arg for layer in config['compose_layers'] for arg in ('-f', layer['path'])]]
        self._activation = None

    def container(self, container_id):
        require(re.fullmatch('[a-zA-Z0-9][a-zA-Z0-9_.-]*', container_id), 'invalid_container_id')
        # Project only required fields: never retrieve Config.Env or Docker auth.
        template = '{"id":{{json .Id}},"image":{{json .Image}},"state":{"Status":{{json .State.Status}},"Running":{{json .State.Running}},"Pid":{{json .State.Pid}},"Restarting":{{json .State.Restarting}},"Paused":{{json .State.Paused}},"Dead":{{json .State.Dead}},"Health":{"Status":{{with (index .State "Health")}}{{json .Status}}{{else}}null{{end}}}},"labels":{{json .Config.Labels}},"command":{{json .Config.Cmd}},"entrypoint":{{json .Config.Entrypoint}},"restart":{{json .HostConfig.RestartPolicy.Name}},"mounts":{{json .Mounts}},"networks":{{json .NetworkSettings.Networks}},"ports":{{json .HostConfig.PortBindings}},"security":{"readonly":{{json .HostConfig.ReadonlyRootfs}},"privileged":{{json .HostConfig.Privileged}},"caps":{{json .HostConfig.CapDrop}},"options":{{json .HostConfig.SecurityOpt}},"user":{{json .Config.User}}}}'
        result = json.loads(self.command(self.base + ['inspect', '--format', template, container_id]))
        result['mounts'] = sorted([{key: value.get(key) for key in ('Type', 'Name', 'Source', 'Destination', 'RW')}
                                   for value in result['mounts']], key=lambda value: value['Destination'])
        result['networks'] = {name: {'id': value['NetworkID'],
                                   'aliases': sorted(a for a in (value.get('Aliases') or [])
                                                     if a not in (result['id'], result['id'][:12]))}
                              for name, value in result['networks'].items()}
        return result

    def containers(self, service):
        require(service in inventory.services(self.config), 'service_not_allowlisted')
        ids = self.command(self.base + ['ps', '--all', '--quiet', '--no-trunc', '--filter',
                    'label=com.docker.compose.project=' + self.config['compose_project'], '--filter',
                    'label=com.docker.compose.service=' + service]).decode().split()
        result = [self.container(value) for value in ids]
        for item in result:
            labels = item['labels']
            require(labels.get('com.docker.compose.project') == self.config['compose_project']
                    and labels.get('com.docker.compose.service') == service, 'container_owner_mismatch')
        return result

    def retirement(self):
        # The commissioned DEV inventory cannot be weakened by omitting a config entry.
        require(self.config.get('environment') == 'dev', 'retirement_environment_not_commissioned')
        require(self.config.get('retired_containers') == [DEV_RETIRED_CONTAINER]
                and self.config.get('retired_services') == DEV_RETIRED_SERVICES
                and self.config.get('retired_timers') == [DEV_RETIRED_TIMER], 'retirement_inventory_invalid')
        expected_id = self.config.get('retired_container_id', '')
        require(isinstance(expected_id, str) and re.fullmatch('[0-9a-f]{64}', expected_id),
                'retirement_container_binding_missing')
        # Inspect the required object directly: absent is unverifiable, not retired.
        old = self.container(DEV_RETIRED_CONTAINER)
        state = old.get('state', {})
        require(old.get('id') == expected_id and old.get('restart') == 'no'
                and state.get('Status') == 'exited' and state.get('Pid') == 0
                and all(state.get(flag) is False for flag in ('Running', 'Restarting', 'Paused', 'Dead')),
                'legacy_dispatcher_not_retired')
        labels = old.get('labels', {})
        require(labels.get('com.docker.compose.project') == 'moneybowl-ingestion-support'
                and labels.get('com.docker.compose.service') == 'outbox-dispatcher', 'retirement_container_mismatch')
        ids = self.command(self.base + ['ps', '--all', '--no-trunc', '--quiet', '--filter',
                            'label=com.docker.compose.service=outbox-dispatcher']).decode().split()
        require(ids == [expected_id], 'unexpected_legacy_dispatcher')

        # Templates are unit files, not executable units. Inspect persistent file state,
        # then inspect every concrete loaded instance so a template mask cannot hide one.
        raw = self.command([self.systemctl, 'list-unit-files', '--no-legend', '--no-pager',
                            DEV_RECONCILER + '*']).decode()
        files = {}
        for line in raw.splitlines():
            parts = line.split()
            require(len(parts) in (2, 3) and parts[0] not in files, 'retirement_units_unverifiable')
            files[parts[0]] = parts[1]
        required = set(DEV_RETIRED_SERVICES + [DEV_RETIRED_TIMER])
        require(required <= files.keys(), 'retirement_units_unverifiable')
        instance = re.compile(re.escape(DEV_RECONCILER) + r'@[a-zA-Z0-9_.-]+\.service')
        for unit, enabled in files.items():
            require(unit in required or instance.fullmatch(unit), 'unexpected_retirement_unit')
            require(enabled == ('disabled' if unit == DEV_RETIRED_TIMER else 'masked'),
                    'legacy_restart_owner_enabled')
        raw = self.command([self.systemctl, 'list-units', '--all', '--plain', '--no-legend',
                            '--no-pager', DEV_RECONCILER + '*']).decode()
        loaded = set()
        for line in raw.splitlines():
            parts = line.split()
            require(len(parts) >= 4 and parts[0] not in loaded, 'retirement_units_unverifiable')
            unit = parts[0]
            require(unit in (DEV_RETIRED_SERVICES[0], DEV_RETIRED_TIMER) or instance.fullmatch(unit),
                    'unexpected_retirement_unit')
            loaded.add(unit)
        concrete = (files.keys() | loaded) - {DEV_RETIRED_SERVICES[1]}
        for unit in sorted(concrete):
            raw = self.command([self.systemctl, 'show', unit,
                                '--property=Id,LoadState,ActiveState,SubState,UnitFileState']).decode()
            fields = {}
            for line in raw.splitlines():
                key, separator, value = line.partition('=')
                require(separator and key not in fields, 'retirement_units_unverifiable')
                fields[key] = value
            timer = unit == DEV_RETIRED_TIMER
            require(fields == dict(Id=unit, LoadState='loaded' if timer else 'masked',
                                   ActiveState='inactive', SubState='dead',
                                   UnitFileState='disabled' if timer else 'masked'),
                    'legacy_restart_owner_enabled')
        return 'retired'

    def config_hash(self, service, override=None):
        prefix = self.prefix + ([] if override is None else ['-f', str(override)])
        parts = self.command(prefix + ['config', '--hash', service]).decode().split()
        require(len(parts) == 2 and parts[0] == service and re.fullmatch('[0-9a-f]{64}', parts[1]), 'compose_hash_unverifiable')
        return parts[1]

    def compose_image(self, service):
        """Return only this service's resolved reference, never dependency image lists."""
        require(service in inventory.services(self.config), 'service_not_allowlisted')

        def unique_object(pairs):
            result = {}
            for key, value in pairs:
                require(key not in result, 'compose_image_unverifiable')
                result[key] = value
            return result

        def invalid_constant(value):
            raise ValueError

        # Interpolation uses the commissioned owner's private inputs. Do not load
        # service env files or retain/report the rest of the rendered configuration.
        # Command discards stderr and never includes child output in exceptions.
        raw = self.command(self.prefix + ['config', '--format', 'json', '--no-env-resolution', service])
        try:
            model = json.loads(raw, object_pairs_hook=unique_object, parse_constant=invalid_constant)
            require(isinstance(model, dict) and model.get('name') == self.config['compose_project'],
                    'compose_image_unverifiable')
            services = model.get('services')
            require(isinstance(services, dict) and isinstance(services.get(service), dict),
                    'compose_image_unverifiable')
            ref = services[service].get('image')
            require(isinstance(ref, str) and len(ref) <= 512 and IMAGE_REFERENCE.fullmatch(ref),
                    'compose_image_unverifiable')
            return ref
        except (ValueError, UnicodeError, RecursionError):
            raise Rejected('compose_image_unverifiable') from None

    def infrastructure(self, source):
        require(self.command(self.base + ['info', '--format', '{{.ID}}']).decode().strip() == self.config['daemon_id'],
                'wrong_docker_daemon')
        inventory.files(self.config, source)
        self.retirement()
        expected = inventory.services(self.config)
        require(set(self.config.get('compose_services', {})) == expected, 'service_inventory_uncommissioned')
        # Render structure without reading credentials. Resolved service hashes below are private-owner reads.
        structural = self.prefix.copy()
        structural[structural.index('--env-file') + 1] = '/dev/null'
        model = json.loads(self.command(structural + ['config', '--format', 'json', '--no-interpolate', '--no-env-resolution']))
        require(model.get('name') == self.config['compose_project'], 'compose_project_binding_invalid')
        require(set(model['services']) == expected | {'outbox-dispatcher'}, 'unexpected_compose_service')
        old = model['services']['outbox-dispatcher']
        require(old.get('profiles') == ['outbox-dispatch'], 'retired_service_profile_missing')
        for service in expected:
            definition = model['services'][service]
            require(not definition.get('profiles') and not definition.get('extends')
                    and 'outbox-dispatcher' not in definition.get('depends_on', {})
                    and not any('outbox-dispatcher' in str(definition.get(key, ''))
                                for key in ('network_mode', 'pid', 'ipc', 'volumes_from', 'links')),
                    'retired_service_dependency')
        require(inventory.digest(model) == self.config.get('compose_model_sha256'), 'compose_model_unapproved')
        all_ids = self.command(self.base + ['ps', '--all', '--quiet', '--no-trunc', '--filter',
                               'label=com.docker.compose.project=' + self.config['compose_project']]).decode().split()
        expected_ids = {self.config['retired_container_id']}
        snapshot = {}
        for service in sorted(expected):
            values = self.containers(service)
            require(len(values) == 1 and values[0]['state']['Running'] is True, 'support_service_not_running')
            value = values[0]; approved = self.config['compose_services'][service]
            expected_ids.add(value['id'])
            require(value['labels'].get('com.docker.compose.project.working_dir') == str(self.root)
                    and value['labels'].get('com.docker.compose.oneoff') == 'False', 'container_owner_mismatch')
            require(inventory.runtime_identity(value) == approved.get('runtime_sha256'), 'running_relationship_drift')
            health = value['state'].get('Health', {}).get('Status')
            if service in ('api', 'clamav', 'github-webhook', 'm3b-receiver'):
                require(health == 'healthy', 'support_service_unhealthy')
            else:
                require(health in (None, 'healthy'), 'support_service_unhealthy')
            if service == 'api':
                self.validate_current(value)
                continue
            require(value['id'] == approved.get('container_id') and value['image'] == approved.get('image_id'),
                    'support_image_or_container_drift')
            inventory.recorded_files(self.config, service, value['labels'].get('com.docker.compose.project.config_files'))
            require(value['labels'].get('com.docker.compose.config-hash') == approved.get('config_hash')
                    == self.config_hash(service), 'running_configuration_drift')
            # Existing non-API tags are never pulled/redeployed; approved local IDs remain authoritative.
            require(self.image(self.compose_image(service))['id'] == value['image'], 'support_image_drift')
            snapshot[service] = value
        require(set(all_ids) == expected_ids and len(all_ids) == len(expected_ids), 'unexpected_project_container')
        snapshot['resources'] = self.resources(model)
        # Caddy has no Engine healthcheck in DEV: verify its non-financial API route too.
        require(read_json(self.config['service_origin'].rstrip('/') + '/ready') == {'status': 'ready'},
                'public_service_not_ready')
        self._source = source
        return snapshot

    def resources(self, model):
        result = {}
        for kind in ('network', 'volume'):
            definitions = model.get(kind + 's', {})
            names = {definition['name'] for definition in definitions.values()}
            approved = self.config.get('compose_resources', {}).get(kind, {})
            require(names == set(approved), 'resource_inventory_uncommissioned')
            for name in sorted(names):
                require(re.fullmatch('[a-zA-Z0-9][a-zA-Z0-9_.-]+', name), 'invalid_resource_name')
                template = ('{"id":{{json .Id}},"name":{{json .Name}},"driver":{{json .Driver}},"internal":{{json .Internal}},"ipam":{{json .IPAM.Config}},"labels":{{json .Labels}}}'
                            if kind == 'network' else
                            '{"name":{{json .Name}},"driver":{{json .Driver}},"mountpoint":{{json .Mountpoint}},"scope":{{json .Scope}},"option_count":{{len .Options}},"labels":{{json .Labels}}}')
                actual = json.loads(self.command(self.base + [kind, 'inspect', '--format', template, name]))
                require(inventory.digest(actual) == approved[name], 'running_resource_drift')
                result[kind + ':' + name] = actual
        return result

    def capacity(self):
        require(self.command(self.base + ['info', '--format', '{{.DockerRootDir}}']).decode().strip()
                == self.config.get('docker_data_root'), 'docker_storage_binding_invalid')
        inventory.capacity(self.config)

    def validate_current(self, current):
        require(current is not None, 'api_baseline_missing')
        approved = self.config['compose_services']['api']
        require(current.get('command') == API_COMMAND and not current.get('entrypoint'), 'single_worker_command_required')
        require(inventory.runtime_identity(current) == approved.get('runtime_sha256'), 'running_relationship_drift')
        previous = current['labels'].get('org.opencontainers.image.revision')
        override = None
        if previous:
            previous = revision(previous)
            state = Path(self.config['state_root'])
            proof = json.loads((state / (previous + '.provenance.json')).read_text())
            require(proof['git_commit'] == previous and proof['image_id'] == current['image']
                    and proof['source_digest'] == manifest(self.config['repository'], previous)['ingestion_support'],
                    'ledger_mismatch')
            self.verify_image(proof)
            override = state / (previous + '.compose.json')
            require(json.loads(override.read_text()) == service_manifest('dev', previous, proof['image'], load_policy()),
                    'api_override_unapproved')
            recorded = ','.join([layer['path'] for layer in self.config['compose_layers']] + [str(override)])
            require(current['labels'].get('com.docker.compose.project.config_files') == recorded
                    and current['labels'].get('moneybowl.environment') == 'dev', 'container_compose_files_mismatch')
        else:
            require(current['id'] == approved.get('container_id') and current['image'] == approved.get('image_id'),
                    'initial_image_binding_mismatch')
            inventory.recorded_files(self.config, 'api', current['labels'].get('com.docker.compose.project.config_files'))
            require(current['labels'].get('com.docker.compose.config-hash') == approved.get('config_hash'),
                    'running_configuration_drift')
        require(current['labels'].get('com.docker.compose.config-hash') == self.config_hash('api', override),
                'running_configuration_drift')

    def image(self, image):
        data = json.loads(self.command(self.base + ['image', 'inspect', '--format',
            '{"id":{{json .Id}},"digests":{{json .RepoDigests}},"labels":{{json (index .Config "Labels")}},"command":{{json (index .Config "Cmd")}},"entrypoint":{{json (index .Config "Entrypoint")}}}', image]))
        require(DIGEST.fullmatch(data['id']), 'invalid_image_id')
        require(data.get('labels') is None or isinstance(data['labels'], dict), 'invalid_image_labels')
        data['labels'] = data.get('labels') or {}
        return data

    def build(self, source, sha, source_digest):
        # A source archive does not isolate Dockerfile RUN instructions from the
        # privileged host Engine. No live isolated builder has been reviewed.
        # There is intentionally no configuration flag that enables this path.
        require(self._offline_transport, 'untrusted_build_isolation_uncommissioned')
        self.capacity()
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
        proof = {'image': refs[0], 'image_id': image_id, 'git_commit': sha, 'source_digest': source_digest}
        if self.registry is not None:
            self.registry.verify(proof)
        return proof

    def verify_image(self, provenance):
        if self.registry is not None:
            self.registry.verify(provenance)
        image = self.image(provenance['image'])
        require(image['id'] == provenance['image_id'] and provenance['image'] in image['digests'], 'image_provenance_mismatch')
        require(image.get('command') == API_COMMAND and not image.get('entrypoint'), 'single_worker_command_required')
        require(image['labels'].get('org.opencontainers.image.revision') == provenance['git_commit'] and
                image['labels'].get('moneybowl.source_digest') == provenance['source_digest'], 'image_provenance_mismatch')

    def current(self):
        values = self.containers('api')
        require(len(values) <= 1, 'multiple_api_workers')
        return values[0] if values else None

    def prepare_activation(self, override, provenance):
        self._activation = None
        self.verify_image(provenance)
        require(json.loads(Path(override).read_text()) == service_manifest('dev', provenance['git_commit'], provenance['image'], load_policy()),
                'api_override_unapproved')
        before = self.infrastructure(self._source)
        for service in inventory.services(self.config) - {'api'}:
            require(self.config_hash(service, override) == self.config_hash(service), 'override_changes_unrelated_service')
        self._activation = (str(override), inventory.sha256(Path(override).read_bytes()), before, self.current())

    def activate(self, override):
        permission, self._activation = self._activation, None
        require(permission is not None and str(override) == permission[0]
                and inventory.sha256(Path(override).read_bytes()) == permission[1], 'api_activation_not_prepared')
        self.capacity()
        require(self.infrastructure(self._source) == permission[2] and self.current() == permission[3],
                'infrastructure_changed_before_activation')
        # Explicit service + no-deps and pre-existing verified resources. No down/prune/orphan removal.
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
    initial = initial_integrity.required(config)
    with deployment_lock(state) if initial else lock(state):
        # A partial initial transition cannot race into regular reconciliation.
        if initial_integrity.required(config):
            initial_integrity.completed(config, policy, repo)
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
    docker.capacity()
    with source_tree(repo, sha) as source:
        before = docker.infrastructure(source)
        current = docker.current()
        if current:
            previous = current['labels'].get('org.opencontainers.image.revision')
            # Legacy image without a revision requires a separately reviewed initial binding.
            previous = previous or inventory.initial_revision(config, current, repo)
            require(ancestor(repo, revision(previous), sha), 'service_rollback_rejected')
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
        docker.prepare_activation(override_path, provenance)
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
        if config.get('execution_boundary') == 'api-executor-v2':
            require(env == 'dev', 'execution_environment_invalid')
            from api_broker import client
            result = client(latest(repo, p['branch']))
        else:
            result = reconcile(config, load_policy(), DockerOwner(config), repo, lambda: latest(repo, p['branch']))
    except Rejected as error:
        result = {'state': 'failed', 'reason': str(error)}
    except Exception:
        result = {'state': 'failed', 'reason': 'service_owner_failed'}
    print(json.dumps(result, sort_keys=True))
    return 0 if result['state'] in ('deployed', 'already_deployed', 'superseded') else 1


if __name__ == '__main__':
    raise SystemExit(main())
