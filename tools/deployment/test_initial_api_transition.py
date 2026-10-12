"""Disposable Git + synthetic Engine/OCI tests. Never access live infrastructure."""
import base64
import copy
import json
import os
import re
import urllib.request
import unittest
from pathlib import Path
from unittest.mock import patch

import compose_inventory as inventory
import initial_api_transition as transition
import test_compose_inventory as fixtures
from contract import DEV_PROJECT, Rejected, manifest
from ingestion_owner import API_COMMAND, DEV_RETIRED_CONTAINER, reconcile
from owner_common import sha256
from private_registry import Registry
from protected_io import deployment_lock, protected, publish, read_private

NOW = 1800000000


def synthetic_root_authority(test):
    # The restricted test runner maps host root to nobody. Model genuine root-owned
    # system ancestors while preserving all fixture permission/link checks.
    original = Path.lstat
    def metadata(path):
        info = original(path)
        if path in (Path('/'), Path('/tmp')) and info.st_uid == 65534:
            values = list(info); values[4] = 0
            return os.stat_result(values)
        return info
    mock = patch.object(Path, 'lstat', metadata)
    mock.start(); test.addCleanup(mock.stop)



class TransitionTests(unittest.TestCase):
    def setUp(self):
        synthetic_root_authority(self)
        self.f = fixtures.ComposeInventoryTests('runTest')
        self.f.setUp(); self.addCleanup(self.f.doCleanups)
        f = self.f
        self.config = f.config
        self.config['commissioned'] = False
        self.config['retired_containers'] = [DEV_RETIRED_CONTAINER]
        for key in ('state_root', 'report_root'):
            Path(self.config[key]).mkdir(mode=0o700)
        auth = f.root / 'auth'; auth.mkdir(mode=0o700)
        publish(auth / 'config.json', {'auths': {'registry.invalid': {'auth': base64.b64encode(b'user:synthetic-secret').decode()}}})
        self.config['docker_config'] = str(auth)
        approvals = f.root / 'approvals'; approvals.mkdir(mode=0o700)
        private = f.root / 'private.env'; private.write_bytes(b'PRIVATE=synthetic'); private.chmod(0o600)
        self.config['compose_env'] = str(private)
        archive = f.root / 'legacy.tar'; archive.write_bytes(b'synthetic reviewed recovery archive'); archive.chmod(0o600)
        record = f.root / 'recovery.json'; publish(record, {'image_id': transition.LEGACY, 'git_commit': None})
        self.config['initial_transition'] = dict(enabled=True, source_revision=f.sha,
            source_digest=manifest(f.repo, f.sha)['ingestion_support'], candidate_image_id=transition.CANDIDATE,
            approved_branch_head=f.sha, image='registry.invalid/api@sha256:' + 'd'*64,
            approval_root=str(approvals), protected_inputs=[dict(path=str(private), approval='private-owner-review',
            sha256=sha256(private.read_bytes()))], recovery=dict(archive=str(archive), record=str(record),
            sha256=sha256(archive.read_bytes()), size=archive.stat().st_size, image_id=transition.LEGACY,
            record_sha256=sha256(record.read_bytes()), approval='recovery-owner-review'))
        for name, value in (('SOURCE', f.sha), ('SOURCE_DIGEST', self.config['initial_transition']['source_digest'])):
            mock = patch.object(transition, name, value); mock.start(); self.addCleanup(mock.stop)
        old = f.live['api']; old.update(id=transition.LEGACY_CONTAINER, image=transition.LEGACY)
        old['security']['user'] = '10001:10001'
        self.config['compose_services']['api'].update(container_id=old['id'], image_id=old['image'],
                                                     runtime_sha256=inventory.runtime_identity(old))
        f.images[transition.LEGACY] = dict(id=transition.LEGACY)
        proof = transition.proof_for(self.config)
        f.images[proof['image']] = dict(id=transition.CANDIDATE, digests=[proof['image']], command=API_COMMAND.copy(),
            entrypoint=None, user='10001:10001', architecture='arm64', os='linux',
            labels={'org.opencontainers.image.revision': f.sha, 'moneybowl.source_digest': proof['source_digest']})
        self.retired = dict(id='c'*64, image='sha256:'+'9'*64, state={'Status':'exited', 'Running':False}, restart='no')
        def transport(argv, **kwargs):
            raw = f.command(argv, **kwargs)
            if 'up' in argv:
                f.live['api']['labels']['moneybowl.source_digest'] = proof['source_digest']
            return raw
        self.docker = transition.InitialDockerOwner(self.config, command=transport)
        self.docker.container = lambda identifier: copy.deepcopy(self.retired if identifier in
            ('c'*64, DEV_RETIRED_CONTAINER) else next(v for v in f.live.values() if v['id'] == identifier))
        self.docker.retirement = lambda: 'retired'
        self.docker.capacity = lambda: None  # Real statvfs boundary covered by existing capacity tests.
        self.remote = {'image': proof['image'], 'image_id': transition.CANDIDATE, 'remote_verified':True, 'private':True}
        self.registry = unittest.mock.Mock()
        self.registry.verify.side_effect = lambda _: copy.deepcopy(self.remote)
        self.head = lambda: f.sha
        self.args = (self.config, f.p, self.docker, self.head, self.registry)
        self.state = Path(self.config['state_root'])

    def prepare(self):
        return transition.prepare(*self.args, now=lambda: NOW)

    def approval(self):
        path = Path(self.config['initial_transition']['approval_root']) / 'approval.json'
        publish(path, dict(kind='moneybowl-initial-api-activation-v1', environment='dev', project_ref=DEV_PROJECT,
            target='api', owner='independent-owner', nonce='a'*64, expires_at=NOW+300,
            branch_head=self.f.sha, plan_digest=read_private(self.state / transition.JOURNAL)['plan_digest']))
        return path

    def activate(self, approval=None):
        return transition.activate(*self.args, approval or self.approval(), now=lambda: NOW)

    def verify(self):
        return transition.verify(*self.args, now=lambda: NOW)

    def assert_no_up(self):
        self.assertFalse(any('up' in call for call in self.f.calls))

    def test_success_separate_phases_exact_command_and_future_owner_adoption(self):
        unrelated = copy.deepcopy({k:v for k,v in self.f.live.items() if k!='api'})
        self.assertEqual(self.prepare()['state'], 'PREPARED'); self.assert_no_up()
        self.assertFalse((self.state / (self.f.sha + '.provenance.json')).exists())
        self.assertEqual(self.activate()['state'], 'ACTIVATED_NOT_VERIFIED')
        self.assertFalse((self.state / (self.f.sha + '.provenance.json')).exists())
        result = self.verify(); self.assertEqual(result['state'], 'VERIFIED')
        up = [call for call in self.f.calls if 'up' in call]
        self.assertEqual(len(up), 1)
        self.assertEqual(up[0][up[0].index('up'):], ['up','--detach','--no-deps','--no-build','--pull','never',
            '--scale','api=1','--wait','--wait-timeout','120','api'])
        self.assertEqual(up[0].count('-f'), 6)
        self.assertEqual(unrelated, {k:v for k,v in self.f.live.items() if k!='api'})
        # Regular labelled-image validation adopts genuine ledger without historical invention.
        self.f.owner.validate_current(self.f.live['api'])
        receipt = read_private(Path(self.config['report_root']) / (self.f.sha + '.json'))
        self.assertEqual(receipt['component']['proof'], 'running_image')
        self.assertNotIn('synthetic-secret', json.dumps(receipt))
        self.assertEqual(read_private(self.state / transition.JOURNAL)['state'], 'VERIFIED')

    def test_unknown_history_not_fabricated_or_normal_guard_weakened(self):
        self.prepare()
        plan = read_private(self.state / 'initial-plan.json')
        self.assertEqual(plan['legacy_provenance'], dict(git_commit=None, source_digest=None, status='unknown'))
        with self.assertRaisesRegex(Rejected, 'legacy_provenance_unverified'):
            inventory.initial_revision(self.config, self.f.live['api'], self.f.repo)

    def test_optional_entrypoint_template_and_rejection(self):
        proof = transition.proof_for(self.config)
        fields = {'.Id': proof['image_id'], '.RepoDigests': [proof['image']],
            '.Config.Labels': {'org.opencontainers.image.revision': self.f.sha,
                              'moneybowl.source_digest': proof['source_digest']},
            '.Config.Cmd': API_COMMAND, '.Config.User': '10001:10001', '.Architecture': 'arm64', '.Os': 'linux'}
        for entrypoint in (None, [], ['unauthorized']):
            def command(argv, **kwargs):
                template = argv[argv.index('--format') + 1]
                optional = '{{json (index .Config "Entrypoint")}}'
                self.assertEqual(template.count(optional), 1)
                rendered = template.replace(optional, json.dumps(entrypoint))
                return re.sub(r'\{\{json ([^}]+)\}\}',lambda match:json.dumps(fields[match[1]]),rendered).encode()
            owner = transition.InitialDockerOwner(self.config, command=command)
            if entrypoint:
                with self.assertRaisesRegex(Rejected,'single_worker_command_required'):owner.verify_image(proof)
            else: owner.verify_image(proof)

    def test_missing_running_source_digest(self):
        self.prepare(); self.activate(); self.f.live['api']['labels'].pop('moneybowl.source_digest')
        self.assertEqual(self.verify()['reason'],'running_source_digest_mismatch')

    def test_changed_effective_compose_hash(self):
        self.prepare(); self.f.hashes['api']='f'*64
        self.assertEqual(self.activate()['reason'],'running_configuration_drift'); self.assert_no_up()

    def test_second_api_instance_is_rejected(self):
        self.prepare(); original=self.docker.containers
        self.docker.containers=lambda service: original(service)*2 if service=='api' else original(service)
        self.assertEqual(self.activate()['reason'],'support_service_not_running'); self.assert_no_up()

    def test_remote_digest_changes_before_activation(self):
        self.prepare(); self.remote['config_digest']='sha256:'+'e'*64
        self.assertEqual(self.activate()['reason'],'remote_registry_changed'); self.assert_no_up()

    def test_failed_prepare_keeps_no_trusted_ledger(self):
        self.docker.capacity=unittest.mock.Mock(side_effect=Rejected('insufficient_build_capacity'))
        with self.assertRaisesRegex(Rejected,'insufficient_build_capacity'): self.prepare()
        self.assertFalse((self.state/(self.f.sha+'.provenance.json')).exists())
        self.assert_no_up()

    def test_private_bind_credential_cannot_be_omitted_from_approved_inputs(self):
        secret = self.f.root/'private-bind'; secret.write_bytes(b'synthetic'); secret.chmod(0o600)
        self.f.live['api']['mounts']=[dict(Type='bind',Source=str(secret),Destination='/credential',RW=False)]
        self.config['compose_services']['api']['runtime_sha256']=inventory.runtime_identity(self.f.live['api'])
        with self.assertRaisesRegex(Rejected,'private_bind_input_unapproved'):self.prepare()
        self.assertEqual(read_private(self.state/transition.JOURNAL)['state'],'FAILED')
        self.assert_no_up()

    def test_wrong_source_revision(self):
        self.config['initial_transition']['source_revision']='f'*40
        with self.assertRaisesRegex(Rejected,'initial_source_unapproved'): self.prepare()
        self.assert_no_up()

    def test_wrong_git_component_digest(self):
        with patch.object(transition, 'manifest', return_value={'ingestion_support':'f'*64}):
            with self.assertRaisesRegex(Rejected,'source_digest_mismatch'): self.prepare()
        self.assert_no_up()

    def test_four_layers_rejected(self):
        self.config['compose_layers'].pop()
        with self.assertRaisesRegex(Rejected,'five_compose_layers_required'): self.prepare()

    def test_wrong_environment(self):
        self.config['environment']='qa'
        with self.assertRaisesRegex(Rejected,'initial_environment_invalid'): self.prepare()

    def test_missing_registry_credentials(self):
        self.registry.verify.side_effect=Rejected('registry_credentials_missing')
        with self.assertRaisesRegex(Rejected,'registry_credentials_missing'): self.prepare()
        self.assert_no_up()

    def test_missing_remote_digest(self):
        self.registry.verify.side_effect=Rejected('registry_digest_unpublished')
        with self.assertRaisesRegex(Rejected,'registry_digest_unpublished'): self.prepare()
        self.assert_no_up()

    def test_invalid_approval(self):
        self.prepare(); approval=self.approval(); value=read_private(approval); value['plan_digest']='f'*64
        publish(approval,value)
        self.assertEqual(self.activate(approval)['reason'],'owner_approval_invalid'); self.assert_no_up()

    def test_approval_reuse_and_no_blind_retry(self):
        self.prepare(); approval=self.approval(); self.activate(approval)
        with self.assertRaisesRegex(Rejected,'activation_not_retryable'): self.activate(approval)
        self.assertEqual(len([call for call in self.f.calls if 'up' in call]),1)

    def test_consumed_nonce_rejected(self):
        self.prepare(); approval=self.approval()
        publish(self.state / ('approval-'+'a'*64+'.consumed.json'),{},immutable=True)
        self.assertEqual(self.activate(approval)['reason'],'owner_approval_reused'); self.assert_no_up()

    def test_expired_approval(self):
        self.prepare(); approval=self.approval(); value=read_private(approval); value['expires_at']=NOW-1
        publish(approval,value)
        self.assertEqual(self.activate(approval)['reason'],'owner_approval_invalid'); self.assert_no_up()

    def test_branch_moves_after_prepare(self):
        self.prepare(); self.args=(*self.args[:3],lambda:'f'*40,self.registry)
        self.assertEqual(self.activate()['reason'],'branch_changed'); self.assert_no_up()

    def test_concurrent_normal_and_initial_owner(self):
        with deployment_lock(self.state):
            with self.assertRaisesRegex(Rejected,'deployment_busy'): self.prepare()
        self.assert_no_up()

    def test_capacity_fails_before_activation(self):
        self.prepare(); self.docker.capacity=unittest.mock.Mock(side_effect=Rejected('insufficient_build_capacity'))
        self.assertEqual(self.activate()['reason'],'insufficient_build_capacity'); self.assert_no_up()

    def test_prepare_cannot_be_repeated(self):
        self.prepare()
        with self.assertRaisesRegex(Rejected,'initial_transition_already_prepared'): self.prepare()

    def test_plan_tampering(self):
        self.prepare(); value=read_private(self.state/'initial-plan.json'); value['activation_target']='caddy'
        publish(self.state/'initial-plan.json', value)
        with self.assertRaisesRegex(Rejected,'plan_integrity_failed'): self.activate()
        self.assert_no_up()

    def test_changed_private_input(self):
        self.prepare(); Path(self.config['compose_env']).write_bytes(b'changed')
        self.assertEqual(self.activate()['reason'],'private_input_changed'); self.assert_no_up()

    def test_recovery_archive_preserved_and_tamper_rejected(self):
        self.prepare(); archive=Path(self.config['initial_transition']['recovery']['archive']); archive.write_bytes(b'changed')
        self.assertEqual(self.activate()['reason'],'recovery_archive_changed'); self.assertTrue(archive.exists()); self.assert_no_up()

    def test_partial_activation_records_unknown_and_consumes_approval(self):
        self.prepare(); approval=self.approval()
        replace=self.docker.replace_api
        def partial(override):
            replace(override); raise Rejected('owner_command_failed')
        self.docker.replace_api=partial
        result=self.activate(approval)
        self.assertEqual(result,dict(state='UNKNOWN',reason='owner_command_failed',activation_attempted=True))
        self.assertEqual(read_private(self.state / transition.JOURNAL)['recovery'],'review_required')
        with self.assertRaisesRegex(Rejected,'verification_not_authorized'): self.verify()
        with self.assertRaisesRegex(Rejected,'activation_not_retryable'): self.activate(approval)
        self.assertFalse((self.state/(self.f.sha+'.provenance.json')).exists())
        self.assertTrue(Path(self.config['initial_transition']['recovery']['archive']).exists())

    def test_verification_before_activation_never_passes(self):
        self.prepare()
        with self.assertRaisesRegex(Rejected,'verification_not_authorized'): self.verify()

    def test_atomic_publication_failure_never_passes(self):
        self.prepare(); self.activate()
        original=transition.publish
        def fail_receipt(path,value,**kwargs):
            if Path(path).parent == Path(self.config['report_root']): raise OSError('synthetic failure')
            return original(path,value,**kwargs)
        with patch.object(transition,'publish',side_effect=fail_receipt): result=self.verify()
        self.assertEqual(result['state'],'UNKNOWN')
        self.assertEqual(list(Path(self.config['report_root']).iterdir()),[])
        self.config['commissioned']=True
        with self.assertRaisesRegex(Rejected,'initial_transition_not_verified'):
            reconcile(self.config,self.f.p,self.f.owner,self.f.repo,self.head)

    def test_journal_publication_failure_never_exposes_success_receipt(self):
        self.prepare(); self.activate(); original=transition.publish
        def fail_completion(path,value,**kwargs):
            if Path(path).name==transition.JOURNAL and value.get('state')=='VERIFIED':
                raise OSError('synthetic journal failure')
            return original(path,value,**kwargs)
        with patch.object(transition,'publish',side_effect=fail_completion): result=self.verify()
        self.assertEqual(result['state'],'UNKNOWN')
        self.assertEqual(list(Path(self.config['report_root']).iterdir()),[])
        self.assertEqual(read_private(self.state/'initial-failure.json')['activation_attempted'],True)
        self.assertEqual((self.state/'initial-failure.json').stat().st_mode & 0o777,0o400)

    def test_immutable_private_artifacts(self):
        self.prepare()
        path=self.state/'initial-plan.json'
        self.assertEqual(path.stat().st_mode & 0o777,0o400)
        with self.assertRaises(FileExistsError): publish(path,{},immutable=True)
        self.assertEqual(list(self.state.glob('.pending-*')),[])

    def test_protected_symlink_and_parent_symlink(self):
        path=self.f.root/'link'; path.symlink_to(self.state,target_is_directory=True)
        with self.assertRaisesRegex(Rejected,'protected_path_invalid'): protected(path,directory=True)
        with self.assertRaisesRegex(Rejected,'protected_path_invalid'): protected(path/'initial-plan.json')

    def test_protected_lock_symlink(self):
        (self.state/'.owner.lock').symlink_to(self.f.root/'victim')
        with self.assertRaisesRegex(Rejected,'protected_path_invalid'): self.prepare()

    def test_world_readable_approval(self):
        self.prepare(); approval=self.approval(); approval.chmod(0o644)
        self.assertEqual(self.activate(approval)['reason'],'protected_permissions_invalid'); self.assert_no_up()

    def test_mutable_git_cli_is_blocked(self):
        with self.assertRaisesRegex(Rejected,'privileged_code_not_installed'): transition.installed_code()


