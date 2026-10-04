# Platform Admin Authority V1

Base: freshly fetched `origin/develop` **`bdc8a151ada84baced72fe69fd462db5d5eed64a`**. This implements the platform-authority dimension of the [role audit](MONEYBOWL_ROLE_MODEL_AUDIT_V1.md) on top of [authorization containment](AUTHORIZATION_CONTAINMENT_V1.md). It does not implement MFD onboarding. No hosted data, account, MFA factor or secret was changed.

## Authority and storage

The [forward migration](../../supabase/migrations/20261004081141_platform_admin_authority_v1.sql) creates private `platform_authority.grants` and `platform_authority.events`. A grant belongs to an **`auth.users.id`**, with no workspace or business-profile dependency. `revoked_at IS NULL` means active. A partial unique index permits one active grant per account/key; revoked history is retained. Grant UUID, subject, key, timestamp, database principal, evidence reference and request UUID are immutable. Revocation records its own timestamp, principal, evidence and request UUID. Triggers audit changes atomically and reject grant deletion, provenance edits and audit updates/deletes.

The private schema has no Data API role access, including `service_role`; tables have RLS and no API policies or grants. Application facades are explicitly granted to `authenticated`, never `PUBLIC`/`anon`. Privileged functions use an empty search path and qualified objects. Operator functions are SECURITY INVOKER, execute only for the trusted database operator, and derive attribution from `session_user`, never a caller-supplied actor.

| Grant | Meaning |
|---|---|
| `platform_admin` | Platform context; prerequisite for every platform capability. Does not imply the following capabilities. |
| `mfd_applications.review` | Discoverable authority reserved for the next MFD-review implementation; no application/decision endpoint exists yet. |
| `platform.catalog.manage` | Existing global catalogue maintenance, gated by verified step-up. |
| `platform.family_support` | Existing narrowly bound, audited family-delegation support override; explicit additional commissioning required. |
| `platform.investor_links.revoke` | Existing exceptional investor-link revocation, gated by verified step-up and reason. |

This is a fixed allowlist, not configurable IAM. Initial bootstrap grants **only `platform_admin` and `mfd_applications.review`**. Unknown keys fail closed. A capability is effective only while both it and the account's admin grant remain active.

`public.is_platform_admin()` reads current database grants for `auth.uid()`. Auth must exist, be email-confirmed, non-anonymous, not banned/deleted, and have no attached inactive/suspended profile. A profile is optional; its *role* never grants platform authority. Neither account state, email spelling, JWT business roles nor user metadata is an authority source.

`has_platform_capability(text)` checks current grants. `get_my_platform_context()` takes **no account selector** and exposes only the caller's admin flag, effective capability names, MFA-enrollment flag and verified-step-up flag. It returns no grant provenance, other accounts or tenant data. UI projections are hints; mutations independently authorize in the database.

## MFA and existing platform operations

`platform_admin_step_up_verified()` now requires current admin authority, a signed request with `aal2`, and a live matching `auth.sessions` row at AAL2 tied to a currently verified factor belonging to the same account. Expired/deleted sessions or removed factors fail closed. JWT metadata cannot substitute for these checks. See Supabase's [MFA](https://supabase.com/docs/guides/auth/auth-mfa) and [session](https://supabase.com/docs/guides/auth/sessions) contracts.

`can_perform_platform_mutation(capability)` is a safe predicate. Private `require_mutation(capability)` locks account/profile, grant and MFA/session rows, then checks current authority. Future approve/reject RPCs must use this gate with `mfd_applications.review` inside their transaction, plus their own application/resource checks; discovering the capability is not approval implementation.

Existing surfaces are normalized:

- Deprecated `is_admin()` means stepped-up `platform.catalog.manage`, never Workspace Admin.
- The NAV Edge function uses the caller's token and `platform_update_fund_nav`, removing its broad service-key portfolio enumeration. Each write checks capability/MFA and records an auth-user audit; affected portfolios are repriced internally without returning investor records.
- Investor-link revocation requires its separate capability, step-up and a reason.
- Family-support attempts require their separate capability and step-up. `workspace_audit_logs.actor_user_id` permits truthful platform-only attribution without inventing a profile; existing profile-based audit records remain intact. Service-side support execution rechecks the initiating account's current grants/session/factor. An old attempted audit cannot preserve revoked access. Historical attempts lacking auth/session provenance must be reissued.

