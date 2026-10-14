"""Disabled-by-default root broker and UID 993 semantic client.

One child/process group per connection; fixed socket, kernel peer credentials,
root authority, shared lock, durable consumption and no recovery/retry operation.
"""
import argparse
import array
import json
import math
import os
import re
import select
import signal
import socket
import stat
import struct
import time
from pathlib import Path

from contract import Rejected, require, revision, DEV_PROJECT
from owner_common import sha256, envelope
from protected_io import deployment_lock, publish, protected, read_private, root_controlled
from restricted_execution import encoded, decoded, hex_pin, peer_identity
from api_executor import SOCKET_PATH, POLICY_PATH, load_authority, Process, SealedSource, ApiEngine
from delivery_verifier import GithubVerifier

OPERATION = 'reconcile-api-v2'
MAX_PACKET = 1024
MAX_SECONDS = 240


def packet(raw, peer):
    from restricted_execution import check_peer
    check_peer(peer)
    value = decoded(raw, MAX_PACKET)
    require(set(value) == {'schema_version', 'operation', 'git_commit', 'request_id'}
            and type(value['schema_version']) is int and value['schema_version'] == 2
            and value['operation'] == OPERATION and hex_pin(value['request_id']), 'executor_request_invalid')
    revision(value['git_commit'])
    return value


def receive(connection, policy):
    peer = peer_identity(connection)
    pid = peer[0]
    # SO_PEERCRED identifies host credentials. Namespace/cgroup checks bind the
    # independently installed unit; UID alone is insufficient installation proof.
    for name in ('user', 'pid'):
        require(os.readlink(f'/proc/{pid}/ns/{name}') == os.readlink(f'/proc/1/ns/{name}'), 'executor_peer_namespace')
    require(Path(f'/proc/{pid}/cgroup').read_text() == '0::' + policy['owner_cgroup'] + '\n', 'executor_peer_service')
    status = Path(f'/proc/{pid}/status').read_text()
    require(re.search(r'^Uid:\s+993\s+993\s+993\s+993$', status, re.M)
            and re.search(r'^Gid:\s+983\s+983\s+983\s+983$', status, re.M)
            and re.search(r'^CapEff:\s+0000000000000000$', status, re.M), 'executor_peer_process')
    connection.settimeout(2)
    try:
        raw, ancillary, flags, _ = connection.recvmsg(MAX_PACKET + 1, socket.CMSG_SPACE(256))
    except OSError:
        raise Rejected('executor_receive_failed') from None
    for level, kind, data in ancillary:
        if level == socket.SOL_SOCKET and kind == socket.SCM_RIGHTS:
            fds = array.array('i')
            fds.frombytes(data[:len(data) - len(data) % fds.itemsize])
            for fd in fds:
                os.close(fd)
    require(not ancillary and not flags & (socket.MSG_TRUNC | socket.MSG_CTRUNC), 'executor_ancillary_forbidden')
    return packet(raw, peer)


