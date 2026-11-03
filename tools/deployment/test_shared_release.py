"""Shared pipeline regressions. No live Engine, credentials, provider calls or deployment."""
import copy
import hashlib
import json
import os
import tempfile
import types
import unittest
from pathlib import Path
from unittest.mock import patch

from contract import DEV_PROJECT, REPOSITORY, Rejected
from shared_contract import (IMAGE, INFRASTRUCTURE, OWNER_ID, REPOSITORY_ID, decoded, encoded,
                             pr_source, public_config, push, request, target)
from shared_release import admit, check_results, make_request
from shared_host import Engine, Journal, policy
from protected_io import publish

A, B, C = 'a' * 40, 'b' * 40, 'c' * 40
DIGEST = 'd' * 64


def release(branch='develop'):
    t = target('refs/heads/' + branch)
    return make_request(dict(t, deployment_sha=B, component_digest=DIGEST, infrastructure={k:DIGEST for k in INFRASTRUCTURE}, project_ref=DEV_PROJECT if branch=='develop' else 'abcdefghijklmnopqrst'), A,
                        IMAGE + '@sha256:' + 'e' * 64, 123, 1000)


def event(branch='develop'):
    return dict(repository=dict(id=REPOSITORY_ID, full_name=REPOSITORY, owner={'id': OWNER_ID}, fork=False),
                ref='refs/heads/' + branch, before=A, after=B, forced=False, deleted=False)


def checks():
    return [dict(name=name, app={'id': 15368}, status='completed', conclusion='success')
            for name in ('M4 Required CI', 'validate-commits', 'validate-docs')]


class ContractTests(unittest.TestCase):
    def test_exact_mapping(self):
        for branch, env, runtime in [('develop', 'dev', 'DEV'), ('qa', 'qa', 'QA'), ('main', 'production', 'PROD')]:
            with self.subTest(branch=branch):
                t = target('refs/heads/' + branch)
                self.assertEqual((t['environment'], t['runtime_environment']), (env, runtime))

    def test_arbitrary_targets_rejected(self):
        for ref in ('main', 'refs/tags/main', 'refs/pull/1/merge', 'refs/heads/feature/main', 'refs/heads/production'):
            with self.subTest(ref=ref), self.assertRaises(Rejected): target(ref)

    def test_pr_never_deploys(self):
        for kind in ('pull_request', 'pull_request_target', 'workflow_dispatch', 'workflow_run'):
            with self.subTest(kind=kind), self.assertRaises(Rejected): push(kind, event(), event()['ref'], B)

    def test_push_identity(self):
        self.assertEqual(push('push', event(), event()['ref'], B)['environment'], 'dev')
        for key, value in [('forced', True), ('deleted', True), ('after', C), ('ref', 'refs/heads/main')]:
            v = event(); v[key] = value
            with self.subTest(key=key), self.assertRaises(Rejected): push('push', v, event()['ref'], B)

    def test_only_defined_promotions(self):
        for base, head in [('develop', 'feature/test'), ('qa', 'develop'), ('main', 'qa')]: pr_source(base, head)
        for base, head in [('main', 'develop'), ('main', 'feature/x'), ('qa', 'feature/x'), ('develop', 'qa'), ('develop', 'feature/')]:
            with self.subTest(base=base, head=head), self.assertRaises(Rejected): pr_source(base, head)

    def test_readonly_checks_require_actual_app(self):
        check_results(checks())
        for field, value in [('app', {'id': 999}), ('status', 'in_progress'), ('conclusion', 'failure')]:
            rows = checks(); rows[0][field] = value
            with self.subTest(field=field), self.assertRaises(Rejected): check_results(rows)

    def test_conflicting_success_is_not_selected(self):
        rows = checks(); rows.append(dict(rows[0], conclusion='failure'))
        with self.assertRaises(Rejected): check_results(rows)

    def test_expired_and_replayed_authority(self):
        v = release(); request(v, now=1000)
        for now in (999, 1901):
            with self.subTest(now=now), self.assertRaises(Rejected): request(v, now=now)

    def test_cross_environment_and_unapproved_image(self):
        for field, value in [('environment', 'production'), ('image', 'evil.invalid/x@sha256:'+'e'*64),
                             ('build_sha', 'fake'), ('component_digest', 'fake'), ('expires_at', 999999)]:
            v=release(); v[field]=value
            with self.subTest(field=field), self.assertRaises(Rejected): request(v)

    def test_no_extra_commands_or_paths(self):
        for key in ('command', 'compose_file', 'docker_socket', 'secrets', 'sudo'):
            v=release();v[key]='forbidden'
            with self.subTest(key=key), self.assertRaises(Rejected): request(v)

    def test_duplicate_and_oversized_json(self):
        for raw in (b'{"a":1,"a":2}', b'x'* (2*1024*1024+1), b'{"value":NaN}'):
            with self.assertRaises((Rejected, ValueError)): decoded(raw)

    def test_public_configuration_has_no_runtime_secret(self):
        for branch, project in [('develop', DEV_PROJECT), ('qa', 'abcdefghijklmnopqrst'), ('main', 'bcdefghijklmnopqrstu')]:
            v=public_config(target('refs/heads/'+branch), project, 'sb_publishable_synthetic_only_0000')
            self.assertEqual(set(v), {'SUPABASE_URL','SUPABASE_ANON_KEY','MONEYBOWL_ENV','NSE_CONSOLE_ENABLED','MONEYBOWL_DEV_ONBOARDING_PREVIEW'})
            self.assertEqual(v['NSE_CONSOLE_ENABLED'], 'false')
        with self.assertRaises(Rejected): public_config(target('refs/heads/qa'), DEV_PROJECT, 'sb_publishable_synthetic_only_0000')

    def test_prod_uncommissioned_by_default(self):
        root=Path(__file__).resolve().parents[2]
        self.assertFalse(json.loads((root/'tools/deployment/environments.json').read_text())['prod']['deployment_enabled'])
        with self.assertRaises(Rejected): policy(json.loads((root/'tools/deployment/shared-host.example.json').read_text()))


