# Feature Catalog

## Purpose
This document logs all functional capabilities of Sharan Fincorp, tracking their business values, dependencies, and delivery status.

## Audience
Product managers, developers, stakeholders, and sales teams.

## Business Context
Keeping an active catalog of implemented and planned features prevents duplicate development and maps core capabilities directly to customer values.

---

## Detailed Explanation

### 1. Implemented Features

#### Autocomplete Fund Search & Factsheets
- **Description**: Autocomplete search bar on dashboard displaying mutual fund factsheets on click.
- **Business Value**: Allows investors to discover scheme profiles and returns instantly.
- **Dependencies**: SQLite NAV datasets.
- **Status**: Completed (v1.0.0).

#### Batch PDF/ZIP Invoice Signer
- **Description**: In-memory stamp overlays on invoices.
- **Business Value**: Saves hours of manual paper/PDF signing for advisors.
- **Dependencies**: `@zip.js/zip.js` library, PDF-lib runtime.
- **Status**: Completed (v1.1.0).

#### Vault PAN Protection
- **Description**: AES-256 encrypted PAN records and SHA-256 HMAC lookups.
- **Business Value**: Secures client data to SOC 2 / GDPR standards.
- **Dependencies**: `pg_vault` Supabase extension.
- **Status**: Completed (v0.7.0).

#### Folio-Scoped RLS
- **Description**: Row Level Security restricting database checks to approved grants.
- **Business Value**: Restricts read access to authorized owners only.
- **Dependencies**: Identity link schemas.
- **Status**: Completed (Sprint 5.3).

---

### 2. In Progress Features

#### Advisor review presentation
- **Description**: Dashboard UI for advisors to review, assign, and approve claim requests.
- **Business Value**: Automates verification queues.
- **Dependencies**: Advisor assignment schemas (`verification_request_assignments`).
- **Status**: Active development (Sprint 5.6B).

---

### 3. Planned Features

#### Valuation History Curves
- **Description**: Visual charts showing client portfolio performance curves over time.
- **Business Value**: Visual feedback of investor returns.
- **Dependencies**: NAV databases.
- **Status**: Planned (Sprint 6).

---

### 4. Future Features

#### AI Portfolio Advisory
- **Description**: Automated insights identifying underperforming mutual funds.
- **Business Value**: Increases advisory value.
- **Dependencies**: Transaction history, market benchmarks.
- **Status**: Future Roadmap.
