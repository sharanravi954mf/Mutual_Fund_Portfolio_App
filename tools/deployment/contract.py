"""M4 public release contract. No database/financial mutation capability."""
import base64
import hashlib
import json
import re
import subprocess
from pathlib import Path

DEV_PROJECT = 'rskryngwzyuzmiwtriyy'
REPOSITORY = 'sharanravi954mf/Mutual_Fund_Portfolio_App'
SHA = re.compile(r'[0-9a-f]{40}')
COMPONENT_PATHS = {
    'migrations': ['supabase/migrations'],
    'edge_functions': ['supabase/functions', 'supabase/config.toml'],
    'ingestion_support': ['services/ingestion-support'],
}


class Rejected(Exception):
    """Only fixed, public error codes may cross the reporting boundary."""


def require(condition, code):
    if not condition:
        raise Rejected(code)


def revision(value):
    require(isinstance(value, str) and SHA.fullmatch(value) is not None, 'invalid_revision')
    require(value != '0' * 40, 'invalid_revision')
    return value


def git(repo, *args):
    try:
        return subprocess.check_output(['git', '-C', str(repo), *args], stderr=subprocess.DEVNULL, timeout=120)
    except (subprocess.SubprocessError, OSError):
        raise Rejected('git_failed') from None


def target(environment, policy):
    require(environment in ('dev', 'qa'), 'invalid_environment')
    p = policy[environment]
    require(p['branch'] == {'dev': 'develop', 'qa': 'qa'}[environment], 'invalid_branch_binding')
    project = p['project_ref']
    require(isinstance(project, str) and re.fullmatch(r'[a-z]{20}', project), 'invalid_project')
    require((environment == 'dev') == (project == DEV_PROJECT), 'wrong_project_binding')
    require(p['financial_policy'] == ('preserve' if environment == 'dev' else 'disabled'), 'financial_policy_invalid')
    require(p['nse_origin'] == ('https://nseinvestuat.nseindia.com' if environment == 'dev' else 'https://www.nseinvest.com'), 'wrong_nse_origin')
    return p


def push_event(event, environment, policy):
    p = target(environment, policy)
    require(isinstance(event, dict), 'malformed_event')
    require(isinstance(event.get('repository'), dict) and event['repository'].get('full_name') == REPOSITORY, 'wrong_repository')
    require(event.get('ref') == 'refs/heads/' + p['branch'], 'wrong_event_branch')
    require(event.get('deleted') is False and event.get('forced') is False, 'unsafe_branch_update')
    return revision(event.get('after'))


def public_defines(values, environment, policy):
    p = target(environment, policy)
    allowed = {'SUPABASE_URL', 'SUPABASE_ANON_KEY', 'MONEYBOWL_ENV',
               'NSE_CONSOLE_ENABLED', 'MONEYBOWL_DEV_ONBOARDING_PREVIEW'}
    require(isinstance(values, dict) and set(values) <= allowed, 'non_public_build_setting')
    require(values.get('MONEYBOWL_ENV') == environment, 'wrong_frontend_environment')
    require(values.get('SUPABASE_URL') == 'https://' + p['project_ref'] + '.supabase.co', 'wrong_frontend_project')
    key = values.get('SUPABASE_ANON_KEY', '')
    require(isinstance(key, str) and len(key) <= 4096, 'invalid_public_key')
    if not re.fullmatch(r'sb_publishable_[A-Za-z0-9_-]{16,}', key):
        try:
            parts = key.split('.')
            require(len(parts) == 3, 'invalid_public_key')
            claims = json.loads(base64.urlsafe_b64decode(parts[1] + '=' * (-len(parts[1]) % 4)))
            require(claims.get('role') == 'anon' and claims.get('ref') == p['project_ref'], 'invalid_public_key')
        except (ValueError, TypeError, KeyError):
            raise Rejected('invalid_public_key') from None
    for flag in ('NSE_CONSOLE_ENABLED', 'MONEYBOWL_DEV_ONBOARDING_PREVIEW'):
        require(values.get(flag, 'false') in ('true', 'false'), 'invalid_feature_flag')
        require(environment == 'dev' or values.get(flag, 'false') == 'false', 'dev_flag_in_qa')
    # Canonical values only: arbitrary defines and process environment are never forwarded.
    return {**values, **{f: values.get(f, 'false') for f in ('NSE_CONSOLE_ENABLED', 'MONEYBOWL_DEV_ONBOARDING_PREVIEW')}}


def manifest(repo, sha):
    revision(sha)
    components = {}
    for name, paths in COMPONENT_PATHS.items():
        # Git object IDs bind file paths, modes and content, including shared Edge dependencies.
        raw = git(repo, 'ls-tree', '-r', sha, '--', *paths)
        require(bool(raw), 'missing_component')
        components[name] = hashlib.sha256(raw).hexdigest()
    return components


def immutable_history(repo, base, head):
    revision(base)
    revision(head)
    entries = git(repo, 'diff', '--name-status', '--no-renames', base, head, '--',
                  'supabase/migrations', '.github/migration-history.json').decode().splitlines()
    require(all(line.startswith('A\t') and line.endswith('.sql') for line in entries), 'migration_history_modified')


def promotion(repo, event):
    pr = event['pull_request']
    base, head = pr['base'], pr['head']
    require(base['ref'] in ('develop', 'qa'), 'invalid_pr_target')
    revision(base['sha']); revision(head['sha'])
    require(head['repo']['full_name'] == REPOSITORY, 'untrusted_pr_source')
    if base['ref'] == 'qa':
        require(head['ref'] == 'develop', 'qa_requires_develop')
        git(repo, 'merge-base', '--is-ancestor', head['sha'], 'origin/develop')
        require(not git(repo, 'diff', head['sha'], 'HEAD', '--'), 'qa_merge_tree_differs')
    else:
        require(head['ref'].startswith('feature/'), 'develop_requires_feature')
    immutable_history(repo, base['sha'], head['sha'])
    return head['sha']


def load_policy():
    return json.loads(Path(__file__).with_name('environments.json').read_text())
