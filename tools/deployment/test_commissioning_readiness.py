"""Offline commissioning regression tests; synthetic files and Engine transport only."""
import contextlib
import copy
import json
import os
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch

import commissioning_readiness as commissioning
import initial_private_inputs as private
import test_initial_api_transition as transition_fixtures
import test_initial_private_inputs as input_fixtures
from contract import DEV_PROJECT, Rejected
from owner_common import Command, sha256


class EnvironmentTests(unittest.TestCase):
    def test_original_bytes_preserved_exactly_and_all_six_appended(self):
        original = b'PRIVATE="synthetic-value"\r\nPUBLIC=fixture'
        result = commissioning.append_m3b(original, commissioning.M3B)
        self.assertTrue(result.startswith(original + b'\n'))
        commissioning.check_env(result, commissioning.M3B)

    def test_missing_candidate_setting_fails(self):
        for key in commissioning.M3B:
            settings = {k: v for k, v in commissioning.M3B.items() if k != key}
            with self.subTest(key=key), self.assertRaisesRegex(Rejected, 'm3b_settings_missing'):
                commissioning.append_m3b(b'', settings)

    def test_existing_assignments_exports_and_bare_keys_rejected(self):
        for key in commissioning.M3B:
            for line in (key + '=fixture', 'export ' + key + '=fixture', key,
                         '  ' + key + ' =fixture', '\ufeff' + key + '=fixture', key + ': fixture'):
                with self.subTest(line=line), self.assertRaisesRegex(Rejected, 'm3b_variable_already_present'):
                    commissioning.append_m3b(line.encode(), commissioning.M3B)

    def test_missing_prepared_variable_fails(self):
        raw = commissioning.append_m3b(b'', commissioning.M3B)
        for key in commissioning.M3B:
            line = (key + '=' + commissioning.M3B[key] + '\n').encode()
            with self.subTest(key=key), self.assertRaisesRegex(Rejected, 'm3b_variable_missing'):
                commissioning.check_env(raw.replace(line, b''), commissioning.M3B)

    def test_duplicate_prepared_variable_fails_even_if_values_identical(self):
        raw = commissioning.append_m3b(b'', commissioning.M3B)
        with self.assertRaisesRegex(Rejected, 'm3b_variable_duplicate'):
            commissioning.check_env(raw + b'M3B_WAKE_GID=985\n', commissioning.M3B)

    def test_changed_tag_or_interpolated_value_is_not_substituted(self):
        raw = commissioning.append_m3b(b'', commissioning.M3B)
        with self.assertRaisesRegex(Rejected, 'm3b_variable_invalid'):
            commissioning.check_env(raw.replace(b'M3B_WAKE_GID=985', b'M3B_WAKE_GID=${OTHER}'), commissioning.M3B)
        settings = dict(commissioning.M3B, M3B_INGRESS_ADAPTER_IMAGE='fixture@sha256:' + 'a' * 64)
        with self.assertRaisesRegex(Rejected, 'm3b_settings_missing'):
            commissioning.append_m3b(b'', settings)

    def test_command_never_inherits_operator_interpolations(self):
        with patch.dict(os.environ, {**commissioning.M3B, 'PRIVATE_FIXTURE': 'must-not-inherit'}):
            command = Command({'DOCKER_CONFIG': '/synthetic/auth'})
        self.assertEqual(command.env, dict(PATH='/usr/local/bin:/usr/bin:/bin', LANG='C.UTF-8',
                                          DOCKER_CONFIG='/synthetic/auth'))

    def test_duplicate_json_fields_cannot_hide_approval_or_settings(self):
        with self.assertRaisesRegex(Rejected, 'commissioning_duplicate_json_key'):
            commissioning.parse_json(b'{"approval":null,"approval":"fixture"}')

    def test_git_remote_inspection_runs_inside_trusted_mirror_with_isolated_environment(self):
        transport = Mock(return_value=b'fixture')
        config = dict(repository='/synthetic/root-source.git')
        with patch.object(commissioning, 'Command', return_value=transport) as constructor, \
                patch.object(commissioning, 'pinned_executable', return_value='/synthetic/git'):
            commissioning.safe_git(config, 'ls-remote', 'https://github.com/synthetic/repo.git', remote=True)
        self.assertEqual(transport.call_args.kwargs, dict(cwd=config['repository']))
        self.assertEqual(constructor.call_args.args[0], dict(GIT_CONFIG_NOSYSTEM='1',
                         GIT_CONFIG_GLOBAL='/dev/null', GIT_TERMINAL_PROMPT='0'))
        self.assertIn('core.hooksPath=/dev/null', transport.call_args.args[0])
        self.assertIn('credential.helper=', transport.call_args.args[0])


