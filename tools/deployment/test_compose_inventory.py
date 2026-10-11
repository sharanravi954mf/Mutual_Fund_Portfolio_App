"""Synthetic four/five-layer DEV stack. Never invokes Docker or reads host config."""
import copy
import json
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

import compose_inventory as inventory
from contract import Rejected, load_policy, manifest
from ingestion_owner import API_COMMAND, DockerOwner, reconcile
from service_manifest import service_manifest
from test_owners import SourceFixture


class ComposeInventoryTests(SourceFixture):
    def setUp(self):
        super().setUp()
        self.compose = self.root / 'compose'; self.compose.mkdir()
        self.runtime = self.root / 'runtime'; self.runtime.mkdir()
        (self.repo / 'services/ingestion-support/compose.m3b.yaml').write_text('reviewed M3B')
        self.sha = self.commit()
        layers = (
            ('base', str(self.compose / 'compose.yaml'), 'ingestion'),
            ('hosted', str(self.compose / 'compose.hosted.yaml'), 'ingestion'),
            ('flutter', str(self.runtime / 'compose.web-dev.yaml'), 'flutter'),
            ('m3b', str(self.runtime / 'compose.m3b.yaml'), 'director-m3b'),
            ('m3b-ingress', str(self.runtime / 'compose.m3b-ingress-adapter.yaml'), 'director-m3b'),
        )
        artifacts = {str(self.runtime / 'Caddyfile'): 'flutter', str(self.runtime / 'receiver.py'): 'flutter'}
        for name, value in (('DEV_ROOT', str(self.compose)), ('DEV_LAYERS', layers),
                            ('HISTORICAL_M3B', str(self.compose / 'compose.m3b.yaml')), ('DEV_ARTIFACTS', artifacts)):
            p = patch.object(inventory, name, value); p.start(); self.addCleanup(p.stop)
        self.config.update(compose_root=str(self.compose), compose_project='moneybowl-ingestion-support',
                           compose_env=str(self.root / 'never-read-private.env'), docker_socket='unix:///var/run/docker.sock',
                           daemon_id='synthetic-daemon', docker_data_root=str(self.root),
                           retired_container_id='c'*64, image_repository='registry.invalid/api',
                           service_origin='https://service.invalid', compose_layers=[], compose_artifacts=[])
        for role, path, authority in layers:
            p = Path(path)
            p.write_bytes((self.repo / 'services/ingestion-support' / p.name).read_bytes()
                         if role in ('base', 'hosted', 'm3b') else role.encode())
            item = dict(role=role, path=path, authority=authority, sha256=inventory.sha256(p.read_bytes()), approval='review-001',
                        uid=p.stat().st_uid, mode=p.stat().st_mode & 0o777)
            if role == 'm3b': item['origin'] = dict(revision=self.sha, path='services/ingestion-support/compose.m3b.yaml')
            self.config['compose_layers'].append(item)
        (self.compose / 'Caddyfile').write_bytes((self.repo / 'services/ingestion-support/Caddyfile').read_bytes())
        for path, authority in artifacts.items():
            Path(path).write_text('synthetic public config')
            self.config['compose_artifacts'].append(dict(path=path, authority=authority, approval='review-001',
                                                        uid=Path(path).stat().st_uid, mode=Path(path).stat().st_mode & 0o777,
                                                        sha256=inventory.sha256(Path(path).read_bytes())))
        self.names = inventory.services(self.config)
        self.model = dict(name=self.config['compose_project'], services={name: {} for name in self.names},
                          networks={'internal': {'name': 'synthetic_internal'}, 'm3b': {'name': 'synthetic_m3b'}},
                          volumes={'clamav': {'name': 'synthetic_clamav'}, 'caddy': {'name': 'synthetic_caddy'}})
        self.model['services']['outbox-dispatcher'] = {'profiles': ['outbox-dispatch']}
        self.hashes = {name: inventory.sha256(name.encode()) for name in self.names}
        self.live = {}; self.images = {}; self.config['compose_services'] = {}
        for i, name in enumerate(sorted(self.names)):
            image = 'sha256:' + str(i+1)*64
            ref = 'registry.invalid/' + name + '@' + image
            historical = [item['path'] for item in self.config['compose_layers']]
            if name in ('api', 'm3b-receiver'): historical = historical[:3] + [inventory.HISTORICAL_M3B]
            if name == 'clamav': historical = historical[:2]
            if name == 'github-webhook': historical = historical[:3]
            labels = {'com.docker.compose.project': self.config['compose_project'], 'com.docker.compose.service': name,
                      'com.docker.compose.project.working_dir': str(self.compose), 'com.docker.compose.oneoff': 'False',
                      'com.docker.compose.project.config_files': ','.join(historical),
                      'com.docker.compose.config-hash': self.hashes[name]}
            value = dict(id=str(i+1)*64, image=image, labels=labels, command=API_COMMAND if name=='api' else ['synthetic'],
                         entrypoint=None, restart='unless-stopped', mounts=[], ports={}, security={'privileged': False},
                         networks={'synthetic_internal': {'id': 'network-id', 'aliases': [name]}},
                         state={'Running': True, 'Health': {'Status': None if name in ('caddy','m3b-ingress-adapter') else 'healthy'}})
            self.live[name] = value
            self.config['compose_services'][name] = dict(container_id=value['id'], image_id=image,
                  config_hash=self.hashes[name], runtime_sha256=inventory.runtime_identity(value), recorded_files=','.join(historical))
            self.images[ref] = dict(id=image, digests=[ref], labels={}, command=value['command'], entrypoint=None)
            self.model['services'][name]['image'] = ref
        self.objects = {kind: {v['name']: {'name': v['name'], 'id': v['name'] + '-id'} for v in self.model[kind+'s'].values()}
                        for kind in ('network','volume')}
        self.config['compose_resources'] = {kind: {name: inventory.digest(value) for name,value in objects.items()}
                                           for kind,objects in self.objects.items()}
        self.config['compose_model_sha256'] = inventory.digest(self.model)
        self.calls = []; self.extra_ids = []; self.change_override_service = None; self.up_failure = False
        self.owner = DockerOwner(self.config, command=self.command)
        # Engine object decoding and retirement transport have their own tests; use stable metadata here.
        self.owner.container = lambda id: copy.deepcopy(next(v for v in self.live.values() if v['id']==id))
        self.owner.retirement = lambda: 'retired'
        self.owner.image = lambda ref: copy.deepcopy(self.images[ref])
        ready = patch('ingestion_owner.read_json', return_value={'status': 'ready'})
        ready.start(); self.addCleanup(ready.stop)

    def command(self, argv, **kwargs):
        self.calls.append(argv)
        if 'info' in argv: return (self.config['docker_data_root'] if 'DockerRootDir' in argv[-1] else 'synthetic-daemon').encode()
        if 'ps' in argv:
            selected = next((s.split('=',2)[2] for s in argv if s.startswith('label=com.docker.compose.service=')), None)
            ids = [self.live[selected]['id']] if selected else [v['id'] for v in self.live.values()] + ['c'*64] + self.extra_ids
            return ' '.join(ids).encode()
        if 'config' in argv:
            if '--format' in argv:
                self.assertIn('--no-interpolate', argv); self.assertIn('--no-env-resolution', argv)
                self.assertEqual(argv[argv.index('--env-file')+1], '/dev/null')
                return json.dumps(self.model).encode()
            if '--hash' in argv:
                service=argv[-1]; override=argv[argv.index('config')-1]
                h=self.hashes[service]
                if override.endswith('.json'):
                    if service=='api': h=inventory.sha256(Path(override).read_bytes())
                    if service==self.change_override_service: h='f'*64
                return f'{service} {h}'.encode()
            if '--images' in argv: return self.model['services'][argv[-1]]['image'].encode()
        if 'inspect' in argv:
            kind='network' if 'network' in argv else 'volume'
            return json.dumps(self.objects[kind][argv[-1]]).encode()
        if 'up' in argv:
            if self.up_failure: raise Rejected('owner_command_failed')
            override=Path(argv[argv.index('up')-1]); data=json.loads(override.read_text())['services']['api']
            current=self.live['api']; current['id']='e'*64; current['image']=self.images[data['image']]['id']
            current['labels'].update(data['labels'])
            current['labels']['com.docker.compose.config-hash']=inventory.sha256(override.read_bytes())
            current['labels']['com.docker.compose.project.config_files']=','.join([x['path'] for x in self.config['compose_layers']]+[str(override)])
            return b''
        raise AssertionError('unexpected mocked command')

    def approved_override(self):
        proof=dict(image='registry.invalid/api@sha256:'+'d'*64, image_id='sha256:'+'e'*64,
                   git_commit=self.sha, source_digest=manifest(self.repo,self.sha)['ingestion_support'])
        self.images[proof['image']]=dict(id=proof['image_id'], digests=[proof['image']], command=API_COMMAND,
            entrypoint=None, labels={'org.opencontainers.image.revision':self.sha,'moneybowl.source_digest':proof['source_digest']})
        state=Path(self.config['state_root']);state.mkdir(exist_ok=True)
        (state/(self.sha+'.provenance.json')).write_text(json.dumps(proof))
        override=state/(self.sha+'.compose.json');override.write_text(json.dumps(service_manifest('dev',self.sha,proof['image'],load_policy())))
        return override,proof

    def assert_no_up(self): self.assertFalse(any('up' in argv for argv in self.calls))

    def test_five_layers_preserve_all_existing_owners_and_resources(self):
        before=self.owner.infrastructure(self.repo)
        override,proof=self.approved_override();self.owner.prepare_activation(override,proof)
        with patch.object(self.owner,'capacity'): self.owner.activate(override)
        after=self.owner.infrastructure(self.repo)
        self.assertEqual(before,after)
        with patch('ingestion_owner.read_json',return_value={'status':'ready'}): self.owner.verified(proof,override)
        up=[argv for argv in self.calls if 'up' in argv];self.assertEqual(len(up),1)
        self.assertEqual(up[0][-1],'api')
        self.assertEqual(up[0][up[0].index('up'):],['up','--detach','--no-deps','--no-build','--pull','never','--scale','api=1','--wait','--wait-timeout','120','api'])
        self.assertNotIn('--profile',up[0]);self.assertNotIn('--remove-orphans',up[0])
        with self.assertRaisesRegex(Rejected,'api_activation_not_prepared'): self.owner.activate(override)

    def test_correct_four_layer_inventory(self):
        self.config['compose_layers'].pop()
        for section in (self.live,self.config['compose_services'],self.model['services']): section.pop('m3b-ingress-adapter')
        recorded=','.join(x['path'] for x in self.config['compose_layers'])
        self.live['caddy']['labels']['com.docker.compose.project.config_files']=recorded
        self.config['compose_services']['caddy']['recorded_files']=recorded
        self.config['compose_model_sha256']=inventory.digest(self.model)
        self.owner=DockerOwner(self.config,command=self.command)
        self.owner.container=lambda id:copy.deepcopy(next(v for v in self.live.values() if v['id']==id))
        self.owner.image=lambda ref:copy.deepcopy(self.images[ref]);self.owner.retirement=lambda:'retired'
        self.assertIn('m3b-receiver',self.owner.infrastructure(self.repo));self.assert_no_up()

    def test_wrong_order_paths_authority_or_uncommissioned_inventory(self):
        for field,value in (('path','/unapproved/compose.yaml'),('authority','unapproved'),('approval',''),('sha256','')):
            config=copy.deepcopy(self.config);config['compose_layers'][0][field]=value
            with self.subTest(field=field),self.assertRaises(Rejected): DockerOwner(config,command=self.command)
        for indices in ([1,0,2,3],[0,1],[0,1,2,4]):
            config=copy.deepcopy(self.config);config['compose_layers']=[config['compose_layers'][i] for i in indices]
            with self.assertRaises(Rejected): DockerOwner(config,command=self.command)
        self.assert_no_up()

    def test_missing_relocated_overlay_never_falls_back_to_historical_path(self):
        p=Path(self.config['compose_layers'][3]['path']);data=p.read_bytes();p.unlink()
        Path(inventory.HISTORICAL_M3B).write_bytes(data)
        with self.assertRaisesRegex(Rejected,'compose_layer_missing'):self.owner.infrastructure(self.repo)
        self.assert_no_up()

    def test_substitution_is_rejected_even_with_updated_local_hash(self):
        layer=self.config['compose_layers'][3];Path(layer['path']).write_text('arbitrary replacement')
        with self.assertRaisesRegex(Rejected,'compose_layer_changed'):self.owner.infrastructure(self.repo)
        layer['sha256']=inventory.sha256(Path(layer['path']).read_bytes())
        with self.assertRaisesRegex(Rejected,'m3b_origin_unverified'):self.owner.infrastructure(self.repo)
        self.assert_no_up()

    def test_source_compose_change_requires_separate_review(self):
        (self.repo/'services/ingestion-support/compose.yaml').write_text('new infrastructure')
        with self.assertRaisesRegex(Rejected,'infrastructure_change_requires_commissioning'):self.owner.infrastructure(self.repo)

    def test_changed_mounted_config_or_missing_artifact_binding(self):
        item=self.config['compose_artifacts'][0];Path(item['path']).write_text('changed')
        with self.assertRaisesRegex(Rejected,'compose_artifact_changed'):self.owner.infrastructure(self.repo)
        self.config['compose_artifacts']=[]
        with self.assertRaisesRegex(Rejected,'compose_artifacts_uncommissioned'):self.owner.infrastructure(self.repo)

    def test_unexpected_service_or_container(self):
        self.extra_ids=['f'*64]
        with self.assertRaisesRegex(Rejected,'unexpected_project_container'):self.owner.infrastructure(self.repo)
        self.extra_ids=[];self.model['services']['another-webhook']={}
        with self.assertRaisesRegex(Rejected,'unexpected_compose_service'):self.owner.infrastructure(self.repo)

    def test_project_and_container_ownership(self):
        config={**self.config,'compose_project':'another-project'}
        with self.assertRaisesRegex(Rejected,'compose_project_binding_invalid'):DockerOwner(config,command=self.command)
        for key in ('com.docker.compose.project','com.docker.compose.service','com.docker.compose.project.working_dir','com.docker.compose.project.config_files','com.docker.compose.oneoff'):
            value=self.live['caddy']['labels'][key];self.live['caddy']['labels'][key]='unexpected'
            with self.subTest(key=key),self.assertRaises(Rejected):self.owner.infrastructure(self.repo)
            self.live['caddy']['labels'][key]=value

    def test_network_mount_port_and_security_drift(self):
        for key,value in (('networks',{}),('mounts',[{'Type':'bind','Source':'/wrong','Destination':'/data','RW':True}]),
                          ('ports',{'8080/tcp':[{'HostPort':'8080'}]}),('restart','always'),('security',{'privileged':True})):
            previous=self.live['api'][key];self.live['api'][key]=value
            with self.subTest(key=key),self.assertRaisesRegex(Rejected,'running_relationship_drift'):self.owner.infrastructure(self.repo)
            self.live['api'][key]=previous

    def test_resource_replacement_or_unapproved_resource(self):
        for kind in ('network','volume'):
            name=next(iter(self.objects[kind]));old=copy.deepcopy(self.objects[kind][name]);self.objects[kind][name]['id']='replaced'
            with self.subTest(kind=kind),self.assertRaisesRegex(Rejected,'running_resource_drift'):self.owner.infrastructure(self.repo)
            self.objects[kind][name]=old
        self.model['networks']['extra']={'name':'unapproved'}
        with self.assertRaisesRegex(Rejected,'compose_model_unapproved'):self.owner.infrastructure(self.repo)

    def test_image_config_hash_and_health_drift(self):
        for service in ('api','caddy','clamav','github-webhook','m3b-receiver','m3b-ingress-adapter'):
            old=copy.deepcopy(self.live[service]);self.live[service]['image']='sha256:'+'f'*64
            with self.subTest(service=service),self.assertRaises(Rejected):self.owner.infrastructure(self.repo)
            self.live[service]=copy.deepcopy(old);self.live[service]['labels']['com.docker.compose.config-hash']='0'*64
            with self.assertRaisesRegex(Rejected,'running_configuration_drift'):self.owner.infrastructure(self.repo)
            self.live[service]=copy.deepcopy(old);self.live[service]['state']['Health']['Status']='unhealthy'
            with self.assertRaisesRegex(Rejected,'support_service_unhealthy'):self.owner.infrastructure(self.repo)
            self.live[service]=old

    def test_effective_config_must_match_running_hash(self):
        self.hashes['caddy']='0'*64
        with self.assertRaisesRegex(Rejected,'running_configuration_drift'):self.owner.infrastructure(self.repo)
        self.assert_no_up()

    def test_caddy_readiness_failure_blocks_deployment(self):
        with patch('ingestion_owner.read_json', return_value={'status': 'unavailable'}):
            with self.assertRaisesRegex(Rejected, 'public_service_not_ready'): self.owner.infrastructure(self.repo)
        self.assert_no_up()

    def test_single_worker_and_retired_dependencies(self):
        self.live['api']['command']=API_COMMAND[:-1]+['2']
        with self.assertRaisesRegex(Rejected,'single_worker_command_required'):self.owner.validate_current(self.live['api'])
        self.live['api']['command']=API_COMMAND
        self.model['services']['api']['depends_on']={'outbox-dispatcher':{}}
        with self.assertRaisesRegex(Rejected,'retired_service_dependency'):self.owner.infrastructure(self.repo)
        del self.model['services']['api']['depends_on'];self.model['services']['outbox-dispatcher']['profiles']=[]
        with self.assertRaisesRegex(Rejected,'retired_service_profile_missing'):self.owner.infrastructure(self.repo)

    def test_override_cannot_change_another_service_or_bypass_preparation(self):
        self.owner.infrastructure(self.repo);override,proof=self.approved_override()
        data=json.loads(override.read_text());data['services']['caddy']={'restart':'always'};override.write_text(json.dumps(data))
        with self.assertRaisesRegex(Rejected,'api_override_unapproved'):self.owner.prepare_activation(override,proof)
        override,proof=self.approved_override();self.change_override_service='caddy'
        with self.assertRaisesRegex(Rejected,'override_changes_unrelated_service'):self.owner.prepare_activation(override,proof)
        with self.assertRaisesRegex(Rejected,'api_activation_not_prepared'):self.owner.activate(override)
        self.assert_no_up()

    def test_changed_host_or_override_after_preparation(self):
        self.owner.infrastructure(self.repo);override,proof=self.approved_override();self.owner.prepare_activation(override,proof)
        override.write_text('{}')
        with self.assertRaisesRegex(Rejected,'api_activation_not_prepared'):self.owner.activate(override)
        override,proof=self.approved_override();self.owner.prepare_activation(override,proof)
        self.live['m3b-receiver']['id']='f'*64
        with patch.object(self.owner,'capacity'),self.assertRaises(Rejected):self.owner.activate(override)
        self.assert_no_up()

    def test_api_failure_does_not_retry_or_mutate_support_services(self):
        before=copy.deepcopy(self.live);self.owner.infrastructure(self.repo)
        override,proof=self.approved_override();self.owner.prepare_activation(override,proof);self.up_failure=True
        with patch.object(self.owner,'capacity'),self.assertRaisesRegex(Rejected,'owner_command_failed'):self.owner.activate(override)
        self.assertEqual(self.live,before);self.assertEqual(sum('up' in a for a in self.calls),1)
        with self.assertRaisesRegex(Rejected,'api_activation_not_prepared'):self.owner.activate(override)

    def test_legacy_source_must_have_independent_historical_record(self):
        self.config.update(initial_revision=self.sha,initial_image_id=self.live['api']['image'])
        with self.assertRaisesRegex(Rejected,'legacy_provenance_unverified'):inventory.initial_revision(self.config,self.live['api'],self.repo)
        record=dict(kind='historical-build-record',authority='synthetic-build-archive',git_commit=self.sha,
                    source_digest=manifest(self.repo,self.sha)['ingestion_support'],image_id=self.live['api']['image'])
        path=self.root/'proof.json';path.write_text(json.dumps(record));path.chmod(0o600)
        self.config['initial_provenance']=dict(path=str(path),sha256=inventory.sha256(path.read_bytes()))
        self.assertEqual(inventory.initial_revision(self.config,self.live['api'],self.repo),self.sha)
        path.write_text('{}')
        with self.assertRaisesRegex(Rejected,'legacy_provenance_unverified'):inventory.initial_revision(self.config,self.live['api'],self.repo)

    def test_qa_and_production_are_rejected_before_docker(self):
        for env in ('qa','prod'):
            with self.assertRaisesRegex(Rejected,'compose_environment_not_commissioned'):DockerOwner({**self.config,'environment':env},command=self.command)
        self.assertEqual(self.calls,[])

    def test_low_disk_or_inodes_prevents_build_and_activation(self):
        good=dict(f_blocks=100*1024**3,f_frsize=1,f_bavail=30*1024**3,f_files=1_000_000,f_favail=800_000)
        inventory.capacity(self.config,stat=lambda _:SimpleNamespace(**good))
        for key,value in (('f_bavail',3*1024**3),('f_favail',50_000),('f_files',0)):
            with self.subTest(key=key),self.assertRaises(Rejected):inventory.capacity(self.config,stat=lambda _:SimpleNamespace(**{**good,key:value}))
        with patch('compose_inventory.capacity',side_effect=Rejected('insufficient_build_capacity')):
            with self.assertRaisesRegex(Rejected,'insufficient_build_capacity'):self.owner.build(self.repo,self.sha,'a'*64)
            self.assertFalse(any('build' in a for a in self.calls))
            self.owner.infrastructure(self.repo);override,proof=self.approved_override();self.owner.prepare_activation(override,proof)
            with self.assertRaisesRegex(Rejected,'insufficient_build_capacity'):self.owner.activate(override)
            self.assert_no_up()

    def test_concurrent_full_owner_calls_build_and_activate_only_once(self):
        from concurrent.futures import ThreadPoolExecutor
        record = dict(kind='historical-build-record', authority='synthetic-archive', git_commit=self.sha,
                      source_digest=manifest(self.repo, self.sha)['ingestion_support'], image_id=self.live['api']['image'])
        path = self.root / 'historical.json'; path.write_text(json.dumps(record)); path.chmod(0o600)
        self.config['initial_provenance'] = dict(path=str(path), sha256=inventory.sha256(path.read_bytes()))
        builds = []
        def build(source, sha, source_digest):
            builds.append(sha)
            return self.approved_override()[1]
        with patch.object(self.owner, 'capacity'), patch.object(self.owner, 'build', side_effect=build), \
             patch('ingestion_owner.read_json', return_value={'status': 'ready'}), ThreadPoolExecutor(max_workers=3) as pool:
            results = list(pool.map(lambda _: reconcile(self.config, self.p, self.owner, self.repo, lambda: self.sha), range(3)))
        self.assertTrue(all(result['state'] == 'deployed' for result in results))
        self.assertEqual(builds, [self.sha]); self.assertEqual(sum('up' in argv for argv in self.calls), 1)

    def test_forged_current_revision_without_owner_ledger_fails(self):
        self.live['api']['labels']['org.opencontainers.image.revision'] = self.sha
        with self.assertRaises(FileNotFoundError): self.owner.infrastructure(self.repo)
        self.assert_no_up()

    def test_missing_historical_path_is_accepted_only_with_exact_archived_relocation(self):
        self.assertFalse(Path(inventory.HISTORICAL_M3B).exists())
        self.owner.infrastructure(self.repo)
        layer = self.config['compose_layers'][3]
        layer['origin']['revision'] = 'f' * 40
        with self.assertRaises(Rejected): self.owner.infrastructure(self.repo)
        self.assert_no_up()

    def test_reviewed_layer_symlink_is_not_an_approved_file(self):
        layer = self.config['compose_layers'][2]; p = Path(layer['path'])
        saved = p.with_suffix('.saved'); p.rename(saved); p.symlink_to(saved)
        with self.assertRaisesRegex(Rejected, 'compose_layer_missing_or_linked'): self.owner.infrastructure(self.repo)

    def test_file_authority_changes_are_rejected(self):
        layer = self.config['compose_layers'][2]
        layer['uid'] += 1
        with self.assertRaisesRegex(Rejected, 'compose_file_authority_changed'): self.owner.infrastructure(self.repo)
        layer['uid'] -= 1
        Path(layer['path']).chmod(0o666)
        with self.assertRaisesRegex(Rejected, 'compose_file_authority_changed'): self.owner.infrastructure(self.repo)

    def test_supplied_record_cannot_claim_a_requested_sha_as_measurement(self):
        path = self.root / 'not-a-build-record.json'
        record = dict(kind='requested-release', authority='synthetic-ci', image_id=self.live['api']['image'],
                      git_commit=self.sha, source_digest=manifest(self.repo, self.sha)['ingestion_support'])
        path.write_text(json.dumps(record)); path.chmod(0o600)
        self.config['initial_provenance'] = dict(path=str(path), sha256=inventory.sha256(path.read_bytes()))
        with self.assertRaisesRegex(Rejected, 'initial_image_binding_mismatch'): inventory.initial_revision(self.config, self.live['api'], self.repo)

    def test_real_constructor_requires_the_reviewed_compose_plugin(self):
        config = {**self.config, 'docker_config': '/synthetic/no-auth'}
        with patch('ingestion_owner.pinned_executable', side_effect=lambda c, key: '/synthetic/' + key), \
             patch('ingestion_owner.Command', return_value=lambda *args, **kw: b'/unreviewed/compose'):
            with self.assertRaisesRegex(Rejected, 'compose_plugin_binding_invalid'): DockerOwner(config)


if __name__=='__main__':unittest.main()
