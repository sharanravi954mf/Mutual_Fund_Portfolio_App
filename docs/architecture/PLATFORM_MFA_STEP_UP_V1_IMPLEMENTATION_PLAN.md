# Platform MFA step-up V1 implementation plan

Original plan saved 2026-10-04 before implementation edits. Local candidate only.

## Verified starting point

Canonical `/home/ubuntu/moneybowl`: clean `develop`, HEAD and fresh read-only
`git ls-remote origin refs/heads/develop` both
`cdf363680236708dea9dbbd9d8b0d6e8a4a276a7` (PR #188). New isolated branch
`feature/platform-mfa-step-up-v1` at
`/home/ubuntu/moneybowl-worktrees/platform-mfa-step-up-v1`; neither existed.
Flutter executable `/home/ubuntu/.local/share/flutter-moneybowl/bin/flutter`:
Flutter 3.44.6 (ee80f08bbf), Dart 3.12.2. Offline resolution actually produced
supabase_flutter 2.18.0, supabase 2.16.2, gotrue 2.27.2. `pubspec.lock` is ignored
by repository policy; preserve that policy and archive resolution outside Git.

Pre-edit baseline: 74 Flutter auth/platform/MFD tests passed (exit 0). Initial
sandbox attempt could not bind Flutter's local test socket (0 tests executed).
The inspected full-schema SQL harness passed (exit 0), including all four
concurrency scripts. It creates a fresh `--network none` PostgreSQL 17.6.1.155
container using tmpfs, runs composed migrations and rolls back test fixtures,
then removes only its own container. No existing service is a test target.

Evidence root:
`/home/ubuntu/moneybowl-commissioning-evidence/platform-mfa-step-up-v1-20261004T-local-165340`.
Record command, exit code, count, SHA256, base and final candidate/tree there.

## Intended file inventory

- `lib/features/authentication/services/auth_session_fence.dart`: shared
  transport ownership fence for auth responses; no second token store.
- `lib/main.dart`: install the fence on the existing client and disable SDK
  debug output; preserve configuration, callback and routing contracts.
- `lib/services/supabase_service.dart`: coordinate explicit authentication intent.
- `lib/providers/auth_provider.dart`: session/identity/request generations,
  bounded focused platform refresh and lifecycle invalidation.
- `lib/features/platform_administration/models/platform_context.dart`: helper
  for suppressing sensitive actions while retaining AAL1 read navigation.
- `lib/features/platform_administration/mfa/mfa_models.dart`: typed safe states,
  factors, errors, transient setup and internal return destination.
- `lib/features/platform_administration/mfa/mfa_repository.dart`: injectable
  interface and current-user SDK adapter; no transport in widgets.
- `lib/features/platform_administration/mfa/mfa_controller.dart`: bounded state
  transitions, explicit enrollment/verification, current owner checks.
- `lib/features/platform_administration/mfa/platform_security_screen.dart` and
  `mfa_setup_panel.dart`: responsive security, factor selection, local QR,
  manual setup/copy, six ASCII digits and explicit completion navigation.
- `lib/features/platform_administration/presentation/platform_administration_screen.dart`:
  actionable Account security and focused refresh.
- `lib/features/mfd_applications/presentation/mfd_application_screens.dart`:
  same security flow for blocked decisions, typed return, owned asynchronous
  reads/actions, original request retention and current application reload.
- `pubspec.yaml`: one pinned QR rendering dependency, qr_flutter 4.1.0
  (BSD-3-Clause, Flutter/Dart null safety compatible; transitive `qr` expected).
  Render the validated returned otpauth URI locally, not the SDK SVG/data URI.
  No blanket upgrade. Record resulting dependency diff and licenses.
- `test/platform_mfa_controller_test.dart`, `test/platform_mfa_widget_test.dart`,
  `test/platform_mfa_sdk_test.dart`, `test/support/platform_mfa_fakes.dart`:
  deterministic controller/widget and actual SDK mocked HTTP coverage.
- `test/authentication/auth_session_test.dart`, `test/mfd_application_test.dart`,
  `test/platform_administration_screen_test.dart`: integration regressions.
- `scripts/test_platform_mfa.sh`: discoverable local Flutter validation entry.
- `supabase/operations/platform_mfa_commissioning_preflight.sql`,
  `supabase/operations/platform_mfa_mfd_commissioning_postcheck.sql`: SELECT-only
  read-only transactions; explicit project attestation and UUID parameters.
- `supabase/tests/platform_mfa_commissioning_test.sql`,
  `supabase/tests/mfd_application_approval_v1_test.sql`,
  `scripts/test_mfd_application_sql.sh`: disposable-only inspection and guard
  tests (extend only where existing coverage is insufficient).
- This plan, `docs/architecture/PLATFORM_MFA_STEP_UP_V1.md`,
  `docs/architecture/PLATFORM_MFA_STEP_UP_V1_DEV_COMMISSIONING.md`, and
  `docs/CHANGELOG.md`.

No applied migration, server function, grant, ACL, infrastructure or deployment
workflow changes. Add dated deviations below if file/design scope changes.

## Components, ownership and session synchronization

The gateway uses the sole existing Supabase client. Inspect installed GoTrue
source as the executable contract: `enroll` returns unverified TOTP and prefixes
its SVG as `data:image/svg+xml;utf-8,`; `verify` saves a Session then emits
`mfaChallengeVerified`; `listFactors` refreshes the session and returns all
factors plus verified-only subsets. The inspected refresh implementation fences
late session writes; `verify` has no equivalent guard. Install a shared HTTP
response ownership fence before SDK initialization so obsolete responses are
rejected before their session body reaches GoTrue. Explicit login/logout intent
invalidates old requests; session object changes catch callback/account changes.
Do not compensate by signing out a newer user. Do not use timeout as cancellation.

AuthProvider tracks account lifetime independently from session/context request
generation. Every session event invalidates stale platform loads, suppresses
step-up while checking, and schedules a focused/coalesced projection read.
Same-user MFA/token events avoid repeated business bootstrap. Never call
`listFactors` from token callbacks. Platform mutations continue relying on
`get_my_platform_context` and the unchanged server guard, not decoded claims.
Current SDK AAL2 + supported verified factor + affirmative fresh server
`step_up_verified` are required for security-flow success. Any disagreement is
uncertainty and suppresses decisions. Lifecycle suspension hides secrets and
disables actions; resume performs one bounded status reconciliation.

Controller states: checking -> ready(no factor / pending / verified TOTP /
unsupported) -> enrolling or verifying -> reconciling -> ready/confirmed or
safe error. Access/session loss is terminal for that controller/account lifetime.
Multiple factors require explicit selection, with safe type/status/ordinal
labels instead of trusting factor names. Page entry, refresh and rebuild never
enroll. Set up checks fresh factors and base authority before a single enroll.
A verified factor prevents duplicate enrollment. Pending factors can explicitly
be selected for completion, or the user acknowledges missing setup material and
requests a fresh setup. Never call unenroll. Unknown status cannot mean no factor.

One user tap owns an operation until it settles; disable duplicate controls.
Six ASCII digits stay strings. Each deliberate verification creates the required
challenge for the exact selected/owned factor; errors never reenroll. Uncertain
outcomes get one reconciliation, not mutation retry. Honor Retry-After when
available; show sanitized invalid-code, expired, rate-limit, disabled, capacity,
access and network messages without exception interpolation.

## Secret lifetime and navigation

Setup secret/URI lives only in a screen-owned controller; OTP only in its input
controller until explicit submission. Clear input after each attempt and release
setup references on success, cancellation, disposal, logout or account change.
No diagnostics/toString/URL/analytics/log serialization of setup or tokens.
Copy key only on explicit action. No clipboard cleanup that overwrites unrelated
content. No claim of guaranteed secure erasure. Same-phone manual time-based
setup is explained. Cancellation may leave a pending server factor; reload
cannot recover its secret. Lost-device removal/recovery is deferred.

Return destinations are typed Account security or an internal application ID.
Return after server confirmation requires a user action, reloads the same
application/version/terminal state and current permissions, and never starts or
decides a review. Keep form drafts for the same account in memory. Frozen sent
UUID/version/payload stays unchanged across MFA; require renewed confirmation
and reconcile terminal/stale state. Bind applicant, queue, detail, Start review
and form async work to account lifetime, including account A -> B -> A changes.

## Requirement-to-test matrix

| Requirement | Planned executable evidence | Acceptance |
| --- | --- | --- |
| Entry/rebuild/refresh zero enroll; double click once | controller + widget | exact call counts, disabled pending controls |
| Existing/multiple/pending/unsupported factors | controller + widget | explicit selection, no accidental enrollment/removal |
| Local QR, manual reveal/copy, same phone, large text/dark | widget synthetic URI + validation tests | no remote rendering, readable layouts, white QR backing |
| Leading zero/invalid input | controller + widget + SDK wire | string preserved; invalid makes zero verify calls |
| Invalid/expired/rate limit/disabled/network errors | controller + SDK | safe errors, bounded reconciliation, zero mutation retries |
| Cancel/reload/resume/restart/uncertain outcomes | controller + widget | honest pending state, no timeout replacement |
| Actual SDK verify session + event | SDK MockClient | real GoTrue save/event observed; fresh projection required |
| Enrollment alone/AAL disagreement/server denial | controller + widget + SQL | no decision enablement |
| AAL1 late read / old AAL2 vs new denial | AuthProvider controlled HTTP | latest current request wins |
| Delayed SDK verify/refresh vs logout/new login | real SDK controlled HTTP | old session never installed; newer account preserved |
| listFactors token event feedback | SDK + provider | bounded refresh/projection, no recursion/bootstrap loop |
| Access expiry/capability/factor loss/background | controller + provider + widget | disable actions, explicit recovery boundaries |
| Secrets absent in diagnostics/navigation/logs | synthetic diagnostic assertions + diff audit | no setup/OTP/token output |
| Both entry points and typed return | integrated widget | same feature, correct application reload, no mutation |
| AAL1 reads/Start review and decision confirmation | existing + extended MFD tests | original contract and notes preserved |
| Concurrent/stale result, same request retry | MFD widget + SQL concurrency | immutable UUID/payload; no auto-replay |
| Account switches and delayed actions | MFD widget + auth regressions | no actor state reuse/navigation clobber |
| Explorer/signup/callback/platform-first routing | pre-existing auth + full suite | baseline preserved |
| Fabricated/expired/wrong-owner session; removed factors/grants | disposable full-schema SQL | current authorization rejection preserved |
| Commissioning inspection scripts | disposable SQL fixtures + static audit | SELECT-only/read-only, safe columns, missing/mismatch results |

## Commands and acceptance gates

Use the verified Flutter binary (PATH is not assumed):

```bash
/home/ubuntu/.local/share/flutter-moneybowl/bin/flutter pub get --offline
/home/ubuntu/.local/share/flutter-moneybowl/bin/flutter test --no-pub --reporter expanded test/authentication/ test/platform_administration_screen_test.dart test/mfd_application_test.dart
bash scripts/test_mfd_application_sql.sh
# After implementation:
bash scripts/test_platform_mfa.sh
/home/ubuntu/.local/share/flutter-moneybowl/bin/dart format --output=none --set-exit-if-changed <changed Dart paths>
/home/ubuntu/.local/share/flutter-moneybowl/bin/flutter analyze --no-pub <changed Dart paths>
/home/ubuntu/.local/share/flutter-moneybowl/bin/flutter test --no-pub --reporter expanded
python3 .github/scripts/validate_docs.py
python3 .github/scripts/validate_migration_history.py
/home/ubuntu/.local/share/flutter-moneybowl/bin/flutter build web --release --no-pub --dart-define=SUPABASE_URL=http://127.0.0.1:54321 --dart-define=SUPABASE_ANON_KEY=synthetic-local-public-key
```

Mocks fail unexpected external requests; no hosted fallback. If existing local
Auth cannot be proven disposable and task-owned, record
`LOCAL_REAL_AUTH_REHEARSAL=NOT_RUN` with reason. Existing unrelated Auth stack is
not authorization to mutate it. Mocked SDK and synthetic SQL are not real TOTP
verification. Hosted DEV commissioning remains NOT EXECUTED, requiring separate
authorization and deployment. Canonical files remain clean at base throughout.

## Staged checklist (original, retained)

- [x] Verify base, remote identity, clean canonical; create isolated worktree.
- [x] Inspect instructions, SDK source, current official docs and isolation.
- [x] Run pre-edit auth/platform/MFD Flutter and full-schema SQL baselines.
- [x] Save this original plan before implementation edits.
- [ ] Implement response/session fencing, focused refresh, controller/gateway/UI.
- [ ] Integrate owned MFD navigation, drafts and immutable request retries.
- [ ] Complete matrix with controller/widget/real SDK/disposable SQL evidence.
- [ ] Write architecture, read-only SQL, NOT EXECUTED DEV runbook, changelog.
- [ ] Full tests, analysis, docs/migration validators, safe local web build.
- [ ] Review complete diff, secrets/dependency/guard/canonical audit.
- [ ] Stage reviewed explicit paths; one local commit only.

## Exclusions

No push, PR, merge, deploy, hosted read/write commissioning, real signup/email,
real MFA, MFD business decisions, Production access, provider calls, new grants,
tenant/investor relationships, factor removal/reset/recovery, service changes,
new sessions/agents, SQL authorization changes or migration edits.

## Implementation deviations

Append dated evidence here; retain all original plan text above.

### 2026-10-04 — implemented deviations and checkpoints

- Added `lib/features/mfd_applications/presentation/mfd_account_scope.dart` to
  share account-lifetime and lifecycle cleanup across all four MFD routes, and
  `scripts/test_platform_mfa_commissioning.py` to validate the operational SQL
  output and disposable-container identity. The original planned SQL fixture
  remains `supabase/tests/platform_mfa_commissioning_test.sql`.
- Updated the shared `test/authentication/route_guard_test.dart` fake for the new
  provider interface. Existing auth-session and platform-shell test files did not
  need edits; their regressions run alongside the new SDK/widget files.
- The shell delegates lifecycle observation to AuthProvider; security and MFD
  routes retain feature revalidation. This avoids duplicate shell refreshes.
- SDK initialization now uses its supported `publishableKey` parameter with the
  unchanged existing environment value; this removes a deprecation on touched
  code without changing project selection or credentials.
- HTTP Retry-After dates and seconds use existing `intl`. One timer wakes UI
  controls at the deadline; it never performs a retry or polling request.
- Resolved dependency delta is exactly qr_flutter 4.1.0 and transitive qr 3.0.2,
  both BSD-3-Clause. No existing package upgraded and no lockfile policy change.
- SDK refresh's built-in bounded retry behavior is retained; application code
  never retries MFA mutations automatically. Setup uses validated otpauth URI
  rendering, so SVG parsing is not needed.
- SQL coverage extends wrong-account session denial for both decisions. The
  baseline already covered AAL1, fabricated assurance, expired sessions, removed
  factors/grants, exact receipts and concurrency; no authorization SQL changed.
- Initial implementation test failures (fixture response metadata, fake provider
  interface, lazy widget scrolling/duplicate synthetic factor ID, and API/fixture
  compile errors) were corrected without weakening assertions. Logs are retained
  externally. A 128-test focused checkpoint passed before the final extra
  failed-target-reload and SDK-error regressions/full suite.
- Real local Auth rehearsal is NOT_RUN: the visible stack belongs to another
  validation environment and was not proven disposable/task-owned. No existing
  service or hosted DEV substitute was used.

### 2026-10-04 — final validation and additional review corrections

- Full-suite compilation identified a second independent AuthProvider fake in
  `test/features/orders/order_widgets_test.dart`. Added only the new interface
  members/observer defaults; order assertions and product code were unchanged.
  The initial full-suite failure is preserved in external evidence.
- Final diff review hid setup/verification controls if review capability is
  revoked while its security destination is open, and made factor selection
  tolerate a concurrently invalidated status. Added the capability-revocation
  widget regression. Account security for a base admin remains available.
- Simplified the new inspection scripts' explicit empty-application validation
  and corrected the postcheck parameter comment. Reran the complete disposable
  harness after this edit; no applied migrations or authorization guards changed.
- The exact original plan prefix still hashes to
  `e2fa4280dd186a75fa52786ec48bd1d04e1d0a4a23cc733b10c5e4884e652709`.

## Completed requirement-to-test evidence — 2026-10-04

All rows below passed locally. They supplement, rather than replace, the original
matrix. `C`, `W`, and `S` refer respectively to
`test/platform_mfa_controller_test.dart`, `test/platform_mfa_widget_test.dart`,
and `test/platform_mfa_sdk_test.dart`. The focused runner executes all three plus
existing auth/platform/MFD tests. All external HTTP in S uses a deterministic
MockClient that rejects unexpected paths and hosts.

| Original requirement | Completed evidence |
| --- | --- |
| Entry/rebuild/refresh and double clicks | C entry/unknown state and shared pending operation; W entry/rebuild exact enroll counts |
| Existing/multiple/pending/unsupported factors | C fresh verified prevention, explicit multiple selection, pending completion/restart, unsupported-only denial |
| Local QR/manual/copy and layouts | C URI rejection cases; W synthetic QR/manual/copy, leading zeros, narrow dark 2x text/inactive display |
| Input validation | C six malformed inputs make zero verifies; W pasted leading zeros; S exact string wire assertion |
| Error handling | C six typed failures and bounded reconciliation; S actual SDK invalid code, expired challenge, disabled configuration, factor limit and Retry-After |
| Uncertainty/cancel/reload/resume/restart | C uncertain enrollment reconciles once, shared operation across route recreation, pending restart/background; W pending guidance/cancel |
| SDK session/event installation | S real SDK verify emits mfaChallengeVerified, installs AAL2 and confirms a fresh projection |
| Enrollment/assurance/server denial | C enrollment alone and disagreement; S both disagreement directions/removed factor; W authoritative decision denial |
| Stale reads and late failures | S late AAL1 vs AAL2, old AAL2 vs denial, old failed request vs new confirmed projection |
| Late SDK side effects | S delayed verify and delayed refresh, each against logout and account B login |
| Refresh recursion/bootstrap | S bounded refresh/projection counts and unchanged bootstrap count during step-up |
| Access/lifecycle loss | C account generation and grant loss; S background/resume/removed factor/session errors; W missing/revoked capability and existing form assurance-loss regression |
| Secret diagnostics/navigation | C redacted setup/controller diagnostics; S no raw response output; W internal destination and synthetic setup only; full source/log review |
| Shared entry and typed return | W platform tile and MFD detail open same feature, reload current application, zero automatic mutations |
| AAL1 reads/Start review and confirmations | Existing MFD tests preserve explicit Start review, AAL1 denial, approval evidence/checkbox and rejection reason |
| Concurrent/stale results and request identity | W terminal application on return, failed reload suppression, original UUID/version/note and renewed confirmation; SQL four concurrency scripts |
| Actor binding | W account-switch Start review; existing applicant/form switch regressions; C ownership and S newer-login preservation |
| Explorer/signup/callback/routing | 74 existing focused regressions retained, full suite 454 passed |
| SQL assurance/grants/containment | Existing platform/MFD SQL rejects AAL1, fabricated/expired/removed-factor/grant assurance; added both wrong-operator-session decision checks |
| Read-only commissioning scripts | New fixture/Python checks both SELECT-only/read-only scripts, invalid/missing/same/mismatched IDs, project attestation, approve/reject exact integrity and unchanged baselines |

Final commands, counts and exit codes (full commands and sanitized output in the
evidence root's `commands.jsonl` and named logs):

| Check | Result | Log |
| --- | --- | --- |
| `bash scripts/test_platform_mfa.sh` | 133 passed: 26 controller, 14 widget, 19 actual SDK/mock transport, 74 existing; exit 0 | `focused-release.log` |
| `flutter test --no-pub --reporter expanded --concurrency=2` | 454 passed, no skips/failures; exit 0 | `full-flutter-release.log` |
| `dart format --output=none --set-exit-if-changed` on all changed Dart | 20 files, 0 changed; exit 0 | `format-release.log` |
| `flutter analyze --no-pub` on all changed Dart | 20 items, no issues; exit 0 | `analysis-release.log` |
| `bash scripts/test_mfd_application_sql.sh` | 11 SQL suites, 4 concurrency scripts, 2 inspection queries plus synthetic commissioning assertions; exit 0 | `sql-release.log` |
| Local release web build with loopback URL/synthetic public key | Built `build/web`; exit 0 | `web-build-release.log` |

The web build reports existing `dart:js` Wasm incompatibilities in
`admin_dashboard.dart`/`excel_updater.dart` and a Cupertino font reference warning.
The supported JavaScript web build succeeded; a Wasm build is not claimed.
No build was published. Documentation/link, migration-history and boundary
checks are captured separately in final evidence. All 83 migration files are
byte-identical to the canonical base; the history validator also checks the
repository's 27 frozen historical entries.

### Completion checklist (original checklist above retained)

- [x] Implement gateway/controller/local QR and session-response ownership.
- [x] Integrate owned MFD return, drafts and immutable retry requests.
- [x] Complete controller/widget/real SDK mock/SQL authorization matrix.
- [x] Save architecture, SELECT-only inspections, NOT EXECUTED runbook/changelog.
- [x] Pass focused/full tests, changed-code checks and safe local web build.
- [x] Review diff, dependency delta, secret handling, guards and canonical base.
- [x] Preserve the original plan and dated deviations; archive sanitized evidence.

The final local commit is created only after documentation, staging and boundary
checks; its exact commit/tree and clean statuses are recorded in external
`validation-summary.md`/`final-state.json`. Hosted commissioning and real local
Auth remain outside the completed evidence, as described above.

## MFA-REVIEW-001 correction plan — 2026-10-04 (before implementation)

Fresh prechecks: canonical clean `develop` and queried remote develop both
`cdf363680236708dea9dbbd9d8b0d6e8a4a276a7`; existing feature worktree clean at
`cf091ccdf5c9d3c1324858ea1e24f374f4583c7a`, tree
`efa4aff2b66531a84517bba698a07933407af335`. No Git locks or competing writable
repository file descriptors were found. The reviewed commit will not be amended.

The supplied independent probe was run unchanged before edits: ordinary existing
factor verification passed, overlapping same-account projection recovery failed
with `controller.current == false` after current admin context was restored
(exit 1). This is the reported recovery defect, not an environment failure.
Evidence:
`/home/ubuntu/moneybowl-commissioning-evidence/mfa-review-001-20261004T193329Z-ms65bz4_`.

### Bounded correction design and intended files

- `lib/features/platform_administration/mfa/mfa_repository.dart`: classify a
  non-current projection separately from affirmative current non-admin denial.
  Check account lifetime before/after awaiting as today. Never use cached grants
  or assurance to make an unknown status actionable.
- `lib/features/platform_administration/mfa/mfa_models.dart`: add a typed
  recoverable context-unavailable error with explicit Refresh guidance; no raw
  diagnostics or new secret-bearing state.
- `lib/features/platform_administration/mfa/mfa_controller.dart`: this failure
  clears actionable status/confirmation while retaining the same account's
  transient pending setup and factor selection. Explicit refresh can recover
  the existing page. Genuine current denial/account change remains terminal.
- Preserve AuthProvider's session/request ownership and bounded Auth-event
  coalescing. A superseded read cannot publish or promise the newer read's result.
  Use recoverable return instead of awaiting an independently pending newer
  request: the supplied probe deliberately awaits the old inspection before
  releasing the newer response. No polling, retry chain or mutation replay.
- `test/platform_mfa_session_integration_test.dart`: portable production
  controller/provider/SDK/access-listener regressions, including the two reviewer
  cases, pending setup, response ordering, denial, account lifetimes, recoverable
  read failure and actual stacked MFD/security lifecycle widgets where practical.
- `test/platform_mfa_sdk_test.dart`: narrowly extend the existing deterministic
  fixture for pending factor status, base-authority denial and controlled reads.
  Keep its exported fixture compatible with the unchanged external probe.
- `scripts/test_platform_mfa.sh`: include the portable integration file.
- This retained plan and `docs/architecture/PLATFORM_MFA_STEP_UP_V1.md`: append
  actual correction/validation evidence. Update the DEV runbook only if explicit
  recovery guidance changes; retain NOT EXECUTED. No package changes.

### Acceptance and validation

Require same-account unknown context to remain recoverable, retain pending setup
without new enrollment, and keep sensitive actions off. Current denial, expiry,
removed factor and logout/A -> B/A -> B -> A must not be overridden by stale
responses. Original UUID/payload/confirmation behavior and SDK session fence
remain untouched. No automatic OTP/enrollment/business mutation retry.

Run the new portable regression and unchanged reviewer probe, focused runner,
full Flutter suite (`--no-pub --reporter expanded --concurrency=2`), existing
network-disabled disposable SQL harness, changed-Dart formatting/analysis,
documentation/link and migration-history checks, commit-quality validation and
the supported loopback/synthetic-key release web build. Commands run with stdin
from `/dev/null` in the evidence runner so SQL subprocesses cannot consume later
shell commands. Preserve before/after logs, exits and source hashes externally.
Require all 83 migrations byte-identical to base and canonical checkout clean.
Create exactly one additive local correction commit after all gates pass.
No publication, deployment, hosted/real Auth commissioning or child sessions.

### MFA-REVIEW-001 implementation notes — 2026-10-04

- Implemented the planned typed recoverable return in repository/models/
  controller. AuthProvider and the Auth session fence remain byte-identical to
  the reviewed candidate; no new read coalescer or waiter was needed.
- Reused the existing SDK fixture through a relative Dart import; its public
  fixture entry remains compatible with the unchanged external review probe.
  Added only pending-factor status, base-authority response and login-actor
  controls. No absolute fixture imports or remote HTTP fallback were added.
- Added 13 portable tests, including actual stacked MFD/security lifecycle
  observers. Initial widget runs split SDK operations between fake and real
  async zones; safe state/count diagnostics identified the ordering issue.
  Running its actions and SDK events in one real-async zone resolved it without
  weakening assertions. Temporary diagnostics were removed; failed logs retained.
- The unchanged reviewer probe now passes both tests; portable tests pass all
  13. The runbook gained only the explicit same-account refresh recovery check
  and remains NOT EXECUTED. Full validation results are appended when complete.

### MFA-REVIEW-001 final validation — 2026-10-04

| Check | Result | Exit | External log |
| --- | --- | --- | --- |
| Unchanged reviewer probe before edits | 1 passed, overlap recovery failed exactly as reported | 1 | `probe-before.log` |
| Same unchanged probe after correction | 2 passed | 0 | `probe-after.log` |
| Portable production controller/provider/SDK integration | 13 passed | 0 | `portable-final.log` |
| `bash scripts/test_platform_mfa.sh` | 146 passed | 0 | `focused-final.log` |
| Full Flutter suite, `--no-pub --reporter expanded --concurrency=2` | 467 passed | 0 | `full-suite-final.log` |
| Changed-Dart formatting / analysis | 5 files, zero formatting changes, no analysis issues | 0 | `formatting-final.log`, `analysis-final.log` |
| Disposable full-schema SQL / concurrency / inspections | 11 suites, 4 concurrency scripts, both read-only commissioning scripts passed | 0 | `sql-final.log` |
| Migration history | 27 frozen entries passed; separately all 83 files byte-identical to base | 0 | `migration-history-final.log`, `boundary-final.log` |
| Local release web build, loopback/test-only configuration | JavaScript build passed; unchanged Wasm/font warnings | 0 | `web-build-final.log` |
| Documentation / links and commit quality | Repository validators passed | 0 | `docs-final.log`, `commit-quality-final.log` |

Commands use the previously verified Flutter 3.44.6 / Dart 3.12.2 executable.
Resolved Supabase Flutter 2.18.0, Supabase 2.16.2 and GoTrue 2.27.2 are unchanged;
the ignored dependency lock is byte-identical to the reviewed resolution.
Full commands, return codes, sanitized logs, changed-file hashes, boundary audit
and final commit/tree are saved in this correction's external evidence directory.
The probe file and original review evidence were not modified. No failing
expectation was removed or weakened. The reviewed implementation commit is
retained; exactly one additive correction commit is the final local gate.

- [x] Reproduce and preserve the independent before-edit failure.
- [x] Save the correction plan before implementation and retain original history.
- [x] Implement typed recovery without accepting stale grants/assurance.
- [x] Cover pending setup, actual listeners, response orders and account lifetimes.
- [x] Pass probe, portable/focused/full suites, SQL and local build.
- [x] Verify unchanged provider/fence/MFD contracts, dependencies and 83 migrations.
- [x] Update architecture and the unexecuted commissioning recovery procedure.

Real local Auth, physical authenticator and hosted DEV commissioning remain
NOT RUN. Mocked SDK/session-model tests and synthetic SQL do not establish real
TOTP cryptographic verification. No hosted or Production action occurred.
