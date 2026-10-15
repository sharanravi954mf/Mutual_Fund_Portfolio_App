"""Authenticated GitHub publication verifier. Caller identities never supply proof.

Uses the supported gh attestation verifier and its trust roots, then enforces
policy on verified statements plus independent REST and sealed Git objects.
"""
import json
import re
import time
from datetime import datetime

from contract import Rejected, require, revision, manifest, DEV_PROJECT
from oci_delivery import (REPOSITORY, IMAGE, WORKFLOW, PREDICATE, DIGEST, document,
                          github, http, run_identity, completed_jobs)
from owner_common import sha256
from private_registry import Registry

MAX_AGE = 300
INDEPENDENT = 'independent-review-v1'
SOLO_OWNER = 'solo-owner-protected-merge-v1'


def authorization_policy(policy):
    """Only sealed root policy selects governance; absent legacy config stays independent."""
    require(type(policy.get('github_repository_id')) is int and policy['github_repository_id'] > 0,
            'executor_source_review_policy_invalid')
    reviewers = policy.get('approved_reviewers')
    require(type(reviewers) is dict and all(type(login) is str and re.fullmatch('[a-zA-Z0-9-]{1,39}', login)
            and type(uid) is int and uid > 0 for login, uid in reviewers.items()),
            'executor_source_review_policy_invalid')
    config = policy.get('release_authorization', {'mode': INDEPENDENT})
    require(type(config) is dict and type(config.get('mode')) is str
            and config['mode'] in (INDEPENDENT, SOLO_OWNER), 'release_authorization_policy_invalid')
    if config['mode'] == INDEPENDENT:
        require(set(config) == {'mode'} and reviewers, 'executor_source_review_policy_invalid')
    else:
        require(set(config) == {'mode', 'owner', 'required_checks'} and not reviewers
                and policy.get('repository') == REPOSITORY and policy.get('branch') == 'develop'
                and policy.get('project_ref') == DEV_PROJECT, 'release_authorization_policy_invalid')
        owner = config['owner']
        require(type(owner) is dict and set(owner) == {'login', 'id'}
                and owner['login'] == REPOSITORY.split('/')[0]
                and type(owner['id']) is int and owner['id'] > 0, 'release_authorization_owner_invalid')
        checks = config['required_checks']
        require(type(checks) is list and 0 < len(checks) <= 100 and all(type(c) is dict
                and set(c) == {'context', 'app_id'} and type(c['context']) is str and c['context']
                and type(c['app_id']) is int and c['app_id'] > 0 for c in checks),
                'release_authorization_checks_invalid')
        require(len({c['context'] for c in checks}) == len(checks)
                and 'M4 Required CI' in {c['context'] for c in checks}, 'release_authorization_checks_invalid')
    return config


def verified_predicate(raw, sha, run_id, attempt):
    """Only call with stdout of a successful pinned gh verification, never a bundle."""
    require(type(raw) is bytes and len(raw) <= 4 * 1024 * 1024, 'attestation_output_size')
    values = json.loads(raw)
    require(type(values) is list and 0 < len(values) <= 30, 'attestation_result_invalid')
    matches = []
    for entry in values:
        result = entry.get('verificationResult', {})
        statement = result.get('statement', {})
        p = statement.get('predicate', {})
        if statement.get('predicateType') != PREDICATE:
            continue
        required = {'index_digest', 'manifest_digest', 'config_digest', 'image', 'git_commit',
                    'build_source', 'release_source', 'source_digest', 'platform', 'repository',
                    'workflow', 'event', 'ref', 'run_id', 'run_attempt', 'archive_digest', 'builder'}
        require(type(p) is dict and set(p) == required
                and p['git_commit'] == p['build_source'] == p['release_source'] == sha
                and p['repository'] == REPOSITORY and p['workflow'] == WORKFLOW
                and p['event'] == 'push' and p['ref'] == 'refs/heads/develop'
                and type(p['run_id']) is int and p['run_id'] == run_id
                and type(p['run_attempt']) is int and p['run_attempt'] == attempt
                and p['platform'] == 'linux/arm64' and p['builder'] == 'github-hosted/ubuntu-24.04-arm'
                and all(DIGEST.fullmatch(p[k]) for k in
                        ('index_digest', 'manifest_digest', 'config_digest', 'archive_digest'))
                and p['image'] == IMAGE + '@' + p['manifest_digest']
                and len(p['source_digest']) == 64, 'attestation_policy_mismatch')
        require(statement.get('subject') == [{'name': IMAGE, 'digest': {'sha256': p['manifest_digest'][7:]}}],
                'attestation_subject_mismatch')
        # These properties come from the supported verifier, not self-authored JSON.
        require(result.get('signature', {}).get('certificate') and result.get('verifiedTimestamps'),
                'attestation_authenticated_metadata_missing')
        matches.append(p)
    require(len(matches) == 1, 'attestation_missing_or_ambiguous')
    return matches[0]


