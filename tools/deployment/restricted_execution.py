"""Restricted API boundary V1: admission primitives and OFFLINE transaction model.

SOURCE CANDIDATE; NOT COMMISSIONED. No listener, Docker transport, build, subprocess,
network client or deployment receipt producer exists here. Synthetic dictionaries
are expectations, never runtime/registry/build/initial-acceptance attestations.
"""
import array
import json
import math
import os
import re
import socket
import stat
import struct
import time
from pathlib import Path

from contract import DEV_PROJECT, REPOSITORY, Rejected, require, revision
from initial_private_inputs import checked_file, no_acl, trusted_path
from owner_common import sha256
from protected_io import deployment_lock, protected, publish, root_controlled

UID, GID = 993, 983
MAX_PACKET = 1024
MAX_DOCUMENT = 65536
MAX_APPROVAL_SECONDS = 300
MAX_CHECK_SECONDS = 5
OPERATION = 'reconcile-api-v1'
HEX = re.compile(r'[0-9a-f]{64}')
IMAGE_REPOSITORY = 'ghcr.io/sharanravi954mf/moneybowl-ingestion-dev'
POLICY_PATH = Path('/etc/moneybowl-deployment/restricted-api-v1.json')
APPROVAL_ROOT = Path('/etc/moneybowl-deployment/restricted-api-approvals-v1')
DIGEST_PINS = {
    'source_digest', 'controller_sha256', 'owner_config_sha256',
    'initial_acceptance_sha256', 'build_isolation_sha256', 'registry_proof_sha256',
    'baseline_sha256', 'runtime_sha256', 'compose_hash', 'invariant_sha256',
    'file_seals_sha256',
}
BINDING_KEYS = DIGEST_PINS | {
    'environment', 'branch', 'project_ref', 'repository', 'git_commit', 'image', 'image_id',
}


def encoded(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), allow_nan=False).encode() + b'\n'


def decoded(raw, limit=MAX_DOCUMENT):
    require(type(raw) is bytes and 0 < len(raw) <= limit, 'boundary_document_size_invalid')
    def unique(pairs):
        result = {}
        for key, value in pairs:
            require(key not in result, 'boundary_duplicate_key')
            result[key] = value
        return result
    def invalid(_):
        raise Rejected('boundary_json_invalid')
    try:
        result = json.loads(raw, object_pairs_hook=unique, parse_constant=invalid)
        require(type(result) is dict, 'boundary_object_required')
        return result
    except (ValueError, UnicodeError, RecursionError):
        raise Rejected('boundary_json_invalid') from None


def hex_pin(value):
    return type(value) is str and HEX.fullmatch(value) is not None and value != '0' * 64


def peer_identity(connection):
    """Linux kernel credentials on a connected Unix SEQPACKET socket, never JSON UID.

    No socket is opened here. Namespace/service/socket installation is a separate
    review prerequisite; SO_PEERCRED alone does not attest an executable or unit.
    """
    require(connection.family == socket.AF_UNIX and
            connection.getsockopt(socket.SOL_SOCKET, socket.SO_TYPE) == socket.SOCK_SEQPACKET,
            'boundary_socket_invalid')
    try:
        raw = connection.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, struct.calcsize('3i'))
        require(len(raw) == struct.calcsize('3i'), 'boundary_peer_invalid')
        peer = struct.unpack('3i', raw)
    except (OSError, struct.error):
        raise Rejected('boundary_peer_invalid') from None
    check_peer(peer)
    return peer


def check_peer(peer):
    require(type(peer) is tuple and len(peer) == 3 and all(type(v) is int for v in peer)
            and peer[0] > 0 and peer[1:] == (UID, GID), 'boundary_peer_unauthorized')


def request(raw, peer):
    check_peer(peer)
    value = decoded(raw, MAX_PACKET)
    require(set(value) == {'schema_version', 'operation', 'git_commit', 'request_id', 'approval_id'}
            and type(value['schema_version']) is int and value['schema_version'] == 1
            and value['operation'] == OPERATION
            and hex_pin(value['request_id']) and hex_pin(value['approval_id']),
            'boundary_request_invalid')
    revision(value['git_commit'])
    return value


