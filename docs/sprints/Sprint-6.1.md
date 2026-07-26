# Sprint 6.1 — Order Execution Engine, Subscriptions & Schema Extensions

## Technical Specifications & Scope
This sprint implements the core order execution engine, membership-based workspace isolation RLS, transactional event outbox, subscriber billing, referrals tracking, and frontend order queues in alignment with BRD v1.2.1 and SYSTEM_ARCHITECTURE v1.5.0-Final-Production-Baseline.

### Target Migration File
`supabase/migrations/20260801000000_brd_v1_2_1_execution_subscriptions_referrals.sql`

## Task Checklist & Tracking
- [ ] **feat(database): create order_type and order_status ENUMs [BRD-FR-005, ARCH-Sec3]** (#28)
- [ ] **feat(database): create order_requests and workspace_audit_logs tables [BRD-BE-012, ARCH-Sec3]** (#29)
- [ ] **feat(database): implement workspace isolation RLS policy on order_requests [BRD-BR-003, ARCH-Sec4.A]** (#30)
- [ ] **feat(database): implement platform admin override and family delegation RLS policies [BRD-BR-007, BRD-BR-009, ARCH-Sec4.B, ARCH-Sec4.C]** (#31)
- [ ] **feat(edge): build Deno in-memory stream parser worker for CAMS/KFintech feeds [BRD-BC-006, BRD-FR-009, ARCH-Sec5.A]** (#32)
- [ ] **feat(edge): build Order Auto-Approval RPC Engine [BRD-BR-006, ARCH-Sec5.B]** (#33)
- [ ] **feat(flutter): build Investor Order Request Modal (Buy/Sell/Switch) [BRD-FR-005, ARCH-Sec2.A]** (#34)
- [ ] **feat(flutter): build MFD Qualification Queue Screen [BRD-FR-006, ARCH-Sec2.A]** (#35)
- [ ] **feat(database): create subscription_plans and workspace_billing tables with tier limits [BC-009, BR-011]** (#39)
- [ ] **feat(database): create investor_referrals and referral_rewards tables [BC-018, FR-011]** (#40)
- [ ] **test(database): add pgTAP automated tests for RLS membership isolation and auto-approval triggers [BR-003, BR-006]** (#41)
- [ ] **feat(database): implement event_outbox table and transactional triggers [ARCH-Sec7]** (#43)
- [ ] **feat(database): implement membership-based RLS policy for workspace isolation [BR-003, ARCH-Sec5.A]** (#44)
- [ ] **feat(database): create role-segregated RLS policies on order_requests [BRD-FR-005, ARCH-Sec5.A]** (#48)
- [ ] **feat(database): create workspace-scoped family_delegations and RLS policies [BRD-BR-009, ARCH-Sec5.B]** (#49)
- [ ] **feat(database): create auto_approval_rules table and decision evaluation triggers [BRD-BR-006, ARCH-Sec6.B]** (#50)
- [ ] **test(database): add pgTAP automated tests for role-segregated RLS and step-up PII reveal [BRD-BR-003, BRD-BR-008]** (#51)