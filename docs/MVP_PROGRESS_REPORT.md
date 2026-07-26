# Money Bowl MVP - Progress Report & Revised Roadmap
**Report Date**: 2026-07-26  
**Overall Project Completion**: 90% (per PROJECT_STATE.md)  
**MVP Readiness**: 60% (Backend done, UI screens 40% complete)  
**Current Phase**: Sprint 6.1 — Order Execution Engine, Subscriptions & UI Implementation

---

## 📊 Completion Status Summary

### ✅ COMPLETED (7/7 Infrastructure Tasks - 100%)

| Component | Status | Deliverable | BRD Mapping |
|---|---|---|---|
| **Core Auth & RBAC** | ✅ Done | Email/password auth, multi-role RLS policies | BC-001, BC-002 |
| **Workspace & User Mgmt** | ✅ Done | Workspaces, memberships, invitations, audit logs | BC-003 |
| **Email Ingestion Pipeline** | ✅ Done | IMAP OAuth, CAMS/KFintech parser, ZIP/DBF extraction | BC-006, FR-009 |
| **Portfolio Engine** | ✅ Done | XIRR calculator, absolute return, folio verification models | BC-005, utilities |
| **Investor Verification** | ✅ Done | Folio verification state machine, advisor review assignments | BC-011 |
| **Invoice Signer Module** | ✅ Done | PDF stamping, ZIP archiving, Excel metadata tracking | BC-013 |
| **Database Schema** | ✅ Done | 20+ migrations, RLS policies, triggers, verification flows | Foundation |

**Key Artifacts**: 
- ✅ 20+ PostgreSQL migrations (supabase/migrations/)
- ✅ 4+ Edge Functions deployed (cams-kfintech-ingestion, sign-stamp-invoice, daily-nav-updater, update-excel-metadata)
- ✅ Complete Dart models for Auth, Workspace, Investor Verification, Portfolio
- ✅ Full Supabase RLS layer with authorization functions

---

### 🚧 IN PROGRESS (2/2 Tasks - 50%)

| Task | Status | What's Done | What's Needed |
|---|---|---|---|
| **Portfolio View Screens** | 50% | Dart models, XIRR calculator utility | UI screens to render folios + holdings, transaction history |
| **Folio Verification Screens** | 50% | Backend verification state machine | Advisor approval/rejection UI, verification queue display |

---

### ❌ NOT STARTED - CRITICAL PATH FOR MVP (5/5 Tasks - 0%)

| Task | Priority | Est. Size | BRD | Status |
|---|---|---|---|---|
| **Order Execution Forms** | 🔴 CRITICAL | 1.5 weeks | FR-005 | ❌ Need investor order form UI |
| **Order Approval Dashboard** | 🔴 CRITICAL | 1.5 weeks | FR-006 | ❌ Need MFD approval queue UI |
| **Auto-Approval Rules Engine** | 🔴 CRITICAL | 1 week | BR-006 | ❌ Need rules config UI + RLS enforcement |
| **Order Routing Edge Function** | 🔴 CRITICAL | 3 days | NFR-003 | ❌ Need Deno Edge Function |
| **Relationship Mapping UI** | 🔴 CRITICAL | 1 week | BC-004 | ❌ Need linking/acceptance screens |

**Impact**: ⚠️ **ORDER WORKFLOW (THE CRITICAL MVP PATH) IS CURRENTLY 0% COMPLETE**

---

### 🟡 SECONDARY FEATURES (5 Tasks - 0%)

| Task | Component | Est. Size | Status |
|---|---|---|---|
| **AMFI Factsheet Schema** | Portfolio discovery | 3 days | ❌ Pending |
| **AMFI Factsheet UI** | Scheme browsing | 5 days | ❌ Pending |
| **Universal Search** | Global search bar | 4 days | ❌ Pending |
| **PII Masking** | Security | 3 days | ❌ Pending |
| **Responsive Audit** | Polish | 3 days | ❌ Pending |

---

### 🎯 DEFERRED TO v1.1 (4 Tasks)

- ❌ Subscriptions & Billing
- ❌ AI Assistant Integration
- ❌ Support Ticketing
- ❌ Family Portfolio

---

## 🎯 Revised MVP Roadmap (5 Weeks to Launch)

### Week 1: Critical Order Workflow Foundation
**Focus**: Build the core order execution pipeline

**Tasks**:
- [ ] **Order Execution Forms** (1.5 days)
  - Investor form: Select folio + scheme, enter units/amount, choose order type (Buy/Sell/Switch)
  - Responsive layout for mobile/web
  - Client-side validation
  