**Out-of-band exception:** initial commissioning and emergency privilege revocation are private database-operator procedures, not Platform Admin application actions. They intentionally do not require the target to have MFA beforehand. No browser or service-key IAM management API exists, at any AAL. All sensitive application operations require verified AAL2.

## Separation and routing

`bootstrap_identity()` returns neutral `explorer` state plus `platform_context` resolution for an authorized operator. It neither creates a business profile nor assigns `account_state=advisor`. Flutter independently loads the safe platform projection; `AuthProvider` skips business-profile loading for operators. `RouteGuard` routes them to **MoneyBowl Platform Administration**, with read-only access/MFA status, account information, refresh/sign-out and a clearly unavailable future MFD-applications section. No approval controls are implemented. Refresh, auth events and app resume reload authority; projection failure fails closed. Database revocation requires no JWT refresh even if an idle UI has not yet refreshed.

Advisors and Workspace Admins retain the MFD dashboard; the server bootstrap also recognizes an active professional workspace membership for an investor persona. Investors and Explorers retain their existing destinations. `UserRole.admin` never implies platform access; the legacy `UserRole.platformAdmin` label cannot substitute for a grant or open the MFD dashboard.

Platform operators cannot use MFD membership, investor ownership or assignments to obtain routine tenant access while the platform grant is active. This preserves containment's operator exclusion even when obsolete Advisor rows have not yet been retired. Multi-persona platform/MFD operation would require a later explicit product/security decision. Revocation alone is **not** a substitute for retiring obsolete memberships: otherwise those independent tenant grants could become usable again.

Invitation acceptance now requires the inviter's active admin membership in the exact workspace; its old `profiles.role=platform_admin` exception is removed. An operator cannot accept an MFD invitation through this path. Public signup remains neutral and cannot insert platform grants. The composed baseline contained no surviving JWT `app_metadata.user_role` authorization; historical migrations remain untouched. Existing legacy `profiles.role=platform_admin` records are **not automatically commissioned**.

## Commission Ravi after review and merge

Product target: **`sharanravi954@gmail.com` becomes a platform-only operator**. The supplied DEV facts are Advisor profile/state, active profile, multiple workspaces and validation relationships, with no verified MFA. These are user-supplied facts, not a live inventory. Local implementation cannot establish which individual hosted rows are test-only.

1. Independently verify Ravi's existing Auth UUID and confirmed email in the intended DEV project. Do not create another Auth account or authorize by email matching. Confirm project, reviewed commit and migrations first.
2. Run the [read-only preflight](../../supabase/operations/platform_admin_commissioning_preflight.sql) using `psql -v target_user_id=VERIFIED_UUID -f ...` against a disposable restored dataset first, then separately authorized DEV. It inventories identity, grants, memberships, owned workspaces, assignments, credentials' identifiers/statuses, investor links, pending reviews/invitations, historical order references and OAuth actor references; it selects no secret or evidence ciphertext.
3. Record a reviewed disposition with **explicit row IDs** and an external operator/change reference. Empty financial counts alone do not prove a workspace is disposable. Transfer any legitimate workspace ownership to a separately verified owner before removing its administrator; archive only confirmed test workspaces. Stop commissioning retirement if ownership or legitimate business use is unresolved.
4. In a controlled transaction, lock the target account and approved rows and recheck that inventory. End only approved obsolete memberships and advisor assignments; deactivate approved EUIN and folio-review assignments; cancel obsolete pending invitations. Handle pending orders, OAuth ownership and legitimate customer relationships explicitly. Preserve financial records, order actors, evidence and immutable audit. Record each retirement with database-operator attribution and evidence in the existing audit stream. **No blanket delete or email-based update.**
5. Retain the existing profile UUID where history references it; after its test professional authority is retired, `role='user'` is the existing neutral compatibility label. Set its account projection to Explorer and retain active account/profile status: retiring a business persona is not account suspension. `advisor_profiles` has no retirement flag: retain it as inert historical metadata if referenced rather than fabricating a new identity or deleting it blindly. Its existence grants nothing; the operator never loads or requires it. Any destructive cleanup is a separately reviewed task. Do not remove a potentially legitimate investor link without verified disposition.
6. In that same commissioning transaction, invoke the private bootstrap with the verified UUID, two fresh request UUIDs and the evidence reference, then inspect the resulting grants/audits before commit:

```sql
-- Template for a separately authorized database-operator session; not executed here.
SELECT platform_authority.bootstrap_first_admin(
  :'target_user_id'::uuid, :'admin_request_id'::uuid,
  :'review_request_id'::uuid, :'reviewed_evidence_reference');
```

