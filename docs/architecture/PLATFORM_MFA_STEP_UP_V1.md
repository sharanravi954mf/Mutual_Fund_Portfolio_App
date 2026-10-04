# Platform MFA step-up V1

Local candidate on the PR #188 base
`cdf363680236708dea9dbbd9d8b0d6e8a4a276a7`. Hosted DEV commissioning is **NOT RUN**.
See the retained [implementation plan](PLATFORM_MFA_STEP_UP_V1_IMPLEMENTATION_PLAN.md)
and the **NOT EXECUTED** [DEV runbook](PLATFORM_MFA_STEP_UP_V1_DEV_COMMISSIONING.md).

## Implemented components

| Component | Responsibility |
| --- | --- |
| [AuthSessionFence](../../lib/features/authentication/services/auth_session_fence.dart) | Existing-client Auth response ownership, identity intent invalidation, safe stale-response errors and Retry-After parsing |
| [AuthProvider](../../lib/providers/auth_provider.dart) | Account lifetime, session and projection generations; focused platform refresh; lifecycle and session-expiry suppression |
| [MFA repository](../../lib/features/platform_administration/mfa/mfa_repository.dart) | Current-user SDK adapter, factor/assurance inventory, validated local setup URI, shared per-client operation slot |
| [MFA models](../../lib/features/platform_administration/mfa/mfa_models.dart) | Typed factors, statuses, safe failures, redacted transient setup and internal return reference |
| [MFA controller](../../lib/features/platform_administration/mfa/mfa_controller.dart) | Explicit enrollment/verification, bounded reconciliation, pending-factor recovery, backgrounding and disposal |
| [Security screen](../../lib/features/platform_administration/mfa/platform_security_screen.dart) and [setup panel](../../lib/features/platform_administration/mfa/mfa_setup_panel.dart) | Factor selection, six ASCII digits, local QR/manual/copy, explicit return and cancellation |
| [Platform shell](../../lib/features/platform_administration/presentation/platform_administration_screen.dart) | Account security entry and focused access refresh |
| [MFD screens](../../lib/features/mfd_applications/presentation/mfd_application_screens.dart) and [account scope](../../lib/features/mfd_applications/presentation/mfd_account_scope.dart) | Shared security entry, owned async reads/actions, exact application reload and original request retention |

`main.dart` installs the response fence on the existing Supabase client and turns
SDK debug output off. No second Auth client or token store is introduced. An MFA
adapter refuses to operate without the fence attached. Explicit sign-in/sign-out
intent in `SupabaseService` invalidates obsolete requests before awaiting SDK I/O.

## Trust and authorization contract

This is MFA for the signed-in **MoneyBowl application account**, not Supabase
Dashboard MFA. Base `platform_admin` permits the account-security screen.
`mfd_applications.review` additionally gates the MFD domain. Missing review
capability is an access error and never an invitation to gain a business role
through enrollment. Public signup, Explorers, tenant screens and investor
routing gain no new MFA requirement.

AAL1 preserves platform reads and capability-authorized Start review. Approve and
Reject retain their original RPCs and server checks. No migration, applied SQL,
ACL or server authorization function changes. In particular:

- `get_my_platform_context()` is the server projection for current platform UI.
- `platform_admin_step_up_verified()` checks the existing claim/session/factor
  contract, including current session ownership, expiry and verified factor.
- `can_perform_platform_mutation(...)` and
  `platform_authority.require_mutation('mfd_applications.review')` remain final.

Enrollment, `nextLevel=aal2`, a local boolean and decoded JWT claims cannot grant
business authority. The screen requires a supported verified TOTP factor,
current SDK AAL2 and affirmative fresh server `step_up_verified`. SDK information
can suppress UI assurance; it cannot promote a server denial. Every mutation
still rechecks server authorization. No arbitrary MFA validity interval exists.

## State and session behavior

