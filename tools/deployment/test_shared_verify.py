"""Real reader/verifier code with deterministic provider/CLI fixtures; no live calls."""
import copy
import contextlib
import hashlib
import hmac
import io
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from contract import DEV_PROJECT, Rejected
from observe import Pending
from shared_contract import IMAGE, INFRASTRUCTURE, OWNER_ID, REPOSITORY, REPOSITORY_ID, encoded, target
from shared_release import make_request
from shared_verify import (ConvergenceTimeout, context, converge, current_head, failure_result,
                           remaining_timeout, verify, verify_backend)
from supabase_reader import CONTROL, MIGRATIONS, SupabaseReader

A, B, C = 'a' * 40, 'b' * 40, 'c' * 40
PROJECTS = {'develop': DEV_PROJECT, 'qa': 'abcdefghijklmnopqrst', 'main': 'bcdefghijklmnopqrstu'}


class Clock:
    def __init__(self):
        self.now, self.sleeps = 0, []
        self.after_sleep = lambda: None

    def __call__(self):
        return self.now

    def sleep(self, seconds):
        self.sleeps.append(seconds)
        self.now += seconds
        self.after_sleep()


class Fixture:
    def __init__(self, source, branch='develop', clock=None):
        self.source, self.t = source, target('refs/heads/' + branch)
        self.project = PROJECTS[branch]
        self.mode = 'active' if branch == 'develop' else 'disabled'
        self.key = 'synthetic-readiness-only-' * 3
        self.calls, self.commands = [], []
        self.rows = [{'version': '20260101000000', 'statements': ['SELECT 1;']}]
        self.functions = [{'slug': 'synthetic', 'id': 'synthetic', 'version': 1,
                           'status': 'ACTIVE', 'verify_jwt': True}]
        self.export = b'export const synthetic = 1;\n'
        self.jobs = [self.job(True)] if branch == 'develop' else []
        self.control_env = self.t['runtime_environment']
        self.reader = SupabaseReader({'project_ref': self.project}, 'synthetic-read-token', self.key,
            request=self.transport, command=self.download, clock=clock or Clock())
        self.release = make_request(dict(self.t, deployment_sha=B, project_ref=self.project,
            component_digest='d' * 64, infrastructure={p: 'e' * 64 for p in INFRASTRUCTURE}), A,
            IMAGE + '@sha256:' + 'f' * 64, 123, 1000)
        self.host = dict(state='deployed', release=self.release, api_id='synthetic-api', image_id='sha256:synthetic')
        self.asset = b'synthetic compiled frontend'
        self.frontend = dict(git_commit=B, environment=self.t['runtime_environment'], git_branch=branch,
            supabase_project=self.project, assets={p: hashlib.sha256(self.asset).hexdigest()
                                                   for p in ('index.html', 'main.dart.js')})

    @staticmethod
    def job(active):
        return dict(schedule='*/15 * * * *', command='SELECT moneybowl_dispatch.notify(NULL,0);',
                    active=active, database='postgres')

    def transport(self, url, body=None, headers=None):
        self.calls.append((url, copy.deepcopy(body), dict(headers or {})))
        base = 'https://api.supabase.com/v1/projects/' + self.project
        if url == base + '/database/query/read-only':
            assert body['query'] in (CONTROL, MIGRATIONS), 'only fixed SELECT measurements are authorized'
            if body['query'] == MIGRATIONS:
                return copy.deepcopy(self.rows)
            return [dict(environment=self.control_env, project_ref=self.project,
                         project_url='https://' + self.project + '.supabase.co', mode=self.mode, jobs=copy.deepcopy(self.jobs))]
        if url == base + '/functions':
            assert body is None
            return copy.deepcopy(self.functions)
        assert url == 'https://' + self.project + '.supabase.co/functions/v1/outbox-dispatcher/readiness'
        assert body['environment'] == self.t['runtime_environment']
        assert body['kind'] == 'readiness' and body['event_outbox_id'] is None and body['hop'] == 0
        assert body['project_url'] == 'https://' + self.project + '.supabase.co'
        message = 'moneybowl-readiness-v1|' + '|'.join(str(body[p]) for p in
            ('version', 'request_id', 'issued_at', 'environment', 'project_url', 'kind')) + '|-|0'
        assert headers == {'Content-Type': 'application/json', 'x-outbox-readiness-signature':
                           hmac.new(self.key.encode(), message.encode(), hashlib.sha256).hexdigest()}
        return dict(code='outbox_ready', mode=self.mode, environment=self.t['runtime_environment'],
                    project_url=body['project_url'], routes={str(i): 'synthetic' for i in range(17)})

    def download(self, argv, **kwargs):
        self.commands.append((argv, kwargs))
        assert argv[:4] == ['/opt/supabase', 'functions', 'download', 'synthetic']
        assert argv[argv.index('--project-ref') + 1] == self.project and '--use-api' in argv
        assert kwargs['timeout'] <= 120
        path = Path(argv[argv.index('--workdir') + 1]) / 'supabase/functions/synthetic/index.ts'
        path.parent.mkdir(parents=True)
        path.write_bytes(self.export)
        return b''

    def backend(self):
        return verify_backend(self.source, self.t, self.reader)

    def full(self):
        return verify(self.source, self.release, self.host, self.reader, self.frontend, {'status': 'ready'},
                      lambda _: self.asset, ancestor=lambda old, new: old == A and new == B)


class VerificationTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.source = Path(self.tmp.name)
        for name in ('supabase/migrations', 'supabase/functions/synthetic', 'services/outbox-dispatcher'):
            (self.source / name).mkdir(parents=True)
        (self.source / 'supabase/migrations/20260101000000_synthetic.sql').write_text('SELECT 1;')
        (self.source / 'supabase/functions/synthetic/index.ts').write_bytes(b'export const synthetic = 1;\n')
        (self.source / 'supabase/config.toml').write_text('[functions.synthetic]\nverify_jwt = true\n')
        (self.source / 'services/outbox-dispatcher/routes.json').write_bytes(
            encoded({str(i): {'worker_slug': 'synthetic'} for i in range(17)}))

    def test_full_dev_qa_production_use_real_reader_and_readiness_protocol(self):
        for branch in PROJECTS:
            with self.subTest(branch=branch):
                f = Fixture(self.source, branch)
                self.assertEqual(f.backend()['state'], 'backend_ready')
                result = f.full()
                self.assertEqual(result['state'], 'verified')
                self.assertEqual(result['deployment_sha'], B)
                self.assertEqual(result['supabase_project'], PROJECTS[branch])
                self.assertEqual(result['nse_live_kyc'], 'NOT_EXECUTED')
                self.assertTrue(f.commands)
                self.assertTrue(all('/database/query/read-only' in url or url.endswith('/functions')
                                    or url.endswith('/outbox-dispatcher/readiness') for url, _, _ in f.calls))

    def test_nondev_allows_actual_inert_absence_or_one_disabled_recovery_job(self):
        for branch in ('qa', 'main'):
            for jobs in ([], [Fixture.job(False)]):
                with self.subTest(branch=branch, jobs=jobs):
                    f = Fixture(self.source, branch)
                    f.jobs = jobs
                    self.assertEqual(f.full()['state'], 'verified')

    def test_financial_activation_is_rejected_outside_dev(self):
        for branch in ('qa', 'main'):
            for change in ('mode', 'cron'):
                with self.subTest(branch=branch, change=change):
                    f = Fixture(self.source, branch)
                    if change == 'mode':
                        f.mode = 'active'
                    else:
                        f.jobs = [Fixture.job(True)]
                    with self.assertRaises(Rejected):
                        f.backend()
                    self.assertEqual(f.commands, [])

    def test_dev_still_requires_the_existing_active_recovery_contract(self):
        f = Fixture(self.source)
        f.jobs = []
        with self.assertRaises(Rejected):
            f.backend()

    def test_cross_environment_is_rejected_before_convergence(self):
        for branch in PROJECTS:
            with self.subTest(branch=branch):
                f = Fixture(self.source, branch)
                f.frontend['supabase_project'] = 'zzzzzzzzzzzzzzzzzzzz'
                with self.assertRaisesRegex(Rejected, 'release_frontend_mismatch'):
                    f.full()
                self.assertFalse(f.calls)
                f.frontend['supabase_project'] = f.project
                f.control_env = 'QA' if branch != 'qa' else 'PROD'
                with self.assertRaisesRegex(Rejected, 'release_control_mismatch'):
                    f.backend()

    def test_readiness_project_binding_rejects_dev_token_target_used_as_prod(self):
        f = Fixture(self.source)
        with self.assertRaisesRegex(Rejected, 'readiness_project_mismatch'):
            f.reader.readiness('PROD')
        self.assertFalse(f.calls)

    def test_backend_converges_from_missing_migration_and_old_function_bytes(self):
        f, clock = Fixture(self.source, 'main'), Clock()
        desired = copy.deepcopy(f.rows)
        f.rows = []
        def progress():
            f.rows = desired
            f.export = b'export const old = 1;\n' if len(clock.sleeps) == 1 else b'export const synthetic = 1;\n'
        clock.after_sleep = progress
        guards = []
        result = converge(f.backend, lambda: guards.append(B), deadline=40, clock=clock, sleep=clock.sleep)
        self.assertEqual(result['state'], 'backend_ready')
        self.assertEqual(clock.sleeps, [10, 10])
        self.assertGreaterEqual(len(guards), 4)

    def test_known_deployment_status_and_configuration_can_converge(self):
        for transition in ('missing', 'deploying', 'jwt'):
            with self.subTest(transition=transition):
                f, clock = Fixture(self.source, 'qa'), Clock()
                desired = copy.deepcopy(f.functions)
                if transition == 'missing':
                    f.functions = []
                elif transition == 'deploying':
                    f.functions[0]['status'] = 'DEPLOYING'
                else:
                    f.functions[0]['verify_jwt'] = False
                clock.after_sleep = lambda: setattr(f, 'functions', desired)
                self.assertEqual(converge(f.backend, lambda: None, deadline=20, clock=clock, sleep=clock.sleep)['state'], 'backend_ready')
                self.assertEqual(clock.sleeps, [10])

    def test_flutter_converges_only_from_an_ancestor_to_the_exact_sha(self):
        f, clock = Fixture(self.source, 'main'), Clock()
        f.frontend['git_commit'] = A
        clock.after_sleep = lambda: f.frontend.update(git_commit=B)
        result = converge(f.full, lambda: None, deadline=20, clock=clock, sleep=clock.sleep)
        self.assertEqual(result['frontend_sha'], B)
        self.assertEqual(clock.sleeps, [10])

    def test_future_or_unknown_frontend_source_is_terminal(self):
        f, clock = Fixture(self.source, 'qa'), Clock()
        f.frontend['git_commit'] = C
        with self.assertRaisesRegex(Rejected, 'release_frontend_source_invalid'):
            converge(f.full, lambda: None, deadline=20, clock=clock, sleep=clock.sleep)
        self.assertFalse(clock.sleeps)

    def test_corrupt_artifact_or_health_is_never_waited_into_success(self):
        for change in ('asset', 'receipt', 'health'):
            with self.subTest(change=change):
                f, clock = Fixture(self.source), Clock()
                if change == 'asset':
                    f.asset = b'changed'
                elif change == 'receipt':
                    f.host['release'] = dict(f.release, deployment_sha=C)
                def measure():
                    return verify(f.source, f.release, f.host, f.reader, f.frontend,
                                  {'status': 'unhealthy'} if change == 'health' else {'status': 'ready'}, lambda _: f.asset)
                with self.assertRaises(Rejected):
                    converge(measure, lambda: None, deadline=20, clock=clock, sleep=clock.sleep)
                self.assertFalse(clock.sleeps)

    def test_failed_function_unexpected_migration_or_denied_credential_is_terminal(self):
        for change in ('function', 'migration', 'credential'):
            with self.subTest(change=change):
                f, clock = Fixture(self.source), Clock()
                if change == 'function':
                    f.functions[0]['status'] = 'FAILED'
                elif change == 'migration':
                    f.rows.append({'version': '20990101000000', 'statements': ['SELECT 1;']})
                else:
                    f.reader.request = lambda *_: (_ for _ in ()).throw(Rejected('measurement_http_rejected'))
                with self.assertRaises(Rejected):
                    converge(f.backend, lambda: None, deadline=20, clock=clock, sleep=clock.sleep)
                self.assertFalse(clock.sleeps)

    def test_reader_bounds_all_http_and_cli_calls_to_remaining_budget(self):
        f, clock = Fixture(self.source), Clock()
        f.reader.clock, f.reader.deadline = clock, 2
        f.reader.files('synthetic')
        self.assertEqual(f.commands[0][1]['timeout'], 2)
        clock.now = 2
        with self.assertRaises(Pending):
            f.reader.control()
        self.assertFalse(f.calls)

    def test_expired_in_flight_provider_read_cannot_return_success(self):
        f, clock = Fixture(self.source), Clock()
        f.reader.clock, f.reader.deadline = clock, 2
        transport = f.reader.request
        def slow(*args):
            value = transport(*args)
            clock.now = 3
            return value
        f.reader.request = slow
        with self.assertRaises(ConvergenceTimeout):
            converge(f.backend, lambda: None, deadline=2, clock=clock, sleep=clock.sleep)
        self.assertEqual(len(f.calls), 1)
        self.assertFalse(clock.sleeps)

    def run_cli(self, f, *, backend=False, delayed_frontend=False):
        from shared_verify import main
        event = dict(repository=dict(id=REPOSITORY_ID, full_name=REPOSITORY, owner={'id': OWNER_ID}, fork=False),
                     ref='refs/heads/' + f.t['branch'], before=A, after=B, forced=False, deleted=False)
        (self.source / 'event.json').write_bytes(encoded(event))
        (self.source / 'release.json').write_bytes(encoded(f.release))
        (self.source / 'admission.json').write_bytes(encoded(dict(f.t, project_ref=f.project, deployment_sha=B)))
        (self.source / 'host-result.json').write_bytes(encoded(f.host))
        clock, heads = Clock(), []
        f.reader.clock = clock
        if delayed_frontend:
            f.frontend['git_commit'] = A
            clock.after_sleep = lambda: f.frontend.update(git_commit=B)
        def api(path, **kwargs):
            heads.append((path, kwargs))
            self.assertEqual(path, '/git/ref/heads/' + f.t['branch'])
            return {'object': {'sha': B}}
        def reader(config, token, key, **kwargs):
            self.assertEqual(config['project_ref'], f.project)
            self.assertEqual(token, 'synthetic-read-token')
            self.assertEqual(key, f.key)
            f.reader.deadline = kwargs['deadline']
            return f.reader
        environment = dict(GITHUB_SHA=B, GITHUB_REF=event['ref'], GITHUB_EVENT_NAME='push',
            GITHUB_EVENT_PATH=str(self.source / 'event.json'), GH_TOKEN='synthetic-gh-read',
            SUPABASE_PROJECT_REF=f.project, SUPABASE_CLI='/synthetic/cli', SUPABASE_CLI_SHA256='f' * 64,
            SUPABASE_MEASUREMENT_TOKEN='synthetic-read-token', OUTBOX_READINESS_KEY=f.key,
            FRONTEND_ORIGIN='https://frontend.invalid', API_ORIGIN='https://api.invalid')
        class Response:
            def __enter__(self): return self
            def __exit__(self, *_): pass
            def read(self, *_): return f.asset
        class Opener:
            def open(self, *_args, **_kwargs): return Response()
        previous = Path.cwd()
        output = io.StringIO()
        try:
            os.chdir(self.source)
            with patch.dict(os.environ, environment, clear=True), patch('sys.argv', ['shared_verify.py', *(['backend'] if backend else [])]), \
                    patch('shared_verify.Github', return_value=api), patch('shared_verify.SupabaseReader', side_effect=reader), \
                    patch('shared_verify.git', side_effect=lambda _, *args, **kwargs: B.encode() if args == ('rev-parse', 'HEAD') else b''), \
                    patch('shared_verify.read_json', side_effect=lambda url, **_: copy.deepcopy(f.frontend) if '/deployment.json?' in url else {'status': 'ready'}), \
                    patch('urllib.request.build_opener', return_value=Opener()), \
                    patch('shared_verify.time.monotonic', side_effect=clock), patch('shared_verify.time.sleep', side_effect=clock.sleep), \
                    contextlib.redirect_stdout(output):
                status = main()
        finally:
            os.chdir(previous)
        result = json.loads((self.source / ('backend-result.json' if backend else 'deployment-result.json')).read_bytes())
        self.assertNotIn(f.key, output.getvalue())
        self.assertNotIn('synthetic-read-token', output.getvalue())
        self.assertTrue(heads)
        return status, result, clock

    def test_both_cli_paths_for_all_environments(self):
        for branch in PROJECTS:
            for backend in (True, False):
                with self.subTest(branch=branch, backend=backend):
                    status, result, _ = self.run_cli(Fixture(self.source, branch), backend=backend)
                    self.assertEqual(status, 0)
                    self.assertEqual(result['state'], 'backend_ready' if backend else 'verified')
                    self.assertEqual(result['deployment_sha'], B)
                    self.assertEqual(result['environment'], target('refs/heads/' + branch)['environment'])

    def test_cli_waits_readonly_then_records_only_the_exact_sha(self):
        status, result, clock = self.run_cli(Fixture(self.source, 'main'), delayed_frontend=True)
        self.assertEqual(status, 0)
        self.assertEqual(result['deployment_sha'], B)
        self.assertEqual(result['frontend_sha'], B)
        self.assertEqual(clock.sleeps, [10])

    def test_cli_failure_is_sanitized_and_not_recorded_as_a_verified_deployment(self):
        f = Fixture(self.source, 'main')
        f.mode = 'active'
        status, result, clock = self.run_cli(f, backend=True)
        self.assertEqual(status, 1)
        self.assertEqual(result['state'], 'failed')
        self.assertEqual(result['reason'], 'dispatcher_mode_changed')
        self.assertEqual(result['deployment_sha'], B)
        self.assertFalse(clock.sleeps)


