"""Synthetic secrets only; never read credentials, invoke Docker or acquire root."""
import copy
import os
import unittest
from pathlib import Path
from unittest.mock import patch

import initial_private_inputs as inputs
from contract import DEV_PROJECT, Rejected
from ingestion_owner import DockerOwner
from owner_common import sha256
from protected_io import protected, publish, read_private
import test_initial_api_transition as transition_fixtures


class ProtectedInputTests(unittest.TestCase):
    def setUp(self):
        self.t = transition_fixtures.TransitionTests('runTest')
        self.t.setUp(); self.addCleanup(self.t.doCleanups)
        self.root = self.t.f.root
        self.secret = self.root / 'external-secret'
        self.secret.write_bytes(b'fixture-only-secret'); self.secret.chmod(0o440)
        self.record = self.root / 'external-policy.json'

    def external(self, name='m3b-webhook-v1'):
        rule = {**inputs.EXTERNAL_SECRETS[name], 'path': str(self.secret)}
        self.enterContext(patch.dict(inputs.EXTERNAL_SECRETS, {name: rule}))
        original = self.t.root_operator
        self.overrides = {self.secret: dict(gid=rule['gid'])}
        self.t.root_operator = lambda untrusted=(), metadata_overrides=None: original(
            untrusted, {**self.overrides, **(metadata_overrides or {})})
        with self.t.root_operator():
            identity = inputs.identity(self.secret.lstat())
        self.item = dict(path=str(self.secret), policy=name, identity=identity,
                         sha256=sha256(self.secret.read_bytes()), approval='fixture-independent-input-review')
        value = dict(kind='moneybowl-external-secret-policy-v1', environment='dev', project_ref=DEV_PROJECT,
                     policy=name, **rule, uid=0, mode=0o440, read_only=True, identity=identity,
                     sha256=self.item['sha256'], owner_review='fixture-independent-policy-review')
        publish(self.record, value)
        self.item['policy_record'] = dict(path=str(self.record), sha256=sha256(self.record.read_bytes()))
        self.t.config['initial_transition']['protected_inputs'].append(self.item)
        self.container = self.t.f.live[rule['service']]
        self.mount = dict(Type='bind', Source=str(self.secret), Destination=rule['destination'], RW=False)
        self.container['mounts'] = [self.mount]
        self.container['security']['user'] = rule['runtime_user']
        self.review_runtime()
        return self.item

    def review_runtime(self):
        # Synthetic independent baseline only. No host baseline is discovered/approved here.
        from compose_inventory import runtime_identity
        for service, value in self.t.f.live.items():
            self.t.config['compose_services'][service]['runtime_sha256'] = runtime_identity(value)

    def assert_blocked(self, reason):
        with self.assertRaisesRegex(Rejected, reason):
            self.t.prepare()
        self.t.assert_no_up()
        self.assertFalse((self.t.state / 'initial-plan.json').exists())
        self.assertFalse((self.t.state / (self.t.f.sha + '.provenance.json')).exists())

    def test_m3b_group_reader_with_root_policy_completes_all_synthetic_phases(self):
        self.external()
        self.assertEqual(self.t.prepare()['state'], 'PREPARED')
        plan = read_private(self.t.state / 'initial-plan.json')
        self.assertEqual(plan['private_inputs'][str(self.secret)], dict(
            sha256=self.item['sha256'], identity=self.item['identity'],
            policy_sha256=self.item['policy_record']['sha256']))
        self.assertNotIn('fixture-only-secret', str(plan))
        with self.t.root_operator(), self.assertRaisesRegex(Rejected, 'protected_permissions_invalid'):
            protected(self.secret)  # No global protected() relaxation.
        self.assertEqual(self.t.activate()['state'], 'ACTIVATED_NOT_VERIFIED')
        self.assertEqual(self.t.verify()['state'], 'VERIFIED')
        self.assertEqual(self.secret.stat().st_mode & 0o777, 0o440)

    def test_protected_webhook_migration_preserves_non_root_reader(self):
        self.external('github-webhook-v1')
        self.assertEqual(self.t.prepare()['state'], 'PREPARED')
        self.assertEqual(self.t.activate()['state'], 'ACTIVATED_NOT_VERIFIED')
        self.assertEqual(self.t.verify()['state'], 'VERIFIED')
        self.assertEqual(self.container['security']['user'], '1001:1001')

    def test_group_readable_without_external_policy_fails_before_read(self):
        item = self.external(); item.pop('policy'); item.pop('policy_record')
        with patch.object(inputs.os, 'open') as opened:
            with self.t.root_operator(), self.assertRaisesRegex(Rejected, 'approval_authority_invalid'):
                inputs.binding(item)
        opened.assert_not_called()

    def test_same_bytes_new_inode_rejected_before_activation(self):
        self.external(); self.t.prepare()
        replacement = self.root / 'replacement'
        replacement.write_bytes(self.secret.read_bytes()); replacement.chmod(0o440)
        replacement.replace(self.secret)
        result = self.t.activate()
        self.assertEqual(result['reason'], 'private_input_identity_changed'); self.t.assert_no_up()

    def test_root_private_same_bytes_new_inode_is_also_rejected(self):
        self.t.prepare(); path = Path(self.t.config['compose_env'])
        replacement = self.root / 'replacement'
        replacement.write_bytes(path.read_bytes()); replacement.chmod(0o600); replacement.replace(path)
        self.assertEqual(self.t.activate()['reason'], 'private_input_identity_changed'); self.t.assert_no_up()

    def test_external_owner_substitution_rejected(self):
        self.external(); self.overrides[self.secret]['uid'] = 993
        self.assert_blocked('private_input_identity_changed')

    def test_wrong_group_cannot_be_approved_by_record(self):
        self.external(); self.overrides[self.secret]['gid'] = 983
        self.item['identity']['gid'] = 983
        self.assert_blocked('external_secret_permissions_invalid')

    def test_missing_identity_is_not_auto_approved(self):
        self.t.config['initial_transition']['protected_inputs'][0].pop('identity')
        self.assert_blocked('private_input_identity_unapproved')

    def test_duplicate_inputs_rejected(self):
        items = self.t.config['initial_transition']['protected_inputs']; items.append(copy.deepcopy(items[0]))
        self.assert_blocked('private_inputs_unapproved')

    def test_writable_external_ancestor_rejected_before_read(self):
        self.external(); self.root.chmod(0o770)
        with self.t.root_operator(), patch.object(inputs.os, 'open') as opened:
            with self.assertRaisesRegex(Rejected, 'private_input_parent_invalid'):
                inputs.binding(self.item)
        opened.assert_not_called()

    def test_application_owned_ancestor_cannot_be_whitelisted(self):
        self.external()
        with self.t.root_operator(untrusted=(self.root,)), patch.object(inputs.os, 'open') as opened:
            with self.assertRaisesRegex(Rejected, 'private_input_parent_invalid'):
                inputs.binding(self.item)
        opened.assert_not_called()

    def test_root_private_under_application_ancestor_rejected_before_read(self):
        item = self.t.config['initial_transition']['protected_inputs'][0]
        with self.t.root_operator(untrusted=(self.root,)), patch.object(inputs.os, 'open') as opened:
            with self.assertRaisesRegex(Rejected, 'approval_authority_invalid'):
                inputs.binding(item)
        opened.assert_not_called()

    def test_external_policy_rejects_other_paths(self):
        self.external(); self.item['path'] = '/home/ubuntu/.config/moneybowl/github-webhook-secret'
        self.assert_blocked('external_secret_path_unapproved')  # No read of the real path.

    def test_unknown_policy_cannot_waive_ancestry(self):
        self.external(); self.item['policy'] = 'allow-home-v1'
        self.assert_blocked('external_secret_policy_unapproved')

    def test_external_secret_cannot_be_compose_interpolation_input(self):
        self.external(); self.t.config['compose_env'] = str(self.secret)
        self.assert_blocked('private_inputs_unapproved')

    def test_secret_leaf_symlink_rejected(self):
        self.external(); saved = self.root / 'saved'; self.secret.rename(saved); self.secret.symlink_to(saved)
        self.assert_blocked('private_input_path_invalid')

    def test_secret_parent_symlink_rejected(self):
        self.external(); alias = self.root / 'alias'; alias.symlink_to(self.root, target_is_directory=True)
        self.item['path'] = str(alias / self.secret.name)
        with patch.dict(inputs.EXTERNAL_SECRETS, {self.item['policy']: {
            **inputs.EXTERNAL_SECRETS[self.item['policy']], 'path': self.item['path']}}):
            self.assert_blocked('private_input_path_invalid')

    def test_secret_hardlink_rejected(self):
        self.external(); os.link(self.secret, self.root / 'linked')
        self.assert_blocked('private_input_file_invalid')

    def test_more_readable_or_writable_external_modes_cannot_be_approved(self):
        self.external()
        for mode in (0o640, 0o444, 0o460, 0o400):
            with self.subTest(mode=oct(mode)):
                self.overrides[self.secret]['mode'] = mode
                self.item['identity']['mode'] = mode
                with self.t.root_operator(), self.assertRaisesRegex(Rejected, 'external_secret_permissions_invalid'):
                    inputs.binding(self.item)

    def test_extra_acl_reader_rejected(self):
        self.external(); original = os.listxattr
        with patch.object(inputs.os, 'listxattr', side_effect=lambda path, **kw:
                          ['system.posix_acl_access'] if Path(path) == self.secret else original(path, **kw)):
            self.assert_blocked('private_input_acl_unapproved')

    def test_parent_default_acl_rejected(self):
        self.external(); original = os.listxattr
        with self.t.root_operator(), patch.object(inputs.os, 'listxattr', side_effect=lambda path, **kw:
                ['system.posix_acl_default'] if Path(path) == self.root else original(path, **kw)):
            with self.assertRaisesRegex(Rejected, 'private_input_acl_unapproved'):
                inputs.binding(self.item)

    def test_executor_owned_policy_is_not_independent_authority(self):
        self.external()
        with self.t.root_operator(untrusted=(self.record,)):
            with self.assertRaisesRegex(Rejected, 'approval_authority_invalid'):
                inputs.binding(self.item)

    def test_policy_symlink_rejected(self):
        self.external(); alias = self.root / 'policy-link'; alias.symlink_to(self.record)
        self.item['policy_record']['path'] = str(alias)
        self.assert_blocked('approval_authority_invalid')

    def test_policy_changed_after_prepare_blocks_activation(self):
        self.external(); self.t.prepare(); self.record.write_bytes(b'{}')
        self.assertEqual(self.t.activate()['reason'], 'external_secret_policy_changed'); self.t.assert_no_up()

    def test_root_policy_wrong_runtime_scope_is_not_authority(self):
        self.external(); value = read_private(self.record); value['runtime_user'] = '0'
        publish(self.record, value); self.item['policy_record']['sha256'] = sha256(self.record.read_bytes())
        self.assert_blocked('external_secret_policy_unapproved')

    def test_root_policy_wrong_project_is_not_authority(self):
        self.external(); value = read_private(self.record); value['project_ref'] = 'production'
        publish(self.record, value); self.item['policy_record']['sha256'] = sha256(self.record.read_bytes())
        self.assert_blocked('external_secret_policy_unapproved')

    def test_secret_content_drift_after_prepare_blocks_activation(self):
        self.external(); self.t.prepare(); self.secret.chmod(0o600)
        self.secret.write_bytes(b'changed-fixture-secret'); self.secret.chmod(0o440)
        self.assertEqual(self.t.activate()['reason'], 'private_input_changed'); self.t.assert_no_up()

    def test_root_policy_missing_independent_review_rejected(self):
        self.external(); value = read_private(self.record); value['owner_review'] = ''
        publish(self.record, value); self.item['policy_record']['sha256'] = sha256(self.record.read_bytes())
        self.assert_blocked('external_secret_policy_unapproved')

    def test_policy_cannot_substitute_for_single_use_activation_approval(self):
        self.external(); self.t.prepare()
        approval = Path(self.t.config['initial_transition']['approval_root']) / 'wrong-kind.json'
        publish(approval, read_private(self.record))
        self.assertEqual(self.t.activate(approval)['reason'], 'owner_approval_invalid'); self.t.assert_no_up()

    def test_non_root_cannot_validate_or_create_its_own_external_policy(self):
        self.external()
        with patch('os.getuid', return_value=993), patch('os.geteuid', return_value=993), \
                self.assertRaisesRegex(Rejected, 'cutover_requires_root_operator'):
            inputs.binding(self.item)

    def test_replacement_between_check_and_open_rejected(self):
        item = self.t.config['initial_transition']['protected_inputs'][0]
        path = Path(item['path']); replacement = self.root / 'replacement'
        replacement.write_bytes(path.read_bytes()); replacement.chmod(0o600)
        original = os.open
        def substitute(location, flags, *args, **kwargs):
            if Path(location) == path:
                replacement.replace(path)
            return original(location, flags, *args, **kwargs)
        with self.t.root_operator(), patch.object(inputs.os, 'open', side_effect=substitute):
            with self.assertRaisesRegex(Rejected, 'private_input_identity_changed'):
                inputs.binding(item)

    def test_policy_replacement_rejected_before_reading_replacement(self):
        self.external(); replacement = self.root / 'replacement'
        replacement.write_bytes(self.record.read_bytes()); replacement.chmod(0o600)
        original = os.open
        def substitute(location, flags, *args, **kwargs):
            if Path(location) == self.record:
                replacement.replace(self.record)
            return original(location, flags, *args, **kwargs)
        with self.t.root_operator(), patch.object(inputs.os, 'open', side_effect=substitute), \
                patch.object(inputs.os, 'read') as read:
            with self.assertRaisesRegex(Rejected, 'private_input_identity_changed'):
                inputs.binding(self.item)
        read.assert_not_called()

    def test_concurrent_content_change_rejected(self):
        item = self.t.config['initial_transition']['protected_inputs'][0]
        original = os.read
        def change(fd, size):
            data = original(fd, size)
            if data:
                Path(item['path']).write_bytes(b'altered-and-different-length')
            return data
        with self.t.root_operator(), patch.object(inputs.os, 'read', side_effect=change):
            with self.assertRaisesRegex(Rejected, 'private_input_changed_during_read'):
                inputs.binding(item)

    def test_raw_docker_cannot_commission_uid_993_even_with_socket_access(self):
        self.t.config['commissioned'] = True
        with patch('os.getuid', return_value=993), patch('os.geteuid', return_value=993), \
                patch('os.access', return_value=True), patch('ingestion_owner.Registry') as registry, \
                patch('ingestion_owner.Command') as command:
            with self.assertRaisesRegex(Rejected, 'docker_execution_boundary_uncommissioned'):
                DockerOwner(self.t.config)
        registry.assert_not_called(); command.assert_not_called()

    def test_partial_root_identity_does_not_authorize_raw_transport(self):
        for real, effective in ((0, 993), (993, 0), (1001, 1001)):
            with self.subTest(real=real, effective=effective), patch('os.getuid', return_value=real), \
                    patch('os.geteuid', return_value=effective), patch('ingestion_owner.Command') as command:
                with self.assertRaisesRegex(Rejected, 'docker_execution_boundary_uncommissioned'):
                    DockerOwner(self.t.config)
                command.assert_not_called()

    def exposure_mount(self, category, form):
        if category == 'external':
            # Isolate this directory from the private interpolation input so the
            # regression proves the external policy independently rejects exposure.
            directory = self.root / 'runtime-secrets'; directory.mkdir(mode=0o700)
            self.secret.rename(directory / self.secret.name)
            self.secret = directory / self.secret.name
            self.external()
            path = self.secret
        else:
            path = Path(self.t.config['compose_env'])
        source = path if form in ('direct', 'file_alias', 'component_alias', 'normalized') else path.parent
        if form in ('file_alias', 'directory_alias'):
            alias = self.root / 'source-alias'; alias.symlink_to(source, target_is_directory=source.is_dir())
            source = alias
        elif form == 'component_alias':
            alias = self.root / 'parent-alias'; alias.symlink_to(path.parent, target_is_directory=True)
            source = alias / path.name
        elif form == 'normalized':
            source = str(path.parent / 'child' / '..' / path.name)
            (path.parent / 'child').mkdir()
        self.t.f.live['caddy']['mounts'].append(dict(Type='bind', Source=str(source), Destination='/exposure', RW=False))
        self.review_runtime()  # A reviewed runtime fingerprint cannot authorize private-input exposure.

    def test_prepare_rejects_external_secret_directory_exposure(self):
        self.exposure_mount('external', 'directory')
        self.assert_blocked('external_secret_mount_unapproved')

    def test_prepare_rejects_private_compose_input_direct_exposure(self):
        self.exposure_mount('private', 'direct')
        self.assert_blocked('private_input_mount_unapproved')

    def test_approved_external_reader_cannot_mount_parent_directory(self):
        self.exposure_mount('external', 'directory')
        self.t.f.live['caddy']['mounts'] = []
        self.mount['Source'] = str(self.secret.parent)
        self.review_runtime()
        self.assert_blocked('external_secret_mount_unapproved')

    def test_approved_external_reader_cannot_substitute_symlink_alias(self):
        self.external(); alias = self.root / 'alias'; alias.symlink_to(self.secret)
        self.mount['Source'] = str(alias)
        self.review_runtime()
        self.assert_blocked('external_secret_mount_unapproved')

    def test_private_compose_input_is_not_authorized_for_api_either(self):
        self.exposure_mount('private', 'direct')
        self.t.f.live['api']['mounts'] = self.t.f.live['caddy']['mounts']
        self.t.f.live['caddy']['mounts'] = []
        self.review_runtime()
        self.assert_blocked('private_input_mount_unapproved')

    def test_unresolvable_bind_alias_fails_closed(self):
        self.external(); alias = self.root / 'dangling'; alias.symlink_to(self.root / 'missing')
        self.t.f.live['caddy']['mounts'] = [dict(Type='bind', Source=str(alias), Destination='/alias', RW=False)]
        self.review_runtime()
        self.assert_blocked('private_bind_source_unverifiable')

    def test_cyclic_bind_alias_fails_closed(self):
        alias = self.root / 'cycle'; alias.symlink_to(alias)
        self.t.f.live['caddy']['mounts'] = [dict(Type='bind', Source=str(alias), Destination='/alias', RW=False)]
        self.review_runtime()
        self.assert_blocked('private_bind_source_unverifiable')

    def test_legitimate_public_directories_aliases_and_existing_mounts_preserved(self):
        self.external()
        directory = self.root / 'external-secret-public'; directory.mkdir()
        volume = directory / 'volume-data'; volume.mkdir()
        alias = self.root / 'public-alias'; alias.symlink_to(directory, target_is_directory=True)
        self.t.f.live['caddy']['mounts'] = [
            dict(Type='bind', Source=str(directory), Destination='/public', RW=False),
            dict(Type='bind', Source=str(alias), Destination='/public-alias', RW=False),
            dict(Type='bind', Source=str(self.t.f.runtime / 'Caddyfile'), Destination='/etc/caddy/Caddyfile', RW=False),
            dict(Type='volume', Source=str(volume), Destination='/data', RW=True),
        ]
        self.review_runtime()
        before = copy.deepcopy({k: v['mounts'] for k, v in self.t.f.live.items()})
        self.assertEqual(len(self.t.config['compose_layers']), 5)
        self.assertEqual(self.t.prepare()['state'], 'PREPARED')
        self.assertEqual(self.t.activate()['state'], 'ACTIVATED_NOT_VERIFIED')
        self.assertEqual(self.t.verify()['state'], 'VERIFIED')
        self.assertEqual({k: v['mounts'] for k, v in self.t.f.live.items()}, before)


