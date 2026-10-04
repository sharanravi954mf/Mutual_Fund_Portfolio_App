# Authorization containment V1

Local implementation against freshly fetched `origin/develop` **`9f6888be717106cda4c873a3ff91d8575efbb7c3`**, reviewed 2026-10-03/04. This contains authorization defects from the [role audit](MONEYBOWL_ROLE_MODEL_AUDIT_V1.md); it does not complete the future role redesign or MFD onboarding. No hosted environment, account, secret, or provider commissioning state was changed.

## Corrected boundaries

A baseline test using the actual composed schema and `SET ROLE authenticated` demonstrated that Advisor A could select both A and B portfolios belonging to the same investor. The corrected test returns only A. Previously, the portfolio policy checked whether advisor and investor shared *some* workspace, while transaction access inherited that error.

The [forward migration](../../supabase/migrations/20261003233928_authorization_workspace_containment.sql) makes authorization depend on the persisted resource workspace, current account/profile, active workspace and non-ended active membership. A required assignment must belong to that same workspace. Account state and global professional labels no longer grant tenant authority.

| Surface | Corrected authority |
|---|---|
| Portfolios / transactions | Read the portfolio's actual workspace. Workspace staff book access and investor folio grants cannot authorize another workspace, including another portfolio of the same investor. Transactions retain their staff/investor contract. |
| Profiles / account links | Own identity or scoped staff visibility for profiles; account and investor-link table reads are self-only. Advisors cannot enumerate global accounts/links. |
| Advisor assignments | Explicit workspace, matching professional/customer memberships, immutable provenance, scoped uniqueness, actor-derived attribution and audit. A person-pair assignment in A cannot satisfy NSE authorization in B. |
| Membership / invitations | Direct membership insertion/update is revoked. Admission uses a stored invitation and verified recipient email; status changes use a scoped audited RPC. Invitations cannot change their recipient/role/workspace/token after creation. Accepting one grants only that workspace's authority. |
| Orders | Initiation, qualification, cancellation and folio projections use exact workspace authority. Historical initiator/reviewer provenance stays immutable, but an earlier actor's revocation does not prevent a different authorized actor processing an accepted order. |
| NSE frontend | Actor identity is active database identity; target membership supplies workspace/investor scope. Existing owner+admin or assigned-advisor rules remain. Assignments and locks include workspace. Provider contracts, gates and commissioning remain unchanged. |
| Verification | Queues, detail, candidates and decisions require request workspace; folio review additionally requires an active request assignment and the linked investor's scoped folio relationship. Candidate membership must match request workspace. Tokenless approval is disabled; the generic approval facade retains PAN evidence validation. |
| Folio grants | Token → request → reviewer assignment → grant carries one workspace. A grant for the same investor/folio in A is not a B grant. Grant uniqueness includes workspace. |
| Ingestion / documents | Current professional membership authorizes ingestion and OAuth initiation/revocation. OAuth completion rechecks the stored initiating actor, including suspension/ban, before installing credentials. Persisted documents remain private. Unscoped legacy CAMS statements are unavailable to browsers; ingestion logs require their actual workspace. |
| Uploaded-document utilities | Caller-bound database capability checks replace global profile labels. These endpoints process caller-supplied bytes, not persisted investor documents. The public fund-data proxy remains a separate authenticated utility. Global NAV updates require Platform Admin. |
| Family Guests | Active, accepted, unexpired consent grants portfolio access only in the delegation workspace; no secondary membership is required. It grants no order or MFD authority. |

Existing advisor workspace membership intentionally retains book access: individual advisor-investor assignment is additionally required for NSE, and an explicit request assignment for folio review. Ending an assignment removes assignment-derived authority, not a separate live book-access grant. Operations retains scoped staff reads; it cannot qualify orders, operate NSE, ingest, review verification or configure advisor approval rules through the shared advisor predicate.

## Authorization primitives and sources of truth

Private `moneybowl_authz` functions centralize `account_active`, `profile_active`, `actor`, `member_role`, `owns_investor`, `assigned`, `folio_workspaces`, `can_review` and `lock_scope`. Public RLS/RPC adapters expose caller-bound decisions such as `can_access_investor(workspace, investor)`, `can_read_portfolio`, `can_review_verification`, `can_select_order_request` and the existing workspace helpers. The old one-argument investor-access and assignment-management helpers fail closed.

