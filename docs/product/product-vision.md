# Product Vision

## Purpose
This document communicates the long-term vision, core mission, and strategic business goals of Sharan Fincorp.

## Audience
Product managers, engineering teams, stakeholders, and business clients.

## Business Context
Distributors of mutual funds struggle to manage multiple RTA file ingestion formats (CAMS/KFintech), coordinate PDF invoice signings, and securely present portfolio holdings to clients. Sharan Fincorp unifies these workflows under one secure portal.

---

## Detailed Explanation

### Mission Statement
To democratize and secure mutual fund tracking for independent financial advisors and their client base.

### Vision Statement
To establish the industry standard for independent portfolio auditing, automated ingestion reconciliations, and secure identity mapping.

### Problem Statement
Existing mutual fund portfolio tracking tools are expensive, duplicate ledger records, and suffer from security leaks by treating sensitive credentials (like PAN) as login passwords. Furthermore, advisors waste hours downloading and manually stamping PDF invoices.

### Core Business Goals & Success Metrics

| Goal | Description | Success Metric |
| :--- | :--- | :--- |
| **Onboard Clients Instantly** | Automate profile linkages when clients register. | >90% automatic link rate via verified contact checks. |
| **Reduce Signer Overhead** | Stamping and signing PDF invoices. | Under 2 minutes for a batch of 50 invoices. |
| **Zero Compliance Breaches** | Avoid logging sensitive investor variables. | 100% compliance with raw PAN logging bans. |
| **Accurate Performance Auditing** | Show correct internal rate of returns (XIRR). | Match registrar statements with zero decimal drift. |

---

## Dependencies
- Registrar statement formats (CAMS and KFintech) remaining consistent with DBF schemas.

## Future Evolution
- **B2B Tenant Scaling**: Transforming the system into a multi-distributor white-label platform where multiple advisor agencies host their own sub-domains.
