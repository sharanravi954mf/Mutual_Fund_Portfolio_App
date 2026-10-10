"""Owner adapters tested without Docker, hosted databases, network or real credentials."""
import copy
import json
import os
import subprocess
import tempfile
import unittest
import urllib.error
from pathlib import Path
from unittest.mock import patch

from contract import DEV_PROJECT, Rejected, load_policy, manifest
from evidence_owner import (dispatcher_measurement, function_index, measure, produce,
                            publish_release, sql_tokens, verify_files, verify_migrations, module_specifiers)
from ingestion_owner import API_COMMAND, DockerOwner, reconcile
from observe import Pending, observe, read_json
from owner_common import Command, binding, envelope, private_config
from supabase_reader import CONTROL, MIGRATIONS, SupabaseReader
from test_deployment import A, B, NOW, EXPECTED, event, frontend, policy, receipt


class WaitTests(unittest.TestCase):
    def run_observer(self, samples, head=lambda: A, front=None, is_ancestor=lambda *_: False):
        calls, pauses = [], []
        iterator = iter(samples)
        def read(url):
            calls.append(url)
            if 'backend.invalid' in url:
                value = next(iterator)
                if isinstance(value, Exception): raise value
                return value
            if 'deployment.json' in url: return front or frontend()
            return {'git_commit': A, 'healthy': True}
        result = observe(event(), 'dev', policy(), EXPECTED, head, read,
                         'https://frontend.invalid', 'https://backend.invalid', attempts=3,
                         pause=pauses.append, now=lambda: NOW, read_asset=lambda _: 'f' * 64,
                         is_ancestor=is_ancestor)
        return result, calls, pauses

    def test_delayed_receipt_and_404_converge(self):
        result, calls, pauses = self.run_observer([Pending('evidence_not_published'), Pending('transient_read_failed'), receipt()])
        self.assertEqual(result['state'], 'pass')
        self.assertEqual(pauses, [10, 10])
        self.assertTrue(all(A + '.json' in url for url in calls if 'backend.invalid' in url))

    def test_partial_components_wait(self):
        partial = receipt(); partial['components']['migrations'] = {'state': 'pending'}
        next_stage = receipt(); next_stage['components']['ingestion_support'] = {'state': 'deploying'}
        self.assertEqual(self.run_observer([partial, next_stage, receipt()])[0]['state'], 'pass')

    def test_explicit_owner_failure_is_permanent(self):
        failed = {**frontend(), 'state': 'failed', 'reason': 'backend_measurement_failed'}
        result, calls, pauses = self.run_observer([failed])
        self.assertEqual(result['reason'], 'owner_reported_failure')
        self.assertEqual(len(calls), 1); self.assertEqual(pauses, [])

    def test_partial_does_not_hide_invalid_other_component(self):
        partial = receipt(); partial['components']['migrations'] = {'state': 'pending'}
        partial['components']['edge_functions']['source_digest'] = 'wrong'
        result, _, pauses = self.run_observer([partial])
        self.assertEqual(result['reason'], 'component_unverified'); self.assertEqual(pauses, [])

    def test_permanent_evidence_failure_never_retried(self):
        for value in (Rejected('evidence_http_rejected'), {}, receipt('qa')):
            result, calls, pauses = self.run_observer([value])
            self.assertEqual(result['state'], 'failed'); self.assertEqual(len(calls), 1)
            self.assertEqual(pauses, [])

    def test_timeout_is_failure(self):
        result, _, pauses = self.run_observer([Pending('evidence_not_published')] * 3)
        self.assertEqual(result['reason'], 'deployment_timeout')
        self.assertEqual(result['environment_release'], 'not_verified')
        self.assertEqual(len(pauses), 2)

    def test_branch_advances_while_waiting(self):
        heads = iter([A, A, B])
        result, _, _ = self.run_observer([Pending('evidence_not_published')], head=lambda: next(heads))
        self.assertEqual(result['state'], 'superseded')
        self.assertNotIn('deployed', result.values())

    def test_ancestor_frontend_can_wait_but_wrong_project_cannot(self):
        old = frontend(sha=B)
        result, _, pauses = self.run_observer([receipt()] * 3, front=old, is_ancestor=lambda *_: True)
        self.assertEqual(result['reason'], 'deployment_timeout'); self.assertEqual(len(pauses), 2)
        result, _, pauses = self.run_observer([receipt()], front=frontend('qa'), is_ancestor=lambda *_: True)
        self.assertEqual(result['reason'], 'identity_mismatch'); self.assertEqual(pauses, [])

    def test_http_404_is_pending_and_401_is_rejected(self):
        for code, exception in ((404, Pending), (503, Pending), (401, Rejected), (403, Rejected)):
            with patch('observe.urllib.request.build_opener') as opener:
                opener.return_value.open.side_effect = urllib.error.HTTPError('https://fixture.invalid', code, '', {}, None)
                with self.assertRaises(exception) as caught: read_json('https://fixture.invalid')
                self.assertEqual(isinstance(caught.exception, Pending), code in (404, 503))


