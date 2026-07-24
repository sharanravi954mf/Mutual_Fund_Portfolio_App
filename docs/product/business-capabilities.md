# Business Capabilities

## Purpose
This document catalogs the core modules and functional capabilities that Sharan Fincorp delivers to the enterprise.

## Audience
Product owners, QA engineers, and operations managers.

## Business Context
We organize software requirements by business capabilities to keep development decoupled and align code updates to product domains.

---

## Detailed Explanation

### 1. Authentication & Onboarding
- **Description**: Secure client signup and login with automatic contact verification.
- **Value**: Prevents manual entry and links existing portfolios to new users instantly.

### 2. Portfolio Management
- **Description**: Displays absolute returns, valuation curves, holdings metrics, and transaction details.
- **Value**: Gives investors a single, clear summary of their wealth performance.

### 3. Document Management & Invoice Signing
- **Description**: Processes PDF invoices in batches to apply signature and stamp graphic overlays.
- **Value**: Reduces administrative signing cycles for advisors.

### 4. Statement Ingestion Engine
- **Description**: Extracts transaction records from password-protected ZIP folders containing RTA statements.
- **Value**: Unifies disparate registrar data into a standard relational schema.

### 5. Verification & Compliance
- **Description**: Coordinates client folio claims, advisor reviews, and Vault-backed PAN protections.
- **Value**: Guarantees that users only see data they are authorized to access.

### 6. Analytics & Future AI Assistance
- **Description**: Calculates XIRR and asset allocations. Planned AI modules will generate insights based on transaction trends.

---

## References
- [Target Architecture Contract: Section 4](../architecture/ARCHITECTURE.md#4-domain-driven-module-organization)
