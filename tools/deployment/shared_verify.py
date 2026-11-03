"""Bounded read-only convergence; existing Supabase/Flutter owners remain the only writers."""
import hashlib
import json
import math
import os
import re
import sys
import time
import tomllib
from pathlib import Path

from contract import DEV_PROJECT, Rejected, git, require, revision
from evidence_owner import dispatcher_measurement, function_index, verify_files, verify_migrations
from observe import NoRedirect, Pending, read_json
from shared_contract import decoded, encoded, push, request, target
from shared_release import Github
from supabase_reader import SupabaseReader

WAIT_SECONDS = 15 * 60
POLL_SECONDS = 10
MAX_ATTEMPTS = 91
PENDING_REASONS = frozenset({
    'release_migrations_pending', 'release_functions_pending', 'release_function_configuration_pending',
    'release_function_content_pending', 'release_measurement_pending', 'release_frontend_pending',
    'measurement_unavailable', 'measurement_deadline_exceeded', 'transient_read_failed',
    'evidence_not_published', 'release_asset_pending',
})


class ConvergenceTimeout(Rejected):
    def __init__(self, last_pending, attempts):
        super().__init__('release_convergence_timeout')
        self.last_pending = last_pending if last_pending in PENDING_REASONS else 'measurement_unavailable'
        self.attempts = attempts


def remaining_timeout(deadline, maximum, clock=None):
    clock = clock or time.monotonic
    remaining = deadline - clock()
    if remaining <= 0:
        raise Pending('measurement_deadline_exceeded')
    return min(maximum, remaining)


def converge(measure, ensure_current, *, deadline, clock=None, sleep=None,
             interval=POLL_SECONDS, max_attempts=MAX_ATTEMPTS):
    """Only known pending reads repeat. A mutation callback is never supplied here."""
    clock, sleep = clock or time.monotonic, sleep or time.sleep
    require(math.isfinite(deadline) and 0 < interval <= POLL_SECONDS
            and type(max_attempts) is int and 0 < max_attempts <= MAX_ATTEMPTS, 'release_wait_limits_invalid')
    last_pending, attempts = 'measurement_unavailable', 0

    def guard():
        if clock() >= deadline:
            raise ConvergenceTimeout(last_pending, attempts)
        try:
            ensure_current()
        except Rejected:
            if clock() >= deadline:
                raise ConvergenceTimeout(last_pending, attempts) from None
            raise
        if clock() >= deadline:
            raise ConvergenceTimeout(last_pending, attempts)

    for _ in range(max_attempts):
        guard()
        attempts += 1
        try:
            result = measure()
        except Pending as error:
            # Unknown/unsafe failures are never silently converted to propagation.
            require(str(error) in PENDING_REASONS, 'release_pending_reason_invalid')
            last_pending = str(error)
        except Rejected:
            if clock() >= deadline:
                raise ConvergenceTimeout(last_pending, attempts) from None
            raise
        else:
            guard()  # Includes supersession during the final in-flight measurement.
            return result
        guard()
        if attempts == max_attempts:
            break
        sleep(min(interval, max(0, deadline - clock())))
    raise ConvergenceTimeout(last_pending, attempts)


def verify(source, release, host, reader, frontend, ready, fetch_asset, *, ancestor=None):
    request(release)
    t = target('refs/heads/' + release['branch'])
    require(host.get('state') in ('deployed', 'already_deployed') and host.get('release') == release
            and host.get('api_id') and host.get('image_id'), 'release_host_unverified')
    require(ready == {'status': 'ready'}, 'release_api_unhealthy')
    # Check target identity before considering a lagging SHA to be convergence.
    require(frontend.get('environment') == t['runtime_environment']
            and frontend.get('git_branch') == t['branch']
            and frontend.get('supabase_project') == reader.project == release['project_ref'], 'release_frontend_mismatch')
    require((t['environment'] == 'dev') == (reader.project == DEV_PROJECT), 'release_project_mismatch')
    observed = revision(frontend.get('git_commit'))
    if observed != release['deployment_sha']:
        require(ancestor is not None and ancestor(observed, release['deployment_sha']), 'release_frontend_source_invalid')
        raise Pending('release_frontend_pending')
    for asset in ('index.html', 'main.dart.js'):
        require(hashlib.sha256(fetch_asset(asset)).hexdigest() == frontend.get('assets', {}).get(asset),
                'release_frontend_asset_changed')
    verify_backend(source, t, reader)
    return dict(state='verified', environment=t['environment'], deployment_sha=release['deployment_sha'],
                build_sha=release['build_sha'], image=release['image'], api_id=host['api_id'],
                image_id=host['image_id'], supabase_project=reader.project, frontend_sha=frontend['git_commit'],
                observed_at=int(time.time()), nse_live_kyc='NOT_EXECUTED')


