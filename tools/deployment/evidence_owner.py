"""Independently compare measured deployment state to approved Git, then publish sanitized proof."""
import argparse
import json
import os
import posixpath
import re
import time
import tomllib
from pathlib import Path

from contract import REPOSITORY, Rejected, git, load_policy, manifest, require, revision
from observe import Pending, ancestor, identity, observe, read_json, verify_receipt
from owner_common import sha256, atomic_json, binding, envelope, latest, lock, private_config, source_tree
from supabase_reader import SupabaseReader


def sql_tokens(text):
    """Conservative lexer: ignore comments, whitespace and statement separators, never literals.

No SQL is executed. Dollar bodies and quoted identifiers remain byte-exact. Unsupported
or incomplete quoting fails instead of repairing an unverifiable migration history.
"""
    tokens = []
    i = 0
    while i < len(text):
        if text[i].isspace() or text[i] == ';':
            i += 1
        elif text.startswith('--', i):
            end = text.find('\n', i)
            i = len(text) if end < 0 else end + 1
        elif text.startswith('/*', i):
            depth = 1; i += 2
            while i < len(text) and depth:
                if text.startswith('/*', i): depth += 1; i += 2
                elif text.startswith('*/', i): depth -= 1; i += 2
                else: i += 1
            require(depth == 0, 'migration_statement_unverifiable')
        elif text[i] in "'\"":
            start = i; quote = text[i]; i += 1
            closed = False
            while i < len(text):
                if text[i] == '\\': i += 2
                elif text[i] == quote:
                    i += 1
                    if i < len(text) and text[i] == quote: i += 1
                    else: closed = True; break
                else: i += 1
            require(closed, 'migration_statement_unverifiable')
            tokens.append(text[start:i])
        else:
            dollar = re.match(r'\$(?:[A-Za-z_][A-Za-z_0-9]*)?\$', text[i:])
            if dollar:
                delimiter = dollar[0]; end = text.find(delimiter, i + len(delimiter))
                require(end >= 0, 'migration_statement_unverifiable')
                end += len(delimiter); tokens.append(text[i:end]); i = end
            else:
                token = re.match(r'[A-Za-z_0-9]+|.', text[i:], re.S)[0]
                tokens.append(token); i += len(token)
    return tokens


def verify_migrations(source, rows):
    require(isinstance(rows, list), 'migration_measurement_malformed')
    actual = {}
    for row in rows:
        require(isinstance(row, dict) and re.fullmatch('[0-9]+', row.get('version', ''))
                and row['version'] not in actual, 'migration_measurement_malformed')
        statements = row.get('statements')
        require(isinstance(statements, list) and statements and all(isinstance(s, str) for s in statements),
                'migration_statements_unavailable')
        actual[row['version']] = sql_tokens(';\n'.join(statements))
    expected = {}
    for path in (source / 'supabase/migrations').glob('*.sql'):
        version = path.name.split('_', 1)[0]
        require(version not in expected, 'migration_source_duplicate')
        expected[version] = sql_tokens(path.read_text())
    require(expected and not (actual.keys() - expected.keys()), 'unexpected_applied_migration')
    for version, statements in actual.items():
        require(statements == expected[version], 'applied_migration_content_mismatch')
    return actual.keys() == expected.keys()


def function_index(rows):
    require(isinstance(rows, list), 'function_measurement_malformed')
    result = {}
    for row in rows:
        require(isinstance(row, dict) and isinstance(row.get('slug'), str) and row['slug'] not in result,
                'function_measurement_malformed')
        require(type(row.get('version')) is int and row['version'] > 0 and row.get('id'), 'function_revision_unverifiable')
        result[row['slug']] = {key: row.get(key) for key in ('id', 'version', 'status', 'verify_jwt', 'ezbr_sha256')}
    return result


