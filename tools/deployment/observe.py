"""Read-only release observer. A missing owner receipt is never deployment success."""
import argparse
import hashlib
import json
import os
import re
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

from contract import Rejected, git, load_policy, manifest, push_event, require, target


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        raise Rejected('redirect_rejected')


def read_json(url):
    parsed = urllib.parse.urlsplit(url)
    require(parsed.scheme == 'https' and parsed.hostname and not parsed.username
            and not parsed.password and parsed.port is None and not parsed.fragment,
            'invalid_evidence_url')
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
    try:
        with opener.open(urllib.request.Request(url, headers={'Cache-Control': 'no-cache'}), timeout=10) as response:
            data = response.read(262145)
            require(len(data) <= 262144, 'evidence_too_large')
            return json.loads(data)
    except urllib.error.HTTPError as error:
        if error.code in (408, 429, 500, 502, 503, 504):
            raise Rejected('transient_read_failed') from None
        raise Rejected('evidence_http_rejected') from None
    except (urllib.error.URLError, TimeoutError):
        raise Rejected('transient_read_failed') from None
    except (ValueError, UnicodeError):
        raise Rejected('invalid_evidence') from None


def read_digest(url):
    parsed = urllib.parse.urlsplit(url)
    require(parsed.scheme == 'https' and parsed.hostname and not parsed.username
            and not parsed.password and parsed.port is None and not parsed.fragment,
            'invalid_evidence_url')
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
    try:
        with opener.open(urllib.request.Request(url, headers={'Cache-Control': 'no-cache'}), timeout=10) as response:
            digest = hashlib.sha256()
            total = 0
            while block := response.read(65536):
                total += len(block)
                require(total <= 64 * 1024 * 1024, 'asset_too_large')
                digest.update(block)
            return digest.hexdigest()
    except urllib.error.HTTPError as error:
        if error.code in (408, 429, 500, 502, 503, 504):
            raise Rejected('transient_read_failed') from None
        raise Rejected('evidence_http_rejected') from None
    except (urllib.error.URLError, TimeoutError):
        raise Rejected('transient_read_failed') from None


def identity(data, env, sha, policy):
    p = target(env, policy)
    require(isinstance(data, dict) and data.get('environment') == env.upper()
            and data.get('git_commit') == sha and data.get('git_branch') == p['branch']
            and data.get('supabase_project') == p['project_ref'], 'identity_mismatch')


def verify_receipt(data, env, sha, expected, policy, now):
    identity(data, env, sha, policy)
    require(data.get('schema_version') == 1, 'receipt_schema_invalid')
    observed = data.get('observed_at')
    require(type(observed) in (int, float) and 0 <= now - observed <= 300, 'receipt_expired')
    require(data.get('financial_policy') == policy[env]['financial_policy'], 'financial_policy_invalid')
    require(data.get('nse_origin') == policy[env]['nse_origin'], 'wrong_nse_origin')
    require(data.get('oracle_dispatcher') == 'retired', 'legacy_dispatcher_not_retired')
    dispatcher = data.get('dispatcher', {})
    require(dispatcher == {'mode': 'active' if env == 'dev' else 'disabled',
                           'cron_count': 1, 'cron_schedule': '*/15 * * * *',
                           'cron_active': env == 'dev', 'route_count': 17,
                           'readiness_authenticated': True}, 'dispatcher_invariants_unverified')
    components = data.get('components', {})
    require(set(components) == set(expected), 'component_inventory_mismatch')
    for name, digest in expected.items():
        item = components[name]
        require(item.get('state') == 'deployed', 'component_not_deployed')
        require(item.get('source_digest') == digest and item.get('healthy') is True, 'component_unverified')
        require(item.get('proof') == {'migrations': 'applied_history', 'edge_functions': 'downloaded_bundle',
                                     'ingestion_support': 'running_image'}[name], 'component_proof_missing')
    return True


