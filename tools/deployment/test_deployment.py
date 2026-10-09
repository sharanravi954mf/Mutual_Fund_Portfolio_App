"""Synthetic contracts and real filesystem/process tests; no hosted interfaces."""
import copy
import json
import multiprocessing
import os
import subprocess
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch

from contract import (DEV_PROJECT, REPOSITORY, Rejected, immutable_history, load_policy,
                      manifest, promotion, public_defines, push_event, target)
from host import digest_tree, flutter_builder, locked_deploy, run
from observe import observe, read_json

A, B, C = 'a' * 40, 'b' * 40, 'c' * 40
NOW = 1000
EXPECTED = {name: 'd' * 64 for name in ('migrations', 'edge_functions', 'ingestion_support')}


def policy():
    p = load_policy()
    # Unit-only fixture for a future private owner, never used by production entrypoints.
    p['qa'].update(project_ref='abcdefghijklmnopqrst', deployment_enabled=True)
    return p


def event(env='dev', sha=A):
    return {'repository': {'full_name': REPOSITORY}, 'ref': 'refs/heads/' + policy()[env]['branch'],
            'deleted': False, 'forced': False, 'after': sha}


def frontend(env='dev', sha=A):
    return {'schema_version': 1, 'environment': env.upper(), 'git_commit': sha,
            'git_branch': policy()[env]['branch'], 'supabase_project': policy()[env]['project_ref'],
            'artifact_digest': 'e' * 64, 'assets': {'index.html': 'f' * 64, 'main.dart.js': 'f' * 64}}


def receipt(env='dev', sha=A):
    return {**frontend(env, sha), 'observed_at': NOW,
            'financial_policy': policy()[env]['financial_policy'],
            'nse_origin': policy()[env]['nse_origin'], 'oracle_dispatcher': 'retired',
            'dispatcher': {'mode': 'active' if env == 'dev' else 'disabled', 'cron_count': 1,
                           'cron_schedule': '*/15 * * * *', 'cron_active': env == 'dev',
                           'route_count': 17, 'readiness_authenticated': True},
            'components': {name: {'state': 'deployed', 'source_digest': digest, 'healthy': True,
                                  'proof': {'migrations': 'applied_history',
                                            'edge_functions': 'downloaded_bundle',
                                            'ingestion_support': 'running_image'}[name]}
                           for name, digest in EXPECTED.items()}}


def defines(env='dev'):
    return {'SUPABASE_URL': 'https://' + policy()[env]['project_ref'] + '.supabase.co',
            'SUPABASE_ANON_KEY': 'sb_publishable_synthetic_only_0000', 'MONEYBOWL_ENV': env}


def fake_build(sha, stage):
    (stage / 'index.html').write_text('<html>synthetic</html>')
    (stage / 'main.dart.js').write_text(sha)


def concurrent_deploy(root, marker):
    def build(sha, stage):
        with open(marker, 'a') as f:
            f.write('build\n')
        time.sleep(0.05)
        fake_build(sha, stage)
    locked_deploy(Path(root), env='dev', sha=A, policy=policy(), latest=lambda: A,
                  ancestor=lambda old, new: True, build=build, config_digest='f' * 64)