def precondition_case(mutate, expected):
    def test(self):
        self.prepare(); mutate(self)
        self.assertEqual(self.activate()['reason'],expected); self.assert_no_up()
    return test


def verification_case(mutate, expected):
    def test(self):
        self.prepare(); self.activate(); mutate(self)
        result=self.verify()
        self.assertEqual(result['state'],'FAILED'); self.assertEqual(result['reason'],expected)
        self.assertFalse((self.state/(self.f.sha+'.provenance.json')).exists())
        self.assertEqual(list(Path(self.config['report_root']).iterdir()),[])
    return test


def drift_api(self,key,value): self.f.live['api'][key]=value

def retirement_failure(self): self.docker.retirement=unittest.mock.Mock(side_effect=Rejected('legacy_dispatcher_not_retired'))

for name, mutate, expected in (
    ('daemon_identity',lambda s:setattr(s.docker,'command',lambda argv,**kw: b'changed' if 'info' in argv and argv[-1]=='{{.ID}}' else s.f.command(argv,**kw)),'wrong_docker_daemon'),
    ('api_container_identity',lambda s:drift_api(s,'id','f'*64),'initial_legacy_identity_changed'),
    ('compose_layer',lambda s:Path(s.config['compose_layers'][0]['path']).write_bytes(b'changed'),'compose_layer_changed'),
    ('network_drift',lambda s:s.f.live['api']['networks']['synthetic_internal'].update(id='changed'),'running_relationship_drift'),
    ('mount_drift',lambda s:s.f.live['api']['mounts'].append({'Source':'/unexpected','Destination':'/x'}),'running_relationship_drift'),
    ('volume_drift',lambda s:s.f.objects['volume']['synthetic_clamav'].update(id='changed'),'running_resource_drift'),
    ('second_replica',lambda s:s.f.extra_ids.append('f'*64),'unexpected_project_container'),
    ('support_container',lambda s:s.f.live['caddy'].update(id='f'*64),'support_image_or_container_drift'),
    ('financial_retirement',retirement_failure,'legacy_dispatcher_not_retired'),
    ('override_support_change',lambda s:setattr(s.f,'change_override_service','caddy'),'override_changes_unrelated_service'),
): setattr(TransitionTests,'test_activation_rejects_'+name,precondition_case(mutate,expected))

