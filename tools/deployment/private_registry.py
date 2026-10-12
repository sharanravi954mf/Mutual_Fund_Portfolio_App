"""Read-only private OCI verification. Local RepoDigests never prove publication."""
import base64
import json
import re
import urllib.error
import urllib.parse
import urllib.request

from contract import Rejected, require
from owner_common import sha256
from protected_io import protected, read_private

ACCEPT = ', '.join(('application/vnd.oci.image.index.v1+json',
                   'application/vnd.oci.image.manifest.v1+json',
                   'application/vnd.docker.distribution.manifest.list.v2+json',
                   'application/vnd.docker.distribution.manifest.v2+json'))
DIGEST = re.compile(r'sha256:[0-9a-f]{64}')


class Registry:
    def __init__(self, config, request=None):
        self.config = config
        policy = config.get('registry', {})
        repository = config.get('image_repository', '')
        require(re.fullmatch(r'[a-z0-9][a-z0-9.-]+/[a-z0-9]+(?:[._-][a-z0-9]+)*'
                             r'(?:/[a-z0-9]+(?:[._-][a-z0-9]+)*)*', repository)
                and 'example.invalid' not in repository and policy.get('private') is True
                and policy.get('approval') and policy.get('repository') == repository,
                'registry_not_commissioned')
        self.host, self.name = repository.split('/', 1)
        endpoint = urllib.parse.urlsplit(policy.get('token_endpoint', ''))
        require(endpoint.scheme == 'https' and endpoint.hostname and not endpoint.username
                and not endpoint.password and endpoint.port is None and not endpoint.query
                and not endpoint.fragment and policy.get('service') == self.host,
                'registry_auth_binding_invalid')
        self.endpoint = endpoint.geturl()
        allowed = policy.get('blob_redirect_hosts', [])
        require(isinstance(allowed, list) and len(allowed) == len(set(allowed))
                and all(isinstance(value, str) and re.fullmatch(r'[a-z0-9][a-z0-9.-]+', value)
                        for value in allowed), 'registry_auth_binding_invalid')
        self.request = request or self.http

    def http(self, url, headers, method='GET'):
        host = self.host
        repository = self.name
        allowed = self.config['registry'].get('blob_redirect_hosts', [])
        class BlobRedirect(urllib.request.HTTPRedirectHandler):
            def redirect_request(self, request, fp, code, message, response_headers, destination):
                source = urllib.parse.urlsplit(request.full_url)
                target = urllib.parse.urlsplit(destination)
                require(source.hostname == host and source.path.startswith('/v2/' + repository + '/blobs/')
                        and code in (302, 303, 307, 308) and target.scheme == 'https'
                        and target.hostname in allowed and not target.username and not target.password
                        and target.port is None and not target.fragment, 'registry_redirect_rejected')
                # Blob storage may use signed URLs. Never forward registry authentication.
                return urllib.request.Request(destination, headers={'Accept': ACCEPT}, method=method)
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), BlobRedirect())
        try:
            with opener.open(urllib.request.Request(url, headers=headers, method=method), timeout=15) as response:
                data = response.read(4 * 1024 * 1024 + 1)
                require(len(data) <= 4 * 1024 * 1024, 'registry_response_oversized')
                return response.status, data
        except urllib.error.HTTPError as error:
            return error.code, b''
        except Rejected:
            raise
        except Exception:
            raise Rejected('registry_unavailable') from None

    def credential(self):
        try:
            directory = protected(self.config['docker_config'], directory=True)
            auth = read_private(directory / 'config.json')
            require(set(auth) == {'auths'} and set(auth['auths']) == {self.host}
                    and set(auth['auths'][self.host]) == {'auth'}, 'registry_auth_scope_invalid')
            encoded = auth['auths'][self.host]['auth']
            decoded = base64.b64decode(encoded, validate=True).decode()
            username, separator, password = decoded.partition(':')
            require(username and separator and password and '\n' not in decoded,
                    'registry_credentials_missing')
            return encoded
        except (OSError, ValueError, KeyError, UnicodeError):
            raise Rejected('registry_credentials_missing') from None

    def token(self, credential=None):
        query = urllib.parse.urlencode({'service': self.host, 'scope': 'repository:' + self.name + ':pull'})
        headers = {} if credential is None else {'Authorization': 'Basic ' + credential}
        status, data = self.request(self.endpoint + '?' + query, headers)
        if credential is None and status in (401, 403):
            return None
        require(status == 200, 'registry_auth_failed')
        value = json.loads(data)
        token = value.get('token', value.get('access_token'))
        require(isinstance(token, str) and re.fullmatch(r'[A-Za-z0-9._~+/-]+=*', token), 'registry_auth_failed')
        return token

    def verify(self, proof):
        image = proof.get('image', '')
        require(image.startswith(self.config['image_repository'] + '@')
                and DIGEST.fullmatch(image.split('@')[-1]), 'registry_digest_missing')
        credential = self.credential()
        root = image.split('@')[1]
        url = 'https://' + self.host + '/v2/' + self.name + '/'
        anonymous = self.token()
        status, _ = self.request(url + 'manifests/' + root,
                                {'Accept': ACCEPT, **({'Authorization': 'Bearer ' + anonymous} if anonymous else {})})
        require(status in (401, 403, 404), 'registry_repository_not_private')
        token = self.token(credential)
        headers = {'Accept': ACCEPT, 'Authorization': 'Bearer ' + token}

        def fetch(kind, digest, size=None):
            require(DIGEST.fullmatch(digest), 'registry_digest_invalid')
            status, raw = self.request(url + kind + '/' + digest, headers)
            require(status == 200, 'registry_digest_unpublished')
            require('sha256:' + sha256(raw) == digest and (size is None or len(raw) == size),
                    'registry_content_mismatch')
            return json.loads(raw)

        manifest = fetch('manifests', root)
        if 'manifests' in manifest:
            matches = [item for item in manifest['manifests'] if
                       item.get('platform', {}).get('os') == 'linux' and
                       item.get('platform', {}).get('architecture') == 'arm64']
            require(len(matches) == 1, 'registry_platform_invalid')
            manifest = fetch('manifests', matches[0]['digest'], matches[0]['size'])
        descriptor = manifest['config']
        config = fetch('blobs', descriptor['digest'], descriptor['size'])
        require(manifest.get('schemaVersion') == 2 and isinstance(manifest.get('layers'), list)
                and 0 < len(manifest['layers']) <= 128, 'registry_layers_invalid')
        for layer in manifest['layers']:
            require(DIGEST.fullmatch(layer.get('digest', '')) and type(layer.get('size')) is int
                    and layer['size'] > 0, 'registry_layers_invalid')
            status, _ = self.request(url + 'blobs/' + layer['digest'], headers, method='HEAD')
            require(status == 200, 'registry_layer_unpublished')
        # Classic Docker IDs are config digests; containerd-backed Docker uses the OCI index ID.
        require(proof['image_id'] in (root, descriptor['digest']), 'registry_image_id_mismatch')
        runtime = config.get('config', {})
        require(config.get('architecture') == 'arm64' and config.get('os') == 'linux'
                and runtime.get('Labels', {}).get('org.opencontainers.image.revision') == proof['git_commit']
                and runtime.get('Labels', {}).get('moneybowl.source_digest') == proof['source_digest'],
                'registry_provenance_mismatch')
        from ingestion_owner import API_COMMAND
        require(runtime.get('Cmd') == API_COMMAND and not runtime.get('Entrypoint')
                and runtime.get('User') == '10001:10001', 'registry_runtime_invalid')
        return {'image': image, 'image_id': proof['image_id'], 'config_digest': descriptor['digest'],
                'git_commit': proof['git_commit'], 'source_digest': proof['source_digest'],
                'private': True, 'remote_verified': True}
