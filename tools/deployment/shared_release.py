"""Protected Actions release admission and request creation. No host or Supabase writes."""
import argparse
import hashlib
import json
import os
import time
import urllib.request
from pathlib import Path

from contract import REPOSITORY, Rejected, git, manifest, require, revision
from observe import NoRedirect
from shared_contract import (APP_ID, OWNER_ID, REQUIRED_CHECKS, REPOSITORY_ID,
                             IMAGE, INFRASTRUCTURE, decoded, encoded, pr_source, push, request, target)


class Github:
    def __init__(self, token):
        require(type(token) is str and token and not any(c.isspace() for c in token), 'github_token_missing')
        self.token = token

    def __call__(self, path):
        require(path.startswith('/') and '..' not in path and '\\' not in path, 'github_path_invalid')
        url = 'https://api.github.com/repos/' + REPOSITORY + path
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
        try:
            req = urllib.request.Request(url, headers={'Authorization': 'Bearer ' + self.token,
                'Accept': 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28',
                'User-Agent': 'moneybowl-shared-release'})
            with opener.open(req, timeout=30) as response:
                return decoded(response.read(2 * 1024 * 1024 + 1))
        except Exception:
            raise Rejected('github_read_failed') from None


def check_results(rows):
    require(type(rows) is list, 'required_ci_invalid')
    for name in REQUIRED_CHECKS:
        checks = [v for v in rows if v.get('name') == name and v.get('app', {}).get('id') == APP_ID]
        require(checks, 'required_ci_pending')
        # GitHub's latest filter is per check suite; reject conflicting suites, never pick a convenient success.
        require(all(v.get('status') == 'completed' and v.get('conclusion') == 'success' for v in checks),
                'required_ci_not_successful')


def admit(event_name, event, ref, sha, api, repo='.'):
    t = push(event_name, event, ref, sha)
    require(api('/git/ref/heads/' + t['branch'])['object']['sha'] == sha, 'release_superseded')
    commit = api('/commits/' + sha)
    parents = commit.get('parents', [])
    require(commit.get('sha') == sha and len(parents) == 2
            and parents[0]['sha'] == event['before'], 'release_requires_merge_commit')
    rows = api('/commits/' + sha + '/pulls?per_page=100')
    matches = [v for v in rows if v.get('merge_commit_sha') == sha and v.get('base', {}).get('ref') == t['branch']]
    require(len(matches) == 1, 'release_pr_ambiguous')
    pr = api('/pulls/' + str(matches[0]['number']))
    require(pr.get('merged') is True and pr.get('merge_commit_sha') == sha
            and pr.get('merged_by', {}).get('id') == OWNER_ID
            and pr.get('base', {}).get('repo', {}).get('id') == REPOSITORY_ID
            and pr.get('head', {}).get('repo', {}).get('id') == REPOSITORY_ID
            and pr.get('base', {}).get('ref') == t['branch']
            and pr.get('head', {}).get('sha') == parents[1]['sha'], 'release_owner_merge_invalid')
    pr_source(t['branch'], pr['head']['ref'])
    # An actual merge must contain the reviewed source, with no promotion-only changes.
    git(repo, 'merge-base', '--is-ancestor', pr['head']['sha'], sha)
    if t['branch'] != 'develop':
        require(git(repo, 'rev-parse', sha + '^{tree}') ==
                git(repo, 'rev-parse', pr['head']['sha'] + '^{tree}'), 'promotion_tree_changed')
    result = api('/commits/' + sha + '/check-runs?filter=latest&per_page=100')
    require(result.get('total_count', 101) <= 100, 'required_ci_pagination_required')
    check_results(result.get('check_runs'))
    return dict(t, deployment_sha=sha, component_digest=manifest(repo, sha)['ingestion_support'],
                infrastructure={path: hashlib.sha256(git(repo, 'show', sha + ':' + path)).hexdigest() for path in INFRASTRUCTURE},
                pr_number=pr['number'])


def select_artifact(repo, sha, candidates):
    """A reusable image must bind the exact current component tree and an ancestor build."""
    component = manifest(repo, sha)['ingestion_support']
    for value in candidates:
        try:
            request(value)
            require(value['component_digest'] == component, 'artifact_component_changed')
            git(repo, 'merge-base', '--is-ancestor', value['build_sha'], sha)
            require(manifest(repo, value['build_sha'])['ingestion_support'] == component, 'artifact_source_changed')
            return value
        except (Rejected, KeyError, ValueError):
            continue
    return None


def make_request(admission, build_sha, image, run_id, now):
    return request(dict(schema=1, repository_id=REPOSITORY_ID,
        environment=admission['environment'], project_ref=admission['project_ref'], branch=admission['branch'],
        deployment_sha=admission['deployment_sha'], build_sha=revision(build_sha),
        component_digest=admission['component_digest'], infrastructure=admission['infrastructure'], image=image,
        run_id=int(run_id), issued_at=int(now), expires_at=int(now) + 900), now=now)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('operation', choices=('admit', 'request', 'public-config'))
    args = parser.parse_args()
    try:
        t = target(os.environ['GITHUB_REF'])
        if args.operation == 'admit':
            event = decoded(Path(os.environ['GITHUB_EVENT_PATH']).read_bytes())
            api = Github(os.environ['GH_TOKEN'])
            # Only read-only CI polling is retried; no deployment is attempted here.
            deadline = time.monotonic() + 300
            while True:
                try:
                    result = admit(os.environ['GITHUB_EVENT_NAME'], event, os.environ['GITHUB_REF'],
                                   os.environ['GITHUB_SHA'], api)
                    break
                except Rejected as error:
                    if str(error) not in ('required_ci_pending', 'required_ci_not_successful') or time.monotonic() >= deadline:
                        raise
                    time.sleep(5)
            result['project_ref'] = os.environ['SUPABASE_PROJECT_REF']
            from shared_contract import public_config
            public_config(t, result['project_ref'], os.environ['SUPABASE_PUBLIC_KEY'])
            Path('admission.json').write_bytes(encoded(result))
        elif args.operation == 'request':
            admission = decoded(Path('admission.json').read_bytes())
            result = make_request(admission, os.environ['BUILD_SHA'], os.environ['API_IMAGE'],
                                  os.environ['GITHUB_RUN_ID'], int(time.time()))
            Path('release.json').write_bytes(encoded(result))
        else:
            from shared_contract import public_config
            result = public_config(t, os.environ['SUPABASE_PROJECT_REF'], os.environ['SUPABASE_PUBLIC_KEY'])
            Path('public-defines.json').write_bytes(encoded(result))
        print(json.dumps({'state': 'validated', 'environment': t['environment']}))
        return 0
    except Exception:
        print('{"state":"failed","reason":"shared_release_validation_failed"}')
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
