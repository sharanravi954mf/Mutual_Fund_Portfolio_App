# M4 local validation record — 2026-10-09

Base: `8993ce141ceed6a1cae95c2a7edbfbfcf24524f8`, freshly fetched from origin.
Branch: `feature/m4-unified-environment-deployment-v1`.
Worktree: `/home/ubuntu/moneybowl-worktrees/m4-unified-environment-deployment-v1`.
This record describes synthetic/local validation, not hosted deployment success.
See [ownership, commissioning and limitations](MONEYBOWL_M4_ENVIRONMENT_PROMOTION.md).

## Tools and existing-file baseline

Python 3.12 standard library; Deno 2.9.6; Flutter 3.44.6 / Dart 3.12.2;
repository-pinned network-disabled disposable Supabase Postgres 17.6.1.155;
actionlint 1.7.12 (downloaded release checksum verified).

Before implementation editing, ran the existing commissioning (34), commit-validator
(5), route-parity (17), frozen migration-history (27 files) and documentation checks.
Started existing Deno, legacy dispatcher, SQL and Flutter baseline suites before
editing their corresponding source. No new M4 test is counted as baseline.
Flutter's sandbox-blocked attempt was repeated with loopback permission; no application
Dart files were changed. The existing SQL suite rebuilt 92 migrations and ran 21 SQL
regression files, plus duplicate-admission and recovery-provisioning concurrency checks.
The disposable container was removed by the existing test script. No hosted DB access.

## Commands and results

All commands below ran from the isolated worktree unless a service directory is
specified. Tool names in the commands resolve to these exact local executables:

- `deno`: `/opt/moneybowl-toolchains/deno/2.9.6/aarch64-unknown-linux-gnu/deno`
- `flutter`: `/home/ubuntu/.local/share/flutter-moneybowl/bin/flutter`
- `actionlint`: `/tmp/moneybowl-m4-actionlint/actionlint`
- Legacy Python pytest: `/tmp/b061-test-venv/bin/python`
- Ingestion Python pytest: `/tmp/moneybowl-m4-venv/bin/python`

