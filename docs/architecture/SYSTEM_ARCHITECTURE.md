# Money Bowl — System Architecture Specification
Document Version: v1.2.1 Canonical Baseline  
Target Repository Path: docs/architecture/SYSTEM_ARCHITECTURE.md  
BRD Baseline: docs/business/BRD.md (v1.2.1)  

## 1. Executive System Topology
Money Bowl is engineered as a modular, event-driven B2B2C microservices-on-serverless architecture. It provides isolation between Multi-Tenant MFD Workspaces and End-Investors while executing portfolio ingestion, order qualification, and market data synchronization in real-time.

┌─────────────────────────────────────────────────────────────────────────────┐
│                            SYSTEM TOPOLOGY MAP                              │
├─────────────────────────────────────────────────────────────────────────────┤
│  Flutter Client (iOS/Android/Web)                                           │
│         │                                                                   │
│         ├─► Supabase Auth (JWT with workspace_id & role claims)             │
│         ├─► PostgreSQL Database (Row-Level Security / Multi-Tenancy)        │
│         └─► Deno Edge Functions (Ingestion, Auto-Approval Engine, AMFI Sync) │
└─────────────────────────────────────────────────────────────────────────────┘

## 2. Core Architectural Layers

### A. Presentation Layer (Flutter Client)
* **Architecture Pattern**: Clean Architecture with BLoC / Provider state management organized into structured features (Data ➔ Domain ➔ Presentation).
* **Core Modules**:
  * *Investor Workspace*: Portfolio view, Buy/Sell/Switch order initiation, Family delegation hub.
  * *MFD Command Hub*: Transaction qualification queue, auto-approval threshold configuration, client onboarding.
  * *PII Guardrails*: Automatic client-side masking for sensitive investor demographic data in shared views.

### B. Security & Identity Layer (Supabase Auth & RLS)
* **Authentication**: Multi-factor Mobile/Email OTP authentication via GoTrue.
* **Authorization & Multi-Tenancy**:
  * Enforced at the database engine level via PostgreSQL Row-Level Security (RLS).
  * User JWT tokens carry `workspace_id`, `role` (mfd, investor, delegate), and `subscription_tier`.
  * Multi-tenant data leakage is structurally prevented because database policies restrict all reads/writes to matching workspace IDs or validated membership linkages.

### C. Serverless Execution & Edge Layer (Deno Edge Functions)
* **Mailbag & Feed Ingestion Worker**:
  * Receives CAMS/KFintech WBR2 & WBR22 DBF feeds and CAS PDF files.
  * Processes files using in-memory RAM stream decoding (zero disk persistence for zero-trust security).
* **Order Auto-Approval Engine**:
  * Evaluates pending investor transaction requests against MFD-configured threshold rules (e.g., SIP amount limits).
  * Automatically advances order statuses (`pending_qualification` ➔ `auto_approved` or `pending_review`).
* **AMFI Market Data Sync Worker**:
  * Scheduled cron worker pulling daily scheme NAVs and riskometer metadata directly from official AMFI data feeds.

## 3. Core Data Architecture & Domain Model
The database is structured into 5 primary entity domains matching the business capabilities:

| Domain | Key Data Entities | Architectural Purpose |
| :--- | :--- | :--- |
| **Identity & Access** | `workspaces`, `master_investors`, `mfd_profiles`, `workspace_memberships` | Manages multi-tenant workspace boundaries, user profiles, and roles (`platform_admin`, `admin`, `advisor`, `investor`, `operations`). |
| **Portfolio & Holdings** | `portfolios`, `folios`, `scheme_holdings`, `transactions` | Stores unit balances, scheme choices, NAV pricing historical tracks, and raw statement data. |
| **Order Execution** | `order_requests`, `qualification_queues`, `workspace_invitations`, `workspace_audit_logs` | Manages Buy/Sell/Switch initiation, MFD approval queues, and immutable security audit trails. |
| **Subscriptions & Billing** | `subscription_plans`, `workspace_billing`, `investor_subscriptions` | Enforces feature gates and client limit verification triggers for MFD subscription tiers. |
| **Referrals & Delegations** | `investor_referrals`, `family_delegations` | Manages asymmetric read-only sharing controls and viral registration attribution. |

