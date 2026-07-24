# User Personas

## Purpose
This document defines the roles, objectives, core responsibilities, user privileges, and workflows for each user persona.

## Audience
UI/UX designers, product managers, and developers writing permission rules.

## Business Context
Understanding our users ensures that the security access rules (RLS) match real-world operations without creating usability bottlenecks.

---

## Detailed Explanation

### 1. Advisor (Primary Operator)
- **Goals**: Manage client holdings, audit statements, download signed invoices, and reconcile client folios.
- **Responsibilities**: Trigger registrar imports, review folio claims, and configure company details.
- **Pain Points**: Heavy manual administrative tasks, slow ingestion reconciliations, and complex client verification queries.
- **Permissions**: Full write access to ingestion pipelines, invoice signer dashboards, and verification details.

### 2. Investor (End Client)
- **Goals**: Monitor portfolio valuation, inspect transaction histories, and view fund factsheets.
- **Responsibilities**: Claim and verify folio ownership.
- **Pain Points**: Security concerns about data exposure, slow UI loading, and complex interface navigation.
- **Permissions**: Read-only access to own linked portfolio data. Denied access to all other clients' information.

### 3. Administrator / Operations
- **Goals**: Maintain system availability, manage advisor allocations, and configure database Vault secrets.
- **Responsibilities**: Oversee backups, configure integrations, and monitor system diagnostics.
- **Permissions**: Database owner permissions (no business operations access in the browser).

### 4. Future Roles (Compliance Officer / Relationship Manager)
- **Compliance Officer**: Audits RLS configurations and reviews event logs.
- **Relationship Manager**: Advisor assistants with write access to specific client directories (no system-wide configuration access).

---

## References
- [Target Architecture Contract: Section 5](../architecture/ARCHITECTURE.md#5-role-based-access-control)
- [ADR-007 — Advisor Assignment for Folio Review](../decisions/ADR-007-Advisor-Folio-Review-Assignment.md)
