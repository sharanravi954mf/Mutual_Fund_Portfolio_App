# MoneyBowl role model audit V1

Reviewed 2026-10-03 against freshly fetched `origin/develop` **`9f6888be717106cda4c873a3ff91d8575efbb7c3`**. Analysis/design only; this document is the only working-tree change. No accounts, application code, migrations, or Supabase environments were changed.

## 1. Executive summary

Normalize the existing architecture incrementally. MoneyBowl already separates authentication accounts, investor links, workspaces, and memberships, but several authorization paths still treat a global `advisor`/`admin`/`operations` label—or `account_state = advisor`—as platform-wide authority.

Public signup now correctly creates a profile-free Explorer. Verified, unique trusted investor matching can establish an investor link; signup metadata cannot grant roles. Retain that foundation. MFD approval should create an approved workspace business identity and scoped membership for the **existing auth account**, not change public signup or introduce another global business-role enum. [Signup][signup]

**Security conclusion:** current source contains actionable cross-workspace access and overbroad authorization gaps. Address these before admitting independent MFD organizations. Findings below trace the ordered migration chain, surviving policies, grants, RPCs, and Flutter consumers. This is a focused static review, not a production exploit test or full security scan; deployed migration state, ACL drift, existing role provenance, and actual affected records remain unverified. No database reset or tests that write data were run.

## 2. Current-state role matrix

`profiles.role` permits seven values; membership roles omit `platform_admin` and `user`; invitation roles additionally omit `client`. `profiles.user_id` is nullable and unique, so imported investors can precede authentication. [Workspace schema][workspace], [profile identity][profile-identity]

| Current role/state | Stored / purpose | Actual authority today | Target disposition |
|---|---|---|---|
| `platform_admin` | Global `profiles.role`; internal operator | Active profile enables explicit platform checks and audited, MFA-gated family-support overrides. Broad workspace bypasses were removed; order initiation/qualification is explicitly denied. Bootstrap nevertheless assigns `account_state=advisor`, enabling legacy `is_admin()` powers. No MFD application approval implementation exists yet. | Keep as separate platform grant; remove business-state inheritance. |
| `admin` | Global profile and workspace membership | Global value passes legacy advisor checks and Edge `requireAdvisor`. Workspace value manages membership/invitations; orders and NSE additionally require this admin to be the workspace owner. | Retire global value; retain **Workspace Admin** permission set, distinct from ownership and investment permissions. |
| `advisor` | Global profile, workspace membership, account state | Current MFD-side persona. Global value grants broad legacy access; membership grants workspace capabilities. Orders authorize workspace advisors without individual investor assignment; NSE requires assignment. | Keep **Advisor** as scoped professional function, not global authority. |
| `operations` | Global profile / workspace membership | Advisor dashboard; global `is_admin()`; workspace investor reads, audit/invitation reads, CRM and branding policies. `has_advisor_membership()` also includes it in auto-approval-rule write policies. Excluded by dedicated order-MFD, NSE, and ingestion checks. | Replace with explicit staff capabilities; unsafe as a least-privilege default. |
| `investor` | Profile identity / workspace customer membership | Investor dashboard; own investor links and financial access; own order initiation with investor membership. No qualification rights from this role. Referral eligibility expects an active `investor` profile. | Keep identity, separate from customer-workspace relationship. |
| `client` | Legacy profile / membership value | Investor-compatible bootstrap/UI and ingestion, but old dashboard and verification queries require `client`, while orders/referrals/NSE generally require `investor`. | Historical terminology with live dependencies; phase out, not an immediate rename. |
| `user` | Allowed only by profile constraint | No dedicated business workflow or authority found. Flutter silently parses it as `investor`. | Retire after inventory; never use as a fake Explorer profile. |
| `explorer` | `user_accounts.account_state` | Neutral account, no required profile/workspace; exploration and explicit linking choice. | Keep as derived onboarding/persona label, not an authorization grant. |
| `link_pending` | Account state | Explicit investor-verification workflow; no investor ownership or MFD grant by itself. | Keep as linking workflow state. |
| `linked_investor` | Account state | Used with an active investor-account link for investor access and routing. | Derive from verified link; do not make it exclusive with professional membership. |
| `advisor` account state | Account state | Routing plus real authorization through `is_admin()` and folio assignment; now covers advisor, admin, operations, and platform admin profiles. | Retire as authority; compatibility projection only during transition. |
| `active/inactive/suspended` | Profile `account_status`, membership `status` | Different suspension scopes; enforcement varies across helpers. Membership also has `ended_at`. | Retain separate account and membership lifecycle checks. |
| `active/suspended/archived` | Workspace status | Explicitly enforced by newer NSE/ingestion/invitation paths, not all older helpers. | Retain organization lifecycle as an independent deny condition. |

