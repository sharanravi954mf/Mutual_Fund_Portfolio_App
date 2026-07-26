# Changelog

All notable completed releases of Sharan Fincorp are documented here. This changelog follows the spirit of [Keep a Changelog](https://keepachangelog.com/).

Detailed release notes and boundaries are maintained inside the [docs/changelog/](docs/changelog/README.md) directory.

---

## [v1.5.0-Final-Production-Baseline] — 2026-07-27

### Summary
Release v1.5.0-Final-Production-Baseline refines the System Architecture Specifications to v1.5.0 security compliance baseline, establishing role-segregated RLS policies, workspace-scoped family visibility delegations, auto-approval rules schemas, global identity resolution markers, and out-of-scope product boundaries.

### Major Additions & Changes
- **Role-Segregated Order RLS**: Replaced generic order policies with distinct select, insert, and update policies for Investors, Advisors, and Admins, including explicit `WITH CHECK` clauses and normal user delete prohibitions.
- **Workspace-Scoped Family Delegations**: Realignment of the family delegation model to link to specific workspaces and standardizing on profile ID selectors to prevent unlinked visibility leaks.
- **Vault Security Realignment**: Added explicit document download denial constraints for family guest profiles.
- **Advanced Auto-Approval Rule Table**: Implemented schema entities for the `auto_approval_rules` engine and triggers recording execution rules.
- **Global Identity Matching**: Defined HMAC identity markers on profile entities (`pan_hmac`, `normalised_phone_hmac`, etc.) for deterministic resolution.
- **Product Scope Boundaries**: Defined Section 19 specifying out-of-scope boundaries (direct stocks, insurance, FDs, crypto, tax filing, etc.).

---

## [v1.4.0-Final-Baseline] — 2026-07-27

### Summary
Release v1.4.0-Final-Baseline updates the traceability matrix capability mappings and persona details, implements a compliant document retention lifecycle policy, updates the secure file ingestion scan workflow, and implements role-segregated Row-Level Security policies with explicit `WITH CHECK` conditions on order requests and family delegation transactional tables.

### Major Additions & Changes
- **Traceability Matrix & Persona Updates**: Map BC-016 Platform Config to N/A for functional requirements and associate with BRD Rules BR-006, BR-010, BR-012 under the "Configuration over Customisation" design principle. Refined BC-001 (Identity), BC-007 (AI Assistant), BC-009 (Subscriptions), and BC-012 (Notifications) mappings and personas.
- **Document Retention Lifecycle Overhaul**: Replaced the automated 30-day deletion of original vault files with a compliance-driven retention policy allowing temporary artifact pruning but preserving original files for legal and audit lineage.
- **Secure File Ingestion Scan Workflow**: Standardized file ingestion pipeline to explicitly run MIME & Magic-byte validation, malware screening, and SHA-256 hashing prior to encrypted object storage.
- **Role-Segregated WITH CHECK RLS Policies**: Implemented secure, dynamic membership-based RLS isolation policies on `order_requests`, `family_delegations`, and `portfolios` tables with explicit `WITH CHECK` blocks to prevent write bypasses.

---

## [v1.3.1-Final-Baseline] — 2026-07-27

### Summary
Release v1.3.1-Final-Baseline applies precision improvements to the System Architecture baseline addressing all ChatGPT 5.5 review feedback points, logs the revision history, and updates the Sprint 6.1 issue traceability matrices.

### Major Additions & Changes
- **Many-to-Many Traceability Matrix**: Refined capability maps (BC-002, BC-004, BC-005, BC-006, BC-008, BC-011, BC-012, BC-016) to map cleanly to requirements and tables.
- **Distributor Analytics Dashboard Projection**: Defined the schema and target fields for `mfd_dashboard_metrics` view/table aggregation.
- **Canonical Persona Role Matrix**: Added explicit mapping of BRD user personas to PostgreSQL application membership and auth roles.
- **Ticket SLA target definitions**: Updated static SLA targets to plan-configurable variables.
- **Document Vault Security & Lineage**: Documented file limits, content hashing, deduplication, and added immutable rules to `ingestion_logs`.

---

## [v1.2.1-synthesized] — 2026-07-26

### Summary
Release v1.2.1 establishes the finalized canonical specification baseline for Business Requirements and System Architecture, and initializes Sprint 6.1 (Order Execution Engine, Subscriptions & Schema Extensions).

### Major Additions & Changes
- **Canonical Baseline Freeze**: Populated and froze `docs/business/BRD.md` (v1.2.1) and `docs/architecture/SYSTEM_ARCHITECTURE.md` (v1.2.1 Synthesized 17-layer format).
- **Sprint 6.1 Backlog Setup**: Created and linked 8 core tasks on Project Board 1 (`MoneyBowl Development`) under the `Sprint Backlog` column.
- **Repository Housekeeping**: Pruned legacy, redundant specs and documents to focus the repository scope.

---

## [v1.1.0-alpha] — 2026-07-19

### Summary
Release v1.1.0 introduces significant upgrades to the Admin Dashboard (Invoice Signer tab, in-memory batch ZIP processing), Client Dashboard features (Autocomplete search, factsheets, live wallpapers, time-of-day greetings), and registrar statement ingestion (decryption & auto-linking).

### Major Additions & Changes
- **Invoice Signer upgrades**: Standalone tab inside the Admin Dashboard supporting single PDFs and zipped archives. In-memory batch decryption, signing, and re-zipping.
- **Material 3 Dusty Rose Gold migration**: Migrated design seed color to `Color(0xFFC9B4BC)` across sidebar navigation drawer, metrics, cards, and tables.
- **Client Search & Factsheets**: Autocomplete mutual fund search on dashboard with modal factsheets.
- **Ingestion Pipeline Upgrades**: Deno engine parses password-protected ZIPs containing dBASE III `.dbf` statements. Standalone CAMs staging table imports, unregistered client ingestion, and auto-linking triggers.
- **Live Money Wallpaper**: Animated falling rupee symbols (`₹`) and golden wealth curves under Display settings.
- **Deduplicated greetings**: Unified time-of-day greetings on the main header appbar.

### Detailed Release Logs
- [v1.1.0 In-Memory ZIP Ingestion Spec](docs/changelog/v1.1.0_invoice_signer.md)
- [CAMS Signer Boundary Notes](docs/changelog/cams_invoice_signer_boundary.md)
- [Material 3 Theme Redesign Notes](docs/changelog/theme-redesign.md)

---

## [v0.7.0-alpha] — 2026-07-22

### Summary
Sprint 5.2 – Secure PAN Verification for client account linking.

### Major Additions & Changes
- **PAN Verification Workflow**: Masked PAN lookups and Vault-backed encryption at rest.
- **Opaque Candidate-Tokens**: Token-bound approval mechanisms preventing UUID leak.
- **Immutable Request Evidence**: Safe conflict categorizations and audit records.

---

## [v0.6.1-alpha] — 2026-07-22

### Summary
Sprint 4 – Onboarding and Identity Foundations.

### Major Additions & Changes
- **Separated Identities**: Isolated Supabase Auth credentials from business profile records.
- **Advisor verification queues**: Verification assignment structures.
- **Row Level Security (RLS)**: Enforced client select filters based on active investor links.
