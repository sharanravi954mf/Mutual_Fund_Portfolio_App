#!/usr/bin/env python3
"""Private project-admin CLI. No credentials in arguments, output, SQL or GitHub CI."""
import argparse
import datetime as dt
import json
import os
from pathlib import Path
import re
import sys
import subprocess
import time
import urllib.error
import urllib.request
import uuid

ROOT = Path(__file__).resolve().parents[2]
OPERATIONS = ('bootstrap', 'preflight', 'observe', 'schedule', 'eligibility', 'activate', 'verify', 'rollback')


class Failure(Exception):
    pass


def require(value, code):
    if not value:
        raise Failure(code)


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        raise Failure('management_redirect_rejected')


class Admin:
    def __init__(self, project, token):
        require(bool(token) and '\n' not in token and '\r' not in token, 'admin_credential_missing')
        require(re.fullmatch('[a-z0-9]{20}', project), 'project_invalid')
        self.base = 'https://api.supabase.com/v1/projects/' + project
        self.token = token
        # Do not send administrator credentials through inherited proxy settings.
        self.opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())

    def call(self, path, body=None):
        require(path in ('/database/query', '/secrets'), 'management_path_invalid')
        request = urllib.request.Request(self.base + path,
            data=None if body is None else json.dumps(body).encode(),
            headers={'Authorization': 'Bearer ' + self.token, 'Content-Type': 'application/json'})
        try:
            with self.opener.open(request, timeout=30) as response:
                data = response.read(131073)
                require(len(data) <= 131072, 'management_response_oversized')
                return json.loads(data) if data else None
        except urllib.error.HTTPError as error:
            raise Failure('management_http_' + str(error.code)) from None
        except (OSError, ValueError):
            raise Failure('management_unavailable') from None

    def sql(self, expression):
        rows = self.call('/database/query', {'query': 'SELECT ' + expression + ' AS result;'})
        require(isinstance(rows, list) and len(rows) == 1 and 'result' in rows[0], 'database_response_invalid')
        return rows[0]['result']

    def mode(self, mode, config=None):
        require(mode in ('disabled', 'observe', 'active'), 'mode_invalid')
        values = {'OUTBOX_DISPATCH_MODE': mode}
        if config:
            values.update(MONEYBOWL_ENV=config['environment'], MONEYBOWL_SUPABASE_URL=config['project_url'])
        self.call('/secrets', [{'name': k, 'value': v} for k, v in values.items()])

    def secret_names(self):
        # Management API returns metadata/digests, never requests reveal=true.
        rows = self.call('/secrets')
        require(isinstance(rows, list), 'secret_metadata_invalid')
        return {r['name'] for r in rows}


def literal(value):
    # SQL is transported as JSON, never shell code. No secret is a SQL argument.
    return "'" + str(value).replace("'", "''") + "'"


