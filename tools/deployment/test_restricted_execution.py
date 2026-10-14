"""Synthetic, offline boundary regressions. No Engine, registry or financial APIs."""
import copy
import io
import json
import os
import socket
import stat
import struct
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

import restricted_execution as boundary
from contract import DEV_PROJECT, REPOSITORY, Rejected
from ingestion_owner import DockerOwner
from owner_common import Command, sha256
from protected_io import deployment_lock
from test_initial_api_transition import synthetic_root_authority
from test_commissioning_readiness import FileFixture

NOW = 1800000000
SHA = 'a' * 40
PEER = (123, 993, 983)


class Fixture(unittest.TestCase):
    def setUp(self):
        synthetic_root_authority(self)
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.pins = {key: 'c' * 64 for key in boundary.DIGEST_PINS}
        self.pins.update(environment='dev', branch='develop', project_ref=DEV_PROJECT,
                         repository=REPOSITORY, git_commit=SHA,
                         image=boundary.IMAGE_REPOSITORY + '@sha256:' + 'd' * 64,
                         image_id='sha256:' + 'e' * 64)
        self.packet = dict(schema_version=1, operation=boundary.OPERATION, git_commit=SHA,
                           request_id='f' * 64, approval_id='b' * 64)
        self.approval = dict(kind='moneybowl-restricted-api-approval-v1', operation=boundary.OPERATION,
                             request_id=self.packet['request_id'], approval_id=self.packet['approval_id'],
                             binding=copy.deepcopy(self.pins), issued_at=NOW - 1, expires_at=NOW + 100,
                             review_reference='synthetic independent review')
        self.value = dict(schema_version=1, kind='moneybowl-restricted-api-policy-v1', mode='offline-only',
                          binding=self.pins, approval_id=self.packet['approval_id'],
                          approval_sha256=sha256(boundary.encoded(self.approval)))

    def journal(self):
        return boundary.OfflineJournal(self.root, boundary.encoded(self.value))

    def check(self, **kwargs):
        defaults = dict(raw=boundary.encoded(self.packet), peer=PEER,
                        approval_raw=boundary.encoded(self.approval), before=self.pins, after=self.pins,
                        now=lambda: NOW, monotonic=lambda: 100)
        return self.journal().check(**{**defaults, **kwargs})

    def approve(self):
        # Explicit synthetic approval generation; the implementation has no issuer.
        self.value['approval_sha256'] = sha256(boundary.encoded(self.approval))