def verify_backend(source, t, reader):
    require((t['environment'] == 'dev') == (reader.project == DEV_PROJECT), 'release_project_mismatch')
    control = reader.control()
    require(control.get('environment') == t['runtime_environment'] and control.get('project_ref') == reader.project
            and control.get('project_url') == 'https://' + reader.project + '.supabase.co', 'release_control_mismatch')
    readiness = reader.readiness(t['runtime_environment'])
    # Provider readiness is authenticated and returns before any RPC/worker admission.
    # SQL and Edge modes must still both be disabled outside DEV, including PROD.
    dispatcher_measurement(source, control, readiness, 'dev' if t['environment'] == 'dev' else t['runtime_environment'].lower(),
                           {'project_ref': reader.project}, allow_inert_no_cron=t['environment'] != 'dev')
    rows = reader.migrations()
    if not verify_migrations(source, rows):
        raise Pending('release_migrations_pending')
    before = function_index(reader.functions())
    declared = tomllib.loads((source / 'supabase/config.toml').read_text())['functions']
    require(not (set(before) - set(declared)), 'release_functions_inventory_changed')
    if set(before) != set(declared):
        raise Pending('release_functions_pending')
    for slug, config in declared.items():
        require(before[slug]['status'] in ('ACTIVE', 'DEPLOYING'), 'release_function_failed')
        if before[slug]['status'] == 'DEPLOYING':
            raise Pending('release_functions_pending')
        if before[slug]['verify_jwt'] is not config.get('verify_jwt', True):
            raise Pending('release_function_configuration_pending')
        files = reader.files(slug)
        try:
            verify_files(source, slug, files)
        except Rejected as error:
            if str(error) in ('deployed_function_content_mismatch', 'function_dependency_unmeasured'):
                raise Pending('release_function_content_pending') from None
            raise
    if (function_index(reader.functions()) != before or reader.migrations() != rows
            or reader.control() != control or reader.readiness(t['runtime_environment']) != readiness):
        raise Pending('release_measurement_pending')
    return {'state': 'backend_ready', 'environment': t['environment'], 'supabase_project': reader.project}


def context(t, expected, sha, project):
    require(expected.get('deployment_sha') == revision(sha) and expected.get('environment') == t['environment']
            and expected.get('branch') == t['branch'] and expected.get('project_ref') == project,
            'release_identity_mismatch')
    require((t['environment'] == 'dev') == (project == DEV_PROJECT), 'release_project_mismatch')


def current_head(api, t, sha, deadline):
    value = api('/git/ref/heads/' + t['branch'], timeout=remaining_timeout(deadline, 30))
    require(value.get('object', {}).get('sha') == sha, 'release_superseded')


def failure_result(error, phase, t, sha):
    code = str(error)
    if not re.fullmatch(r'(?:release|readiness|measurement|github|dispatcher|recovery|applied|unexpected|function|deployed|invalid|evidence)_[a-z0-9_]{1,80}', code):
        code = 'release_verification_failed'
    result = dict(state='failed', reason=code, phase=phase, environment=t['environment'], deployment_sha=sha)
    if isinstance(error, ConvergenceTimeout):
        result.update(last_pending_reason=error.last_pending, attempts=error.attempts)
    return result


def main():
    phase, t, sha = 'release', {'environment': 'unknown'}, 'unknown'
    try:
        backend_only = sys.argv[1:] == ['backend']
        require(not sys.argv[1:] or backend_only, 'release_verify_operation_invalid')
        phase = 'backend' if backend_only else 'release'
        sha = revision(os.environ['GITHUB_SHA'])
        event = decoded(Path(os.environ['GITHUB_EVENT_PATH']).read_bytes())
        t = push(os.environ['GITHUB_EVENT_NAME'], event, os.environ['GITHUB_REF'], sha)
        require(git('.', 'rev-parse', 'HEAD').decode().strip() == sha, 'release_checkout_mismatch')
        expected = decoded(Path('admission.json' if backend_only else 'release.json').read_bytes())
        context(t, expected, sha, os.environ['SUPABASE_PROJECT_REF'])
        if not backend_only:
            request(expected)
        deadline = time.monotonic() + WAIT_SECONDS
        api = Github(os.environ['GH_TOKEN'])
        ensure_current = lambda: current_head(api, t, sha, deadline)
        config = {'project_ref': expected['project_ref'], 'supabase_cli': os.environ['SUPABASE_CLI'],
                  'supabase_cli_sha256': os.environ['SUPABASE_CLI_SHA256']}
        reader = SupabaseReader(config, os.environ['SUPABASE_MEASUREMENT_TOKEN'], os.environ['OUTBOX_READINESS_KEY'],
                                deadline=deadline)
        if backend_only:
            measure = lambda: verify_backend(Path('.'), t, reader)
        else:
            host = decoded(Path('host-result.json').read_bytes())
            frontend_origin, api_origin = os.environ['FRONTEND_ORIGIN'], os.environ['API_ORIGIN']
            require(all(re.fullmatch(r'https://[a-z0-9]+(?:[.-][a-z0-9]+)*', v) for v in (frontend_origin, api_origin)),
                    'release_origin_invalid')
            from urllib.request import ProxyHandler, build_opener, Request
            def asset(name):
                with build_opener(ProxyHandler({}), NoRedirect()).open(Request(frontend_origin + '/' + name,
                        headers={'Cache-Control': 'no-cache'}), timeout=remaining_timeout(deadline, 30)) as response:
                    raw = response.read(32 * 1024 * 1024 + 1)
                    require(len(raw) <= 32 * 1024 * 1024, 'release_asset_oversized')
                    return raw
            def ancestor(old, new):
                try:
                    git('.', 'merge-base', '--is-ancestor', old, new, timeout=remaining_timeout(deadline, 120))
                    return True
                except Rejected:
                    return False
            def measure():
                frontend = read_json(frontend_origin + '/deployment.json?revision=' + sha,
                                     timeout=remaining_timeout(deadline, 10))
                ready = read_json(api_origin + '/ready', timeout=remaining_timeout(deadline, 10))
                return verify(Path('.'), expected, host, reader, frontend, ready, asset, ancestor=ancestor)
        result = converge(measure, ensure_current, deadline=deadline)
        result.update(deployment_sha=sha, phase=phase)
        Path('backend-result.json' if backend_only else 'deployment-result.json').write_bytes(encoded(result))
        print(json.dumps(result, sort_keys=True))
        return 0
    except Exception as error:
        result = failure_result(error, phase, t, sha)
        Path('backend-result.json' if phase == 'backend' else 'deployment-result.json').write_bytes(encoded(result))
        print(json.dumps(result, sort_keys=True))
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