The function serializes first-bootstrap attempts, denies a different first operator once commissioned, checks the account and grants both keys atomically. Exact replay returns the same grant without duplicating events. Conflicting input or replay of a revoked grant fails closed. No personal email appears in authorization or commissioning functions.

7. Sign in to verify the profile-free Platform Administration context and tenant denials. Ravi must enroll and verify MFA through a separately authorized Auth flow **before exercising sensitive platform actions**. This task includes no MFA enrollment or bypass.

Later operator maintenance uses private `grant_authority(user_uuid, key, request_uuid, evidence)` and `revoke_authority(grant_uuid, request_uuid, evidence)`. Revocation is immediate for subsequent server decisions and idempotent for the same request; in-flight authorized transactions serialize against it. Revoking admin disables all effective capabilities; separately stored active capability rows remain historical/current assignments and must be reviewed before any re-grant of admin. Never silently reactivate revoked grants.

## Validation and deferred work

The dedicated [harness](../../scripts/test_platform_admin_authority_sql.sh) replays all migrations in a fresh network-disabled disposable database, with actual API roles and synthetic GoTrue session/factor state. Synthetic factors test enforcement; nobody is enrolled in real MFA. Final local results:

| Check | Result |
|---|---|
| Complete migration replay and SQL harness | **PASS**, 10 suites, including 79 named platform assertions and existing containment/signup/NSE/ingestion/order regressions. |
| Concurrency | **PASS**: concurrent first bootstrap is idempotent; a sensitive mutation demonstrably waits on revocation's lock and then denies. Existing signup, membership-revocation and invitation races also pass. |
| Flutter authentication, identity models and platform shell | **54 passed**, 0 failed. Profile-free routing, same-JWT projection revocation, signup/Explorer and investor/advisor destinations covered. |
| Existing Flutter order tests | **124 passed**, 0 failed. |
| Flutter analysis of affected auth/platform sources and tests | **No issues**. |
| Flutter web build | **PASS**. Existing `dart:js` wasm dry-run and CupertinoIcons asset warnings remain in unchanged code/configuration; JavaScript web output builds. |
| Deno shared authorization and support handler tests | **12 passed**, 0 failed. Shared authorization and NAV Edge entrypoint type checks pass. |
| Supabase lint, baseline → candidate | **59 → 59 diagnostics**, 0 errors and no new diagnostics; 56 warnings and 3 unused-parameter warnings remain. |
| Supabase advisors, baseline → candidate | **14 → 14 WARN**, no new finding keys: 8 permissive-policy, 1 RLS-initplan, 3 mutable-search-path and 2 duplicate-index warnings. |
| Read-only commissioning preflight | Executes successfully against the composed local schema; no hosted inventory performed. |
| Documentation, migration-history and whitespace validation | **PASS**; applied migrations unchanged. |

Reproduction commands (tool paths depend on the local installation):

```bash
bash scripts/test_platform_admin_authority_sql.sh
flutter test --no-pub test/authentication test/platform_administration_screen_test.dart \
  test/investor_identity_models_test.dart
flutter test --no-pub test/features/orders
flutter build web --no-pub
deno check supabase/functions/_shared/authorization.ts supabase/functions/daily-nav-updater/index.ts
deno test --cached-only --allow-env supabase/functions/_shared/authorization_test.ts \
  supabase/functions/platform-admin-override/index_test.ts
```

Both Supabase comparisons use disposable local full-schema databases. Commands are `supabase db lint --db-url "$LOCAL_DB_URL" --schema public,moneybowl_authz,nse_app,platform_authority` (omit the new schema for baseline) and `supabase db advisors --db-url "$LOCAL_DB_URL"`. The URL points to loopback inside the task's network-disabled container; the CLI's generic “remote database” label does not mean a hosted project. The final composed function/policy catalog has no `app_metadata`/`user_role` authorization references. This is focused regression coverage, not a claim to have exercised real email delivery, live MFA, hosted identities or provider integrations.

Deferred: actual DEV commissioning/MFA, evidence-based retirement of Ravi's hosted rows, MFD application/approval workflows, ARN/EUIN validation, richer IAM UI and any dual platform/MFD persona. Legacy business-role routing and historical `user/client` terminology remain compatibility debt. Existing unrelated lint/advisor findings are not expanded into this task. Deployment must coordinate the migration, new projection-dependent client and affected Edge functions; older code treating a global label as platform authority must not be retained as a fallback.
