"""Bounded OCI validation and digest-only publication; standalone publisher program.

The workflow embeds these exact reviewed bytes. It never checks out or executes
repository files in the credentialed job. No image is loaded or run here.
"""
import base64
import hashlib
import gzip
import io
import json
import os
import re
import tarfile
import urllib.parse
import urllib.request
from pathlib import Path

REPOSITORY = 'sharanravi954mf/Mutual_Fund_Portfolio_App'
IMAGE = 'ghcr.io/sharanravi954mf/moneybowl-ingestion-dev'
WORKFLOW = '.github/workflows/environment-promotion.yml'
PREDICATE = 'https://moneybowl.dev/attestations/api-publication/v1'
MAX_BYTES = 512 * 1024 * 1024
MAX_JSON = 1024 * 1024
MAX_UNPACKED = 2 * 1024 * 1024 * 1024
DIGEST = re.compile(r'sha256:[0-9a-f]{64}')
SHA = re.compile(r'[0-9a-f]{40}')
COMMAND = ['uvicorn', 'app.main:app', '--host', '0.0.0.0', '--port', '8080',
           '--no-access-log', '--workers', '1']
INDEX = 'application/vnd.oci.image.index.v1+json'
MANIFEST = 'application/vnd.oci.image.manifest.v1+json'
CONFIG = 'application/vnd.oci.image.config.v1+json'
LAYERS = {'application/vnd.oci.image.layer.v1.tar+gzip', 'application/vnd.oci.image.layer.v1.tar'}


class Invalid(ValueError):
    pass


def need(ok, code):
    if not ok:
        raise Invalid(code)


def digest(raw):
    return 'sha256:' + hashlib.sha256(raw).hexdigest()


def document(raw):
    need(0 < len(raw) <= MAX_JSON, 'oci_document_size')
    def unique(items):
        out = {}
        for k, v in items:
            need(k not in out, 'oci_duplicate_key')
            out[k] = v
        return out
    def invalid(_):
        raise Invalid('oci_json')
    value = json.loads(raw, object_pairs_hook=unique, parse_constant=invalid)
    need(type(value) is dict, 'oci_object')
    return value


def descriptor(value, media):
    need(type(value) is dict and set(value) <= {'mediaType', 'digest', 'size', 'platform', 'annotations'}
         and value.get('mediaType') in media and DIGEST.fullmatch(value.get('digest', ''))
         and type(value.get('size')) is int and 0 < value['size'] <= MAX_BYTES, 'oci_descriptor')
    if 'platform' in value:
        need(value['platform'] in ({'os': 'linux', 'architecture': 'arm64'},
                                  {'os': 'linux', 'architecture': 'arm64', 'variant': 'v8'}), 'oci_platform')
    return value


def check_layer(raw, media, budget):
    """Stream-check tar structure and expansion; never extract an image layer.

    Filesystem symlinks inside an OCI layer are normal image content. They are
    never followed on the publisher host. Layout/archive links remain forbidden.
    """
    if len(budget) == 1:
        budget.extend([0, 0])
    source = io.BytesIO(raw)
    stream = gzip.GzipFile(fileobj=source) if media.endswith('+gzip') else source
    class Bounded:
        def read(self, size):
            block = stream.read(min(size, 65536))
            budget[0] += len(block)
            need(budget[0] <= MAX_UNPACKED, 'oci_layer_expansion')
            return block
    try:
        with tarfile.open(fileobj=Bounded(), mode='r|') as tar:
            for member in tar:
                budget[1] += 1
                budget[2] += member.size
                need(budget[1] <= 50000 and budget[2] <= MAX_UNPACKED
                     and member.size <= MAX_UNPACKED, 'oci_layer_structure')
        # Drain gzip trailer/data too, so a second member or padding cannot evade
        # the same total expansion bound. No paths or file bytes are materialized.
        reader = Bounded()
        while reader.read(65536):
            pass
    except (tarfile.TarError, OSError, EOFError):
        raise Invalid('oci_layer_structure') from None
    finally:
        stream.close()