The security controller starts with unknown status. Entry/rebuild/refresh never
enroll. Inspection uses `listFactors().all` to retain pending and unsupported
states; verified-only subsets would incorrectly hide incomplete setup. Multiple
TOTP factors require selection using bounded type/status/ordinal labels, not
untrusted server-friendly-name content. Unsupported-only inventory fails closed.
One verified factor prevents new enrollment even if first seen by the fresh
inspection immediately preceding the explicit Set up action.

The controller holds a shared per-client operation slot from start through
completion/reconciliation. Double taps and a recreated route cannot launch a
replacement while an earlier operation is unresolved. No `Future.timeout` is
used as cancellation. No automatic enroll, verify, removal or business retry.
A deliberate verification attempt refreshes factor ownership, challenges that
exact factor and verifies a six-digit ASCII string, preserving zeros. Wrong
codes do not create another factor.

`AuthProvider` distinguishes account lifetime from session generation and
projection request generation. Same-user `tokenRefreshed` and
`mfaChallengeVerified` events invalidate earlier reads, then schedule a focused
projection outside the SDK callback. They do not call listFactors or repeatedly
bootstrap business identity. Queued events for an already replaced session are
ignored. Projection writes require the initiating SDK Session object, session
generation and latest request ID to remain current. Unknown/refreshing,
backgrounded or expired session context suppresses step-up immediately. A stale
success or failure cannot overwrite a newer denial or logout. Business bootstrap
is retained for sign-in, callback and explicit identity refresh.

The HTTP fence buffers Auth responses, compares the captured SDK Session
reference and identity-intent generation, and substitutes a safe stale-context
error before an obsolete response body reaches GoTrue's parser/session save.
It does not patch JWTs, store tokens or blindly sign out a newer user. It also
checks error responses. Business/storage streams remain unchanged. MFA setup
and SDK session installation are distinct: controller disposal prevents UI reuse;
transport ownership prevents the SDK's late verification result from restoring
an obsolete session. Actual installed-SDK tests cover delayed verify and refresh
against logout and different-account login, plus out-of-order projection reads.

Lifecycle resume performs bounded revalidation. A still-running operation keeps
its slot. No instantaneous cross-tab revocation display is promised: SDK session
events, app resume, explicit refresh, MFA verification and server mutations are
the defined boundaries. The server remains authoritative even before the UI
receives a revocation notification.

## Secrets, local rendering and incomplete setup

The inspected SDK returns an SVG-prefixed data URI, but this implementation uses
its separately returned `otpauth` URI and renders a new QR locally with
`qr_flutter`. The validator requires TOTP, matching issuer/secret, single-valued
parameters, six digits, 30-second period and SHA1, and rejects fragments,
credentials and external URLs. That is a supported-factor format check, not a
claim of cryptographic verification. No QR-generation/image-hosting endpoint.
The QR has a white backing and black modules in both themes.

Issuer is `MoneyBowl DEV` for the canonical DEV project hostname, `MoneyBowl
LOCAL` for localhost/127.0.0.1, and `MoneyBowl` elsewhere. Account label comes from
the current SDK user. There is no hardcoded personal identity or Production
configuration change. A future custom DEV Auth domain would require an explicit
labeling decision; the canonical host is the currently supported configuration.

Setup secret and URI are transient, controller-owned references. The code input
clears on submission, success, backgrounding and ownership loss. Setup is
released on success, disposal, confirmed cancellation and account change.
Backgrounding hides and unmounts sensitive display; same-account resume can keep
an unfinished setup while checking status. `MfaSetup.toString()` is redacted;
errors and navigation carry no secrets. Copy is explicit and never includes an
OTP or token; no unrelated clipboard content is overwritten for cleanup.
Dart/browser memory and clipboard retention cannot be guaranteed securely erased.

Cancellation may leave an unverified server factor. Reload loses its secret;
listFactors cannot recover it. An already-added pending factor can be explicitly
selected and verified after fresh status. Otherwise an explicit acknowledgment
permits a new setup, leaving existing factors intact. Factor limits are reported
honestly. Runtime V1 never calls `unenroll`. Verified-factor removal/replacement,
bulk cleanup, recovery codes, privileged reset and lost-device recovery are
deferred; there is no bypass or invented reset button.

## Error and retry policy