def exposure_case(category, form):
    def test(self):
        self.exposure_mount(category, form)
        self.assert_blocked('external_secret_mount_unapproved' if category == 'external'
                            else 'private_input_mount_unapproved')
    return test


def previously_prepared_exposure_case(category):
    def test(self):
        self.exposure_mount(category, 'directory' if category == 'external' else 'direct')
        # Model a plan prepared by the vulnerable validator, without changing approval authority.
        with patch.object(inputs, 'bind_mounts'):
            self.assertEqual(self.t.prepare()['state'], 'PREPARED')
        approval = self.t.approval()
        result = self.t.activate(approval)
        self.assertEqual(result['state'], 'FAILED')
        self.assertEqual(result['reason'], 'external_secret_mount_unapproved' if category == 'external'
                         else 'private_input_mount_unapproved')
        self.t.assert_no_up()
        self.assertFalse(list(self.t.state.glob('approval-*.consumed.json')))
    return test


def previously_activated_exposure_case(category):
    def test(self):
        self.exposure_mount(category, 'directory' if category == 'external' else 'direct')
        # Model the older controller's acceptance; new VERIFY must not publish success.
        with patch.object(inputs, 'bind_mounts'):
            self.t.prepare()
            self.assertEqual(self.t.activate()['state'], 'ACTIVATED_NOT_VERIFIED')
        result = self.t.verify()
        self.assertEqual(result['state'], 'FAILED')
        self.assertEqual(result['reason'], 'external_secret_mount_unapproved' if category == 'external'
                         else 'private_input_mount_unapproved')
        self.assertFalse((self.t.state / 'initial-service-receipt.json').exists())
        self.assertFalse((self.t.state / (self.t.f.sha + '.provenance.json')).exists())
    return test


