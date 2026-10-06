# MFD-led Investor Onboarding V1 validation

Base: `a7d7bf0eba02220e7b05034f8e32e77cb47d406a`, fetched clean `develop`. All candidate commands run from `/home/ubuntu/moneybowl-worktrees/mfd-led-investor-onboarding-v1` unless stated otherwise. Full [architecture, invariants and commissioning prerequisites](MFD_LED_INVESTOR_ONBOARDING_V1.md) accompany this record.

## Toolchain and safety

Flutter 3.44.6 / Dart 3.12.2 at `/home/ubuntu/.local/share/flutter-moneybowl/bin`; Deno 2.9.6 at `/opt/moneybowl-toolchains/deno/2.9.6/aarch64-unknown-linux-gnu/deno`; Supabase CLI 2.115.0. Dependencies were resolved from the existing local cache with `flutter pub get --offline`; no dependency manifest changed.

PostgreSQL tests use the repository's pinned Supabase PostgreSQL 17.6 image in a new network-disabled, tmpfs-backed container. The platform fixture supplies the Auth/Storage platform schema absent from the bare PostgreSQL image. The complete ordered migration chain is reapplied on each run; historical containment fixtures are inserted at their original boundary and tested after upgrade. This is the disposable fresh-reset validation, not a reset of a linked/shared Supabase environment. Each parent harness removes only its own container. No hosted DEV/Production data or NSE transport is involved.

Initial sandbox attempts could not resolve GitHub/pub.dev or bind Flutter test sockets. The authorised fetch and local-test execution completed with the necessary execution permissions; cached dependencies resolved without downloading new packages. These were tooling restrictions, not test passes or product regressions.

## Baseline

Executed in `/home/ubuntu/moneybowl` without editing tracked files:

| Exact command | Result |
| --- | --- |
| `git fetch origin develop` | Local and origin develop both `a7d7bf0eba02220e7b05034f8e32e77cb47d406a`; canonical worktree clean |
| `bash scripts/test_mfd_application_sql.sh` | PASS: existing full-schema MFD/platform/containment/signup/workspace/order SQL and concurrency/MFA suites |
| `/home/ubuntu/.local/share/flutter-moneybowl/bin/flutter test --no-pub` | PASS: 2,987 tests |
| `/home/ubuntu/.local/share/flutter-moneybowl/bin/flutter analyze --no-pub` | 92 pre-existing diagnostics; no errors |
| `bash /tmp/moneybowl-onboarding-all-sql.sh /home/ubuntu/moneybowl` | Existing broad runner fails at `browser_api_privilege_contract_test.sql`, described below |

## Candidate

| Exact command | Result |
| --- | --- |
| `bash scripts/test_investor_onboarding_sql.sh` | PASS: full migration chain, dedicated A–L tests, PL/pgSQL lint, 16 SQL/upgrade suites, existing signup/containment/platform/MFD races, MFA read-only inspections, new concurrent onboarding/signup and revocation fencing |
| `/home/ubuntu/.local/share/flutter-moneybowl/bin/flutter test --no-pub test/investor_onboarding test/authentication test/investor_identity_models_test.dart test/user_management_workspace_models_test.dart` | PASS: 82 tests |
| `/home/ubuntu/.local/share/flutter-moneybowl/bin/flutter test --no-pub` | PASS: 3,000 tests |
| `/home/ubuntu/.local/share/flutter-moneybowl/bin/flutter analyze --no-pub` | Same 92 baseline diagnostics; zero new diagnostics and zero errors (compared after removing shifted line/column numbers) |
| `/home/ubuntu/.local/share/flutter-moneybowl/bin/flutter build web --no-pub --dart-define=MONEYBOWL_ENV=dev` | PASS: `build/web`; existing dart:js/Wasm compatibility and Cupertino font coverage notices, no new package/font or Wasm compatibility work |
| `/opt/moneybowl-toolchains/deno/2.9.6/aarch64-unknown-linux-gnu/deno test --cached-only --allow-env --allow-read supabase/functions/_shared/nse` | PASS: 476 tests; no provider access permission |
| `python3 .github/scripts/validate_migration_history.py` | PASS: historical frozen migrations unchanged |
| `python3 -m unittest discover -s .github/scripts -p test_validate_commits.py` | PASS: 5 tests |
| `python3 .github/scripts/validate_docs.py` | PASS: documentation structure, links, UTF-8 and anchors |
| `git diff --check` | PASS |
| `bash /tmp/moneybowl-onboarding-all-sql.sh /home/ubuntu/moneybowl-worktrees/mfd-led-investor-onboarding-v1` | Same baseline broad-runner failure; no new privilege-contract failure |

