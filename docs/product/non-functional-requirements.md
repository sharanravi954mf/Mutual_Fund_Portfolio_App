# Non-Functional Requirements (NFR)

## Purpose
This document defines the quality metrics, scalability bounds, security requirements, and system availability standards.

## Audience
QA engineers, security auditors, and system administrators.

## Business Context
NFRs establish the boundary rules that protect the platform's production readiness and ensure the application remains stable under peak user loads.

---

## Detailed Explanation

### 1. Performance
- **Dashboard Load Time**: The main portfolio view must render in under **1.5 seconds** on a standard 3G connection.
- **Invoice Stamping Latency**: The `sign-stamp-invoice` function must complete a batch of 10 PDFs in under **5 seconds**.

### 2. Availability
- **System Uptime**: The system targets **99.9%** availability of the API gateway and database services (excluding scheduled maintenance windows).

### 3. Security & Compliance
- **Data Protection**: Sensitive data (PAN) must be encrypted using AES-256 at rest.
- **Transit Encryption**: All API calls are routed over HTTPS utilizing TLS 1.3.
- **Zero Log Leakage**: Raw PAN or unmasked folio details must never persist in application log files.

### 4. Scalability & Limits
- **Deno Functions Runtime**: Functions must execute under a 50ms active CPU utilization threshold to match serverless resource limits.
- **Database Connection Sizing**: The system must sustain up to 100 concurrent read connections.

### 5. Accessibility & Maintainability
- **Design System Consistency**: Compiles to Material 3 standards. Components use colors defined in `AppColors` for contrast safety.
- **Folder Architecture**: Enforces separation of concerns (`models -> data -> application -> presentation`).

---

## References
- [06 — Infrastructure Architecture](../architecture/06-infrastructure-architecture.md)
- [12 — Security Architecture](../architecture/12-security-architecture.md)