class SourceFixture(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name); self.repo = self.root / 'repo'; self.repo.mkdir()
        self.git('init', '-q'); self.git('config', 'user.name', 'Synthetic')
        self.git('config', 'user.email', 'synthetic@example.invalid')
        files = {
            'supabase/migrations/001_initial.sql': 'CREATE TABLE x (id int);',
            'supabase/config.toml': '[functions.outbox-dispatcher]\nverify_jwt=false\n',
            'supabase/functions/outbox-dispatcher/index.ts': 'import { value } from "../_shared/shared.ts";\nexport const result = value;\n',
            'supabase/functions/_shared/shared.ts': 'export const value = 1;\n',
            'services/ingestion-support/app/main.py': 'print("synthetic")\n',
            'services/ingestion-support/compose.yaml': 'synthetic compose',
            'services/ingestion-support/compose.hosted.yaml': 'synthetic hosted compose',
            'services/ingestion-support/Caddyfile': 'synthetic Caddyfile',
            'services/outbox-dispatcher/routes.json': json.dumps({str(i): {'worker_slug': str(i)} for i in range(17)}),
        }
        for name, content in files.items():
            path = self.repo / name; path.parent.mkdir(parents=True, exist_ok=True); path.write_text(content)
        self.sha = self.commit()
        self.p = load_policy()
        self.config = dict(environment='dev', project_ref=DEV_PROJECT, commissioned=True,
                           repository=str(self.repo), state_root=str(self.root / 'state'),
                           report_root=str(self.root / 'report'), release_status_root=str(self.root / 'release'),
                           frontend_origin='https://frontend.invalid')
        self.reader = FakeReader(self.repo)

    def git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.repo), *args], stderr=subprocess.DEVNULL).decode().strip()

    def commit(self):
        self.git('add', '.'); self.git('commit', '-qm', 'test: fixture'); return self.git('rev-parse', 'HEAD')

    def service(self, sha):
        return {**envelope('dev', self.p['dev'], sha), 'observed_at': NOW,
                'component': dict(state='deployed', healthy=True, proof='running_image',
                                  source_digest=manifest(self.repo, sha)['ingestion_support']),
                'image_id': 'sha256:' + 'a' * 64, 'image': 'registry.invalid/api@sha256:' + 'b' * 64,
                'oracle_dispatcher': 'retired'}


class FakeReader:
    def __init__(self, repo):
        self.repo = repo
        self.rows = [{'version': '001', 'statements': ['CREATE TABLE x (id int)']}]
        self.functions_rows = [dict(slug='outbox-dispatcher', id='function-id', version=2, status='ACTIVE', verify_jwt=False, ezbr_sha256='a' * 64)]
        self.control_row = dict(environment='DEV', project_ref=DEV_PROJECT,
                                project_url='https://' + DEV_PROJECT + '.supabase.co', mode='active',
                                jobs=[dict(schedule='*/15 * * * *', command='SELECT moneybowl_dispatch.notify(NULL,0);',
                                           active=True, database='postgres')])
        self.ready = dict(code='outbox_ready', environment='DEV', project_url=self.control_row['project_url'],
                          mode='active', routes={str(i): str(i) for i in range(17)})
        self.function_reads = 0

    def migrations(self): return copy.deepcopy(self.rows)
    def control(self): return copy.deepcopy(self.control_row)
    def readiness(self, env): return copy.deepcopy(self.ready)
    def functions(self):
        self.function_reads += 1
        return copy.deepcopy(self.functions_rows)
    def files(self, slug):
        root = self.repo / 'supabase/functions'
        return {p.relative_to(root).as_posix(): p.read_bytes() for p in root.rglob('*.ts')}