class AdmissionTests(unittest.TestCase):
    def setUp(self):
        self.commit={'sha':B,'parents':[{'sha':A},{'sha':C}]}
        self.pr={'number':1,'merged':True,'merge_commit_sha':B,'merged_by':{'id':OWNER_ID},
                 'base':{'ref':'develop','repo':{'id':REPOSITORY_ID}},
                 'head':{'ref':'feature/test','sha':C,'repo':{'id':REPOSITORY_ID}}}
        self.rows=checks();self.head=B
        self.git=patch('shared_release.git', return_value=b'tree\n').start()
        patch('shared_release.manifest', return_value={'ingestion_support':DIGEST}).start()
        self.addCleanup(patch.stopall)

    def api(self, path):
        if path.startswith('/git/ref/'):return {'object':{'sha':self.head}}
        if '/check-runs?' in path:return {'total_count':len(self.rows),'check_runs':self.rows}
        if path.endswith('/pulls?per_page=100'):return [self.pr]
        if path.startswith('/pulls/'):return self.pr
        return self.commit

    def run_admit(self, branch='develop'):
        return admit('push', event(branch), 'refs/heads/'+branch, B, self.api)

    def test_owner_merge(self): self.assertEqual(self.run_admit()['deployment_sha'],B)

    def test_direct_squash_rebase_push_rejected(self):
        self.commit['parents']=[{'sha':A}]
        with self.assertRaises(Rejected): self.run_admit()

    def test_different_merger_rejected(self):
        self.pr['merged_by']['id']=999
        with self.assertRaises(Rejected): self.run_admit()

    def test_fork_and_wrong_head_rejected(self):
        for field in ('fork','head'):
            v=copy.deepcopy(self.pr)
            if field=='fork':self.pr['head']['repo']['id']=999
            else:self.pr['head']['sha']=A
            with self.assertRaises(Rejected):self.run_admit()
            self.pr=v

    def test_superseded_merge_rejected(self):
        self.head=C
        with self.assertRaises(Rejected):self.run_admit()

    def test_promotion_checks_ancestry_and_tree(self):
        self.pr['base']['ref']='main';self.pr['head']['ref']='qa'
        self.assertEqual(self.run_admit('main')['environment'],'production')
        self.assertIn(('merge-base','--is-ancestor',C,B), [call.args[1:] for call in self.git.call_args_list])
        self.git.side_effect=[b'',b'newtree',b'oldtree']
        with self.assertRaises(Rejected):self.run_admit('main')

    def test_develop_cannot_promote_to_production(self):
        self.pr['base']['ref']='main';self.pr['head']['ref']='develop'
        with self.assertRaises(Rejected):self.run_admit('main')


