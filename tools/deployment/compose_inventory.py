"""DEV-only, privately approved Compose inventory. No host discovery becomes approval."""
import json
import os
import re
import tempfile
from pathlib import Path

from contract import git, require, revision
from owner_common import sha256

DEV_ROOT = '/home/ubuntu/moneybowl/services/ingestion-support'
DEV_LAYERS = (
    ('base', DEV_ROOT + '/compose.yaml', 'ingestion'),
    ('hosted', DEV_ROOT + '/compose.hosted.yaml', 'ingestion'),
    ('flutter', '/home/ubuntu/moneybowl-runtime/flutter-web-dev/compose.web-dev.yaml', 'flutter'),
    ('m3b', '/home/ubuntu/moneybowl-runtime/m3b/compose.m3b.yaml', 'director-m3b'),
    ('m3b-ingress', '/home/ubuntu/moneybowl-runtime/m3b/compose.m3b-ingress-adapter.yaml', 'director-m3b'),
)
HISTORICAL_M3B = DEV_ROOT + '/compose.m3b.yaml'
DEV_ARTIFACTS = {
    '/home/ubuntu/moneybowl-runtime/flutter-web-dev/Caddyfile': 'flutter',
    '/home/ubuntu/moneybowl-runtime/github-webhook-container/receiver.py': 'flutter',
}
SERVICES = {'api', 'caddy', 'clamav', 'github-webhook', 'm3b-receiver'}
HEX = re.compile('[0-9a-f]{64}')
MIN_FREE_BYTES = 12 * 1024 ** 3
MIN_FREE_INODES = 100_000


def digest(value):
    return sha256(json.dumps(value, sort_keys=True, separators=(',', ':')).encode())


def approved_file(item):
    path = Path(item['path'])
    require(path.is_file() and not path.is_symlink() and path.resolve() == path,
            'compose_layer_missing_or_linked')
    metadata = path.stat()
    require(type(item.get('uid')) is int and item['uid'] >= 0
            and type(item.get('mode')) is int and 0 <= item['mode'] <= 0o777
            and item['mode'] & 0o002 == 0
            and metadata.st_uid == item['uid'] and metadata.st_mode & 0o777 == item['mode'],
            'compose_file_authority_changed')
    return path


def capacity(config, stat=os.statvfs):
    """Reserve for concurrent Flutter/Docker work; never prune or start a build here."""
    for path in (config['state_root'], config['docker_data_root'], tempfile.gettempdir()):
        location = Path(path)
        require(location.is_absolute(), 'capacity_path_invalid')
        while not location.exists() and location != location.parent:
            location = location.parent
        value = stat(location)
        require(value.f_blocks > 0 and value.f_files > 0, 'capacity_unverifiable')
        require(value.f_bavail * value.f_frsize >= max(MIN_FREE_BYTES, value.f_blocks * value.f_frsize // 5)
                and value.f_favail >= max(MIN_FREE_INODES, value.f_files // 5), 'insufficient_build_capacity')


def layout(config):
    require(config.get('environment') == 'dev', 'compose_environment_not_commissioned')
    require(config.get('compose_project') == 'moneybowl-ingestion-support'
            and config.get('compose_root') == DEV_ROOT, 'compose_project_binding_invalid')
    layers = config.get('compose_layers', [])
    require(isinstance(layers, list) and len(layers) in (4, 5), 'compose_inventory_required')
    for value, (role, path, authority) in zip(layers, DEV_LAYERS):
        require(value.get('role') == role and value.get('path') == path
                and value.get('authority') == authority, 'compose_layer_not_approved')
        require(HEX.fullmatch(value.get('sha256', '')) and value.get('approval'), 'compose_layer_uncommissioned')
    return layers


def services(config):
    return SERVICES | ({'m3b-ingress-adapter'} if len(layout(config)) == 5 else set())


def files(config, source):
    for value in layout(config):
        path = approved_file(value)
        data = path.read_bytes()
        require(sha256(data) == value['sha256'], 'compose_layer_changed')
        if value['role'] in ('base', 'hosted'):
            require(data == (source / 'services/ingestion-support' / path.name).read_bytes(),
                    'infrastructure_change_requires_commissioning')
        elif value['role'] == 'm3b':
            # The relocated overlay needs its actual archived Git object in the owner mirror.
            origin = value.get('origin', {})
            require(origin.get('path') == 'services/ingestion-support/compose.m3b.yaml', 'm3b_origin_unverified')
            original = git(config['repository'], 'show', revision(origin.get('revision')) + ':' + origin['path'])
            require(data == original, 'm3b_origin_unverified')
    caddy = Path(config['compose_root']) / 'Caddyfile'
    require(caddy.is_file() and not caddy.is_symlink()
            and caddy.read_bytes() == (source / 'services/ingestion-support/Caddyfile').read_bytes(),
            'infrastructure_change_requires_commissioning')
    # Non-secret mounted application/config files need separate owner-approved byte bindings.
    bindings = config.get('compose_artifacts', [])
    require(isinstance(bindings, list) and len(bindings) == len(DEV_ARTIFACTS)
            and {item['path'] for item in bindings} == set(DEV_ARTIFACTS), 'compose_artifacts_uncommissioned')
    for item in bindings:
        path = Path(item['path'])
        require(path.is_absolute() and path.is_file() and path.resolve() == path
                and item.get('authority') == DEV_ARTIFACTS[str(path)]
                and item.get('approval') and HEX.fullmatch(item.get('sha256', '')),
                'compose_artifact_uncommissioned')
        # Only public configuration/code, never secret bind mounts, are read by this gate.
        require(path.name in ('Caddyfile', 'receiver.py'), 'compose_artifact_not_allowlisted')
        approved_file(item)
        require(sha256(path.read_bytes()) == item['sha256'], 'compose_artifact_changed')


def recorded_files(config, service, recorded):
    paths = [v['path'] for v in layout(config)]
    allowed = {','.join(paths[:n]) for n in range(2, len(paths) + 1)}
    historical = paths[:3] + [HISTORICAL_M3B]
    allowed.add(','.join(historical))
    require(recorded in allowed, 'historical_compose_inventory_unapproved')
    # A different service's history cannot be used to silently waive its own binding.
    require(config['compose_services'][service]['recorded_files'] == recorded,
            'container_compose_files_mismatch')


def runtime_identity(container):
    """Stable, non-secret Engine facts; exclude IPs, health logs and Config.Env."""
    return digest({key: container[key] for key in
                   ('command', 'entrypoint', 'restart', 'mounts', 'networks', 'ports', 'security')})


def initial_revision(config, current, repo):
    """A historical record is independently supplied, never generated from the requested SHA."""
    binding = config.get('initial_provenance', {})
    path = Path(binding.get('path', ''))
    require(path.is_absolute() and path.is_file() and not path.is_symlink()
            and path.stat().st_mode & 0o077 == 0 and path.stat().st_uid in (0, os.getuid()),
            'legacy_provenance_unverified')
    raw = path.read_bytes()
    require(sha256(raw) == binding.get('sha256'), 'legacy_provenance_unverified')
    record = json.loads(raw)
    require(record.get('kind') == 'historical-build-record' and record.get('authority')
            and record.get('image_id') == current['image'], 'initial_image_binding_mismatch')
    from contract import manifest
    previous = revision(record.get('git_commit'))
    require(record.get('source_digest') == manifest(repo, previous)['ingestion_support'],
            'legacy_provenance_unverified')
    return previous
