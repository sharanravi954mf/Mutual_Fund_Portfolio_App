# MFD Investor Onboarding V2-A: implementation and local validation

## Contract and base

This DEV/local candidate implements the PAN-first KYC orchestration portion of the [frozen V2 contract](MFD_INVESTOR_ONBOARDING_V2_KYC_FIRST_FROZEN.md). The frozen document is unchanged. [V1](MFD_LED_INVESTOR_ONBOARDING_V1.md) and its [validation record](MFD_LED_INVESTOR_ONBOARDING_V1_VALIDATION.md) remain the identity/security foundation.

- Fetched `origin/develop`: `802539eefb722b3fad4ef8372a6b2a07fcf68a55`; canonical `/home/ubuntu/moneybowl` was clean and exactly equal to that SHA.
- Fresh branch: `feature/mfd-onboarding-v2a-kyc-orchestration`.
- Fresh worktree: `/home/ubuntu/moneybowl-worktrees/mfd-onboarding-v2a-kyc-orchestration`.
- No experimental worktree was reused, copied or cherry-picked.
- No NSE request, hosted database mutation, push, PR, merge or deployment is part of this work.

## Architecture

The [additive migration](../../supabase/migrations/20261007130243_mfd_onboarding_v2a_kyc_orchestration.sql) adds private `moneybowl_onboarding.kyc_cases`, `kyc_operations` and `ekyc_amcs` tables. Existing encrypted V1 cases hold the investor facts. PAN-only capture does not create a business profile, Auth identity, UCC or integration account. A workspace/PAN HMAC uniqueness constraint converges restarted cases. Canonical PAN resolution examines all non-superseded/non-invalid records, rejects duplicates/conflicts, and binds an existing investor only under the actor's existing assignment. Existing V1 cases are reused. A later identity conflict detected during preparation, dispatch or link projection fails closed; drafts never reserve an identity. V1 drafts without PAN resume at PAN capture.

V1's approved MFD, active account/profile/workspace/membership and relationship authority remains server-derived. The same identity advisory lock, scope locks, case row locks and explicit assignment row locks serialize preparation with saves and revocation. Case projections deny unrelated actors before disclosing identity or provider data. New private tables have RLS and no direct browser/service-role table access. Only explicit authenticated or service RPCs are granted. All privileged functions have an empty search path.

A private onboarding operation is the pre-UCC subject. `integration_operations` and the registered-UCC B01 contract retain their existing required integration-account invariant. The smallest shared evidence extension is an explicit `integration_api_interactions.onboarding_operation_id` foreign key with subject/scope constraints. Requests and raw result bytes use the existing Vault-backed integration encryption and SHA-256 evidence hashes. Operation IDs, request IDs, call IDs, claims and leases are retained. No fake integration account, registration state or client code is created.

`CLIENT_KYC_REPORT` requests contain only `pan_no`, derived from the protected case and frozen into encrypted operation input. Browser transport fields cannot substitute the PAN, add a client code, select an endpoint or assert a KYC result. The request evidence records the same serialized body sent by the worker. Ordinary status responses contain no provider body or link.

Fresh eKYC requires the captured PAN, investor email/mobile and an explicit approved RTA AMC selection. The generated body contains exactly `amcCode`, `panNo`, `invEmail`, `mobileNo`. The documented mobile contract is ten digits; a captured Indian `91` prefix is removed for this provider request only. Missing contacts are retained as encrypted investor facts for later stages. Capture does not invoke account linkage or authenticate ownership. The existing V1 verified-identity matcher and signup/bootstrap functions are unchanged.

The [worker](../../supabase/functions/nse-onboarding-kyc-worker/handler.ts) composes the existing NSE client/authentication and evidence-call helper. It accepts only an outbox event ID with the existing internal worker token. Trusted environment configuration must resolve to the exact NSE UAT origin; Production and arbitrary base overrides are refused. Redirects are disabled. The explicit `integration.nse.onboarding_kyc_check_requested` and `integration.nse.ekyc_registration_requested` routes use existing dispatcher reconciliation. Its database feed composes the unchanged registered-operation/reference-job feed with the new onboarding subject. No wildcard, new scheduler, background provider-status polling or delivery service is added.

## Provider characterization and normalization

Retained local authority inspected: `/home/ubuntu/nse-uat-contract/docs/NSEMF_API_Details_V1.9.7.pdf`, pages 192–194 and the June 2026 removal note on page 282. No sample identity or operational link from that document is copied into fixtures. The user's retained UAT evidence is distinguished from synthetic tests below.

