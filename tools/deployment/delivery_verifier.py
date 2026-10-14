"""Authenticated GitHub publication verifier. Caller identities never supply proof.

Uses the supported gh attestation verifier and its trust roots, then enforces
policy on verified statements plus independent REST and sealed Git objects.
"""
import json
import time

from contract import Rejected, require, revision, manifest
from oci_delivery import (REPOSITORY, IMAGE, WORKFLOW, PREDICATE, DIGEST, document,
                          github, http, run_identity, completed_jobs)
from owner_common import sha256
from private_registry import Registry

MAX_AGE = 300


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
        return github(path, self.token, self.transport)

    def head(self):
        return revision(self.get('git/ref/heads/develop')['object']['sha'])

    def reviewed_merge(self, sha):
        pulls = self.get('commits/' + sha + '/pulls?per_page=100')
        require(type(pulls) is list and len(pulls) < 100, 'release_review_unverifiable')
        matches = [p for p in pulls if p.get('merged_at') and p.get('merge_commit_sha') == sha
                   and p.get('base', {}).get('ref') == 'develop'
                   and p.get('base', {}).get('repo', {}).get('full_name') == REPOSITORY
                   and p.get('head', {}).get('repo', {}).get('full_name') == REPOSITORY
                   and p.get('head', {}).get('ref', '').startswith('feature/')]
        require(len(matches) == 1, 'release_reviewed_merge_required')
        pull = matches[0]
        reviews = self.get(f"pulls/{pull['number']}/reviews?per_page=100")
        require(type(reviews) is list and len(reviews) < 100, 'release_review_unverifiable')
        latest = {}
        for r in reviews:
            user = r.get('user', {}).get('login')
            if (user in self.policy['approved_reviewers'] and r.get('user', {}).get('id') == self.policy['approved_reviewers'][user]
                    and r.get('state') != 'COMMENTED'):
                latest[user] = r
        require(any(r.get('state') == 'APPROVED' and r.get('commit_id') == pull['head']['sha']
                    for r in latest.values())
                and not any(r.get('state') == 'CHANGES_REQUESTED' for r in latest.values()),
                'release_independent_review_required')

    def verify(self, sha, accepted=None):
        revision(sha)
        require(self.head() == sha, 'release_superseded_before_attempt')
        self.reviewed_merge(sha)
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
            require({k: v for k, v in accepted.items() if k not in {'verified_at', 'expires_at', 'proof_id'}} == proof,
                    'publication_acceptance_changed')
        require(proof['image'] == image and proof['source_digest'] == self.source.component(sha),
                'publication_source_mismatch')
        completed_jobs(self.get(f'actions/runs/{run_id}/attempts/{attempt}/jobs?per_page=100'),
                       {'M4 Required CI': 'ubuntu-latest', 'M4 Isolated ARM64 Build': 'ubuntu-24.04-arm',
                        'M4 Verified Private Publication': 'ubuntu-latest'})
        remote = self.registry.verify(dict(image=image, image_id=proof['config_digest'],
                                           git_commit=sha, source_digest=proof['source_digest']))
        require(remote.get('config_digest') == proof['config_digest'] and remote.get('manifest_digest') == proof['manifest_digest']
                and remote.get('private') is True, 'publication_remote_mismatch')
        now = self.clock()
        return {**proof, 'verified_at': now, 'expires_at': now + MAX_AGE,
                'proof_id': sha256((str(run_id) + ':' + str(attempt) + ':' + proof['manifest_digest']).encode())}

    def recheck(self, proof):
        require(proof['verified_at'] <= self.clock() < proof['expires_at'] <= proof['verified_at'] + MAX_AGE,
                'publication_proof_expired')
        require(self.head() == proof['git_commit'], 'release_source_changed')
        self.reviewed_merge(proof['git_commit'])
        self.source.check(proof['git_commit'])
        run = self.get(f"actions/runs/{proof['run_id']}")
        run_identity(run, proof['git_commit'], proof['run_id'], proof['run_attempt'])
        require(run.get('status') in ('completed', 'in_progress'), 'publication_run_changed')
        # Source fetch and provider reads can take time. Check HEAD again at the
        # end so the pre-Compose guard finishes with the exact live source binding.
        require(self.head() == proof['git_commit'], 'release_source_changed')
        require(proof['verified_at'] <= self.clock() < proof['expires_at'] <= proof['verified_at'] + MAX_AGE,
                'publication_proof_expired')
