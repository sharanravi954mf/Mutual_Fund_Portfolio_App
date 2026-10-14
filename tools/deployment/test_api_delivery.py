"""Complete synthetic provider integration; no live providers or privileged state.

Real OCI, publication, policy, journal, initial-integrity and Engine-operation
adapters run. Only provider/OS transports and fixture ownership are simulated.
The gh process boundary is simulated, not claimed as a Sigstore live validation.
"""
import array
import copy
import hashlib
import hmac
import io
import json
import os
import re
import socket
import stat
import struct
import subprocess
import tarfile
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch, Mock

import api_broker as broker
import api_executor as executor
import delivery_verifier as verifier
import oci_delivery as oci
import private_registry
from contract import Rejected, manifest, git
from protected_io import publish, read_private, deployment_lock
from restricted_execution import encoded
import test_initial_api_transition as initial_tests
NOW = initial_tests.NOW


def archive(path, sha, component, edit=None):
    config = {'architecture': 'arm64', 'os': 'linux', 'config': {'User': '10001:10001',
        'Cmd': oci.COMMAND, 'Entrypoint': None, 'WorkingDir': '/app', 'Env': ['PATH=/usr/local/bin:/usr/bin:/bin'],
        'Labels': {'org.opencontainers.image.revision': sha, 'moneybowl.source_digest': component}}}
    if edit: edit(config)
    config_raw = encoded(config)
    layer_file = io.BytesIO()
    with tarfile.open(fileobj=layer_file, mode='w', format=tarfile.USTAR_FORMAT) as tar:
        info = tarfile.TarInfo('app/synthetic-source.txt'); data = sha.encode(); info.size = len(data)
        tar.addfile(info, io.BytesIO(data))
    layer = layer_file.getvalue()
    descriptor = lambda raw, kind: {'digest': oci.digest(raw), 'size': len(raw), 'mediaType': kind}
    image = dict(schemaVersion=2, mediaType=oci.MANIFEST, config=descriptor(config_raw, oci.CONFIG),
                 layers=[descriptor(layer, 'application/vnd.oci.image.layer.v1.tar')])
    image_raw = encoded(image)
    index = dict(schemaVersion=2, mediaType=oci.INDEX, manifests=[{
        **descriptor(image_raw, oci.MANIFEST), 'platform': {'os': 'linux', 'architecture': 'arm64'}}])
    blobs = {'oci-layout': encoded({'imageLayoutVersion': '1.0.0'}), 'index.json': encoded(index),
             'blobs/sha256/' + oci.digest(config_raw)[7:]: config_raw,
             'blobs/sha256/' + oci.digest(layer)[7:]: layer,
             'blobs/sha256/' + oci.digest(image_raw)[7:]: image_raw}
    with tarfile.open(path, 'w', format=tarfile.USTAR_FORMAT) as tar:
        for name, raw in blobs.items():
            info = tarfile.TarInfo(name); info.size = len(raw); tar.addfile(info, io.BytesIO(raw))
    return blobs, image


def runtime():
    return {'name': 'moneybowl-ingestion-support', 'services': {'api': {
        'image': executor.INITIAL_IMAGE, 'user': '10001:10001', 'command': oci.COMMAND,
        'entrypoint': [], 'restart': 'unless-stopped', 'environment': {'CLAMAV_HOST': 'clamav', 'TEST_INPUT': 'synthetic'},
        'cap_drop': ['ALL'], 'cpus': 1.0, 'mem_limit': '512m', 'pids_limit': 128,
        'security_opt': ['no-new-privileges:true'], 'read_only': True,
        'tmpfs': ['/tmp:size=16m,mode=1777'], 'ports': ['127.0.0.1:8080:8080'],
        'networks': {'internal': {'aliases': []}}, 'labels': {'moneybowl.environment': 'dev'},
        'healthcheck': {'test': ['CMD', 'python', '-c', "import urllib.request; urllib.request.urlopen('http://localhost:8080/ready', timeout=3).read()"],
            'interval': '10s', 'timeout': '5s', 'retries': 12, 'start_period': '10s'}}},
        'networks': {'internal': {'external': True, 'name': 'synthetic_internal'}}}