class AdmissionTests(Fixture):
    def test_exact_offline_path_never_authorizes_deployment(self):
        result = self.check()
        self.assertEqual(result['state'], 'CHECKED_OFFLINE')
        self.assertIs(result['deployment_authorized'], False)
        self.assertEqual(result['environment_release'], 'not_verified')
        records = list(self.root.glob('*.json'))
        self.assertEqual(len(records), 2)
        self.assertTrue(all(stat.S_IMODE(p.stat().st_mode) == 0o400 for p in records))

    def test_root_or_other_uid_gid_pid_is_unauthorized(self):
        for peer in ((1, 0, 0), (1, 1001, 983), (1, 993, 981), (1, 993, 0),
                     (0, 993, 983), (-1, 993, 983), (True, 993, 983), [123, 993, 983]):
            with self.subTest(peer=peer), self.assertRaisesRegex(Rejected, 'peer_unauthorized'):
                self.check(peer=peer)
        self.assertEqual(list(self.root.glob('*.json')), [])

    def test_other_revision_cannot_reuse_approval(self):
        self.packet['git_commit'] = 'b' * 40
        with self.assertRaisesRegex(Rejected, 'revision_changed'):
            self.check()

    def test_forged_approval_hash_fails_before_intent(self):
        self.approval['review_reference'] = 'forged'
        with self.assertRaisesRegex(Rejected, 'approval_changed'):
            self.check()
        self.assertEqual(list(self.root.glob('*.json')), [])

    def test_human_review_string_is_not_authority(self):
        self.approval['request_id'] = 'a' * 64
        self.approve()
        with self.assertRaisesRegex(Rejected, 'approval_invalid'):
            self.check()

    def test_wrong_approval_operation_fails_even_if_hash_pinned(self):
        self.approval['operation'] = 'prepare'
        self.approve()
        with self.assertRaisesRegex(Rejected, 'approval_invalid'):
            self.check()

    def test_approval_binding_cannot_disagree_with_policy(self):
        self.approval['binding']['image_id'] = 'sha256:' + 'a' * 64
        self.approve()
        with self.assertRaisesRegex(Rejected, 'approval_invalid'):
            self.check()

    def test_expired_future_overlong_boolean_and_nonfinite_approval_times(self):
        for changes in (dict(expires_at=NOW), dict(issued_at=NOW + 1),
                        dict(expires_at=NOW + 300), dict(issued_at=True),
                        dict(expires_at='later'), dict(issued_at=-1)):
            with self.subTest(changes=changes):
                old = copy.deepcopy(self.approval)
                self.approval.update(changes); self.approve()
                with self.assertRaisesRegex(Rejected, 'approval_expired'):
                    self.check()
                self.approval = old
        for raw in (b'{"issued_at":NaN}', b'{"expires_at":Infinity}'):
            with self.assertRaisesRegex(Rejected, 'json_invalid'):
                boundary.decoded(raw)

    def test_unknown_approval_fields_fail(self):
        self.approval['commissioned'] = True; self.approve()
        with self.assertRaisesRegex(Rejected, 'approval_invalid'):
            self.check()

    def test_unknown_packet_fields_cannot_carry_authority(self):
        for key, data in {
            'argv': ['/usr/bin/docker', 'run'], 'command': 'sh', 'uid': 993,
            'environment': {'DOCKER_HOST': 'tcp://attacker'}, 'project': 'other',
            'target': 'outbox-dispatcher', 'compose_file': '/tmp/evil.yaml',
            'build_context': '/tmp/build', 'dockerfile': '/tmp/Dockerfile',
            'image': 'evil:latest', 'mounts': ['/var/run/docker.sock:/engine'],
            'approval_path': '/etc/shadow', 'commissioned': True,
        }.items():
            with self.subTest(key=key), self.assertRaisesRegex(Rejected, 'request_invalid'):
                self.check(raw=boundary.encoded({**self.packet, key: data}))

    def test_subcommands_are_rejected(self):
        for op in ('build', 'push', 'pull', 'inspect', 'run', 'exec', 'up', 'down', 'prune',
                   'prepare', 'activate', 'verify', 'reconcile-dispatcher', 'reconcile-api-v1;sh'):
            with self.subTest(op=op), self.assertRaisesRegex(Rejected, 'request_invalid'):
                self.check(raw=boundary.encoded({**self.packet, 'operation': op}))

    def test_missing_fields_boolean_version_and_traversal_ids_rejected(self):
        for key in self.packet:
            with self.subTest(key=key), self.assertRaises(Rejected):
                boundary.request(boundary.encoded({k: v for k, v in self.packet.items() if k != key}), PEER)
        for changes in (dict(schema_version=True), dict(request_id='../evil'), dict(approval_id='/tmp/x'),
                        dict(git_commit='0' * 40), dict(approval_id='0' * 64)):
            with self.subTest(changes=changes), self.assertRaises(Rejected):
                boundary.request(boundary.encoded({**self.packet, **changes}), PEER)

    def test_invalid_oversized_duplicate_and_nested_json_fails(self):
        for raw in (b'', b'x' * 1025, b'[]', b'null', b'{} {}', b'\xff',
                    b'{"schema_version":1,"schema_version":1}',
                    b'{"x":' + b'[' * 1500 + b'0' + b']' * 1500 + b'}'):
            with self.subTest(length=len(raw)), self.assertRaises(Rejected):
                boundary.request(raw, PEER)
        with self.assertRaisesRegex(Rejected, 'duplicate_key'):
            boundary.decoded(b'{"binding":{"x":1,"x":2}}')

    def test_commissioned_flag_or_live_mode_cannot_enable_policy(self):
        for changes in (dict(commissioned=True), dict(mode='live'), dict(mode='commissioned'),
                        dict(schema_version=True)):
            with self.subTest(changes=changes), self.assertRaisesRegex(Rejected, 'policy_invalid'):
                boundary.policy(boundary.encoded({**self.value, **changes}))

    def test_mutable_image_tags_other_repositories_and_missing_proof_fail(self):
        for changes in (dict(image=boundary.IMAGE_REPOSITORY + ':latest'),
                        dict(image='ghcr.io/other/api@sha256:' + 'd' * 64),
                        dict(image_id='latest'), dict(build_isolation_sha256='0' * 64),
                        dict(initial_acceptance_sha256=None)):
            with self.subTest(changes=changes), self.assertRaisesRegex(Rejected, 'pin_invalid'):
                boundary.policy(boundary.encoded({**self.value, 'binding': {**self.pins, **changes}}))

    def test_policy_cannot_change_environment_branch_project_repository(self):
        for changes in (dict(environment='qa'), dict(environment='production'), dict(branch='main'),
                        dict(project_ref='a' * 20), dict(repository='other/repo')):
            with self.subTest(changes=changes), self.assertRaisesRegex(Rejected, 'target_invalid'):
                boundary.policy(boundary.encoded({**self.value, 'binding': {**self.pins, **changes}}))

    def test_policy_snapshot_uses_copy_of_bytes(self):
        journal = self.journal()
        self.value['binding']['image_id'] = 'sha256:' + 'a' * 64
        with self.assertRaisesRegex(Rejected, 'measurement_changed'):
            journal.check(boundary.encoded(self.packet), PEER, boundary.encoded(self.approval),
                          self.pins, self.pins, now=lambda: NOW, monotonic=lambda: 1)


