# Money Bowl — System Architecture Specification
Document Version: v1.2.1 Canonical Baseline  
Target Repository Path: docs/architecture/SYSTEM_ARCHITECTURE.md  
BRD Baseline: docs/business/BRD.md (v1.2.1)  

## 1. Executive System Topology & Execution Zones
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

## 2. Master Business Capability Mapping Matrix

| Capability ID | Capability Name | Target Services | Database Tables | Edge Functions |
| :--- | :--- | :--- | :--- | :--- |
| **BC-001** | Identity & Access Management | `AuthService` | `profiles`, `workspace_memberships` | None |
| **BC-002** | Distributor Lifecycle Management | `WorkspaceService` | `workspaces` | None |
| **BC-003** | Investor Lifecycle Management | `MembershipService` | `profiles` | None |
| **BC-004** | Relationship Management | `MembershipService` | `workspace_memberships` | None |
| **BC-005** | Portfolio Management | `WorkspaceService` | `portfolios`, `folios`, `scheme_holdings`, `transactions` | None |
| **BC-006** | Registrar Data Ingestion | `IngestionService` | `transactions`, `scheme_holdings` | `cams-kfintech-ingestion` |
| **BC-007** | Educational AI Assistance | `AIProxyService` | None | `ai-helper` |
| **BC-008** | Customer Servicing (Ticketing) | `TicketService` | `support_tickets` | None |
| **BC-009** | Dual Subscription & Billing | `BillingService` | `subscription_plans`, `workspace_billing`, `investor_subscriptions` | `subscription-manager` |
| **BC-010** | Platform Governance & Administration | `AdminService` | `workspace_audit_logs`, `profiles` | None |
| **BC-011** | Document Management (Lineage) | `IngestionService` | `ingestion_logs` | `cams-kfintech-ingestion` |
| **BC-012** | Actionable Notification Management| `NotificationService` | `notifications`, `notification_retry_queue` | `notification-dispatcher` |
| **BC-013** | Document Storage & Vaulting | `StorageService` | `ingested_documents` | None |
| **BC-014** | Distributor Analytics Dashboard | `AnalyticsService` | `portfolios` (Materialized View) | None |
| **BC-015** | Universal Search & Discovery | `SearchService` | `folios`, `transactions` | None |
| **BC-016** | Platform Configuration | `ConfigService` | `workspaces` | None |
| **BC-017** | AMFI Factsheets & Market Data | `FactsheetService` | `amfi_factsheets` | `amfi-nav-worker` |
| **BC-018** | Investor Referral Engine | `ReferralService` | `investor_referrals` | `referral-tracker` |

## 3. Core Architectural Layers

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

## 4. Core Data Architecture & Domain Model
The database is structured into 5 primary entity domains matching the business capabilities:

| Domain | Key Data Entities | Architectural Purpose |
| :--- | :--- | :--- |
| **Identity & Access** | `workspaces`, `profiles`, `workspace_memberships` | Manages multi-tenant workspace boundaries, user profiles, and roles (`platform_admin`, `admin`, `advisor`, `investor`, `operations`). |
| **Portfolio & Holdings** | `portfolios`, `folios`, `scheme_holdings`, `transactions` | Stores unit balances, scheme choices, NAV pricing historical tracks, and raw statement data. |
| **Order Execution** | `order_requests`, `workspace_invitations`, `workspace_audit_logs` | Manages Buy/Sell/Switch initiation, MFD approval queues, and immutable security audit trails. |
| **Subscriptions & Billing** | `subscription_plans`, `workspace_billing`, `investor_subscriptions` | Enforces feature gates and client limit verification triggers for MFD subscription tiers. |
| **Referrals & Delegations** | `investor_referrals`, `family_delegations` | Manages asymmetric read-only sharing controls and viral registration attribution. |

---

## 5. Concrete Row Level Security (RLS) Mechanics
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

## 6. Edge Service Architectures & Ingestion Pipelines

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

---

## 7. Asynchronous Event Bus Topology
Money Bowl features a central PostgreSQL-backed message broker channel using `NOTIFY/LISTEN` to support decoupled processes:

```text
Postgres Trigger ➔ NOTIFY order_event_chan ➔ Deno Edge Broker Listener ➔ Worker Tasks
```

* **`order.created`**: Fired when an investor creates an order request. Triggers the auto-approval engine.
* **`ticket.raised`**: Fired on customer support request. Routes alert notifications to the assigned advisor.
* **`statement.imported`**: Fired upon statement completion. Re-calculates valuation history and updates the analytics dashboard.

---

## 8. Notification Service Architecture & Retry Queue (BC-012)
* **Channels**: Email, SMS, WhatsApp, and Push Notifications.
* **Retry Queue Engine**: Failures trigger the dispatcher worker using exponential backoff:
  $$T_{\text{wait}} = 2^{\text{attempt}} \times 60 \text{ seconds}$$
