"""Real GHCR response-shape regression; synthetic responses, no credentials/network."""
import hashlib
import io
import unittest
import urllib.error
from email.message import Message
from unittest.mock import patch

from contract import Rejected
from shared_artifacts import IMAGE, NoRedirect, http, select
from shared_contract import encoded


class Response(io.BytesIO):
    status = 200


class RegistryDownloadTests(unittest.TestCase):
    def setUp(self):
        self.config = encoded({'os': 'linux', 'architecture': 'arm64', 'config': {'Labels': {
            'org.opencontainers.image.revision': 'a' * 40, 'moneybowl.source_digest': 'b' * 64}}})
        self.digest = 'sha256:' + hashlib.sha256(self.config).hexdigest()
        self.url = 'https://ghcr.io/v2/' + IMAGE.removeprefix('ghcr.io/') + '/blobs/' + self.digest
        self.location = 'https://pkg-containers.githubusercontent.com/ghcr1/blobs/' + self.digest + '?sig=synthetic%2Bopaque'
        self.calls = []
        self.body = self.config
        self.second_error = None
        patch('shared_artifacts.urllib.request.build_opener', return_value=self).start()
        patch('shared_artifacts.git', return_value=b'').start()
        patch('contract.manifest', return_value={'ingestion_support': 'b' * 64}).start()
        self.addCleanup(patch.stopall)

    def redirect(self, url, code=307, locations=None):
        headers = Message()
        for location in ([self.location] if locations is None else locations):
            headers.add_header('Location', location)
        return urllib.error.HTTPError(url, code, 'synthetic', headers, None)

    def open(self, req, timeout):
        self.calls.append(req)
        self.assertEqual(timeout, 30)
        if '/token?' in req.full_url:
            return Response(encoded({'token': 'synthetic-registry-bearer'}))
        if '/manifests/' in req.full_url:
            return Response(encoded({'mediaType': 'application/vnd.oci.image.manifest.v1+json',
                                     'config': {'digest': self.digest}}))
        if req.full_url == self.url:
            raise self.redirect(req.full_url)
        if self.second_error:
            raise self.second_error
        return Response(self.body)

    def test_actual_307_config_download_full_selection_preserves_digest_and_strips_credentials(self):
        result = select({'deployment_sha': 'c' * 40, 'component_digest': 'b' * 64}, 'synthetic-token', 'synthetic-actor')
        self.assertFalse(result['build'])
        self.assertEqual(result['build_sha'], 'a' * 40)
        manifest = encoded({'mediaType': 'application/vnd.oci.image.manifest.v1+json', 'config': {'digest': self.digest}})
        self.assertEqual(result['image'], IMAGE + '@sha256:' + hashlib.sha256(manifest).hexdigest())
        self.assertEqual(self.calls[-2].get_header('Authorization'), 'Bearer synthetic-registry-bearer')
        self.assertEqual(self.calls[-1].full_url, self.location)
        self.assertEqual(self.calls[-1].header_items(), [])
        self.assertIsNone(NoRedirect().redirect_request(None, None, None, None, None, None))

    def test_untrusted_or_malformed_download_locations_rejected_before_request(self):
        for location in ('http://pkg-containers.githubusercontent.com/x', 'https://evil.invalid/x',
                         'https://pkg-containers.githubusercontent.com.evil.invalid/x',
                         'https://user@pkg-containers.githubusercontent.com/x',
                         'https://pkg-containers.githubusercontent.com:443/x',
                         'https://pkg-containers.githubusercontent.com/x#fragment',
                         '//pkg-containers.githubusercontent.com/x', self.location + '\n',
                         self.location + ' ', self.location + 'x' * 4096):
            with self.subTest(location=location):
                self.location = location
                self.calls = []
                with self.assertRaises(Rejected):
                    http(self.url, {'Authorization': 'Bearer synthetic'})
                self.assertEqual(len(self.calls), 1)

    def test_missing_or_duplicate_locations_rejected(self):
        for locations in ([], [self.location, self.location]):
            with self.subTest(locations=locations), patch.object(self, 'open', side_effect=self.redirect(self.url, locations=locations)):
                with self.assertRaises(Rejected): http(self.url, {})

    def test_token_manifest_other_package_and_other_status_redirects_rejected(self):
        for url in ('https://ghcr.io/token', 'https://ghcr.io/v2/' + IMAGE.removeprefix('ghcr.io/') + '/manifests/component-test',
                    self.url.replace('moneybowl-ingestion-dev', 'other-package')):
            with self.subTest(url=url), patch.object(self, 'open', side_effect=self.redirect(url)):
                with self.assertRaises(Rejected): http(url, {'Authorization': 'Bearer synthetic'})
        for code in (301, 302, 303, 308, 401, 403, 500):
            with self.subTest(code=code), patch.object(self, 'open', side_effect=self.redirect(self.url, code)):
                with self.assertRaises(Rejected): http(self.url, {})

    def test_second_redirect_or_download_failure_is_not_followed(self):
        for code in (301, 302, 307, 308, 403, 404, 500):
            self.calls = []
            self.second_error = self.redirect(self.location, code)
            with self.subTest(code=code), self.assertRaises(Rejected): http(self.url, {})
            self.assertEqual(len(self.calls), 2)

    def test_oversized_download_rejected(self):
        self.body = b'x' * (2 * 1024 * 1024 + 1)
        with self.assertRaisesRegex(Rejected, 'registry_response_oversized'): http(self.url, {})

    def test_direct_success_and_missing_tag_remain_compatible(self):
        with patch.object(self, 'open', return_value=Response(self.config)):
            self.assertEqual(http(self.url, {}), (200, self.config))
        with patch.object(self, 'open', side_effect=self.redirect(self.url, 404)):
            self.assertEqual(http(self.url, {}), (404, b''))

    def test_download_timeout_does_not_retry(self):
        self.second_error = TimeoutError()
        with self.assertRaises(TimeoutError): http(self.url, {})
        self.assertEqual(len(self.calls), 2)

    def test_corrupt_download_never_selects_image(self):
        self.body = self.config + b' '
        with self.assertRaisesRegex(Rejected, 'registry_config_changed'):
            select({'deployment_sha': 'c' * 40, 'component_digest': 'b' * 64}, 'synthetic', 'synthetic')