class GithubVerifier:
    def __init__(self, policy, command, source, token='', transport=http, registry=None, clock=time.time):
        self.policy, self.command, self.source = policy, command, source
        self.token, self.transport, self.clock = token, transport, clock
        self.registry = registry or Registry(policy['owner_config'])

    def get(self, path):
        # The repository metadata endpoint has no trailing slash. Keep the shared
        # bounded/authenticated reader, without relying on provider redirects.
        return github(path, self.token, lambda url, headers: self.transport(url.rstrip('/'), headers))

    def head(self):
        return revision(self.get('git/ref/heads/develop')['object']['sha'])

    def repository_identity(self, repo, owner):
        require(type(repo) is dict and repo.get('full_name') == REPOSITORY
                and type(repo.get('id')) is int and repo['id'] == self.policy['github_repository_id']
                and repo.get('owner', {}).get('login') == owner['login']
                and type(repo.get('owner', {}).get('id')) is int
                and repo['owner']['id'] == owner['id'] and repo.get('fork') is False,
                'release_repository_identity_changed')

    def governance(self, config):
        # Bounded support for classic protection. Never infer missing protection
        # from a 404 or silently ignore an additional, possibly conflicting ruleset.
        rules = self.get('rules/branches/develop?per_page=100')
        require(rules == [], 'release_governance_rules_unsupported')
        protection = self.get('branches/develop/protection')
        require(type(protection) is dict, 'release_governance_unverifiable')
        checks = protection.get('required_status_checks', {})
        actual = checks.get('checks') if type(checks) is dict else None
        require(type(checks) is dict and checks.get('strict') is True
                and type(actual) is list and all(type(c) is dict and set(c) == {'context', 'app_id'}
                    and type(c['context']) is str and type(c['app_id']) is int for c in actual)
                and sorted(actual, key=lambda c: c['context']) == sorted(config['required_checks'], key=lambda c: c['context'])
                and type(checks.get('contexts')) is list
                and sorted(checks['contexts']) == sorted(c['context'] for c in config['required_checks']),
                'release_governance_checks_changed')
        reviews = protection.get('required_pull_request_reviews')
        require(type(reviews) is dict and type(reviews.get('required_approving_review_count')) is int
                and reviews['required_approving_review_count'] == 0
                and reviews.get('dismiss_stale_reviews') is True
                and reviews.get('require_code_owner_reviews') is False
                and reviews.get('require_last_push_approval') is False,
                'release_governance_review_conflict')
        bypass = reviews.get('bypass_pull_request_allowances', {})
        require(type(bypass) is dict and not set(bypass) - {'users', 'teams', 'apps'}
                and all(value == [] for value in bypass.values()), 'release_governance_bypass')
        for field, expected in (('enforce_admins', True), ('allow_force_pushes', False),
                                ('allow_deletions', False), ('required_conversation_resolution', True)):
            require(type(protection.get(field)) is dict and protection[field].get('enabled') is expected,
                    'release_governance_unprotected')

    def solo_merge(self, sha, pull, config):
        require(type(self.token) is str and self.token.strip(), 'release_authenticated_reads_required')
        self.repository_identity(self.get(''), config['owner'])
        number = pull.get('number')
        require(type(number) is int and number > 0, 'release_pull_identity_invalid')
        # Commit association summaries are discovery only, never merger evidence.
        full = self.get(f'pulls/{number}')
        require(type(full) is dict and full.get('number') == number
                and type(full.get('id')) is int and full['id'] > 0
                and full.get('merged') is True and full.get('state') == 'closed'
                and full.get('merge_commit_sha') == sha and full.get('merged_at') == pull.get('merged_at')
                and full.get('base', {}).get('ref') == 'develop'
                and full.get('head', {}).get('ref') == pull['head']['ref']
                and full.get('head', {}).get('sha') == pull['head']['sha'], 'release_pull_identity_invalid')
        require(re.fullmatch(r'feature/.+', full['head']['ref']), 'release_pull_identity_invalid')
        revision(full['head']['sha'])
        for side in ('base', 'head'):
            self.repository_identity(pull[side].get('repo'), config['owner'])
            self.repository_identity(full[side].get('repo'), config['owner'])
        merger = full.get('merged_by')
        require(type(merger) is dict and merger.get('login') == config['owner']['login']
                and type(merger.get('id')) is int and merger['id'] == config['owner']['id'],
                'release_owner_merge_required')
        try:
            stamp = datetime.fromisoformat(full['merged_at'].replace('Z', '+00:00'))
            require(stamp.utcoffset() is not None, 'release_merge_time_invalid')
        except (TypeError, AttributeError, ValueError):
            raise Rejected('release_merge_time_invalid') from None
        commit = self.get('git/commits/' + sha)
        parents = commit.get('parents', [])
        require(commit.get('sha') == sha and type(parents) is list and len(parents) == 2
                and parents[1].get('sha') == full['head']['sha'], 'release_merge_parent_mismatch')
        self.governance(config)
        return full

    def reviewed_merge(self, sha):
        config = authorization_policy(self.policy)
        pulls = self.get('commits/' + sha + '/pulls?per_page=100')
        require(type(pulls) is list and len(pulls) < 100, 'release_review_unverifiable')
        matches = [p for p in pulls if p.get('merged_at') and p.get('merge_commit_sha') == sha
                   and p.get('base', {}).get('ref') == 'develop'
                   and p.get('base', {}).get('repo', {}).get('full_name') == REPOSITORY
                   and p.get('head', {}).get('repo', {}).get('full_name') == REPOSITORY
                   and p.get('head', {}).get('ref', '').startswith('feature/')]
        require(len(matches) == 1, 'release_reviewed_merge_required')
        pull = matches[0]
        if config['mode'] == SOLO_OWNER:
            pull = self.solo_merge(sha, pull, config)
        reviews = self.get(f"pulls/{pull['number']}/reviews?per_page=100")
        require(type(reviews) is list and len(reviews) < 100, 'release_review_unverifiable')
        latest = {}
        for r in reviews:
            user = r.get('user', {}).get('login')
            if config['mode'] == SOLO_OWNER:
                uid = r.get('user', {}).get('id')
                require(type(uid) is int and uid > 0 and type(user) is str
                        and r.get('state') in ('APPROVED', 'CHANGES_REQUESTED', 'COMMENTED', 'DISMISSED', 'PENDING'),
                        'release_review_unverifiable')
                if r['state'] != 'COMMENTED':
                    latest[uid] = r
            elif (user in self.policy['approved_reviewers'] and r.get('user', {}).get('id') == self.policy['approved_reviewers'][user]
                  and r.get('state') != 'COMMENTED'):
                latest[user] = r
        if config['mode'] == SOLO_OWNER:
            require(not any(r.get('state') in ('CHANGES_REQUESTED', 'PENDING') for r in latest.values()),
                    'release_contradictory_review')
            return dict(kind='moneybowl-release-authorization-v1', schema_version=1, mode=SOLO_OWNER,
                repository=REPOSITORY, repository_id=self.policy['github_repository_id'], owner=config['owner'],
                pull_request_id=pull['id'], pull_request_number=pull['number'], base='develop',
                head_ref=pull['head']['ref'], head_sha=pull['head']['sha'], merge_commit_sha=sha,
                merged_at=pull['merged_at'], merged_by={k: pull['merged_by'][k] for k in ('login', 'id')})
        require(any(r.get('state') == 'APPROVED' and r.get('commit_id') == pull['head']['sha']
                    for r in latest.values())
                and not any(r.get('state') == 'CHANGES_REQUESTED' for r in latest.values()),
                'release_independent_review_required')
        return dict(kind='moneybowl-release-authorization-v1', schema_version=1, mode=INDEPENDENT,
                    pull_request_number=pull['number'], head_sha=pull['head']['sha'], merge_commit_sha=sha)

    def required_jobs(self, run_id, attempt, sha):
        jobs = self.get(f'actions/runs/{run_id}/attempts/{attempt}/jobs?per_page=100')
        completed_jobs(jobs, {'M4 Required CI': 'ubuntu-latest', 'M4 Isolated ARM64 Build': 'ubuntu-24.04-arm',
                              'M4 Verified Private Publication': 'ubuntu-latest'})
        config = authorization_policy(self.policy)
        if config['mode'] != SOLO_OWNER:
            return
        checks = self.get(f'commits/{sha}/check-runs?filter=latest&per_page=100')
        require(type(checks) is dict and type(checks.get('check_runs')) is list
                and checks.get('total_count') == len(checks['check_runs'])
                and len(checks['check_runs']) < 100, 'release_checks_incomplete')
        for expected in config['required_checks']:
            matching = [c for c in checks['check_runs'] if c.get('name') == expected['context']]
            require(len(matching) == 1, 'release_required_check_missing_or_ambiguous')
            check = matching[0]
            require(check.get('head_sha') == sha and check.get('status') == 'completed'
                    and check.get('conclusion') == 'success' and type(check.get('app', {}).get('id')) is int
                    and check['app']['id'] == expected['app_id'], 'release_required_check_failed')
            if expected['context'] == 'M4 Required CI':
                job = next(j for j in jobs['jobs'] if j['name'] == 'M4 Required CI')
                require(type(check.get('id')) is int and check['id'] > 0 and job.get('check_run_url') ==
                        f"https://api.github.com/repos/{REPOSITORY}/check-runs/{check['id']}",
                        'release_check_attempt_mismatch')

    def verify(self, sha, accepted=None):
        revision(sha)
        require(self.head() == sha, 'release_superseded_before_attempt')
        authorization = self.reviewed_merge(sha)
        if accepted is not None:
            require(accepted.get('release_authorization') == authorization, 'release_acceptance_authorization_changed')
        self.source.check(sha)
        runs = self.get('actions/runs?branch=develop&event=push&head_sha=' + sha + '&per_page=100')
        require(runs.get('total_count') == len(runs.get('workflow_runs', []))
                and len(runs['workflow_runs']) <= 100, 'publication_runs_incomplete')
        candidates = [r for r in runs['workflow_runs'] if r.get('path') == WORKFLOW
                      and r.get('status') in ('completed', 'in_progress')]
        require(len(candidates) == 1, 'publication_run_missing_or_ambiguous')
        run = candidates[0]
        run_id, attempt = run['id'], run['run_attempt']
        run_identity(run, sha, run_id, attempt)
        require(run['repository'].get('id') == self.policy['github_repository_id'], 'repository_identity_changed')
        if accepted is None:
            # First acceptance resolves the subject from authenticated artifact metadata.
            artifacts = self.get(f'actions/runs/{run_id}/artifacts?per_page=100')
            require(artifacts.get('total_count') == len(artifacts.get('artifacts', [])), 'publication_artifacts_incomplete')
            names = [a for a in artifacts['artifacts'] if a.get('name') == f'api-identity-{sha}-{attempt}'
                     and a.get('expired') is False]
            require(len(names) == 1 and 0 < names[0].get('size_in_bytes', 0) <= 65536, 'publication_identity_missing')
            identity = self.command.artifact(run_id, names[0]['id'])
        else:
            # Completed root journal supplies ONLY a locator. The live attestation
            # must cryptographically authenticate its entire immutable predicate again;
            # neither this JSON nor its hashes replace the independent trust root.
            require(accepted.get('git_commit') == sha and accepted.get('run_id') == run_id
                    and accepted.get('run_attempt') == attempt, 'publication_acceptance_changed')
            identity = {'manifest_digest': accepted.get('manifest_digest')}
        require(set(identity) == {'manifest_digest'} and DIGEST.fullmatch(identity['manifest_digest']),
                'publication_identity_invalid')
        image = IMAGE + '@' + identity['manifest_digest']
        raw = self.command.verify_attestation(image, sha)
        proof = verified_predicate(raw, sha, run_id, attempt)
        if accepted is not None:
            require({k: v for k, v in accepted.items() if k not in {'verified_at', 'expires_at', 'proof_id', 'release_authorization'}} == proof,
                    'publication_acceptance_changed')
        require(proof['image'] == image and proof['source_digest'] == self.source.component(sha),
                'publication_source_mismatch')
        self.required_jobs(run_id, attempt, sha)
        remote = self.registry.verify(dict(image=image, image_id=proof['config_digest'],
                                           git_commit=sha, source_digest=proof['source_digest']))
        require(remote.get('config_digest') == proof['config_digest'] and remote.get('manifest_digest') == proof['manifest_digest']
                and remote.get('private') is True, 'publication_remote_mismatch')
        now = self.clock()
        return {**proof, 'release_authorization': authorization, 'verified_at': now, 'expires_at': now + MAX_AGE,
                'proof_id': sha256((str(run_id) + ':' + str(attempt) + ':' + proof['manifest_digest'] + ':'
                    + json.dumps(authorization, sort_keys=True, separators=(',', ':'))).encode())}

    def recheck(self, proof):
        require(proof['verified_at'] <= self.clock() < proof['expires_at'] <= proof['verified_at'] + MAX_AGE,
                'publication_proof_expired')
        require(self.head() == proof['git_commit'], 'release_source_changed')
        require(self.reviewed_merge(proof['git_commit']) == proof.get('release_authorization'),
                'release_acceptance_authorization_changed')
        self.source.check(proof['git_commit'])
        run = self.get(f"actions/runs/{proof['run_id']}")
        run_identity(run, proof['git_commit'], proof['run_id'], proof['run_attempt'])
        require(run['repository'].get('id') == self.policy['github_repository_id'], 'repository_identity_changed')
        require(run.get('status') in ('completed', 'in_progress'), 'publication_run_changed')
        self.required_jobs(proof['run_id'], proof['run_attempt'], proof['git_commit'])
        # Source fetch and provider reads can take time. Check HEAD again at the
        # end so the pre-Compose guard finishes with the exact live source binding.
        require(self.head() == proof['git_commit'], 'release_source_changed')
        require(proof['verified_at'] <= self.clock() < proof['expires_at'] <= proof['verified_at'] + MAX_AGE,
                'publication_proof_expired')