class EvidenceTests(SourceFixture):
    def measurement(self):
        return measure(self.repo, self.sha, 'dev', self.p, self.reader, self.service, lambda: self.sha, now=lambda: NOW)

    def test_measure_actual_content_and_publish(self):
        result = produce(self.config, self.p, self.reader, self.service, lambda: self.sha, now=lambda: NOW)
        self.assertEqual(result['state'], 'measured')
        saved = json.loads((Path(self.config['report_root']) / (self.sha + '.json')).read_text())
        self.assertEqual(saved['git_commit'], self.sha)
        self.assertTrue(all(c['state'] == 'deployed' for c in saved['components'].values()))

    def test_requested_sha_alone_cannot_manufacture_migration_proof(self):
        self.reader.rows[0]['statements'] = ['DROP TABLE x']
        with self.assertRaisesRegex(Rejected, 'applied_migration_content_mismatch'): self.measurement()

    def test_missing_migration_waits_but_missing_statements_fails(self):
        self.reader.rows = []
        self.assertEqual(self.measurement()['components']['migrations'], {'state': 'pending'})
        self.reader.rows = [{'version': '001', 'statements': None}]
        with self.assertRaisesRegex(Rejected, 'migration_statements_unavailable'): self.measurement()

    def test_extra_or_duplicate_migration_fails(self):
        for row in ({'version': '999', 'statements': ['select 1']}, self.reader.rows[0]):
            self.reader.rows.append(copy.deepcopy(row))
            with self.assertRaises(Rejected): self.measurement()
            self.reader.rows.pop()

    def test_downloaded_function_must_match_source(self):
        with patch.object(self.reader, 'files', return_value={'outbox-dispatcher/index.ts': b'wrong'}):
            with self.assertRaisesRegex(Rejected, 'deployed_function_content_mismatch'): self.measurement()

    def test_incomplete_download_cannot_certify_dependencies(self):
        data = self.reader.files('outbox-dispatcher'); del data['_shared/shared.ts']
        with patch.object(self.reader, 'files', return_value=data):
            with self.assertRaisesRegex(Rejected, 'function_dependency_unmeasured'): self.measurement()

    def test_unsafe_download_paths_fail(self):
        data = self.reader.files('outbox-dispatcher'); data['../../secret'] = b'not_read'
        with self.assertRaisesRegex(Rejected, 'unsafe_function_export_path'):
            verify_files(self.repo, 'outbox-dispatcher', data)

    def test_functions_missing_or_deploying_are_pending(self):
        self.reader.functions_rows = []
        self.assertEqual(self.measurement()['components']['edge_functions'], {'state': 'pending'})

    def test_unhealthy_function_is_not_pending(self):
        self.reader.functions_rows[0]['status'] = 'FAILED'
        with self.assertRaisesRegex(Rejected, 'function_deployment_failed'): self.measurement()

    def test_function_changes_during_measurement_fail(self):
        before = self.reader.functions()
        after = copy.deepcopy(before); after[0]['version'] += 1
        with patch.object(self.reader, 'functions', side_effect=[before, after]):
            with self.assertRaisesRegex(Rejected, 'function_measurement_changed'): self.measurement()

    def test_wrong_project_mode_cron_or_route_measurement_fail(self):
        for kind in ('project', 'mode', 'cron', 'routes'):
            self.reader = FakeReader(self.repo)
            if kind == 'project': self.reader.control_row['project_ref'] = 'a' * 20
            if kind == 'mode': self.reader.control_row['mode'] = 'disabled'
            if kind == 'cron': self.reader.control_row['jobs'].append(self.reader.control_row['jobs'][0])
            if kind == 'routes': self.reader.ready['routes'] = {}
            with self.assertRaises(Rejected): self.measurement()

    def test_unavailable_service_does_not_invent_retirement(self):
        def pending(sha): raise Pending('evidence_not_published')
        result = produce(self.config, self.p, self.reader, pending, lambda: self.sha, now=lambda: NOW)
        self.assertEqual(result['state'], 'pending')
        self.assertFalse((Path(self.config['report_root']) / (self.sha + '.json')).exists())

    def test_stale_service_measurement_fails(self):
        data = self.service(self.sha); data['observed_at'] = 0
        with self.assertRaisesRegex(Rejected, 'service_measurement_expired'):
            measure(self.repo, self.sha, 'dev', self.p, self.reader, lambda _: data, lambda: self.sha, now=lambda: NOW)

    def test_failed_remeasurement_removes_old_success(self):
        produce(self.config, self.p, self.reader, self.service, lambda: self.sha, now=lambda: NOW)
        self.reader.rows[0]['statements'] = ['select 2']
        with self.assertRaises(Rejected): produce(self.config, self.p, self.reader, self.service, lambda: self.sha, now=lambda: NOW)
        self.assertEqual(json.loads((Path(self.config['report_root']) / (self.sha + '.json')).read_text())['state'], 'failed')

    def test_new_head_never_publishes_old_receipt(self):
        heads = iter([self.sha, self.sha, B])
        result = produce(self.config, self.p, self.reader, self.service, lambda: next(heads), now=lambda: NOW)
        self.assertEqual(result['state'], 'superseded')
        self.assertFalse((Path(self.config['report_root']) / (self.sha + '.json')).exists())

    def test_sql_lexer_preserves_literals_dollar_bodies_and_token_boundaries(self):
        self.assertEqual(sql_tokens('select /* a /*b*/ c */ 1; --comment'), sql_tokens('select 1'))
        self.assertNotEqual(sql_tokens("select 'a b'"), sql_tokens("select 'ab'"))
        self.assertNotEqual(sql_tokens('select a b'), sql_tokens('select ab'))
        self.assertNotEqual(sql_tokens('DO $$ BEGIN x; END $$'), sql_tokens('DO $$BEGIN x; END$$'))
        with self.assertRaises(Rejected): sql_tokens('/*unclosed')


