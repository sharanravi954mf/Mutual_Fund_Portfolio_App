#!/usr/bin/env python3
"""Replacement consumer for the EXISTING verified GitHub webhook spool.

No new HTTP endpoint, webhook secret or Docker socket mount. Both reconcilers
are attempted independently; their timers recover failed deliveries.
"""
import fcntl
import json
from pathlib import Path
import re
import subprocess

ROOT = Path('/home/ubuntu/moneybowl-runtime/github-webhook-container')
DEPLOY = Path('/home/ubuntu/moneybowl-runtime/outbox-dispatcher')
WEB = '/home/ubuntu/moneybowl-runtime/flutter-web-dev/deploy-develop.sh'


def event_sha(raw):
    event = json.loads(raw)
    if (event.get('repository') != 'sharanravi954mf/Mutual_Fund_Portfolio_App' or
            event.get('ref') != 'refs/heads/develop' or
            not re.fullmatch('[0-9a-f]{40}', event.get('head_sha', '')) or
            event['head_sha'] == '0' * 40):
        raise ValueError('invalid_event')
    return event['head_sha']


def main():
    with (ROOT / 'process-spool.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        events = sorted((ROOT / 'spool').glob('*.json'))
        if not events:
            return 0
        ok = True
        for event in events:
            try:
                sha = event_sha(event.read_text())
                # Only a fixed systemd template may read the root-owned env.
                result = subprocess.run(['sudo', '--non-interactive', '/usr/bin/systemctl',
                                         'start', '--wait', 'moneybowl-outbox-dispatcher-reconcile@' + sha + '.service'], check=False)
                ok = result.returncode == 0 and ok
            except (ValueError, OSError):
                ok = False
        # Preserve Flutter's existing latest-develop batch reconciliation.
        try:
            ok = subprocess.run([WEB], check=False).returncode == 0 and ok
        except OSError:
            ok = False
        destination = ROOT / ('processed' if ok else 'failed')
        destination.mkdir(exist_ok=True)
        for event in events:
            event.rename(destination / event.name)
        print('WEBHOOK_EVENT_BATCH=' + ('PROCESSED' if ok else 'FAILED'))
        return 0 if ok else 1


if __name__ == '__main__':
    raise SystemExit(main())