def drift_case(key):
    def test(self):
        changed = {**self.pins, key: 'changed'}
        with self.assertRaisesRegex(Rejected, 'measurement_changed'):
            self.check(before=changed)
        self.assertEqual(list(self.root.glob('*.json')), [])
        with self.assertRaisesRegex(Rejected, 'measurement_changed'):
            self.check(after=changed)
        self.assertEqual(len(list(self.root.glob('*.intent.json'))), 1)
        self.assertEqual(list(self.root.glob('*.checked.json')), [])
        with self.assertRaisesRegex(Rejected, 'incomplete_transaction'):
            self.check()
    return test


class DriftTests(Fixture):
    pass


for key in sorted(boundary.BINDING_KEYS):
    setattr(DriftTests, 'test_before_and_after_drift_' + key, drift_case(key))


class JournalTests(Fixture):
    def test_same_request_and_new_request_id_cannot_replay_consumed_approval(self):
        self.check()
        for request_id in (self.packet['request_id'], 'a' * 64):
            self.packet['request_id'] = request_id
            with self.assertRaisesRegex(Rejected, 'replay_rejected'):
                self.check()

    def test_new_sealed_candidate_after_complete_offline_check(self):
        self.check()
        self.packet.update(git_commit='b' * 40, request_id='a' * 64, approval_id='a' * 64)
        self.pins['git_commit'] = self.packet['git_commit']
        self.approval.update(request_id=self.packet['request_id'], approval_id=self.packet['approval_id'],
                             binding=copy.deepcopy(self.pins))
        self.value['approval_id'] = self.packet['approval_id']; self.approve()
        self.assertEqual(self.check()['state'], 'CHECKED_OFFLINE')
        self.assertEqual(len(list(self.root.glob('*.json'))), 4)

    def test_new_approval_cannot_reuse_request_nonce(self):
        self.check()
        self.packet['approval_id'] = self.value['approval_id'] = 'a' * 64
        self.approval['approval_id'] = 'a' * 64; self.approve()
        with self.assertRaisesRegex(Rejected, 'replay_rejected'):
            self.check()

    def test_concurrent_request_fails_without_waiting_or_consuming(self):
        with deployment_lock(self.root):
            with self.assertRaisesRegex(Rejected, 'deployment_busy'):
                self.check()
        self.assertEqual(list(self.root.glob('*.json')), [])
        self.assertEqual(self.check()['state'], 'CHECKED_OFFLINE')

    def test_duration_budget_failure_retains_intent_and_blocks_new_nonce(self):
        with self.assertRaisesRegex(Rejected, 'duration_exceeded'):
            self.check(monotonic=Mock(side_effect=[10, 15]))
        self.packet['approval_id'] = self.value['approval_id'] = 'a' * 64
        self.approval['approval_id'] = 'a' * 64; self.approve()
        with self.assertRaisesRegex(Rejected, 'incomplete_transaction'):
            self.check()

    def test_backward_or_invalid_monotonic_clock_fails_closed(self):
        with self.assertRaisesRegex(Rejected, 'clock_invalid'):
            self.check(monotonic=lambda: float('nan'))
        with self.assertRaisesRegex(Rejected, 'duration_exceeded'):
            self.check(monotonic=Mock(side_effect=[10, 9]))

    def test_approval_expiring_during_check_leaves_intent(self):
        with self.assertRaisesRegex(Rejected, 'approval_expired'):
            self.check(now=Mock(side_effect=[NOW, NOW + 100]))
        self.assertEqual(list(self.root.glob('*.checked.json')), [])
        with self.assertRaisesRegex(Rejected, 'incomplete_transaction'):
            self.check()

    def test_crash_before_terminal_quarantines_transaction(self):
        original = boundary.publish
        def terminate(path, value, **kwargs):
            if str(path).endswith('.checked.json'):
                raise SystemExit('synthetic crash')
            original(path, value, **kwargs)
        with patch.object(boundary, 'publish', side_effect=terminate), self.assertRaises(SystemExit):
            self.check()
        with self.assertRaisesRegex(Rejected, 'incomplete_transaction'):
            self.check()

    def test_crash_after_intent_fsync_retains_one_use_boundary(self):
        original = boundary.publish
        def terminate(path, value, **kwargs):
            original(path, value, **kwargs)
            raise KeyboardInterrupt
        with patch.object(boundary, 'publish', side_effect=terminate), self.assertRaises(KeyboardInterrupt):
            self.check()
        with self.assertRaisesRegex(Rejected, 'incomplete_transaction'):
            self.check()

    def test_partial_intent_unknown_file_or_terminal_without_intent_blocks(self):
        path = self.root / ('a' * 64 + '.intent.json')
        path.write_bytes(b'{'); path.chmod(0o400)
        with self.assertRaisesRegex(Rejected, 'incomplete_transaction'):
            self.check()
        path.rename(self.root / ('a' * 64 + '.checked.json'))
        with self.assertRaisesRegex(Rejected, 'incomplete_transaction'):
            self.check()

    def test_changed_terminal_or_deleted_intent_never_reopens_authority(self):
        self.check()
        terminal = next(self.root.glob('*.checked.json'))
        terminal.chmod(0o600); terminal.write_bytes(boundary.encoded(dict(state='deployed')))
        terminal.chmod(0o400)
        with self.assertRaisesRegex(Rejected, 'incomplete_transaction'):
            self.check()

    def test_journal_symlink_and_hardlink_rejected(self):
        self.check()
        intent = next(self.root.glob('*.intent.json'))
        original = self.root / 'outside'; intent.rename(original)
        intent.symlink_to(original)
        with self.assertRaises(Rejected):
            self.check()
        intent.unlink(); os.link(original, intent); original.rename(self.root.parent / (self.root.name + '-link'))
        self.addCleanup((self.root.parent / (self.root.name + '-link')).unlink)
        with self.assertRaises(Rejected):
            self.check()

    def test_journal_root_link_or_group_writable_path_is_rejected(self):
        alias = self.root / 'link'; alias.symlink_to(self.root, target_is_directory=True)
        with self.assertRaisesRegex(Rejected, 'protected_path_invalid'):
            boundary.OfflineJournal(alias, boundary.encoded(self.value))
        self.root.chmod(0o770)
        with self.assertRaisesRegex(Rejected, 'protected_permissions_invalid'):
            self.journal()


