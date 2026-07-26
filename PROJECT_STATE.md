# Project Control Center (PROJECT_STATE)

## Project Overview
- **Project Name**: Sharan Fincorp (Moneyball)
- **Repository Name**: Mutual_Fund_Portfolio_App
- **Current Mission**: Provide a premium, responsive Mutual Fund Portfolio Tracker for Web and Mobile platforms.
- **Current Vision**: Securely track investor mutual fund portfolios, compile transaction histories, analyze annualized returns (XIRR), and coordinate advisor review pipelines.
- **Current Phase**: Phase 3 (Documentation Platform and Operational Systems complete).
- **Repository Status**: Standards-driven, Production-ready.
- **Documentation Version**: v2.0.0
- **Architecture Version**: v2.0.0-Canonical-Production-Freeze
- **Target Release**: v1.1.0-alpha
- **Last Updated**: 2026-07-27

---

## Current Status
- **Current Epic**: Core Platform Implementation
- **Current Milestone**: User Management & Workspace Foundation Implemented
- **Current Sprint**: Sprint 6.1 — Order Execution Engine, Subscriptions & Schema Extensions
- **Active Baselines**: BRD v1.2.1 | SYSTEM_ARCHITECTURE v2.0.0-Canonical-Production-Freeze
- **Overall Progress**: 90%
- **Repository Health**: 99%
- **Documentation Certification Status**: Certified
- **Current Development Focus**: Setup and implementation of Sprint 6.1 database schemas, edge processors, and transaction modal frontends.

---

## Completed Epics

| Epic | Status | Completion Date | Major Deliverables |
| :--- | :--- | :--- | :--- |
| **Documentation Platform v1.0** | **Completed** | 2026-07-25 | Target Architecture Contract, Product Vision blueprint, Engineering handbooks, Governance frameworks, Repository OS configurations, AIOS, and Documentation Certification audits. |
| **Core Authentication & RBAC** | **Completed** | 2026-07-25 | Database migrations, triggers, is_admin() and has_active_investor_link() status RLS validations, UserProfile models, and decoupled RouteGuard builders. |
| **Workspace & User Management** | **Completed** | 2026-07-25 | Workspaces, workspace memberships, assignments, invitations, and mutable audit logs schema, current_user_profile_id() RLS functions, secure accepting and acceptance RPC functions, Dart models, and API Services. |

---

## Upcoming Epics

### 1. Repository Automation
- **Priority**: High
- **Dependencies**: None
- **Current Status**: In Progress (Documentation validation and commit quality workflows integrated)

### 2. Core Platform
- **Priority**: Critical
- **Dependencies**: Supabase DB local setup
- **Current Status**: Completed (Authentication and Role-Based Access Control foundation integrated).

### 4. Email Ingestion
- **Priority**: High
- **Dependencies**: Supabase Edge Functions
- **Current Status**: Registrar (CAMS/KFintech) parser edge functions configured.

### 5. PDF Intelligence
- **Priority**: High
- **Dependencies**: In-Memory ZIP Ingestion
- **Current Status**: ZIP processing decision accepted (DEC-008).

### 6. Portfolio Engine
- **Priority**: High
- **Dependencies**: Folio Verification
- **Current Status**: XIRR calculation models and absolute return utilities completed.

### 7. Advisor Dashboard
- **Priority**: Medium
- **Dependencies**: Folio Review Assignment
- **Current Status**: Assignment-scoped queue RPCs completed.

### 8. Investor Portal
- **Priority**: Medium
- **Dependencies**: Auth profile separation
- **Current Status**: Portfolio tracking screens completed.

### 9. AI Intelligence
- **Priority**: Medium
- **Dependencies**: AI Handoff Specs
- **Current Status**: AIOS and prompt standards defined.

### 10. Production Hardening
- **Priority**: High
- **Dependencies**: Staging smoke checks
- **Current Status**: Staging role validation checklists defined.

---

## Active Branch Strategy

