"""Shared release data contract. Branch names select fixed, never caller-chosen targets."""
import json
import re
from types import MappingProxyType

from contract import DEV_PROJECT, REPOSITORY, require, revision

REPOSITORY_ID = 1303872993
OWNER_ID = 306140954
WORKFLOW = '.github/workflows/shared-release.yml'
IMAGE = 'ghcr.io/sharanravi954mf/moneybowl-ingestion-dev'
REQUIRED_CHECKS = ('M4 Required CI', 'validate-commits', 'validate-docs')
APP_ID = 15368
TARGETS = MappingProxyType({
    'develop': ('dev', 'DEV', 'dev', 'feature/'),
    'qa': ('qa', 'QA', 'qa', 'develop'),
    'main': ('production', 'PROD', 'production', 'qa'),
})
INFRASTRUCTURE = ('services/ingestion-support/compose.yaml',
                  'services/ingestion-support/compose.hosted.yaml', 'services/ingestion-support/Caddyfile')
MAX_REQUEST = 2 * 1024 * 1024


def target(ref):
    require(type(ref) is str and ref.startswith('refs/heads/'), 'release_branch_invalid')
    branch = ref.removeprefix('refs/heads/')
    require(branch in TARGETS, 'release_branch_invalid')
    env, runtime, github_environment, source = TARGETS[branch]
    return dict(branch=branch, environment=env, runtime_environment=runtime,
                github_environment=github_environment, promotion_source=source)


def push(event_name, event, ref, sha):
    require(event_name == 'push', 'release_requires_merged_push')
    t = target(ref)
    repo = event.get('repository', {})
    require(repo.get('id') == REPOSITORY_ID and repo.get('full_name') == REPOSITORY
            and repo.get('owner', {}).get('id') == OWNER_ID and repo.get('fork') is False,
            'release_repository_invalid')
    require(event.get('ref') == ref and event.get('after') == revision(sha)
            and event.get('deleted') is False and event.get('forced') is False,
            'release_push_invalid')
    revision(event.get('before'))
    return t


def pr_source(base, head):
    require(base in TARGETS and type(head) is str, 'promotion_target_invalid')
    required = TARGETS[base][3]
    require(head.startswith(required) and len(head) > len(required) if base == 'develop'
            else head == required, 'promotion_source_invalid')


def digest(value):
    require(type(value) is str and re.fullmatch(r'sha256:[0-9a-f]{64}', value), 'release_digest_invalid')
    return value


def request(value, *, now=None):
    fields = {'schema', 'repository_id', 'environment', 'project_ref', 'branch', 'deployment_sha',
              'build_sha', 'component_digest', 'infrastructure', 'image', 'run_id', 'issued_at', 'expires_at'}
    require(type(value) is dict and set(value) == fields and value['schema'] == 1
            and value['repository_id'] == REPOSITORY_ID, 'release_request_invalid')
    t = target('refs/heads/' + value['branch'])
    require(value['environment'] == t['environment'], 'release_environment_mismatch')
    require(type(value['project_ref']) is str and re.fullmatch('[a-z]{20}', value['project_ref'])
            and ((t['environment'] == 'dev') == (value['project_ref'] == DEV_PROJECT)), 'release_project_isolation')
    require(type(value['infrastructure']) is dict and set(value['infrastructure']) == set(INFRASTRUCTURE)
            and all(type(v) is str and re.fullmatch('[0-9a-f]{64}', v) for v in value['infrastructure'].values()),
            'release_infrastructure_invalid')
    revision(value['deployment_sha']); revision(value['build_sha'])
    require(re.fullmatch('[0-9a-f]{64}', value['component_digest']), 'release_component_invalid')
    require(value['image'].startswith(IMAGE + '@'), 'release_image_repository_invalid')
    digest(value['image'].removeprefix(IMAGE + '@'))
    require(type(value['run_id']) is int and value['run_id'] > 0, 'release_run_invalid')
    require(type(value['issued_at']) is int and type(value['expires_at']) is int
            and 0 < value['expires_at'] - value['issued_at'] <= 900, 'release_expiry_invalid')
    if now is not None:
        require(value['issued_at'] <= now <= value['expires_at'], 'release_authority_expired')
    return value


def encoded(value):
    return (json.dumps(value, sort_keys=True, separators=(',', ':'), allow_nan=False) + '\n').encode()


def decoded(raw, limit=MAX_REQUEST):
    require(type(raw) is bytes and len(raw) <= limit, 'release_document_oversized')
    def unique(items):
        result = {}
        for k, v in items:
            require(k not in result, 'release_duplicate_key')
            result[k] = v
        return result
    return json.loads(raw, object_pairs_hook=unique,
                      parse_constant=lambda _: require(False, 'release_nonfinite_number'))


def public_config(t, project, key):
    require(type(project) is str and re.fullmatch('[a-z]{20}', project), 'release_project_invalid')
    require((t['environment'] == 'dev') == (project == DEV_PROJECT), 'release_project_isolation')
    # Publishable keys are public configuration. Legacy JWTs need explicit role/ref validation.
    from contract import public_defines
    from contract import load_policy
    policy = load_policy()
    env = 'prod' if t['environment'] == 'production' else t['environment']
    policy[env] = dict(policy[env], project_ref=project)
    values = public_defines({'SUPABASE_URL': 'https://' + project + '.supabase.co',
                            'SUPABASE_ANON_KEY': key, 'MONEYBOWL_ENV': env,
                            'NSE_CONSOLE_ENABLED': 'false', 'MONEYBOWL_DEV_ONBOARDING_PREVIEW': 'false'}, env, policy)
    return values