def module_specifiers(text):
    """Extract supported module references without matching SQL/property names or prose.

    This is deliberately conservative, not a JavaScript compiler. Escaped module names,
    computed imports and imports inside template expressions need a reviewed exporter.
    They cannot be silently omitted from deployment evidence.
    """
    tokens = []
    pattern = re.compile(r'''\s+|//[^\n]*|/\*[\s\S]*?\*/|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|`(?:\\.|[^`\\])*`|[A-Za-z_$][\w$]*|.''', re.S)
    for match in pattern.finditer(text):
        value = match[0]
        if value.isspace() or value.startswith(('//', '/*')):
            continue
        if value.startswith('`'):
            require(not re.search(r'\bimport\b', value), 'dynamic_import_unverifiable')
        tokens.append(value)
    result = []
    def literal(value):
        require(len(value) >= 2 and value[0] in "\"'" and value[-1] == value[0]
                and '\\' not in value, 'dynamic_import_unverifiable')
        result.append(value[1:-1])
    for i, token in enumerate(tokens):
        if token not in ('import', 'export') or (i and tokens[i - 1] == '.'):
            continue
        tail = tokens[i + 1:]
        require(tail, 'module_syntax_unverifiable')
        if token == 'import' and tail[0] == '.':  # import.meta is not a module load
            continue
        if token == 'import' and tail[0] == '(':
            require(len(tail) >= 3 and tail[2] == ')', 'dynamic_import_unverifiable')
            literal(tail[1]); continue
        if token == 'import' and tail[0].startswith(('"', "'")):
            literal(tail[0]); continue
        if token == 'export' and tail[0] not in ('{', '*', 'type'):
            continue
        # Named/default imports or re-exports. Stop at a statement boundary.
        for j, value in enumerate(tail):
            if value == ';':
                break
            if value == 'from':
                require(j + 1 < len(tail), 'module_syntax_unverifiable')
                literal(tail[j + 1]); break
            if value == '}' and (j + 1 == len(tail) or tail[j + 1] != 'from'):
                break
    return result


def verify_files(source, slug, files):
    root = source / 'supabase/functions'
    require(isinstance(files, dict) and slug + '/index.ts' in files, 'function_export_unverifiable')
    for name, data in files.items():
        require(isinstance(name, str) and not name.startswith('/') and '\\' not in name
                and posixpath.normpath(name) == name and '..' not in name.split('/'), 'unsafe_function_export_path')
        path = root / name
        require(path.is_file() and path.read_bytes() == data, 'deployed_function_content_mismatch')
    # Require exported relative dependencies, not just the entrypoint or an arbitrary subset.
    visited = set()
    def walk(name):
        if name in visited:
            return
        visited.add(name)
        require(name in files, 'function_dependency_unmeasured')
        if not name.endswith(('.ts', '.js', '.mjs')):
            return
        text = files[name].decode()
        for specifier in module_specifiers(text):
            if specifier.startswith('.'):
                dependency = posixpath.normpath(posixpath.join(posixpath.dirname(name), specifier))
                require(not dependency.startswith('../'), 'function_dependency_outside_source')
                walk(dependency)
            else:
                require(specifier.startswith(('https://', 'npm:', 'node:', 'jsr:')), 'unresolved_import_map')
    walk(slug + '/index.ts')


def dispatcher_measurement(source, control, readiness, env, p):
    require(control.get('environment') == env.upper() and control.get('project_ref') == p['project_ref']
            and control.get('project_url') == 'https://' + p['project_ref'] + '.supabase.co', 'measured_project_mismatch')
    routes = {name: value['worker_slug'] for name, value in json.loads((source / 'services/outbox-dispatcher/routes.json').read_text()).items()}
    require(len(routes) == 17 and readiness.get('code') == 'outbox_ready'
            and readiness.get('environment') == env.upper() and readiness.get('project_url') == control['project_url']
            and readiness.get('routes') == routes, 'readiness_unverifiable')
    mode = 'active' if env == 'dev' else 'disabled'
    require(control.get('mode') == readiness.get('mode') == mode, 'dispatcher_mode_changed')
    jobs = control.get('jobs')
    require(isinstance(jobs, list) and len(jobs) == 1, 'recovery_cron_count_invalid')
    job = jobs[0]
    require(job.get('schedule') == '*/15 * * * *' and job.get('command') == 'SELECT moneybowl_dispatch.notify(NULL,0);'
            and job.get('database') == 'postgres' and job.get('active') is (env == 'dev'), 'recovery_cron_changed')
    return dict(mode=mode, cron_count=1, cron_schedule=job['schedule'], cron_active=job['active'],
                route_count=len(routes), readiness_authenticated=True)