def validate(archive, sha, component):
    need(SHA.fullmatch(sha) and sha != '0' * 40 and re.fullmatch('[0-9a-f]{64}', component), 'oci_source')
    path = Path(archive)
    need(path.is_file() and not path.is_symlink() and path.resolve() == path.absolute()
         and path.stat().st_nlink == 1 and path.stat().st_size <= MAX_BYTES + 2 * MAX_JSON,
         'oci_archive_size')
    blobs, total = {}, 0
    with tarfile.open(path, 'r:') as tar:
        for member in tar:
            name = member.name
            need(name not in blobs and len(blobs) < 260 and not member.pax_headers and not member.sparse,
                 'oci_archive_duplicate_or_extended')
            if member.isdir():
                need(name in ('blobs', 'blobs/sha256') and name not in blobs, 'oci_archive_directory')
                blobs[name] = None
                continue
            need(member.isfile() and (name in ('oci-layout', 'index.json') or
                 re.fullmatch(r'blobs/sha256/[0-9a-f]{64}', name)), 'oci_archive_path_or_type')
            total += member.size
            need(0 < member.size <= MAX_BYTES and total <= MAX_BYTES, 'oci_archive_size')
            raw = tar.extractfile(member).read(member.size + 1)
            need(len(raw) == member.size, 'oci_archive_truncated')
            if name.startswith('blobs/'):
                need(digest(raw)[7:] == name.rsplit('/', 1)[1], 'oci_blob_digest')
            blobs[name] = raw
    need(document(blobs.get('oci-layout', b'')) == {'imageLayoutVersion': '1.0.0'}, 'oci_layout')
    index_raw = blobs.get('index.json', b'')
    index = document(index_raw)
    need(index.get('schemaVersion') == 2 and index.get('mediaType', INDEX) == INDEX
         and set(index) <= {'schemaVersion', 'mediaType', 'manifests', 'annotations'}
         and type(index.get('manifests')) is list and len(index['manifests']) == 1, 'oci_index')
    used = {'index.json', 'oci-layout', 'blobs', 'blobs/sha256'}
    def content(desc, media):
        descriptor(desc, media)
        name = 'blobs/sha256/' + desc['digest'][7:]
        raw = blobs.get(name)
        need(type(raw) is bytes and len(raw) == desc['size'] and digest(raw) == desc['digest'], 'oci_content')
        used.add(name)
        return raw
    platform = index['manifests'][0]
    manifest_raw = content(platform, {MANIFEST})
    image = document(manifest_raw)
    need(image.get('schemaVersion') == 2 and image.get('mediaType') == MANIFEST
         and set(image) <= {'schemaVersion', 'mediaType', 'config', 'layers', 'annotations'}
         and type(image.get('layers')) is list and 0 < len(image['layers']) <= 128, 'oci_manifest')
    config = document(content(image['config'], {CONFIG}))
    need(config.get('os') == 'linux' and config.get('architecture') == 'arm64', 'oci_platform')
    runtime = config.get('config', {})
    labels = runtime.get('Labels', {})
    need(labels.get('org.opencontainers.image.revision') == sha
         and labels.get('moneybowl.source_digest') == component, 'oci_source_metadata')
    need(runtime.get('User') == '10001:10001' and runtime.get('Cmd') == COMMAND
         and not runtime.get('Entrypoint') and runtime.get('WorkingDir') == '/app'
         and not any(runtime.get(k) for k in ('Volumes', 'OnBuild', 'Shell')), 'oci_runtime')
    allowed_env = {'PATH', 'LANG', 'GPG_KEY', 'PYTHON_VERSION', 'PYTHON_SHA256',
                   'PYTHONDONTWRITEBYTECODE', 'PYTHONUNBUFFERED', 'PIP_DISABLE_PIP_VERSION_CHECK', 'PIP_NO_CACHE_DIR'}
    env = runtime.get('Env', [])
    need(type(env) is list and len(env) <= len(allowed_env)
         and all(type(v) is str and len(v) <= 4096 and '=' in v and v.split('=', 1)[0] in allowed_env for v in env)
         and len({v.split('=', 1)[0] for v in env}) == len(env), 'oci_environment')
    budget = [0]
    for layer in image['layers']:
        check_layer(content(layer, LAYERS), layer['mediaType'], budget)
    need(set(blobs) <= used, 'oci_unreferenced_blob')
    return dict(index_digest=digest(index_raw), manifest_digest=platform['digest'],
                config_digest=image['config']['digest'], image=IMAGE + '@' + platform['digest'],
                git_commit=sha, build_source=sha, release_source=sha, source_digest=component,
                platform='linux/arm64'), blobs, image


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args):
        raise Invalid('publication_redirect')


def http(url, headers=None, method='GET', data=None):
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
    try:
        with opener.open(urllib.request.Request(url, headers=headers or {}, method=method, data=data), timeout=30) as r:
            raw = r.read(MAX_JSON + 1)
            need(len(raw) <= MAX_JSON, 'publication_response_size')
            return r.status, dict(r.headers), raw
    except urllib.error.HTTPError as e:
        return e.code, dict(e.headers), b''