The temporary all-SQL harness copies the existing disposable-container bootstrap/migration loop, takes only a local repository path, and runs the repository command `SUPABASE_DB_CONTAINER="$container" sh supabase/tests/run_all.sh` after applying the complete migration chain. It changes no test/grant and contacts no hosted database. Logs are retained locally under `/tmp/mfd-onboarding-*.log` for this session.

The broad SQL runner fails identically on base and candidate with:

```text
browser_api_privilege_contract:authenticated_acl_missing:workspace_memberships:INSERT
```

That old test expects a direct authenticated membership INSERT grant removed by the newer authorization-containment migration. Restoring it would weaken the security boundary. The test and grants remain unchanged. The broad runner stops there; **a pass for every historical SQL file is not claimed**. The dedicated harness separately exercises the current containment, signup, MFD/platform, workspace authorization, order and affected NSE contracts. Static analysis similarly remains nonzero because of the established 92 baseline diagnostics, not new onboarding findings.

## Dedicated evidence

- A/J: business investor without login; relationship ready; missing DOB/KYC/bank evidence remains visible.
- B: existing Explorer linked by verified Auth evidence using ordinary investor input; same login routes Investor.
- C/L: investor precedes signup; first completed matching bootstrap routes Investor; no second profile.
- D/I: duplicate/retried/restarted input reuses canonical identity, case, relationship, bank and address; concurrent callers agree.
- E: verified email/mobile identifying different accounts returns explicit reconciliation on both MFD and signup paths.
- F: another existing profile and active link remain intact; no relink or detachment.
- G/H: cross-workspace and unrelated actors, direct private matching and service-only preparation attempts denied under actual API roles; ended membership/assignment and operations role denied.
- K: verified signup without an investor remains a profile-free Explorer.
- A single verified contact does not link newly asserted MFD identity; later verified mobile on the same auth user can complete linkage.
- Historical duplicate PAN investors produce reconciliation; frontend payload cannot clear it, choose an account or assert verification.
- Validated inputs materialize transactionally. Captured bank and reported KYC completion remain unverified. Verified registration changes require review.
- Service preparation refuses missing evidence. With synthetic trusted evidence, the existing CLIENTCOMMON183 source loads and repeated preparation returns exactly one operation. No HTTP submission occurs.
- New private table RLS/ACL boundaries, public/service execution grants, immutable audits and omission of raw financial values are tested.
- Flutter tests cover same-account phone-change SDK calls with mocked transport, safe errors/cooldown/disposal, loading/unavailable states, save/retry/review, direct Add Investor entry, sensitive masking, identity conflict routing, and 320/1200px light/dark layouts at increased text scale.

## Local commissioning limits

No Priya/Lala records were read, created, linked, verified or submitted. Real details were not put in fixtures, logs, snapshots or application logic. Once admitted to DEV, the real UI can exercise capture/resume/review, canonical resolution and safe account linking. Real DOB, identity/contact compatibility, address, tax/occupation/holding choices, KYC/CKYC evidence, bank verification, nomination/consent/declarations and provider codes must be obtained legitimately; missing facts stay incomplete. Actual Supabase SMS delivery and hosted auth confirmation were not exercised by mocked SDK tests.

No push, PR, merge, Production deployment, main mutation, CI bypass, force push or unrelated NSE behavior change is part of this candidate.