class SocketTests(Fixture):
    def connection(self, peer=PEER):
        connection = Mock(family=socket.AF_UNIX)
        connection.getsockopt.side_effect = [socket.SOCK_SEQPACKET, struct.pack('3i', *peer)]
        connection.recvmsg.return_value = (boundary.encoded(self.packet), [], 0, None)
        return connection

    def test_kernel_peer_credentials_used_for_one_packet(self):
        connection = self.connection()
        self.assertEqual(boundary.receive_request(connection), self.packet)
        self.assertEqual(connection.getsockopt.call_args.args,
                         (socket.SOL_SOCKET, socket.SO_PEERCRED, struct.calcsize('3i')))
        connection.settimeout.assert_called_once_with(2)

    def test_unauthorized_peer_rejected_before_receive(self):
        connection = self.connection((123, 0, 0))
        with self.assertRaisesRegex(Rejected, 'peer_unauthorized'):
            boundary.receive_request(connection)
        connection.recvmsg.assert_not_called()

    def test_nonunix_stream_or_bad_credential_socket_rejected(self):
        connection = self.connection(); connection.family = socket.AF_INET
        with self.assertRaisesRegex(Rejected, 'socket_invalid'):
            boundary.receive_request(connection)
        connection = self.connection(); connection.getsockopt.side_effect = [socket.SOCK_STREAM]
        with self.assertRaisesRegex(Rejected, 'socket_invalid'):
            boundary.receive_request(connection)
        connection = self.connection(); connection.getsockopt.side_effect = [socket.SOCK_SEQPACKET, b'bad']
        with self.assertRaisesRegex(Rejected, 'peer_invalid'):
            boundary.receive_request(connection)

    def test_ancillary_descriptors_are_closed_and_rejected(self):
        connection = self.connection()
        connection.recvmsg.return_value = (boundary.encoded(self.packet),
            [(socket.SOL_SOCKET, socket.SCM_RIGHTS, struct.pack('i', 999))], 0, None)
        with patch.object(os, 'close') as close, self.assertRaisesRegex(Rejected, 'ancillary_forbidden'):
            boundary.receive_request(connection)
        close.assert_called_once_with(999)

    def test_truncated_and_other_control_packets_fail(self):
        for flags, controls in ((socket.MSG_TRUNC, []), (socket.MSG_CTRUNC, []),
                                (0, [(socket.SOL_SOCKET, socket.SCM_CREDENTIALS, b'fixture')])):
            connection = self.connection()
            connection.recvmsg.return_value = (boundary.encoded(self.packet), controls, flags, None)
            with self.subTest(flags=flags), self.assertRaisesRegex(Rejected, 'ancillary_forbidden'):
                boundary.receive_request(connection)

    def test_timeout_and_oversized_packet_fail_closed(self):
        connection = self.connection(); connection.recvmsg.side_effect = TimeoutError
        with self.assertRaisesRegex(Rejected, 'receive_failed'):
            boundary.receive_request(connection)
        connection = self.connection(); connection.recvmsg.return_value = (b'x' * 1025, [], 0, None)
        with self.assertRaisesRegex(Rejected, 'size_invalid'):
            boundary.receive_request(connection)


