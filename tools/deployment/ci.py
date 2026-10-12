"""Offline promotion and immutable-history gate, driven by GitHub event files."""
import json
import os
from pathlib import Path
from contract import Rejected, git, immutable_history, promotion, revision


def main():
    try:
        event = json.loads(Path(os.environ['GITHUB_EVENT_PATH']).read_text())
        if os.environ['GITHUB_EVENT_NAME'] == 'pull_request':
            source = promotion('.', event)
        else:
            source = revision(event['after'])
            if event.get('deleted') or event.get('forced'):
                raise Rejected('unsafe_branch_update')
            base = event.get('before')
            # New feature branches must preserve all latest develop migration files too.
            if not base or base == '0' * 40:
                base = git('.', 'merge-base', source, 'origin/develop').decode().strip()
            immutable_history('.', base, source)
        print(json.dumps({'state': 'code_validated', 'reviewed_source': source}))
        return 0
    except Exception:
        print('{"state":"failed","reason":"promotion_or_history_invalid"}')
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
