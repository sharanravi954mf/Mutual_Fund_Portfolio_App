"""Read-only private-registry selection. A component tag is a hint, never provenance."""
import base64
import hashlib
import json
import os
import re
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

from contract import Rejected, git, require, revision
from shared_contract import IMAGE, decoded, digest


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None  # Expose the response; never forward registry authentication.


def http(url, headers):
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
    def read(request):
        with opener.open(request, timeout=30) as response:
            raw = response.read(2 * 1024 * 1024 + 1)
            require(len(raw) <= 2 * 1024 * 1024, 'registry_response_oversized')
            return response.status, raw
    try:
        return read(urllib.request.Request(url, headers=headers))
    except urllib.error.HTTPError as error:
        if error.code == 404:
            return 404, b''
        blob_prefix = 'https://ghcr.io/v2/' + IMAGE.removeprefix('ghcr.io/') + '/blobs/'
        require(error.code == 307 and re.fullmatch(re.escape(blob_prefix)
                + r'sha256:[0-9a-f]{64}', url), 'registry_read_rejected')
        locations = error.headers.get_all('Location', [])
        require(len(locations) == 1 and 0 < len(locations[0]) <= 4096
                and re.fullmatch(r'[\x21-\x7e]+', locations[0]), 'registry_download_location_invalid')
        location = locations[0]
        parsed = urllib.parse.urlsplit(location)
        require(parsed.scheme == 'https' and parsed.netloc == 'pkg-containers.githubusercontent.com'
                and parsed.path.startswith('/') and not parsed.fragment, 'registry_download_location_invalid')
    # GHCR serves blobs through this documented GitHub content host. One GET only,
    # no registry/GitHub headers; select() still verifies the exact config digest.
    try:
        return read(urllib.request.Request(location, headers={}))
    except urllib.error.HTTPError:
        raise Rejected('registry_download_rejected') from None


def select(admission, token, actor, repo='.', transport=http):
    component = admission['component_digest']
    package = IMAGE.removeprefix('ghcr.io/')
    auth = base64.b64encode((actor + ':' + token).encode()).decode()
    status, raw = transport('https://ghcr.io/token?' + urllib.parse.urlencode(
        {'service': 'ghcr.io', 'scope': 'repository:' + package + ':pull'}), {'Authorization': 'Basic ' + auth})
    require(status == 200, 'registry_auth_failed')
    bearer = decoded(raw)['token']
    require(type(bearer) is str and bearer and '\n' not in bearer and '\r' not in bearer, 'registry_auth_failed')
    headers = {'Authorization': 'Bearer ' + bearer, 'Accept': 'application/vnd.oci.image.manifest.v1+json'}
    base = 'https://ghcr.io/v2/' + package + '/'
    status, raw = transport(base + 'manifests/component-' + component, headers)
    if status == 404:
        return {'build': True}
    require(status == 200, 'registry_manifest_failed')
    manifest_digest = 'sha256:' + hashlib.sha256(raw).hexdigest()
    value = decoded(raw)
    require(value.get('mediaType') == 'application/vnd.oci.image.manifest.v1+json', 'registry_manifest_invalid')
    config_digest = digest(value['config']['digest'])
    status, raw = transport(base + 'blobs/' + config_digest, headers)
    require(status == 200 and 'sha256:' + hashlib.sha256(raw).hexdigest() == config_digest, 'registry_config_changed')
    config = decoded(raw)
    labels = config.get('config', {}).get('Labels', {})
    build_sha = revision(labels.get('org.opencontainers.image.revision'))
    require(config.get('os') == 'linux' and config.get('architecture') == 'arm64'
            and labels.get('moneybowl.source_digest') == component, 'registry_component_changed')
    git(repo, 'merge-base', '--is-ancestor', build_sha, admission['deployment_sha'])
    from contract import manifest
    require(manifest(repo, build_sha)['ingestion_support'] == component, 'registry_source_changed')
    return {'build': False, 'image': IMAGE + '@' + manifest_digest, 'build_sha': build_sha}


def main():
    try:
        value = select(decoded(Path('admission.json').read_bytes()), os.environ['GH_TOKEN'], os.environ['GITHUB_ACTOR'])
        if not value['build']:
            from oci_delivery import private_package, http as publication_http
            private_package(value['image'].split('@', 1)[1], os.environ['GH_TOKEN'], publication_http)
        with open(os.environ['GITHUB_OUTPUT'], 'a') as out:
            for k, v in value.items():
                out.write(k + '=' + (str(v).lower() if type(v) is bool else v) + '\n')
        print(json.dumps({'state': 'build_required' if value['build'] else 'candidate_selected'}))
        return 0
    except Exception:
        print('{"state":"failed","reason":"artifact_selection_failed"}')
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