class Providers:
    def __init__(self, fixture):
        self.f = fixture
        self.sha = fixture.sha
        self.head = self.sha
        self.run = dict(id=123, run_attempt=1, event='push', head_branch='develop', head_sha=self.sha,
                        path=oci.WORKFLOW, status='completed', conclusion='success',
                        repository={'full_name': oci.REPOSITORY, 'id': 123456},
                        head_repository={'full_name': oci.REPOSITORY, 'fork': False})
        self.jobs = {'total_count': 3, 'jobs': [dict(name=name, labels=[label], status='completed', conclusion='success')
            for name, label in [('M4 Required CI', 'ubuntu-latest'), ('M4 Isolated ARM64 Build', 'ubuntu-24.04-arm'),
                                ('M4 Verified Private Publication', 'ubuntu-latest')]]}
        self.calls = []
        self.remote = {}
        self.proof = None
        self.seal_key = b'synthetic verifier fixture only; not a production trust root'
        self.authenticated_statement = None
        self.broken_signature = False

    def json(self, value):
        return 200, {}, encoded(value)

    def http(self, url, headers=None, method='GET', data=None):
        self.calls.append((url, method))
        if url.startswith('https://api.github.com/'):
            route = url.split('/' + oci.REPOSITORY + '/', 1)[1]
            if route.startswith('commits/'):
                return self.json([dict(number=42, merged_at='2026-10-14T00:00:00Z', merge_commit_sha=self.sha,
                    base={'ref': 'develop', 'repo': {'full_name': oci.REPOSITORY}},
                    head={'sha': self.sha, 'ref': 'feature/synthetic', 'repo': {'full_name': oci.REPOSITORY}})])
            if route.startswith('pulls/42/reviews'):
                return self.json([dict(user={'login': 'independent-reviewer', 'id': 9876}, state='APPROVED', commit_id=self.sha)])
            if route == 'git/ref/heads/develop': return self.json({'object': {'sha': self.head}})
            if route.startswith('git/trees/'):
                entries = []
                for line in git(self.f.repo, 'ls-tree', '-r', self.sha).decode().splitlines():
                    record, path = line.split('\t'); mode, kind, sha = record.split()
                    entries.append(dict(path=path, mode=mode, type=kind, sha=sha))
                return self.json(dict(truncated=False, tree=entries))
            if '/jobs?' in route: return self.json(self.jobs)
            if '/artifacts?' in route: return self.json(dict(total_count=1, artifacts=[dict(id=456,
                name=f'api-identity-{self.sha}-1', expired=False, size_in_bytes=256)]))
            if route.startswith('actions/runs?'): return self.json(dict(total_count=1, workflow_runs=[self.run]))
            if route.startswith('actions/runs/123'): return self.json(self.run)
            raise AssertionError('Unexpected GitHub API read: ' + route)
        if url.startswith('https://ghcr.io/token'):
            if not headers or not headers.get('Authorization'): return 403, {}, b''
            return self.json({'token': 'synthetic-pull-or-push-token'})
        base = 'https://ghcr.io/v2/sharanravi954mf/moneybowl-ingestion-dev/'
        self.f.assertTrue(url.startswith(base))
        route = url[len(base):]
        if not headers or not headers.get('Authorization'): return 401, {}, b''
        if method == 'POST': return 202, {'Location': base + 'blobs/uploads/synthetic-upload'}, b''
        if method == 'PUT' and route.startswith('blobs/uploads/'):
            digest = __import__('urllib.parse', fromlist=['parse_qs']).parse_qs(url.split('?', 1)[1])['digest'][0]
            self.f.assertEqual(oci.digest(data), digest)
            self.remote['blobs/' + digest] = data
            return 201, {}, b''
        if method == 'PUT' and route.startswith('manifests/'):
            self.f.assertEqual(oci.digest(data), route.split('/', 1)[1])
            self.remote[route] = data
            return 201, {}, b''
        if route in self.remote: return 200, {}, b'' if method == 'HEAD' else self.remote[route]
        return 404, {}, b''

    def registry_request(self, url, headers, method='GET'):
        status, _, raw = self.http(url, headers, method)
        return status, raw

    def authenticate(self, proof):
        self.proof = proof
        statement = dict(subject=[{'name': oci.IMAGE, 'digest': {'sha256': proof['manifest_digest'][7:]}}],
                         predicateType=oci.PREDICATE, predicate=proof)
        raw = encoded(statement)
        self.authenticated_statement = (raw, hmac.digest(self.seal_key, raw, 'sha256'))

    def gh_output(self):
        raw, signature = self.authenticated_statement
        if self.broken_signature: signature = b'forged'
        if not hmac.compare_digest(signature, hmac.digest(self.seal_key, raw, 'sha256')):
            raise Rejected('executor_delivery_unknown')
        # Test model of successfully verified gh stdout. This is never consumed by
        # production entrypoints or persisted as a real Sigstore bundle/receipt.
        return encoded_list([dict(verificationResult=dict(statement=json.loads(raw),
            signature={'certificate': {'synthetic': True}}, verifiedTimestamps=[{'synthetic': True}]))])


def encoded_list(value):
    return json.dumps(value, sort_keys=True).encode()