def receive_request(connection):
    """One bounded packet; reject descriptor/control-message transfer and truncation."""
    peer = peer_identity(connection)  # Unauthorized peers are rejected before recv.
    connection.settimeout(2)
    try:
        raw, ancillary, flags, _ = connection.recvmsg(MAX_PACKET + 1, socket.CMSG_SPACE(256))
    except OSError:
        raise Rejected('boundary_receive_failed') from None
    # Close any received rights even on rejection, including a truncated rights list.
    for level, kind, data in ancillary:
        if level == socket.SOL_SOCKET and kind == socket.SCM_RIGHTS:
            fds = array.array('i')
            fds.frombytes(data[:len(data) - len(data) % fds.itemsize])
            for fd in fds:
                os.close(fd)
    require(not ancillary and not flags & (socket.MSG_TRUNC | socket.MSG_CTRUNC),
            'boundary_ancillary_forbidden')
    return request(raw, peer)


def policy(raw):
    value = decoded(raw)
    require(set(value) == {'schema_version', 'kind', 'mode', 'binding', 'approval_id', 'approval_sha256'}
            and type(value['schema_version']) is int and value['schema_version'] == 1
            and value['kind'] == 'moneybowl-restricted-api-policy-v1'
            and value['mode'] == 'offline-only', 'boundary_policy_invalid')
    pins = value['binding']
    require(type(pins) is dict and set(pins) == BINDING_KEYS, 'boundary_binding_invalid')
    require(pins['environment'] == 'dev' and pins['branch'] == 'develop'
            and pins['project_ref'] == DEV_PROJECT and pins['repository'] == REPOSITORY,
            'boundary_target_invalid')
    revision(pins['git_commit'])
    require(all(hex_pin(pins[key]) for key in DIGEST_PINS)
            and type(pins['image']) is str
            and pins['image'].startswith(IMAGE_REPOSITORY + '@sha256:')
            and hex_pin(pins['image'].removeprefix(IMAGE_REPOSITORY + '@sha256:'))
            and type(pins['image_id']) is str and pins['image_id'].startswith('sha256:')
            and hex_pin(pins['image_id'].removeprefix('sha256:'))
            and hex_pin(value['approval_id']) and hex_pin(value['approval_sha256']),
            'boundary_pin_invalid')
    return value


def root_document(path):
    """Internal fixed-path root authority reader. Does not read runtime secrets."""
    require(os.getuid() == os.geteuid() == 0, 'boundary_root_authority_required')
    require(path == POLICY_PATH or (path.parent == APPROVAL_ROOT and
            path.suffix == '.json' and hex_pin(path.stem)), 'boundary_authority_path_invalid')
    root_controlled(path)
    location, info = trusted_path(path)
    require(info.st_gid == 0 and stat.S_IMODE(info.st_mode) == 0o400, 'boundary_authority_invalid')
    with checked_file(location, info) as fd:
        raw = b''
        while len(raw) <= MAX_DOCUMENT:
            block = os.read(fd, min(4096, MAX_DOCUMENT + 1 - len(raw)))
            if not block:
                break
            raw += block
    decoded(raw)
    return raw


def read_authority(approval_id):
    """Future root launcher seam; no caller-selected paths or live admission."""
    require(hex_pin(approval_id), 'boundary_approval_invalid')
    value = policy(root_document(POLICY_PATH))
    require(approval_id == value['approval_id'], 'boundary_approval_invalid')
    raw = root_document(APPROVAL_ROOT / (approval_id + '.json'))
    require(sha256(raw) == value['approval_sha256'], 'boundary_approval_changed')
    return value, raw


def admission(value, packet, approval_raw, measured, now):
    """Pure comparison. Supplied synthetic measurements do not establish authority."""
    require(type(now) in (int, float) and math.isfinite(now), 'boundary_clock_invalid')
    require(packet['git_commit'] == value['binding']['git_commit'], 'boundary_revision_changed')
    require(packet['approval_id'] == value['approval_id'] and
            sha256(approval_raw) == value['approval_sha256'], 'boundary_approval_changed')
    approval = decoded(approval_raw)
    require(set(approval) == {'kind', 'operation', 'request_id', 'approval_id', 'binding',
                             'issued_at', 'expires_at', 'review_reference'}
            and approval['kind'] == 'moneybowl-restricted-api-approval-v1'
            and approval['operation'] == OPERATION
            and approval['request_id'] == packet['request_id']
            and approval['approval_id'] == packet['approval_id']
            and approval['binding'] == value['binding']
            and type(approval['review_reference']) is str
            and 0 < len(approval['review_reference']) <= 200,
            'boundary_approval_invalid')
    issued, expiry = approval['issued_at'], approval['expires_at']
    require(all(type(v) in (int, float) and math.isfinite(v) for v in (issued, expiry))
            and 0 <= issued <= now < expiry <= issued + MAX_APPROVAL_SECONDS,
            'boundary_approval_expired')
    require(type(measured) is dict and measured == value['binding'], 'boundary_measurement_changed')