for name, mutate, expected in (
    ('unhealthy_api',lambda s:s.f.live['api']['state']['Health'].update(Status='unhealthy'),'support_service_unhealthy'),
    ('public_readiness',lambda s:s.enterContext(patch('ingestion_owner.read_json',return_value={'status':'failed'})),'public_service_not_ready'),
    ('support_change',lambda s:s.f.live['caddy'].update(id='f'*64),'support_image_or_container_drift'),
    ('financial_retirement',retirement_failure,'legacy_dispatcher_not_retired'),
    ('nonroot_user',lambda s:s.f.live['api']['security'].update(user='0'),'running_relationship_drift'),
    ('wrong_running_image',lambda s:drift_api(s,'image',transition.LEGACY),'running_image_mismatch'),
    ('entrypoint',lambda s:drift_api(s,'entrypoint',['unauthorized']),'running_relationship_drift'),
    ('multiple_workers',lambda s:drift_api(s,'command',API_COMMAND[:-1]+['2']),'running_relationship_drift'),
): setattr(TransitionTests,'test_verification_rejects_'+name,verification_case(mutate,expected))

for name,key,value,expected in (
    ('revision','labels',{'org.opencontainers.image.revision':'f'*40},'image_provenance_mismatch'),
    ('digest','labels',{'org.opencontainers.image.revision':None,'moneybowl.source_digest':'f'*64},'image_provenance_mismatch'),
    ('entrypoint','entrypoint',['unauthorized'],'single_worker_command_required'),
    ('command','command',['uvicorn','other:app'],'single_worker_command_required'),
    ('multiple_workers','command',API_COMMAND[:-1]+['2'],'single_worker_command_required'),
    ('root','user','0','candidate_runtime_invalid'),
):
    def test(self,key=key,value=value,expected=expected):
        self.f.images[transition.proof_for(self.config)['image']][key]=value
        with self.assertRaisesRegex(Rejected,expected): self.prepare()
        self.assert_no_up()
    setattr(TransitionTests,'test_candidate_rejects_'+name,test)