class EngineTransport:
    verify_attestation = executor.Process.verify_attestation

    def __init__(self, fixture, providers):
        self.f, self.providers = fixture, providers
        self.tools = {k: '/usr/bin/' + k for k in ('docker', 'compose_plugin', 'systemctl', 'gh', 'git')}
        self.calls, self.activations = [], 0
        self.fail, self.after_change = None, None
        self.capacity_error = False
        self.environment = ['CLAMAV_HOST=clamav', 'TEST_INPUT=synthetic', 'PATH=/usr/local/bin:/usr/bin:/bin']
        self.live = fixture.t.f.live
        self.retired = dict(id='c'*64, image='sha256:'+'9'*64, command=[], entrypoint=None, labels={
            'com.docker.compose.project': 'moneybowl-ingestion-support', 'com.docker.compose.service': 'outbox-dispatcher'},
            state=dict(Status='exited', Running=False, Pid=0, Restarting=False, Paused=False, Dead=False, Health={'Status': None}),
            restart='no', mounts=[], networks={}, ports={}, security={})
        self.config = fixture.t.config
        self.config.update(retired_services=executor.DEV_RETIRED_SERVICES, retired_timers=[executor.DEV_RETIRED_TIMER])
        for i, v in enumerate(self.live.values()):
            v['state'].update(Status='running', Running=True, Pid=1000+i, Restarting=False, Paused=False, Dead=False)
        self.live['api']['security'] = dict(readonly=True, privileged=False, caps=['ALL'],
            options=['no-new-privileges:true'], user='10001:10001')
        self.limits = dict(cpu=1000000000, memory=536870912, pids=128, tmpfs={'/tmp': 'size=16m,mode=1777'})

    def capacity(self):
        if self.capacity_error: raise Rejected('insufficient_build_capacity')

    def artifact(self, run_id, artifact_id):
        self.f.assertEqual((run_id, artifact_id), (123, 456))
        return {'manifest_digest': self.providers.proof['manifest_digest']}

    def __call__(self, argv, **kwargs):
        self.calls.append(argv)
        if argv[0] == self.tools['gh']:
            self.f.assertIn('--deny-self-hosted-runners', argv)
            self.f.assertEqual(argv[argv.index('--source-digest') + 1], self.f.sha)
            self.f.assertIn(oci.REPOSITORY + '/' + oci.WORKFLOW, argv)
            return self.providers.gh_output()
        if argv[0] == self.tools['git']:
            if 'config' in argv: return b'core.bare=true\ncore.repositoryformatversion=0\ncore.filemode=true\n'
            tail = argv[argv.index('fetch'):] if 'fetch' in argv else None
            if tail:
                self.f.assertEqual(tail, ['fetch', '--no-tags', '--no-recurse-submodules',
                    'https://github.com/' + oci.REPOSITORY + '.git', 'develop'])
                return b''
            if 'FETCH_HEAD' in argv: return self.providers.head.encode()
            return subprocess.check_output(argv, stderr=subprocess.DEVNULL)
        if argv[0] == self.tools['systemctl']:
            name = executor.DEV_RETIRED_SERVICES[0][:-8]
            if 'list-unit-files' in argv:
                return '\n'.join(f'{u} {"disabled" if u.endswith(".timer") else "masked"}' for u in
                    executor.DEV_RETIRED_SERVICES + [executor.DEV_RETIRED_TIMER]).encode()
            if 'list-units' in argv: return b''
            if 'show' in argv:
                unit = argv[2]; timer = unit.endswith('.timer')
                return ('Id=' + unit + '\nLoadState=' + ('loaded' if timer else 'masked') +
                    '\nActiveState=inactive\nSubState=dead\nUnitFileState=' + ('disabled' if timer else 'masked')).encode()
        self.f.assertEqual(argv[:3], ['/usr/bin/docker', '--host', 'unix:///var/run/docker.sock'])
        if 'info' in argv:
            if 'DockerRootDir' in argv[-1]: return self.config['docker_data_root'].encode()
            return self.tools['compose_plugin'].encode() if 'ClientInfo' in argv[-1] else b'synthetic-daemon'
        if 'ps' in argv:
            service = next((v.split('=', 2)[2] for v in argv if v.startswith('label=com.docker.compose.service=')), None)
            if service == 'outbox-dispatcher': return self.retired['id'].encode()
            if service: return self.live[service]['id'].encode()
            return ' '.join([v['id'] for v in self.live.values()] + [self.retired['id']]).encode()
        if 'top' in argv: return ('UID COMMAND\n10001 ' + ' '.join(oci.COMMAND)).encode()
        if 'inspect' in argv:
            if 'Config.Env' in argv[-2]: return encoded_list(self.environment)
            if 'image' in argv:
                p = self.providers.proof
                return encoded(dict(id=p['config_digest'], os='linux', architecture='arm64', user='10001:10001',
                    command=oci.COMMAND, entrypoint=None, labels={'org.opencontainers.image.revision': self.f.sha,
                    'moneybowl.source_digest': p['source_digest']}, digests=[p['image']]))
            if 'network' in argv: return encoded_list([{'Id': 'network-id', 'Name': 'synthetic_internal'}])
            if 'NanoCpus' in argv[-2]: return encoded(self.limits)
            name = argv[-1]
            value = self.retired if name in (executor.DEV_RETIRED_CONTAINER, self.retired['id']) else next(v for v in self.live.values() if v['id'] == name)
            value = copy.deepcopy(value)
            value['networks'] = {name: {'NetworkID': v['id'], 'Aliases': v['aliases']} for name, v in value['networks'].items()}
            return encoded(value)
        if 'pull' in argv:
            self.f.assertEqual(argv[3:], ['image', 'pull', '--platform', 'linux/arm64', self.providers.proof['image']])
            if self.fail == 'pull': raise Rejected('executor_delivery_unknown')
            return b''
        if 'up' in argv:
            self.activations += 1
            self.f.assertEqual(argv[-12:], ['up', '--detach', '--no-deps', '--no-build', '--pull', 'never', '--scale', 'api=1',
                                          '--wait', '--wait-timeout', '120', 'api'])
            path = argv[argv.index('-f') + 1]
            self.f.assertRegex(path, r'^/proc/[0-9]+/fd/[0-9]+$')
            fd = int(path.rsplit('/', 1)[1]); self.f.assertEqual(kwargs['pass_fds'], (fd,))
            import fcntl
            self.f.assertTrue(fcntl.fcntl(fd, fcntl.F_GET_SEALS) & fcntl.F_SEAL_WRITE)
            data = json.loads(Path(path).read_bytes())['services']['api']
            self.f.assertEqual(data['command'], oci.COMMAND)
            self.live['api'].update(id='d'*64, image=self.providers.proof['config_digest'])
            self.live['api']['labels'].update(data['labels'])
            if self.after_change: self.after_change(self)
            if self.fail == 'up': raise Rejected('executor_delivery_unknown')
            return b''
        raise AssertionError('Unexpected Engine operation: ' + repr(argv))


