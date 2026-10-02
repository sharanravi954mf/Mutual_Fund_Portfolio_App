#!/usr/bin/env python3
"""Render the deployment manifest with synthetic env only. No Docker daemon calls."""
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import sys

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[1]
DEPLOY = ROOT / 'services/outbox-dispatcher/deploy'
spec = importlib.util.spec_from_file_location('reconcile', DEPLOY / 'reconcile.py')
r = importlib.util.module_from_spec(spec)
spec.loader.exec_module(r)
env = {k: 'synthetic-only' for k in r.SECRETS}
env.update(dict(zip(r.SETTINGS, ['false', '60', '30', '10', '45', '30', '12'])))
env.update(SUPABASE_URL='https://example.invalid', DISPATCHER_IMAGE='moneybowl-outbox-dispatcher:'+'a'*40)
with tempfile.TemporaryDirectory(prefix='moneybowl-compose-test-') as directory:
    path = Path(directory) / 'synthetic.env'
    path.write_text(''.join(k+'='+v+'\n' for k,v in env.items()))
    path.chmod(0o600)
    result = subprocess.run(['docker', 'compose', '--project-name', r.PROJECT, '--env-file', str(path),
                             '-f', str(DEPLOY / 'compose.yaml'), 'config', '--format', 'json'],
                            capture_output=True, text=True, check=True)
    cfg = json.loads(result.stdout)
    r.check_compose(cfg, env)
    assert cfg['services'][r.SERVICE]['image'] == env['DISPATCHER_IMAGE']
print('Synthetic Compose rendering and deployment preflight: PASS')
