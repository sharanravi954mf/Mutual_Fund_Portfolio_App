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

## Final security boundary correction — 2026-10-10

Continued reviewed candidate `617c6c7d27399357f0cbb184ae90d05c8beb766a` in the
same isolated worktree. Before editing, the existing M4 suite passed 108 tests,
commissioning passed 34, and the dispatcher suite passed 88. Only generated Python
bytecode caches were initially untracked; no source edits were present.

The first finding was authority sharing: a holder of the evidence owner's former
key could sign a fresh financial notification, not merely replay readiness. The
fix introduces optional `OUTBOX_READINESS_KEY`, a readiness-only header and signing
domain, confines it to the side-effect-free handler branch, and removes legacy-key
loading from the M4 owner. Config rejects reuse of notification/database/worker keys.
The second finding accepted incomplete or temporary retirement state. The fix binds
explicit DEV inventory and the original container ID, requires persistent service
masks and the disabled/inactive timer, and checks concrete template instances.

Ordered verification and executed commands (`deno` resolves to the absolute 2.9.6
executable listed above; all fixtures are synthetic):

| Gate / command | Result |
| --- | --- |
| `deno fmt supabase/functions/outbox-dispatcher/config.ts supabase/functions/outbox-dispatcher/handler.ts supabase/functions/outbox-dispatcher/handler_test.ts` | Three changed TypeScript files formatted |
| `deno check supabase/functions/outbox-dispatcher/index.ts` | Passed |
| `deno test --deny-net --deny-env --filter 'readiness' supabase/functions/outbox-dispatcher` | 17 passed, 78 filtered; includes seven new boundary/compatibility tests |
| `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tools/deployment -q` | Final 119 passed, zero failed |
| `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tools/commissioning -q` | 34 passed, zero failed |
| `deno test --deny-net --deny-env supabase/functions/outbox-dispatcher supabase/functions/_shared/nse supabase/functions/nse*-worker supabase/functions/nse-uat-smoke-test` | 1,076 passed, zero failed; includes all 95 native dispatcher tests |
| `PYTHONDONTWRITEBYTECODE=1 /tmp/b061-test-venv/bin/python -m pytest -q` in `services/outbox-dispatcher` | 63 passed; compatibility tests only |
| `python3 tools/deployment/edge_entries.py`, each returned entry checked with `deno check` using a Python subprocess loop with `check=True` | All 20 declared Edge entrypoints passed |
| `python3 scripts/generate_outbox_routes.py --check` | All 17 routes unchanged |
| `python3 .github/scripts/validate_migration_history.py` | 27 frozen migration files unchanged; no migration edits |
| `/tmp/moneybowl-m4-actionlint/actionlint -ignore 'unexpected key "queue" for "concurrency" section' .github/workflows/*.yml` | Passed with the existing documented linter schema exception |
| `python3 .github/scripts/validate_docs.py` | Passed |
| `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s .github/scripts -p 'test_validate_commits.py'` | 5 passed |
| `python3 .github/scripts/validate_commits.py 'fix: isolate readiness authority and enforce dispatcher retirement'` | Passed |
| `git diff --check` and `git diff --cached --check` | Passed |

The independently repeated read-only candidate review found no concrete surviving
bypass or compatibility regression and ran `PYTHONDONTWRITEBYTECODE=1 python3 -B
-m unittest test_owners.TransportTests -v` from `tools/deployment`: 25 passed.
One new multi-gate test initially reused a provenance ledger with a fresh mock Docker
instance; its isolated fixture state was corrected. No production assertion was weakened.

The new tests sign fully valid fresh event/recovery envelopes with the readiness-only
key, under both headers/signing schemes and both route aliases. Every attempt fails
without RPC, worker or log calls. Mixed headers, wrong/missing credentials, stale
bodies and path confusion also fail. Legacy readiness and financial notifications
still work with the new secret present or absent. Python and Edge verify the same
fixed domain-separated HMAC vector. M4 refuses the former credential filename.

Retirement tests exercise missing/replaced/running/restarting containers, restart
policy changes, incomplete inventory, temporary/absent service masks, enabled or
active timers, active template instances, malformed or duplicate properties and
unexpected owners. Each deployment measurement gate withholds success on failure.
All Docker/systemd interactions in these tests are mocked; no real command ran.

No live credentials were read, logged, copied, rotated or provisioned. No deployment,
service restart, financial operation, M2A lifecycle operation, QA/Production access,
push, PR, merge or repository-setting change occurred. No SQL, Cron, routes, event
leases, encrypted evidence, PROVEN_NOT_SENT/MAYBE_SENT logic or worker code changed.
SQL/Docker integration and Flutter suites were not rerun because their sources are
unchanged and this task prohibits infrastructure mutation. Actual Oracle output,
private inventory bindings, new readiness credential provisioning and complete live
release verification remain commissioning prerequisites. Local security fixes are
verified; **live M4 commissioning remains BLOCKED**.