class ContractTests(unittest.TestCase):
    def reject(self, function, *args):
        with self.assertRaises(Rejected):
            function(*args)

    def test_dev_push(self):
        self.assertEqual(push_event(event(), 'dev', policy()), A)

    def test_future_private_qa_push(self):
        self.assertEqual(push_event(event('qa'), 'qa', policy()), A)

    def test_feature_push_cannot_deploy(self):
        e = event(); e['ref'] = 'refs/heads/feature/example'
        self.reject(push_event, e, 'dev', policy())

    def test_production_and_wrong_environment_rejected(self):
        for env in ('prod', 'PROD', 'DEV', 'staging', 'main', ''):
            self.reject(target, env, policy())

    def test_wrong_project(self):
        p = policy(); p['dev']['project_ref'] = p['qa']['project_ref']
        self.reject(target, 'dev', p)
        p = policy(); p['qa']['project_ref'] = DEV_PROJECT
        self.reject(target, 'qa', p)

    def test_malformed_events(self):
        for key, value in [('after', '../invalid'), ('after', '0' * 40), ('deleted', True),
                           ('forced', True), ('ref', 'refs/heads/main'), ('repository', {}), ('repository', None), ('repository', [])]:
            e = event(); e[key] = value
            self.reject(push_event, e, 'dev', policy())
        self.reject(push_event, [], 'dev', policy())

    def test_valid_public_build(self):
        self.assertEqual(public_defines(defines(), 'dev', policy())['MONEYBOWL_ENV'], 'dev')
        self.assertEqual(public_defines(defines('qa'), 'qa', policy())['NSE_CONSOLE_ENABLED'], 'false')

    def test_missing_public_configuration(self):
        for key in defines():
            d = defines(); del d[key]
            self.reject(public_defines, d, 'dev', policy())

    def test_backend_secrets_rejected(self):
        for key in ('SUPABASE_SERVICE_ROLE_KEY', 'NSE_API_KEY_MEMBER', 'OUTBOX_NOTIFICATION_KEY', 'NSE_WORKER_TOKEN'):
            d = defines(); d[key] = 'synthetic_secret'
            self.reject(public_defines, d, 'dev', policy())
        d = defines(); d['SUPABASE_ANON_KEY'] = 'sb_secret_synthetic_000000'
        self.reject(public_defines, d, 'dev', policy())

    def test_service_role_jwt_rejected(self):
        import base64
        claims = base64.urlsafe_b64encode(json.dumps({'role': 'service_role', 'ref': DEV_PROJECT}).encode()).decode().rstrip('=')
        d = defines(); d['SUPABASE_ANON_KEY'] = 'e30.' + claims + '.signature'
        self.reject(public_defines, d, 'dev', policy())

    def test_qa_cannot_inherit_dev_flags_or_url(self):
        for key, value in [('MONEYBOWL_ENV', 'dev'), ('SUPABASE_URL', defines()['SUPABASE_URL']),
                           ('NSE_CONSOLE_ENABLED', 'true'), ('MONEYBOWL_DEV_ONBOARDING_PREVIEW', 'true')]:
            d = defines('qa'); d[key] = value
            self.reject(public_defines, d, 'qa', policy())

    def test_environment_origin_cannot_be_relabelled(self):
        p = policy(); p['qa']['nse_origin'] = p['dev']['nse_origin']
        self.reject(target, 'qa', p)

    def test_qa_financial_policy_disabled(self):
        p = policy(); p['qa']['financial_policy'] = 'active'
        self.reject(target, 'qa', p)

    def test_actual_qa_host_disabled_before_reading_any_configuration(self):
        with patch('host.public_defines') as read:
            self.reject(run, {'environment': 'qa'}, load_policy())
            read.assert_not_called()