class FakeDocker:
    def __init__(self):
        self.live = None; self.calls = []; self.provenance = None
        self.fail_build = False; self.fail_activate = False; self.bad_health = False
        self.before = {'caddy': {'id': 'caddy-old'}, 'clamav': {'id': 'clamav-old'}}
    def infrastructure(self, source): self.calls.append('infrastructure'); return copy.deepcopy(self.before)
    def current(self): return copy.deepcopy(self.live)
    def build(self, source, sha, digest):
        self.calls.append('build')
        if self.fail_build: raise Rejected('build_failed')
        self.provenance = dict(image='registry.invalid/api@sha256:' + 'a' * 64, image_id='sha256:' + 'b' * 64,
                               git_commit=sha, source_digest=digest)
        return copy.deepcopy(self.provenance)
    def verify_image(self, provenance):
        self.calls.append('verify_image')
        if self.provenance is not None and provenance != self.provenance: raise Rejected('image_provenance_mismatch')
    def activate(self, override):
        self.calls.append('activate')
        self.live = dict(image=self.provenance['image_id'], labels={'org.opencontainers.image.revision': self.provenance['git_commit']})
        if self.fail_activate: raise Rejected('activation_failed')
    def verified(self, provenance, override):
        self.calls.append('verified')
        if self.bad_health: raise Rejected('service_unhealthy')
        if not self.live or self.live['image'] != provenance['image_id']: raise Rejected('running_image_mismatch')