class Broker:
    def __init__(self, policy, policy_raw, verifier, source, engine, authority, clock=time.time):
        self.policy, self.policy_raw = policy, policy_raw
        self.verifier, self.source, self.engine, self.authority = verifier, source, engine, authority
        self.clock = clock
        self.root = Path(policy['journal_root'])

    def records(self):
        records, proof_ids, request_ids, shas = [], set(), set(), set()
        renewals = []
        for path in sorted(self.root.iterdir()):
            if re.fullmatch(r'[0-9a-f]{64}\.renewal\.[0-9a-f]{64}\.(intent|complete)\.json', path.name):
                renewals.append(path)
                continue
            require(re.fullmatch(r'[0-9a-f]{64}\.intent\.json', path.name)
                    or re.fullmatch(r'[0-9a-f]{64}\.(complete|observation)\.json', path.name),
                    'executor_journal_quarantined')
            if not path.name.endswith('.intent.json'):
                require((self.root / (path.name.split('.')[0] + '.intent.json')).exists(), 'executor_journal_quarantined')
                continue
            intent = read_private(path)
            key = path.name.split('.')[0]
            require(key == intent.get('proof', {}).get('proof_id') and key not in proof_ids
                    and intent.get('request', {}).get('request_id') not in request_ids
                    and intent['request']['git_commit'] not in shas, 'executor_journal_quarantined')
            proof_ids.add(key); request_ids.add(intent['request']['request_id']); shas.add(intent['request']['git_commit'])
            complete = self.root / (key + '.complete.json')
            observation = self.root / (key + '.observation.json')
            require(complete.exists() and observation.exists(), 'executor_journal_quarantined')
            done, observed = read_private(complete), read_private(observation)
            receipt_path = Path(self.policy['receipt_root']) / (intent['request']['git_commit'] + '.json')
            require(done == dict(state='VERIFIED', intent_sha256=sha256(encoded(intent)),
                                 observation_sha256=sha256(encoded(observed)), receipt_sha256=sha256(encoded(observed['receipt']))), 'executor_journal_quarantined')
            records.append((intent, observed))
        require(sorted(i.get('sequence', 0) for i, _ in records) == list(range(1, len(records)+1)), 'executor_journal_quarantined')
        latest = {i['proof']['proof_id']: o['receipt'] for i, o in records}
        for path in renewals:
            base = path.name.removesuffix('.intent.json').removesuffix('.complete.json')
            intent_path = self.root/(base+'.intent.json')
            complete_path = self.root/(base+'.complete.json')
            require(intent_path.exists() and complete_path.exists(), 'executor_journal_quarantined')
            renewal = read_private(intent_path)
            key = base.split('.')[0]
            require(key in latest and read_private(complete_path) == {'renewal_sha256': sha256(encoded(renewal))},
                    'executor_journal_quarantined')
            receipt = renewal['receipt']
            old = latest[key]
            stamp = receipt.get('observed_at')
            require(type(stamp) in (int, float) and math.isfinite(stamp) and stamp >= 0
                    and {k: v for k, v in old.items() if k != 'observed_at'} ==
                        {k: v for k, v in receipt.items() if k != 'observed_at'}, 'executor_journal_quarantined')
            if stamp > old['observed_at']:
                latest[key] = receipt
        for intent, _ in records:
            key = intent['proof']['proof_id']
            path = Path(self.policy['receipt_root'])/(intent['request']['git_commit']+'.json')
            require(read_private(path) == latest[key], 'executor_journal_quarantined')
        return records

    def check_authority(self):
        p, raw = self.authority()
        require(raw == self.policy_raw and p == self.policy, 'executor_authority_changed')
        return self.source.initial()

    def reconcile(self, request):
        with deployment_lock(self.policy['state_root']):
            records = self.records()  # Uncertainty takes precedence over supersession.
            initial_api = self.check_authority()
            for intent, observed in records:
                old = intent['request']
                if old['request_id'] == request['request_id']:
                    require(old == request, 'executor_request_replayed')
                if old['git_commit'] == request['git_commit']:
                    fresh = self.verifier.verify(request['git_commit'], accepted=intent['proof'])
                    require(fresh['proof_id'] == intent['proof']['proof_id'], 'executor_completed_proof_changed')
                    require(self.engine.observation() == observed['after'], 'executor_completed_runtime_changed')
                    self.verifier.recheck(fresh)
                    self.check_authority()
                    now = self.clock()
                    receipt_path = Path(self.policy['receipt_root'])/(request['git_commit']+'.json')
                    current = read_private(receipt_path)
                    if now > current['observed_at']:
                        receipt = {**observed['receipt'], 'observed_at': now}
                        renewal = dict(receipt=receipt, proof_id=fresh['proof_id'])
                        key = fresh['proof_id']+'.renewal.'+sha256(encoded(renewal))
                        publish(self.root/(key+'.intent.json'), renewal, immutable=True)
                        try:
                            publish(receipt_path, receipt)
                            publish(self.root/(key+'.complete.json'), {'renewal_sha256': sha256(encoded(renewal))}, immutable=True)
                        except BaseException:
                            raise Rejected('executor_transaction_quarantined') from None
                    return dict(state='already_deployed', git_commit=request['git_commit'])
            try:
                proof = self.verifier.verify(request['git_commit'])
            except Rejected as e:
                if str(e) == 'release_superseded_before_attempt':
                    return dict(state='superseded', git_commit=request['git_commit'])
                raise
            require(proof['proof_id'] not in {i['proof']['proof_id'] for i, _ in records}, 'executor_proof_replayed')
            before = self.engine.observation()
            expected_api = max(records, key=lambda record: record[0]['sequence'])[1]['after']['api'] if records else initial_api
            keys = ('id', 'image', 'labels')
            require({k: before['api'][k] for k in keys} == {k: expected_api[k] for k in keys}, 'executor_current_release_drift')
            # Ancestry of current running release checked using root-controlled Git,
            # not the requested SHA or its label alone.
            previous = revision(before['api']['labels'].get('org.opencontainers.image.revision'))
            self.source.git('merge-base', '--is-ancestor', previous, proof['build_source'])
            spec_digest = self.engine.prepare(proof)
            self.verifier.recheck(proof)
            self.check_authority()
            require(self.engine.observation() == before, 'executor_pre_activation_drift')
            intent = dict(kind='moneybowl-api-intent-v2', sequence=len(records)+1, request=request, proof=proof, before=before,
                          policy_sha256=sha256(self.policy_raw), runtime_sha256=spec_digest, issued_at=self.clock(),
                          activation_may_be_attempted=True)
            key = proof['proof_id']
            # Proof, release SHA and caller nonce are consumed DURABLY before pull or
            # activation. Any remaining intent without complete tuple blocks all work.
            publish(self.root / (key + '.intent.json'), intent, immutable=True)
            try:
                self.verifier.recheck(proof)
                self.check_authority()
                require(self.engine.observation() == before, 'executor_pre_activation_drift')
                def before_activation():
                    self.check_authority()
                    require(self.engine.observation() == before, 'executor_pre_activation_drift')
                    self.verifier.recheck(proof)
                self.engine.activate(proof, before_activation)  # exactly one permitted attempt
                after = self.engine.verify_after(before, proof)
                self.verifier.recheck(proof)  # branch move after attempt quarantines
                self.check_authority()
                receipt = {**envelope('dev', self.policy['environment_policy']['dev'], proof['release_source']),
                    'observed_at': self.clock(), 'oracle_dispatcher': 'retired',
                    'component': {'state': 'deployed', 'proof': 'running_image', 'healthy': True,
                                  'source_digest': proof['source_digest']},
                    'image': proof['image'], 'image_id': after['api']['image']}
                observed = dict(after=after, receipt=receipt, proof_id=key)
                publish(self.root / (key + '.observation.json'), observed, immutable=True)
                publish(Path(self.policy['receipt_root']) / (request['git_commit'] + '.json'), receipt, immutable=True)
                publish(self.root / (key + '.complete.json'), dict(state='VERIFIED',
                    intent_sha256=sha256(encoded(intent)), observation_sha256=sha256(encoded(observed)),
                    receipt_sha256=sha256(encoded(receipt))), immutable=True)
            except BaseException:
                # Even abrupt termination leaves an immutable intent. No catch here
                # can convert attempted delivery to superseded or safe-to-retry.
                raise Rejected('executor_transaction_quarantined') from None
            return dict(state='deployed', git_commit=request['git_commit'])