class FakeEngine:
    def __init__(self):
        self.config={'environment':'dev','baseline_api_id':'old','baseline_image_id':'sha256:old'}
        self.value={'api':{'id':'old','image':'sha256:old','labels':{}},'caddy':{'id':'unchanged'}}
        self.activations=0;self.fail=None
    def authority(self): pass
    def verify_authorization(self, value, bundle, clock):
        request(value, now=clock())
        if value['environment']!=self.config['environment'] or bundle!={'valid':True}:raise Rejected('unauthorized')
    def observation(self):return copy.deepcopy(self.value)
    def prepare(self,value):pass
    def activate(self,value,recheck):
        recheck();self.activations+=1
        if self.fail=='uncertain':raise TimeoutError()
        self.value['api']={'id':'new','image':'sha256:new','labels':{'org.opencontainers.image.revision':value['deployment_sha'],'moneybowl.source_digest':value['component_digest']}}
        if self.fail=='support':self.value['caddy']['id']='changed'
        if self.fail=='health':raise Rejected('unhealthy')
        return 'sha256:new'


class JournalTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        root=Path(self.tmp.name);root.chmod(0o700)
        self.root=root/'journal';self.root.mkdir(mode=0o700)
        self.lock=root/'lock';self.lock.mkdir(mode=0o700)
        (self.lock/'.owner.lock').write_bytes(b'');(self.lock/'.owner.lock').chmod(0o600)
        self.engine=FakeEngine();self.journal=Journal(self.root,self.lock,self.engine,clock=lambda:1001)
        # Root ownership is enforced separately by production policy tests; real
        # fsync/create-only/lock behavior is exercised here as the test process UID.
        patch('shared_host.root_controlled',side_effect=lambda p,**_:Path(p)).start()
        self.addCleanup(patch.stopall)

    def deploy(self,v=None):return self.journal.deploy(v or release(), {'valid':True})

    def test_success_and_duplicate_without_activation(self):
        self.assertEqual(self.deploy()['state'],'deployed')
        self.assertEqual(self.deploy()['state'],'already_deployed')
        self.assertEqual(self.engine.activations,1)
        self.assertEqual(self.engine.value['caddy']['id'],'unchanged')

    def test_unauthorized_request_never_consumes_intent(self):
        with self.assertRaises(Rejected):self.journal.deploy(release(),{'valid':False})
        self.assertEqual(list(self.root.iterdir()),[])

    def test_wrong_environment_never_consumes_intent(self):
        with self.assertRaises(Rejected):self.deploy(release('qa'))
        self.assertEqual(list(self.root.iterdir()),[])

    def test_failure_quarantines_without_retry_or_rollback(self):
        self.engine.fail='health'
        with self.assertRaises(Rejected):self.deploy()
        self.assertTrue((self.root/(B+'.intent.json')).exists())
        with self.assertRaises((Rejected,FileNotFoundError)):self.deploy()
        self.assertEqual(self.engine.activations,1)

    def test_uncertain_activation_is_not_retried(self):
        self.engine.fail='uncertain'
        with self.assertRaises(TimeoutError):self.deploy()
        with self.assertRaises((Rejected,FileNotFoundError)):self.deploy()
        self.assertEqual(self.engine.activations,1)

    def test_changed_support_blocks_completion(self):
        self.engine.fail='support'
        with self.assertRaises(Rejected):self.deploy()
        self.assertFalse((self.root/(B+'.complete.json')).exists())

    def test_interruption_after_intent_is_durable(self):
        def interrupted(path,value,**kwargs):
            publish(path,value,**kwargs)
            raise KeyboardInterrupt()
        with patch('shared_host.publish', side_effect=interrupted):
            with self.assertRaises(KeyboardInterrupt):self.deploy()
        self.assertTrue((self.root/(B+'.intent.json')).exists())
        self.assertEqual(self.engine.activations,0)
        with self.assertRaises((Rejected,FileNotFoundError)):self.deploy()

    def test_interruption_before_completion_does_not_reactivate(self):
        calls=0
        def interrupted(path,value,**kwargs):
            nonlocal calls
            calls+=1
            if calls==2:raise KeyboardInterrupt()
            return publish(path,value,**kwargs)
        with patch('shared_host.publish',side_effect=interrupted):
            with self.assertRaises(KeyboardInterrupt):self.deploy()
        with self.assertRaises((Rejected,FileNotFoundError)):self.deploy()
        self.assertEqual(self.engine.activations,1)

    def test_conflicting_duplicate_rejected(self):
        self.deploy();v=release();v['image']=IMAGE+'@sha256:'+'f'*64
        with self.assertRaises(Rejected):self.deploy(v)

    def test_runtime_drift_rejected(self):
        self.engine.value['api']['id']='unknown'
        with self.assertRaises(Rejected):self.deploy()
        self.assertEqual(self.engine.activations,0)

    def test_unfinished_private_write_rejected(self):
        (self.root/'.pending-interrupted').write_text('partial')
        with self.assertRaises(Rejected):self.deploy()

    def test_missing_original_lock_is_never_recreated(self):
        (self.lock/'.owner.lock').unlink()
        with self.assertRaises(FileNotFoundError):self.deploy()
        self.assertFalse((self.lock/'.owner.lock').exists())
        self.assertEqual(self.engine.activations,0)


