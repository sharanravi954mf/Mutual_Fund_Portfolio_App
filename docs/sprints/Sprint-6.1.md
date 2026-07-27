# Sprint 6.1 — Order Execution Engine, Subscriptions & Schema Extensions

## Technical Specifications & Scope
This sprint implements the core order execution engine (Buy/Sell/Switch transaction requests), membership-based workspace isolation RLS, transactional event outbox, Deno auto-approval worker, CAMS/KFintech Statement Ingestion pipeline, dual MFD and Investor billing subscriptions, payment events, plan entitlements, referrals and conversion tracking, profile-resolved Family Access lifecycle and consent mechanics, and frontend order workflows in alignment with BRD v1.2.1 and SYSTEM_ARCHITECTURE v2.0.1-Canonical-Production-Freeze.

### Target Migration Files
* `supabase/migrations/20260801000000_brd_v1_2_1_execution_subscriptions_referrals.sql`
* `supabase/migrations/20260801000001_sprint_6_1_canonical_hardening.sql` (Hardening and compliance corrective patch)

## Task Checklist & Tracking
- [ ] **feat(database): create order_status ENUM and cancel_order SECURITY DEFINER RPC [BRD-FR-005, BRD-BR-005, Section 6.A, Section 6.E, Section 17.F]** (#28)
- [ ] **feat(database): create order_requests and immutable workspace_audit_logs tables [BRD-FR-005, BRD-FR-006, BRD-BR-005, BRD-NFR-005, Section 5, Section 6.A, Section 17.F]** (#29)
- [ ] **feat(database): implement workspace isolation RLS policy on order_requests [BRD-BR-003, Section 6.A]** (#30)
- [ ] **feat(database/edge): implement audited Platform Admin override and family delegation access controls [BRD-BR-007, BRD-BR-009, Section 6.F, Section 6.G, Section 17.F]** (#31)
- [ ] **feat(edge): build Deno in-memory stream parser worker for CAMS/KFintech feeds [BRD-BC-006, BRD-FR-009, Section 7.A]** (#32)
- [ ] **feat(edge): build Deno order-auto-approval-worker with event-bound correlation, deterministic retries, and conditional rule-decision payloads [BRD-BR-006, Section 6.B, Section 6.C, Section 8]** (#33)
- [ ] **feat(flutter): build Investor Order Request Modal (Buy/Sell/Switch) [BRD-FR-005, Section 3.A]** (#34)
- [ ] **feat(flutter): build MFD Qualification Queue Screen [BRD-FR-006, Section 3.A]** (#35)
- [ ] **feat(database): create subscription_plans, workspace_billing, investor_subscriptions and payment_events for dual MFD/Investor billing [BRD-FR-010, BRD-BR-011, BC-009, Section 5, Section 13]** (#39)
- [ ] **feat(database): create investor_referrals, referral_conversions and referral_rewards [BRD-FR-011, BC-018, Section 12]** (#40)
- [ ] **test(database/edge): add auto-approval outbox, replay, rule-validation and race-condition tests [BRD-BR-003, BRD-BR-006, Section 6.A, Section 6.B, Section 6.C, Section 8, Section 17.F]** (#41)
- [ ] **feat(database): implement event_outbox table and transactional triggers [Section 8]** (#43)
- [ ] **feat(database): implement membership-based RLS policy for workspace isolation [BR-003, Section 6.A]** (#44)
- [ ] **feat(database): create advisor-only qualify_order SECURITY DEFINER RPC restricted to pending_review orders [BRD-FR-005, BRD-FR-006, BRD-BR-005, Section 6.D, Section 17.F]** (#48)
- [ ] **feat(database): implement profile-resolved Family Access lifecycle, consent RPCs and workspace-matched read-only RLS [BRD-BR-009, Section 4, Section 6.F, Section 11, Section 17.F]** (#49)
- [ ] **feat(database): create auto_approval_rules table, rule-version persistence fields, and indexes; no database decision-evaluation trigger [BRD-BR-006, Section 6.B, Section 6.C, Section 8]** (#50)
- [ ] **test(database/edge): add pgTAP and service-level tests for qualify_order, cancel_order, immutable audits, and Platform Admin overrides [BRD-BR-003, BRD-BR-007, BRD-FR-005, Section 6.D, Section 6.E, Section 6.G, Section 17.F]** (#51)
- [ ] **feat(database): create plan_entitlements table for feature gating [BRD-BR-011, Section 13]** (#53)
- [ ] **feat(database): create service-only apply_auto_approval_decision RPC with stable outbox-event idempotency and rule-version validation [BRD-FR-005, BRD-BR-005, BRD-BR-006, Section 6.B, Section 6.C, Section 8, NFR-003, NFR-005]** (#59)
- [x] **docs: align architecture v2.0.1 with Sprint 6.1 [Section 1, Section 18]** (#60)