class AuthorityTests(Fixture):
    def test_unprivileged_caller_cannot_read_root_authority(self):
        with patch('os.getuid', return_value=993), patch('os.geteuid', return_value=993), \
                patch.object(boundary, 'root_controlled') as read:
            with self.assertRaisesRegex(Rejected, 'root_authority_required'):
                boundary.root_document(boundary.POLICY_PATH)
        read.assert_not_called()

    def test_root_cannot_select_arbitrary_authority_path(self):
        with patch('os.getuid', return_value=0), patch('os.geteuid', return_value=0), \
                patch.object(boundary, 'root_controlled') as read:
            with self.assertRaisesRegex(Rejected, 'authority_path_invalid'):
                boundary.root_document(Path('/tmp/forged.json'))
        read.assert_not_called()

    def test_authority_reads_only_fixed_policy_and_pinned_approval_paths(self):
        with patch.object(boundary, 'root_document', side_effect=[boundary.encoded(self.value),
                boundary.encoded(self.approval)]) as read:
            value, raw = boundary.read_authority(self.packet['approval_id'])
        self.assertEqual(value, self.value)
        self.assertEqual(sha256(raw), self.value['approval_sha256'])
        self.assertEqual([c.args[0] for c in read.call_args_list], [boundary.POLICY_PATH,
                         boundary.APPROVAL_ROOT / (self.packet['approval_id'] + '.json')])

    def test_changed_approval_bytes_or_id_rejected(self):
        with patch.object(boundary, 'root_document', return_value=boundary.encoded(self.value)) as read:
            with self.assertRaisesRegex(Rejected, 'approval_invalid'):
                boundary.read_authority('a' * 64)
        self.assertEqual(read.call_count, 1)
        with patch.object(boundary, 'root_document', side_effect=[boundary.encoded(self.value), b'{}']):
            with self.assertRaisesRegex(Rejected, 'approval_changed'):
                boundary.read_authority(self.packet['approval_id'])

    def test_live_entrypoint_cannot_be_enabled_by_config_approval_or_transport(self):
        with self.assertRaisesRegex(Rejected, 'boundary_uncommissioned'):
            boundary.live_reconcile(commissioned=True, command=Mock(), policy=self.value,
                                    approval=self.approval)
        with patch('sys.stdout', new_callable=io.StringIO) as output:
            self.assertEqual(boundary.main(), 1)
        self.assertEqual(json.loads(output.getvalue())['environment_release'], 'not_verified')

    def test_default_owner_live_build_rejects_before_capacity_or_engine(self):
        owner = object.__new__(DockerOwner)
        owner._offline_transport = False
        owner.capacity = Mock(); owner.command = Mock()
        with self.assertRaisesRegex(Rejected, 'untrusted_build_isolation_uncommissioned'):
            owner.build(Path('/untrusted/context'), SHA, 'a' * 64)
        owner.capacity.assert_not_called(); owner.command.assert_not_called()

    def test_live_command_injection_is_not_an_offline_transport(self):
        with patch('ingestion_owner.inventory.layout'), patch('ingestion_owner.Registry') as registry:
            with self.assertRaisesRegex(Rejected, 'live_command_injection_forbidden'):
                DockerOwner({}, command=Command())
        registry.assert_not_called()