class WorkflowTests(unittest.TestCase):
    def test_workflow_boundaries(self):
        root=Path(__file__).resolve().parents[2]
        source=(root/'.github/workflows/shared-release.yml').read_text()
        self.assertNotIn('workflow_dispatch',source)
        self.assertNotIn('self-hosted',source)
        self.assertNotIn('supabase db push',source)
        self.assertNotIn('supabase functions deploy',source)
        self.assertIn('workflow_call:',source)
        self.assertIn('push-to-registry: true',source)
        self.assertIn('ConnectionAttempts=1',source)
        self.assertIn('cancel-in-progress: false',source)
        self.assertNotIn('inputs.environment',source)
        self.assertIn('flutter build web --release --dart-define-from-file=',source)

    def test_no_client_docker_or_sudo_or_arbitrary_unit(self):
        root=Path(__file__).resolve().parent
        client=(root/'shared_client.py').read_text()
        self.assertNotIn("'sudo'",client);self.assertNotIn("'docker'",client)
        rule=(root/'moneybowl-shared-deploy.rules').read_text()
        self.assertIn('action.lookup("verb") == "start"',rule)
        self.assertIn('action.lookup("unit") == "moneybowl-api-deploy.service"',rule)
        self.assertNotIn('[Install]',(root/'moneybowl-api-deploy.service').read_text().split('# No [Install]')[0])


class SignatureTests(unittest.TestCase):
    def test_pinned_signer_source_and_environment(self):
        calls=[]
        class Process:
            tools={'gh':'/approved/gh','docker':'/approved/docker','systemctl':'/approved/systemctl'}
            def __call__(self, argv, **kwargs):
                calls.append(argv)
                subject = argv[3].split('@sha256:', 1)[1] if argv[3].startswith('oci://') else hashlib.sha256(Path(argv[3]).read_bytes()).hexdigest()
                return encoded([{'verificationResult':{'signature':{'certificate':'synthetic'},
                    'statement':{'subject':[{'digest':{'sha256':subject}}]}}}])
        engine=Engine({'environment':'dev','branch':'develop','project_ref':DEV_PROJECT,
                       'infrastructure_pins':release()['infrastructure'], 'trusted_root_seal':{'path':'/approved/trust'}},Process())
        with patch('shared_host.sealed_read',return_value=b'nonsecret-trust'):
            engine.verify_authorization(release(),{'synthetic':'bundle'},lambda:1001)
        self.assertEqual(len(calls),2)
        self.assertIn('--bundle',calls[0]);self.assertIn('--bundle-from-oci',calls[1])
        self.assertIn('--deny-self-hosted-runners',calls[0])
        self.assertIn('--source-ref',calls[0]);self.assertIn('refs/heads/develop',calls[0])
        self.assertIn(B,calls[0]);self.assertIn(A,calls[1])
        self.assertIn(REPOSITORY+'/.github/workflows/shared-release.yml',calls[0])

    def test_cross_environment_rejected_before_gh(self):
        class Process:
            tools={'gh':'/approved/gh','docker':'/approved/docker','systemctl':'/approved/systemctl'}
            def __call__(self,*args,**kwargs):raise AssertionError('must not run')
        engine=Engine({'environment':'production','branch':'main','project_ref':'abcdefghijklmnopqrst'},Process())
        with self.assertRaises(Rejected):engine.verify_authorization(release(),{},lambda:1001)

    def test_failed_signature_preserves_empty_journal(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp);path.chmod(0o700)
            (path/'.owner.lock').write_bytes(b'');(path/'.owner.lock').chmod(0o600)
            engine=FakeEngine()
            with patch.object(engine,'verify_authorization',side_effect=Rejected('invalid_signature')):
                with self.assertRaises(Rejected):Journal(path,path,engine,lambda:1001).deploy(release(),{})
            self.assertEqual(engine.activations,0)
            self.assertFalse(list(path.glob('*.intent.json')))

    def test_empty_failed_or_wrong_artifact_evidence_rejected(self):
        from shared_host import verified_subject
        for value in ([], {}, [{'verificationResult':{}}],
                      [{'verificationResult':{'signature':{'certificate':'synthetic'},'statement':{'subject':[{'digest':{'sha256':'wrong'}}]}}}]):
            with self.subTest(value=value), self.assertRaises(Rejected):verified_subject(encoded(value),DIGEST)