| Contract | Evidence and implemented behavior |
| --- | --- |
| `CLIENT_KYC_REPORT` | v1.9.7 permits PAN-only lookup, independent of UCC. The existing diagnostic policy recognizes precisely `S / 0 / [] / No record(s) found.`. That observation maps to `KYC_NOT_AVAILABLE` before eKYC. Arbitrary empty/error envelopes do not. |
| Non-empty report | Count, object/array shape, required string fields, requested PAN and single-row scope are validated. Multiple/duplicate rows, foreign PAN and malformed payloads reconcile. No authoritative compliant status enumeration was found; structurally valid non-empty results map to `KYC_PROVIDER_REVIEW_REQUIRED`, regardless of HTTP success, row existence, name or DOB. |
| `EKYCREG` | The four-field initiation contract and successful returned link are UAT-characterized by the retained commissioning evidence supplied for this task. Local tests exercise synthetic responses only. Runtime accepts the characterized `RECEIVED` message and the manual's exact `RECEVIED` spelling. |
| Positive completed KYC | **Not empirically commissioned.** No synthetic test is represented as positive provider completion. No guessed positive status or runtime path to compliant is added. Test requirement I is inapplicable until an authoritative enumeration is available. |
| `KYC_CHECK` | Retained UAT evidence says the old endpoint returned `F / NOT AVAILABLE`; v1.9.7 removes that API. Historical evidence is preserved. There is no new runtime dependency on it. |
| Separate fresh-eKYC status | No separate authoritative endpoint is retained. Explicit **Refresh KYC Status** queues another `CLIENT_KYC_REPORT` read. |

The client-authorization sample elsewhere in the manual uses `SUCCESS / VERIFIED` for `primary_holder_kyc_status`. It does not enumerate `CLIENT_KYC_REPORT.kyc_status`; those values are not transferred between API contracts.

The RTA AMC requirement is material: the existing scheme/systematic masters contain AMC codes but do not prove their mapping to fresh-eKYC RTA codes. The private approved-selector catalog therefore has no runtime seed or default. Its entries require an explicit source reference. **A trusted catalog must be commissioned through a reviewed configuration/migration change before eKYC can be initiated.** The UI visibly explains an empty selector. Only synthetic local tests install a synthetic selector; the manually tested UAT code is not hard-coded.

There is no assertion that the CAMS/provider completion flow or OTP delivery worked. A successful link remains `EKYC_IN_PROGRESS` when the investor cannot complete the provider flow, and a later empty KYC observation preserves that state.

## Retry, evidence and secure link

Read operations use `READ_ONLY` and a maximum of three attempts. Provider mutations use `OTHER_MUTATING`. Each claimed attempt receives a call ID and token; request evidence and a conservative `MAYBE_SENT` fence commit before transport. A proved pre-invocation failure may retry within the bound. Network failure after invocation, an expired submitted mutation, uncertain HTTP outcome or invalid success payload requires reconciliation. The same case can have only one fresh registration operation; a reload or different request UUID cannot blindly create another.

A persistence acknowledgement loss retries only the same idempotent evidence write, never the transport callback. Result evidence is append-only and duplicate completion checks the original response hash/status. A late original result for an expired mutation may reconcile that same operation using its original call/token; it does not submit again. A read can retry after an expired claim, but a submitted mutation cannot.

The returned workflow URL must use HTTPS, the exact `nseinvestuat.nseindia.com` host, and the `/nsemfdesk/ekycVerifyByUser/` path family with a bounded opaque segment. Credentials, ports, queries, fragments, other hosts and paths are rejected. No redirect probe is made. Raw bytes containing the link remain solely in encrypted RESULT evidence; the link is not duplicated into the case, outbox, audit, worker response or normal list response.

`get_onboarding_ekyc_link` returns a link only to the live initiating/assigned MFD or the investor's authenticated account under an active V1 link. Unrelated users and revoked MFDs receive the same authorization failure, without link/existence disclosure. The Flutter controller fetches the secret only for **Open eKYC**, validates the boundary again, launches the action and does not retain/render the link as body text. No second login, email or SMS delivery is introduced.

Transition audit events contain workspace, case/investor, actor, operation, previous/projected state and bounded classification. PAN, contacts, link and provider bodies are excluded.

## UI and later stages

```text
Clients → Add Investor → PAN → Continue / Check KYC
  → Checking KYC → Refresh progress
  → Not available → only missing Email / Mobile + explicit AMC
  → Proceed to eKYC → Preparing eKYC → Refresh progress
  → eKYC in progress → Open eKYC / Refresh KYC Status
  → provider review or reconciliation when evidence is unknown/ambiguous
```

The UI can hand a future authoritative `KYC_COMPLIANT` projection to the existing remaining-detail form. It hides private account-linkage text and editable/reviewed KYC type/status/CKYC claims in that V2 presentation and states that authoritative provider data is required. The V2 case guard also rejects provider-state fabrication through legacy save RPCs, and the legacy identity-resolution entry cannot advance a V2 case before compliant evidence. The underlying V1 capture model remains intact for its existing tests and downstream consumers. Full progressive post-KYC, UCC/consent redesign, B07 changes and readiness redesign are out of scope.

## Validation

All commands use the candidate worktree unless explicitly marked baseline. SQL uses the repository's pinned Supabase PostgreSQL 17.6 container, a tmpfs database and `--network none`. The full ordered migration chain is applied. The parent harness removes only its own disposable container. No linked/shared Supabase reset is performed.

Tool paths used:

