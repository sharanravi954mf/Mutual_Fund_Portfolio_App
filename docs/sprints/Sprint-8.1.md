# Sprint 8.1 — Sprint 6.1 Carryover & Security Stabilization
Target Repository Path: docs/sprints/Sprint-8.1.md

## Technical Specifications & Scope
Sprint 8.1 carries forward open database, Edge worker, audit, entitlement, subscription, and testing tasks from Sprint 6.1 following its closure on 6 August 2026, alongside newly registered security stabilization tasks. All implementations align with BRD v1.3.0 and SYSTEM_ARCHITECTURE v2.1.0.

### Carryover Context
Sprint 6.1 closed on 6 August 2026. Still-open backlog tasks (#39, #40, #41, #43, #44, #48, #49, #50, #51, #53, #59) were carried over into Sprint 8.1 with their existing workflow status preserved.

In addition, Issue #95 was discovered on 8 August 2026 as a post-sprint security follow-up to address direct browser queries to protected folio tables in the order repository. Issue #95 is tracked as a Sprint 8.1 task and is not counted as incomplete original Sprint 6.1 scope.

## Task Checklist & Tracking
- [ ] **feat(database): implement dual MFD and Investor subscriptions, billing-owner payment events and entitlement RLS (scope includes subscription_plans, workspace_billing, investor_subscriptions, payment_events, Owner XOR, Investor-owned payment-event RLS, full state machine, and billing status/idempotency) [BRD-FR-010, BRD-BR-011, BC-009, Section 5, Section 13]** (#39)
- [ ] **feat(database): implement investor referrals, conversions, rewards and profile-resolved RLS [BRD-FR-011, BC-018, Section 12]** (#40)
- [ ] **test(database/edge): add auto-approval outbox, replay, rule-validation and race-condition tests [BRD-BR-003, BRD-BR-006, Section 6.A, Section 6.B, Section 6.C, Section 8, Section 17.F]** (#41)
- [ ] **feat(database): implement event_outbox table and transactional triggers (scope includes entity_id, entity_type, claim metadata, completion state, failure state, database uniqueness, transactional trigger, and duplicate-event protection) [Section 8]** (#43)
- [ ] **feat(database): implement membership-based RLS policy for workspace isolation [BR-003, Section 6.A]** (#44)
- [ ] **feat(database): create advisor-only qualify_order SECURITY DEFINER RPC restricted to pending_review orders (the qualifying MFD-side profile may be the same profile stored in initiated_by_profile_id, with no maker-checker denial) [BRD-FR-005, BRD-FR-006, BRD-BR-005, Section 6.D, Section 17.F]** (#48)
- [ ] **feat(database): implement profile-resolved Family Access lifecycle, consent RPCs, assisted flows and workspace-matched read-only RLS (scope includes owner creation, delegate acceptance/rejection, owner/delegate revocation, MFD-assisted workflow, narrow Platform Admin support path, no broad FOR ALL, document-access boundary, and audit events) [BRD-BR-009, Section 4, Section 6.F, Section 11, Section 17.F]** (#49)
- [ ] **feat(database): create auto_approval_rules table, rule-version persistence fields, and indexes; no database decision-evaluation trigger [BRD-BR-006, Section 6.B, Section 6.C, Section 8]** (#50)
- [ ] **test(database/edge): add pgTAP and service-level tests for qualify_order, cancel_order, order initiation, immutable audits, and Platform Admin overrides (includes tests for investor self-initiation, distributor-assisted initiation, same-workspace validation, initiator identity persistence, MFD initiator later qualifying the same order successfully, different authorised MFD user qualifying successfully, separate immutable initiation and qualification audit events, and negative tests denying investor qualification, Platform Admins, Family Guests, unrelated MFDs, and cross-workspace attempts) [BRD-BR-003, BRD-BR-007, BRD-FR-005, Section 6.D, Section 6.E, Section 6.G, Section 17.F]** (#51)
- [ ] **feat(database): create plan_entitlements table for feature gating [BRD-BR-011, Section 13]** (#53)
- [ ] **feat(database): create service-only apply_auto_approval_decision RPC with stable outbox-event idempotency and rule-version validation (scope includes claimed-event validation, completed-event update, failure state update, rule_inactive code, empty search path, and outbox uniqueness dependency) [BRD-FR-005, BRD-BR-005, BRD-BR-006, Section 6.B, Section 6.C, Section 8, NFR-003, NFR-005]** (#59)
- [ ] **security(database/flutter): replace direct browser access to protected folio mapping/reference tables in Buy/Sell/Switch order flows with narrow SECURITY DEFINER projection RPC(s), preserving folio ACL isolation, caller-bound authorization, masked-only folio disclosure, exact investor/workspace/portfolio/folio isolation, and positive/negative SQL + Flutter regression coverage [BRD-FR-005, BRD-BR-003, Section 3.A, Section 6.A, Section 17.F]** (#95)