class DeliveryTests(unittest.TestCase):
    def setUp(self):
        self.t = initial_tests.TransitionTests('runTest'); self.t.setUp(); self.addCleanup(self.t.doCleanups)
        self.t.prepare(); self.t.activate(); self.t.verify()
        self.repo = self.t.f.repo
        self.initial_sha = self.t.f.sha
        workflow = self.repo/oci.WORKFLOW; workflow.parent.mkdir(parents=True, exist_ok=True); workflow.write_text('synthetic reviewed workflow')
        app = self.repo / 'services/ingestion-support/app.py'; app.write_text('synthetic next reviewed release')
        self.sha = self.t.f.commit()
        self.t.f.sha = self.sha
        self.root = self.t.f.root
        for key in ('journal', 'receipts'):
            (self.root/key).mkdir(mode=0o700)
        self.oci_path = self.root / 'api.oci.tar'
        self.component = manifest(self.repo, self.sha)['ingestion_support']
        archive(self.oci_path, self.sha, self.component)
        self.providers = Providers(self)
        with patch.dict(os.environ, {'M4_IMAGE_PUBLICATION_ENABLED': 'owner-approved-v1', 'GITHUB_ACTOR': 'synthetic-owner'}):
            self.proof = oci.publish(self.oci_path, self.sha, 123, 1, 'synthetic-token', self.providers.http)
        self.providers.authenticate(self.proof)
        self.process = EngineTransport(self, self.providers)
        self.runtime_path = self.root/'runtime.json'; publish(self.runtime_path, runtime(), immutable=True)
        def seal(path):
            return dict(path=str(path), identity={**executor.identity(path.stat()), 'uid': 0}, sha256=executor.sha256(path.read_bytes()))
        self.repo.chmod(0o700)
        for path in (self.repo/'.git').rglob('*'):
            path.chmod(path.stat().st_mode & 0o777 & ~0o022)
        (self.repo/'.git').chmod(0o700)
        (self.repo/'.git/config').chmod(0o600)
        self.policy = dict(github_repository_id=123456, approved_reviewers={'independent-reviewer': 9876}, state_root=self.t.config['state_root'], journal_root=str(self.root/'journal'),
            receipt_root=str(self.root/'receipts'), owner_config=self.t.config, source_mirror=str(self.repo/'.git'),
            environment_policy=self.t.f.p, runtime_seal=seal(self.runtime_path), daemon_id='synthetic-daemon',
            runtime_identities={name: executor.inventory.runtime_identity(v) for name, v in self.process.live.items()},
            unrelated={name: {'id': v['id'], 'image': v['image']} for name, v in self.process.live.items() if name != 'api'},
            resources={'network': {'synthetic_internal': {'Id': 'network-id', 'Name': 'synthetic_internal'}}},
            protected_inputs=self.t.config['initial_transition']['protected_inputs'], api_limits=self.process.limits,
            source_authority_seals=[seal(self.repo/'.git/config')], infrastructure_source_sha256={path: executor.sha256(git(self.repo, 'show', self.sha+':'+path))
                for path in executor.REVIEWED_SOURCE_FILES}, runtime_relationship_seals=[],
            service_origin='https://service.invalid', initial_acceptance_seals=[seal(p) for p in self.t.state.iterdir() if p.name in
                {'initial-transition.json', 'initial-plan.json', 'initial-verification.json', 'initial-service-receipt.json',
                 self.initial_sha+'.provenance.json'} or re.fullmatch(r'approval-[0-9a-f]{64}\.consumed\.json', p.name)])
        self.policy_raw = encoded(self.policy)
        p = patch.object(executor, 'INITIAL_SOURCE', self.initial_sha); p.start(); self.addCleanup(p.stop)
        p = patch.object(executor, 'read_json', return_value={'status': 'ready'}); p.start(); self.addCleanup(p.stop)
        self.source = executor.SealedSource(self.policy, self.process)
        registry_config = dict(image_repository=oci.IMAGE, docker_config=self.t.config['docker_config'],
            registry=dict(private=True, approval='synthetic-reviewed-package-access', repository=oci.IMAGE,
                          token_endpoint='https://ghcr.io/token', service='ghcr.io', blob_redirect_hosts=[]))
        auth = Path(self.t.config['docker_config'])/'config.json'
        publish(auth, {'auths': {'ghcr.io': {'auth': __import__('base64').b64encode(b'user:synthetic-token').decode()}}})
        registry = private_registry.Registry(registry_config, request=self.providers.registry_request)
        self.verifier = verifier.GithubVerifier(self.policy, self.process, self.source, token='synthetic-read-token',
            transport=self.providers.http, registry=registry, clock=lambda: NOW)
        with self.t.root_operator(): self.engine = executor.ApiEngine(self.policy, self.process)
        self.instance = broker.Broker(self.policy, self.policy_raw, self.verifier, self.source, self.engine,
            lambda: (self.policy, self.policy_raw), clock=lambda: NOW)
        self.request = broker.packet(encoded(dict(schema_version=2, operation=broker.OPERATION, git_commit=self.sha,
                                                request_id='f'*64)), (321, 993, 983))

    def run_release(self):
        with self.t.root_operator(): return self.instance.reconcile(self.request)

    def test_complete_real_adapter_path_and_restart_duplicate(self):
        left, right = socket.socketpair(socket.AF_UNIX, socket.SOCK_SEQPACKET)
        self.addCleanup(left.close); self.addCleanup(right.close)
        left.sendmsg([encoded(self.request)])
        with patch.object(broker, 'peer_identity', return_value=(123, 993, 983)), patch('os.readlink', return_value='host'), \
             RuntimeTests('runTest').peer_context():
            self.request = broker.receive(right, {'owner_cgroup': '/system.slice/moneybowl-ingestion-deploy.service'})
        permanent = (self.t.state/'initial-service-receipt.json').read_bytes()
        self.assertEqual(self.run_release(), dict(state='deployed', git_commit=self.sha))
        self.assertEqual(self.run_release()['state'], 'already_deployed')
        self.instance = broker.Broker(self.policy, self.policy_raw, self.verifier, self.source, self.engine,
            lambda: (self.policy, self.policy_raw), clock=lambda: NOW)
        self.assertEqual(self.run_release()['state'], 'already_deployed')
        self.assertEqual(self.process.activations, 1)
        self.assertEqual((self.t.state/'initial-service-receipt.json').read_bytes(), permanent)
        receipt = read_private(self.root/'receipts'/(self.sha+'.json'))
        self.assertEqual(receipt['image_id'], self.proof['config_digest'])
        self.assertEqual(receipt['git_commit'], self.sha)
        self.assertEqual(receipt['observed_at'], NOW)
        self.assertTrue(receipt['component']['healthy'])
        self.assertNotIn('environment', receipt.get('component', {}))
        mutations = [a for a in self.process.calls if 'pull' in a or 'up' in a]
        self.assertEqual(len(mutations), 2)
        self.assertFalse(any('build' in a or 'exec' in a or 'prune' in a for a in self.process.calls))

    def test_publication_does_not_wait_for_passive_release_observer(self):
        self.providers.run['status'] = 'in_progress'
        self.providers.run['conclusion'] = None
        self.assertEqual(self.run_release()['state'], 'deployed')

    def test_wrong_authenticated_run_identity(self):
        for field, value in [('event', 'pull_request'), ('event', 'pull_request_target'), ('path', '.github/workflows/evil.yml'),
                             ('head_sha', 'b'*40), ('head_branch', 'main'), ('run_attempt', 2), ('head_branch', 'qa')]:
            with self.subTest(field=field, value=value):
                previous = self.providers.run[field]; self.providers.run[field] = value
                with self.assertRaises((Rejected, oci.Invalid)): self.run_release()
                self.providers.run[field] = previous
        self.providers.run['head_repository']['fork'] = True
        with self.assertRaises((Rejected, oci.Invalid)): self.run_release()
        self.assertEqual(self.process.activations, 0)

    def test_forged_proof_is_not_a_label_check(self):
        self.providers.broken_signature = True
        with self.assertRaises(Rejected): self.run_release()
        self.assertEqual(self.process.activations, 0)

    def test_failed_ci_or_publisher_never_activates(self):
        for j in self.providers.jobs['jobs']:
            j['conclusion'] = 'failure'
            with self.assertRaises(oci.Invalid): self.run_release()
            j['conclusion'] = 'success'
        self.assertEqual(self.process.activations, 0)

    def test_current_image_substitution_is_rejected_even_with_ancestral_labels(self):
        self.process.live['api']['image'] = 'sha256:'+'1'*64
        with self.assertRaisesRegex(Rejected, 'current_release_drift'): self.run_release()
        self.assertEqual(self.process.activations, 0)

    def test_missing_initial_tuple(self):
        (self.t.state/'initial-verification.json').unlink()
        with self.assertRaises(Rejected): self.run_release()
        self.assertEqual(self.process.activations, 0)

    def test_superseded_only_before_attempt(self):
        self.providers.head = 'b'*40
        self.assertEqual(self.run_release()['state'], 'superseded')
        self.assertEqual(self.process.activations, 0)

    def test_branch_change_after_attempt_quarantines(self):
        self.process.after_change = lambda _: setattr(self.providers, 'head', 'b'*40)
        with self.assertRaisesRegex(Rejected, 'quarantined'): self.run_release()
        with self.assertRaisesRegex(Rejected, 'quarantined'): self.run_release()
        self.assertEqual(self.process.activations, 1)

    def test_timeout_unknown_activation_never_retries(self):
        self.process.fail = 'up'
        with self.assertRaisesRegex(Rejected, 'quarantined'): self.run_release()
        self.process.fail = None
        with self.assertRaisesRegex(Rejected, 'quarantined'): self.run_release()
        self.assertEqual(self.process.activations, 1)

    def test_unrelated_mutation_and_failed_readiness_quarantine(self):
        self.process.after_change = lambda p: p.live['caddy'].update(id='b'*64)
        with self.assertRaisesRegex(Rejected, 'quarantined'): self.run_release()
        self.assertEqual(self.process.activations, 1)

    def test_failed_health_quarantines(self):
        self.process.after_change = lambda p: p.live['api']['state']['Health'].update(Status='unhealthy')
        with self.assertRaisesRegex(Rejected, 'quarantined'): self.run_release()

    def test_outbox_reactivation_is_denied(self):
        self.process.retired['state']['Running'] = True
        with self.assertRaisesRegex(Rejected, 'legacy_dispatcher_not_retired'): self.run_release()
        self.assertEqual(self.process.activations, 0)

    def test_concurrent_shared_initial_lock(self):
        with deployment_lock(self.t.state), self.assertRaisesRegex(Rejected, 'deployment_busy'): self.run_release()
        self.assertEqual(self.process.activations, 0)

    def test_interrupted_receipt_write_is_not_retried(self):
        original = broker.publish
        def interrupt(path, value, **kw):
            if Path(path).parent == self.root/'receipts': raise OSError('synthetic interrupted publication')
            return original(path, value, **kw)
        with patch.object(broker, 'publish', side_effect=interrupt), self.assertRaisesRegex(Rejected, 'quarantined'): self.run_release()
        with self.assertRaisesRegex(Rejected, 'quarantined'): self.run_release()
        self.assertEqual(self.process.activations, 1)

    def test_approval_substitution_and_runtime_substitution(self):
        self.instance.authority = lambda: ({**self.policy, 'owner_review': 'replacement'}, b'changed')
        with self.assertRaisesRegex(Rejected, 'authority_changed'): self.run_release()
        self.assertEqual(self.process.activations, 0)

    def test_runtime_inode_substitution(self):
        other = self.root/'replacement'; other.write_bytes(self.runtime_path.read_bytes()); other.chmod(0o400)
        os.replace(other, self.runtime_path)
        with self.assertRaisesRegex(Rejected, 'identity_changed'): self.run_release()
        self.assertEqual(self.process.activations, 0)

    def test_wrong_registry_config_digest(self):
        p = copy.deepcopy(self.proof); p['config_digest'] = 'sha256:'+'1'*64
        self.providers.authenticate(p)
        with self.assertRaises(Rejected): self.run_release()
        self.assertEqual(self.process.activations, 0)

    def test_expired_proof(self):
        original = self.verifier.verify
        def expired(sha):
            p = original(sha); p['expires_at'] = NOW-1; return p
        self.verifier.verify = expired
        with self.assertRaisesRegex(Rejected, 'expired'): self.run_release()
        self.assertEqual(self.process.activations, 0)

    def test_consumed_request_cannot_change_release(self):
        self.run_release()
        self.request['git_commit'] = 'b'*40
        with self.assertRaisesRegex(Rejected, 'replayed'): self.run_release()
        self.assertEqual(self.process.activations, 1)

    def test_independent_review_is_required(self):
        self.policy['approved_reviewers'] = {'different-reviewer': 1234}
        self.instance.policy_raw = encoded(self.policy)
        self.policy_raw = self.instance.policy_raw
        with self.assertRaisesRegex(Rejected, 'independent_review'): self.run_release()
        self.assertEqual(self.process.activations, 0)

    def test_source_workflow_or_infrastructure_changes_need_new_policy(self):
        self.policy['infrastructure_source_sha256'][oci.WORKFLOW] = '0'*64
        self.instance.policy_raw = encoded(self.policy)
        self.policy_raw = self.instance.policy_raw
        with self.assertRaisesRegex(Rejected, 'policy_change_requires_review'): self.run_release()
        self.assertEqual(self.process.activations, 0)

    def test_missing_immutable_initial_authority_consumption_blocks(self):
        for p in self.t.state.glob('approval-*.consumed.json'): p.unlink()
        with self.assertRaises(Rejected): self.run_release()
        self.assertEqual(self.process.activations, 0)

    def test_installed_public_code_seal_does_not_relax_private_config(self):
        path = self.root/'public-code.py'; path.write_bytes(b'# reviewed public constants\n'); path.chmod(0o444)
        item = dict(path=str(path), sha256=executor.sha256(path.read_bytes()), identity={**executor.identity(path.stat()), 'uid': 0, 'gid': 0})
        with self.t.root_operator(metadata_overrides={path: {'gid': 0}}):
            self.assertEqual(executor.sealed_read(item, public_code=True), b'# reviewed public constants\n')
            with self.assertRaises(Rejected): executor.sealed_read(item)

    def test_actual_environment_substitution_is_rejected(self):
        self.process.environment.append('LD_PRELOAD=/app/injected.so')
        with self.assertRaisesRegex(Rejected, 'environment_changed'): self.run_release()
        self.assertEqual(self.process.activations, 0)

    def test_capacity_is_measured_before_any_mutation(self):
        self.process.capacity_error = True
        with self.assertRaisesRegex(Rejected, 'insufficient_build_capacity'): self.run_release()
        self.assertEqual(self.process.activations, 0)

    def test_missing_runtime_limits_or_resource_inventory_denies(self):
        self.process.limits['memory'] = 1
        self.policy['api_limits'] = dict(cpu=1000000000, memory=536870912, pids=128, tmpfs={'/tmp': 'size=16m,mode=1777'})
        self.policy_raw = encoded(self.policy); self.instance.policy_raw = self.policy_raw
        with self.assertRaisesRegex(Rejected, 'limits_changed'): self.run_release()
        self.assertEqual(self.process.activations, 0)

    def test_receipts_are_renewed_after_real_observation_without_activation(self):
        self.run_release()
        self.instance.clock = lambda: NOW+60
        self.assertEqual(self.run_release()['state'], 'already_deployed')
        self.assertEqual(read_private(self.root/'receipts'/(self.sha+'.json'))['observed_at'], NOW+60)
        self.assertEqual(self.run_release()['state'], 'already_deployed')
        self.assertEqual(self.process.activations, 1)

    def test_interrupted_renewal_quarantines_without_activation_retry(self):
        self.run_release()
        self.instance.clock = lambda: NOW+60
        original = broker.publish
        def fail(path, value, **kw):
            if Path(path).parent == self.root/'receipts': raise OSError('synthetic publication failure')
            return original(path, value, **kw)
        with patch.object(broker, 'publish', side_effect=fail), self.assertRaisesRegex(Rejected, 'quarantined'): self.run_release()
        with self.assertRaisesRegex(Rejected, 'quarantined'): self.run_release()
        self.assertEqual(self.process.activations, 1)

    def test_failed_public_readiness_after_attempt_is_quarantined(self):
        with patch.object(executor, 'read_json', side_effect=lambda _: {'status': 'failed'} if self.process.activations else {'status': 'ready'}), \
             self.assertRaisesRegex(Rejected, 'quarantined'): self.run_release()
        self.assertEqual(self.process.activations, 1)

    def test_changed_tag_never_selects_runtime_artifact(self):
        self.providers.remote['manifests/latest'] = b'changed mutable tag'
        self.assertEqual(self.run_release()['state'], 'deployed')
        self.assertFalse(any('latest' in url for url, _ in self.providers.calls))


class OciTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name)/'api.tar'
        self.sha, self.component = 'a'*40, 'b'*64
        self.blobs, _ = archive(self.path, self.sha, self.component)

    def test_distinct_oci_identities_and_exact_metadata(self):
        proof, _, _ = oci.validate(self.path, self.sha, self.component)
        self.assertEqual(len({proof[k] for k in ('index_digest', 'manifest_digest', 'config_digest')}), 3)
        self.assertEqual(proof['build_source'], proof['release_source'])
        self.assertEqual(proof['image'], oci.IMAGE+'@'+proof['manifest_digest'])

    def test_wrong_platform_digest_user_command_and_source(self):
        cases = [lambda c: c.update(architecture='amd64'), lambda c: c.update(os='windows'),
                 lambda c: c['config'].update(User='0:0'), lambda c: c['config'].update(Cmd=['sh']),
                 lambda c: c['config'].update(Entrypoint=['sh']),
                 lambda c: c['config']['Labels'].update({'org.opencontainers.image.revision': 'c'*40}),
                 lambda c: c['config'].update(Env=['SUPABASE_SERVICE_ROLE_KEY=forbidden']),
                 lambda c: c['config'].update(Volumes={'/var/run/docker.sock': {}})]
        for edit in cases:
            archive(self.path, self.sha, self.component, edit)
            with self.subTest(edit=edit), self.assertRaises(oci.Invalid): oci.validate(self.path, self.sha, self.component)

    def write_entries(self, extra):
        with tarfile.open(self.path, 'w', format=tarfile.USTAR_FORMAT) as tar:
            for name, raw in self.blobs.items():
                info = tarfile.TarInfo(name); info.size = len(raw); tar.addfile(info, io.BytesIO(raw))
            for info, raw in extra:
                tar.addfile(info, io.BytesIO(raw) if raw else None)

    def test_unsafe_archive_names_links_duplicates_and_special_files(self):
        for name, kind in [('../escape', tarfile.REGTYPE), ('/absolute', tarfile.REGTYPE),
                           ('blobs/sha256/link', tarfile.SYMTYPE), ('index.json', tarfile.REGTYPE),
                           ('fifo', tarfile.FIFOTYPE), ('device', tarfile.CHRTYPE), ('other-dir', tarfile.DIRTYPE)]:
            info = tarfile.TarInfo(name); info.type = kind; info.linkname = '/etc/shadow'
            raw = b'x' if kind == tarfile.REGTYPE else b''; info.size = len(raw)
            self.write_entries([(info, raw)])
            with self.subTest(name=name, kind=kind), self.assertRaises((oci.Invalid, ValueError)): oci.validate(self.path, self.sha, self.component)

    def test_unreferenced_or_corrupt_blob_and_size(self):
        raw = b'extra'; info = tarfile.TarInfo('blobs/sha256/'+oci.digest(raw)[7:]); info.size = len(raw)
        self.write_entries([(info, raw)])
        with self.assertRaisesRegex(oci.Invalid, 'unreferenced'): oci.validate(self.path, self.sha, self.component)
        info = tarfile.TarInfo('blobs/sha256/'+'0'*64); info.size = 5
        self.write_entries([(info, b'wrong')])
        with self.assertRaisesRegex(oci.Invalid, 'digest'): oci.validate(self.path, self.sha, self.component)
        with patch.object(oci, 'MAX_BYTES', 1024), self.assertRaises(oci.Invalid): oci.validate(self.path, self.sha, self.component)

    def test_external_descriptor_url_and_duplicate_json(self):
        with self.assertRaises(oci.Invalid): oci.descriptor(dict(mediaType=oci.MANIFEST, digest='sha256:'+'b'*64,
            size=1, urls=['https://attacker.invalid']), {oci.MANIFEST})
        with self.assertRaises(oci.Invalid): oci.document(b'{"schemaVersion":2,"schemaVersion":2}')
        with self.assertRaises(oci.Invalid): oci.document(b'{"size":NaN}')

    def test_malformed_or_expanding_layers_fail_without_extraction(self):
        with self.assertRaisesRegex(oci.Invalid, 'structure'): oci.check_layer(b'not a tar', 'application/vnd.oci.image.layer.v1.tar', [0])
        with patch.object(oci, 'MAX_UNPACKED', 1), self.assertRaisesRegex(oci.Invalid, 'expansion'):
            oci.check_layer(__import__('gzip').compress(b'0'*10000), 'application/vnd.oci.image.layer.v1.tar+gzip', [0])

    def test_publication_disabled_does_not_contact_provider(self):
        contact = Mock(side_effect=AssertionError('disabled gate contacted a provider'))
        with patch.dict(os.environ, {}, clear=True), self.assertRaisesRegex(oci.Invalid, 'disabled'):
            oci.publish(self.path, self.sha, 123, 1, 'unused', contact)
        contact.assert_not_called()