Failures map to safe typed messages: invalid code, expired challenge/session,
rate limit, disabled configuration, factor limit, revoked access, changed
session, unsupported factor, invalid setup and context disagreement. Raw SDK
exceptions/responses are neither displayed nor interpolated into diagnostics.
Uncertain enrollment/verification outcomes get at most one status reconciliation
before another user action. Fatal access/session loss releases setup references.
A failed reconciliation leaves status unknown; it cannot become “no factor.”
Supabase MFA is not the application's request-receipt protocol; exactly-once
enrollment is not promised.

Retry-After delta seconds and HTTP dates are honored. A single timer may wake
controls at the server deadline; it never makes a request. There is no mutation
auto-retry or polling. Ordinary SDK token storage, automatic session refresh and
its built-in refresh-token retry behavior remain SDK-owned; application code
adds no second retry loop. A hung operation remains in flight; leaving the page
does not cancel the underlying SDK request or permit replacement work.

## MFD return and actor binding

Both platform and blocked-review entry points use `openPlatformSecurity`.
`MfaDestination` carries only an optional internal application ID, never an
arbitrary redirect URL. Server confirmation enables an explicit Return button.
On return the originating route refreshes access and reloads the application,
version and terminal state. No Start review, approval or rejection is replayed.

Applicant, queue, detail and form state belongs to one account lifetime, including
A -> B -> A changes. Current-request checks prevent stale reads from replacing
newer application data. Account loss clears lists, target, draft and pending
Start review/decision state; late completions cannot navigate as another actor.
Same-account decision notes remain in memory through MFA. A sent `MfdRequest`
retains its original UUID, version, operation and note. Unsaved forms may use the
newly loaded version; already sent payloads are never rewritten. Approval
acknowledgment is reset after security return/revalidation. A terminal result
replaces the decision path; a failed revalidation leaves submission disabled.
A server assurance/capability denial invalidates client context immediately.

## Compatibility facts and documentation

Resolved locally: Flutter 3.44.6 / Dart 3.12.2; supabase_flutter 2.18.0,
supabase 2.16.2 and gotrue 2.27.2. Only two resolution additions: qr_flutter 4.1.0
(BSD-3-Clause) and its transitive qr 3.0.2 (BSD-3-Clause). Existing SDK package
ranges and the ignored lockfile policy remain unchanged. Full before/after lock
snapshots and source/license hashes are in external evidence, not large Git logs.
These are the tested resolutions; future dependency resolution changes require
rerunning the SDK regressions.

Inspected GoTrue facts: `enroll` prefixes SVG data; `verify` saves Session and
emits `mfaChallengeVerified` before returning; `listFactors` invokes
`refreshSession`; refresh coalesces by refresh token and checks session version
before applying success/failure. MFA verify does not have that refresh guard.
Flutter SDK persistence listens to auth events and remains the sole session
persistence mechanism. Debug logging is disabled in application initialization.