* **Dead Letter Queue (DLQ)**: Tasks failing more than 5 times are routed to `failed_notifications` for administrative review.

---

## 9. Customer Servicing & Ticketing Workflow Engine (BC-008)
Support requests follow a rigid state machine layout:
```text
[raised] ➔ [assigned] ➔ [resolved] ➔ [closed]
```
* **SLA Thresholds**:
  * P0 (Critical): 4 hours
  * P1 (Medium): 24 hours
  * P2 (Low): 72 hours
Breaches auto-escalate directly to the workspace owner.

---

## 10. Encrypted Document Vaulting & Signed URL Lineage (BC-011, BC-013)
* **Encryption**: CAS PDF statements are encrypted at the object boundary using AES-256 keys.
* **Access Control**: Users receive signed URLs with an expiry limit of 15 minutes. Decryption happens on-the-fly inside the Edge compute boundary.

---

## 11. Viral Referral Engine & Fraud Detection Rules (BC-018)
* **Attribution**: Referrals are tracked using SHA-256 hashed invite tokens.
* **Fraud Detection rules**:
  * Self-Referral block: Prevents users from registering with identical emails/phones.
  * Collision block: Rejects referrals matching pre-existing PAN or bank accounts.

---

## 12. Dual Subscription & Feature Gating Engine (BC-009)
* **Starter limits**: Gated at 25 mapped clients. Upgrades require active checkout session confirmations.
* **Auto-Approval limits**: Workspace limits are checked at order submission. If the workspace exceeds its monthly allowed auto-approval volume, orders fallback to manual qualification.

---

## 13. Educational AI Assistant Proxy & Guardrail Declination Gate (BC-007, BR-010)
* **Core Stack**: Edge function communicating with a secured LLM endpoint.
* **Decline Gate (FR-013)**: The prompt system includes rigid system instructions to detect intent. Queries containing recommendation keywords (e.g., "which fund to buy", "should I switch") are blocked and responded to with the static education declination template.

---

## 14. Universal Search Architecture (BC-015)
To meet the `<200ms` latency SLA, the database uses PostgreSQL Generalized Inverted Index (GIN) on scheme names, folios, and client details using the `pg_trgm` extension. The client implements search-as-you-type debouncing and query caching.

---

## 15. Observability, Structured Logging & Audit Metrics
All microservices and Edge functions log structured JSON outputs containing `workspace_id`, `execution_time_ms`, and `operation_type` to a centralized Postgres logging collector. Central metrics include database latency, ingestion failures, and SLA breaches.

---

## 16. Non-Functional Criteria & Security Architecture
* **NFR-001: Data Security & PII Protection**: Sensitive fields (`pan`, `phone`) are encrypted at rest using AES-256 keys managed by the Supabase Vault. Searches use SHA-256 HMAC lookups to verify matching entities without decrypting values.
* **NFR-002: Latency SLAs**:
  * Search queries: `<200ms`.
  * Order qualification routing: `<5s`.
  * Statement parsing processing: `<15 minutes`.
* **NFR-003: Audit Trail**: Every status change on `order_requests`, workspace administrative resets, and billing overrides insert tracking records into `workspace_audit_logs`. The table enforces immutability via a trigger blocking all update and delete queries.

---

## 17. Full BRD Traceability Matrix

| BRD Requirement ID | BRD Rule ID | Technical Architecture Component | Postgres Table / Edge Function |
| :--- | :--- | :--- | :--- |
| **FR-001** | BR-002 | Identity & Access / Workspace onboarding | `workspaces` |
| **FR-002** | BR-001 | Standalone onboarding / Explore mode | `profiles` |
| **FR-003** | BR-007 | Supersede Access / Override controls | `platform_admin_override_policy` |
| **FR-004** | BR-008 | Client Masking & Column Vault encryption | Supabase Vault AES-256 keys |
| **FR-005** | BR-005 | Buy/Sell/Switch Order Initiation forms | `order_requests` |
| **FR-006** | BR-005 | Route to qualification queues | `order_requests` |
| **FR-007** | N/A | Top universal search component | pg_trgm GIN indexing |
| **FR-008** | BR-012 | AMFI factsheets sync and metadata Sync | `amfi_factsheets` / `amfi-nav-worker` |
| **FR-009** | BR-003 | Mailbag connection DBF/PDF stream parser | `cams-kfintech-ingestion` |
| **FR-010** | BR-011 | Subscription tier gates | `subscription_plans` |
| **FR-011** | N/A | Viral referral code generation & rewards | `investor_referrals` |
| **FR-012** | BR-010 | Educational AI companion | `ai-helper` |
| **FR-013** | BR-010 | Decline financial advisory prompts | AI proxy decline gate |
| **FR-014** | N/A | Raise tickets from AI/frontend to queue | `support_tickets` |