class RegistryTests(unittest.TestCase):
    def setUp(self):
        synthetic_root_authority(self)
        import tempfile
        tmp=tempfile.TemporaryDirectory(); self.addCleanup(tmp.cleanup)
        self.root=Path(tmp.name); auth=self.root/'auth'; auth.mkdir(mode=0o700)
        publish(auth/'config.json',{'auths':{'ghcr.io':{'auth':base64.b64encode(b'owner:synthetic-private-token').decode()}}})
        self.config=dict(image_repository='ghcr.io/owner/api',docker_config=str(auth),registry=dict(
            repository='ghcr.io/owner/api',private=True,approval='registry-owner-review',
            token_endpoint='https://ghcr.io/token',service='ghcr.io'))
        self.runtime=dict(architecture='arm64',os='linux',config=dict(User='10001:10001',Cmd=API_COMMAND,
            Labels={'org.opencontainers.image.revision':'a'*40,'moneybowl.source_digest':'b'*64}))
        self.calls=[]; self.public=False; self.missing=False; self.corrupt=False; self.layer_missing=False
        self.prepare_remote()

    def prepare_remote(self,index=False):
        raw=json.dumps(self.runtime).encode(); config_digest='sha256:'+sha256(raw)
        manifest=json.dumps(dict(schemaVersion=2,config=dict(digest=config_digest,size=len(raw)),
            layers=[dict(digest='sha256:'+'c'*64,size=100)])).encode()
        self.config_digest=config_digest
        root='sha256:'+sha256(manifest)
        self.objects={config_digest:raw,root:manifest}
        if index:
            raw_index=json.dumps(dict(schemaVersion=2,manifests=[dict(digest=root,size=len(manifest),
                platform=dict(os='linux',architecture='arm64'))])).encode()
            root='sha256:'+sha256(raw_index); self.objects[root]=raw_index
        self.proof=dict(image=self.config['image_repository']+'@'+root,image_id=root,git_commit='a'*40,source_digest='b'*64)
        self.registry=Registry(self.config,request=self.request)

    def request(self,url,headers,method='GET'):
        self.calls.append((url,headers.copy()))
        if '/token?' in url:
            self.assertIn('scope=repository%3Aowner%2Fapi%3Apull',url)
            return 200,json.dumps({'token':'private-token' if 'Authorization' in headers else 'anonymous-token'}).encode()
        if headers.get('Authorization')=='Bearer anonymous-token': return (200 if self.public else 403),b''
        if self.missing:return 404,b''
        if method == 'HEAD': return (404 if self.layer_missing else 200),b''
        digest=url.rsplit('/',1)[1]
        raw=self.objects[digest]
        return 200,(raw+b' ' if self.corrupt else raw)

    def test_remote_single_manifest_and_index(self):
        for index in (False,True):
            self.prepare_remote(index)
            result=self.registry.verify(self.proof)
            self.assertTrue(result['remote_verified']); self.assertTrue(result['private'])
            self.assertEqual(result['config_digest'],self.config_digest)
        self.assertFalse(any('Basic ' in headers.get('Authorization','') for url,headers in self.calls if '/token?' not in url))

    def test_missing_remote_layer(self):
        self.layer_missing=True
        with self.assertRaisesRegex(Rejected,'registry_layer_unpublished'):self.registry.verify(self.proof)

    def test_blob_redirect_drops_authorization_and_requires_allowlist(self):
        self.config['registry']['blob_redirect_hosts']=['blobs.private.invalid']
        with patch('private_registry.urllib.request.build_opener') as build:
            response=build.return_value.open.return_value.__enter__.return_value
            response.status=200; response.read.return_value=b'{}'
            self.registry.http('https://ghcr.io/v2/owner/api/blobs/sha256:'+'a'*64,{'Authorization':'Bearer secret'})
            handler=build.call_args.args[1]
        request=urllib.request.Request('https://ghcr.io/v2/owner/api/blobs/sha256:'+'a'*64,
                                      headers={'Authorization':'Bearer secret'})
        redirected=handler.redirect_request(request,None,307,'',{},'https://blobs.private.invalid/config?signature=synthetic')
        self.assertFalse(redirected.has_header('Authorization'))
        for target in ('http://blobs.private.invalid/config','https://attacker.invalid/config',
                       'https://user:password@blobs.private.invalid/config'):
            with self.assertRaisesRegex(Rejected,'registry_redirect_rejected'):
                handler.redirect_request(request,None,307,'',{},target)

    def test_regular_owner_requires_remote_verification(self):
        owner=object.__new__(transition.DockerOwner)
        owner.registry=unittest.mock.Mock(); owner.registry.verify.side_effect=Rejected('registry_digest_unpublished')
        owner.image=unittest.mock.Mock()
        with self.assertRaisesRegex(Rejected,'registry_digest_unpublished'):owner.verify_image(self.proof)
        owner.image.assert_not_called()

    def test_missing_credentials(self):
        (Path(self.config['docker_config'])/'config.json').unlink()
        with self.assertRaisesRegex(Rejected,'registry_credentials_missing'):self.registry.verify(self.proof)

    def test_missing_remote_publication(self):
        self.missing=True
        with self.assertRaisesRegex(Rejected,'registry_digest_unpublished'):self.registry.verify(self.proof)

    def test_local_image_digest_is_insufficient(self):
        self.proof['image']='moneybowl/m4-ingestion-review@sha256:'+'a'*64
        with self.assertRaisesRegex(Rejected,'registry_digest_missing'):self.registry.verify(self.proof)

    def test_repository_must_be_private(self):
        self.public=True
        with self.assertRaisesRegex(Rejected,'registry_repository_not_private'):self.registry.verify(self.proof)

    def test_remote_content_digest_mismatch(self):
        self.corrupt=True
        with self.assertRaisesRegex(Rejected,'registry_content_mismatch'):self.registry.verify(self.proof)

    def test_remote_image_id_mismatch(self):
        self.proof['image_id']='sha256:'+'e'*64
        with self.assertRaisesRegex(Rejected,'registry_image_id_mismatch'):self.registry.verify(self.proof)

    def test_remote_source_labels_invalid(self):
        self.runtime['config']['Labels']['moneybowl.source_digest']='f'*64; self.prepare_remote()
        with self.assertRaisesRegex(Rejected,'registry_provenance_mismatch'):self.registry.verify(self.proof)

    def test_remote_nonempty_entrypoint(self):
        self.runtime['config']['Entrypoint']=['unauthorized']; self.prepare_remote()
        with self.assertRaisesRegex(Rejected,'registry_runtime_invalid'):self.registry.verify(self.proof)

    def test_registry_not_provisioned(self):
        self.config['registry']['approval']=None
        with self.assertRaisesRegex(Rejected,'registry_not_commissioned'):Registry(self.config,request=self.request)

    def test_credentials_scope_rejected(self):
        publish(Path(self.config['docker_config'])/'config.json',{'auths':{'other.invalid':{'auth':'secret'}}})
        with self.assertRaisesRegex(Rejected,'registry_auth_scope_invalid'):self.registry.verify(self.proof)


if __name__ == '__main__': unittest.main()