class RootFileTests(FileFixture):
    def setUp(self):
        super().setUp()
        self.path = self.root / 'policy.json'
        self.path.write_bytes(b'{"synthetic":true}\n'); self.path.chmod(0o400)
        self.pin = patch.object(boundary, 'POLICY_PATH', self.path)
        self.pin.start(); self.addCleanup(self.pin.stop)

    def test_root_controlled_document_read_checks_descriptor_and_path(self):
        with self.authority():
            self.assertEqual(boundary.root_document(self.path), b'{"synthetic":true}\n')

    def test_executor_owned_authority_is_rejected(self):
        self.owners[self.path] = 993
        with self.authority(), self.assertRaisesRegex(Rejected, 'approval_authority_invalid'):
            boundary.root_document(self.path)

    def test_executor_owned_ancestor_is_rejected(self):
        self.untrusted.add(self.root)
        with self.authority(), self.assertRaisesRegex(Rejected, 'approval_authority_invalid'):
            boundary.root_document(self.path)

    def test_writable_authority_or_wrong_group_is_rejected(self):
        self.path.chmod(0o600)
        with self.authority(), self.assertRaisesRegex(Rejected, 'authority_invalid'):
            boundary.root_document(self.path)
        self.path.chmod(0o400); self.groups[self.path] = 983
        with self.authority(), self.assertRaisesRegex(Rejected, 'authority_invalid'):
            boundary.root_document(self.path)

    def test_acl_on_authority_or_ancestor_is_rejected(self):
        for target in (self.path, self.root):
            with self.subTest(target=target), self.authority(), \
                    patch('os.listxattr', side_effect=lambda p, **kw: ['system.posix_acl_access']
                          if Path(p) == target else []), self.assertRaisesRegex(Rejected, 'acl_unapproved'):
                boundary.root_document(self.path)

    def test_symlink_authority_is_rejected(self):
        target = self.root / 'target'; self.path.rename(target); self.path.symlink_to(target)
        with self.authority(), self.assertRaises(Rejected):
            boundary.root_document(self.path)

    def test_hardlink_authority_is_rejected(self):
        os.link(self.path, self.root / 'other')
        with self.authority(), self.assertRaises(Rejected):
            boundary.root_document(self.path)

    def test_replaced_inode_during_read_is_rejected(self):
        original = os.read
        def replace(fd, size):
            raw = original(fd, size)
            if raw:
                other = self.root / 'replacement'
                other.write_bytes(raw); other.chmod(0o400); os.replace(other, self.path)
            return raw
        with self.authority(), patch('os.read', side_effect=replace), self.assertRaisesRegex(
                Rejected, 'private_input_(changed_during_read|identity_changed)'):
            boundary.root_document(self.path)

    def test_authority_oversize_is_rejected(self):
        self.path.chmod(0o600); self.path.write_bytes(b'x' * (boundary.MAX_DOCUMENT + 1))
        self.path.chmod(0o400)
        with self.authority(), self.assertRaisesRegex(Rejected, 'size_invalid'):
            boundary.root_document(self.path)


if __name__ == '__main__':
    unittest.main()