Authority evidence: [legacy RBAC][rbac], [platform boundary][platform], [membership helpers][membership-helpers], [orders][orders], [order RLS][order-rls], [NSE][nse], [ingestion][ingest], [rule policies][rule-policies], [Flutter roles][flutter-role]. Policy permissions on older tables still depend on deployed table ACLs; explicit browser grants confirm access to profiles, accounts, links, portfolios, transactions, memberships, assignments, and invitations. [Browser ACLs][browser-acl]

Other meaningful concepts:

- **MFD / owner:** `workspaces.owner_profile_id` records ownership; there is no `owner` membership role. Historical backfill created personal workspaces for every profile, including investors—ownership alone is not proof of an approved MFD. `WorkspaceService.createWorkspace` still attempts direct insertion, but the platform workspace-write policy was removed. [Workspace][workspace], [platform][platform], [workspace service][workspace-service]
- **Professional data:** `advisor_profiles` stores one ARN-bearing record per profile, not per organization; `advisor_euin_assignments` stores EUIN strings attached to that record, not staff membership or reporting lines. Neither proves approval or grants the reviewed order/NSE permissions. Legacy `distributor_details` is also not workspace-scoped. No first-class sub-advisor/staff hierarchy or MFD application lifecycle was found. NSE sub-broker/EUIN report fields are provider data, not application roles. [Professional schema][professional]
- **Relationships:** `advisor_investor_assignments` lacks `workspace_id`; validation requires some shared active workspace. Folio `verification_request_assignments` is a separate auth-account-to-request relationship, with a single-advisor fallback. Family delegation is consent-backed access, not an investor or MFD role. [Workspace][workspace], [folio][folio], [platform][platform]

## 3. Problems and ambiguities found

