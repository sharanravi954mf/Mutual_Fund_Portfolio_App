"""One read-only release verification job; no resident Evidence Owner or remote writes."""
import hashlib
import json
import os
import time
import tomllib
from pathlib import Path

from contract import require
from evidence_owner import function_index, verify_files, verify_migrations
from observe import read_json
from shared_contract import decoded, encoded, public_config, request, target
from supabase_reader import SupabaseReader


def verify(source, release, host, reader, frontend, ready, fetch_asset):
    request(release)
    t = target('refs/heads/' + release['branch'])
    require(host.get('state') in ('deployed', 'already_deployed') and host.get('release') == release
            and host.get('api_id') and host.get('image_id'), 'release_host_unverified')
    require(ready == {'status': 'ready'}, 'release_api_unhealthy')
    require(frontend.get('git_commit') == release['deployment_sha']
            and frontend.get('environment') == ('PROD' if t['environment'] == 'production' else t['runtime_environment'])
            and frontend.get('git_branch') == t['branch']
            and frontend.get('supabase_project') == reader.project == release['project_ref'], 'release_frontend_mismatch')
    require((t['environment'] == 'dev') == (reader.project == 'rskryngwzyuzmiwtriyy'), 'release_project_mismatch')
    for asset in ('index.html', 'main.dart.js'):
        require(hashlib.sha256(fetch_asset(asset)).hexdigest() == frontend.get('assets', {}).get(asset),
                'release_frontend_asset_changed')
    verify_backend(source, t, reader)
    return dict(state='verified', environment=t['environment'], deployment_sha=release['deployment_sha'],
                build_sha=release['build_sha'], image=release['image'], api_id=host['api_id'],
                image_id=host['image_id'], supabase_project=reader.project, frontend_sha=frontend['git_commit'],
                observed_at=int(time.time()), nse_live_kyc='NOT_EXECUTED')


def verify_backend(source, t, reader):
    rows = reader.migrations()
    require(verify_migrations(source, rows) is True, 'release_migrations_pending')
    before = function_index(reader.functions())
    declared = tomllib.loads((source / 'supabase/config.toml').read_text())['functions']
    require(set(before) == set(declared), 'release_functions_inventory_changed')
    for slug, config in declared.items():
        require(before[slug]['status'] == 'ACTIVE' and before[slug]['verify_jwt'] is config.get('verify_jwt', True),
                'release_function_not_ready')
        verify_files(source, slug, reader.files(slug))
    require(function_index(reader.functions()) == before and reader.migrations() == rows, 'release_measurement_changed')
    control = reader.control()
    require(control.get('environment') == t['runtime_environment'] and control.get('project_ref') == reader.project
            and control.get('project_url') == 'https://' + reader.project + '.supabase.co', 'release_control_mismatch')
    readiness = reader.readiness(t['runtime_environment'])
    from evidence_owner import dispatcher_measurement
    # Existing DEV controls remain active; QA/Production financial dispatch remains disabled.
    dispatcher_measurement(source, control, readiness, 'dev' if t['environment'] == 'dev' else t['runtime_environment'].lower(),
                           {'project_ref': reader.project})
    return {'state': 'backend_ready', 'environment': t['environment'], 'supabase_project': reader.project}


def main():
    try:
        import sys
        t = target(os.environ['GITHUB_REF'])
        backend_only = sys.argv[1:] == ['backend']
        require(not sys.argv[1:] or backend_only, 'release_verify_operation_invalid')
        release = None if backend_only else decoded(Path('release.json').read_bytes())
        if release is not None:
            require(release['environment'] == t['environment'] and release['deployment_sha'] == os.environ['GITHUB_SHA'],
                    'release_identity_mismatch')
        config = {'project_ref': os.environ['SUPABASE_PROJECT_REF'], 'supabase_cli': os.environ['SUPABASE_CLI'],
                  'supabase_cli_sha256': os.environ['SUPABASE_CLI_SHA256']}
        reader = SupabaseReader(config, os.environ['SUPABASE_MEASUREMENT_TOKEN'], os.environ['OUTBOX_READINESS_KEY'])
        require(reader.project == os.environ['SUPABASE_PROJECT_REF'], 'release_project_mismatch')
        if backend_only:
            print(json.dumps(verify_backend(Path('.'), t, reader), sort_keys=True))
            return 0
        frontend_origin, api_origin = os.environ['FRONTEND_ORIGIN'], os.environ['API_ORIGIN']
        import re
        require(all(re.fullmatch(r'https://[a-z0-9]+(?:[.-][a-z0-9]+)*', v) for v in (frontend_origin, api_origin)),
                'release_origin_invalid')
        from urllib.request import ProxyHandler, build_opener, Request
        from observe import NoRedirect
        def asset(name):
            with build_opener(ProxyHandler({}), NoRedirect()).open(Request(frontend_origin + '/' + name,
                    headers={'Cache-Control': 'no-cache'}), timeout=30) as response:
                raw = response.read(32 * 1024 * 1024 + 1)
                require(len(raw) <= 32 * 1024 * 1024, 'release_asset_oversized')
                return raw
        result = verify(Path('.'), release, decoded(Path('host-result.json').read_bytes()), reader,
            read_json(frontend_origin + '/deployment.json?revision=' + release['deployment_sha']),
            read_json(api_origin + '/ready'), asset)
        Path('deployment-result.json').write_bytes(encoded(result))
        print(json.dumps(result, sort_keys=True))
        return 0
    except Exception:
        Path('deployment-result.json').write_bytes(encoded({'state': 'failed', 'reason': 'release_verification_failed'}))
        print('{"state":"failed","reason":"release_verification_failed"}')
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