- [ ] **Order Routing Edge Function** (1 day)
  - Deno Edge Function: Receive order submission → route to MFD queue
  - Store in `orders` table with `pending` status
  - Add to `order_queue` with distributor_id
  - Return <5s SLA confirmation (NFR-003)

- [ ] **Order Approval Dashboard** (1.5 days)
  - MFD view their pending orders in a queue
  - Display order details (folio, scheme, type, amount, investor name)
  - Approve/Reject buttons with decision notes
  - Apply RLS to show only their orders

**Deliverable**: ✅ Investor can submit order → MFD sees it in queue

**SLA Targets**: Order submission <5s, MFD sees order instantly

---

### Week 2: Auto-Approval & Relationship Management
**Focus**: Enable MFD autonomy + investor-distributor linking

**Tasks**:
- [ ] **Auto-Approval Rules Engine** (2.5 days)
  - Backend: RLS-scoped query to retrieve MFD's auto-approval rules
  - Edge Function: On order submission, check rules (min/max amount, scheme, transaction type)
  - Auto-approve matching orders → immutable audit log
  - Catch rule evaluation errors → manual review queue
  - Test edge cases (rule conflicts, disabled rules)

- [ ] **Relationship Mapping UI** (1.5 days)
  - Investor request form: "Link to my advisor" with MFD email/code
  - MFD acceptance interface: Approve/reject pending investors
  - Create `distributor_relationships` record on acceptance
  - Enforce RLS: MFDs only see their investors going forward

**Deliverable**: ✅ MFD can auto-approve orders, link investors, enforce isolation

**SLA Targets**: Auto-approval check <2s, relationship creation <1s

---

### Week 3: Portfolio & Discovery Features
**Focus**: Enable investors to browse + view their portfolios

**Tasks**:
- [ ] **Portfolio View Screens** (2 days)
  - Query ingested folios via `distributor_relationships` (RLS-scoped)
  - Render: Folio number, scheme holdings count, total value, XIRR
  - List scheme holdings with current NAV, units, absolute gain/loss
  - Transaction history tab per holding
  - Responsive: 2x2 grid mobile, multi-column web

- [ ] **PII Masking Utility** (1 day)
  - Create formatters in `lib/utils/formatters.dart`
  - PAN masking: Apply to portfolio, profile, transaction screens
  - Bank masking: Apply to any banking UI
  - Test: Verify masks in all user-facing screens

- [ ] **AMFI Factsheet Schema** (1 day)
  - Create PostgreSQL tables: schemes, amc_details, scheme_nav_history, holdings_benchmark
  - Seed with top 100 mutual fund schemes (or integrate AMFI API)

**Deliverable**: ✅ Investors see portfolios ingested from CAS, with secure PII masking

**SLA Targets**: Portfolio load <500ms, XIRR calc <200ms

---

### Week 4: Search & Scheme Discovery
**Focus**: Enable explorers to browse AMFI schemes

**Tasks**:
- [ ] **AMFI Factsheet UI** (2.5 days)
  - Factsheet screen: Display scheme name, AMC, category, launch date
  - NAV history chart (30/90/365 day views)
  - Expense ratio, riskometer, top 10 holdings
  - Responsive layout for mobile/web

- [ ] **Universal Search Engine** (1.5 days)
  - Top-nav search component with autocomplete
  - Query across: Schemes, folios, transactions
  - Full-text search on scheme names/ISIN
  - Return results in <200ms (NFR-002)
  - Autocomplete suggestions

**Deliverable**: ✅ Explorers can browse AMFI schemes, universal search functional

**SLA Targets**: Search latency <200ms, factsheet load <1s

---

### Week 5: Testing, Polish & Deployment
**Focus**: Finalize, test, ship MVP

**Tasks**:
- [ ] **Responsive UI Audit** (1.5 days)
  - Audit all screens: mobile <600px, tablet 600-900px, web >900px
  - Test navigation, buttons, text readability on each breakpoint
  - Fix layout issues, ensure dark theme consistency

- [ ] **Unit Tests** (1.5 days)
  - XIRR calculator tests (accuracy, edge cases)
  - PII masking tests (format validation)
  - Order approval rules tests (match/no-match scenarios)
  - Email validator tests
  - Run: `flutter test` (target 80%+ coverage)

- [ ] **Integration Tests** (1 day)
  - Critical flow: Ingestion → portfolio view → order → MFD approval
  - Relationship linking → MFD sees investor
  - Auto-approval rule matches → order auto-approved
  - Run: `flutter test integration_test/`

- [ ] **Production Deployment** (1 day)
  - Build Web: `flutter build web` → deploy to Firebase Hosting
  - Build Android: `flutter build apk` → upload to Play Store (internal testing)
  - Enable monitoring: Sentry (errors), Firebase Analytics (usage)
  - Gradual rollout: Start with 10% of users