class FileFixture(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.untrusted = set()
        self.groups = {}
        self.owners = {}

    @contextlib.contextmanager
    def authority(self):
        # Metadata-only simulation. No real root, sudo, Docker or chown is acquired.
        original = Path.lstat
        fstat = os.fstat
        def mapped(path, info):
            values = list(info)
            if path in (Path('/'), Path('/tmp')) or path == self.root or self.root in path.parents:
                values[4] = self.owners.get(path, 0) if path not in self.untrusted else 993
                values[5] = self.groups.get(path, 0)
            if path == Path('/tmp'):
                values[0] &= ~0o022
            return os.stat_result(values)
        def descriptor(fd):
            return mapped(Path(os.readlink('/proc/self/fd/' + str(fd))), fstat(fd))
        with patch.object(Path, 'lstat', lambda p: mapped(p, original(p))), \
                patch('os.fstat', descriptor), patch('os.getuid', return_value=0), \
                patch('os.geteuid', return_value=0), patch('os.fchown'), patch('os.chown'):
            yield


class FileTests(FileFixture):
    def test_exclusive_root_0400_creation_and_integrity(self):
        path = self.root / 'created'
        with self.authority():
            identity = commissioning.create(path, b'fixture-only')
            self.assertEqual(identity['uid'], 0); self.assertEqual(identity['gid'], 0)
            self.assertEqual(identity['mode'], 0o400)
            with self.assertRaises(FileExistsError):
                commissioning.create(path, b'replacement')
            self.assertEqual(path.read_bytes(), b'fixture-only')

    def test_file_and_parent_are_synchronized(self):
        path = self.root / 'created'
        with self.authority(), patch.object(commissioning, 'sync_directory') as sync, patch('os.fsync') as fsync:
            commissioning.create(path, b'fixture-only')
        fsync.assert_called_once(); sync.assert_called_once_with(self.root)

    def test_creation_rejects_symlink_and_untrusted_ancestor(self):
        target = self.root / 'target'; target.write_bytes(b'preserved')
        alias = self.root / 'alias'; alias.symlink_to(target)
        with self.authority(), self.assertRaises(FileExistsError):
            commissioning.create(alias, b'replacement')
        self.assertEqual(target.read_bytes(), b'preserved')
        self.untrusted.add(self.root)
        with self.authority(), self.assertRaisesRegex(Rejected, 'approval_authority_invalid'):
            commissioning.create(self.root / 'new', b'replacement')

    def test_parent_symlink_read_is_rejected(self):
        sub = self.root / 'sub'; sub.mkdir(mode=0o700)
        file = sub / 'input'; file.write_bytes(b'fixture'); file.chmod(0o400)
        alias = self.root / 'alias'; alias.symlink_to(sub, target_is_directory=True)
        with self.authority(), self.assertRaisesRegex(Rejected, 'approval_authority_invalid'):
            commissioning.root_bytes(alias / 'input')

    def test_bad_permissions_hardlinks_and_digest_changes_rejected(self):
        path = self.root / 'input'; path.write_bytes(b'fixture'); path.chmod(0o440)
        with self.authority(), self.assertRaisesRegex(Rejected, 'approval_authority_invalid'):
            commissioning.root_bytes(path)
        path.chmod(0o400)
        with self.authority(), self.assertRaisesRegex(Rejected, 'commissioning_artifact_changed'):
            commissioning.root_bytes(path, '0' * 64)
        os.link(path, self.root / 'hardlink')
        with self.authority(), self.assertRaisesRegex(Rejected, 'approval_authority_invalid'):
            commissioning.root_bytes(path)

    def test_same_bytes_inode_substitution_before_open_is_rejected(self):
        path = self.root / 'input'; path.write_bytes(b'fixture'); path.chmod(0o400)
        replacement = self.root / 'other'; replacement.write_bytes(b'fixture'); replacement.chmod(0o400)
        opened = os.open
        def substitute(name, flags, *args, **kwargs):
            if Path(name) == path:
                replacement.replace(path)
            return opened(name, flags, *args, **kwargs)
        with self.authority(), patch('os.open', side_effect=substitute), \
                self.assertRaisesRegex(Rejected, 'private_input_identity_changed'):
            commissioning.root_bytes(path)

    def test_transfer_retains_inode_and_never_overwrites(self):
        source = self.root / 'source'; destination = self.root / 'destination'
        with self.authority():
            identity = commissioning.create(source, b'fixture')
            commissioning.move_exclusive(source, destination)
            self.assertEqual(private.identity(destination.lstat()), identity)
            self.assertEqual(destination.stat().st_nlink, 1)
            commissioning.create(source, b'other')
            with self.assertRaises(FileExistsError):
                commissioning.move_exclusive(source, destination)
            self.assertEqual(destination.read_bytes(), b'fixture')

    def test_transfer_interruption_retains_two_links_and_both_are_unusable(self):
        source = self.root / 'source'; destination = self.root / 'destination'
        with self.authority():
            commissioning.create(source, b'fixture')
            with patch.object(Path, 'unlink', side_effect=OSError('synthetic crash before source unlink')), \
                    self.assertRaises(OSError):
                commissioning.move_exclusive(source, destination)
            self.assertEqual(source.stat().st_ino, destination.stat().st_ino)
            self.assertEqual(destination.stat().st_nlink, 2)
            for path in (source, destination):
                with self.subTest(path=path), self.assertRaisesRegex(Rejected, 'approval_authority_invalid'):
                    commissioning.root_bytes(path)


class ImageInspectionTests(unittest.TestCase):
    def owner(self, cls, labels=None):
        owner = object.__new__(cls)
        owner.base = ['/synthetic/docker']
        owner.registry = None
        def transport(argv):
            self.assertIn('(index .Config "Labels")', argv[-2])
            self.assertIn('(index .Config "Cmd")', argv[-2])
            self.assertNotIn('.Config.Env', argv[-2])
            return json.dumps(dict(id='sha256:' + '1' * 64, digests=['synthetic@sha256:' + '1' * 64],
                labels=labels, command=commissioning.initial.API_COMMAND, entrypoint=None,
                user='10001:10001', architecture='arm64', os='linux')).encode()
        owner.command = transport
        return owner

    def test_existing_support_images_with_missing_labels_are_inspectable(self):
        for cls in (commissioning.DockerOwner, commissioning.initial.InitialDockerOwner):
            with self.subTest(cls=cls):
                self.assertEqual(self.owner(cls).image('synthetic')['labels'], {})

    def test_candidate_missing_labels_still_fails_mandatory_provenance(self):
        for cls in (commissioning.DockerOwner, commissioning.initial.InitialDockerOwner):
            proof = dict(image='synthetic@sha256:' + '1' * 64, image_id='sha256:' + '1' * 64,
                         git_commit='a' * 40, source_digest='b' * 64)
            with self.subTest(cls=cls), self.assertRaisesRegex(Rejected, 'image_provenance_mismatch'):
                self.owner(cls).verify_image(proof)

    def test_nonobject_labels_rejected(self):
        for cls in (commissioning.DockerOwner, commissioning.initial.InitialDockerOwner):
            with self.subTest(cls=cls), self.assertRaisesRegex(Rejected, 'invalid_image_labels'):
                self.owner(cls, labels=['untrusted']).image('synthetic')


class RelationshipTests(FileFixture):
    def setUp(self):
        super().setUp()
        self.settings = copy.deepcopy(commissioning.M3B)
        for key in ('M3B_RECEIVER_SECRET_FILE', 'M3B_RECEIVER_STATE_DIR', 'M3B_WAKE_SPOOL_DIR'):
            self.settings[key] = str(self.root / key)
        self.enterContext(patch.dict(commissioning.M3B, self.settings))
        for key, mode, uid, gid in (
            ('M3B_RECEIVER_SECRET_FILE', 0o440, 0, 10001),
            ('M3B_RECEIVER_STATE_DIR', 0o700, 10001, 10001),
            ('M3B_WAKE_SPOOL_DIR', 0o2770, 0, 985),
        ):
            path = Path(self.settings[key])
            if key == 'M3B_RECEIVER_SECRET_FILE':
                path.write_bytes(b'synthetic-secret-never-read')
            else:
                path.mkdir()
            path.chmod(mode); self.groups[path] = gid; self.owners[path] = uid
        self.receiver = dict(id='1' * 64, image='sha256:' + '2' * 64, mounts=[
            dict(Type='bind', Name=None, Source=self.settings[key], Destination=dest, RW=rw)
            for key, dest, rw in (('M3B_RECEIVER_SECRET_FILE', '/run/secrets/m3b_webhook_secret', False),
                ('M3B_RECEIVER_STATE_DIR', '/state', True), ('M3B_WAKE_SPOOL_DIR', '/spool', True))])
        self.adapter = dict(id='3' * 64, image='sha256:' + '4' * 64)
        self.caddy = dict(mounts=[dict(Type='bind', Name=None, Source='/srv/moneybowl-m4-receipts',
                                     Destination='/srv/moneybowl-m4-receipts', RW=False)])
        self.extra_groups = ['985']
        def transport(argv):
            is_receiver = argv[-1] == self.receiver['id']
            return json.dumps(dict(groups=self.extra_groups if is_receiver else None,
                configured_image=self.settings['M3B_RECEIVER_IMAGE' if is_receiver else 'M3B_INGRESS_ADAPTER_IMAGE'])).encode()
        self.images = {self.settings['M3B_RECEIVER_IMAGE']: self.receiver['image'],
                       self.settings['M3B_INGRESS_ADAPTER_IMAGE']: self.adapter['image']}
        self.docker = SimpleNamespace(base=['/synthetic/docker'], command=transport,
                                      image=lambda ref: dict(id=self.images[ref]))
        self.enterContext(patch.object(commissioning.grp, 'getgrgid', return_value=SimpleNamespace(gr_name='moneybowl-director-wake')))

    def verify(self):
        with self.authority():
            return commissioning.m3b_relationships(self.docker, dict(unrelated={
                'm3b-receiver': self.receiver, 'm3b-ingress-adapter': self.adapter, 'caddy': self.caddy}), self.settings)

    def test_verified_runtime_relationships_keep_existing_tag(self):
        self.verify()
        self.assertEqual(self.settings['M3B_INGRESS_ADAPTER_IMAGE'], commissioning.M3B['M3B_INGRESS_ADAPTER_IMAGE'])

    def test_supplemental_group_change_fails(self):
        self.extra_groups = ['983']
        with self.assertRaisesRegex(Rejected, 'm3b_wake_group_changed'):
            self.verify()

    def test_tag_rebinding_fails_without_pull_or_recreation(self):
        self.images[self.settings['M3B_INGRESS_ADAPTER_IMAGE']] = 'sha256:' + 'f' * 64
        with self.assertRaisesRegex(Rejected, 'm3b_image_binding_changed'):
            self.verify()

    def test_secret_mount_must_be_read_only_and_exact(self):
        self.receiver['mounts'][0]['RW'] = True
        with self.assertRaisesRegex(Rejected, 'm3b_mount_relationship_changed'):
            self.verify()

    def test_caddy_receipt_mount_is_required(self):
        self.caddy['mounts'].clear()
        with self.assertRaisesRegex(Rejected, 'caddy_receipt_mount_changed'):
            self.verify()


class PreflightTests(unittest.TestCase):
    def setUp(self):
        self.t = transition_fixtures.TransitionTests('runTest')
        self.t.setUp(); self.addCleanup(self.t.doCleanups)
        path = Path(self.t.config['compose_env'])
        path.write_bytes(commissioning.append_m3b(b'PRIVATE=synthetic\n', commissioning.M3B))
        self.t.config['initial_transition']['protected_inputs'][0]['sha256'] = sha256(path.read_bytes())
        self.relationships = self.enterContext(patch.object(commissioning, 'm3b_relationships'))

    def preflight(self):
        with self.t.root_operator():
            return commissioning.preflight(self.t.config, commissioning.M3B,
                docker=self.t.docker, source_view=self.t.f.repo)

    def test_actual_controller_hash_comparison_checks_exact_six(self):
        before = set(self.t.state.iterdir())
        result = self.preflight()
        self.assertEqual(set(result['effective_hashes']), set(commissioning.SIX))
        self.assertEqual(set(self.t.state.iterdir()), before)
        self.t.assert_no_up()
        self.assertFalse(result['controller_prepare_invoked'])
        self.relationships.assert_called_once()

    def test_staged_file_is_selected_by_actual_controller_prefix(self):
        config = copy.deepcopy(self.t.config)
        final = str(self.t.f.root / 'not-published.env')
        config['compose_env'] = final
        config['initial_transition']['protected_inputs'][0]['path'] = final
        selected = Path(self.t.config['compose_env'])
        construct = commissioning.initial.InitialDockerOwner
        def factory(runtime):
            self.assertEqual(runtime['compose_env'], str(selected))
            owner = construct(runtime, command=self.t.docker.command)
            self.assertEqual(owner.prefix[owner.prefix.index('--env-file') + 1], str(selected))
            owner.container = self.t.docker.container
            owner.retirement = self.t.docker.retirement
            owner.capacity = self.t.docker.capacity
            return owner
        with self.t.root_operator(), patch.object(commissioning, 'FINAL_ENV', final), \
                patch.object(commissioning.initial, 'InitialDockerOwner', side_effect=factory):
            result = commissioning.preflight(config, commissioning.M3B, selected, source_view=self.t.f.repo)
        self.assertEqual(set(result['effective_hashes']), set(commissioning.SIX))
        self.assertFalse(Path(final).exists()); self.t.assert_no_up()

    def test_every_service_hash_drift_fails(self):
        for name in commissioning.SIX:
            original = self.t.f.hashes[name]
            self.t.f.hashes[name] = 'f' * 64
            with self.subTest(name=name), self.assertRaisesRegex(Rejected, 'running_configuration_drift'):
                self.preflight()
            self.t.f.hashes[name] = original
        self.t.assert_no_up()

    def test_container_and_runtime_drift_fail(self):
        self.t.f.live['caddy']['id'] = 'f' * 64
        with self.assertRaisesRegex(Rejected, 'support_image_or_container_drift'):
            self.preflight()
        self.t.f.live['caddy']['id'] = self.t.config['compose_services']['caddy']['container_id']
        self.t.f.live['caddy']['restart'] = 'always'
        with self.assertRaisesRegex(Rejected, 'running_relationship_drift'):
            self.preflight()
        self.t.assert_no_up()

    def test_legacy_provenance_remains_unknown_and_health_is_required(self):
        self.t.f.live['api']['labels']['org.opencontainers.image.revision'] = self.t.f.sha
        with self.assertRaisesRegex(Rejected, 'initial_legacy_identity_changed'):
            self.preflight()
        self.t.f.live['api']['labels'].pop('org.opencontainers.image.revision')
        self.t.f.live['github-webhook']['state']['Health']['Status'] = 'unhealthy'
        with self.assertRaisesRegex(Rejected, 'support_service_unhealthy'):
            self.preflight()
        self.t.assert_no_up()

    def test_unapproved_external_policy_fails_before_docker(self):
        external = input_fixtures.ProtectedInputTests('runTest')
        external.setUp(); self.addCleanup(external.doCleanups)
        external.external()
        item = external.item
        item['policy_record']['sha256'] = '0' * 64
        with external.t.root_operator(), self.assertRaisesRegex(Rejected, 'external_secret_policy_changed'):
            private.checked_input(item)
        external.t.assert_no_up()


class TransactionTests(FileFixture):
    def setUp(self):
        super().setUp()
        self.inputs = self.root / 'inputs'; self.inputs.mkdir(mode=0o700)
        self.config_dir = self.root / 'configs'; self.config_dir.mkdir(mode=0o700)
        self.stages = self.root / 'stages'; self.stages.mkdir(mode=0o700)
        self.stage_path = self.stages / 'transaction'
        self.approvals = self.root / 'approvals'; self.approvals.mkdir(mode=0o700)
        original = self.inputs / 'original.env'; original.write_bytes(b'PRIVATE=synthetic\n'); original.chmod(0o400)
        final = self.inputs / 'm4.env'; final_config = self.config_dir / 'initial.json'
        owner = self.config_dir / 'owner.json'; owner.write_bytes(b'{"commissioned":false}'); owner.chmod(0o400)
        history = {}
        for name in commissioning.HISTORY:
            p = owner if name == 'disabled_owner' else self.root / (name + '.fixture')
            if p != owner:
                p.write_bytes(('synthetic historical ' + name).encode()); p.chmod(0o400)
            history[name] = str(p)
        for name, value in (('ORIGINAL_ENV', str(original)), ('FINAL_ENV', str(final)),
                            ('FINAL_CONFIG', str(final_config)), ('OWNER_CONFIG', str(owner)), ('HISTORY', history)):
            self.enterContext(patch.object(commissioning, name, value))
        config = dict(commissioned=False, environment='dev', project_ref=DEV_PROJECT, compose_env=str(final),
            compose_layers=[dict(approval=None)] * 5, compose_artifacts=[dict(approval=None)],
            compose_services={name: dict(image_id='sha256:' + '1' * 64) for name in commissioning.SIX},
            registry=dict(approval=None), repository=str(self.root / 'source.git'),
            state_root=str(self.root / 'state'), report_root=str(self.root / 'report'),
            docker_config=str(self.root / 'auth'), initial_transition=dict(enabled=False, acceptance_required=True,
            approval_root=str(self.approvals), image='ghcr.io/sharanravi954mf/moneybowl-ingestion-dev@' +
            commissioning.initial.CANDIDATE, recovery=dict(archive=history['recovery_archive'],
            record=history['recovery_record'], sha256=sha256(Path(history['recovery_archive']).read_bytes()),
            record_sha256=sha256(Path(history['recovery_record']).read_bytes()), approval=None),
            protected_inputs=[dict(path=str(final), policy='root-private-v1', approval=None)] +
            [dict(path=v['path'], approval=None) for v in private.EXTERNAL_SECRETS.values()]))
        Path(config['state_root']).mkdir(mode=0o700)
        def item(path):
            with self.authority():
                return dict(path=str(path), identity=private.identity(Path(path).lstat()),
                            sha256=sha256(Path(path).read_bytes()), approval='synthetic-independent-original-review')
        self.request = dict(kind='moneybowl-m4-commissioning-request-v1', config=config,
                            original_input=item(original), preserved={k: item(p) for k, p in history.items()},
                            m3b=copy.deepcopy(commissioning.M3B))
        # Engine inspection has separate transport tests. Never contact a live daemon.
        self.inspect_mock = self.enterContext(patch.object(commissioning, 'inspect', return_value={}))
        self.preflight = self.enterContext(patch.object(commissioning, 'preflight', return_value=dict(verified='synthetic')))
        self.baseline_path = self.approvals / 'baseline.json'
        self.approval_path = self.approvals / 'publish.json'

    def stage(self):
        with self.authority():
            return commissioning.stage(self.request, self.stage_path)

    def baseline(self):
        with self.authority():
            value = commissioning.staged(self.stage_path)
            config = copy.deepcopy(value['config'])
            config['initial_transition']['enabled'] = True
            for item in config['compose_layers'] + config['compose_artifacts'] + config['initial_transition']['protected_inputs']:
                item['approval'] = 'synthetic-independent-baseline-review'
            config['registry']['approval'] = config['initial_transition']['recovery']['approval'] = 'synthetic-review'
            baseline = dict(kind='moneybowl-m4-commissioning-baseline-v1', config=config, owner_review='synthetic-review',
                stage_sha256=commissioning.inventory.digest(value), ingress_tag_review=dict(
                reference=commissioning.M3B['M3B_INGRESS_ADAPTER_IMAGE'], image_id='sha256:' + '1' * 64,
                owner_review='synthetic-tag-retention-review', preserve_without_pull=True),
                recovery_review=dict(offhost_retention_review='synthetic-retention-review',
                restoration_readiness_review='synthetic-recovery-review', rollback_requires_separate_authorization=True))
            commissioning.create(self.baseline_path, commissioning.json_bytes(baseline))
        return sha256(self.baseline_path.read_bytes())

    def review(self, digest):
        with self.authority():
            return commissioning.review(self.stage_path, self.baseline_path, digest)

    def approve(self, digest):
        report = self.review(digest)
        approval = dict(kind='moneybowl-m4-commissioning-publication-v1', environment='dev', project_ref=DEV_PROJECT,
            review_sha256=commissioning.inventory.digest(report), baseline_sha256=digest,
            stage_sha256=report['stage_sha256'], owner_review='synthetic-publication-owner', nonce='a' * 64,
            expires_at=1000 + 300, targets=[commissioning.FINAL_ENV, commissioning.FINAL_CONFIG],
            api_activation_authorized=False)
        with self.authority():
            commissioning.create(self.approval_path, commissioning.json_bytes(approval))

    def publish(self, digest):
        with self.authority():
            return commissioning.publish_stage(self.stage_path, self.baseline_path, digest,
                                                self.approval_path, now=lambda: 1000)

    def test_staging_is_inactive_originals_preserved_and_exclusive(self):
        originals = {p: Path(p).read_bytes() for p in commissioning.HISTORY.values()}
        self.stage()
        with self.authority():
            staged = commissioning.staged(self.stage_path)
        self.assertFalse(staged['config']['commissioned'])
        self.assertFalse(staged['config']['initial_transition']['enabled'])
        self.assertIsNone(staged['config']['initial_transition']['protected_inputs'][0]['approval'])
        self.assertFalse(Path(commissioning.FINAL_ENV).exists())
        self.assertFalse(Path(commissioning.FINAL_CONFIG).exists())
        with self.assertRaises(FileExistsError):
            self.stage()
        self.assertEqual(originals, {p: Path(p).read_bytes() for p in originals})

    def test_staging_sync_failure_is_terminal_unknown_never_retried(self):
        original_create = commissioning.create
        def fail(path, data):
            if Path(path).name == 'compose.env':
                original_create(path, data)
                raise OSError('synthetic fsync outcome unknown')
            return original_create(path, data)
        with patch.object(commissioning, 'create', side_effect=fail), self.assertRaises(OSError):
            self.stage()
        self.assertTrue((self.stage_path / '99-unknown.json').exists())
        with self.authority(), self.assertRaisesRegex(Rejected, 'commissioning_outcome_requires_review'):
            commissioning.staged(self.stage_path)
        with self.assertRaises(FileExistsError):
            self.stage()

    def test_replaced_stage_inode_rejected_even_with_same_bytes(self):
        self.stage()
        env = self.stage_path / 'compose.env'
        replacement = self.stage_path / 'replacement'; replacement.write_bytes(env.read_bytes()); replacement.chmod(0o400)
        replacement.replace(env)
        with self.authority(), self.assertRaisesRegex(Rejected, 'commissioning_stage_env_changed'):
            commissioning.staged(self.stage_path)

    def test_independent_baseline_cannot_change_any_nonapproval_binding(self):
        self.stage(); digest = self.baseline()
        baseline = json.loads(self.baseline_path.read_bytes()); baseline['config']['compose_services']['api']['image_id'] = 'changed'
        self.baseline_path.chmod(0o600); self.baseline_path.write_bytes(commissioning.json_bytes(baseline)); self.baseline_path.chmod(0o400)
        digest = sha256(self.baseline_path.read_bytes())
        with self.assertRaisesRegex(Rejected, 'commissioning_baseline_changes_draft'):
            self.review(digest)

    def test_unapproved_baseline_is_not_created_by_review(self):
        self.stage()
        with self.authority(), self.assertRaises(FileNotFoundError):
            commissioning.review(self.stage_path, self.baseline_path, '0' * 64)
        self.assertFalse(self.baseline_path.exists())
        self.assertFalse(Path(commissioning.FINAL_CONFIG).exists())

    def test_review_does_not_install_or_enable_anything(self):
        self.stage(); digest = self.baseline()
        before = set(self.stage_path.iterdir())
        result = self.review(digest)
        self.assertFalse(result['activation_authorized'])
        self.assertEqual(set(self.stage_path.iterdir()), before)
        self.assertFalse(Path(commissioning.FINAL_ENV).exists())

    def test_publish_requires_independent_root_authority_and_exact_review(self):
        self.stage(); digest = self.baseline(); self.approve(digest)
        self.untrusted.add(self.approval_path)
        with self.assertRaisesRegex(Rejected, 'approval_authority_invalid'):
            self.publish(digest)
        self.untrusted.clear()
        self.preflight.return_value = dict(verified='changed-after-approval')
        with self.assertRaisesRegex(Rejected, 'commissioning_publication_approval_invalid'):
            self.publish(digest)
        self.assertFalse((self.stage_path / '30-publish-intent.json').exists())
        self.assertFalse(Path(commissioning.FINAL_ENV).exists())

    def test_success_preserves_reviewed_inode_and_history_and_never_prepares(self):
        before = {p: Path(p).read_bytes() for p in commissioning.HISTORY.values()}
        stage = self.stage(); digest = self.baseline(); self.approve(digest)
        self.assertEqual(self.publish(digest)['state'], 'PUBLISHED_NOT_PREPARED')
        with self.authority():
            self.assertEqual(private.identity(Path(commissioning.FINAL_ENV).lstat()), stage['env_identity'])
        self.assertEqual(Path(commissioning.FINAL_ENV).stat().st_nlink, 1)
        self.assertEqual(before, {p: Path(p).read_bytes() for p in before})
        self.assertEqual(list(Path(self.request['config']['state_root']).iterdir())[0].name, '.owner.lock')
        with self.assertRaisesRegex(Rejected, 'commissioning_outcome_requires_review'):
            self.publish(digest)

    def test_partial_publication_is_retained_and_retry_is_blocked(self):
        self.stage(); digest = self.baseline(); self.approve(digest)
        create = commissioning.create
        def fail(path, data):
            if str(path) == commissioning.FINAL_CONFIG:
                raise OSError('synthetic disk failure')
            return create(path, data)
        with patch.object(commissioning, 'create', side_effect=fail), self.assertRaises(OSError):
            self.publish(digest)
        self.assertTrue(Path(commissioning.FINAL_ENV).exists())
        self.assertFalse(Path(commissioning.FINAL_CONFIG).exists())
        self.assertTrue((self.stage_path / '30-publish-intent.json').exists())
        with self.assertRaisesRegex(Rejected, 'commissioning_outcome_requires_review'):
            self.publish(digest)

    def test_historical_recovery_identity_change_blocks_review(self):
        self.stage(); digest = self.baseline()
        original = Path(commissioning.HISTORY['recovery_archive'])
        replacement = self.root / 'replacement'; replacement.write_bytes(original.read_bytes()); replacement.chmod(0o400)
        replacement.replace(original)
        with self.assertRaisesRegex(Rejected, 'private_input_identity_changed'):
            self.review(digest)
        self.preflight.assert_not_called()

    def test_retained_initial_state_blocks_review_without_rewriting_it(self):
        self.stage(); digest = self.baseline()
        journal = Path(self.request['config']['state_root']) / 'initial-transition.json'
        journal.write_bytes(b'{"state":"UNKNOWN"}'); journal.chmod(0o400)
        with self.assertRaisesRegex(Rejected, 'commissioning_initial_state_requires_review'):
            self.review(digest)
        self.assertEqual(journal.read_bytes(), b'{"state":"UNKNOWN"}')

    def test_unresolved_tag_or_recovery_review_cannot_advance(self):
        self.stage(); self.baseline()
        original = json.loads(self.baseline_path.read_bytes())
        for field, key, reason in (('ingress_tag_review', 'owner_review', 'commissioning_tag_review_missing'),
                                  ('recovery_review', 'offhost_retention_review', 'commissioning_recovery_review_missing')):
            value = copy.deepcopy(original); value[field][key] = None
            self.baseline_path.chmod(0o600); self.baseline_path.write_bytes(commissioning.json_bytes(value)); self.baseline_path.chmod(0o400)
            with self.subTest(field=field), self.assertRaisesRegex(Rejected, reason):
                self.review(sha256(self.baseline_path.read_bytes()))
        self.preflight.assert_not_called()

    def test_existing_target_is_preserved_instead_of_overwritten(self):
        self.stage(); digest = self.baseline()
        config = Path(commissioning.FINAL_CONFIG); config.write_bytes(b'independently-approved-existing'); config.chmod(0o400)
        with self.assertRaisesRegex(Rejected, 'commissioning_destination_exists'):
            self.review(digest)
        self.assertEqual(config.read_bytes(), b'independently-approved-existing')


if __name__ == '__main__':
    unittest.main()