def measure(repo, sha, env, policy, reader, service_read, latest_head, now=time.time):
    p = policy[env]
    expected = manifest(repo, sha)
    require(latest_head() == sha, 'source_superseded')
    with source_tree(repo, sha) as source:
        rows = reader.migrations()
        migrations_ready = verify_migrations(source, rows)
        before = function_index(reader.functions())
        declared = tomllib.loads((source / 'supabase/config.toml').read_text())['functions']
        require(declared and not (before.keys() - declared.keys()), 'unexpected_deployed_function')
        functions_ready = True
        for slug, config in declared.items():
            require(re.fullmatch('[a-z0-9-]+', slug) and config.get('enabled', True) is True
                    and 'entrypoint' not in config and 'import_map' not in config, 'unsupported_function_configuration')
            if slug not in before:
                functions_ready = False
                continue
            meta = before[slug]
            require(meta['status'] in ('ACTIVE', 'DEPLOYING'), 'function_deployment_failed')
            if meta['status'] == 'DEPLOYING':
                functions_ready = False
                continue
            require(meta['verify_jwt'] is config.get('verify_jwt', True), 'function_configuration_mismatch')
            verify_files(source, slug, reader.files(slug))
        # Snapshot stability: no PASS while either independent backend owner moves.
        require(function_index(reader.functions()) == before, 'function_measurement_changed')
        require(reader.migrations() == rows, 'migration_measurement_changed')
        control = reader.control()
        dispatcher = dispatcher_measurement(source, control, reader.readiness(env.upper()), env, p)
        require(reader.control() == control, 'dispatcher_measurement_changed')
        components = {
            'migrations': {'state': 'deployed', 'healthy': True, 'source_digest': expected['migrations'], 'proof': 'applied_history'} if migrations_ready else {'state': 'pending'},
            'edge_functions': {'state': 'deployed', 'healthy': True, 'source_digest': expected['edge_functions'], 'proof': 'downloaded_bundle'} if functions_ready else {'state': 'pending'},
        }
        try:
            service = service_read(sha)
            identity(service, env, sha, policy)
            require(service.get('state') != 'failed', 'service_owner_reported_failure')
            stamp = service.get('observed_at')
            require(type(stamp) in (int, float) and 0 <= now() - stamp <= 300, 'service_measurement_expired')
            require(service.get('oracle_dispatcher') == 'retired', 'legacy_dispatcher_not_retired')
            component = service.get('component', {})
            require(component == {'state': 'deployed', 'healthy': True, 'source_digest': expected['ingestion_support'], 'proof': 'running_image'}, 'service_measurement_unverifiable')
            require(re.fullmatch(r'sha256:[0-9a-f]{64}', service.get('image_id', '')) and
                    re.fullmatch(r'[a-z0-9][a-z0-9./_-]+@sha256:[0-9a-f]{64}', service.get('image', '')), 'service_image_unverifiable')
            components['ingestion_support'] = component
        except Pending:
            # Retirement must be measured, even while a service is unavailable. Do not invent it.
            raise Pending('service_measurement_pending') from None
        require(latest_head() == sha, 'source_superseded')
        result = {**envelope(env, p, sha), 'observed_at': now(), 'financial_policy': p['financial_policy'],
                  'nse_origin': p['nse_origin'], 'oracle_dispatcher': service['oracle_dispatcher'],
                  'dispatcher': dispatcher, 'components': components,
                  'measurement_digest': sha256(json.dumps({'migrations': rows, 'functions': before}, sort_keys=True).encode())}
        # NSE origin follows from exact deployed dispatcher config/runtime source + authenticated readiness.
        try:
            verify_receipt(result, env, sha, expected, policy, now())
        except Pending:
            pass
        return result