def github(path, token, transport=http):
    status, _, raw = transport('https://api.github.com/repos/' + REPOSITORY + '/' + path,
        {'Authorization': 'Bearer ' + token, 'Accept': 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28'})
    need(status == 200, 'github_read_failed')
    return json.loads(raw)


def source_digest(sha, token, transport=http):
    tree = github('git/trees/' + sha + '?recursive=1', token, transport)
    need(tree.get('truncated') is False, 'github_tree_truncated')
    entries = []
    for e in tree['tree']:
        if e['path'].startswith('services/ingestion-support/') and e['type'] != 'tree':
            need(e['type'] == 'blob' and e['mode'] in ('100644', '100755'), 'source_links')
            entries.append(e)
    need(entries, 'source_missing')
    raw = ''.join(f"{e['mode']} {e['type']} {e['sha']}\t{e['path']}\n" for e in sorted(entries, key=lambda e: e['path']))
    return hashlib.sha256(raw.encode()).hexdigest()


def run_identity(run, sha, run_id, attempt):
    need(type(run_id) is int and run_id > 0 and type(attempt) is int and attempt > 0
         and run.get('id') == run_id and run.get('run_attempt') == attempt
         and run.get('event') == 'push' and run.get('head_branch') == 'develop'
         and run.get('head_sha') == sha and run.get('path') == WORKFLOW
         and run.get('repository', {}).get('full_name') == REPOSITORY
         and run.get('head_repository', {}).get('full_name') == REPOSITORY
         and not run.get('head_repository', {}).get('fork', True), 'github_run_identity')


def completed_jobs(value, names):
    need(type(value) is dict and type(value.get('jobs')) is list and value.get('total_count') == len(value['jobs'])
         and len(value['jobs']) <= 100, 'github_jobs_incomplete')
    for name, label in names.items():
        jobs = [j for j in value['jobs'] if j.get('name') == name]
        need(len(jobs) == 1 and jobs[0].get('status') == 'completed' and jobs[0].get('conclusion') == 'success'
             and label in jobs[0].get('labels', []), 'github_required_job')


def private_package(manifest_digest, token, transport):
    """Probe anonymous pull separately from authenticated package visibility.

    A challenge alone is normal for public GHCR images. An absent new digest
    cannot establish package privacy, so require package-scope evidence too.
    Challenge URLs are checked, never followed or given owner credentials.
    """
    host, package = IMAGE.split('/', 1)
    url = 'https://' + host + '/v2/' + package + '/manifests/' + manifest_digest
    headers = {'Accept': MANIFEST}
    status, response, _ = transport(url, headers)
    need(status != 200, 'publication_package_public')
    challenges = [v for k, v in response.items() if k.lower() == 'www-authenticate']
    need(status == 401 and len(challenges) == 1 and type(challenges[0]) is str
         and len(challenges[0]) <= 4096, 'publication_anonymous_unknown')
    challenge = challenges[0]
    need(re.fullmatch(r'Bearer\s+[a-z]+="[^"\r\n]*"(?:\s*,\s*[a-z]+="[^"\r\n]*")*', challenge),
         'publication_challenge_invalid')
    fields = re.findall(r'([a-z]+)="([^"\r\n]*)"', challenge)
    need(len(fields) == 3 and dict(fields) == {'realm': 'https://ghcr.io/token', 'service': host,
         'scope': 'repository:' + package + ':pull'}, 'publication_challenge_invalid')
    status, _, raw = transport('https://ghcr.io/token?' + urllib.parse.urlencode(
        {'service': host, 'scope': 'repository:' + package + ':pull'}), {})
    if status == 200:
        value = document(raw)
        anonymous = value.get('token', value.get('access_token'))
        need(type(anonymous) is str and 0 < len(anonymous) <= MAX_JSON
             and re.fullmatch(r'[A-Za-z0-9._~+/-]+=*', anonymous)
             and value.get('access_token', anonymous) == anonymous, 'publication_anonymous_unknown')
        headers['Authorization'] = 'Bearer ' + anonymous
    else:
        need(status in (401, 403), 'publication_anonymous_unknown')
    status, _, _ = transport(url, headers)
    need(status != 200, 'publication_package_public')
    need(status in (401, 403, 404), 'publication_anonymous_unknown')
    owner, name = package.split('/', 1)
    status, _, raw = transport('https://api.github.com/users/' + owner + '/packages/container/' + name,
        {'Authorization': 'Bearer ' + token, 'Accept': 'application/vnd.github+json',
         'X-GitHub-Api-Version': '2022-11-28'})
    need(status == 200, 'publication_package_visibility_unknown')
    metadata = document(raw)
    need(metadata.get('name') == name and metadata.get('package_type') == 'container'
         and metadata.get('owner', {}).get('login') == owner and metadata.get('visibility') == 'private',
         'publication_package_not_private')


def publish(archive, sha, run_id, attempt, token, transport=http):
    need(os.environ.get('M4_IMAGE_PUBLICATION_ENABLED') == 'owner-approved-v1', 'publication_disabled')
    run = github(f'actions/runs/{run_id}/attempts/{attempt}', token, transport)
    run_identity(run, sha, run_id, attempt)
    completed_jobs(github(f'actions/runs/{run_id}/attempts/{attempt}/jobs?per_page=100', token, transport),
                   {'M4 Required CI': 'ubuntu-latest', 'M4 Isolated ARM64 Build': 'ubuntu-24.04-arm'})
    component = source_digest(sha, token, transport)
    proof, blobs, image = validate(archive, sha, component)
    host, package = IMAGE.split('/', 1)
    base = 'https://' + host + '/v2/' + package + '/'
    private_package(proof['manifest_digest'], token, transport)
    auth = base64.b64encode((os.environ['GITHUB_ACTOR'] + ':' + token).encode()).decode()
    status, _, raw = transport('https://ghcr.io/token?' + urllib.parse.urlencode(
        {'service': 'ghcr.io', 'scope': 'repository:' + package + ':pull,push'}), {'Authorization': 'Basic ' + auth})
    need(status == 200, 'publication_auth')
    bearer = document(raw).get('token')
    need(type(bearer) is str and re.fullmatch(r'[A-Za-z0-9._~+/-]+=*', bearer), 'publication_auth')
    headers = {'Authorization': 'Bearer ' + bearer}
    for desc in [image['config'], *image['layers']]:
        status, _, _ = transport(base + 'blobs/' + desc['digest'], headers, 'HEAD')
        if status == 200:
            continue
        need(status == 404, 'publication_blob_read')
        status, response, _ = transport(base + 'blobs/uploads/', headers, 'POST', b'')
        location = urllib.parse.urljoin(base, response.get('Location', response.get('location', '')))
        parsed = urllib.parse.urlsplit(location)
        need(status == 202 and parsed.scheme == 'https' and parsed.netloc == host and not parsed.fragment
             and parsed.path.startswith('/v2/' + package + '/blobs/uploads/')
             and len(location) <= 4096, 'publication_upload_location')
        location += ('&' if parsed.query else '?') + urllib.parse.urlencode({'digest': desc['digest']})
        status, _, _ = transport(location, {**headers, 'Content-Type': 'application/octet-stream'}, 'PUT',
                                  blobs['blobs/sha256/' + desc['digest'][7:]])
        need(status == 201, 'publication_blob_write')
    raw = blobs['blobs/sha256/' + proof['manifest_digest'][7:]]
    status, _, _ = transport(base + 'manifests/' + proof['manifest_digest'],
                             {**headers, 'Content-Type': MANIFEST}, 'PUT', raw)
    need(status == 201, 'publication_manifest_write')
    status, _, remote = transport(base + 'manifests/' + proof['manifest_digest'], {**headers, 'Accept': MANIFEST})
    need(status == 200 and remote == raw, 'publication_remote_digest')
    return {**proof, 'repository': REPOSITORY, 'workflow': WORKFLOW, 'event': 'push',
            'ref': 'refs/heads/develop', 'run_id': run_id, 'run_attempt': attempt,
            'archive_digest': digest(Path(archive).read_bytes()), 'builder': 'github-hosted/ubuntu-24.04-arm'}


def main():
    # No arguments/dispatch-selected SHA. Platform context and owner gate only.
    proof = publish('incoming/api.oci.tar', os.environ['GITHUB_SHA'], int(os.environ['GITHUB_RUN_ID']),
                    int(os.environ['GITHUB_RUN_ATTEMPT']), os.environ['GH_TOKEN'])
    Path('predicate.json').write_text(json.dumps(proof, sort_keys=True) + '\n')
    with open(os.environ['GITHUB_OUTPUT'], 'a') as out:
        out.write('digest=' + proof['manifest_digest'] + '\n')


if __name__ == '__main__':
    main()