- **Account state:** Explorer/link-pending/linked-investor/advisor remains a routing/compatibility projection. Live Auth deletion/ban/anonymous state and profile suspension gate business access. An ended membership is denied even if its textual status still says active.
- **Platform authority:** the active database `profiles.role = platform_admin` is the existing authority source. `is_admin()` is retained only as a deprecated alias for global platform/catalogue administration. It never means workspace admin. Named platform support semantics remain; global investor-link revocation requires both Platform Admin and existing JWT `aal2` step-up and records a platform actor.
- **Business identity:** trusted investor-account links establish ownership. A new active link cannot take over an already-owned profile. Professional profile/EUIN data is descriptive, not an approval or permission grant.
- **Workspace authority:** active membership in the resource's active workspace. Owner is still `workspaces.owner_profile_id`; existing order/NSE owner-admin restrictions are preserved.
- **Relationships:** workspace-bound advisor assignments, request-bound folio reviewer assignments, investor links, scoped folio grants and explicit family consent.

No `raw_user_meta_data` or JWT business-role claim grants authority. JWT authentication identity and step-up assurance remain inputs, with current database authority checks. Platform Admin is not provisioned and receives no implicit MFD membership or book access.

Affected privileged functions use an empty search path, qualified application objects and explicit execution ACLs. The internal schema and trigger helpers are not browser-executable. The generic non-PAN creation helper and service OAuth completion remain private. Affected permissive RLS policy sets are replaced together, avoiding surviving OR-policy bypasses. Sensitive mutations lock authority/resource rows and recheck after waiting; existing request versions, token consumption and immutable audits remain in force.

## Provenance and compatibility

The migration adds nullable `workspace_id` foreign keys to advisor assignments, verification requests, folio tokens and grants. Existing assignment backfill requires exactly one contemporaneous common workspace; current active flags cannot conceal another historical candidate. Folio requests/grants backfill only where the linked investor and persisted folio/portfolio mapping identify one workspace. Grants additionally require a recorded approver with professional membership in that workspace at approval time; missing approver provenance remains quarantined. Existing unscoped tokens become unusable and can be reissued.

Ambiguous or absent provenance stays NULL and grants no access. No financial record is deleted, and no tenant ownership is selected arbitrarily. Synthetic upgrade fixtures prove that a unique historical relationship remains usable while a shared-workspace relationship is quarantined. **Actual hosted row counts are unknown:** this task inspected no live data.

Before deployment, a trusted read-only preflight must inventory:

```sql
select count(*) from public.advisor_investor_assignments where workspace_id is null;
select method_code, count(*) from public.verification_requests
where workspace_id is null group by method_code;
select count(*) from public.folio_grants where workspace_id is null;
select count(*) from public.portfolios where workspace_id is null;
select count(*) from public.ingestion_logs where workspace_id is null;
```

These are post-migration shape checks to run on a disposable restored dataset first. Review original memberships/timestamps, folio mappings and approval evidence; do not resolve ambiguity by choosing the actor's current workspace. Retire/reissue ambiguous assignments or grants through controlled, audited maintenance after evidence review. Historical non-PAN requests need explicit trusted routing before tenant review. Legacy CAMS statements need provenance before browser access can return.

New manual verification requests cannot silently enter an unreviewable queue. `list_my_verification_workspaces` derives choices from existing membership/verified investor links or an unexpired server invitation matching the recipient's verified email. The explicit-workspace creation RPC validates that choice; the old signature works only for a unique trusted choice. An unrelated Explorer must obtain advisor context first. PAN single-match evidence can automatically scope only a uniquely attributable investor/workspace; ambiguous PAN requests remain quarantined.

Flutter passes the selected workspace for folio/manual verification, automatically retains a unique choice, and offers selection for multiple choices. The token RPC independently proves the selected folio belongs to the linked investor in that workspace. Unknown/ended membership and assignment states do not appear active. Account state no longer claims access to all portfolios. Folio submission also uses a UUID correlation identifier, as required by the existing RPC.

## Validation and remaining debt

The dedicated [SQL harness](../../scripts/test_authorization_containment_sql.sh) runs the full migration chain in a fresh network-disabled Supabase PostgreSQL container, inserts historical fixtures before the new migration, and exercises real authenticated/service roles. It includes shared-investor/shared-folio and unrelated-tenant BOLA tests; membership/workspace/profile/Auth lifecycle; invitation/role-metadata attacks; generic/PAN/folio decisions; investor and advisor orders; NSE; private documents; Family Guest consent; and exact ACL/policy checks. Concurrent tests cover retained-token revocation while cancellation waits, duplicate invitation acceptance, and repeated/concurrent verified-email bootstrap.

