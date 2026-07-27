# Money Bowl MVP — Progress Report & Revised Roadmap

**Document Version**: v2.0 (BRD-aligned rebaseline)
**Report Date**: 2026-07-27
**Supersedes**: v1.0 (2026-07-26), authored before the Sprint 6.1 schema landed on `main`
**Governing Baselines**: BRD v1.2.1 (Final Approved) · SYSTEM_ARCHITECTURE v2.0.1-Canonical-Production-Freeze
**Architecture Status**: Canonical production-freeze baseline approved
**Application Status**: Pre-alpha — backend schema substantially landed, order/commercial UI not started
**Release Readiness**: Not ready

---

## 0. What Changed in This Revision

v1.0 was written against an assumed schema and a stale scope model. It has been rebaselined against the BRD. The material corrections:

| # | v1.0 claim | Correction |
|---|---|---|
| 1 | "Overall Project Completion: 90% (per PROJECT_STATE.md)" | `PROJECT_STATE.md` contains no such figure. It states *architecture complete, application pre-alpha, release readiness: not ready*. Percentage removed in favour of per-requirement status. |
| 2 | "Order workflow is 0% complete" | The Sprint 6.1 migration `20260801000000_brd_v1_2_1_execution_subscriptions_referrals.sql` **has landed on `main`**: `order_requests`, `auto_approval_rules`, `event_outbox`, `qualify_order`, `cancel_order`, RLS policies. The gap is now UI + the auto-approval worker, not the schema. |
| 3 | Planned tables `orders`, `order_queue`, `distributor_relationships` | Not the canonical names. BRD/architecture use `order_requests`, `event_outbox`, and `workspace_memberships`. All references corrected. |
| 4 | Planned edge function `order_router` | Canonical name is `order-auto-approval-worker` (Architecture §6.B, Sprint 6.1 #33). Orders are routed by a transactional outbox trigger, not by an HTTP router function. |
| 5 | "Deferred to v1.1: Subscriptions & Billing, Family Portfolio" | **Not deferrable.** BRD §9 places the Dual Subscription Engine and the Referral System inside the v1.2 in-scope baseline, and BR-009 Family Access is a stated business rule. Moved back into MVP scope. |
| 6 | BC mappings (BC-011 = investor verification, BC-013 = invoice signer, BC-003 = workspace mgmt) | Wrong. BRD §5: BC-011 = Document Management (Lineage), BC-013 = Document Storage & Vaulting, BC-003 = Investor Lifecycle Management. Remapped. |
| 7 | "PII is masked across UI ✅ (NEEDED)" | Self-contradictory. Actual state: server-side masked projections exist inside the verification slice only; there is no cross-app masking utility and no step-up reveal (NFR-001). Marked Partial. |
| 8 | No coverage of FR-001, FR-003, FR-010, FR-011, BR-004, NFR-004, NFR-005 | Full FR / BR / NFR coverage matrix added (§3). |
| 9 | Success criteria listed "80%+ coverage" and Firebase/Sentry rollout | Neither appears in the BRD or the architecture, and no Firebase/Sentry dependency exists in `pubspec.yaml`. Replaced with the BRD's own SLAs (NFR-001 – NFR-005). |

---

## 1. Scope Contract (BRD §9 — binding)

**In scope for MVP** (may not be descoped without a BRD amendment):
Mutual Fund Portfolio Management · Investor Order Requests (Buy/Sell/Switch) · MFD Transaction Approval Queue · Dual Subscription Engine · AMFI Scheme Factsheets (free API sync) · Universal Search & Discovery Bar · Investor Referral System · Exploring Standalone Investor Flow · Admin Supersede & Override · Mandatory PII Security & Masking.

**Out of scope** (BRD §9 — do not build):
Direct unassisted order execution without an MFD · Stocks/equity, insurance, FDs, crypto · Personalised AI investment advice or scheme routing · Automated portfolio rebalancing · Tax filing / IT returns.

**Legitimately deferrable to v1.1** — capabilities present in the BRD taxonomy but *absent from the §9 in-scope list*:
BC-007 Educational AI Assistant (FR-012, FR-013) · BC-008 Customer Servicing / Ticketing (FR-014) · BC-012 Actionable Notifications · BC-014 Distributor Analytics Dashboard · BC-016 Platform Configuration UI.

---

## 2. Capability Status (BRD §5 taxonomy, ground-truthed against `main`)

| BC | Capability | Status | Evidence on `main` | Gap |
|---|---|---|---|---|
| BC-001 | Identity & Access Management | 🟢 Done | `RouteGuard` + `AccountStateResolver`, `bootstrap_identity()`, `is_admin()`, `has_active_investor_link()` | Password recovery flow unverified |
| BC-002 | Distributor Lifecycle Management | 🔴 Not started | `advisor_profiles` (ARN/EUIN columns only) | No self-registration, no ARN certificate upload, no Admin review queue (FR-001) |
| BC-003 | Investor Lifecycle Management | 🟢 Done | `profiles`, onboarding choice RPC, explorer + linking destinations | — |
| BC-004 | Relationship Management | 🟡 Partial | `workspace_memberships`, invitations, assignments, `family_delegations` + RLS | No investor→MFD link request UI, no MFD acceptance UI, no relationship context switching |
| BC-005 | Portfolio Management | 🟡 Partial | `portfolios`/`folios`/`transactions`, XIRR + absolute return in `lib/utils/finance.dart`, `portfolio_dashboard_service.dart` | Capital gains absent; BR-004 no-consolidation invariant unenforced in code |
| BC-006 | Registrar Data Ingestion | 🟢 Done | `cams-kfintech-ingestion` edge function (IMAP → ZIP → DBF, in-memory) | NFR-004 15-min SLA never measured |
| BC-007 | Educational AI Assistance | ⚪ Deferred v1.1 | — | Out of §9 in-scope list |
| BC-008 | Customer Servicing (Ticketing) | ⚪ Deferred v1.1 | — | Out of §9 in-scope list |
| BC-009 | Dual Subscription & Billing | 🟡 Partial | `subscription_plans`, `plan_entitlements`, `workspace_billing`, `payment_events`, `sync_billing_workspace_limit()` | No feature-gating enforcement in the client, no plan management UI (FR-010) |
| BC-010 | Platform Governance & Administration | 🟡 Partial | `platform_admin` RLS policies, `workspace_audit_logs` | No supersede/override RPCs, no admin UI (FR-003, Sprint 6.1 #31) |
| BC-011 | Document Management (Lineage) | 🟡 Partial | `ingestion_logs`, `ingested_documents` | No lineage/error surface in UI |
| BC-012 | Actionable Notification Management | ⚪ Deferred v1.1 | — | Out of §9 in-scope list |
| BC-013 | Document Storage & Vaulting | 🟡 Partial | `sign-stamp-invoice`, `ingested_documents`, invoice signer feature slice | No investor-facing statement vault / signed-URL download |
| BC-014 | Distributor Analytics Dashboard | ⚪ Deferred v1.1 | — | Out of §9 in-scope list |
| BC-015 | Universal Search & Discovery | 🔴 Not started | `fund_search_service.dart` (scheme lookup only) | No global search bar; no folio/transaction/document/ticket search (FR-007, NFR-002) |
| BC-016 | Platform Configuration | ⚪ Deferred v1.1 | — | Out of §9 in-scope list |
| BC-017 | AMFI Scheme Factsheets & Market Data | 🟡 Partial | `fund_factsheets` table, `factsheet_dialog.dart`, `daily-nav-updater` | Deviates from BR-012 — see §5 |
| BC-018 | Investor Referral Engine | 🟡 Partial | `investor_referrals`, `referral_conversions`, `referral_rewards` + RLS | No code generation, no share flow, no conversion tracking, no reward grant (FR-011) |

Legend: 🟢 done · 🟡 partial · 🔴 not started · ⚪ deferred to v1.1 per §1.

---

## 3. BRD Requirement Coverage Matrix

### 3.1 Functional Requirements

| FR | Requirement | Status | Blocking work |
|---|---|---|---|
| FR-001 | Distributor self-registration with ARN, firm details, document upload | 🔴 | MFD onboarding schema + upload + Admin review queue |
| FR-002 | Standalone Exploring Investor registration without distributor mapping | 🟢 | — |
| FR-003 | Platform Admin supersede / account recovery / access reset tools | 🔴 | Audited override RPCs + admin UI (#31) |
| FR-004 | PII masked by default across UI (`XXXXX1234F`) | 🟡 | Cross-app masking utility; apply to portfolio/profile/transaction screens |
| FR-005 | Investor initiates Buy/Sell/Switch within their relationship view | 🟡 | Schema done; order modal missing (#34) |
| FR-006 | Orders route to the mapped Distributor's approval queue | 🟡 | Schema + outbox trigger done; MFD queue UI missing (#35) |
| FR-007 | Universal Search bar across schemes, folios, transactions, documents, tickets | 🔴 | Search RPC + top-nav component |
| FR-008 | Scheme factsheets: AMC, category, NAV history, expense ratio, riskometer, top holdings | 🟡 | Present via live third-party proxy, not the BRD's local-table model |
| FR-009 | IMAP/OAuth mailbag CAMS/KFintech extraction | 🟢 | OAuth path unverified — current deploy path is IMAP password/app-password |
| FR-010 | Dual subscription plans with feature gating and client limits | 🟡 | Client-side entitlement checks + plan UI |
| FR-011 | Referral link generation, signup tracking, trial rewards | 🟡 | Generation/share/tracking logic + UI |
| FR-012 | Educational AI Assistant | ⚪ v1.1 | — |
| FR-013 | AI declines advice prompts | ⚪ v1.1 | — |
| FR-014 | Support tickets to distributor queue | ⚪ v1.1 | — |

### 3.2 Business Rules

| BR | Rule | Status | Note |
|---|---|---|---|
| BR-001 | Single global investor identity (PAN + contact) | 🟡 | `pan_hmac`, `normalised_phone_hmac`, `normalised_email_hmac`, `identity_match_status` columns exist; no resolution logic runs against them |
| BR-002 | N distributor relationships per investor, isolated views | 🟡 | `workspace_memberships` supports it; no context-switching UI |
| BR-003 | Distributor cannot query another distributor's holdings | 🟢 | Workspace-membership RLS; covered by `supabase/tests/` |
| BR-004 | No merged cross-distributor return view | 🔴 | **Unenforced.** No guard prevents a future aggregate view; needs an explicit invariant + test |
| BR-005 | All investor transactions need approval or auto-approval | 🟡 | Enforced in `qualify_order`; no submission path yet |
| BR-006 | Configurable auto-approval rules | 🟡 | `auto_approval_rules` table + RLS; no evaluator, no rules UI |
| BR-007 | Platform Admin supersede rights | 🟡 | RLS-level only; no audited override RPCs |
| BR-008 | PII masked by default | 🟡 | See FR-004 |
| BR-009 | Family access read-only, consent-backed | 🟡 | `family_delegations` + read policies + audit trigger; no consent UI |
| BR-010 | AI guardrails | ⚪ v1.1 | — |
| BR-011 | Premium features gated by plan | 🟡 | `plan_entitlements` exists; not enforced client-side |
| BR-012 | Factsheet metadata synced from free AMFI APIs into local schema | 🔴 | See §5 deviation |

### 3.3 Non-Functional Requirements

| NFR | Target | Status |
|---|---|---|
| NFR-001 | PII masked at rest and on screen; step-up auth to reveal | 🟡 PAN encrypted at rest with HMAC lookup; **no step-up reveal flow** |
| NFR-002 | Universal search < 200 ms | 🔴 Feature absent; unmeasured |
| NFR-003 | Order appears in approval queue < 5 s | 🔴 Unmeasured; depends on outbox → worker latency |
| NFR-004 | CAS attachment processed into portfolio records < 15 min | 🔴 Unmeasured |
| NFR-005 | Immutable timestamped audit logs for approvals, auto-approvals, overrides, resets | 🟡 `workspace_audit_logs` written by `qualify_order`/`cancel_order`; append-only enforcement and override coverage outstanding (#29, #51) |

---

## 4. Revised Roadmap — 5 Sprints to MVP

Sequenced so each sprint closes a BRD requirement set end-to-end. GitHub issue numbers refer to `docs/sprints/Sprint-6.1.md`.

### Sprint A — Close the Order Engine (FR-005, FR-006, BR-005, BR-006, NFR-003, NFR-005)
- Implement `apply_auto_approval_decision` service-only RPC with outbox-event idempotency and rule-version validation (#59) — **the single largest missing piece of the frozen contract**.
- Build `order-auto-approval-worker` Deno function with event-bound correlation and deterministic retries (#33).
- Reconcile `qualify_order` / `cancel_order` with Architecture §6.D–6.E (see §5 deviations) and prove it with pgTAP (#48, #28, #51).
- Enforce append-only `workspace_audit_logs` (#29).
- Exit: an order submitted by RPC reaches the advisor queue in < 5 s, auto-approves when a rule matches, and writes an immutable audit row.

### Sprint B — Order & Relationship UI (FR-005, FR-006, BC-004)
- Investor order modal: folio + scheme selection, Buy/Sell/Switch, amount/units validation (#34).
- MFD qualification queue screen with approve/reject + reason capture (#35).
- Auto-approval rules configuration UI (BR-006).
- Investor→MFD link request + MFD acceptance screens; relationship context switching (BC-004, BR-002).
- Exit: the full happy path is clickable in the app on both breakpoints.

### Sprint C — Security, Masking & Admin Governance (FR-003, FR-004, BR-004, BR-007, BR-008, NFR-001)
- Cross-app PII masking utility applied to every portfolio, profile and transaction surface.
- Step-up authentication to reveal masked values (NFR-001).
- Audited Platform Admin override RPCs + admin console (#31, FR-003).
- Encode the BR-004 no-consolidation invariant as an explicit architectural test.
- Exit: no unmasked PAN/bank value renders anywhere without step-up; every override is audited.

### Sprint D — Commercial Engine (FR-010, FR-011, BR-011, BC-009, BC-018)
- Client-side entitlement gating driven by `plan_entitlements`; MFD tier limits and upgrade path.
- Investor subscription tier surfaces (Free Exploring vs Premium).
- Referral code generation, WhatsApp/SMS/Email share, conversion tracking, trial reward grant.
- Exit: tier limits block the 26th client on Starter; a referral signup grants the trial to both parties.

### Sprint E — Discovery, Factsheets & Launch Readiness (FR-007, FR-008, BR-012, NFR-002, NFR-004)
- Migrate factsheets to the BRD model: local `amfi_factsheets` tables synced by a scheduled AMFI worker (see §5).
- Universal Search bar across schemes, folios, transactions, documents; measure against the 200 ms budget.
- Instrument and verify NFR-002/003/004 with real timings.
- Responsive audit across mobile / tablet / web breakpoints; `flutter analyze` error-clean; `sh supabase/tests/run_all.sh` green.
- Exit: all §6 criteria met.

---

## 5. Architecture / Implementation Deviations Requiring a Decision

These are contradictions between what is on `main` and the frozen v2.0.1 contract. Each needs either a code fix or a documented architecture amendment before MVP exit.

| # | Deviation | Evidence | Contract |
|---|---|---|---|
| D-1 | `qualify_order` accepts Platform Admins | `20260801000000_...sql:238,247` allows `app_metadata.user_role = 'platform_admin'` and lets admins transition out of `pending_qualification` | Architecture §6.D.3–4: "Platform Admins must not qualify, approve, or reject order requests" (also CHANGELOG v2.0.1) |
| D-2 | `cancel_order` resolves the caller as `investor_profile_id = auth.uid()` | `20260801000000_...sql:324` | §6.E.3 requires resolution via `public.current_user_profile_id()`; `profiles.id` is not the auth UID, so owner-initiated cancellation likely fails outright |
| D-3 | `cancel_order` returns success when the order is already `cancelled` | `20260801000000_...sql:317-320` | CHANGELOG v2.0.1: repeated cancellation from `cancelled` must be **denied**, not treated as a successful idempotent operation |
| D-4 | `apply_auto_approval_decision` does not exist | No match anywhere in `supabase/migrations/` | Architecture §6.C defines it as the service-role-only decision RPC; the entire auto-approval path depends on it (#59) |
| D-5 | Factsheets use a live third-party proxy | `fund_search_service.dart` calls `api.mfapi.in` through a `proxy-get` action on the `sign-stamp-invoice` function; table is `fund_factsheets`, not `amfi_factsheets` | BR-012 / FR-008 / BC-017 require local PostgreSQL storage synced from free **AMFI** APIs. Also couples market data to the invoice-signing function |
| D-6 | `daily-nav-updater` requires an advisor JWT (`requireAdvisor`) | `supabase/functions/daily-nav-updater/index.ts:16` | Architecture §3.C specifies a *scheduled cron* AMFI worker; it cannot run unattended with a user-role gate |
| D-7 | MFD onboarding entities absent | No `mfd_profiles`, `mfd_verification_documents`, `mfd_onboarding_reviews` in any migration | Architecture §2 BC-002 and FR-001 |

---

## 6. MVP Exit Criteria (BRD-derived, replaces v1.0's list)

**Functional** — every §9 in-scope item demonstrably working:
- [ ] Exploring investor can register standalone and browse factsheets (FR-002, FR-008)
- [ ] MFD can self-register with ARN + documents and be approved by an Admin (FR-001)
- [ ] Investor can link to an MFD and the MFD can accept (BC-004)
- [ ] CAS ingestion populates portfolios; investor sees folios, holdings, XIRR, absolute return (BC-005, FR-009)
- [ ] Investor can submit Buy/Sell/Switch; MFD sees and qualifies it (FR-005, FR-006)
- [ ] A matching auto-approval rule approves an order without MFD action (BR-006)
- [ ] Subscription tiers gate features and enforce client limits (FR-010, BR-011)
- [ ] Referral link produces a tracked signup and grants the trial (FR-011)
- [ ] Universal search returns schemes, folios and transactions (FR-007)
- [ ] Platform Admin can perform an audited supersede/reset (FR-003, BR-007)
- [ ] Family access grant is consent-backed and read-only (BR-009)
- [ ] No cross-distributor consolidated return view exists (BR-004)

**Non-functional** — measured, not asserted:
- [ ] Order visible in MFD queue < 5 s (NFR-003)
- [ ] Universal search < 200 ms (NFR-002)
- [ ] CAS processed to portfolio < 15 min (NFR-004)
- [ ] PII masked everywhere; reveal requires step-up auth (NFR-001, BR-008)
- [ ] Immutable audit rows for every approval, auto-approval, override and reset (NFR-005)

**Engineering gates**:
- [ ] `flutter analyze` reports zero errors
- [ ] `flutter test` green
- [ ] `sh supabase/tests/run_all.sh` green after `supabase db reset`, with new pgTAP coverage for #41 and #51
- [ ] All §5 deviations resolved or formally amended

---

## 7. Risk Register

| Risk | Impact | Mitigation |
|---|---|---|
| D-1 – D-4 unresolved (order RPC contract drift) | 🔴 Critical — the approval path is the MVP's reason to exist, and D-2 may make investor cancellation non-functional today | Fix in Sprint A before any order UI is built on top of it |
| BR-004 has no enforcement mechanism | 🔴 Critical — a single aggregate query silently violates the product constitution | Encode as an architectural test in Sprint C |
| NFR SLAs (002/003/004) never measured | 🟠 High — all four are currently assertions | Instrument in Sprint A and E; treat as release gates |
| Subscriptions/referrals/family were mis-scoped as v1.1 in v1.0 | 🟠 High — three in-scope BRD capabilities were about to be dropped | Restored as Sprint D + Sprint C |
| Factsheet data depends on an unofficial third-party API routed through the invoice signer | 🟠 High — availability and BR-012 compliance | Sprint E migration to local AMFI-synced tables and a dedicated worker |
| Legacy `admin_dashboard.dart` / `client_dashboard.dart` (~7k lines, inline Supabase access) | 🟡 Medium — new order/queue UI risks being bolted onto them | Build all new screens as `lib/features/*` slices following the `investor_verification` pattern |
| No PII masking utility while new screens are being added | 🟡 Medium — masking debt compounds per screen | Land the utility in Sprint C before Sprint D/E screens |

---

## Version History

| Version | Date | Notes |
|---|---|---|
| v2.0 | 2026-07-27 | Rebaselined against BRD v1.2.1 and SYSTEM_ARCHITECTURE v2.0.1. Full FR/BR/NFR coverage matrix, corrected BC mappings and canonical entity names, restored in-scope subscriptions/referrals/family, added architecture-deviation register (D-1 – D-7), replaced unsourced metrics with BRD SLAs. |
| v1.0 | 2026-07-26 | Initial MVP progress report based on a codebase audit. Superseded — see §0. |