**Deliverable**: 🎉 **MVP v1.0 LIVE**

---

## 📋 Task Breakdown by Component

### Component: Order Workflow (Critical Path)
```
┌─ Order Execution Forms
│  ├─ UI: Folio selection, scheme selection, amount input
│  └─ Validation: Amount range, scheme eligibility
│
├─ Order Routing Edge Function
│  ├─ Receive & validate order
│  ├─ Route to MFD queue
│  └─ Return <5s confirmation
│
├─ MFD Approval Dashboard
│  ├─ List pending orders
│  ├─ Approve/reject UI
│  └─ RLS enforcement
│
├─ Auto-Approval Rules
│  ├─ Rule definition schema
│  ├─ Rule matching logic
│  └─ Audit logging
│
└─ Relationship Mapping
   ├─ Investor linking UI
   ├─ MFD acceptance UI
   └─ RLS enforcement
```

---

## 🔧 Technical Setup Checklist

- [x] Supabase project initialized with auth
- [x] Database schema migrations applied (20+ done)
- [x] Edge functions deployed (cams-kfintech-ingestion, etc.)
- [x] Flutter project structure established
- [x] Provider state management configured
- [x] Dart models generated (auth, workspace, verification)
- [ ] Order schema migrations (NEW - needed)
- [ ] Order routing edge function (NEW - needed)
- [ ] Order approval provider (NEW - needed)
- [ ] Portfolio view providers (IN PROGRESS)

---

## 🚀 Success Criteria (MVP Exit)

### Functional Requirements
- ✅ Statement ingestion works (DONE - edge functions deployed)
- ✅ Portfolio calculations work (DONE - XIRR utility exists)
- ✅ User authentication works (DONE - RLS policies in place)
- ⏳ **Investor can submit order** (NEEDED - order forms not yet implemented)
- ⏳ **MFD can approve order** (NEEDED - approval dashboard not yet implemented)
- ⏳ **Auto-approval rules execute** (NEEDED - rules engine not yet implemented)
- ✅ PII is masked across UI (NEEDED - formatters exist, need UI application)
- ✅ Relationships are isolated (DONE - RLS policies implemented)

### Non-Functional Requirements
- ⏳ Order submission <5s (SLA target - NFR-003)
- ⏳ Search latency <200ms (SLA target - NFR-002)
- ⏳ XIRR calc <200ms (SLA target - performance)
- ⏳ Portfolio load <500ms (SLA target - performance)
- ⏳ Unit test coverage 80%+ (TEST coverage)
- ⏳ Responsive across mobile/web (UI polish)

---

## 📈 Risk Assessment

| Risk | Impact | Mitigation |
|---|---|---|
| **Order workflow not complete** | 🔴 CRITICAL | Start Week 1 immediately on order forms/approval queue |
| **Order routing SLA miss** | 🟡 HIGH | Pre-test Edge Function at scale, use queue patterns |
| **Auto-approval rules bugs** | 🟡 HIGH | Comprehensive unit tests, edge case validation |
| **PII masking incomplete** | 🟡 HIGH | Audit all screens, enforce masking in formatters |
| **Responsive UI gaps** | 🟡 MEDIUM | Use Flutter's responsive widgets, test on emulators |
| **Database SLA miss** | 🟠 MEDIUM | Monitor Supabase query performance, add indexes |

---

## 📝 Files to Update Next

1. **supabase/migrations/20260730000002_order_execution_schema.sql**
   - Create `orders`, `order_queue`, `auto_approval_rules` tables
   - Add RLS policies for relationship isolation

2. **supabase/functions/order_router/index.ts**
   - Deno Edge Function to route orders → MFD queue

3. **lib/features/order_management/** (NEW FEATURE)
   - `models/order_models.dart`
   - `services/order_service.dart`
   - `presentation/screens/order_form_screen.dart`
   - `presentation/screens/order_approval_queue_screen.dart`

4. **lib/providers/order_provider.dart** (NEW)
   - State management for order submission, approval queue

---

## 🎯 Next Immediate Actions

1. **Review this progress report** with stakeholders
2. **Create order execution schema migration** (SQL)
3. **Build order form UI screens** (Flutter)
4. **Deploy order routing Edge Function** (Deno)
5. **Implement order approval dashboard** (Flutter)

**Target**: Complete all critical path tasks by end of Week 2 → MFD can approve orders

---

## Version History

| Version | Date | Status | Notes |
|---|---|---|---|
| v1.0 | 2026-07-26 | CURRENT | MVP Progress Report based on codebase audit (90% backend, 40% UI) |
