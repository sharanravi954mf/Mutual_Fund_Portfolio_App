#!/usr/bin/env python3
"""Test the actual opt-in configuration only in the parent's disposable DB."""
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
container = sys.argv[1]
if not re.fullmatch(r'moneybowl-authz-regression-platform-mfd-[0-9]+', container):
    raise SystemExit('Disposable onboarding harness container required')
info = json.loads(subprocess.check_output(['docker', 'inspect', container], text=True))[0]
assert info['HostConfig']['NetworkMode'] == 'none'
assert '/var/lib/postgresql/data' in info['HostConfig']['Tmpfs']

CONFIG = (ROOT / 'supabase/operations/nse_ekyc_amcs_dev.sql').read_text()
COMMAND = ['docker', 'exec', '-i', container, 'psql', '-X', '-qAt',
           '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1']
SOURCE = ('https://nseinvestuat.nseindia.com/nsemfdesk/resources/upload/apidetails/'
          'NSE_INVEST_API_FAQ_310725.pdf#page=5')
# Independent expected values from FAQ p5 Q1.18, not parsed from the seed.
EXPECTED = {
    'B': 'Aditya Birla', 'K': 'Kotak Mahindra', 'H': 'HDFC Mutual Fund',
    'G': 'Bandhan Mutual Fund', 'CR': 'Canara Robeco Mutual Fund',
    'O': 'HSBC Asset Management', 'UK': 'Union Asset Management',
}
checks = 0


def check(ok, label):
    global checks
    if not ok:
        raise AssertionError(label)
    checks += 1


def run(statement, params=(), error=None):
    result = subprocess.run(COMMAND + list(params), input=statement, text=True,
                            capture_output=True)
    if error is not None:
        check(result.returncode != 0 and error in result.stderr, 'expected safe failure: ' + error)
    elif result.returncode:
        # Never echo input SQL or a provider/identity payload on failure.
        raise AssertionError('local SQL failed; exit code ' + str(result.returncode))
    return result.stdout.strip()


def apply(project='LOCAL_DISPOSABLE', error=None):
    return run(CONFIG, ['-v', 'project_ref=' + project], error)


def rows():
    return json.loads(run("SELECT coalesce(jsonb_agg(to_jsonb(a) ORDER BY code),'[]') "
                          "FROM moneybowl_onboarding.ekyc_amcs a;"))


def reset():
    # Owner-only fixture cleanup in the proven local tmpfs container.
    run('TRUNCATE moneybowl_onboarding.ekyc_amcs;')


check(rows() == [], 'automatic migration chain must leave selector uncommissioned')
baseline = run("SELECT md5(string_agg(pg_get_functiondef(p.oid), '' ORDER BY p.oid)) "
               "FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace "
               "WHERE n.nspname='moneybowl_onboarding' OR "
               "(n.nspname='public' AND p.proname LIKE '%onboarding%');")
for target in ['', 'PRODUCTION', 'WRONG_PROJECT']:
    apply(target, 'ekyc_amc_dev_project_attestation_required')
check(rows() == [], 'invalid target inserts nothing')
run(CONFIG, error='syntax error')  # Required psql variable deliberately missing.

apply()
initial = rows()
check(len(initial) == 7, 'exactly seven approved rows')
check({r['code']: r['label'] for r in initial} == EXPECTED, 'exact FAQ codes and labels')
check(all(r['source_reference'] == SOURCE and r['active'] for r in initial), 'provenance and DEV activation')
check(next(r['code'] for r in initial if r['label'] == 'Bandhan Mutual Fund') == 'G', 'capital G')
apply()
check(rows() == initial, 'identical reapplication changes nothing')
run('SET ROLE authenticated;\n' + CONFIG,
    ['-v', 'project_ref=LOCAL_DISPOSABLE'], error='permission denied')
check(rows() == initial, 'browser cannot apply config by spoofing target attestation')
run("INSERT INTO moneybowl_onboarding.ekyc_amcs SELECT * FROM moneybowl_onboarding.ekyc_amcs WHERE code='G';",
    error='duplicate key')

run("UPDATE moneybowl_onboarding.ekyc_amcs SET active=false WHERE code='G';")
inactive = rows()
apply()
check(rows() == inactive, 'inactive rows remain inactive on reapplication')

for column, value in [('label', 'Conflicting label'), ('source_reference', 'unapproved source')]:
    reset()
    apply()
    run("DELETE FROM moneybowl_onboarding.ekyc_amcs WHERE code='UK';")
    run(f"UPDATE moneybowl_onboarding.ekyc_amcs SET {column}=:'value' WHERE code='G';", ['-v', 'value=' + value])
    before = rows()
    apply(error='ekyc_amc_catalog_conflict')
    check(rows() == before, 'conflict preserves rows and prevents partial seed')

for unknown in ['AXF', 'T', 'UNAPPROVED']:
    reset()
    run("INSERT INTO moneybowl_onboarding.ekyc_amcs VALUES(:'code','Unapproved fixture','local-only',true);",
        ['-v', 'code=' + unknown])
    before = rows()
    apply(error='ekyc_amc_catalog_conflict')
    check(rows() == before, 'unknown pre-existing entry is never overwritten or admitted')

reset()
# Two concurrent applications serialize under the table lock and retain seven rows.
command = COMMAND + ['-v', 'project_ref=LOCAL_DISPOSABLE']
workers = [subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True) for _ in range(2)]
for worker in workers:
    worker.stdin.write(CONFIG)
    worker.stdin.close()
    worker.stdin = None
for worker in workers:
    worker.communicate(timeout=30)
    check(worker.returncode == 0, 'concurrent configuration completes')
check(rows() == initial, 'concurrent configuration has no duplicates or drift')
after = run("SELECT md5(string_agg(pg_get_functiondef(p.oid), '' ORDER BY p.oid)) "
            "FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace "
            "WHERE n.nspname='moneybowl_onboarding' OR "
            "(n.nspname='public' AND p.proname LIKE '%onboarding%');")
check(after == baseline, 'onboarding functions unchanged')
check(run('SELECT count(*) FROM moneybowl_onboarding.kyc_operations;') == '0', 'configuration prepares no provider operation')
print(f'eKYC AMC configuration: {checks} checks PASS; local network disabled; no provider send')
