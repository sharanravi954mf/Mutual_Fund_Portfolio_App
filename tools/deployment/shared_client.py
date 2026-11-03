"""SSH forced-command client. No shell/argv transport; only one fixed systemd unit."""
import hashlib
import os
import stat
import subprocess
import sys
from pathlib import Path

if __name__ == '__main__':
    # Isolated Python (-I) deliberately omits the script directory. Admit only the
    # root-controlled installed directory before importing any deployment code.
    directory = Path(__file__).resolve().parent
    for parent in [directory, *directory.parents]:
        if parent.resolve() != parent or parent.stat().st_uid != 0 or parent.stat().st_mode & 0o022:
            raise SystemExit(1)
    sys.path.insert(0, str(directory))

from contract import require
from shared_contract import MAX_REQUEST, decoded, encoded, request

INBOX = Path('/var/spool/moneybowl-shared-deploy/inbox/request.json')
RESULT = Path('/run/moneybowl-shared-deploy/result.json')
UNIT = 'moneybowl-api-deploy.service'


def main():
    try:
        require(os.getuid() == os.geteuid() == 993 and os.getgid() == os.getegid() == 983,
                'shared_client_identity_invalid')
        status = dict(line.split(':', 1) for line in Path('/proc/self/status').read_text().splitlines() if ':' in line)
        require(int(status['CapEff'].strip(), 16) == 0, 'shared_client_capabilities_invalid')
        require(not os.environ.get('SSH_ORIGINAL_COMMAND') and len(sys.argv) == 1, 'shared_client_command_forbidden')
        raw = sys.stdin.buffer.read(MAX_REQUEST + 1)
        envelope = decoded(raw)
        require(set(envelope) == {'release', 'bundle'}, 'shared_client_envelope_invalid')
        request(envelope['release'])
        parent = INBOX.parent.lstat()
        require(stat.S_ISDIR(parent.st_mode) and parent.st_uid == 993 and parent.st_gid == 983
                and stat.S_IMODE(parent.st_mode) == 0o700 and INBOX.parent.resolve() == INBOX.parent,
                'shared_client_inbox_invalid')
        fd = os.open(INBOX, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        with os.fdopen(fd, 'wb') as out:
            out.write(raw); out.flush(); os.fsync(out.fileno())
        dfd = os.open(INBOX.parent, os.O_RDONLY | os.O_DIRECTORY)
        try: os.fsync(dfd)
        finally: os.close(dfd)
        # Polkit may authorize start of this exact root-owned unit only. No sudo, unit
        # properties, environment, executable, Docker endpoint or restart action is accepted.
        p = subprocess.run(['/usr/bin/systemctl', 'start', UNIT], env={'PATH': '/usr/bin:/bin', 'LANG': 'C.UTF-8'},
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=600)
        require(p.returncode == 0, 'shared_client_execution_uncertain')
        info = RESULT.lstat()
        require(stat.S_ISREG(info.st_mode) and info.st_uid == 0 and info.st_gid == 983
                and info.st_nlink == 1 and stat.S_IMODE(info.st_mode) == 0o640, 'shared_client_result_invalid')
        result = decoded(RESULT.read_bytes())
        require(result['request_sha256'] == hashlib.sha256(raw).hexdigest()
                and result['state'] in ('deployed', 'already_deployed')
                and result['release'] == envelope['release'], 'shared_client_result_mismatch')
        sys.stdout.buffer.write(encoded(result)); sys.stdout.buffer.flush()
        # Successful requests alone can be removed. Failure/timeout preserves the inbox
        # and any consumed root journal for explicit investigation, never automatic retry.
        require(INBOX.read_bytes() == raw, 'shared_client_inbox_changed')
        INBOX.unlink()
        return 0
    except Exception:
        print('{"state":"failed","reason":"shared_client_stopped_review_required"}')
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
