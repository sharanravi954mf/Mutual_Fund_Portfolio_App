# Platform MFA + MFD DEV commissioning

Status: **NOT EXECUTED**. This local candidate is not a hosted commissioning PASS.
No account was enrolled, created, emailed, impersonated or approved/rejected on
hosted DEV. The procedure below requires separate deployment and explicit human
authorization. Automated deployment follows a separately reviewed merge; never
manually deploy to compensate for automation failures.

## Environment and evidence gate

1. Confirm the deployed web artifact's exact merge SHA from the existing build /
   deployment evidence, not its branch name. Record the reviewed candidate SHA
   and actual deployed merge SHA. Stop if provenance cannot be verified.
2. Independently confirm the browser backend and inspection connection target
   Supabase **DEV `rskryngwzyuzmiwtriyy`**. Production
   `auxbbotbcvrgzvynyrgg` is excluded. `current_database()` commonly says
   `postgres` and is not proof of project identity. Confirm the DEV Dashboard
   project and connection host through the established operator process.
3. Use the signed-in **MoneyBowl application account**, not Dashboard-account
   MFA. Independently resolve the operator's Auth UUID and two separate clean
   Explorer test-account UUIDs using authorized account administration. Record
   only safe IDs/statuses. Do not collect passwords, access/refresh tokens,
   setup material or OTPs. Do not use a service-role client as the browser actor.
4. Operator must already have active `platform_admin` and
   `mfd_applications.review` grants. MFA does not create either grant. Record
   existing grant IDs/keys/revocation statuses and preserve all old workspace
   relationships. No new grants or Platform Team management in this rehearsal.
5. Use a new evidence directory outside the repository. Save dated sanitized
   checks, deployed SHA, commands, exit codes, safe IDs/counts and file hashes.
   No QR, setup key, OTP, personal records or tokens in screenshots, chat, shell,
   logs, repository, URLs or issue attachments. No cleanup/deletion afterwards.

## Read-only inspection scripts

The two scripts have only SELECT/CTE inspection within `BEGIN TRANSACTION READ
ONLY` and `COMMIT`. They do not set claims, create factors, grant authority or
mutate an application. Run through an already authorized inspection connection;
never broaden ACLs to run them. They are not browser RPCs and need access to
private audit and Auth inventory tables. The project parameter is an explicit
operator attestation, not automatic host detection. A forged attestation cannot
protect a wrongly selected connection. `LOCAL_DISPOSABLE` is reserved for the
isolated automated harness.

Use the existing secure connection workflow without exposing a connection URI or
credential in command history. The following templates deliberately omit it:

```bash
psql -X -v ON_ERROR_STOP=1 \
  -v project_ref=rskryngwzyuzmiwtriyy \
  -v operator_user_id='<independently resolved operator UUID>' \
  -v applicant_user_id='<separate clean Explorer UUID>' \
  -v application_id='' \
  -f supabase/operations/platform_mfa_commissioning_preflight.sql
```

Before submission, the explicit empty application parameter is allowed only by
preflight; `application_supplied=false` documents why no application is inspected.
After submission supply its actual UUID. Postcheck requires all three UUIDs:

```bash
psql -X -v ON_ERROR_STOP=1 \
  -v project_ref=rskryngwzyuzmiwtriyy \
  -v operator_user_id='<independently resolved operator UUID>' \
  -v applicant_user_id='<same Explorer UUID>' \
  -v application_id='<application UUID recorded from normal UI>' \
  -f supabase/operations/platform_mfa_mfd_commissioning_postcheck.sql
```

Require `transaction_read_only=on`, `parameters_valid=true` and an empty
`validation_errors` array. Invalid/missing IDs, the same operator/applicant,
wrong project attestation and application/applicant mismatches are explicitly
reported. A SQL process exit 0 with validation errors is **not** a PASS.
`browser_session_confirmed` is deliberately always false: SQL factor/session
inventory only corroborates enrollment. The current browser's own
`get_my_platform_context()` projection must confirm that browser session. Do not
copy its request Authorization header, JWT or SDK session object into evidence.

Record the preflight's `operator_grants`, `operator_factors`, `target_counts`,
`applicant_account_state` and `global_baseline`. Global integrity/count changes
can also come from unrelated DEV activity; investigate attribution instead of
assuming they were caused by the rehearsal. Never clean up someone else's data.

## Human-assisted application and MFA rehearsal

1. With the first clean Explorer, record preflight before submission. Require
   eligible account, Explorer routing, zero business profiles/owned workspaces /
   memberships, zero platform grants and zero target investor/NSE/EUIN links.
   If a baseline is not clean, stop and use the established account-selection
   process; do not delete relationships or reuse the operator as an applicant.