class InboxTests(unittest.TestCase):
    def test_reading_does_not_reject_its_own_atime_update(self):
        from shared_host import read_inbox
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'request.json'
            raw = encoded({'release': release(), 'bundle': {'synthetic': True}})
            path.write_bytes(raw); path.chmod(0o600)
            old_fstat = os.fstat
            def metadata(fd):
                value = old_fstat(fd)
                result = types.SimpleNamespace(**{name: getattr(value, name) for name in
                    ('st_dev', 'st_ino', 'st_mode', 'st_nlink', 'st_size', 'st_mtime_ns', 'st_ctime_ns')})
                result.st_uid, result.st_gid = 993, 983
                return result
            with patch('shared_host.INBOX', path), patch('shared_host.os.fstat', side_effect=metadata):
                self.assertEqual(read_inbox()[0], raw)

    def test_public_bind_file_bytes_and_inode_remain_bound(self):
        from shared_host import public_relationship
        from initial_private_inputs import identity
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'Caddyfile'
            path.write_bytes(b'synthetic public configuration');path.chmod(0o644)
            value = {'path':str(path), 'identity':identity(path.stat()),
                     'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
            public_relationship(value)
            path.write_bytes(b'changed public configuration')
            with self.assertRaises(Rejected):public_relationship(value)

    def test_replaced_public_bind_inode_rejected(self):
        from shared_host import public_relationship
        from initial_private_inputs import identity
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'Caddyfile';path.write_bytes(b'synthetic');path.chmod(0o644)
            value={'path':str(path),'identity':identity(path.stat()),'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
            replacement=Path(tmp)/'new';replacement.write_bytes(b'synthetic');replacement.chmod(0o644)
            os.replace(replacement,path)
            with self.assertRaises(Rejected):public_relationship(value)


class ArtifactTests(unittest.TestCase):
    def setUp(self):
        self.config={'os':'linux','architecture':'arm64','config':{'Labels':{
            'org.opencontainers.image.revision':A,'moneybowl.source_digest':DIGEST}}}
        self.missing=False
        patch('shared_artifacts.git',return_value=b'').start()
        patch('contract.manifest',return_value={'ingestion_support':DIGEST}).start()
        self.addCleanup(patch.stopall)

    def http(self,url,headers):
        if '/token?' in url:return 200,encoded({'token':'synthetic'})
        raw=encoded(self.config)
        if '/manifests/' in url:
            if self.missing:return 404,b''
            return 200,encoded({'mediaType':'application/vnd.oci.image.manifest.v1+json',
                               'config':{'digest':'sha256:'+hashlib.sha256(raw).hexdigest()}})
        return 200,raw

    def select(self):
        from shared_artifacts import select
        return select({'deployment_sha':B,'component_digest':DIGEST},'synthetic','synthetic',transport=self.http)

    def test_unchanged_component_reuses_digest_and_build_sha(self):
        value=self.select()
        self.assertFalse(value['build']);self.assertEqual(value['build_sha'],A)
        self.assertTrue(value['image'].startswith(IMAGE+'@sha256:'))

    def test_absent_component_requires_build(self):
        self.missing=True;self.assertTrue(self.select()['build'])

    def test_changed_component_not_promoted(self):
        self.config['config']['Labels']['moneybowl.source_digest']='f'*64
        with self.assertRaises(Rejected):self.select()

    def test_nonancestor_image_rejected(self):
        with patch('shared_artifacts.git',side_effect=Rejected('not_ancestor')):
            with self.assertRaises(Rejected):self.select()

    def test_registry_failure_does_not_fallback_to_build(self):
        from shared_artifacts import select
        with self.assertRaises(Rejected):select({'component_digest':DIGEST},'synthetic','synthetic',transport=lambda *_:(403,b''))

    def test_wrong_architecture_rejected(self):
        self.config['architecture']='amd64'
        with self.assertRaises(Rejected):self.select()


class MeasurementTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.source=Path(self.tmp.name)
        for name in ('supabase/migrations','supabase/functions/synthetic','services/outbox-dispatcher'):
            (self.source/name).mkdir(parents=True,exist_ok=True)
        (self.source/'supabase/migrations/20260101000000_synthetic.sql').write_text('SELECT 1;')
        (self.source/'supabase/config.toml').write_text('[functions.synthetic]\nverify_jwt = true\n')
        (self.source/'supabase/functions/synthetic/index.ts').write_text('export const synthetic = 1;\n')
        self.routes={str(i):{'worker_slug':'synthetic'} for i in range(17)}
        (self.source/'services/outbox-dispatcher/routes.json').write_text(json.dumps(self.routes))
        self.reader=type('Reader',(),{})();r=self.reader;r.project=DEV_PROJECT
        self.rows=[{'version':'20260101000000','statements':['SELECT 1;']}]
        self.functions=[{'slug':'synthetic','id':'synthetic','version':1,'status':'ACTIVE','verify_jwt':True}]
        r.migrations=lambda:self.rows;r.functions=lambda:self.functions
        r.files=lambda _:{'synthetic/index.ts':b'export const synthetic = 1;\n'}
        r.control=lambda:dict(environment='DEV',project_ref=DEV_PROJECT,project_url='https://'+DEV_PROJECT+'.supabase.co',
                              mode='active',jobs=[{'schedule':'*/15 * * * *','command':'SELECT moneybowl_dispatch.notify(NULL,0);','active':True,'database':'postgres'}])
        r.readiness=lambda _:dict(code='outbox_ready',environment='DEV',project_url='https://'+DEV_PROJECT+'.supabase.co',
                                  routes={str(i):'synthetic' for i in range(17)},mode='active')

    def verify(self):
        from shared_verify import verify_backend
        return verify_backend(self.source,target('refs/heads/develop'),self.reader)

    def test_real_statement_and_export_comparison(self):self.assertEqual(self.verify()['state'],'backend_ready')

    def test_source_count_alone_is_not_evidence(self):
        self.rows[0]['statements']=['SELECT 2;']
        with self.assertRaises(Rejected):self.verify()

    def test_changed_function_source_rejected(self):
        self.reader.files=lambda _:{'synthetic/index.ts':b'export const changed = 1;\n'}
        with self.assertRaises(Rejected):self.verify()

    def test_changed_function_jwt_rejected(self):
        self.functions[0]['verify_jwt']=False
        with self.assertRaises(Rejected):self.verify()

    def test_unknown_function_is_not_ignored(self):
        self.functions.append(dict(self.functions[0],slug='unapproved'))
        with self.assertRaises(Rejected):self.verify()

    def test_readiness_authentication_cannot_be_omitted(self):
        self.reader.readiness=lambda _: {}
        with self.assertRaises(Rejected):self.verify()

    def test_erased_type_import_export_compatibility(self):
        from evidence_owner import module_specifiers
        self.assertEqual(module_specifiers('import type { Foo } from "./erased.ts"; export type { Bar } from "./also-erased.ts";'),[])
        self.assertEqual(module_specifiers('import type from "./runtime.ts";'),['./runtime.ts'])


if __name__=='__main__':unittest.main()
