"""Private DEV measurement transport: fixed read-only Management queries and readiness only.

No access to /secrets, deployment, migration writes or M2A lifecycle operations.
"""
import hashlib
import hmac
import json
import os
import re
import ssl
import tempfile
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path

from contract import Rejected, require
from observe import NoRedirect, Pending
from owner_common import Command, pinned_executable

MIGRATIONS = 'SELECT version, statements FROM supabase_migrations.schema_migrations ORDER BY version;'
CONTROL = """SELECT i.environment, i.project_ref, c.project_url, c.mode,
 (SELECT coalesce(jsonb_agg(jsonb_build_object('schedule',schedule,'command',command,
 'active',active,'database',database)), '[]'::jsonb) FROM cron.job
 WHERE jobname='moneybowl-outbox-recovery') AS jobs
 FROM moneybowl_dispatch.commission_identity i JOIN moneybowl_dispatch.control c USING(singleton)
 WHERE i.singleton AND c.environment=i.environment;"""


class SupabaseReader:
    def __init__(self, config, token, readiness_key, request=None, command=None):
        self.project = config['project_ref']
        require(re.fullmatch('[a-z]{20}', self.project), 'invalid_project')
        require(isinstance(token, str) and token and '\n' not in token and '\r' not in token, 'measurement_token_missing')
        require(isinstance(readiness_key, str) and re.fullmatch(r'[\x21-\x7e]{32,4096}', readiness_key),
                'readiness_only_capability_missing')
        self.token, self.key = token, readiness_key
        self.cli = pinned_executable(config, 'supabase_cli') if command is None else '/opt/supabase'
        self.command = command
        self.request = request or self._request

    def _request(self, url, body=None, headers=None):
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
        try:
            request = urllib.request.Request(url, data=None if body is None else json.dumps(body).encode(),
                                             headers=headers or {})
            with opener.open(request, timeout=30) as response:
                data = response.read(16 * 1024 * 1024 + 1)
                require(len(data) <= 16 * 1024 * 1024, 'measurement_too_large')
                return json.loads(data)
        except urllib.error.HTTPError as error:
            if error.code in (404, 408, 429, 500, 502, 503, 504):
                raise Pending('measurement_unavailable') from None
            raise Rejected('measurement_http_rejected') from None
        except urllib.error.URLError as error:
            if isinstance(error.reason, ssl.SSLError):
                raise Rejected('evidence_tls_rejected') from None
            raise Pending('transient_read_failed') from None
        except TimeoutError:
            raise Pending('measurement_unavailable') from None
        except (ValueError, UnicodeError):
            raise Rejected('measurement_malformed') from None

    def api(self, path, query=None):
        require((path == '/database/query/read-only' and query in (MIGRATIONS, CONTROL))
                or (path == '/functions' and query is None), 'measurement_operation_forbidden')
        return self.request('https://api.supabase.com/v1/projects/' + self.project + path,
                            None if query is None else {'query': query},
                            {'Authorization': 'Bearer ' + self.token, 'Content-Type': 'application/json'})

    def migrations(self):
        return self.api('/database/query/read-only', MIGRATIONS)

    def control(self):
        rows = self.api('/database/query/read-only', CONTROL)
        require(isinstance(rows, list) and len(rows) == 1, 'project_binding_unmeasured')
        return rows[0]

    def functions(self):
        return self.api('/functions')

    def files(self, slug):
        require(re.fullmatch('[a-z0-9-]+', slug), 'invalid_function_slug')
        with tempfile.TemporaryDirectory(prefix='m4-function-download-') as tmp:
            # CLI receives only its private project-scoped read capability, no worker/database keys.
            command = self.command or Command({'SUPABASE_ACCESS_TOKEN': self.token, 'HOME': tmp})
            command([self.cli, 'functions', 'download', slug, '--project-ref', self.project,
                     '--use-api', '--workdir', tmp], timeout=120)
            root = Path(tmp) / 'supabase/functions'
            require(root.is_dir(), 'function_export_unverifiable')
            result = {}
            total = 0
            for path in root.rglob('*'):
                require(not path.is_symlink(), 'function_export_link_rejected')
                if path.is_file():
                    data = path.read_bytes()
                    total += len(data)
                    require(total <= 16 * 1024 * 1024, 'function_export_oversized')
                    result[path.relative_to(root).as_posix()] = data
            require(result, 'function_export_unverifiable')
            return result

    def readiness(self, environment):
        require(environment in ('DEV', 'QA'), 'invalid_environment')
        origin = 'https://' + self.project + '.supabase.co'
        payload = dict(version=1, request_id=str(uuid.uuid4()), issued_at=int(time.time()),
                       environment=environment, project_url=origin, kind='readiness',
                       event_outbox_id=None, hop=0)
        message = 'moneybowl-readiness-v1|' + '|'.join(str(payload[name]) for name in ('version', 'request_id', 'issued_at',
                            'environment', 'project_url', 'kind')) + '|-|0'
        signature = hmac.new(self.key.encode(), message.encode(), hashlib.sha256).hexdigest()
        return self.request(origin + '/functions/v1/outbox-dispatcher/readiness', payload,
                            {'Content-Type': 'application/json', 'x-outbox-readiness-signature': signature})
