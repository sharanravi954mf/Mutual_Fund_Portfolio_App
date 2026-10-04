#!/usr/bin/env python3
"""Exercise read-only operational queries in the parent's proven disposable DB."""
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
container = sys.argv[1]
if not re.fullmatch(r'moneybowl-authz-regression-platform-mfd-[0-9]+', container):
    raise SystemExit('Disposable MFD harness container required')
info = json.loads(subprocess.check_output(['docker', 'inspect', container], text=True))[0]
assert info['HostConfig']['NetworkMode'] == 'none'
assert '/var/lib/postgresql/data' in info['HostConfig']['Tmpfs']


def sql(statement, params=None):
    command = ['docker', 'exec', '-i', container, 'psql', '-X', '-qAt', '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1']
    for key, value in (params or {}).items():
        command.extend(['-v', f'{key}={value}'])
    result = subprocess.run(command, input=statement, text=True, capture_output=True)
    if result.returncode:
        # All queries and fixtures here are synthetic. No Auth secrets selected.
        raise AssertionError(result.stderr)
    return result.stdout.strip()


def uid(n):
    value = hashlib.md5(f'mfa-commissioning-fixture-{n}'.encode()).hexdigest()
    return f'{value[:8]}-{value[8:12]}-{value[12:16]}-{value[16:20]}-{value[20:]}'


paths = [ROOT/'supabase/operations/platform_mfa_commissioning_preflight.sql',
         ROOT/'supabase/operations/platform_mfa_mfd_commissioning_postcheck.sql']
for path in paths:
    clean = re.sub(r'--[^\n]*', '', path.read_text())
    assert not re.search(r'\b(insert|update|delete|create|alter|drop|grant|revoke|set_config|set\s+role|select\s+\*)\b', clean, re.I)
    assert 'BEGIN TRANSACTION READ ONLY;' in clean
    assert not re.search(r'\b(secret|access_token|refresh_token|encrypted_secret|ip|user_agent)\b', clean, re.I)

sql((ROOT/'supabase/tests/platform_mfa_commissioning_test.sql').read_text())
params = dict(project_ref='LOCAL_DISPOSABLE', operator_user_id=uid(1), applicant_user_id=uid(2), application_id='')


def inspect(post=False, **overrides):
    result = json.loads(sql(paths[1 if post else 0].read_text(), params | overrides))
    assert result['transaction_read_only'] == 'on'
    assert result['browser_session_confirmed'] is False
    return result


before = inspect()
assert before['parameters_valid'] and not before['application_supplied']
assert before['target_counts']['profiles'] == 0
assert before['operator_factors']['verified_totp'] == 1
assert len(before['operator_grants']) == 2
for key in ['operator_user_id', 'applicant_user_id', 'application_id']:
    bad = inspect(True, **{key: 'not-a-uuid'})
    assert not bad['parameters_valid'] and bad['validation_errors']
assert inspect(project_ref='WRONG_PROJECT')['validation_errors'] == ['dev_project_attestation_required']
assert 'operator_and_applicant_must_differ' in inspect(applicant_user_id=uid(1))['validation_errors']
assert 'applicant_not_found' in inspect(applicant_user_id=uid(999))['validation_errors']
assert 'application_not_found' in inspect(application_id=uid(998))['validation_errors']
assert 'invalid_application_uuid' in inspect(True)['validation_errors']

for n, action in [(2, 'approve'), (3, 'reject')]:
    sql(f"""SET ROLE authenticated;
SELECT mfa_commissioning_fixture.login({n});
SELECT public.submit_mfd_application('{uid(400+n)}','DEV-only synthetic application','DEV-TEST','local synthetic');
SELECT mfa_commissioning_fixture.login(1);
SELECT public.start_mfd_application_review((SELECT id FROM public.mfd_applications WHERE applicant_user_id='{uid(n)}'),1,'{uid(500+n)}');
SELECT mfa_commissioning_fixture.login(1,'aal2');
SELECT public.{action}_mfd_application((SELECT id FROM public.mfd_applications WHERE applicant_user_id='{uid(n)}'),2,'{uid(600+n)}','Synthetic local evidence only');""")
    application = sql(f"SELECT id FROM public.mfd_applications WHERE applicant_user_id='{uid(n)}';")
    result = inspect(True, applicant_user_id=uid(n), application_id=application)
    assert result['parameters_valid']
    integrity = result['decision_integrity']
    assert integrity['terminal'] and integrity['expected_operator']
    for key in ['terminal_events', 'attributed_terminal_events', 'decision_receipts', 'receipt_event_binding']:
        assert integrity[key] == 1, key
    approved = action == 'approve'
    assert integrity['approval_binding'] is approved
    assert integrity['rejection_has_no_provisioning'] is not approved
    for key in ['provisioning_audits', 'attributed_provisioning_audits']:
        assert integrity[key] == (1 if approved else 0)
    counts = result['target_counts']
    for key in ['profiles', 'owned_workspaces', 'memberships']:
        assert counts[key] == (1 if approved else 0)
    for key in ['investor_profiles', 'investor_links', 'investor_assignments', 'advisor_profiles',
                'euin_assignments', 'integration_accounts', 'integration_operations', 'nse_connections', 'platform_grants']:
        assert counts[key] == 0, key
    assert result['global_baseline'] == before['global_baseline']
    assert result['operator_grants'] == before['operator_grants']
    mismatch = inspect(True, applicant_user_id=uid(1), application_id=application)
    assert 'application_applicant_mismatch' in mismatch['validation_errors']
    assert mismatch['application'] is None
print('MFA commissioning inspections: read-only, UUID/project/missing/mismatch, approval/rejection integrity and unchanged baselines PASS')