def produce(config, policy, reader, service_read, head, now=time.time):
    env, p = binding(config, policy)
    with lock(config['state_root']):
        sha = revision(head())
        path = Path(config['report_root']) / (sha + '.json')
        path.unlink(missing_ok=True)
        if config.get('release_status_root'):
            (Path(config['release_status_root']) / (sha + '.json')).unlink(missing_ok=True)
        try:
            result = measure(config['repository'], sha, env, policy, reader, service_read, head, now)
            if head() != sha:
                return {'state': 'superseded', 'git_commit': sha}
            atomic_json(path, result)
            state = 'measured' if all(c['state'] == 'deployed' for c in result['components'].values()) else 'pending'
            return {'state': state, 'git_commit': sha}
        except Pending:
            return {'state': 'pending', 'git_commit': sha}
        except Rejected as error:
            if str(error) == 'source_superseded':
                return {'state': 'superseded', 'git_commit': sha}
            atomic_json(path, {**envelope(env, p, sha), 'state': 'failed', 'reason': 'backend_measurement_failed'})
            raise
        except Exception:
            atomic_json(path, {**envelope(env, p, sha), 'state': 'failed', 'reason': 'backend_measurement_failed'})
            raise Rejected('measurement_malformed') from None


def publish_release(config, policy, sha, head, read=read_json, asset_reader=None):
    """Recurring independent full-release verification; does not claim a GitHub CI result."""
    env, p = binding(config, policy)
    event = {'repository': {'full_name': REPOSITORY}, 'ref': 'refs/heads/' + p['branch'],
             'after': sha, 'forced': False, 'deleted': False}
    receipt_url = 'https://private-owner.invalid/receipts/' + sha + '.json'
    def read_evidence(url):
        if url == receipt_url:
            return json.loads((Path(config['report_root']) / (sha + '.json')).read_text())
        return read(url)
    extra = {} if asset_reader is None else {'read_asset': asset_reader}
    result = observe(event, env, policy, manifest(config['repository'], sha), head, read_evidence,
                     config['frontend_origin'], 'https://private-owner.invalid/receipts', attempts=1,
                     is_ancestor=lambda old, new: ancestor(config['repository'], old, new), **extra)
    atomic_json(Path(config['release_status_root']) / (sha + '.json'), result)
    return result


def owner_cycle(config, policy, reader, service_read, head):
    binding(config, policy)
    # Serialize measurement and final publication as one owner lifecycle.
    with lock(Path(config['state_root']) / 'cycle'):
        result = produce(config, policy, reader, service_read, head)
        if result['state'] == 'measured':
            return publish_release(config, policy, result['git_commit'], head)
        return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', required=True)
    args = parser.parse_args()
    try:
        config = private_config(args.config)
        env, p = binding(config, load_policy())
        require(config.get('frontend_origin') and config.get('release_status_root'), 'release_verification_not_configured')
        credentials = Path(os.environ.get('CREDENTIALS_DIRECTORY', '/nonexistent/m4-credentials'))
        require(credentials.is_absolute() and credentials.is_dir(), 'measurement_credentials_not_provisioned')
        reader = SupabaseReader(config, (credentials / 'measurement-token').read_text().strip(),
                                (credentials / 'readiness-only-key').read_text().removesuffix('\n'))
        result = owner_cycle(config, load_policy(), reader,
                         lambda sha: read_json(config['service_evidence_origin'].rstrip('/') + '/' + sha + '.json'),
                         lambda: latest(config['repository'], p['branch']))

    except Rejected as error:
        result = {'state': 'failed', 'reason': str(error)}
    except Exception:
        result = {'state': 'failed', 'reason': 'evidence_owner_failed'}
    print(json.dumps(result, sort_keys=True))
    return 0 if result['state'] in ('pass', 'pending', 'superseded') else 1


if __name__ == '__main__':
    raise SystemExit(main())