Official references checked 2026-10-04:
[TOTP guide](https://supabase.com/docs/guides/auth/auth-mfa/totp),
[Dart enrollment](https://supabase.com/docs/reference/dart/auth-mfa-enroll),
[challenge](https://supabase.com/docs/reference/dart/auth-mfa-challenge),
[verification](https://supabase.com/docs/reference/dart/auth-mfa-verify),
[assurance](https://supabase.com/docs/reference/dart/auth-mfa-getauthenticatorassurancelevel),
and [changelog](https://supabase.com/changelog).
The changelog Markdown URL failed to render; the HTML index was checked instead.
The installed Dart source, rather than JavaScript example lifecycle behavior,
determines this adapter. Product policy explicitly requires user-triggered enroll.
QR [package](https://pub.dev/packages/qr_flutter) and
[license](https://pub.dev/packages/qr_flutter/license) were checked.

## Validation and commissioning limits

Run `bash scripts/test_platform_mfa.sh` for focused tests, then the full Flutter
suite. `bash scripts/test_mfd_application_sql.sh` creates a disposable,
network-disabled tmpfs PostgreSQL instance, applies unchanged composed
migrations, runs authorization/concurrency regressions and validates both
commissioning scripts against synthetic approval/rejection fixtures. The Python
inspection test independently verifies container identity/network/tmpfs before
using its fixtures and checks SELECT-only/read-only output, malformed/missing /
mismatched IDs, project attestation, actor attribution and unchanged baselines.

UI/controller tests use fake repositories. SDK integration tests use the **real
installed Supabase/GoTrue client with MockClient**, synthetic sessions and no
external fallback. SQL fixtures assert server authorization and atomicity; they
are not real TOTP cryptographic verification. No test images contain real setup
material. The local web build uses localhost and a synthetic public-key value.

`LOCAL_REAL_AUTH_REHEARSAL=NOT_RUN`: the visible Auth stack belongs to another
validation environment. It was not proven disposable/task-owned; the user
forbids existing-service mutation. No new Auth service or real user was started.
Hosted DEV commissioning is NOT RUN and cannot be inferred from any local PASS.
The runbook requires independently authorized deployment and human rehearsal.

Validation results and source/evidence hashes are appended after final checks.

### Final local validation — 2026-10-04

- Pre-edit baseline: 74 existing auth/platform/MFD tests plus disposable full
  composed-schema/authorization/concurrency harness, both exit 0.
- Final focused runner: 133 tests, including 26 controller, 14 widget, 19 real
  SDK with mocked HTTP and the same 74 existing tests, exit 0.
- Full Flutter suite: 454 tests passed, exit 0. The first full run exposed an
  existing order-widget AuthProvider test double requiring interface updates;
  its assertions were retained and the final suite passed.
- All 20 changed Dart files formatted with zero changes and analyzed with no
  issues, exit 0. No disabled tests or weakened CI assertions.
- Disposable PostgreSQL: 11 SQL suites, all four concurrency scripts and both
  read-only inspection scripts' synthetic integrity/validation checks passed,
  exit 0. All 83 applied migration files remain byte-identical to the base.
- Local release web build succeeded, exit 0, using
  `SUPABASE_URL=http://127.0.0.1:54321` and a synthetic public-key value. Existing
  `dart:js` Wasm dry-run warnings and a Cupertino font-reference warning remain;
  the JavaScript build passed. No deployment or Wasm compatibility claim.

The completed requirement matrix is appended to the retained plan. Sanitized
commands, exits, logs, original/resolved dependency snapshots, SDK/license
hashes, all changed-file hashes, boundary checks and final commit/tree identity
are outside Git at:

`/home/ubuntu/moneybowl-commissioning-evidence/platform-mfa-step-up-v1-20261004T-local-165340`

Key final log SHA256 values:

```text
focused-release.log       c46cf0aca49f562fe301f1eb64ae244e2774a790a93c30874207a19c71986a1e
full-flutter-release.log  a54d5d8c8d2640175f1785aecfc05f7c56833f1346e6fbc9df15cf96c5609c96
analysis-release.log      c4712765994da7f1020b3ec100c322f96e006dcc17ca21c7fe79f06b69635214
sql-release.log           6f6209b8c295d398678f090042cc27e67e88e043b2be69188ef338fb0a8a56d4
web-build-release.log     4636fea9d7389dd81469325e837f5581d8d90e5fcafec4d04a6b84ad4c605c47
```

Repository documentation/link and migration-history checks plus commit metadata
are recorded in the final external summary. Local implementation evidence does
not establish real Auth cryptography, camera scanning on a physical device or
hosted commissioning. Those human checks remain explicitly NOT EXECUTED in the
DEV runbook. Verified-factor removal/recovery stays deferred.

### MFA-REVIEW-001 — same-account refresh recovery (2026-10-04)

Independent review reproduced a recovery defect in the original local commit
`cf091ccdf5c9d3c1324858ea1e24f374f4583c7a`. A superseded platform read correctly
returned without publishing, but the MFA repository conflated
`platformContextCurrent=false` with a current server denial. The controller then
entered its terminal unavailable phase and discarded setup. A later successful
projection could not recover that page. This was a recovery failure, not an
authorization bypass.

The correction keeps the provider's latest-request/session ownership checks and
SDK response fence unchanged. The repository now distinguishes three outcomes:

- Account/session ownership loss still produces a terminal changed-session
  error, and a **current** non-admin server projection still denies access.
- An unknown, refreshing, superseded or failed projection produces typed
  `contextUnavailable`. It does not prove either authority or revocation.
- Only a current affirmative server projection, with the existing SDK/factor
  checks, can supply an actionable MFA status.

`contextUnavailable` leaves the same-account controller recoverable, clears all
actionable factor/assurance status and retains any pending setup reference and
selection. The secret display stays hidden while status is unknown. The user
can choose **Refresh security status** on the existing page after the overlapping
request settles. A current denial or account-lifetime change still clears setup
and cannot be reversed by a late response, including A -> B -> A.

This is a bounded recoverable return, not an automatic retry. AuthProvider's
existing Auth-event coalescing remains unchanged. The superseded inspection
does not await or repeatedly chase independently started newer reads; the review
probe deliberately waits for that inspection before releasing the newer read.
No cached grant/AAL2 value is used for recovery. No enrollment, verification or
MFD action is automatically replayed. All MFD request UUID/payload and explicit
confirmation code is unchanged.

Portable regressions live in
[test/platform_mfa_session_integration_test.dart](../../test/platform_mfa_session_integration_test.dart)
and run through `scripts/test_platform_mfa.sh`. They use the production
controller/provider/access listener and the real installed SDK with the existing
MockClient fixture. Coverage includes both response orders for authoritative
denial, pending setup identity without duplicate enrollment, recoverable failed
reads, stale assurance, removed factors, expiry, logout and both account-switch
sequences. The expiry case expires only a synthetic SDK Session model; it is not
real Auth token expiry commissioning. A widget regression stacks the actual MFD
detail and security routes and dispatches lifecycle events to their real
listeners. SDK callbacks run in one real-async test zone, with Flutter pumping
frames separately, to avoid split fake-clock event delivery.

The unchanged independent probe failed before the correction (1 pass, 1 failure,
exit 1) and passed after it (2 passes, exit 0). The portable integration file
passed 13 tests, exit 0. Additional final validation results follow below.
Evidence is separate from the original implementation evidence:

`/home/ubuntu/moneybowl-commissioning-evidence/mfa-review-001-20261004T193329Z-ms65bz4_`

No packages, provider implementation, session fence, MFD mutation/navigation
implementation, applied migration, authorization guard, RLS or ACL changed.
Hosted commissioning remains NOT RUN.

#### Correction validation results

Final correction checks all exited 0: 13 portable integration tests, 146 focused
Flutter tests, 467 full-suite Flutter tests, formatting/analysis of all five
changed Dart files, 11 disposable SQL suites plus four concurrency scripts and
both commissioning inspections, documentation/link checks, migration history and
commit-quality validation. All 83 migrations and the dependency lock match the
reviewed base/resolution. JavaScript web build passed using the same loopback URL
and synthetic public-key value; existing `dart:js` Wasm and Cupertino font
warnings remain. No build was published.

Probe log hashes distinguish the reproduced failure from the corrected result:

```text
probe-before.log  4f9ea0fa8934d4938b52b9d1f4fe5a78fe808c8f73026ddb54e933a351d666f0
probe-after.log   d234df300f007bb8c6cf805f9d9badea1763a611b9eeb48b36ce5a81b2d58aa3
portable-final.log 0aab7c5af6c4c17b9aefd6661b391ee68f237a7941d12e89e7b2bd0cfd7700ec
full-suite-final.log 68bb580acc704a4cb920e53f926383372fc649a0eef725c0333d95ce098ee975
```

`validation-summary.md`, `commands.jsonl`, `source-files.sha256` and
`final-state.json` in the correction evidence directory record exact commands,
all log hashes and the additive local commit/tree. Real Auth and hosted
commissioning remain NOT RUN. Independent re-review and separately authorized
deployment/human commissioning remain necessary before a hosted readiness claim.