1. **High-priority cross-workspace disclosure.** `portfolios_workspace_select` calls `can_access_investor(client_id)`, which checks shared membership in *any* workspace, not `portfolios.workspace_id`; transaction access inherits it. An advisor/operations user in A can therefore read investor I's B portfolios when I also belongs to A. Authenticated SELECT is explicitly granted. Workspace admins can also directly insert investor memberships using a known profile ID without an investor-consent/provenance check, potentially manufacturing that shared relationship. [Access helper and policies][platform], [membership policies][workspace], [ACLs][browser-acl]
2. **Workspace authority escapes into global authority.** `is_admin()` accepts active global advisor/admin/operations profiles **or** advisor account state, with no workspace. Surviving policies expose all account/link rows; non-folio review RPCs list and act on requests without workspace/assignment authorization. An accepted advisor invitation creates a global advisor profile for a profile-free recipient, so a tenant invitation confers these unrelated powers. Legacy factsheet, distributor, CAMS-statement and ingestion-log policies also use this helper. This is an authorization defect, not a signup-role injection: the latest signup fix does block self-declared privileged metadata. [RBAC][rbac], [account/link reads][verification-foundation], [review RPCs][verification], [signup/invitations][signup]
3. **Revocation is incomplete.** `is_workspace_admin`, `current_user_workspace_ids`, shared-profile access and order-MFD helpers test membership `status` but omit `ended_at`, profile suspension and/or workspace suspension. A retained token can still call these paths after the UI blocks access or an ended membership remains `active`. Ingestion checks workspace and membership lifecycle but omits profile status; NSE checks more of these layers. This is primarily missing database checks, not stale role claims. [Workspace helpers][workspace], [orders][orders], [ingestion][ingest], [NSE][nse]
4. **“Admin/advisor” means different things per feature.** Orders allow any active advisor membership or owner+admin; NSE requires owner+admin or assigned advisor; generic verification uses global `is_admin`; Edge `requireAdvisor` accepts only global `admin`, without account-status checks, for NAV/Excel-metadata administration. `operations` can reach policies for automatic-approval configuration despite being excluded from manual qualification. Do not reuse it unchanged for staff. [Orders][orders], [NSE][nse], [Edge helper][edge-auth], [rule policies][rule-policies]
5. **Relationship and credential boundaries are incomplete.** A person-pair advisor assignment can be reused across multiple shared workspaces because it has no workspace key. Advisor profiles have self-write policies without an approval gate, and the older `advisor_profiles_read USING(true)` / `advisor_euin_select USING(true)` policies survive narrower additions; with table grants, those reads remain broad. Credential rows must not become approval evidence merely because they exist. [Professional schema/policies][professional], [rule policies][rule-policies]
6. **Routing and compatibility obscure authority.** Bootstrap maps platform operators and operations to the advisor dashboard; there is no dedicated platform destination. Existing investor profiles are not promoted when accepting an advisor invitation, leaving membership and global-profile routing inconsistent. The admin dashboard filters `role='client'` despite the migration to `investor`; generic/PAN verification retains client-only candidates. Folio submission fails closed unless exactly one `advisor` account exists globally. Unknown Flutter role/status values default to investor/active instead of an unavailable state. [Signup][signup], [AuthProvider][auth], [RouteGuard][routing], [dashboard][dashboard], [verification][verification], [PAN][pan], [folio][folio], [Flutter roles][flutter-role]
7. **JWT history needs accurate treatment.** Earlier `app_metadata.user_role` admin policies/override RPCs are replaced or dropped by later hardening, especially Issue #31. No surviving role authorization based on `app_metadata` was identified in the reviewed migration chain. JWT `aal2` still proves step-up authentication; API `service_role` claims identify server execution. Do not report superseded JWT policies as current vulnerabilities. Older deployed schemas could differ, and reintroducing JWT membership lists would create revocation lag. [Platform hardening][platform]; [Supabase RLS guidance][supabase-rls]

Referrals are a separate entitlement/provenance system: codes and conversion require an active investor profile; a claim can bind to the new auth account before investor resolution. A profile-free Explorer cannot currently issue investor referral codes. Claims/rewards must never grant MFD authority or motivate creating a fake profile. [Referral eligibility][referrals], [claim lifecycle][referral-claims]

## 4. Recommended target model

| Dimension | Source of truth | Meaning |
|---|---|---|
| A. Account/authentication | `auth.users` + `user_accounts` | Verified sign-in and global account status. Separate linking/application workflows; Explorer means no established business context. |
| B. Platform authority | Restricted platform grants keyed to auth account | `platform_admin` initially; explicit capability such as `mfd_applications.review`. No automatic tenant membership. |
| C. Business identity | Existing investor identity/link; approved MFD identity attached to workspace | A person can be an investor and an MFD professional simultaneously. ARN belongs to the approved business; personal credentials belong to the professional. Neither alone is permission. |
| D. Workspace authority | Active, non-ended memberships + explicit capability mapping | `admin`, `advisor`, `staff`; ownership remains an explicit workspace relationship. Each grant belongs to one workspace. |
| E. Relationships | Workspace-scoped investor relationship, advisor assignment, consent/verification grants | State which investor and records an actor may serve; never infer access from shared global labels. |