| Executed command | Result |
| --- | --- |
| `python3 -m unittest discover -s tools/commissioning -v` | 34 passed baseline and final |
| `python3 -m unittest discover -s .github/scripts -p 'test_validate_commits.py'` | 5 passed baseline and final |
| `python3 scripts/generate_outbox_routes.py --check` | Exact 17-route parity, baseline and final |
| `python3 .github/scripts/validate_migration_history.py` | 27 frozen files unchanged, baseline and final |
| `python3 .github/scripts/validate_docs.py` | Baseline and final documentation/link audit passed |
| `python3 -m pytest -q` in `services/outbox-dispatcher` | Initial system Python lacked pytest; repeated with legacy test venv: 63 passed |
| `bash scripts/test_m2_outbox_sql.sh` | Initial sandbox Docker access denied; authorized disposable run passed: 92 migrations, 21 SQL files, both concurrency checks |
| `deno test --deny-net --deny-env supabase/functions/outbox-dispatcher supabase/functions/_shared/nse supabase/functions/nse*-worker supabase/functions/nse-uat-smoke-test` | 1,069 passed, zero failed |
| `flutter --version` | 3.44.6, Dart 3.12.2 |
| `flutter pub get --offline` | Passed using existing package cache |
| `flutter test` | Initial sandbox socket denial; loopback-enabled rerun: 3,017 passed, zero failed |
| `flutter analyze --no-fatal-warnings --no-fatal-infos` | Exit zero; 91 pre-existing warnings/information, no errors |
| `python3 -m unittest discover -s tools/deployment -v` | Final 56 passed, zero failed; repeated as implementation evolved |
| `deno test --deny-net --deny-env supabase/functions` | Initial 1,222 passed, one failed: existing authorization test intentionally needs synthetic env access |
| `deno test --deny-net --deny-env --ignore=supabase/functions/_shared/authorization_test.ts supabase/functions` | Final 1,222 passed, zero failed |
| `env -u SUPABASE_URL -u SUPABASE_ANON_KEY -u SUPABASE_SERVICE_ROLE_KEY deno test --deny-net --allow-env=SUPABASE_URL,SUPABASE_ANON_KEY,SUPABASE_SERVICE_ROLE_KEY supabase/functions/_shared/authorization_test.ts` | 1 passed; inherited variables removed, only synthetic values used, network denied |
| `while IFS= read -r entry; do deno check "$entry" || exit 1; done < <(find supabase/functions -mindepth 2 -maxdepth 2 -name index.ts \| sort)` | Initial two RPC type errors in platform override; later attempt also reached obsolete undeployed `update-excel-metadata` and failed on uncached npm metadata/DNS |
| `deno check supabase/functions/platform-admin-override/index.ts` | Passed after one-line PromiseLike compatibility correction |
| `deno test --deny-net --deny-env supabase/functions/platform-admin-override` | 11 passed, zero failed after type correction; included in final full suite |
| `python3 tools/deployment/edge_entries.py > /tmp/moneybowl-m4-evidence/edge-entries.txt` followed by `while IFS= read -r entry; do deno check "$entry" || exit 1; done < /tmp/moneybowl-m4-evidence/edge-entries.txt` | All 20 integration-declared entrypoints passed; missing declared entrypoint fails. Retired undeployed sources are not deployment targets |
| `/tmp/b061-test-venv/bin/python -m pytest -q` in `services/ingestion-support` | Baseline tooling attempt lacked FastAPI |
| `python3 -m venv /tmp/moneybowl-m4-venv` and `/tmp/moneybowl-m4-venv/bin/pip install -r services/ingestion-support/requirements-dev.txt` | Repository-pinned test dependencies installed in isolated temporary venv |
| `/tmp/moneybowl-m4-venv/bin/python -m pytest` in `services/ingestion-support` | First attempt overlapped dependency installation; later restricted test harness stalled and was terminated |
| `env -u INGESTION_SUPPORT_BASE_URL /tmp/moneybowl-m4-venv/bin/python -m pytest -vv` in `services/ingestion-support` | Local harness permission enabled: 194 passed, 1 intentionally skipped live Compose smoke, zero failed |
| `flutter build web --release --dart-define=MONEYBOWL_ENV=qa --dart-define=SUPABASE_URL=https://abcdefghijklmnopqrst.supabase.co --dart-define=SUPABASE_ANON_KEY=sb_publishable_synthetic_ci_only_0000 --dart-define=NSE_CONSOLE_ENABLED=false --dart-define=MONEYBOWL_DEV_ONBOARDING_PREVIEW=false` | Release build passed; synthetic public settings only; existing Wasm dry-run and Cupertino font warnings |
| `python3 .github/scripts/validate_commits.py 'feat: implement unified environment promotion and release verification'` | Conventional Commit format passed |
| `python3 -m py_compile tools/deployment/*.py` | Passed |
| `actionlint .github/workflows/environment-promotion.yml .github/workflows/commit-quality.yml .github/workflows/documentation-quality.yml .github/workflows/migration-history.yml` | Passed before queue setting added; with queue setting, one schema-version limitation below |
| `actionlint -ignore 'unexpected key "queue" for "concurrency" section' .github/workflows/*.yml` | All workflows passed remaining checks; only documented schema-version mismatch suppressed |
| `git diff --check` and `git diff --cached --check` | Passed |

Current GitHub documentation supports `concurrency.queue: max`; actionlint 1.7.12
still accepts only group/cancel-in-progress. The narrow ignore applies only to this
known linter schema lag. The workflow retains queueing to prevent a slow old CI run
from cancelling the latest revision's pending observer. No runtime validation or
security test is disabled. Actual Actions execution remains unverified until publication.

## Negative/security coverage

The 56 M4 tests use only temporary directories, disposable Git repositories,
synthetic configurations, mock HTTP readers and an executable synthetic Flutter
builder. Three real processes contend for one release lock; exactly one builds.
Coverage includes every required failure scenario:

1. Valid feature PR to develop and valid reviewed develop-to-QA promotion.
2. Feature pushes cannot deploy; direct feature-to-QA PRs cannot promote.
3. QA is blocked before network/configuration access until privately commissioned.
4. Wrong project, environment, repository, SHA, branch, origin, forced/deleted or
   malformed events fail. Production targets fail.
