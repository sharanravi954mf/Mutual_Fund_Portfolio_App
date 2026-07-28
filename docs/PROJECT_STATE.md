# Project Control Center (PROJECT_STATE)
Target Repository Path: docs/PROJECT_STATE.md

## Project Overview
- **Project Name**: Money Bowl
- **Repository Name**: Mutual_Fund_Portfolio_App
- **Current Mission**: Provide a premium, responsive Mutual Fund Portfolio Tracker supporting relationship-isolated portfolios, advisor qualifications, AMFI factsheets, dual subscriptions, Family Access, referrals, educational AI, and immutable auditing across Web and Mobile platforms.
- **Current Vision**: Securely track investor mutual fund portfolios, compile transaction histories, analyze annualized returns (XIRR), manage advisor ingestion/qualification reviews, and coordinate family delegation and subscriber billing workflows under strict compliance constraints.
- **Current Phase**: Phase 3 (Documentation Platform and Operational Systems).
- **Architecture Status**: Canonical v2.1.0 baseline approved
- **Documentation Status**: Aligned and certified
- **Application Status**: Pre-alpha implementation in progress
- **Application Implementation**: In Progress
- **Current Release Target**: v1.2.0-alpha
- **Current released application version**: v1.1.0-alpha
- **Last Updated**: 2026-07-28

---

## Canonical Project Documents Notice
The following five documents are the current and authoritative records for this project:
- [PROJECT_STATE](PROJECT_STATE.md)
- [CHANGELOG](CHANGELOG.md)
- [BRD](business/BRD.md)
- [System Architecture](architecture/SYSTEM_ARCHITECTURE.md)
- [Sprint 6.1](sprints/Sprint-6.1.md)

All other Markdown files are stale and must not be used for project status or architecture decisions.

---

## Current Status
- **Current Epic**: Core Platform Implementation
- **Current Milestone**: User Management & Workspace Foundation Implemented
- **Current Sprint**: Sprint 6.1 — Order Execution Engine, Subscriptions & Schema Extensions
- **Active Baselines**: BRD v1.3.0 | SYSTEM_ARCHITECTURE v2.1.0
- **Sprint 6.1 Status**: Ready to Start
- **Architecture Completion**: Complete
- **Release Readiness**: Not Ready
- **Documentation Certification Status**: Complete
- **Current Development Focus**: Execute Sprint 6.1 issues sequentially (including audit-schema hardening, Family Access lifecycle RPCs, Platform Admin support overrides with step-up verification, outbox event claiming and uniqueness validations, investor/distributor subscriptions, and pgTAP integration verification).

---

## Active Branch Strategy
- **`main`**: Production stable track. Direct commits are forbidden. Merges occur via pull requests from `release/*` or `hotfix/*` branches.
- **`develop`**: Integration branch for pre-release testing.
- **`release/*`**: Pre-release verification tracks. Squash-merged to `main` and `develop` after Go/No-Go sign-off.
- **`feature/*`**: Standalone feature branches (e.g. `feature/analytics`). Merged to `develop` via PRs after CI verification.
- **`bugfix/*`**: Non-critical bug remediation.
- **`hotfix/*`**: Emergency production fixes. Direct merges to `main` and `develop` after architect approvals.