Reuse `workspaces` as the MFD organization boundary for V1; add an approved business-identity record keyed to it. Avoid introducing another organization hierarchy until a real need appears. Keep profile IDs and existing investor links stable. An ordinary actor profile can support membership/auditing without being an investor or ARN-bearing MFD profile; Explorers need no such record until a trusted workflow requires one.

One person may hold different memberships in multiple MFD workspaces. One investor identity may have multiple MFD relationships. Existing one-active-account-to-investor-link uniqueness can remain: it links authentication to identity, not identity to one distributor. Keep portfolios, orders, permissions and reporting explicitly separated by workspace; no implicit cross-MFD aggregation. [Identity/link constraints][identity]

## 5. Recommended terminology

Use **MoneyBowl Platform Admin**, **MFD Organization**, **Workspace Owner**, **Workspace Admin**, **Advisor**, **Operations Staff**, **Investor**, and **Explorer**. Reserve “active/suspended” for lifecycle status. “Linked investor” describes verified identity resolution; “assigned advisor” describes a relationship. Retire global `admin`, `advisor`, `operations`, `user`, and eventually `client` as authorization sources. Keep historical audit labels readable rather than rewriting them.

## 6. Recommended MFD hierarchy

| Workspace position | Default responsibility |
|---|---|
| Owner | Business accountability, ownership transfer and administrator appointment; requires approved organization and active membership. |
| Admin | Scoped team/organization administration. No platform powers; investment permissions require an explicit approved professional capability. |
| Advisor | Service assigned investors; permitted order/verification actions require the relevant capability and relationship. |
| Operations Staff | Explicit back-office tasks; no qualification, automatic-approval-rule management, identity linking or role management by default. |

The initial MFD owner should receive ownership + workspace admin membership, plus explicitly approved professional capabilities when appropriate. **No global advisor role is required in the target model.** Existing advisor/admin labels can temporarily remain for compatibility after boundary fixes.

Today, an owner using both Flutter and NSE generally needs a global advisor/admin profile, `account_state=advisor`, workspace admin membership, and `owner_profile_id`. That duplication describes current compatibility requirements, not the target model. [NSE][nse], [routing][routing]

“Sub-advisor” should be an advisor membership with restricted assignments and, if needed, a workspace-scoped supervisor relationship—not a global identity role. Do not conflate supervision with financial approval. Retain the documented ability for the same authorized MFD user to initiate and qualify an order; this does not permit investors or platform operators to qualify it. [BRD][brd]

## 7. Proposed MFD onboarding state flow

```text
Public signup → email verification → trusted identity resolution
                                  ├─ unique trusted investor → linked investor
                                  └─ otherwise → Explorer

Existing authenticated account → application draft → submitted → under review
                                                      ├─ changes requested → resubmitted
                                                      ├─ rejected / withdrawn
                                                      └─ approved → atomic provisioning
                                                                    → active MFD workspace
```

Application status is separate from account state. Pending/rejected applicants retain their existing Explorer/investor access; applying grants no MFD authority. Permit investors to apply too, preserving their investor identity.

Approval must use a current platform grant and step-up authentication. In one audited, idempotent transaction: lock/check application version and applicant identity, validate business evidence and duplicate organization ownership, create/reuse the applicant's actor profile, create the approved workspace/business identity, and grant owner/admin membership and approved capabilities. Commit approval and provisioning together; otherwise retain a non-active retryable state. Store reviewer, evidence version, reason and outcome. An applicant cannot approve their own application.

For an existing Explorer, bind the application to the current `auth.users.id`; do not call signup again, relink by editable email, or overwrite an unrelated investor profile. Refresh server-derived capabilities after approval. Later staff invitations join an already approved organization; they do not constitute approval of a new MFD.

## 8. Authorization source-of-truth rules

