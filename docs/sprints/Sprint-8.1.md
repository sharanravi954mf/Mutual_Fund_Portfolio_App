# Sprint 8.1 — Sprint 6.1 Carryover & Security Stabilization
Target Repository Path: docs/sprints/Sprint-8.1.md

## Technical Specifications & Scope
Sprint 8.1 carries forward open database, Edge worker, audit, entitlement, subscription, and testing tasks from Sprint 6.1 following its closure on 6 August 2026, alongside newly registered security stabilization tasks. All implementations align with BRD v1.3.0 and SYSTEM_ARCHITECTURE v2.1.0.

### Carryover Context
Sprint 6.1 closed on 6 August 2026. Still-open backlog tasks (#39, #40, #41, #43, #44, #48, #49, #50, #51, #53, #59) were carried over into Sprint 8.1 with their existing workflow status preserved.

In addition, Issue #95 was discovered on 8 August 2026 as a post-sprint security follow-up to address direct browser queries to protected folio tables in the order repository. Issue #95 is tracked as a Sprint 8.1 task and is not counted as incomplete original Sprint 6.1 scope.

## Task Checklist & Tracking
- [ ] **feat(database/flutter): implement MFD and Investor subscription webhook workers and checkout flows (scope includes subscription webhook endpoints / Edge workers to handle payment provider callbacks, and Flutter UI plan selection / checkout / subscription status panels) [BRD-FR-010, BRD-BR-011, Section 5, Section 13]** (#39)
- [ ] **feat(flutter/edge): implement WhatsApp referral sharing, code registration validation, and referral reward credits (scope includes WhatsApp sharing integration, registered referral code validation, referral statistics/rewards UI dashboard, and Edge worker/scheduler to apply discount credits to active subscriptions upon referral conversions) [BRD-FR-011, Section 12]** (#40)
- [ ] **test(edge/ci): add auto-approval simulated HTTP gateway Edge integration tests and CI concurrency runner config (scope includes Deno Edge integration test suite simulating local gateway hooks, and CI configuration executing concurrency bash test scripts on every pull request) [BRD-BR-003, BRD-BR-006, Section 6.B, Section 6.C, Section 8]** (#41)
- [ ] **feat(flutter): integrate workspace context HTTP header interception and user switcher dropdown interface (scope includes Flutter client HTTP request interceptor injecting the active `x-workspace-id` header context, and frontend workspace context switcher visual dropdown selector) [BR-003, Section 5, Section 6.A]** (#44)
- [ ] **feat(flutter): build Family Access consent management hub and holdings view context (scope includes Flutter Family Hub screen managing delegation invitations, approvals, and revocations, and holdings/portfolio views dynamically restricted to consented family member profiles) [BRD-BR-009, Section 4, Section 6.F, Section 11]** (#49)
- [ ] **security(database/flutter): replace direct browser access to protected folio mapping/reference tables in Buy/Sell/Switch order flows with narrow SECURITY DEFINER projection RPC(s), preserving folio ACL isolation, caller-bound authorization, masked-only folio disclosure, exact investor/workspace/portfolio/folio isolation, and positive/negative SQL + Flutter regression coverage [BRD-FR-005, BRD-BR-003, Section 3.A, Section 6.A, Section 17.F]** (#95)

### Administrative Reconciliation
The following issues were initially carried over to Sprint 8.1 administratively, but were subsequently confirmed to have already been fully implemented during Sprint 6.1 work and have been closed as completed:
- **#43** — `feat(database): implement event_outbox table and transactional triggers` (Delivered via Issue #29 / PR #29 and PR #92)
- **#48** — `feat(database): create advisor-only qualify_order SECURITY DEFINER RPC` (Delivered via Issue #29 / PR #29 and PR #90 / PR #88)
- **#50** — `feat(database): create auto_approval_rules table` (Delivered via PR #92)
- **#51** — `test(database/edge): add pgTAP and service-level tests` (Delivered via PR #88, PR #90, PR #92, and PR #93)
- **#53** — `feat(database): create plan_entitlements table` (Delivered via PR #87)
- **#59** — `feat(database): create service-only apply_auto_approval_decision RPC` (Delivered via PR #92)
