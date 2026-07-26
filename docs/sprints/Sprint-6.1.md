# Sprint 6.1 — Order Execution Engine, Subscriptions & Schema Extensions

## Technical Specifications & Scope
This sprint implements the core order execution engine, membership-based workspace isolation RLS, transactional event outbox, subscriber billing, referrals tracking, and frontend order queues in alignment with BRD v1.2.1 and SYSTEM_ARCHITECTURE v2.0.1-Canonical-Production-Freeze.

### Target Migration File
`supabase/migrations/20260801000000_brd_v1_2_1_execution_subscriptions_referrals.sql`

## Task Checklist & Tracking
- [ ] **feat(database): create order_status ENUM and cancel_order SECURITY DEFINER RPC [BRD-FR-005, Section 6.A, Section 6.E]** (#28)
- [ ] **feat(database): create order_requests and immutable workspace_audit_logs tables [BRD-FR-005, BRD-FR-006, BRD-BR-005, BRD-NFR-005, Section 5, Section 6.A, Section 17.F]** (#29)
- [ ] **feat(database): implement workspace isolation RLS policy on order_requests [BRD-BR-003, Section 6.A]** (#30)
- [ ] **feat(database): implement audited Platform Admin override and family delegation RLS policies [BRD-BR-007, BRD-BR-009, Section 6.F, Section 6.G]** (#31)
- [ ] **feat(edge): build Deno in-memory stream parser worker for CAMS/KFintech feeds [BRD-BC-006, BRD-FR-009, Section 7.A]** (#32)
- [ ] **feat(edge): build Deno order-auto-approval-worker [BRD-BR-006, Section 6.B, Section 6.C, Section 8]** (#33)
- [ ] **feat(flutter): build Investor Order Request Modal (Buy/Sell/Switch) [BRD-FR-005, Section 3.A]** (#34)
- [ ] **feat(flutter): build MFD Qualification Queue Screen [BRD-FR-006, Section 3.A]** (#35)
- [ ] **feat(database): create subscription_plans and workspace_billing tables with tier limits [BC-009, BR-011, Section 5, Section 13]** (#39)
- [ ] **feat(database): create investor_referrals and referral_rewards tables [BC-018, FR-011, Section 12]** (#40)
- [ ] **test(database): add pgTAP automated tests for outbox, worker claiming, RPC validations, and race conditions [BR-003, BR-006, Section 6.A, Section 6.B, Section 6.C, Section 8, Section 17.F]** (#41)
- [ ] **feat(database): implement event_outbox table and transactional triggers [Section 8]** (#43)
- [ ] **feat(database): implement membership-based RLS policy for workspace isolation [BR-003, Section 6.A]** (#44)
- [ ] **feat(database): create qualify_order SECURITY DEFINER RPC restricted to pending_review orders [BRD-FR-005, Section 6.D]** (#48)
- [ ] **feat(database): create family_delegations table with consent_status and workspace RLS [BRD-BR-009, Section 6.F]** (#49)
- [ ] **feat(database): create auto_approval_rules table, rule-version persistence fields, and indexes; no database decision-evaluation trigger [BRD-BR-006, Section 6.B, Section 6.C, Section 8]** (#50)
- [ ] **test(database): add pgTAP automated unit tests for qualify_order, cancel_order, outbox triggers, and overrides [BRD-BR-003, BRD-FR-005, Section 6.D, Section 6.E, Section 8, Section 17.F]** (#51)
- [ ] **feat(database): create plan_entitlements table for feature gating [BRD-BR-011, Section 13]** (#53)
- [ ] **feat(database): create service-only apply_auto_approval_decision RPC [BRD-FR-005, BRD-BR-005, BRD-BR-006, Section 6.C, NFR-003, NFR-005]** (#59)
- [x] **docs: align architecture v2.0.1 with Sprint 6.1 [Section 1, Section 18]** (#60)