class IngestionTests(SourceFixture):
    def setUp(self):
        super().setUp(); self.docker = FakeDocker()
    def run_owner(self, head=None):
        return reconcile(self.config, self.p, self.docker, self.repo, head or (lambda: self.sha), now=lambda: NOW)

    def test_build_activate_verify_and_duplicate_idempotency(self):
        self.assertEqual(self.run_owner()['state'], 'deployed')
        self.assertEqual(self.run_owner()['state'], 'deployed')
        self.assertEqual(self.docker.calls.count('build'), 1); self.assertEqual(self.docker.calls.count('activate'), 1)
        self.assertEqual(self.docker.calls.count('verified'), 2)

    def test_failed_build_never_activates(self):
        self.docker.fail_build = True
        with self.assertRaises(Rejected): self.run_owner()
        self.assertNotIn('activate', self.docker.calls); self.assertIsNone(self.docker.live)

    def test_failed_activation_is_not_retried_or_rolled_back(self):
        self.docker.fail_activate = True
        with self.assertRaises(Rejected): self.run_owner()
        self.assertEqual(self.docker.calls.count('activate'), 1)
        self.assertEqual(json.loads((Path(self.config['report_root']) / (self.sha + '.json')).read_text())['state'], 'failed')
        self.docker.fail_activate = False
        self.assertEqual(self.run_owner()['state'], 'deployed')
        self.assertEqual(self.docker.calls.count('activate'), 1)

    def test_unhealthy_service_cannot_publish(self):
        self.docker.bad_health = True
        with self.assertRaisesRegex(Rejected, 'service_unhealthy'): self.run_owner()
        self.assertEqual(json.loads((Path(self.config['report_root']) / (self.sha + '.json')).read_text())['state'], 'failed')

    def test_head_advances_during_build_does_not_activate(self):
        heads = iter([self.sha, B])
        self.assertEqual(self.run_owner(lambda: next(heads))['state'], 'superseded')
        self.assertNotIn('activate', self.docker.calls)

    def test_head_advances_after_activation_is_not_reported_deployed(self):
        heads = iter([self.sha, self.sha, B])
        self.assertEqual(self.run_owner(lambda: next(heads))['state'], 'superseded')
        self.assertFalse((Path(self.config['report_root']) / (self.sha + '.json')).exists())

    def test_force_reset_cannot_roll_back_live_service(self):
        self.run_owner()
        old = self.sha
        (self.repo / 'services/ingestion-support/app/main.py').write_text('changed')
        self.sha = self.commit(); self.run_owner()
        self.sha = old
        with self.assertRaisesRegex(Rejected, 'service_rollback_rejected'): self.run_owner()

    def test_legacy_image_needs_independent_initial_binding(self):
        self.docker.live = dict(image='sha256:' + 'f' * 64, labels={})
        with self.assertRaises(Rejected): self.run_owner()
        self.config.update(initial_revision=self.sha, initial_image_id='sha256:' + 'e' * 64)
        with self.assertRaisesRegex(Rejected, 'initial_image_binding_mismatch'): self.run_owner()

    def test_uncommissioned_owner_and_qa_never_call_docker(self):
        for env in ('dev', 'qa', 'prod'):
            config = {**self.config, 'environment': env, 'commissioned': False}
            with self.assertRaises(Rejected): reconcile(config, self.p, self.docker, self.repo, lambda: self.sha)
        self.assertEqual(self.docker.calls, [])

    def test_tampered_provenance_is_rejected(self):
        self.run_owner()
        path = Path(self.config['state_root']) / (self.sha + '.provenance.json')
        data = json.loads(path.read_text()); data['image_id'] = 'sha256:' + 'f' * 64
        path.write_text(json.dumps(data))
        with self.assertRaisesRegex(Rejected, 'image_provenance_mismatch'): self.run_owner()

    def test_concurrent_attempts_use_one_build_and_activation(self):
        from concurrent.futures import ThreadPoolExecutor
        with ThreadPoolExecutor(max_workers=3) as executor:
            results = list(executor.map(lambda _: self.run_owner(), range(3)))
        self.assertTrue(all(r['state'] == 'deployed' for r in results))
        self.assertEqual(self.docker.calls.count('build'), 1); self.assertEqual(self.docker.calls.count('activate'), 1)

    def test_complete_synthetic_sequence_to_independent_full_status(self):
        self.run_owner()
        def service_read(sha): return json.loads((Path(self.config['report_root']) / (sha + '.json')).read_text())
        config = {**self.config, 'state_root': str(self.root / 'evidence-state'), 'report_root': str(self.root / 'evidence-report')}
        produce(config, self.p, self.reader, service_read, lambda: self.sha, now=lambda: NOW)
        # Service stamp must be fresh for the production freshness check.
        import time
        service_path = Path(self.config['report_root']) / (self.sha + '.json')
        data = json.loads(service_path.read_text()); data['observed_at'] = time.time(); service_path.write_text(json.dumps(data))
        produce(config, self.p, self.reader, service_read, lambda: self.sha)
        def web(url):
            if 'deployment.json' in url: return frontend(sha=self.sha)
            return dict(git_commit=self.sha, healthy=True)
        result = publish_release(config, self.p, self.sha, lambda: self.sha, read=web, asset_reader=lambda _: 'f' * 64)
        self.assertEqual(result['state'], 'pass'); self.assertEqual(result['code_validated'], 'not_observed')