5. Missing public values, backend define names, service-role JWTs, wrong project
   URLs, DEV flags in QA and QA financial activation policy fail.
6. Synthetic backend environment values cannot appear in the compiled fixture;
   only explicitly public defines reach the isolated child process.
7. Outdated revisions skip; rapid merges skip a stale build and activate the latest;
   forced rollback fails; duplicate and concurrent deliveries cannot corrupt releases.
8. Failed builds retain the previous release; corrupt immutable releases, symlink
   assets and changed configuration at the same SHA fail. Published asset modes are
   explicitly readable by the web server.
9. Failed migrations, unverifiable/expired backend receipts, missing service proof,
   wrong live frontend identity/assets and read timeouts cannot report PASS.
10. Replaced dispatcher policy or an active legacy Oracle dispatcher fails evidence
    validation. M4 modules expose no commissioning/financial mutation capability.
11. Shared workflows have no QA/Production secrets, self-hosted runners, privileged
    PR events or duplicate Supabase deployment commands.
12. Service overrides require immutable image digests and retain one API replica;
    QA-disabled and Production manifests fail.
13. Existing migrations cannot be changed; additive migrations are allowed; unreviewed
    QA merge-tree additions fail; every declared function must have an entrypoint.
14. Raw transport exceptions are sanitized; permanent HTTP errors are not retried as
    transient failures; redirects and non-HTTPS evidence are rejected.

## Evidence limits and safety

The backend/service receipt producer is a contract and an outstanding private
implementation/commissioning requirement. No test asserts that a real Supabase
integration emitted trustworthy source evidence. Existing live ownership and DEV
commissioning context came from the task and inspected source/runbooks, not new
hosted probes. Public deployment endpoints were not contacted in this execution.

Host adapter installation, GitHub settings, receipt hosting and private service
release automation were not performed. QA policy remains disabled with no project
identity. No branch `qa`, QA project, QA secrets, Production access, live DEV files,
service restarts, financial operations, M2A operations or legacy Oracle activation
were created or changed. No backend secret files/values were read or disclosed.
Existing authenticated Git fetch was used only to establish the source baseline;
no push, PR, merge or repository-setting change occurred.

Source inspection confirms M1, M2, M2A, canonical routes, migrations and Flutter
application code remain unchanged. The sole existing runtime-source edit is the
platform override's TypeScript-only PromiseLike interface correction; it changes no
JavaScript behavior, authorization or RPC calls. The canonical develop checkout
remains at the original SHA and clean. M4 is a reviewable local implementation,
**not commissioned full-stack deployment automation**.

## Review corrections — 2026-10-10

Continued the existing candidate `d8eb4b9f02ae85e22903b6cc77d15e345d3d4ed4`
in the same isolated worktree/branch. Did not recreate M4, update canonical develop,
fetch a different base or publish anything. The sections above describe the original
candidate; this correction implements the previously missing private evidence and
service owners. Their live commissioning is still blocked.

Existing-file baseline, recorded before these edits:
`PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tools/deployment -v`
passed 56 tests; the equivalent commissioning command passed 34. New owner tests
are not baseline evidence. Temporary logs for this execution are under
`/tmp/moneybowl-m4-review/`; this versioned record is the durable result summary.