def production():
    policy, raw = load_authority()
    process = Process(policy)
    source = SealedSource(policy, process)
    verifier = GithubVerifier(policy, process, source, token=process.env.get('GH_TOKEN', ''))
    engine = ApiEngine(policy, process)
    return Broker(policy, raw, verifier, source, engine, load_authority)


def send_packet(connection, value):
    raw = encoded(value)
    require(len(raw) <= MAX_PACKET and connection.sendmsg([raw]) == len(raw), 'executor_short_send')


def client(sha):
    revision(sha)
    require(os.getuid() == os.geteuid() == 993 and os.getgid() == os.getegid() == 983, 'executor_client_identity')
    # Gate checked before any socket/provider contact. Root-owned public marker
    # grants no root config/state access and is a later commissioning artifact.
    marker = Path('/run/moneybowl-api-executor/enabled')
    info = marker.lstat()
    require(stat.S_ISREG(info.st_mode) and info.st_uid == 0 and not info.st_mode & 0o022
            and marker.read_bytes() == b'api-executor-v2\n', 'executor_client_disabled')
    with socket.socket(socket.AF_UNIX, socket.SOCK_SEQPACKET) as connection:
        connection.settimeout(MAX_SECONDS + 5)
        connection.connect(SOCKET_PATH)
        peer = struct.unpack('3i', connection.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, 12))
        require(peer[1:] == (0, 0), 'executor_server_identity')
        send_packet(connection, dict(schema_version=2, operation=OPERATION, git_commit=sha,
                                    request_id=sha256(('api-executor-v2:' + sha).encode())))
        raw, ancillary, flags, _ = connection.recvmsg(MAX_PACKET + 1, socket.CMSG_SPACE(256))
        for level, kind, data in ancillary:
            if level == socket.SOL_SOCKET and kind == socket.SCM_RIGHTS:
                fds = array.array('i'); fds.frombytes(data[:len(data) - len(data) % fds.itemsize])
                for fd in fds: os.close(fd)
        require(not ancillary and not flags, 'executor_reply_invalid')
        value = decoded(raw, MAX_PACKET)
        require(set(value) in ({'state', 'git_commit'}, {'state', 'reason'})
                and value['state'] in ('deployed', 'already_deployed', 'superseded', 'failed'), 'executor_reply_invalid')
        return value