---

## 4. Concrete Row Level Security (RLS) Mechanics
The database layer uses specific PostgreSQL policies to guarantee Workspace Isolation (BR-003) and Role-Based Access Control (BR-007):

### A. Workspace Tenant Boundary Policy (BR-003)
```sql
-- Enforces that MFDs and Investors can ONLY read/write data within their assigned workspace
CREATE POLICY workspace_isolation_policy ON order_requests
    FOR ALL
    USING (
        workspace_id = (auth.jwt() -> 'app_metadata' ->> 'workspace_id')::uuid
    );
```

### B. Asymmetric Family Delegation Policy (BR-009)
```sql
-- Allows family delegates read-only portfolio access without granting transaction privileges
CREATE POLICY family_delegate_read_policy ON order_requests
    FOR SELECT
    USING (
        investor_id IN (
            SELECT owner_investor_id FROM family_delegations
            WHERE delegate_investor_id = auth.uid() AND is_active = TRUE
        )
    );
```

### C. Platform Admin Override Policy (BR-007)
```sql
-- Platform admins bypass table-level workspace scoping to resolve accounts and overrides
CREATE POLICY platform_admin_override_policy ON workspaces
    FOR ALL
    USING (
        (auth.jwt() -> 'app_metadata' ->> 'user_role') = 'platform_admin'
    );
```

---

## 5. Edge Service Architectures & Pipelines

### A. In-Memory Zero-Disk Mailbag Ingestion (BC-006 / FR-009)
```text
[IMAP Mailbag Polling] ➔ [Deno RAM buffer] ➔ [Stream Decoders] ➔ [Postgres Transaction]
```
To guarantee zero-trust compliance, the parser reads DBF feeds and CAS PDFs directly from network streams into memory buffers. It extracts transaction arrays and updates folio balances without saving temporary files to disk.

### B. Transaction Qualification & Auto-Approval Engine (BR-006)
1. Mapped Investor submits a Buy/Sell/Switch `order_request`.
2. The database trigger invokes the Edge auto-approval function.
3. The engine evaluates:
   * Is `auto_approval_enabled` true for the workspace?
   * Is the order amount $\le$ `auto_approval_max_amount`?
4. If yes, status is set to `auto_approved`. If no, it is marked `pending_qualification` and routed to the MFD approval queue.

### C. Universal Search Architecture (BC-015 / FR-007)
To meet the `<200ms` latency SLA, the database uses PostgreSQL Generalized Inverted Index (GIN) on scheme names, folios, and client details using the `pg_trgm` extension. The client implements search-as-you-type debouncing and query caching.

### D. Educational AI Assistant Proxy (BC-007 / FR-012)
* **Core Stack**: Edge function communicating with a secured LLM endpoint.
* **Decline Gate (FR-013)**: The prompt system includes rigid system instructions to detect intent. Queries containing recommendation keywords (e.g., "which fund to buy", "should I switch") are blocked and responded to with the static education declination template.

---

## 6. Non-Functional Criteria & Security Architecture
* **NFR-001: Data Security & PII Protection**: Sensitive fields (`pan`, `phone`) are encrypted at rest using AES-256 keys managed by the Supabase Vault. Searches use SHA-256 HMAC lookups to verify matching entities without decrypting values.
* **NFR-002: Latency SLAs**:
  * Search queries: `<200ms`.
  * Order qualification routing: `<5s`.
  * Statement parsing processing: `<15 minutes`.
* **NFR-003: Audit Trail**: Every status change on `order_requests`, workspace administrative resets, and billing overrides insert tracking records into `workspace_audit_logs`. The table enforces immutability via a trigger blocking all update and delete queries.