2. Submit via the normal Explorer **Apply as MFD** UI. Use clearly synthetic
   DEV-only business/ARN claims and a truthful test note. Record the application
   UUID. Re-run preflight with that UUID: `submitted`, version 1, and no new
   business authority. This is not actual external ARN validation.
3. Sign in as the existing operator at AAL1. Platform Administration and the
   MFD queue/detail must be readable. Explicitly choose **Start review**; expect
   `under_review`, version 2. Approve/Reject remain disabled. Record this safe
   state without session tokens. Missing capability must show an access error,
   not suggest that MFA grants permission.
4. Open **Set up / Verify MFA** from that detail. Account security from Platform
   Administration must lead to the same feature. If a verified TOTP factor
   already exists, use it; no enrollment should occur. If none exists, the
   human explicitly chooses **Set up authenticator** after status checking.
5. Human handles the QR/key/code only inside MoneyBowl and their authenticator.
   In DEV, verify the **MoneyBowl DEV** issuer and their actual application
   account label. Scan the locally rendered QR or use the reveal/copy manual
   time-based key on the same phone. Never send the key/QR/OTP to an assistant,
   shell, repository, chat, screenshots or logs. Clipboard copy is explicit;
   MoneyBowl does not overwrite unrelated clipboard content on cleanup.
6. Enter the six-digit code, preserving zeros, and explicitly **Verify MFA**.
   Enrollment alone is not success. Require the current browser's server
   projection to affirm `step_up_verified=true` with current platform authority
   and review capability; the screen must show server confirmation. If SDK and
   server disagree, stop; do not bypass the guard or manually change JWT claims.
7. Choose **Return to application**. Verify the same UUID reloads with current
   version, permissions and terminal state. No automatic Start review, approval
   or rejection is permitted. If another reviewer decided it, inspect that
   result and do not replay a decision.
8. Explicitly open approval, enter an honest evidence reference such as a DEV
   synthetic test log reference, and acknowledge manual review. Confirm once.
   On uncertainty, preserve the exact request UUID/version/note and use **Retry
   safely** or reconcile the current application. Do not invent another request
   merely because MFA was visited. Sent payloads remain immutable. If assurance
   expires with the form open, verify, reload and acknowledge review again.

## Approval postcheck and containment

Run postcheck with the same operator/applicant/application IDs. Require:

- `approved`, version 3, expected operator `decided_by`, and correct reviewer
  attribution. Exactly one terminal event, attributed terminal event, decision
  receipt and receipt/event binding.
- Exactly one active advisor business profile, one owned active workspace and
  one active admin membership bound to the application's stored IDs;
  `approval_binding=true`. Exactly one provisioning audit and attributed audit
  bound by request correlation. Explorer's next identity refresh routes to its
  MFD workspace. Operator remains in Platform Administration without gaining
  membership in that workspace.
- Operator grants and global grant-integrity fingerprint unchanged; target
  platform grants, investor profiles/links/assignments, advisor_profiles/EUIN,
  integration accounts/operations and NSE connections unchanged (zero for the
  clean applicant). Compare all global baselines and investigate differences.
  Existing owner/admin capability predicates are not redesigned by this feature.

With the **second separate clean Explorer**, repeat preflight/submission/review
and explicitly reject with a truthful DEV-test reason. Preserve the account and
application history. Expect `rejected`, one event/receipt with correct actor,
no business provisioning/audit, `rejection_has_no_provisioning=true`, and Explorer
routing/history retained. A later unrelated identity change must not be reset.

## Later login, incomplete setup and final record

Sign out and sign back in as the same operator. At AAL1, use the existing verified
TOTP factor, choose among multiple factors if present, and verify without
reenrolling. Compare verified-factor counts before/after; there must be no
accidental duplicate. Backgrounding to read a code hides setup material and
resuming checks status without enrolling again.

Incomplete setup is not automatically removed: cancel/reload may leave a pending
factor and the secret cannot be recovered from listFactors. If already added,
select that pending factor and finish verification. Otherwise acknowledge the
explicit new-setup guidance. A factor-limit error needs the established recovery
process. V1 has no removal/replacement, bulk pending cleanup, recovery codes,
privileged reset or lost-device bypass. Do not attempt these during rehearsal.

Record each step PASS/FAIL, actual deployed SHA, local/browser differences,
counts and limitations. Unexpected errors, contradictory context or changed
baselines make the rehearsal incomplete; retain evidence and stop. No automatic
claim of hosted completion follows a local implementation PASS. Never enroll
Ravi, retire old relationships, create real users or make hosted decisions as
part of the local implementation task.
