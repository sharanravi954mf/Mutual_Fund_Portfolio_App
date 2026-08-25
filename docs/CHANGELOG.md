# Changelog
Target Repository Path: docs/CHANGELOG.md

All notable completed releases of Money Bowl are documented here. This changelog follows the spirit of [Keep a Changelog](https://keepachangelog.com/).

This CHANGELOG.md is the sole authoritative release-history document. Historical release references found elsewhere are non-authoritative.

---

## Unreleased

### Added
- **External Ingestion Support Stack (#109)**: Added a provider-host-agnostic
  FastAPI and ClamAV Docker Compose stack implementing the unchanged mailbox
  OAuth, attachment fetch, PDF extraction infrastructure with deterministic
  synthetic characterization layouts, and malware scanning contracts expected
  by `cams-kfintech-ingestion`. Live registrar PDF layouts are not yet enabled.
- **Ingestion Contract and Threat Tests**: Added mocked Gmail provider tests,
  bounded pagination/backlog and OAuth-cache failure tests, strict
  bearer/size/redirect/timeout tests, synthetic registrar PDF fixtures, actual
  Edge parser compatibility tests, ClamAV `INSTREAM` protocol tests, and
  clean/EICAR/unavailable behavior coverage.
- **Hosted Dev Ingestion Operations (#113)**: Added a provider-agnostic Docker
  Compose override with pinned Caddy HTTPS ingress, exact single-replica
  enforcement, placeholder-only host configuration, an HTTPS-safe endpoint
  smoke test, and a deployment/rollback runbook. Hosted Dev deployment and
  encrypted Gmail OAuth smoke testing now reach attachment search; final
  synthetic ingestion remains pending under Issue #113.
- **Secure Gmail OAuth Provisioning (#114)**: Added the web-server
  authorization-code flow with exact redirect validation, Gmail read-only
  offline consent, expiring hashed single-use state, server-side exchange,
  AES-256-GCM first-write/reauthorization using the existing mailbox AAD, and
  nonce-fenced server-side revocation. No Hosted Dev or Production deployment
  was performed.

### Fixed
- **CAMS WBR2/WBR9 Mailback ZIPs (#113, related #109)**: CAMS Gmail discovery
  now accepts sender-filtered URL-mailback messages without requiring an
  attachment, recognizes only WBR2/WBR9 DBF responses, records WBR49/unknown
  reports as `unsupported_report`, accepts data only for the confirmed
  Link/validated-URL combination, and treats exact No Data/NA responses as
  legitimate zero-attempt outcomes. Mixed or unconfirmed statuses fail closed.
  Validated CAMS URLs download bounded
  password-protected ZIPs in memory and route the extracted DBF through the
  existing Edge integrity, malware, and parser path. Generic attachment and
  inline attachment flows remain intact; Production was not changed.
- **Inline Gmail Attachments (#113)**: Gmail polling now recognizes small
  attachment MIME parts returned as base64url `body.data` as well as normal
  `attachmentId` parts. Poll remains metadata-only; a bounded, scoped,
  expiring internal locator lets fetch re-read and validate the MIME part
  without caching or persisting attachment bytes.
- **Bounded Gmail Detail Polling (#113)**: Gmail page listing remains
  sequential, while a configurable fixed worker pool fetches per-page message
  details concurrently and restores listing order. Failures cancel and await
  sibling workers; existing timeout, page, candidate, response, and attachment
  bounds remain unchanged.
- **Sanitized Ingestion Diagnostics (#113)**: The support API now emits
  fixed-schema INFO JSON lines to container stdout for safe request outcomes,
  successful mailbox message/attachment counts, and sanitized ServiceError
  code/status. Uvicorn access logs remain disabled, duplicate handlers are
  prevented, and no body, provider identity, mailbox metadata, or credential is
  logged.
- **Bounded Gmail Message Details (#113)**: Gmail `format=full` detail calls now
  request only connector-required top-level fields plus the complete recursive
  MIME subtree needed for normal and inline attachments. A separate validated
  4 MiB detail ceiling leaves OAuth/list responses at 1 MiB and bounds the
  default five concurrent raw detail buffers at 20 MiB. Oversized required MIME
  data still fails closed; attachment, timeout, page, candidate, and concurrency
  limits are unchanged.

### Security
- **CAMS Mailback Boundaries (#113)**: Added exact HTTPS host/path validation,
  redirect rejection, bounded downloads/timeouts, CAMS-specific secret
  configuration, and encrypted ZIP entry/size/ratio/traversal/duplicate/nested
  archive controls. Sender validation remains post-read and precedes download;
  logs exclude sender, URL, request identity, password, and DBF content.
- **Zero-Disk External Processing**: Statement bytes stay in bounded memory,
  service tokens are capability-specific and constant-time compared, provider
  origins and Host headers are constrained, ClamAV remains private, and error
  responses/logging exclude document content and credentials.
- **Legacy Deployment Helper Retired**: `deploy_ingestion.sh` now exits without
  deploying or requesting direct IMAP credentials. Hosted Dev continues to
  deploy from `develop`; no hosted environment is changed by Issue #109.
- **Hosted Ingress Boundary**: Hosted Compose removes direct API exposure,
  publishes only Caddy on 80/443, retains private persistent ClamAV signatures,
  disables request access logging, and preserves one API worker/replica until
  #112 removes the process-local OAuth bridge.
- **OAuth Credential Boundary**: Authorization codes and tokens are never
  logged or persisted by the support service. The database stores no plaintext
  state or token fields; only state digests and existing encrypted credential
  envelopes are persisted behind least-privilege RPCs.
- **Ingestion Workspace Authorization (#114)**: Corrected the Hosted Dev
  ingestion/OAuth authorizer to validate the caller JWT and invoke a narrowly
  scoped authenticated `SECURITY DEFINER` RPC. The RPC returns only an
  authorization result, fails closed, and preserves the hardened business-table
  grants instead of requiring service-role `SELECT` access.
- **Hosted Edge OAuth Callback Boundary (#119)**: Callback routing now accepts
  only the configured external `/functions/v1/<function-name>/oauth/callback`
  pathname and its deterministically derived gateway-stripped
  `/<function-name>/oauth/callback` runtime pathname. The configured URI remains
  bound to hashed single-use state and is used unchanged for Google
  authorization and code exchange; caller-controlled host and forwarding
  headers are not trusted.

## Architecture and Documentation Baselines

### [v2.1.0 / v1.3.0] — 2026-07-28

#### Changed
- **Distributor-Assisted Initiation**: Authorized MFD-side users (workspace owners/advisors) can now initiate orders on behalf of actively mapped investors within their workspace.
- **Same-Profile Initiation & Qualification**: Explicitly permitted MFD-side profile to both initiate and qualify/approve/reject the same order request. Visible trace preserved in audit record (maker-checker requirement removed).
- **Metadata & Audit Hardening**: Expanded order submission and manual qualification audit fields matrix (actor, investor, initiator, reviewer, states, reason).
- **Subscription Domain Wording**: Clarified billing ownership, subscription lifecycle, and feature entitlements tracking across both MFD and Investor tiers.
- **Family Portfolio viewing limits**: Standardized viewing to consent-backed separate workspace switching, preserving no cross-distributor consolidation rules (BR-004).
- **GitHub Issue alignment**: Synchronized checklist and Issue scopes (#29, #30, #34, #35, #48, #51, #60).

### [v2.0.1] — 2026-07-27

#### Added
- Corrective Sprint 6.1 migration files were added to the repository.
- Platform Admin role wording correction in the role matrix notes.
- Removal of broad Platform Admin policies on `auto_approval_rules` and `event_outbox`.
- Family Access lifecycle RPC scope explicitly defined and restricted.
- Removal of broad Family Delegation `FOR ALL` policy.
- Step-up override auditing sequence enforced.
- Outbox claim/completion validation contract defined.
- Concurrency-safe event uniqueness index added for `order.created`.
- RPC search-path alignment to `SET search_path = ''` for qualify, cancel, auto-approval, family access, and Platform Admin RPCs.
- Audit-schema alignment adding canonical columns to `workspace_audit_logs`.
- Investor subscription trial state machine and payment RLS defined.
- Resolver verification result and unique mapping validation.
- Issue and Kanban synchronisation.

#### Changed
- Standardised application-profile authorization through `public.current_user_profile_id()`.
- Replaced direct `delegate_profile_id = auth.uid()` Family Delegation RLS logic with resolved application profile identity.
- Clarified that `owner_profile_id`, `delegate_profile_id`, and `investor_profile_id` reference `public.profiles.id`.
- Corrected issue `#51` to test resolved application profile ownership rather than Auth-UUID equality.
- Consolidated repeated-cancellation tests into the single `already_cancelled` denial contract.
- Added implementation verification requirements for `public.current_user_profile_id()`.
- Corrected issue `#28` traceability from stale Section 5.A/Section 4 references to Sections 6.A, 6.E, and 17.F.
- Clarified that `cancel_order` resolves the authenticated caller through `public.current_user_profile_id()` rather than comparing `investor_profile_id` directly with `auth.uid()`.
- Clarified that repeated cancellation from `cancelled` is denied and is not treated as a successful idempotent operation.
- Added matching cancellation identity and final-state test requirements to issue `#51`.
- Removed duplicated outbox-insertion test ownership from issue `#51`.
- Assigned all auto-approval outbox, replay, event-binding, and rule-validation tests exclusively to issue `#41`.
- Restricted issue `#51` to advisor qualification, cancellation, immutable-audit, and Platform Admin override testing.
- Removed Section 8 traceability from Sprint task and issue `#51`.
- Added `event_type` to the Platform Admin override audit-matrix contract (Section 17.F).
- Replaced the misleading `platform_admin_override_policy` traceability component with platform_admin_read_policies and platform_admin_override_rpcs (Section 18).
- Renamed issue `#41` to accurately represent auto-approval outbox, replay, rule-validation and race-condition testing.
- Clarified separation between auto-approval tests in `#41` and Platform Admin/order RPC tests in `#51`.
- Removed Platform Admin authorization from `qualify_order`, restricting manual qualifications strictly to active advisors and workspace owners.
- Clarified advisor-only order qualification rules, ensuring Platform Admins cannot qualify, approve, or reject order requests.
- Made auto-approval rule validation conditional by decision (strict rule validations when `auto_approved`; no rule lookup and null checks when `pending_review`).
- Bound auto-approval correlation IDs to matching `order.created` outbox events using UUID type.
- Defined replay-before-stale validation sequence in the service RPC.
- Added idempotency-conflict semantics for duplicate event replays.
- Converted Platform Admin override auditing to strictly append-only attempt and final-outcome events, prohibiting updates or deletions of audit rows.
- Corrected Sprint 6.1 and issue traceability for #31, #33, #41, #48, and #59.
- Removed every remaining reference to the nonexistent `docs/changelog/` directory.
- Aligned Platform Admin override audit-field requirements to match in Section 6.G and Section 17.F.
- Defined durable logging for failed override attempts using a separate database call committed before the mutation RPC.
- Clarified that Platform Admin mutation overrides use hardened SECURITY DEFINER RPCs rather than broad unrestricted RLS bypass.
- Added Platform Admin override test requirements in the database test suite.
- Defined stable outbox-based auto-approval idempotency keys (`auto_approval_correlation_id = event_outbox.id`) and uniqueness contracts.
- Added explicit rule-version equality validation.
- Corrected `apply_auto_approval_decision` privileges to service-role-only (revoked authenticated and public execution grants, granted exclusively to service_role).
- Updated Sprint 6.1 task checklists and issue traceability matrices to match v2.0.1 architecture headers.
- Removed remaining trigger-evaluation business rule logic wording from issue specifications and sprint planning.
- Synchronized GitHub issues and Kanban board card statuses.
- Replaced local file links (`file:///Users/...`) with repository-relative links across canonical documents.
- Clarified architecture readiness status (canonical production-freeze baseline approved) versus application execution status (pre-alpha implementation in progress).
- Added an audited Platform Admin override contract (Section 6.G).
- Corrected stale architecture section annotations.
- Defined null and rule-version semantics for auto-approval decisions inside the service RPC.
- Corrected Sprint 6.1 traceability for issues #29, #31, #51, and #59.
- Clarified legacy mutable audit schema status.

### [v2.0.0-Canonical-Production-Freeze] — 2026-07-27

#### Changed
- Pessimistic Order Race Guard: Restricted advisor qualification actions in `qualify_order` strictly to orders in `pending_review` status, preventing race conditions with the auto-approval pipeline.
- Unified Decoupled Outbox Flow: Configured the outbox auto-approval workflow triggering upon investor order insertion events.
- Revoked RPC Privileges: Revoked public access privileges on `qualify_order` and `cancel_order` functions, restricting executions solely to authenticated roles.
- Family Guest Workspace Exclusions: Standardized family delegation permissions mapping, allowing guest visibility checks without secondary workspace membership requirements.
- Taxonomy Mappings Expansion: Expanded the capability `BC-005` definition mapping order execution components.

### [v1.9.0-Canonical-Production-Freeze] — 2026-07-27

#### Summary
Release v1.9.0-Canonical-Production-Freeze refines system-wide authorization safeguards, auto-approval engines fallbacks, introduces a secure cancellation path, and standardizes the JWT claim structure.

#### Changed
- Auto-Approval Fallbacks: Non-matching transactions route explicitly to `pending_review` in the MFD queue.
- RPC Authorization & Row Locking Hardening: verify advisor memberships and platform admin overrides inside `qualify_order` under pessimistic `FOR UPDATE` locks.
- cancel_order RPC Function: Integrated `cancel_order` permitting investors and advisors to cancel orders in pending state and rejecting cancellation on finalized ones.
- Standardized JWT Claim Naming: Realigned RLS checks to use `(auth.jwt() -> 'app_metadata' ->> 'user_role')` and `(auth.jwt() -> 'app_metadata' ->> 'subscription_tier')`.
- Authoritative Family Delegation: Documented `family_delegations` accepted consent as the single authoritative source of truth for portfolio delegated access.

### [v1.8.0-Canonical-Production-Freeze] — 2026-07-27

#### Summary
Release v1.8.0-Canonical-Production-Freeze locks the System Architecture baseline, standardizing the order status lifecycles, hardening the qualify_order security-definer RPC with row locking and idempotent re-validation guards, enforcing consent verification for family delegation RLS, and detailing role-based sub-permissions.

#### Changed
- Standardized Order State Machine: Configured the order lifecycle flow: `draft ➔ pending_qualification ➔ pending_review ➔ auto_approved / approved / rejected / cancelled`.
- Hardened qualify_order RPC: Implemented concurrent row locking (`SELECT FOR UPDATE`), idempotent checks, set `search_path = ''` constraints, and revoked default execution permissions from PUBLIC.
- Enforced Consent checks on Family Delegation RLS: Hardened portfolios select policies to check `consent_status = 'accepted'` to prevent unconsented family guest access.
- JWT Claim & Workspace Sub-role Hierarchy: Standardized token validation logic and mapped workspace admin/operations sub-roles permissions.

### [v1.7.0-Canonical-Implementation-Baseline] — 2026-07-27

#### Summary
Release v1.7.0-Canonical-Implementation-Baseline applies final hardening adjustments to row-level security and service API boundaries. Specifically, it enforces RPC-only order qualifications for advisors (direct updates revoked), hardens the family RLS rules to match workspace and expiration filters explicitly, defines additional plan entitlement properties, and includes a searchable tools catalog projection in Section 15.

#### Changed
- RPC-Only Order Qualification: Revoked direct `UPDATE` permissions on `order_requests` from authenticated roles. Mutating order statuses is routed exclusively through the `SECURITY DEFINER` RPC `qualify_order` with set `search_path = public`.
- Workspace-Matched & Expiration-Hardened Family Delegation RLS: Hardened the portfolios read check to require explicit workspace ID matching and expiration limits validation (`expires_at IS NULL OR expires_at > now()`).
- Expanded Audit Log Scopes: Configured system triggers logging immutable audit entries upon family delegation creation, acceptance, revocation, and original CAS file downloads.
- Entitlements Extension: Added keys `advanced_analytics_enabled` and `support_sla_policy_id` to the `plan_entitlements` catalog.
- Searchable Tools Catalog: Added `searchable_tools` to Universal Search projections mapping calculators and factsheet paths.

### [v1.6.0-Final-Approved-Baseline] — 2026-07-27

#### Summary
Release v1.6.0-Final-Approved-Baseline updates the NFR identifiers to align 100% with the frozen BRD, enforces stricter RLS insert checking for investors, incorporates the qualify_order security-definer RPC design, explicitly classifies Aadhaar numbers as excluded PII elements, and introduces the plan entitlements data model.

#### Changed
- NFR ID Alignments: Re-mapped all capabilities in Section 18 to NFR-001 through NFR-005, and defined internal SLO thresholds for key validation and central logging.
- Hardened Order RLS & qualification RPC: Hardened the investor order insertion constraint to use `has_investor_membership(workspace_id)` and added explicit select RLS for advisors. Hardened transaction status mutation triggers to execute strictly via `qualify_order` RPC.
- Aadhaar PII classification: Added Aadhaar number and Aadhaar-derived identifiers to Section 17.C, strictly prohibiting Aadhaar details from search and logging pools.
- Plan Entitlements Model: Introduced the `plan_entitlements` entity supporting configurable gating options (Auto-approval limits, white-label flags, family-hub flags).
- Mailbox Health Notification Events: Documented mailbox connection, authentication failure, and poll failure states inside Section 8/12 triggers.

### [v1.5.0-Final-Production-Baseline] — 2026-07-27

#### Summary
Release v1.5.0-Final-Production-Baseline refines the System Architecture Specifications to v1.5.0 security compliance baseline, establishing role-segregated RLS policies, workspace-scoped family visibility delegations, auto-approval rules schemas, global identity resolution markers, and out-of-scope product boundaries.

#### Changed
- Role-Segregated Order RLS: Replaced generic order policies with distinct select, insert, and update policies for Investors, Advisors, and Admins, including explicit `WITH CHECK` clauses and normal user delete prohibitions.
- Workspace-Scoped Family Delegations: Realignment of the family delegation model to link to specific workspaces and standardizing on profile ID selectors to prevent unlinked visibility leaks.
- Vault Security Realignment: Added explicit document download denial constraints for family guest profiles.
- Advanced Auto-Approval Rule Table: Implemented schema entities for the `auto_approval_rules` engine and triggers recording execution rules.
- Global Identity Matching: Defined HMAC identity markers on profile entities (`pan_hmac`, `normalised_phone_hmac`, etc.) for deterministic resolution.
- Product Scope Boundaries: Defined Section 19 specifying out-of-scope boundaries (direct stocks, insurance, FDs, crypto, tax filing, etc.).

### [v1.4.0-Final-Baseline] — 2026-07-27

#### Summary
Release v1.4.0-Final-Baseline updates the traceability matrix capability mappings and persona details, implements a compliant document retention lifecycle policy, updates the secure file ingestion scan workflow, and implements role-segregated Row-Level Security policies with explicit `WITH CHECK` conditions on order requests and family delegation transactional tables.

#### Changed
- Traceability Matrix & Persona Updates: Map BC-016 Platform Config to N/A for functional requirements and associate with BRD Rules BR-006, BR-010, BR-012 under the "Configuration over Customisation" design principle. Refined BC-001 (Identity), BC-007 (AI Assistant), BC-009 (Subscriptions), and BC-012 (Notifications) mappings and personas.
- Document Retention Lifecycle Overhaul: Replaced the automated 30-day deletion of original vault files with a compliance-driven retention policy allowing temporary artifact pruning but preserving original files for legal and audit lineage.
- Secure File Ingestion Scan Workflow: Standardized file ingestion pipeline to explicitly run MIME & Magic-byte validation, malware screening, and SHA-256 hashing prior to encrypted object storage.
- Role-Segregated WITH CHECK RLS Policies: Implemented secure, dynamic membership-based RLS isolation policies on `order_requests`, `family_delegations`, and `portfolios` tables with explicit `WITH CHECK` blocks to prevent write bypasses.

### [v1.3.1-Final-Baseline] — 2026-07-27

#### Summary
Release v1.3.1-Final-Baseline applies precision improvements to the System Architecture baseline addressing all ChatGPT 5.5 review feedback points, logs the revision history, and updates the Sprint 6.1 issue traceability matrices.

#### Changed
- Many-to-Many Traceability Matrix: Refined capability maps (BC-002, BC-004, BC-005, BC-006, BC-008, BC-011, BC-012, BC-016) to map cleanly to requirements and tables.
- Distributor Analytics Dashboard Projection: Defined the schema and target fields for `mfd_dashboard_metrics` view/table aggregation.
- Canonical Persona Role Matrix: Added explicit mapping of BRD user personas to PostgreSQL application membership and auth roles.
- Ticket SLA target definitions: Updated static SLA targets to plan-configurable variables.
- Document Vault Security & Lineage: Documented file limits, content hashing, deduplication, and added immutable rules to `ingestion_logs`.

### [v1.2.1-synthesized] — 2026-07-26

#### Summary
Release v1.2.1 establishes the finalized canonical specification baseline for Business Requirements and System Architecture, and initializes Sprint 6.1 (Order Execution Engine, Subscriptions & Schema Extensions).

#### Changed
- Canonical Baseline Freeze: Populated and froze `docs/business/BRD.md` (v1.2.1) and `docs/architecture/SYSTEM_ARCHITECTURE.md` (v1.2.1 Synthesized 17-layer format).
- Sprint 6.1 Backlog Setup: Created and linked 8 core tasks on Project Board 1 (`MoneyBowl Development`) under the `Sprint Backlog` column.
- Repository Housekeeping: Pruned legacy, redundant specs and documents to focus the repository scope.

---

## Application Releases

## [Unreleased] — Target v1.2.0-alpha

### Planned
- Sprint 6.1 implementation outcomes.

---

## [v1.1.0-alpha] — 2026-07-19

### Summary
Release v1.1.0 introduces significant upgrades to the Admin Dashboard (Invoice Signer tab, in-memory batch ZIP processing), Client Dashboard features (Autocomplete search, factsheets, live wallpapers, time-of-day greetings), and registrar statement ingestion (decryption & auto-linking).

### Major Additions & Changes
- **Invoice Signer upgrades**: Standalone tab inside the Admin Dashboard supporting single PDFs and zipped archives. In-memory batch decryption, signing, and re-zipping.
- **Material 3 Dusty Rose Gold migration**: Migrated design seed color to `Color(0xFFC9B4BC)` across sidebar navigation drawer, metrics, cards, and tables.
- **Client Search & Factsheets**: Autocomplete mutual fund search on dashboard with modal factsheets.
- **Ingestion Pipeline Upgrades**: Deno engine parses password-protected ZIPs containing dBASE III `.dbf` statements. Standalone CAMs staging table imports, unregistered client ingestion, and auto-linking triggers.
- **Live Money Wallpaper**: Animated falling rupee symbols (`₹`) and golden wealth curves under Display settings.
- **Deduplicated greetings**: Unified time-of-day greetings on the main header appbar.

---

## Historical Development Milestones

### [v0.7.0-alpha] — 2026-07-22 (Internal Milestone)

#### Summary
Sprint 5.2 – Secure PAN Verification for client account linking.

#### Major Additions & Changes
- **PAN Verification Workflow**: Masked PAN lookups and Vault-backed encryption at rest.
- **Opaque Candidate-Tokens**: Token-bound approval mechanisms preventing UUID leak.
- **Immutable Request Evidence**: Safe conflict categorizations and audit records.

---

### [v0.6.1-alpha] — 2026-07-22 (Internal Milestone)

#### Summary
Sprint 4 – Onboarding and Identity Foundations.

#### Major Additions & Changes
- **Separated Identities**: Isolated Supabase Auth credentials from business profile records.
- **Advisor verification queues**: Verification assignment structures.
- **Row Level Security (RLS)**: Enforced client select filters based on active investor links.