def serve():
    # No injected socket activation or inherited descriptor from a caller. Never
    # unlink an existing socket: its presence needs commissioning/recovery review.
    policy, _ = load_authority()  # disabled/missing policy exits before socket bind
    parent = Path(SOCKET_PATH).parent
    require(parent.resolve() == parent and parent.lstat().st_uid == 0 and stat.S_IMODE(parent.lstat().st_mode) == 0o750
            and parent.lstat().st_gid == 983, 'executor_socket_directory_invalid')
    from initial_private_inputs import no_acl
    for path in (parent, *parent.parents):
        info = path.lstat()
        require(stat.S_ISDIR(info.st_mode) and info.st_uid == 0 and not info.st_mode & 0o022, 'executor_socket_directory_invalid')
        no_acl(path)
    require(not Path(SOCKET_PATH).exists() and not Path(SOCKET_PATH).is_symlink(), 'executor_socket_exists')
    previous_umask = os.umask(0o077)
    listener = socket.socket(socket.AF_UNIX, socket.SOCK_SEQPACKET)
    try:
        listener.bind(SOCKET_PATH)
        os.chown(SOCKET_PATH, 0, 983); os.chmod(SOCKET_PATH, 0o660)
    finally:
        os.umask(previous_umask)
    listener.listen(1)
    active = None
    try:
        while True:
            if active is not None:
                waited, _ = os.waitpid(active[0], os.WNOHANG)
                if waited or time.monotonic() - active[1] >= MAX_SECONDS:
                    try: os.killpg(active[0], signal.SIGKILL)
                    except ProcessLookupError: pass
                    if not waited: os.waitpid(active[0], 0)
                    active = None
            if not select.select([listener], [], [], .25)[0]:
                continue
            connection, _ = listener.accept()
            if active is not None:
                connection.close()
                continue
            try:
                request = receive(connection, policy)
            except (Rejected, OSError):
                connection.close()
                continue
            pid = os.fork()
            if pid == 0:
                listener.close()
                os.setsid()
                signal.alarm(MAX_SECONDS)
                try:
                    result = production().reconcile(request)
                except Rejected as error:
                    result = {'state': 'failed', 'reason': str(error)}
                except BaseException:
                    result = {'state': 'failed', 'reason': 'executor_transaction_unknown'}
                try:
                    send_packet(connection, result)
                finally:
                    connection.close()
                    os._exit(0)
            connection.close()
            active = (pid, time.monotonic())
    finally:
        listener.close()
        if active is not None:
            try: os.killpg(active[0], signal.SIGKILL)
            except ProcessLookupError: pass
        # The root-owned socket remains until a separately authorized service restart.


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('operation', choices=('serve', 'request'))
    parser.add_argument('--revision')
    args = parser.parse_args()
    try:
        if args.operation == 'serve':
            require(args.revision is None, 'executor_argument_invalid')
            serve()
            return 0
        result = client(args.revision)
    except Rejected as error:
        result = {'state': 'failed', 'reason': str(error)}
    except Exception:
        result = {'state': 'failed', 'reason': 'executor_uncommissioned_or_unavailable'}
    print(json.dumps(result, sort_keys=True))
    return 0 if result['state'] in ('deployed', 'already_deployed', 'superseded') else 1


if __name__ == '__main__':
    raise SystemExit(main())