class Controller:
    def __init__(self, config, admin, sleep=time.sleep):
        require(set(config) == {'environment', 'project_ref', 'project_url', 'revision', 'actor', 'ticket'}, 'config_fields_invalid')
        require(config['environment'] in ('DEV', 'QA', 'PROD'), 'environment_invalid')
        require(re.fullmatch('[a-z0-9]{20}', config['project_ref']), 'project_invalid')
        require(config['project_url'] == 'https://' + config['project_ref'] + '.supabase.co', 'project_binding_invalid')
        require(re.fullmatch('[a-f0-9]{40}', config['revision']), 'revision_invalid')
        require(re.fullmatch('[A-Za-z0-9_.@ -]{1,100}', config['actor']), 'actor_invalid')
        require(re.fullmatch('[A-Za-z0-9_.:/-]{1,200}', config['ticket']), 'ticket_invalid')
        self.config, self.admin, self.sleep = config, admin, sleep
        self.routes = {k: v['worker_slug'] for k, v in json.loads((ROOT / 'services/outbox-dispatcher/routes.json').read_text()).items()}

    def db(self, action, **extra):
        args = {**self.config, "id": str(uuid.uuid4()), **extra}
        return self.admin.sql('moneybowl_dispatch.commission(' + literal(action) + ',' + literal(json.dumps(args)) + '::jsonb)')

    def status(self):
        return self.db('status')

    def result(self, request_id):
        require(type(request_id) is int and request_id > 0, 'probe_id_invalid')
        for _ in range(20):
            result = self.admin.sql(f'moneybowl_dispatch.commission_result({request_id})')
            if result.get('pending') is True:
                self.sleep(1)
                continue
            require(not result.get('failed'), 'probe_failed')
            return result
        raise Failure('probe_timeout')

    def probe(self, kind='readiness', replay=None):
        require(kind in ('readiness', 'recovery'), 'probe_kind_invalid')
        require(replay is None or type(replay) is int, 'probe_id_invalid')
        request_id = self.admin.sql('moneybowl_dispatch.commission_probe(' + literal(kind) + ',' + ('NULL' if replay is None else str(replay)) + ')')
        return request_id, self.result(request_id)

    def readiness(self, mode=None):
        request_id, result = self.probe()
        require(result.get('status') == 200 and result.get('code') == 'outbox_ready', 'edge_not_ready')
        require(result.get('environment') == self.config['environment'] and result.get('project_url') == self.config['project_url'], 'edge_binding_invalid')
        require(result.get('routes') == self.routes, 'edge_routes_invalid')
        require(result.get('mode') in ('disabled', 'observe', 'active'), 'edge_mode_invalid')
        if mode is not None:
            require(result['mode'] == mode, 'edge_mode_mismatch')
        return request_id, result

    def preflight(self):
        s = self.status()
        require(s.get('environment') == self.config['environment'] and s.get('project_ref') == self.config['project_ref'] and s.get('binding_matches'), 'database_binding_invalid')
        require(s.get('key_present') and s.get('extensions_ready'), 'database_not_ready')
        require({'OUTBOX_NOTIFICATION_KEY', 'NSE_WORKER_TOKEN'} <= self.admin.secret_names(), 'edge_secret_missing')
        self.readiness()
        return s

    def rollback(self):
        # A separate committed API request disables DB and Cron BEFORE touching Edge.
        s = self.db('rollback')
        require(s['mode'] == 'disabled' and not s['schedule_active'], 'rollback_database_failed')
        self.admin.mode('disabled')
        self.readiness('disabled')
        s = self.status()
        return dict(s, oracle_restart_safe=s['mode'] == 'disabled' and not s['schedule_active'] and s['inflight'] == 0)

    def eligibility(self):
        s = self.preflight()
        require(self.config['environment'] == 'DEV', 'activation_dev_only')
        require(s['mode'] != 'active' and s['inflight'] == 0, 'activation_inflight_or_active')
        require(s['schedule_ready'] and s['schedule_count'] == 1, 'schedule_not_ready')
        stamp = s.get('last_observe')
        require(stamp is not None and dt.datetime.fromisoformat(stamp.replace('Z', '+00:00')) > dt.datetime.now(dt.timezone.utc) - dt.timedelta(minutes=15), 'observe_stale')
        return s

    def run(self, operation, approval=None):
        require(operation in OPERATIONS, 'operation_invalid')
        if operation == 'bootstrap':
            require(self.status()['mode'] == 'disabled', 'bootstrap_disabled_required')
            require({'OUTBOX_NOTIFICATION_KEY', 'NSE_WORKER_TOKEN'} <= self.admin.secret_names(), 'edge_secret_missing')
            self.admin.mode('disabled', self.config)
            self.db('bind')
            return self.preflight()
        if operation == 'preflight':
            return self.preflight()
        if operation == 'rollback':
            return self.rollback()
        if operation == 'schedule':
            self.preflight()
            return self.db('schedule')
        if operation == 'eligibility':
            return self.eligibility()
        if operation == 'observe':
            require(self.preflight()['mode'] != 'active', 'observe_active_conflict')
            try:
                self.admin.mode('observe')
                proof, _ = self.readiness('observe')
                self.db('observe', probe_id=proof)
                request_id, response = self.probe('recovery')
                require(response['status'] == 200 and response['code'] == 'outbox_processed', 'observe_failed')
                replay_id, replay = self.probe('recovery', request_id)
                require(replay['code'] == 'outbox_replay' and replay['status'] == 202, 'replay_failed')
                return self.db('record_observe', probe_id=request_id, replay_id=replay_id)
            except Exception:
                # Fail closed even if the initiating call timed out after being committed.
                self.db('rollback')
                raise
        if operation == 'verify':
            s = self.preflight()
            self.readiness('active')
            require(self.config['environment'] == 'DEV' and s['mode'] == 'active' and s['schedule_active'] and s['schedule_ready'] and s['schedule_count'] == 1, 'active_verification_failed')
            return dict(s, active_configuration_verified=True, business_processing_verified=False)
        # Activation is never called from migrations, CI or normal deployment.
        require(self.config['environment'] == 'DEV', 'activation_dev_only')
        required = {'id', 'environment', 'project_ref', 'revision', 'actor', 'ticket', 'expires_at', 'oracle_retired', 'backlog_authorized'}
        require(isinstance(approval, dict) and set(approval) == required, 'approval_fields_invalid')
        require(all(approval[k] == self.config[k] for k in ('environment', 'project_ref', 'revision', 'actor', 'ticket')), 'approval_binding_invalid')
        require(str(uuid.UUID(approval['id'])) == approval['id'], 'approval_id_invalid')
        expiry = dt.datetime.fromisoformat(approval['expires_at'].replace('Z', '+00:00'))
        now = dt.datetime.now(dt.timezone.utc)
        require(now < expiry <= now + dt.timedelta(minutes=15) and approval['oracle_retired'] is True and approval['backlog_authorized'] is True, 'approval_invalid')
        # A rerun of the same committed activation can verify without deactivating.
        if self.status()['mode'] == 'active':
            self.db('activate', **approval)
            return self.run('verify')
        self.eligibility()
        try:
            self.db('rollback')
            self.admin.mode('active')
            proof, _ = self.readiness('active')
            self.db('activate', **approval, probe_id=proof)
            return self.run('verify')
        except Exception:
            self.db('rollback')
            # Do not re-enable Oracle, even if management of Edge is unavailable.
            try:
                self.admin.mode('disabled')
            except Exception:
                pass
            raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('operation', choices=OPERATIONS)
    parser.add_argument('--config', type=Path, required=True)
    parser.add_argument('--approval', type=Path)
    args = parser.parse_args()
    try:
        config = json.loads(args.config.read_text())
        approval = None
        if args.approval:
            require(args.operation == 'activate' and args.approval.stat().st_mode & 0o077 == 0, 'approval_permissions_invalid')
            approval = json.loads(args.approval.read_text())
        # Validate before opening an authenticated connection.
        controller = Controller(config, None)
        head = subprocess.run(['git', '-C', str(ROOT), 'rev-parse', 'HEAD'], capture_output=True, text=True, check=True).stdout.strip()
        require(head == config['revision'], 'checkout_revision_mismatch')
        clean = subprocess.run(['git', '-C', str(ROOT), 'status', '--porcelain'], capture_output=True, text=True, check=True).stdout
        require(not clean, 'checkout_dirty')
        controller.admin = Admin(config['project_ref'], os.environ.get('MONEYBOWL_COMMISSION_TOKEN', ''))
        result = controller.run(args.operation, approval)
        print(json.dumps({'operation': args.operation, 'result': result}, sort_keys=True))
        return 0
    except Failure as error:
        print(json.dumps({'error': str(error)}))
    except Exception:
        print(json.dumps({'error': 'commission_failed'}))
    return 1


if __name__ == '__main__':
    sys.exit(main())