class ObserverTests(unittest.TestCase):
    def check(self, env='dev', r=None, f=None, latest=lambda: A, reader=None, p=None):
        def read(url):
            if '/deployment.json' in url:
                return f if f is not None else frontend(env)
            if '/release-health.json' in url:
                return {'git_commit': A, 'healthy': True}
            return r if r is not None else receipt(env)
        return observe(event(env), env, p or policy(), EXPECTED, latest, reader or read,
                       'https://frontend.example.invalid', 'https://owner.example.invalid/receipt',
                       attempts=2, pause=lambda _: None, now=lambda: NOW, read_asset=lambda _: 'f' * 64)

    def test_complete_dev_release(self):
        self.assertEqual(self.check()['state'], 'pass')

    def test_complete_synthetic_qa_release(self):
        self.assertEqual(self.check('qa')['state'], 'pass')

    def test_qa_disabled_no_network(self):
        def no_read(url):
            self.fail('QA must not make requests')
        result = self.check('qa', p=load_policy(), reader=no_read)
        self.assertEqual(result['reason'], 'environment_not_commissioned')

    def test_outdated_sha_superseded(self):
        result = self.check(latest=lambda: B)
        self.assertEqual(result['state'], 'superseded')
        self.assertEqual(result['environment_release'], 'not_verified')

    def test_branch_moves_during_observation(self):
        heads = iter([A, A, B])
        self.assertEqual(self.check(latest=lambda: next(heads))['state'], 'superseded')

    def test_migration_failure_not_pass(self):
        r = receipt(); r['components']['migrations']['state'] = 'failed'
        self.assertEqual(self.check(r=r)['reason'], 'component_not_deployed')

    def test_unverifiable_integration(self):
        r = receipt(); del r['components']['edge_functions']['proof']
        self.assertEqual(self.check(r=r)['reason'], 'component_proof_missing')

    def test_timeout_bounded_and_sanitized(self):
        calls = []
        def fail(url):
            calls.append(url)
            raise Rejected('transient_read_failed')
        result = self.check(reader=fail)
        self.assertEqual(result['state'], 'failed')
        self.assertEqual(len(calls), 2)
        self.assertEqual(result['backend'], 'unknown')

    def test_untrusted_errors_never_logged(self):
        def fail(url):
            raise ValueError('secret_value_synthetic')
        self.assertNotIn('secret_value_synthetic', json.dumps(self.check(reader=fail)))

    def test_served_assets_must_match_release_manifest(self):
        f = frontend(); f['assets']['main.dart.js'] = 'a' * 64
        self.assertEqual(self.check(f=f)['reason'], 'served_asset_mismatch')

    def test_wrong_frontend_identity(self):
        self.assertEqual(self.check(f=frontend('qa'))['state'], 'failed')

    def test_expired_or_future_receipt(self):
        for timestamp in (0, NOW + 1):
            r = receipt(); r['observed_at'] = timestamp
            self.assertEqual(self.check(r=r)['state'], 'failed')

    def test_undeployed_service_cannot_be_omitted(self):
        r = receipt(); del r['components']['ingestion_support']
        self.assertEqual(self.check(r=r)['reason'], 'component_inventory_mismatch')

    def test_service_content_mismatch(self):
        r = receipt(); r['components']['ingestion_support']['source_digest'] = 'f' * 64
        self.assertEqual(self.check(r=r)['reason'], 'component_unverified')

    def test_dispatcher_mode_cron_and_routes_must_be_proven(self):
        for key, value in [('mode', 'disabled'), ('cron_count', 2), ('cron_schedule', '* * * * *'),
                           ('cron_active', False), ('route_count', 16), ('readiness_authenticated', False)]:
            r = receipt(); r['dispatcher'][key] = value
            self.assertEqual(self.check(r=r)['reason'], 'dispatcher_invariants_unverified')
        r = receipt('qa'); r['dispatcher']['mode'] = 'active'
        self.assertEqual(self.check('qa', r=r)['state'], 'failed')

    def test_preserve_dev_dispatcher_and_retired_oracle(self):
        for key, value in [('financial_policy', 'disabled'), ('oracle_dispatcher', 'active')]:
            r = receipt(); r[key] = value
            self.assertEqual(self.check(r=r)['state'], 'failed')

    def test_missing_commissioning_fails(self):
        result = observe(event(), 'dev', policy(), EXPECTED, lambda: A, lambda _: None, None, None)
        self.assertEqual(result['reason'], 'owner_evidence_not_commissioned')

    def test_permanent_http_errors_not_classified_as_transient(self):
        import urllib.error
        for code, reason in ((401, 'evidence_http_rejected'), (403, 'evidence_http_rejected'),
                             (503, 'transient_read_failed')):
            with patch('observe.urllib.request.build_opener') as opener:
                opener.return_value.open.side_effect = urllib.error.HTTPError('https://synthetic.invalid', code, '', {}, None)
                with self.assertRaisesRegex(Rejected, reason):
                    read_json('https://synthetic.invalid/receipt')

    def test_redirects_rejected_and_http_rejected(self):
        from observe import NoRedirect
        with self.assertRaises(Rejected):
            NoRedirect().redirect_request(None, None, None, None, None, None)
        with self.assertRaises(Rejected):
            read_json('http://localhost/private')


class HostTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name) / 'web'
        self.addCleanup(self.tmp.cleanup)

    def deploy(self, sha=A, latest=None, build=fake_build, ancestor=lambda old, new: True):
        return locked_deploy(self.root, env='dev', sha=sha, policy=policy(),
                             latest=latest or (lambda: sha), ancestor=ancestor, build=build, config_digest='f' * 64)

    def test_published_release_is_readable_by_web_server(self):
        self.deploy()
        release = (self.root / 'current').resolve()
        self.assertEqual(release.stat().st_mode & 0o777, 0o755)
        self.assertEqual((release / 'main.dart.js').stat().st_mode & 0o777, 0o644)

    def test_duplicate_webhook_safe(self):
        first = self.deploy()
        second = self.deploy(build=lambda *_: self.fail('must not rebuild immutable release'))
        self.assertEqual(first, second)
        self.assertEqual(len(list((self.root / 'releases').iterdir())), 1)

    def test_failed_build_preserves_previous(self):
        self.deploy()
        def fail(sha, stage):
            raise Rejected('flutter_build_failed')
        with self.assertRaises(Rejected):
            self.deploy(B, build=fail)
        self.assertEqual((self.root / 'current').resolve().name, A)
        self.assertFalse((self.root / 'releases' / B).exists())

    def test_rapid_merge_during_build_skips_then_deploys_latest(self):
        self.deploy()
        head = [B]
        def build(sha, stage):
            fake_build(sha, stage); head[0] = C
        result = self.deploy(B, latest=lambda: head[0], build=build)
        self.assertEqual(result['state'], 'superseded')
        self.assertEqual((self.root / 'current').resolve().name, A)
        self.deploy(C)
        self.assertEqual((self.root / 'current').resolve().name, C)

    def test_stale_before_build(self):
        self.assertEqual(self.deploy(A, latest=lambda: B)['state'], 'superseded')
        self.assertFalse((self.root / 'current').exists())

    def test_forced_rollback_rejected(self):
        self.deploy(B)
        with self.assertRaises(Rejected):
            self.deploy(A, ancestor=lambda *_: False)
        self.assertEqual((self.root / 'current').resolve().name, B)

    def test_same_revision_cannot_change_build_configuration(self):
        self.deploy()
        with self.assertRaisesRegex(Rejected, 'immutable_configuration_changed'):
            locked_deploy(self.root, env='dev', sha=A, policy=policy(), latest=lambda: A,
                          ancestor=lambda *_: True, build=fake_build, config_digest='b' * 64)

    def test_corrupt_immutable_release_fails(self):
        self.deploy()
        (self.root / 'current/main.dart.js').write_text('corrupt')
        with self.assertRaises(Rejected):
            self.deploy()

    def test_concurrent_processes_build_once_and_do_not_corrupt(self):
        marker = str(Path(self.tmp.name) / 'builds')
        processes = [multiprocessing.Process(target=concurrent_deploy, args=(str(self.root), marker)) for _ in range(3)]
        for process in processes:
            process.start()
        for process in processes:
            process.join(5)
            self.assertEqual(process.exitcode, 0)
        self.assertEqual(Path(marker).read_text(), 'build\n')
        self.assertEqual((self.root / 'current').resolve().name, A)

    def test_symlink_artifacts_rejected(self):
        def build(sha, stage):
            fake_build(sha, stage)
            (stage / 'bad').symlink_to('/etc/passwd')
        with self.assertRaises(Rejected):
            self.deploy(build=build)

    def test_build_process_does_not_inherit_backend_secrets(self):
        # Actual executable captures only its environment into a synthetic JS bundle.
        repo = Path(self.tmp.name) / 'repo'; repo.mkdir()
        subprocess.run(['git', 'init', '-q', str(repo)], check=True)
        (repo / 'pubspec.yaml').write_text('name: synthetic')
        subprocess.run(['git', '-C', str(repo), 'add', '.'], check=True)
        subprocess.run(['git', '-C', str(repo), '-c', 'user.name=Test', '-c', 'user.email=test@example.invalid',
                        'commit', '-qm', 'test: fixture'], check=True)
        sha = subprocess.check_output(['git', '-C', str(repo), 'rev-parse', 'HEAD']).decode().strip()
        flutter = Path(self.tmp.name) / 'flutter'
        flutter.write_text('#!/usr/bin/python3\nimport os,pathlib\np=pathlib.Path("build/web"); p.mkdir(parents=True,exist_ok=True)\n(p/"index.html").write_text("ok")\n(p/"main.dart.js").write_text(str(dict(os.environ)))\n')
        flutter.chmod(0o755)
        stage = Path(self.tmp.name) / 'stage'; stage.mkdir()
        with patch.dict(os.environ, {'NSE_WORKER_TOKEN': 'synthetic_backend_secret', 'DART_DEFINES': 'bad'}):
            flutter_builder(repo, flutter, defines())(sha, stage)
        self.assertNotIn('synthetic_backend_secret', (stage / 'main.dart.js').read_text())
        self.assertNotIn('DART_DEFINES', (stage / 'main.dart.js').read_text())


class GitPromotionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.repo = Path(self.tmp.name)
        self.git('init', '-q')
        self.git('config', 'user.name', 'Synthetic')
        self.git('config', 'user.email', 'synthetic@example.invalid')
        (self.repo / 'supabase/migrations').mkdir(parents=True)
        (self.repo / 'supabase/migrations/001.sql').write_text('select 1;')
        self.base = self.commit()
        (self.repo / 'feature.txt').write_text('feature')
        self.head = self.commit()
        self.git('update-ref', 'refs/remotes/origin/develop', self.head)

    def git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.repo), *args], stderr=subprocess.DEVNULL).decode().strip()

    def commit(self):
        self.git('add', '.'); self.git('commit', '-qm', 'test: synthetic')
        return self.git('rev-parse', 'HEAD')

    def pr(self, base='develop', head='feature/test'):
        return {'pull_request': {'base': {'ref': base, 'sha': self.base},
                                'head': {'ref': head, 'sha': self.head, 'repo': {'full_name': REPOSITORY}}}}

    def test_feature_pr_to_develop(self):
        self.assertEqual(promotion(self.repo, self.pr()), self.head)

    def test_develop_to_qa_reviewed_source(self):
        self.assertEqual(promotion(self.repo, self.pr('qa', 'develop')), self.head)

    def test_direct_feature_to_qa_rejected(self):
        with self.assertRaises(Rejected):
            promotion(self.repo, self.pr('qa'))

    def test_qa_merge_cannot_include_unreviewed_changes(self):
        (self.repo / 'unreviewed').write_text('extra'); self.commit()
        with self.assertRaises(Rejected):
            promotion(self.repo, self.pr('qa', 'develop'))

    def test_applied_migration_rewrite_rejected(self):
        (self.repo / 'supabase/migrations/001.sql').write_text('select 2;')
        with self.assertRaises(Rejected):
            immutable_history(self.repo, self.base, self.commit())

    def test_additive_migration_allowed(self):
        (self.repo / 'supabase/migrations/002.sql').write_text('select 2;')
        immutable_history(self.repo, self.base, self.commit())


class WorkflowSafetyTests(unittest.TestCase):
    def test_shared_workflow_no_private_secrets_or_production_target(self):
        root = Path(__file__).resolve().parents[2]
        workflow = (root / '.github/workflows/environment-promotion.yml').read_text()
        for forbidden in ('secrets.', 'self-hosted', 'pull_request_target', 'supabase db push',
                          'supabase functions deploy', 'branches: [main', 'commissioning/controller.py'):
            self.assertNotIn(forbidden, workflow)
        self.assertIn("branches: ['feature/**', develop, qa]", workflow)
        self.assertIn('branches: [develop, qa]', workflow)
        self.assertIn('cancel-in-progress: false', workflow)
        self.assertNotIn('paths:', workflow)

    def test_no_dispatcher_mutation_in_deployment_tools(self):
        for name in ('host.py', 'observe.py', 'ci.py'):
            source = Path(__file__).with_name(name).read_text()
            for forbidden in ('controller.py', 'bootstrap', 'notify(', 'systemctl', 'docker compose',
                              'service_role', 'MONEYBOWL_COMMISSION_TOKEN'):
                self.assertNotIn(forbidden, source)


class FunctionInventoryTests(unittest.TestCase):
    def test_integration_inventory_excludes_retired_artifacts(self):
        from edge_entries import entrypoints
        entries = entrypoints(Path(__file__).resolve().parents[2])
        self.assertIn('outbox-dispatcher', ' '.join(entries))
        self.assertNotIn('update-excel-metadata', ' '.join(entries))
        self.assertEqual(len(entries), 20)

    def test_missing_declared_function_fails(self):
        from edge_entries import entrypoints
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); (root / 'supabase').mkdir()
            (root / 'supabase/config.toml').write_text('[functions.missing]\nverify_jwt=false\n')
            with self.assertRaises(ValueError):
                entrypoints(root)


class ServiceManifestTests(unittest.TestCase):
    def test_only_existing_api_single_replica_is_selected(self):
        from service_manifest import service_manifest
        result = service_manifest('dev', A, 'registry.example.invalid/ingestion@sha256:' + 'e' * 64, policy())
        self.assertEqual(set(result['services']), {'api'})
        self.assertEqual(result['services']['api']['scale'], 1)

    def test_mutable_image_and_uncommissioned_qa_and_prod_denied(self):
        from service_manifest import service_manifest
        for env, image, p in [('dev', 'image:latest', policy()),
                              ('qa', 'registry.invalid/image@sha256:' + 'a' * 64, load_policy()),
                              ('prod', 'registry.invalid/image@sha256:' + 'a' * 64, policy())]:
            with self.assertRaises(Rejected):
                service_manifest(env, A, image, p)


if __name__ == '__main__':
    unittest.main()