- **`main`**: Production stable track. Direct commits are forbidden. Merges occur via pull requests from `release/*` or `hotfix/*` branches.
- **`develop`**: Integration branch for pre-release testing.
- **`release/*`**: Pre-release verification tracks. Squash-merged to `main` and `develop` after Go/No-Go sign-off.
- **`feature/*`**: Standalone feature branches (e.g. `feature/analytics`). Merged to `develop` via PRs after CI verification.
- **`bugfix/*`**: Non-critical bug remediation.
- **`hotfix/*`**: Emergency production fixes. Direct merges to `main` and `develop` after architect approvals.

---

## Repository Metrics
- **Documentation Libraries**: 6 (Product, Architecture, Engineering, Governance, AI, Audit)
- **Templates**: 10 (RFC, ADR, Sprint, Epic, Feature, Bug, Task, Release, Architecture Review, Security Review)
- **Architecture Documents**: 10
- **Product Documents**: 9
- **Engineering Documents**: 9
- **Governance Documents**: 8
- **AI Documents**: 10
- **Repository Metadata Files**: 6
- **Certification Status**: Certified

---

## AI Collaboration Model
See **[AI Operating System](docs/ai/README.md)** for detail.
- **Antigravity (Coordinator)**: Coordinates planning, subagent task allocation, and QA verifications.
- **ChatGPT / Codex (Coder)**: Inline edits, feature modifications, and unit tests under sandbox execution.
- **BAI (Auditor)**: Validates database models, calculations, and registrar parser logic.
- **Human (Chief Architect)**: Final code review, plan approvals, and git merge authority.

---

## Decision Summary
- **ADR Repository**: [Architecture Decision Records Index](docs/decisions/README.md)
- **Decision Register**: [Living registry of decisions](docs/governance/decision-register.md)
- **Risk Register**: [Ecosystem risk mitigation tables](docs/governance/risk-register.md)
- **Architecture**: [Executive Architecture entrypoint](docs/architecture.md)
- **Repository Governance**: [Ownership and approval matrices](docs/governance/repository-governance.md)

---

## Technical Debt Summary
See **[Documentation Debt Register](docs/audit/documentation-debt-register.md)** for detail.
- **Open Debt**: Existing legacy compiler warning lines under `lib/`.
- **Documentation Debt**: Sibling path corrections completed; no outstanding documentation debt remaining.
- **Engineering Debt**: Web interop `.xls` SheetJS interop remains an alpha path.

---

## Next Priorities (Execution Order)
1. **Fix Image Selector Filter**: Modify image selection file pickers in `admin_dashboard.dart` to support `.jpg`, `.jpeg`, and `.png` extensions.
2. **Configure Non-Mandatory Excel Ingestion**: Adjust PDF/ZIP signing workflows in `admin_dashboard.dart` to run successfully without requiring an Excel workbook tracker.
3. **Resolve Staging Dashboard Warnings**: Clean up existing lint warnings inside legacy presentation widgets.
4. **Deploy Advisor folio review presentation**: Implement Sprint 5.6B screens for Advisor review approval.
5. **Supervised Reassignment Flow**: Implement supervisor transfer features for outstanding folio verification requests.

---

## Quick Navigation

| Target Guide | Document Reference Link |
| :--- | :--- |
| **README** | [README.md](README.md) |
| **Architecture** | [Architecture Index](docs/architecture/README.md) |
| **Product** | [Product Index](docs/product/README.md) |
| **Engineering** | [Engineering Index](docs/engineering/README.md) |
| **Governance** | [Governance Index](docs/governance/README.md) |
| **AIOS** | [AI Operating System Index](docs/ai/README.md) |
| **Repository OS** | [Repository OS Contributing Guide](CONTRIBUTING.md) |
| **Audit** | [Audit Index](docs/audit/README.md) |
| **Templates** | [Reusable Templates Index](docs/templates/RFC.md) |
| **Contributing Guide** | [Contributor Guide](CONTRIBUTING.md) |
| **PROJECT_STATE** | [Project Control Center](PROJECT_STATE.md) |