class WaitTests(unittest.TestCase):
    def test_workflow_propagates_failures_without_promoting_partial_success(self):
        source = (Path(__file__).resolve().parents[2] / '.github/workflows/shared-release.yml').read_text()
        body = source.split("          python3 - <<'PY_RESULT'\n", 1)[1].split('          PY_RESULT\n', 1)[0]
        code = '\n'.join(line[10:] if line.startswith('          ') else line for line in body.splitlines())
        for stage in ('backend', 'frontend', 'partial-success', 'wrong-sha'):
            with self.subTest(stage=stage), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                failure = dict(state='failed', reason='release_convergence_timeout', deployment_sha=B)
                if stage == 'backend':
                    (root / 'backend-result.json').write_bytes(encoded(failure))
                elif stage == 'frontend':
                    (root / 'deployment-result.json').write_bytes(encoded(failure))
                elif stage == 'partial-success':
                    (root / 'deployment-result.json').write_bytes(encoded(dict(state='verified', deployment_sha=B)))
                else:
                    (root / 'backend-result.json').write_bytes(encoded(dict(failure, deployment_sha=C)))
                subprocess.run([sys.executable, '-I', '-B', '-c', code], cwd=root, check=True,
                    env=dict(GITHUB_SHA=B, VERIFY_RESULT='failure', DEPLOY_RESULT='success', BUILD_RESULT='success',
                             PUBLICATION_RESULT='success', GITHUB_STEP_SUMMARY=str(root / 'summary')),
                    stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
                result = json.loads((root / 'release-result.json').read_bytes())
                self.assertEqual(result['state'], 'failed')
                self.assertEqual(result['deployment_sha'], B)
                self.assertEqual(result['reason'], 'release_convergence_timeout' if stage in ('backend', 'frontend')
                                 else 'release_not_verified')

    def test_wait_limits_cannot_be_expanded_or_disabled(self):
        for kwargs in ({'deadline': float('inf')}, {'deadline': 20, 'interval': 0},
                       {'deadline': 20, 'max_attempts': 1000}):
            with self.subTest(kwargs=kwargs), self.assertRaises(Rejected):
                converge(lambda: self.fail('measurement must not start'), lambda: None, **kwargs)

    def test_deadline_has_a_precise_failure_and_no_further_read(self):
        clock, reads, guards = Clock(), [], []
        def measure():
            reads.append(B)
            raise Pending('release_frontend_pending')
        with self.assertRaises(ConvergenceTimeout) as caught:
            converge(measure, lambda: guards.append(B), deadline=25, clock=clock, sleep=clock.sleep)
        self.assertEqual(clock.sleeps, [10, 10, 5])
        self.assertEqual(len(reads), 3)
        report = failure_result(caught.exception, 'release', target('refs/heads/main'), B)
        self.assertEqual(report['reason'], 'release_convergence_timeout')
        self.assertEqual(report['last_pending_reason'], 'release_frontend_pending')
        self.assertEqual(report['deployment_sha'], B)
        self.assertEqual(report['attempts'], 3)

    def test_attempt_limit_is_finite_even_with_a_stalled_clock(self):
        reads = []
        def measure():
            reads.append(B)
            raise Pending('measurement_unavailable')
        with self.assertRaises(ConvergenceTimeout):
            converge(measure, lambda: None, deadline=100, clock=lambda: 0, sleep=lambda _: None, max_attempts=3)
        self.assertEqual(len(reads), 3)

    def test_supersession_before_or_during_measurement_never_changes_requested_sha(self):
        for changes_after_read in (False, True):
            with self.subTest(changes_after_read=changes_after_read):
                clock, reads = Clock(), []
                def guard():
                    if not changes_after_read or reads:
                        raise Rejected('release_superseded')
                def measure():
                    reads.append(B)
                    return {'deployment_sha': B}
                with self.assertRaisesRegex(Rejected, 'release_superseded'):
                    converge(measure, guard, deadline=20, clock=clock, sleep=clock.sleep)
                self.assertEqual(len(reads), int(changes_after_read))
                self.assertFalse(clock.sleeps)

    def test_supersession_while_waiting_stops_before_the_next_measurement(self):
        clock, reads = Clock(), []
        def guard():
            if clock.sleeps:
                raise Rejected('release_superseded')
        def measure():
            reads.append(B)
            raise Pending('release_functions_pending')
        with self.assertRaisesRegex(Rejected, 'release_superseded'):
            converge(measure, guard, deadline=40, clock=clock, sleep=clock.sleep)
        self.assertEqual(reads, [B])

    def test_slow_success_past_deadline_is_not_accepted(self):
        clock = Clock()
        def measure():
            clock.now = 30
            return {'state': 'verified'}
        with self.assertRaises(ConvergenceTimeout):
            converge(measure, lambda: None, deadline=20, clock=clock, sleep=clock.sleep)

    def test_http_and_git_timeouts_use_remaining_budget(self):
        clock = Clock()
        clock.now = 8
        self.assertEqual(remaining_timeout(10, 30, clock), 2)
        calls = []
        with patch('shared_verify.time.monotonic', return_value=0):
            current_head(lambda path, **kwargs: calls.append((path, kwargs)) or {'object': {'sha': B}},
                         target('refs/heads/main'), B, 10)
        self.assertEqual(calls[0][0], '/git/ref/heads/main')
        self.assertLessEqual(calls[0][1]['timeout'], 30)

    def test_failure_results_do_not_log_provider_exception_or_secret(self):
        value = failure_result(RuntimeError('synthetic-do-not-disclose'), 'backend', target('refs/heads/qa'), B)
        self.assertNotIn('synthetic-do-not-disclose', json.dumps(value))
        self.assertEqual(value['reason'], 'release_verification_failed')

    def test_request_context_cannot_select_a_different_target_or_sha(self):
        t = target('refs/heads/qa')
        value = dict(t, deployment_sha=B, project_ref=PROJECTS['qa'])
        context(t, value, B, PROJECTS['qa'])
        for key, changed in [('environment', 'production'), ('branch', 'main'), ('deployment_sha', A), ('project_ref', DEV_PROJECT)]:
            with self.subTest(key=key), self.assertRaises(Rejected):
                context(t, dict(value, **{key: changed}), B, PROJECTS['qa'])


if __name__ == '__main__':
    unittest.main()