for category, forms in (
    ('external', ('direct', 'file_alias', 'directory_alias', 'component_alias', 'normalized')),
    ('private', ('directory', 'file_alias', 'directory_alias', 'component_alias', 'normalized')),
):
    setattr(ProtectedInputTests, 'test_activation_rejects_previous_unsafe_plan_' + category,
            previously_prepared_exposure_case(category))
    setattr(ProtectedInputTests, 'test_verification_rejects_previous_unsafe_plan_' + category,
            previously_activated_exposure_case(category))
    for form in forms:
        setattr(ProtectedInputTests, 'test_prepare_rejects_' + category + '_exposure_' + form,
                exposure_case(category, form))


def bad_mount_case(mutate, reason):
    def test(self):
        self.external(); mutate(self); self.review_runtime()
        self.assert_blocked(reason)
    return test


for name, mutate, reason in (
    ('writable', lambda s: s.mount.update(RW=True), 'private_input_mount_writable'),
    ('wrong_user', lambda s: s.container['security'].update(user='0'), 'external_secret_mount_unapproved'),
    ('wrong_destination', lambda s: s.mount.update(Destination='/wrong'), 'external_secret_mount_unapproved'),
    ('wrong_service', lambda s: s.container['labels'].update({'com.docker.compose.service': 'api'}),
     'container_owner_mismatch'),
    ('absent', lambda s: s.container.update(mounts=[]), 'external_secret_mount_unapproved'),
    ('duplicate', lambda s: s.container['mounts'].append(copy.deepcopy(s.mount)), 'external_secret_mount_unapproved'),
    ('another_reader', lambda s: s.t.f.live['caddy']['mounts'].append(copy.deepcopy(s.mount)),
     'external_secret_mount_unapproved'),
):
    setattr(ProtectedInputTests, 'test_external_mount_' + name, bad_mount_case(mutate, reason))


if __name__ == '__main__':
    unittest.main()