- Database relationships identify the actor, beneficiary, workspace, investor linkage and assignment. Load resource scope from persisted rows; a client-supplied workspace ID is only a selector.
- Workspace membership/capabilities grant tenant actions. Check active account/profile, active workspace, active non-ended membership, resource workspace, relationship/consent and operation-specific capability on every sensitive request. Administrative membership changes must not create investor ownership or bypass consent; administrators may grant only permissions explicitly delegated to them, subject to professional eligibility.
- Platform grants authorize named platform operations only. Keep tenant data support narrow, audited and step-up gated. Server credentials are infrastructure identities, never human roles.
- Account state may deny access and describe onboarding; it cannot grant advisor/platform powers. Entitlements can further restrict a permitted action, never grant authority.
- `app_metadata` may carry server-controlled UI hints; do not make it the sole source for mutable authority. Never trust `user_metadata` for authorization. JWT authentication/assurance claims remain distinct from current database permissions. [Supabase][supabase-rls]
- `profiles.role` becomes a compatibility/display field, then is retired as a grant. Flutter consumes a server-derived capability/context projection; RouteGuard and dashboard visibility are UX checks, while RLS/RPCs enforce access.
- Restrict authority/link mutations to audited RPCs with caller-derived identity, explicit EXECUTE grants, an empty search path, and internal authorization. Generic `is_admin()` must not remain a fallback.

## 9. Areas eventually requiring changes

Database: legacy RBAC/workspace/access helpers and surviving policies; profile/account lifecycle; invitations and direct membership/assignment mutations; workspace-keyed assignments; advisor ARN/EUIN ownership; verification routing; order lifecycle authorization; narrowly scoped platform application RPCs. Preserve immutable order/audit provenance and existing investor-link IDs.

Flutter: `UserRole`, `AccountState`, membership parsing, `AuthProvider`, `AccountStateResolver`/`RouteGuard`, platform versus MFD dashboards, client filters, order/verification/NSE affordances, and workspace selection. Edge: replace `requireAdvisor` with operation-specific platform/workspace authorization. Referrals: retain signup provenance and explicitly decide whether Explorer referral issuance is a future product feature.

## 10. Compatibility and migration risks

- Inventory global roles, personal-workspace backfill, owner/member mismatches, ended-active memberships, client/investor consumers and original provisioning provenance. Do not assume every historical admin or workspace owner is a legitimate MFD; do not automatically promote historical metadata-derived roles.
- Add `workspace_id` to advisor assignments only after resolving ambiguous shared-workspace pairs; no arbitrary backfill. The current uniqueness key cannot represent independent assignments of the same pair in two workspaces.
- A single global enum cannot represent investor + advisor or different roles in multiple workspaces. Introduce capability-based routing before switching those accounts; preserve links and supported older clients during transition.
- Changing account-state semantics affects folio assignment, investor-link checks, NSE and bootstrap. Correct these consumers before removing `advisor`/`linked_investor` states. Additional MFDs already invalidate the folio single-advisor assumption.
- Reconcile policies **and** privileges: permissive policies combine with OR. Narrowing one policy does not remove older broad policies. Restricting reads can expose UI dependence on global lists; plan explicit scoped projections.

## 11. Recommended small implementation phases

1. **Contain authorization gaps first:** add focused local two-workspace/shared-investor and suspension/ended-membership regression coverage; correct portfolio/transaction scope and replace global account/link/non-folio-review access. Audit complete policy/ACL sets without changing business identities.
2. **Establish scoped authority:** centralized deny checks and small capability mappings; audited membership/invitation mutations; workspace-keyed assignments with fail-closed preflight for ambiguous data. Explicitly exclude staff from approval-rule management unless intentionally granted.
3. **Separate platform context:** restricted database platform grants, capability projection and dedicated operator routing. Preserve existing support override controls; inventory the operator's current configuration without automatic role migration.
4. **Implement MFD applications:** application/evidence/review lifecycle and atomic idempotent provisioning on the existing account. Test rejection, replay, concurrent approval, self-approval denial and existing investor preservation.
5. **Normalize compatibility:** migrate ARN/EUIN business scope, update dashboard/verification client filters and multi-workspace context, then retire obsolete global roles/account-state grants after consumer parity is verified.

