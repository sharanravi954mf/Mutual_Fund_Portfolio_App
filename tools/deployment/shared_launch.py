"""Root-owned bootstrap carrier. Installation pins the complete versioned source closure."""
import json
import os
import sys
from pathlib import Path

# This carrier and private host.json are independently installed/root-owned, never
# loaded from a Git worktree. The versioned directory cannot be caller-selected.
if os.getuid() != 0 or len(sys.argv) != 1:
    raise SystemExit(1)
config_path = Path('/etc/moneybowl-shared-deploy/host.json')
if config_path.resolve() != config_path or config_path.stat().st_uid != 0 or config_path.stat().st_mode & 0o077:
    raise SystemExit(1)
config = json.loads(config_path.read_bytes())
source = config.get('installed_source', '')
if len(source) != 40 or any(c not in '0123456789abcdef' for c in source):
    raise SystemExit(1)
directory = Path('/opt/moneybowl-shared-deploy') / source / 'tools/deployment'
for parent in [directory, *directory.parents]:
    if parent.resolve() != parent or parent.stat().st_uid != 0 or parent.stat().st_mode & 0o022:
        raise SystemExit(1)
sys.path.insert(0, str(directory))
from shared_host import main
raise SystemExit(main())