- Flutter/Dart: `/home/ubuntu/.local/share/flutter-moneybowl/bin`.
- Deno: `/opt/moneybowl-toolchains/deno/2.9.6/aarch64-unknown-linux-gnu/deno`.
- Dispatcher tests: existing `/tmp/b061-test-venv/bin/python` environment.

| Exact command | Result |
| --- | --- |
| `git fetch origin develop` in `/home/ubuntu/moneybowl` | PASS; base SHA above; clean canonical worktree |
| `/home/ubuntu/.local/share/flutter-moneybowl/bin/flutter pub get --offline` | PASS; cached dependencies, no tracked manifest change |
| `bash scripts/test_investor_onboarding_sql.sh` | PASS; complete ordered migrations, focused KYC, all B01–B07 suites, V1/security/concurrency and onboarding PL/pgSQL lint |
| `/home/ubuntu/.local/share/flutter-moneybowl/bin/flutter test --no-pub test/investor_onboarding test/authentication test/investor_identity_models_test.dart test/user_management_workspace_models_test.dart` | PASS, 90 tests |
| `/home/ubuntu/.local/share/flutter-moneybowl/bin/flutter test --no-pub` | PASS, 3,008 tests |
| `/home/ubuntu/.local/share/flutter-moneybowl/bin/flutter analyze --no-pub` | 92 pre-existing diagnostics, zero errors; same diagnostics as fresh canonical develop |
| `/home/ubuntu/.local/share/flutter-moneybowl/bin/flutter build web --no-pub --dart-define=MONEYBOWL_ENV=dev` | PASS; built `build/web` |
| `/opt/moneybowl-toolchains/deno/2.9.6/aarch64-unknown-linux-gnu/deno test --cached-only --allow-env --allow-read supabase/functions/_shared/nse supabase/functions/nse-onboarding-kyc-worker` | PASS, 484 tests; no network permission |
| `/opt/moneybowl-toolchains/deno/2.9.6/aarch64-unknown-linux-gnu/deno test --cached-only --allow-env --allow-read supabase/functions/_shared/nse supabase/functions/nse-*` | PASS, 912 tests; no network permission |
| `PYTHONPATH=services/outbox-dispatcher /tmp/b061-test-venv/bin/python -m pytest services/outbox-dispatcher/tests -q` | PASS, 63 tests |
| `python3 .github/scripts/validate_migration_history.py` | PASS; frozen history unchanged |
| `python3 -m unittest discover -s .github/scripts -p test_validate_commits.py` | PASS, 5 tests |
| `python3 .github/scripts/validate_docs.py` | PASS, documentation links/structure/anchors |
| `python3 .github/scripts/validate_commits.py` | PASS; Conventional Commit subject and committed branch range |
| `git diff --check` | PASS |

The SQL harness includes the [focused KYC suite](../../supabase/tests/onboarding_kyc_test.sql), existing V1 onboarding, all NSE B01–B07 SQL suites, UCC/order/report/master regressions, dispatcher, signup, containment, MFD approval, platform authority and their existing concurrency tests. It lints onboarding PL/pgSQL against each trigger's actual table instead of assuming every private trigger belongs to `events`. The [new concurrency suite](../../scripts/test_onboarding_kyc_concurrency.sh) covers two checks, two eKYC initiations, save/check, refresh/initiate and assignment revocation during preparation.

The new SQL tests cover PAN-only capture without profile creation, duplicate/conflicting identities, compatible V1 reuse, unrelated workspace/MFD denial, immutable protected PAN, the exact no-record diagnostic, malformed/foreign/duplicate rows, unknown KYC status, missing/unapproved eKYC prerequisites, exact four-field requests, encrypted link evidence, strict link validation, idempotency, bounded proved-not-sent retry, uncertain-send/expired-mutation fencing, and MFD/linked-investor/revoked link authorization. Existing V1 signup/account-link tests remain unchanged. Flutter tests cover the PAN-first and all implemented KYC stages, explicit selector blocking, secure open, refresh, reconciliation, double-click/retry/disposal fencing and compact/desktop large-text layouts. Worker tests inject their own transport; no real NSE HTTP is permitted.

Environmental notes: initial sandbox Git fetch failed DNS and Docker lacked socket access; the already-authorized fetch and disposable local tests succeeded with execution permission. An initial dispatcher invocation used the system Python without pytest; the corrected command uses the existing test environment and its required module path. These failed invocations are not reported as passes. Build reports existing `dart:js` WebAssembly compatibility and Cupertino font notices from unchanged modules. The full Flutter analyzer baseline was rerun on the exact develop base and compared without line/column offsets; no diagnostics were suppressed.

## Publication and commissioning boundary

This is a clean local candidate after validation/commit, not a deployed feature. No hosted DEV patch, Production/main mutation, CI/RLS weakening, provider commissioning, push or PR is authorized or performed. A later reviewed deployment must include the additive migration, worker and explicit dispatcher routes, legitimate RTA selector configuration, and the existing trusted UAT credentials/encryption keys. Provider completion/status enumeration remains a separate characterization task; no local test or UI hand-off establishes it.