class TransportTests(unittest.TestCase):
    def test_actual_declared_source_import_graph_is_supported(self):
        import tomllib
        root = Path(__file__).resolve().parents[2]
        functions = root / 'supabase/functions'
        files = {p.relative_to(functions).as_posix(): p.read_bytes()
                 for p in functions.rglob('*') if p.is_file() and '__pycache__' not in p.parts}
        declared = tomllib.loads((root / 'supabase/config.toml').read_text())['functions']
        for slug in declared:
            verify_files(root, slug, files)

    def test_import_parser_ignores_prose_and_tracks_reexports(self):
        text = '''// import x from "not-a-module"
        const prose = "from 'not-a-module'"; db.order('effective_from', {});
        import { x } from "./local.ts"; export { x } from './other.ts';
        import "https://example.invalid/mod.ts"; const y = import("./dynamic.ts");
        '''
        self.assertEqual(module_specifiers(text), ['./local.ts', './other.ts',
                         'https://example.invalid/mod.ts', './dynamic.ts'])
        for code in ('import(name)', 'import("./a" + name)', '`x ${import(name)}`'):
            with self.assertRaisesRegex(Rejected, 'dynamic_import_unverifiable'):
                module_specifiers(code)

    def test_management_paths_queries_and_auth_scope(self):
        requests = []
        reader = SupabaseReader({'project_ref': DEV_PROJECT}, 'synthetic-token', 'k' * 32,
                                request=lambda *args: requests.append(args) or [], command=lambda *a, **k: b'')
        reader.migrations(); reader.functions()
        self.assertEqual(requests[0][0], 'https://api.supabase.com/v1/projects/' + DEV_PROJECT + '/database/query/read-only')
        self.assertEqual(requests[0][1], {'query': MIGRATIONS})
        for path, query in (('/secrets', None), ('/database/query', 'select 1'), ('/database/query/read-only', 'DELETE FROM x')):
            with self.assertRaisesRegex(Rejected, 'measurement_operation_forbidden'): reader.api(path, query)

    def test_readiness_can_only_emit_side_effect_free_kind(self):
        requests = []
        reader = SupabaseReader({'project_ref': DEV_PROJECT}, 'synthetic-token', 'k' * 32,
                                request=lambda *args: requests.append(args) or {}, command=lambda *a, **k: b'')
        reader.readiness('DEV')
        url, body, headers = requests[0]
        self.assertTrue(url.endswith('/outbox-dispatcher/readiness'))
        self.assertEqual(body['kind'], 'readiness'); self.assertIsNone(body['event_outbox_id'])
        self.assertNotIn('Authorization', headers)
        with self.assertRaises(Rejected): reader.readiness('PROD')

    def test_function_download_is_explicit_project_read_with_private_temp_output(self):
        commands = []
        def command(argv, **kwargs):
            commands.append(argv)
            root = Path(argv[argv.index('--workdir') + 1]) / 'supabase/functions/outbox-dispatcher'
            root.mkdir(parents=True); (root / 'index.ts').write_text('export const ok = true;')
            return b''
        reader = SupabaseReader({'project_ref': DEV_PROJECT}, 'synthetic-token', 'k' * 32, command=command)
        self.assertEqual(reader.files('outbox-dispatcher'), {'outbox-dispatcher/index.ts': b'export const ok = true;'})
        self.assertNotIn('synthetic-token', str(commands))
        self.assertNotIn('deploy', str(commands)); self.assertIn('--use-api', commands[0])
        with self.assertRaises(Rejected): reader.files('../other')

    def test_command_does_not_inherit_backend_secrets(self):
        with patch.dict(os.environ, {'NSE_WORKER_TOKEN': 'do-not-inherit'}):
            result = Command()(['/usr/bin/env'])
        self.assertNotIn(b'do-not-inherit', result)
        with self.assertRaisesRegex(Rejected, 'owner_command_failed'):
            Command()(['/usr/bin/false'])

    def test_config_requires_private_permissions_and_external_path(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / 'owner.json'; p.write_text(json.dumps({'repository': tmp}))
            p.chmod(0o644)
            with self.assertRaisesRegex(Rejected, 'owner_config_permissions_invalid'): private_config(p)
            p.chmod(0o600)
            with self.assertRaisesRegex(Rejected, 'owner_config_in_source'): private_config(p)

    def docker(self, command):
        return DockerOwner(dict(compose_project='moneybowl-ingestion-support', image_repository='registry.invalid/api',
                                 compose_root='/synthetic/compose', compose_env='/synthetic/private.env',
                                 docker_socket='unix:///var/run/docker.sock', retired_containers=['old-dispatcher'],
                                 retired_units=['old-dispatcher.service']), command=command)

    def test_only_api_is_selected_and_environment_is_not_printed(self):
        calls = []
        owner = self.docker(lambda argv, **kw: calls.append(argv) or b'')
        owner.activate('/synthetic/override.json')
        args = calls[0]
        self.assertEqual(args[-1], 'api'); self.assertIn('--no-deps', args); self.assertIn('--no-build', args)
        self.assertIn('--wait', args); self.assertIn('unix:///var/run/docker.sock', args)
        self.assertNotIn('--remove-orphans', args); self.assertNotIn('down', args)
        with self.assertRaises(Rejected): owner.containers('outbox-dispatcher')

    def test_untrusted_tls_is_permanent(self):
        import ssl
        with patch('observe.urllib.request.build_opener') as opener:
            opener.return_value.open.side_effect = urllib.error.URLError(ssl.SSLCertVerificationError('synthetic'))
            with self.assertRaisesRegex(Rejected, 'evidence_tls_rejected') as caught:
                read_json('https://fixture.invalid')
            self.assertNotIsInstance(caught.exception, Pending)

    def test_actual_build_measures_iid_and_registry_digest(self):
        calls = []
        image_id = 'sha256:' + 'a' * 64
        ref = 'registry.invalid/api@sha256:' + 'b' * 64
        def command(argv, **kwargs):
            calls.append(argv)
            if 'build' in argv:
                Path(argv[argv.index('--iidfile') + 1]).write_text(image_id)
            return b''
        owner = self.docker(command)
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp); context = source / 'services/ingestion-support'; context.mkdir(parents=True)
            with patch.object(owner, 'image', return_value={'id': image_id, 'digests': [ref]}):
                result = owner.build(source, A, 'c' * 64)
            self.assertEqual(result['image'], ref); self.assertEqual(result['image_id'], image_id)
            self.assertIn('org.opencontainers.image.revision=' + A, calls[0])
            self.assertEqual(calls[0][-1], str(context)); self.assertIn('push', calls[1])
            with patch.object(owner, 'image', return_value={'id': 'sha256:' + 'd' * 64, 'digests': [ref]}):
                with self.assertRaisesRegex(Rejected, 'built_image_changed'): owner.build(source, A, 'c' * 64)
            (context / '.env').write_text('SYNTHETIC_SECRET=not-a-real-secret')
            count = len(calls)
            with self.assertRaisesRegex(Rejected, 'secret_build_context_rejected'): owner.build(source, A, 'c' * 64)
            self.assertEqual(len(calls), count)

    def test_image_labels_cannot_replace_provenance(self):
        owner = self.docker(lambda *a, **k: b'')
        proof = dict(image='registry.invalid/api@sha256:' + 'a' * 64, image_id='sha256:' + 'b' * 64,
                     git_commit=A, source_digest='c' * 64)
        measured = dict(id=proof['image_id'], digests=[proof['image']], command=API_COMMAND, entrypoint=None,
                        labels={'org.opencontainers.image.revision': A, 'moneybowl.source_digest': 'c' * 64})
        for field in ('id', 'digests', 'labels', 'command'):
            bad = copy.deepcopy(measured); bad[field] = {'id': 'sha256:' + 'd' * 64, 'digests': [], 'labels': {}, 'command': API_COMMAND[:-1] + ['2']}[field]
            with patch.object(owner, 'image', return_value=bad):
                with self.assertRaisesRegex(Rejected, 'image_provenance_mismatch|single_worker_command_required'): owner.verify_image(proof)

    def test_wrong_daemon_and_infrastructure_drift_prevent_activation(self):
        owner = self.docker(lambda *a, **k: b'actual-daemon')
        owner.config['daemon_id'] = 'other-daemon'
        with self.assertRaisesRegex(Rejected, 'wrong_docker_daemon'): owner.infrastructure(Path('/synthetic'))
        owner.config['daemon_id'] = 'actual-daemon'
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp); (source / 'services/ingestion-support').mkdir(parents=True)
            (source / 'services/ingestion-support/compose.yaml').write_text('reviewed')
            owner.root = source; (source / 'compose.yaml').write_text('drift')
            with self.assertRaisesRegex(Rejected, 'infrastructure_change_requires_commissioning'): owner.infrastructure(source)

    def test_multiworker_or_wrong_container_owner_rejected(self):
        owner = self.docker(lambda *a, **k: b'one two')
        with patch.object(owner, 'containers', return_value=[{}, {}]):
            with self.assertRaisesRegex(Rejected, 'multiple_api_workers'): owner.current()
        with patch.object(owner, 'container', return_value={'labels': {'com.docker.compose.project': 'other'}}):
            with self.assertRaisesRegex(Rejected, 'container_owner_mismatch'): owner.containers('api')

    def test_config_drift_fails_even_when_same_image_is_healthy(self):
        owner = self.docker(lambda *a, **k: b''); owner.config['environment'] = 'dev'
        proof = dict(image_id='sha256:' + 'a' * 64, git_commit=A)
        current = dict(image=proof['image_id'], command=API_COMMAND, entrypoint=None, state={'Running': True, 'Health': {'Status': 'healthy'}},
                       labels={'org.opencontainers.image.revision': A, 'moneybowl.environment': 'dev',
                               'com.docker.compose.config-hash': 'wrong'})
        with patch.object(owner, 'verify_image'), patch.object(owner, 'current', return_value=current), \
             patch.object(owner, 'config_hash', return_value='correct'):
            with self.assertRaisesRegex(Rejected, 'running_configuration_drift'): owner.verified(proof, '/synthetic')

    def test_retired_container_restart_policy_and_units_are_checked(self):
        owner = self.docker(lambda argv, **kw: b'old-dispatcher\n' if '{{.Names}}' in argv else b'')
        with patch.object(owner, 'container', return_value={'state': {'Running': False}, 'restart': 'always'}):
            with self.assertRaisesRegex(Rejected, 'legacy_dispatcher_not_retired'): owner.retirement()
        def command(argv, **kw):
            if 'show' in argv: return b'LoadState=loaded\nActiveState=inactive\nUnitFileState=enabled\n'
            return b''
        owner = self.docker(command)
        with self.assertRaisesRegex(Rejected, 'legacy_restart_owner_enabled'): owner.retirement()


if __name__ == '__main__':
    unittest.main()