class RuntimeTests(unittest.TestCase):
    def setUp(self):
        self.proof = {'image': oci.IMAGE+'@sha256:'+'b'*64, 'git_commit': 'a'*40, 'source_digest': 'c'*64}

    def test_arbitrary_commands_mounts_env_and_path_are_not_request_fields(self):
        request = dict(schema_version=2, operation=broker.OPERATION, git_commit='a'*40, request_id='b'*64)
        for field in ('command', 'argv', 'image', 'mount', 'env', 'compose', 'path', 'target', 'project', 'endpoint'):
            with self.subTest(field=field), self.assertRaises(Rejected):
                broker.packet(encoded({**request, field: 'attacker'}), (1, 993, 983))
        for peer in ((1, 0, 0), (1, 993, 981), (0, 993, 983)):
            with self.assertRaises(Rejected): broker.packet(encoded(request), peer)

    def test_runtime_scope_and_security_not_waived_by_approval_hash(self):
        for field, value in [('build', {'context': '/tmp/evil'}), ('command', ['sh']),
                             ('user', '0'), ('privileged', True), ('env_file', '/etc/evil'),
                             ('volumes', ['/var/run/docker.sock:/var/run/docker.sock']),
                             ('post_start', [{'command': 'sh'}]), ('depends_on', ['clamav']),
                             ('network_mode', 'host'), ('ports', ['0.0.0.0:8080:8080'])]:
            model = runtime(); model['services']['api'][field] = value
            with self.subTest(field=field), self.assertRaises(Rejected): executor.runtime_model(encoded(model), self.proof)
        model = runtime(); model['services']['caddy'] = {}
        with self.assertRaises(Rejected): executor.runtime_model(encoded(model), self.proof)

    def test_runtime_environment_dollars_are_literal(self):
        model = runtime(); model['services']['api']['environment']['TEST_INPUT'] = 'literal$VALUE'
        actual = json.loads(executor.runtime_model(encoded(model), self.proof))
        self.assertEqual(actual['services']['api']['environment']['TEST_INPUT'], 'literal$$VALUE')
        model['services']['api']['environment']['TEST_INPUT'] = '${UNTRUSTED}'
        with self.assertRaises(Rejected): executor.runtime_model(encoded(model), self.proof)

    def test_memfd_seals_and_short_writes(self):
        original = os.write
        def short(fd, raw): return original(fd, raw[:max(1, len(raw)//2)])
        with patch('os.write', side_effect=short), executor.sealed_memfd(b'bounded content') as fd:
            self.assertEqual(os.read(fd, 1024), b'bounded content')
            with self.assertRaises(OSError): os.write(fd, b'changed')
        with patch('os.write', return_value=0), self.assertRaisesRegex(Rejected, 'short_write'):
            with executor.sealed_memfd(b'x'): pass

    def test_process_transport_enforces_real_output_and_time_bounds(self):
        process = executor.Process.__new__(executor.Process)
        process.tools = {'python': '/usr/bin/python3'}
        process.env = {'PATH': '/usr/bin:/bin'}
        with self.assertRaisesRegex(Rejected, 'delivery_unknown'):
            process(['/usr/bin/python3', '-I', '-B', '-c', 'import time; time.sleep(5)'], timeout=.1)
        with self.assertRaisesRegex(Rejected, 'output_oversized'):
            process(['/usr/bin/python3', '-I', '-B', '-c', 'import sys; sys.stdout.buffer.write(b"x"*(4*1024*1024+1))'])

    def test_short_socket_send_fails(self):
        with self.assertRaisesRegex(Rejected, 'short_send'): broker.send_packet(Mock(sendmsg=Mock(return_value=1)), {'state': 'failed'})

    def test_disabled_root_and_client_entrypoints_do_not_contact_provider(self):
        with patch.object(executor, 'POLICY_PATH', Path('/nonexistent/moneybowl-source-test')), \
             patch.object(broker, 'production', side_effect=AssertionError('provider called')), \
             self.assertRaises((Rejected, OSError)):
            broker.serve()
        with patch('os.getuid', return_value=993), patch('os.geteuid', return_value=993), \
             patch('os.getgid', return_value=983), patch('os.getegid', return_value=983), \
             patch('socket.socket', side_effect=AssertionError('socket contacted')), self.assertRaises(OSError):
            broker.client('a'*40)

    def peer_context(self):
        status = 'Uid:\t993\t993\t993\t993\nGid:\t983\t983\t983\t983\nCapEff:\t0000000000000000\n'
        return patch.object(Path, 'read_text', side_effect=lambda *a, **kw: status if str(a[0]).endswith('status') else
            '0::/system.slice/moneybowl-ingestion-deploy.service\n', autospec=True)

    def test_real_socket_fd_passing_truncation_and_timeout(self):
        request = encoded(dict(schema_version=2, operation=broker.OPERATION, git_commit='a'*40, request_id='b'*64))
        for mode in ('fd', 'truncated', 'timeout'):
            left, right = socket.socketpair(socket.AF_UNIX, socket.SOCK_SEQPACKET)
            self.addCleanup(left.close); self.addCleanup(right.close)
            with tempfile.TemporaryFile() as file:
                if mode == 'fd': left.sendmsg([request], [(socket.SOL_SOCKET, socket.SCM_RIGHTS, array.array('i', [file.fileno()]))])
                if mode == 'truncated': left.sendmsg([b'x'*2048])
                with patch.object(broker, 'peer_identity', return_value=(123, 993, 983)), \
                     patch('os.readlink', return_value='same-host-namespace'), self.peer_context(), self.assertRaises(Rejected):
                    broker.receive(right, {'owner_cgroup': '/system.slice/moneybowl-ingestion-deploy.service'})

    def test_invalid_process_namespace_or_service(self):
        left, right = socket.socketpair(socket.AF_UNIX, socket.SOCK_SEQPACKET)
        self.addCleanup(left.close); self.addCleanup(right.close)
        with patch.object(broker, 'peer_identity', return_value=(123, 993, 983)), \
             patch('os.readlink', side_effect=['other', 'host']), self.assertRaisesRegex(Rejected, 'namespace'):
            broker.receive(right, {'owner_cgroup': '/system.slice/moneybowl-ingestion-deploy.service'})


class WorkflowTests(unittest.TestCase):
    def test_embedded_publisher_is_exact_reviewed_source_and_syntax(self):
        root = Path(__file__).resolve().parents[2]
        workflow = (root/'.github/workflows/environment-promotion.yml').read_text()
        body = workflow.split("          python3 -I -B - <<'PY_PUBLISHER'\n", 1)[1].split('          PY_PUBLISHER\n', 1)[0]
        actual = ''.join(line[10:]+'\n' for line in body.splitlines())
        self.assertEqual(actual, (root/'tools/deployment/oci_delivery.py').read_text())
        compile(actual, 'embedded-publisher', 'exec')
        build = workflow.split('  api-build:\n', 1)[1].split('  api-publish:\n', 1)[0]
        publisher = workflow.split('  api-publish:\n', 1)[1].split('  release:\n', 1)[0]
        self.assertIn('runs-on: ubuntu-24.04-arm', build)
        self.assertIn('permissions:\n      contents: read\n    steps:', build)
        self.assertNotIn('packages: write', build)
        self.assertNotIn('id-token: write', build)
        for name in ('contents: read', 'actions: read', 'packages: write', 'attestations: write', 'id-token: write'):
            self.assertIn('      '+name, publisher)
        for section in (build, publisher):
            self.assertIn("vars.M4_IMAGE_PUBLICATION_ENABLED == 'owner-approved-v1'", section)
            self.assertIn("github.event_name == 'push'", section)
            self.assertIn("github.ref == 'refs/heads/develop'", section)
            for reference in re.findall(r'^      - uses: (\S+)', section, re.M):
                self.assertRegex(reference, r'^[a-zA-Z0-9_./-]+@[0-9a-f]{40}$')
        self.assertNotIn('uses: actions/checkout', publisher)
        self.assertNotIn('run: python3 tools/', publisher)
        self.assertNotIn('secrets.', publisher)
        self.assertNotIn('docker login', publisher)
        self.assertIn('needs: [contracts, flutter, backend]', workflow)
        self.assertIn('needs: validated', workflow.split('  release:', 1)[1])


if __name__ == '__main__':
    unittest.main()