Each phase should have its own bounded change and deny-path tests. Do not bundle onboarding with a global rename or rewrite of financial records. **Recommended next implementation task: Phase 1's portfolio/transaction cross-workspace boundary, with a shared investor in two workspaces as the regression fixture.**

## 12. MoneyBowl operator recommendation

The initial operator should ultimately hold **MoneyBowl Platform Admin**, with explicit `mfd_applications.review` authority, current database grant checks and step-up authentication. The current `platform_admin` concept is the correct semantic starting point; global `admin`/`advisor` and workspace ownership are not substitutes.

An operator needs an auth/account identity and may need an ordinary actor profile for audit compatibility. They should normally have **no MFD workspace membership, investor identity, or `advisor_profiles` business record solely to administer MoneyBowl**. Platform access must not inherit MFD investment permissions. Any separate business activity requires separately approved, scoped access. The named operator account was not inspected or changed during this review.

[signup]: ../../supabase/migrations/20261002221544_email_signup_verified_identity.sql
[profile-identity]: ../../supabase/migrations/20260718000001_unregistered_clients.sql#L4
[identity]: ../../supabase/migrations/20260722000001_identity_foundation.sql#L30
[workspace]: ../../supabase/migrations/20260730000001_user_management_workspace.sql
[rbac]: ../../supabase/migrations/20260730000000_core_auth_rbac.sql#L77
[platform]: ../../supabase/migrations/20260801000007_issue_31_platform_admin_family_access.sql
[membership-helpers]: ../../supabase/migrations/20260801000002_sprint_6_1_canonical_hardening.sql#L9
[orders]: ../../supabase/migrations/20260801000005_issue_29_order_request_audit_contract.sql#L11
[order-rls]: ../../supabase/migrations/20260801000006_issue_30_order_requests_rls.sql
[nse]: ../../supabase/migrations/20261002064309_nse_frontend_integration_v1.sql#L89
[ingest]: ../../supabase/migrations/20260823212258_issue_114_workspace_authorization_rpc.sql
[rule-policies]: ../../supabase/migrations/20260801000003_sprint_6_1_final_hardening.sql#L32
[browser-acl]: ../../supabase/migrations/20260808000000_browser_api_privilege_contract.sql
[professional]: ../../supabase/migrations/20260801000001_restore_develop_schema_prerequisites.sql#L277
[verification-foundation]: ../../supabase/migrations/20260724000000_verification_foundation.sql#L71
[verification]: ../../supabase/migrations/20260729000001_close_legacy_folio_authorization_bypasses.sql#L245
[pan]: ../../supabase/migrations/20260727000001_pan_release_blockers.sql#L146
[folio]: ../../supabase/migrations/20260729000000_advisor_folio_authorization.sql#L75
[flutter-role]: ../../lib/features/investor_identity/models/user_profile.dart
[routing]: ../../lib/features/authentication/services/route_guard.dart
[auth]: ../../lib/providers/auth_provider.dart#L125
[dashboard]: ../../lib/screens/admin_dashboard.dart#L280
[workspace-service]: ../../lib/services/workspace_service.dart
[edge-auth]: ../../supabase/functions/_shared/authorization.ts#L56
[referrals]: ../../supabase/migrations/20260814171810_issue_40_referral_mechanics.sql#L137
[referral-claims]: ../../supabase/migrations/20260815180000_issue_40_referral_claim_lifecycle.sql#L118
[brd]: ../business/BRD.md#L145
[supabase-rls]: https://supabase.com/docs/guides/database/postgres/row-level-security