def observe(event, env, policy, expected, latest, read, frontend_url, evidence_url,
            attempts=30, pause=time.sleep, now=time.time, read_asset=read_digest):
    report = {'schema_version': 1, 'environment': env if env in ('dev', 'qa') else 'invalid',
              'state': 'failed', 'code_validated': 'not_observed', 'deployment': 'not_observed',
              'backend': 'unknown', 'frontend': 'unknown', 'services': 'unknown',
              'post_deployment': 'not_passed', 'environment_release': 'not_verified'}
    try:
        require(env in ('dev', 'qa'), 'invalid_environment')
        # QA has no real project, so this must precede identity validation and all network access.
        require(policy[env]['deployment_enabled'] is True, 'environment_not_commissioned')
        sha = push_event(event, env, policy)
        report['git_commit'] = sha
        if latest() != sha:
            report.update(state='superseded', reason='branch_advanced')
            return report
        report['deployment'] = 'detected'
        require(frontend_url and evidence_url, 'owner_evidence_not_commissioned')
        last_error = 'deployment_timeout'
        for attempt in range(attempts):
            if latest() != sha:
                report.update(state='superseded', reason='branch_advanced')
                return report
            try:
                receipt = read(evidence_url + '?revision=' + sha)
                verify_receipt(receipt, env, sha, expected, policy, now())
                report.update(backend='deployed', services='deployed')
                front = read(frontend_url.rstrip('/') + '/deployment.json?revision=' + sha)
                identity(front, env, sha, policy)
                require(front.get('schema_version') == 1 and
                        isinstance(front.get('artifact_digest'), str) and
                        re.fullmatch(r'[0-9a-f]{64}', front['artifact_digest']) is not None, 'frontend_digest_missing')
                assets = front.get('assets', {})
                require(set(assets) == {'index.html', 'main.dart.js'}, 'frontend_assets_missing')
                for name, digest in assets.items():
                    require(isinstance(digest, str) and re.fullmatch(r'[0-9a-f]{64}', digest), 'invalid_asset_digest')
                    require(read_asset(frontend_url.rstrip('/') + '/' + name + '?revision=' + sha) == digest,
                            'served_asset_mismatch')
                report['frontend'] = 'deployed'
                health = read(frontend_url.rstrip('/') + '/release-health.json?revision=' + sha)
                require(health == {'git_commit': sha, 'healthy': True}, 'frontend_health_failed')
                if latest() != sha:
                    report.update(state='superseded', reason='branch_advanced')
                    return report
                report.update(state='pass', post_deployment='passed', environment_release='verified')
                return report
            except Rejected as error:
                last_error = str(error)
                # Retry only bounded, read-only observation, never deployment operations.
                if last_error not in ('transient_read_failed', 'identity_mismatch', 'receipt_expired'):
                    raise
                if attempt + 1 < attempts:
                    pause(10)
        raise Rejected(last_error)
    except Rejected as error:
        report['reason'] = str(error)
    except Exception:
        report['reason'] = 'malformed_or_unavailable_evidence'
    return report


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--environment', required=True)
    parser.add_argument('--event', required=True)
    parser.add_argument('--report', required=True)
    args = parser.parse_args()
    policy = load_policy()
    try:
        require(os.environ.get('M4_CI_RESULT') == 'success', 'code_validation_failed')
        event = json.loads(Path(args.event).read_text())
        sha = event.get('after', '')
        require(git('.', 'rev-parse', 'HEAD').decode().strip() == sha, 'checkout_revision_mismatch')
        expected = manifest('.', sha)
        def latest():
            branch = target(args.environment, policy)['branch']
            return git('.', 'ls-remote', '--exit-code', 'origin', 'refs/heads/' + branch).decode().split()[0]
        report = observe(event, args.environment, policy, expected, latest, read_json,
                         os.environ.get('M4_FRONTEND_ORIGIN'), os.environ.get('M4_EVIDENCE_URL'))
    except Rejected as error:
        report = {'state': 'failed', 'reason': str(error), 'environment_release': 'not_verified'}
    except Exception:
        report = {'state': 'failed', 'reason': 'invalid_event_or_source', 'environment_release': 'not_verified'}
    report['code_validated'] = 'passed' if os.environ.get('M4_CI_RESULT') == 'success' else 'failed'
    Path(args.report).write_text(json.dumps(report, sort_keys=True, indent=2) + '\n')
    print(json.dumps(report, sort_keys=True))
    return 0 if report['state'] in ('pass', 'superseded') else 1


if __name__ == '__main__':
    raise SystemExit(main())
