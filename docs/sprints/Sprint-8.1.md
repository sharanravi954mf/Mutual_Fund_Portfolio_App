# Sprint 8.1 — Sprint 6.1 Carryover & Security Stabilization
Target Repository Path: docs/sprints/Sprint-8.1.md

## Technical Specifications & Scope
Sprint 8.1 carries forward open database, Edge worker, audit, entitlement, subscription, and testing tasks from Sprint 6.1 following its closure on 6 August 2026, alongside newly registered security stabilization tasks. All implementations align with BRD v1.3.0 and SYSTEM_ARCHITECTURE v2.1.0.

### Carryover Context
Sprint 6.1 closed on 6 August 2026. Backlog tasks (#39, #40, #41, #43, #44, #48, #49, #50, #51, #53, #59) were initially carried forward administratively. Following detailed reconciliation against canonical requirements, completed tasks (#41, #43, #44, #48, #50, #51, #53, #59) were confirmed as fully implemented Sprint 6.1 work, leaving active carryover items (#39, #40, #49) in the Sprint 8.1 backlog.

In addition, Issue #95 was discovered on 8 August 2026 as a post-sprint security follow-up to address direct browser queries to protected folio tables in the order repository. Issue #95 is tracked as a Sprint 8.1 task and is not counted as incomplete original Sprint 6.1 scope.

## Task Checklist & Tracking
- [x] **feat(database): implement dual MFD and Investor subscriptions, billing-owner payment events and entitlement RLS (completed the forward-only Investor lifecycle, atomic idempotent payment processing, immutable transition audit, and billing-derived entitlement RLS) [BRD-FR-010, BRD-BR-011, Section 5, Section 13]** (#39)
- [x] **feat(database/flutter): complete Investor referral mechanics with caller-bound idempotent code creation, `/join?ref=` web/Android onboarding attribution, exactly-once post-profile conversion, atomic concurrency-safe conversion, server-timed 30-day Premium Investor entitlement authorization for both participants, immutable reward audit evidence, exclusive profile-resolved RLS, exact API grants, and encoded WhatsApp sharing [BRD-FR-011, Section 12, Section 13]** (#40)
- [ ] **feat(database): implement profile-resolved Family Access lifecycle, consent RPCs, assisted flows and workspace-matched read-only RLS (scope includes owner creation, delegate acceptance/rejection, owner/delegate revocation, MFD-assisted workflow, narrow Platform Admin support path, no broad FOR ALL, document-access boundary, and audit events) [BRD-BR-009, Section 4, Section 6.F, Section 11, Section 17.F]** (#49)
- [x] **security(database/flutter): replace direct browser access to protected folio mapping/reference tables in Buy/Sell/Switch order flows with narrow SECURITY DEFINER projection RPC(s), preserving folio ACL isolation, caller-bound authorization, masked-only folio disclosure, exact investor/workspace/portfolio/folio isolation, and positive/negative SQL + Flutter regression coverage [BRD-FR-005, BRD-BR-003, Section 3.A, Section 6.A, Section 17.F]** (#95 / PR #97)

### Administrative Reconciliation
The following issues were initially carried over to Sprint 8.1 administratively, but were subsequently confirmed to have already been fully implemented during Sprint 6.1 work and have been closed as completed:
- **#41** — `test(database/edge): add auto-approval outbox, replay, rule-validation and race-condition tests` (Delivered via PR #92)
- **#43** — `feat(database): implement event_outbox table and transactional triggers` (Delivered via Issue #29 / PR #83 and PR #92)
- **#44** — `feat(database): implement membership-based RLS policy for workspace isolation` (Delivered via Issue #30 / PR #84 and subsequent PR #94 hardening)
- **#48** — `feat(database): create advisor-only qualify_order SECURITY DEFINER RPC` (Delivered via Issue #29 / PR #83, PR #90 and PR #88)
- **#50** — `feat(database): create auto_approval_rules table` (Delivered via PR #92)
- **#51** — `test(database/edge): add pgTAP and service-level tests` (Delivered via PR #88, PR #90, PR #92 and PR #93)
- **#53** — `feat(database): create plan_entitlements table` (Delivered via PR #87)
- **#59** — `feat(database): create service-only apply_auto_approval_decision RPC` (Delivered via PR #92)