## PR #207 CI correction — 2026-10-11

Continued candidate `7f6f31e0addcc9d02e6e5e8188e572fde2913bdb` in the existing
feature worktree. The worktree was clean, remote feature HEAD matched, and an explicit
fetch confirmed `origin/develop=8993ce141ceed6a1cae95c2a7edbfbfcf24524f8`.
Canonical develop was not changed. Read-only GitHub metadata confirmed
[PR #207](https://github.com/sharanravi954mf/Mutual_Fund_Portfolio_App/pull/207)
and [run 38087054932](https://github.com/sharanravi954mf/Mutual_Fund_Portfolio_App/actions/runs/38087054932)
refer to that candidate: Flutter dependency resolution and the SQL container step
failed, contracts passed, and deployment observation was skipped.

### Root causes and minimal correction

The root `pubspec.lock` existed only as an ignored local file. A fresh clone reproduced
`Cannot do --enforce-lockfile without an existing pubspec.lock` (exit 1). The correction
tracks the existing validated 109-package resolution. `.gitignore` retains its general
lockfile rule and adds only `!/pubspec.lock`; nested lockfiles, `.env`, build products
and caches remain ignored. No dependency constraints or versions were upgraded.
Flutter remains 3.44.6 / Dart 3.12.2, and Actions retains `--enforce-lockfile`.

The lockfile SHA-256 is
`d98f1cb477419371fbc8e37ca7ac7c10bc4400b9031dd0178370aaa5fcbebd80`.
Offline enforcement in the original worktree and online enforcement in a fresh
candidate clone with an empty package cache both left it byte-identical. The latter
had no prior `.dart_tool` or build output and used a clean process environment with
only HOME, PUB_CACHE and PATH. The source manifest remains unchanged. Availability
of newer packages and discontinued `js` are informational, not resolution failures.

The SQL failure occurred at the public ECR image acquisition step, before a database
or test ran. Only `scripts/test_m2_outbox_sql.sh` changes its image reference. Both
existing workflows call this script, so neither needs a new credential or workflow
change. The disposable container, `--network none`, tmpfs data, EXIT cleanup,
`set -euo pipefail`, migration order, fixtures, role checks, assertions and concurrency
checks remain unchanged.

### Independently verified image identity

Selected repository: `docker.io/supabase/postgres`, Supabase image release
`17.6.1.155`; the executable reports **PostgreSQL 17.6**.
Pinned multi-platform index:

```text
sha256:3866d94d8426927e8db3f1c5d790752292bfbe27b5f1f46e199ae1b7d3c1710b
```

| Platform | Manifest digest | Image configuration digest |
| --- | --- | --- |
| linux/amd64 | `sha256:3e2a7ab48783077d0122dc72ed5174afb543110c38266c845716c51d130658e4` | `sha256:56da3fb43b03aca9b8fa264c156177dd204f722e9500e8d80008f5c9f7b82985` |
| linux/arm64 | `sha256:9c09909e66c4da304b3fa280216670408ed76c7587d6c3887e3ed016cd5993da` | `sha256:af17d7a082c3a98b7902018fb68eaf9ac28c10b09cabdcea1d92f5f1903535b5` |

Anonymous HTTPS Registry API reads independently resolved both Docker Hub and ECR's
`17.6.1.155` tags. SHA-256 was computed over returned index/manifest/configuration bytes
and checked against digest references and response digest headers. Both registries
returned the **same index, architecture manifests, configuration digests and ordered
layer digests**. This is content equivalence, not an assumption based on equal tags.
The subsequent Docker Hub pull used the immutable index and no registry credentials.
The local runtime is ARM64; amd64 compatibility was verified from the index and image
configuration, not by executing an x86_64 container on Oracle.

The [Supabase publisher image](https://hub.docker.com/r/supabase/postgres) is used,
not a generic PostgreSQL replacement. A disposable `--network none --rm` image probe
confirmed PostgreSQL 17.6 and the required `pgcrypto`, `uuid-ossp`, `pg_cron`, `pg_net`
and `supabase_vault` control files using `pg_config --sharedir`. The initial probe's
assumed Debian-style extension path was wrong; querying the image's own PostgreSQL
configuration resolved that probe, without changing the image or SQL requirements.
Actual extension installation and SQL behavior are exercised by the full suite.

Registry assumptions: anonymous Docker Hub HTTPS/blob access and the publisher's
retention of this digest are required. Pinning prevents tag drift, not outages or
future registry quotas. A pull failure stays a failed CI job; there is no fallback to
another version, image, mocks or skipped tests. No Docker Hub login/secrets are added.
A synthetic Docker-command failure returned exit 125, invoked cleanup, and made zero
SQL calls. Successful local ARM64 tests cannot certify future GitHub-hosted amd64
network availability or execution; fresh PR CI remains required after publication.

### Baseline and final local execution

Before edits, the existing M4 (119), commissioning (34), route (17) and frozen
migration (27) checks passed. The original ECR script also completed all 92 migrations,
21 SQL regression files, feed parity and both concurrency checks before its image
reference was edited. These are existing-file baseline results, not new tests.
After the change, the entire real SQL suite passed again using the pinned Docker Hub
image. Both image references resolve to the same local ARM64 image identity; a
name-filtered Docker listing confirmed no `moneybowl-m2-test-*` containers remained.

Flutter commands below ran in `/tmp/moneybowl-m4-ci-207/clean-checkout`, a fresh local
clone of the reviewed source with only the candidate root lockfile added. Every
Flutter command used this exact sanitized prefix, with an initially empty package cache:

```sh
env -i HOME=/tmp/moneybowl-m4-ci-207/flutter-home \
  PUB_CACHE=/tmp/moneybowl-m4-ci-207/pub-cache \
  PATH=/home/ubuntu/.local/share/flutter-moneybowl/bin:/usr/bin:/bin
```

Other commands ran in the feature worktree unless a service directory is stated.
`deno` and `actionlint` resolve to the exact tool paths recorded above. Logs and
temporary registry/bundle verification programs are under `/tmp/moneybowl-m4-ci-207/`;
this versioned table is the durable result record.

| Command | Final result |
| --- | --- |
| `flutter pub get --enforce-lockfile` | Passed online from a fresh checkout/cache; lock SHA-256 unchanged |
| `flutter analyze --no-fatal-warnings --no-fatal-infos` | Exit 0; 91 existing warnings/information, no errors |
| `flutter test --reporter expanded` | 3,017 passed, zero failed |
| `flutter build web --release --dart-define=MONEYBOWL_ENV=qa --dart-define=SUPABASE_URL=https://abcdefghijklmnopqrst.supabase.co --dart-define=SUPABASE_ANON_KEY=sb_publishable_synthetic_ci_only_0000 --dart-define=NSE_CONSOLE_ENABLED=false --dart-define=MONEYBOWL_DEV_ONBOARDING_PREVIEW=false` | Passed; existing Wasm dry-run and Cupertino font warnings |
| `python3 /tmp/moneybowl-m4-ci-207/audit_bundle.py` | 33 web files checked; synthetic QA URL/key present, no backend credential-pattern matches |
| `python3 /tmp/moneybowl-m4-ci-207/verify_image.py` | Anonymous registry index/manifest/config digest verification and cross-registry content comparison passed for amd64 and arm64 |
| `DOCKER_CONFIG=/tmp/moneybowl-m4-ci-207/docker-config docker pull docker.io/supabase/postgres:17.6.1.155@sha256:3866d94d8426927e8db3f1c5d790752292bfbe27b5f1f46e199ae1b7d3c1710b` | Passed with empty Docker client configuration; no registry login |
| `DOCKER_CONFIG=/tmp/moneybowl-m4-ci-207/docker-config bash scripts/test_m2_outbox_sql.sh` | Exit 0; 92 migrations, 21 SQL regression files, feed parity, SQL authorization and both concurrency checks actually executed |
| `bash -n scripts/test_m2_outbox_sql.sh` | Passed |
| `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tools/deployment -q` | 119 passed, including owner/observer, readiness isolation, retirement, QA-disabled and fail-closed security tests |
| `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tools/commissioning -q` | 34 passed |
| `deno test --deny-net --deny-env --ignore=supabase/functions/_shared/authorization_test.ts supabase/functions` | 1,229 passed; includes native dispatcher and all NSE workers |
| `env -u SUPABASE_URL -u SUPABASE_ANON_KEY -u SUPABASE_SERVICE_ROLE_KEY deno test --deny-net --allow-env=SUPABASE_URL,SUPABASE_ANON_KEY,SUPABASE_SERVICE_ROLE_KEY supabase/functions/_shared/authorization_test.ts` | 1 passed, synthetic environment only |
| `python3 tools/deployment/edge_entries.py`, followed by `deno check` for every returned entry with checked subprocess exit codes | All 20 declared Edge entrypoints passed |
| `PYTHONDONTWRITEBYTECODE=1 /tmp/b061-test-venv/bin/python -m pytest -q` in `services/outbox-dispatcher` | 63 passed; compatibility tests, no dispatcher process started |
| `env -u INGESTION_SUPPORT_BASE_URL PYTHONDONTWRITEBYTECODE=1 /tmp/moneybowl-m4-venv/bin/python -m pytest -vv` in `services/ingestion-support` | 194 passed, 1 existing hosted Compose smoke skipped because no live URL was provided |
| `python3 scripts/generate_outbox_routes.py --check` | All 17 mappings match |
| `python3 .github/scripts/validate_migration_history.py` | All 27 frozen files unchanged |
| `/tmp/moneybowl-m4-actionlint/actionlint -ignore 'unexpected key "queue" for "concurrency" section' .github/workflows/*.yml` | Passed with the previously documented actionlint 1.7.12 schema limitation; workflows unchanged |
| `python3 .github/scripts/validate_docs.py` | Passed |
| `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s .github/scripts -p 'test_validate_commits.py' -q` | 5 passed |
| `python3 .github/scripts/validate_commits.py 'fix: make M4 Flutter and SQL CI reproducible'` and `python3 .github/scripts/validate_commits.py` | Proposed correction message and existing feature commit messages passed |
| `git diff --check` and `git diff --cached --check` | Passed |

The final unit/service suites total **4,662 passed, zero failed, one existing live
smoke skip**, separate from the successful real SQL regressions. No test was deleted,
weakened or newly skipped. Synthetic pull-failure coverage is supplemental: it does
not substitute for the completed database suite. Docker access and Flutter/local
service test sockets required execution permission outside the restricted harness;
successful reruns above resolve those environment restrictions.

Artifact inspection checked private-key material, secret Supabase keys, backend-role
JWTs and common provider credential formats without reading live credential stores.
An initial additional hostname-absence assertion found the existing public DEV host
comparison in `mfa_repository.dart`'s MFA issuer display label. That is neither a
credential nor the configured Supabase endpoint; the credential audit and synthetic
configuration checks passed. No application code was changed to remove that label.
No pattern scan alone can identify arbitrary opaque secrets; the fresh source checkout,
empty inherited process environment and public-only build inputs provide the boundary.

### Scope and readiness

Only `.gitignore`, root `pubspec.lock`, the SQL script image reference and these two
documentation files changed. Dependency versions, workflows, assertions, financial
business logic, migrations, M4 owners, readiness-key separation and QA-disabled
configuration are unchanged. No live credentials were read, printed or committed.
No hosted DB, live DEV application infrastructure, financial operation, QA/Production,
GitHub setting, push, PR update or deployment pipeline was mutated or triggered.
Only authorized disposable test containers ran; Oracle's retired dispatcher, active
native dispatcher and recovery Cron were untouched.

The correction is ready for independent review and fresh GitHub CI. Successful local
ARM64 tests are not a successful GitHub-hosted amd64 run. There are no outstanding
local test blockers; registry availability and the hosted run remain external
verification requirements. **M4 end-to-end live commissioning remains blocked and
outside this CI correction.**

## DEV commissioning remediation 001 — 2026-10-11

Started at clean local/remote feature candidate
`744ded1d7650fdcbd5415baa83def3eab07774af`, with canonical and fetched develop
unchanged at `8993ce141ceed6a1cae95c2a7edbfbfcf24524f8`. Before editing, the existing
M4 suite passed 119 tests, commissioning passed 34, route parity passed 17, and frozen
migration validation passed 27. No new test is counted as baseline.

Read-only host discovery and its limits are recorded in
[DEV remediation 001](MONEYBOWL_M4_DEV_REMEDIATION_001.md). Docker access used only
inspect/list/info/system-df and credential-free unresolved Compose rendering. No
build, up/down, pull/push, container execution or systemd mutation command ran.
An attempted resolved Compose check was rejected by automatic approval review because
it would read live `.env`; it was replaced with `/dev/null`, no interpolation and no
env-file resolution. Actual resolved hash certification remains blocked, not passed.
Initial discovery also encountered an absent optional Engine Health field and YAML
`!reset`; optional-health handling and a safe parser for structural metadata resolved
those read-only tooling issues. A template unit cannot be queried as a concrete
systemd invocation; persistent masks were verified with unit-file states and symlinks.

Commands below ran in the feature worktree unless a service directory is stated.
Temporary logs/metadata are under `/tmp/m4-remediation-001/`; only sanitized findings,
not raw host inventory or private configuration, are committed.

| Command | Result |
| --- | --- |
| `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tools/deployment -q` | 147 passed, zero failed; 119 existing plus 28 new |
| `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tools/commissioning -q` | 34 passed |
| `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s .github/scripts -p 'test_validate_commits.py' -q` | 5 passed |
| `env -u INGESTION_SUPPORT_BASE_URL PYTHONDONTWRITEBYTECODE=1 /tmp/moneybowl-m4-venv/bin/python -m pytest -vv` in `services/ingestion-support` | 194 passed, 1 existing live smoke skipped; local harness sockets authorized, hosted URL unset |
| `PYTHONDONTWRITEBYTECODE=1 /tmp/b061-test-venv/bin/python -m pytest -q` in `services/outbox-dispatcher` | 63 passed; no dispatcher process started |
| `/opt/moneybowl-toolchains/deno/2.9.6/aarch64-unknown-linux-gnu/deno test --deny-net --deny-env supabase/functions/outbox-dispatcher supabase/functions/_shared/nse supabase/functions/nse*-worker supabase/functions/nse-uat-smoke-test` | 1,076 passed, zero failed |
| `python3 tools/deployment/edge_entries.py` and a checked Python subprocess loop invoking the pinned `deno check` for every returned entry | All 20 declared entrypoints passed |
| `python3 scripts/generate_outbox_routes.py --check` | All 17 canonical mappings match |
| `python3 .github/scripts/validate_migration_history.py` | All 27 frozen files unchanged |
| `/tmp/moneybowl-m4-actionlint/actionlint -ignore 'unexpected key "queue" for "concurrency" section' .github/workflows/*.yml` | Passed with the existing documented actionlint 1.7.12 schema limitation; workflows unchanged |
| `PYTHONPYCACHEPREFIX=/tmp/m4-remediation-001/compile-cache python3 -m py_compile tools/deployment/*.py` | Passed |
| `python3 .github/scripts/validate_docs.py` | Passed |
| `python3 .github/scripts/validate_commits.py 'fix: bind ingestion deployment to commissioned DEV infrastructure'` | Passed |
| `git diff --check` and `git diff --cached --check` | Passed |

Final unit/service counts: **1,519 passed, zero failed, one existing live smoke skip**.
One intermediate run failed because the old mocked retirement container lacked the
newly projected mounts/networks fields. Its synthetic shape was updated; all original
retirement assertions remain. No test was disabled or weakened. New tests cover
four/five layers, historical relocation/missing files, order, authority, paths, byte
substitution, links, project/container ownership, model/resource/runtime drift,
health/HTTP readiness, one worker, unexpected/profiled financial services, API-only
override guards, failed activation, unknown legacy provenance and forged labels,
real-adapter concurrent duplicate reconciliation, capacity/inodes, and QA/Production
denial. Existing tests retain stale-branch, build-failure and superseded-report checks.

All deployment transports in regression tests were mocked; no live model hashes or
legacy source proofs were invented. Separately, the new capacity function was invoked
read-only with state `/tmp/m4-remediation-001` and Docker root `/var/lib/docker`, and
correctly returned `insufficient_build_capacity` on this host. The complete M4 owner
was never run against live DEV. Flutter builds and real SQL/Docker builds were not
rerun: their sources are unchanged, capacity is insufficient and no such deployment
or large build is authorized here. Historical results above are not new executions.

No migration, application/worker source, workflow, live Compose file, credential,
financial evidence, Cron or Director data changed. No cleanup, sudo, publication,
QA/Production access or live deployment occurred. The implementation is reviewable;
actual installation and unattended end-to-end release verification remain blocked.
Final read-only comparison confirmed unchanged IDs/images/states/restart policies
for all six application containers and the retired dispatcher, unchanged hashes for
all five live Compose layer files, both persistent masks, and the disabled/inactive
retirement timer. Remote feature/develop references and canonical checkout remained
at their preflight SHAs before the local commit.

## Compose compatibility fix 002 — 2026-10-11

Starting local and freshly fetched remote feature SHA:
`acd2f1c60f1ec13b58ebcfd7afb0044ed8b23949`. Both checkouts were clean;
canonical/fetched develop remained `8993ce141ceed6a1cae95c2a7edbfbfcf24524f8`
and was verified as an ancestor. Work stayed in the existing M4 feature worktree.
Existing-file baseline: 147 M4, 34 commissioning and 5 commit-quality tests passed,
plus 17-route parity, 27 frozen migration files and documentation validation.

### Defect and correction

Installed Docker Compose 5.5.0 returns dependency images from `config --images
SERVICE`: Caddy returned three, API two, and ClamAV/webhook/M3B receiver one each.
The old fixture returned just the requested image. Updating it to return three
caused the new Caddy success test to fail with `support_image_drift` before the
production change, reproducing the independent finding.

The owner now reads `config --format json --no-env-resolution SERVICE` and selects
exactly `services[SERVICE].image`. Actual JSON includes other named services too;
their order and image membership are irrelevant. Only the requested reference is
returned, inspected locally and compared to the already approved running image ID.
Missing/duplicate keys, wrong project, malformed JSON or references, unresolved
interpolation, missing local images and changed IDs fail closed. No image is pulled.
All inventory, container/hash/resource, retirement, provenance and API-only guards
remain in place. The harness now exercises the production image-inspect decoder too.

Compose interpolation still requires the independently commissioned owner's private
inputs. Service env-file resolution is disabled. Rendered output is transient private
input, never a report/artifact; the command transport discards stderr and the parser
returns only the image reference or a fixed error code. Synthetic private fields and
malformed-output tests verify they do not escape through diagnostics or snapshots.

### Executed checks

Commands ran from the feature worktree. Focused tests are a subset of the full suite;
they are not counted twice. Final unit counts: **196 passed, zero failed, zero skipped**.

| Command | Result |
| --- | --- |
| `PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=tools/deployment python3 -m unittest test_compose_inventory.ComposeInventoryTests.test_dependency_inclusive_caddy_images_match_own_service -v` | Initially 1 error reproducing the defect; after correction 1 passed |
| `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tools/deployment -p test_compose_inventory.py -v` | 38 passed, including 10 new tests |
| `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tools/deployment -q` | 157 passed |
| `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tools/commissioning -q` | 34 passed |
| `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s .github/scripts -p 'test_validate_commits.py' -q` | 5 passed |
| `python3 scripts/generate_outbox_routes.py --check` | 17 canonical mappings match |
| `python3 .github/scripts/validate_migration_history.py` | 27 frozen files unchanged |
| `PYTHONPYCACHEPREFIX=/tmp/m4-compose-fix-002/compile-cache python3 -m py_compile tools/deployment/ingestion_owner.py tools/deployment/test_compose_inventory.py` | Passed; production/test imports also exercised by the unit suites |
| `python3 .github/scripts/validate_docs.py` | Passed |
| `python3 .github/scripts/validate_commits.py 'fix: resolve Compose support images by service identity'` and `python3 .github/scripts/validate_commits.py` | Passed |
| `git diff --check` and `git diff --cached --check` | Passed |
| `PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=tools/deployment python3 /tmp/m4-compose-fix-002/verify_projection.py` | Read-only host projection and synthetic CLI interpolation checks passed, as bounded below |

### Read-only host evidence and limits

All five required live Compose layers were read in their existing order; their file
hashes match the remediation 001 observations. Host queries used `--env-file /dev/null`,
`--no-interpolate --no-env-resolution`, an empty Docker auth path and a sanitized process
environment. No `.env`, container `Config.Env` or registry credentials were read.
Only image metadata and structural findings were exposed, never raw Compose output.

The temporary projection harness fed this credential-free CLI output into the actual
production resolver using a synthetic owner fixture. Caddy, ClamAV and webhook
references resolved to local image IDs matching their unique running containers.
Both M3B image expressions remained unresolved and were correctly rejected. A separate
small synthetic Compose file proved actual public-variable interpolation and a
three-image dependency list work with the resolver. No full owner, build or activation
entrypoint was invoked; the synthetic fixture is not approval of host ownership.

The original retired Oracle container remains exited with PID zero and restart `no`;
both reconciliation service files remain persistently masked to `/dev/null` and the
timer remains disabled/inactive/dead. Root storage remains about 93% used with 3.3 GiB
free. No builds, cleanup, deployments, service changes, secret access, financial
operations, QA/Production changes or remote publication occurred. Heavyweight SQL
containers and builds were deliberately outside this isolated correction's checks.

**Ready for independent code review; live M4 commissioning remains blocked.**
Credential-resolved Compose hashes/image interpolation and full ownership verification
still require the authorized private owner, approved inventory and controlled
installation. Existing capacity, legacy API provenance/initial-binding, registry,
readiness-only credential and independent evidence prerequisites remain unchanged in
the [commissioning record](MONEYBOWL_M4_DEV_REMEDIATION_001.md). Local synthetic success
and structural host compatibility are not a verified unattended environment release.

## DEV commissioning 001 — container inspection correction — 2026-10-11

Started from clean published/reviewed `ad7906bc2e4f53494aa447661e11d816fbc8514e`.
Fresh refs match; canonical develop remains clean at
`8993ce141ceed6a1cae95c2a7edbfbfcf24524f8`. GitHub independently reports PR #207 draft,
open and unmerged, with all five PR workflows successful on that published SHA.
Those CI results do not cover this subsequent local correction.

Permitted read-only commissioning invoked the actual `DockerOwner.container()` and
`retirement()` methods without constructing or running a deployment controller.
Docker returned malformed JSON: the projection closed `security` but omitted the
outer object's closing brace. Appending exactly one brace made the same private
output parse successfully and match the original retired container ID. No raw
inspection/configuration contents or credentials were printed. This is an operational
defect in the published candidate, independent of any missing commissioning capability.

The correction adds that single brace. The regression renders the production template's
JSON and optional-health actions from synthetic Engine fields, rather than returning
a prebuilt JSON document. Both health subcases failed before the source correction;
both pass afterwards. No projected field, ownership check or retirement assertion was
removed. Safe read-only host verification now passes the production retirement method
and all seven original container projections, with unchanged IDs/images/states/restart
policies, both persistent masks and the disabled/inactive timer.

| Executed command / verification | Result |
| --- | --- |
| `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tools/deployment -q` | Existing baseline 157 passed; corrected final 158 passed |
| `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tools/deployment -p test_owners.py -k container_inspect_template -v` | Before fix: 1 test with 2 failing subcases; after fix: 1 passed |
| `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tools/commissioning -q` | 34 passed |
| `python3 scripts/generate_outbox_routes.py --check` | 17 mappings unchanged |
| `python3 .github/scripts/validate_migration_history.py` | 27 frozen migration files unchanged |
| `/opt/moneybowl-toolchains/deno/2.9.6/aarch64-unknown-linux-gnu/deno test --deny-net --deny-env supabase/functions/outbox-dispatcher` | 95 passed; includes readiness-only authority rejection on financial paths and key substitution |
| `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s .github/scripts -p 'test_validate_commits.py' -q` | 5 passed |
| `PYTHONPYCACHEPREFIX=/tmp/m4-dev-commissioning-001-pycache python3 -m py_compile tools/deployment/ingestion_owner.py tools/deployment/test_owners.py` | Passed |
| `python3 .github/scripts/validate_docs.py` | Passed |
| `python3 .github/scripts/validate_commits.py 'fix: close Docker inspection JSON before retirement checks'` | Passed |
| `git diff --check` and `git diff --cached --check` | Passed |

Private non-secret staging, installation proposals and exact remaining authorization
transactions are under `/home/ubuntu/moneybowl-m4-dev-commissioning-001-20261011`.
These host-specific proposals are not installed, independently approved or repository
deployment evidence. Staging acceptance adds 11 tests; unit syntax checks pass with
pre-existing host unit warnings. No privileged installer/private Compose resolver ran.

Read-only findings supersede the older capacity statement: about 12.44 GiB free and
4.89 million free inodes pass the existing 12 GiB code preflight. Only about 0.44 GiB
remains above that floor; no heavyweight build/copy was authorized or started. Three
dedicated users, private mirrors, protected executables, registry, scoped measurement,
readiness provisioning, trusted receipt routing and owner-approved baselines remain
gates. Legacy API provenance remains unknown. Existing frontend identity binds develop
but lacks M4 asset evidence; missing receipt/health URLs return SPA HTML with HTTP 200.
No synthetic receipt or requested SHA has been substituted for live evidence.

No live file, container, systemd unit, credential, Supabase project/financial state,
QA/Production, Director data or GitHub setting changed. No publication/merge occurred.
This narrow correction is local pending independent review; **DEV is not commissioned**.

## Consolidated DEV commissioning — systemd credential correction — 2026-10-11

Starting published/reviewed feature: `535050e0bb6afcd4c019fee6d85015d2172a7672`.
Fresh GitHub inspection found all required CI successful, PR #207 still draft and
unmerged, and develop unchanged at `8993ce141ceed6a1cae95c2a7edbfbfcf24524f8`.
These hosted checks cover the starting commit, not this subsequent local correction.

Authorized installation created the three locked non-login identities and protected
disabled controller sources/configuration at the starting SHA. A real transient
systemd test, without network or Docker access, then failed with
`owner_config_permissions_invalid`. Direct metadata measurement proved systemd 255
provides a root:root `0440` credential inside a root:root `0550` directory on a
read-only mount. Its per-user ACL provides read access without granting write access.
The existing ordinary-file `0600` check rejected that legitimate credential.

The correction retains ordinary private-file validation and adds one narrow case:
`owner-config` under the exact `CREDENTIALS_DIRECTORY`, directly beneath
`/run/credentials/<unit>.service`. It requires canonical paths, regular file type,
root:root ownership, exact file/directory modes, protected root ancestry, a read-only
filesystem, effective read access and no write access. Environment variables alone
cannot approve an arbitrary file. No financial authentication or environment policy
changes. Seven regression tests exercise positive acceptance and negative paths,
ownership, permissions, symlinks, mount availability and effective access.

Root-protected acceptance copies loaded the corrected configuration through actual
systemd credentials and then rejected both disabled owners before any transport.
The ingestion acceptance uses an explicitly synthetic accessible `compose_root`;
the actual `/home/ubuntu` is `0750` and remains inaccessible to the new identity.
No home permission was widened. The evidence test uses its actual disabled config.
Transient test setup initially used a literal `%d` argument (escaped by systemd-run)
and an overly restrictive test `ProtectHome`; these harness failures were diagnosed
separately from the reproduced source defect. No live owner was enabled.

| Command / check | Result |
| --- | --- |
| `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tools/deployment -q` | Starting baseline 158 passed; corrected suite 165 passed |
| `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tools/deployment -p test_owners.py -k SystemdConfigTests -v` | 7 passed |
| `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tools/commissioning -q` | 34 passed |
| `python3 scripts/generate_outbox_routes.py --check` | 17 mappings unchanged |
| `python3 .github/scripts/validate_migration_history.py` | 27 frozen files unchanged |

Protected measurement failed before producing a baseline because required M3B
interpolation inputs are absent from the supplied `.env`; observations were not
converted into approvals. Mirrors now retain real develop ancestry and the archived
M3B object; the repository is currently public, so anonymous HTTPS provides fetch
access without installing a write credential. A pinned official Supabase CLI, public
DEV build settings, empty independent receipt roots, shared build lock and a fresh
local readiness-only key were installed. The key is not provisioned to Edge and no
scoped measurement token is present. The deployed Edge code lacks readiness-only
support. Supabase read-only inspection confirms active DEV dispatch and one active
15-minute recovery Cron; it does not commission the private evidence owner.

Original application container identities and Oracle retirement remain verified.
No API replacement, frontend handoff, Caddy mutation, owner timer enablement, hosted
deployment, QA/Production change or merge occurred. Receipt URLs still require
independent ingress commissioning. API provenance/recovery, approved registry and
Compose inputs, protected Flutter SDK, build headroom, read-only measurement and
independent review remain gates. The corrected source is local for review; installed
controller sources remain at the previously reviewed starting SHA. Exact private
operation evidence is in `/home/ubuntu/moneybowl-m4-dev-execution-20261011`.

## Actions DEV completion — observation timing and safe staging — 2026-10-11

Explicit remote fetch verified feature `bc1870c5ca87962d9768a9000ba02798c7175df4`
and develop `8993ce141ceed6a1cae95c2a7edbfbfcf24524f8`. Both checkouts were clean.
The local implementation changes only observation timing, its offline regressions
and M4 documentation. The workflow itself, deployment owners, financial/SQL code,
Supabase deployment ownership and QA policy are unchanged.

| Executed command / verification | Observed result |
| --- | --- |
| `python3 -m unittest discover -s tools/deployment -v` before editing | 165 passed |
| `python3 -m unittest discover -s tools/commissioning -v` before editing | 34 passed |
| New `test_existing_fifteen_minute_reconciler_can_converge` on original observer | Failed as expected: timed out before the sixteen-minute fixture became ready |
| `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tools/deployment -v` after correction | 171 passed, zero skipped |
| `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tools/commissioning -v` after correction | 34 passed, zero skipped |
| Installed published-controller runtime subset | 162 passed; three repository-file tests covered by the full checkout suite |
| `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s .github/scripts -p test_validate_commits.py -v` | 5 passed |
| `python3 scripts/generate_outbox_routes.py --check` | 17 canonical routes unchanged |
| `python3 .github/scripts/validate_migration_history.py` | 27 frozen migrations unchanged |
| `python3 .github/scripts/validate_docs.py` | 67 documents passed |
| `python3 .github/scripts/validate_commits.py 'fix: allow release observation across DEV reconciliation'` | Passed |
| `systemd-analyze verify` on the existing five private service/timer proposals | Passed; pre-existing monitoring executable-mode and Director description-URL warnings only |
| Published installation manifest and original installation comparison | 25 exact root-owned immutable files in each; original unchanged; no activation stamps |
| Existing ingestion/evidence executable/source pin checks | Passed; frontend SDK remains missing at its protected configured path |
| Legacy API archive validation | 14 OCI blobs and eight decompressed layers verified; 54,473,216 bytes; no load/replacement |
| Read-only production retirement and runtime methods | Seven original container identities/images preserved; retirement passed |
| One real read-only observer attempt against verified develop/endpoints | Failed as expected: `invalid_evidence`, `environment_release=not_verified`, `code_validated=not_observed` |

Actionlint 1.7.12 was downloaded from its official release; ARM64 archive SHA-256
`325e971b6ba9bfa504672e29be93c24981eeb1c07576d730e9f7c8805afff0c6`
matched the published checksum. Unfiltered validation reported one unsupported key:
`queue` under release concurrency. Current [GitHub documentation](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency)
explicitly supports `queue: max` with `cancel-in-progress: false`, and the published
workflow already passed hosted validation. A local rerun ignoring **only that exact
diagnostic** passed with no other findings. No suppression or workflow weakening was
committed; unfiltered actionlint is not reported as passing.

The first test invocation inside the controller-only installation attempted all 165
tests and reported three missing repository-fixture errors (`supabase/config.toml`
and the workflow are deliberately outside that installation). Its 162 runtime tests
were rerun separately and passed; all three repository tests passed in the complete
checkout. The initial recovery verifier assumed a config-blob image identity; Docker
29's OCI index disproved that assumption. The corrected verifier checked the already
exported bytes through the full descriptor tree and decompressed layer hashes. These
were staging-harness corrections, not changes to running applications or provenance.

No Flutter build, new ingestion image build, SQL-container run, Supabase deployment,
private credential round trip, image restoration or live API replacement was run.
Application/SQL sources did not change; unavailable registry/measurement capabilities
and separate replacement review remain explicit gates. Full merge-to-DEV acceptance
is **blocked**, not skipped-as-success. New local source requires independent review
and hosted CI after a separately authorized push. Exact host staging, recovery and
remaining operations are in the [execution record](MONEYBOWL_M4_DEV_REMEDIATION_001.md#github-actions-completion-execution--2026-10-11).