SQL fixtures explicitly provision trusted profiles because current public signup deliberately creates none. Existing order tests retain their denial assertions and accept the centralized `not_authorized` error in addition to prior downstream denial codes. The old ingestion test's blanket denial of service-role SELECT on identity metadata did not match baseline full-schema grants; the test now distinguishes that retained metadata debt from private OAuth secrets. No table privilege was broadened to make tests pass.

Final local validation:

| Check | Result |
|---|---|
| `bash scripts/test_authorization_containment_sql.sh` | PASS: fresh complete migration replay; 9 SQL suites; 117 named containment assertions; signup concurrency, revocation while cancellation waits, concurrent invitation acceptance. |
| Targeted Flutter command below | **253 passed**, 0 failed. Email signup/Explorer routing, existing investor/advisor flows, order/NSE interfaces and workspace selection included. |
| Flutter analysis of 26 changed/new Dart files | 0 errors; 43 existing dashboard warnings/info, all on identical lines in the base SHA. Other 25 files: **no issues**. |
| Deno check of shared authorization, `daily-nav-updater` and `sign-stamp-invoice` | PASS. Caller-bound shared authorization test: **1 passed**, 0 failed. |
| Supabase `db lint` (`public,moneybowl_authz,nse_app`) | Baseline: 76 diagnostics, **4 errors**. Candidate: 59 diagnostics, **0 errors**. The only new diagnostics are 3 unused parameters retained in the disabled tokenless-approval signature; remaining 56 warnings are baseline debt. |
| Supabase `db advisors` | Baseline: **26 WARN**. Candidate: **14 WARN**, **0 new findings** by finding key. Remaining: 8 permissive-policy, 1 RLS-initplan, 3 mutable-search-path and 2 duplicate-index warnings. |

Both Supabase comparisons use separate full-schema disposable databases with networking disabled, not a linked/hosted project. The CLI's generic “remote database” label refers to explicit container-loopback `--db-url`. Existing ambiguous PL/pgSQL identifiers encountered in the exercised verification paths were corrected. Actual order qualification also exposed a historical return-column/table-composite mismatch; qualification and cancellation now return the actual row composite.

```bash
flutter test --no-pub test/investor_identity_models_test.dart test/authentication \
  test/features/orders test/features/nse_integration \
  test/folio_verification_repository_test.dart test/advisor_verification_review_test.dart \
  test/folio_verification_service_test.dart test/folio_verification_controller_test.dart \
  test/folio_verification_page_test.dart test/folio_verification_provider_test.dart \
  test/verification_status_screen_test.dart test/verification_workspace_picker_test.dart \
  test/pan_verification_test.dart test/admin_verification_queue_navigation_test.dart \
  test/portfolio/portfolio_ownership_test.dart
deno check supabase/functions/_shared/authorization.ts \
  supabase/functions/daily-nav-updater/index.ts supabase/functions/sign-stamp-invoice/index.ts
deno test --cached-only --allow-env supabase/functions/_shared/authorization_test.ts
```

The SQL harness names every suite: upgrade provenance, containment, email signup, NSE frontend, workspace ingestion authorization, Gmail OAuth, order RLS, sell/switch intent and order folio projections. This is a scoped containment regression set, not a claim that all historical repository suites or live provider integrations were exercised.

Remaining role debt includes global persona labels and dashboard routing, the advisor account-state projection, legacy `client` terminology, personal-workspace ownership history, organization-level ARN/EUIN modeling and bespoke future staff capabilities. These do not establish business authorization here. Some identity metadata still has baseline service-role table grants; service credentials remain a trusted server boundary. Accepted service-side financial/provider processing retains immutable original scope rather than requiring a historical initiating user to remain active forever.

No MFD application/approval UI, ARN/EUIN onboarding, sub-advisor hierarchy, public role selector, Platform Admin provisioning, deployment or production change is included. The MoneyBowl operator should eventually receive explicit Platform Admin authority through a separate controlled provisioning task, without an MFD workspace/profile requirement. **No account, including Ravi's, was changed.**

Next: independently review the local candidate, rehearse the migration against a disposable restored dataset, resolve ambiguous historical rows with evidence, then authorize a separate DEV rollout. MFD onboarding follows containment validation and that data review.