class OfflineJournal:
    """Disposable offline model, with no execution transport or public receipt path.

    Do not connect this to a live owner: it accepts synthetic peer/snapshot values.
    Append-only files model consumption, serialization and crash quarantine only.
    A real broker must own its journal as root and use the existing initial lock.
    """
    def __init__(self, root, policy_raw):
        self.root = protected(root, directory=True)
        no_acl(self.root)
        self.policy_raw = bytes(policy_raw)
        policy(self.policy_raw)

    def history(self, packet):
        names = {p.name for p in self.root.iterdir()} - {'.owner.lock'}
        intents = {name[:-12] for name in names if name.endswith('.intent.json')}
        require(names == {nonce + suffix for nonce in intents
                         for suffix in ('.intent.json', '.checked.json')}, 'boundary_incomplete_transaction')
        for nonce in sorted(intents):
            require(hex_pin(nonce), 'boundary_journal_invalid')
            def read(suffix):
                path = protected(self.root / (nonce + suffix))
                no_acl(path)
                return decoded(path.read_bytes())
            intent, terminal = read('.intent.json'), read('.checked.json')
            require(set(intent) == {'state', 'request', 'policy_sha256', 'approval_sha256'}
                    and intent['state'] == 'INTENT_OFFLINE'
                    and hex_pin(intent['policy_sha256']) and hex_pin(intent['approval_sha256'])
                    and request(encoded(intent['request']), (1, UID, GID))['approval_id'] == nonce
                    and terminal == dict(state='CHECKED_OFFLINE', intent_sha256=sha256(encoded(intent)),
                                         deployment_authorized=False, environment_release='not_verified'),
                    'boundary_incomplete_transaction')
            require(nonce != packet['approval_id'] and
                    intent['request']['request_id'] != packet['request_id'], 'boundary_replay_rejected')

    def check(self, raw, peer, approval_raw, before, after, *, now=time.time, monotonic=time.monotonic):
        value = policy(self.policy_raw)
        packet = request(raw, peer)
        with deployment_lock(self.root):
            start = monotonic()
            require(type(start) in (int, float) and math.isfinite(start), 'boundary_clock_invalid')
            self.history(packet)
            admission(value, packet, approval_raw, before, now())
            intent = dict(state='INTENT_OFFLINE', request=packet,
                          policy_sha256=sha256(self.policy_raw), approval_sha256=sha256(approval_raw))
            # Intent survives abrupt termination or failed terminal publication. No
            # next nonce, retry, cleanup, repair or automatic rollback is permitted.
            base = self.root / packet['approval_id']
            publish(str(base) + '.intent.json', intent, immutable=True)
            admission(value, packet, approval_raw, after, now())
            end = monotonic()
            require(type(end) in (int, float) and math.isfinite(end) and
                    0 <= end - start < MAX_CHECK_SECONDS, 'boundary_duration_exceeded')
            result = dict(state='CHECKED_OFFLINE', intent_sha256=sha256(encoded(intent)),
                          deployment_authorized=False, environment_release='not_verified')
            publish(str(base) + '.checked.json', result, immutable=True)
            return result


def live_reconcile(*_args, **_kwargs):
    # No config/approval/digest/flag/test transport can commission a live adapter.
    raise Rejected('restricted_execution_boundary_uncommissioned')


def main():
    print(json.dumps(dict(state='BLOCKED', reason='restricted_execution_boundary_uncommissioned',
                          deployment_authorized=False, environment_release='not_verified')))
    return 1


if __name__ == '__main__':
    raise SystemExit(main())