| Command executed for this correction | Result |
| --- | --- |
| `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tools/deployment -v` | Final 108 passed, zero failed (56 existing plus 52 new); repeated after implementation changes |
| `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tools/commissioning -v` | 34 passed; baseline and final |
| `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s .github/scripts -p 'test_validate_commits.py'` | 5 passed |
| `env -u INGESTION_SUPPORT_BASE_URL PYTHONDONTWRITEBYTECODE=1 /tmp/moneybowl-m4-venv/bin/python -m pytest -vv` from `services/ingestion-support` | 194 passed, 1 live smoke test intentionally skipped; local harness permission enabled, hosted URL unset |
| `PYTHONDONTWRITEBYTECODE=1 /tmp/b061-test-venv/bin/python -m pytest -q` from `services/outbox-dispatcher` | 63 passed; compatibility tests only, no dispatcher execution |
| `/opt/moneybowl-toolchains/deno/2.9.6/aarch64-unknown-linux-gnu/deno test --deny-net --deny-env supabase/functions/outbox-dispatcher` | 88 passed, zero failed; includes HMAC readiness and bounded recovery tests |
| `python3 tools/deployment/edge_entries.py > /tmp/moneybowl-m4-review/edge-entries.txt` then `while IFS= read -r entry; do /opt/moneybowl-toolchains/deno/2.9.6/aarch64-unknown-linux-gnu/deno check "$entry" \|\| exit 1; done < /tmp/moneybowl-m4-review/edge-entries.txt` | All 20 integration-declared entrypoints passed |
| `python3 scripts/generate_outbox_routes.py --check` | All 17 canonical routes match |
| `python3 .github/scripts/validate_migration_history.py` | All 27 frozen migrations unchanged |
| `python3 .github/scripts/validate_docs.py` | Documentation/link audit passed |
| `/tmp/moneybowl-m4-actionlint/actionlint -ignore 'unexpected key "queue" for "concurrency" section' .github/workflows/*.yml` | Passed with the previously documented narrow linter-version exception; no workflow edits in this correction |
| `PYTHONPYCACHEPREFIX=/tmp/moneybowl-m4-review/pycache python3 -m py_compile tools/deployment/*.py` | Passed; cache outside source |
| `python3 .github/scripts/validate_commits.py 'feat: complete private release owners and propagation verification'` | Passed |
| `git diff d8eb4b9 -- supabase/migrations supabase/functions tools/commissioning services lib` | Empty: no changes to financial, migration, application or service runtime source |
| `git diff --check` and `git diff --cached --check` | Passed |

The final suites above total **492 passing tests, one intentional live-test skip**.
The original candidate's full Flutter and SQL runs are historical evidence, not new
executions in this correction. Those sources were unchanged. No Docker build, push,
Compose deployment, systemd installation, hosted DB query, receipt endpoint probe or
financial request was executed. CLI version/help and public vendor documentation
were inspected without project credentials.

During implementation, an initial synthetic full-sequence fixture used an expired
service timestamp; the fixture was corrected to use the real freshness contract.
An added check against all declared repository imports caught a parser matching a
field named `effective_from`; the verifier was corrected to tokenize imports without
matching prose/comments/strings. Final tests include the actual declared local import
graph and computed-import denial. These resolved failures are not hidden as passes.

New security/failure coverage includes delayed receipts, HTTP 404 and transient
reads, partial components, immediate unauthorized/TLS/malformed/mismatched denial,
bounded timeout, branch advancement, actual stored migration content, incomplete or
changed function exports, unstable snapshots, project/mode/Cron/route mismatch,
expired or missing service evidence, and removal/replacement of stale success reports.
Private owner tests reject uncommissioned DEV, QA and Production targets before Docker
access, secret build contexts, inherited backend process credentials, unsafe config
permissions/paths, unapproved API operations, unsafe downloads, forged image provenance,
multiple API containers, changed single-worker command, wrong daemon, infrastructure
changes, enabled legacy restart owners, invalid running configuration and rollback.
Concurrent owner calls build/activate only once; duplicate calls remeasure; failed
builds do not activate; failed activation does not produce evidence or blind restart
of a same-image unhealthy service. A fully mocked sequence runs service deployment,
independent backend measurement and frontend verification before final PASS.

These are synthetic interface tests, not real Management API/CLI export or Docker
integration tests. Read-only schema/Cron permissions, historical migration statements,
actual function export layout, Compose/plugin compatibility, private registry/image
provenance adoption and TLS endpoint ownership need independent private provisioning
and validation. The source is ready for independent security review; it is not
security-approved or end-to-end commissioned. See the updated
[precise commissioning dependencies and status matrix](MONEYBOWL_M4_ENVIRONMENT_PROMOTION.md).

QA remains disabled with no project, credential or branch provisioned. No Production
access, live DEV changes, secret-value access/disclosure, M2A lifecycle operation,
financial activation or legacy Oracle restart occurred. The canonical checkout remains
clean at `8993ce141ceed6a1cae95c2a7edbfbfcf24524f8`.
