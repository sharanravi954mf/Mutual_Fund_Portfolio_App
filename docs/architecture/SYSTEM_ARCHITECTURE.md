# Money Bowl — System Architecture Specification
Document Version: v1.7.0-Canonical-Implementation-Baseline  
Target Repository Path: docs/architecture/SYSTEM_ARCHITECTURE.md  
BRD Baseline: docs/business/BRD.md (v1.2.1)  

## Revision History

| Version | Date | Author | Description |
| :--- | :--- | :--- | :--- |
| v1.0.0 | 2026-07-25 | BAI | Initial draft of the system architecture baseline. |
| v1.2.1 | 2026-07-26 | BAI | Reorganized into standard 17-layer format. |
| v1.3.0 | 2026-07-27 | BAI | Integrated dynamic membership-based RLS, family delegation updates, outbox patterns, and server-side masking. |
| v1.3.1 | 2026-07-27 | BAI | Final baseline addressing precision feedback from ChatGPT 5.5 review. |
| v1.4.0 | 2026-07-27 | BAI | Updated Traceability matrices, retention lifecycle policies, malware scan workflow, and role-segregated WITH CHECK RLS policies. |
| v1.5.0 | 2026-07-27 | BAI | Integrated role-segregated RLS policies, workspace-scoped family delegations, auto-approval rules engine table, deterministic PII classification, restored IMAP connector flow, and scope boundaries. |
| v1.6.0 | 2026-07-27 | BAI | Resolved NFR definitions, hardened order RLS, qualify_order RPC design, added Aadhaar to PII classification, and introduced plan entitlements model. |
| v1.7.0 | 2026-07-27 | BAI | Enforced RPC-only order qualification (removed advisor direct update), workspace-matched family RLS, expanded audit scope, and added plan entitlements. |

---

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

---

## 2. Master Business Capability Mapping Matrix

| Capability ID | Capability Name | Target Services | Database Tables / Entities | Edge Functions |
| :--- | :--- | :--- | :--- | :--- |
| **BC-001** | Identity & Access Management | `AuthService` | `profiles`, `workspace_memberships` | None |
| **BC-002** | Distributor Lifecycle Management | `WorkspaceService` | `workspaces`, `mfd_profiles`, `mfd_verification_documents`, `mfd_onboarding_reviews` | None |
| **BC-003** | Investor Lifecycle Management | `MembershipService` | `profiles` | None |
| **BC-004** | Relationship Management | `MembershipService` | `workspace_memberships` | None |
| **BC-005** | Portfolio Management | `WorkspaceService` | `portfolios`, `folios`, `scheme_holdings`, `transactions` | None |
| **BC-006** | Registrar Data Ingestion | `IngestionService` | `transactions`, `scheme_holdings` | `cams-kfintech-ingestion` |
| **BC-007** | Educational AI Assistance | `AIProxyService` | None | `ai-helper` |
| **BC-008** | Customer Servicing (Ticketing) | `TicketService` | `support_tickets` | None |
| **BC-009** | Dual Subscription & Billing | `BillingService` | `subscription_plans`, `workspace_billing`, `investor_subscriptions`, `payment_events`, `plan_entitlements` | `subscription-manager` |
| **BC-010** | Platform Governance & Administration | `AdminService` | `workspace_audit_logs`, `profiles`, `ai_guardrail_versions` | None |
| **BC-011** | Document Management (Lineage) | `IngestionService` | `ingestion_logs` | `cams-kfintech-ingestion` |
| **BC-012** | Actionable Notification Management| `NotificationService` | `notifications`, `notification_retry_queue` | `notification-dispatcher` |
| **BC-013** | Document Storage & Vaulting | `StorageService` | `ingested_documents` | None |
| **BC-014** | Distributor Analytics Dashboard | `AnalyticsService` | `mfd_dashboard_metrics` (View/Table) | None |
| **BC-015** | Universal Search & Discovery | `SearchService` | `folios`, `transactions`, `support_tickets`, `amfi_factsheets`, `ingested_documents`, `searchable_tools` | None |
| **BC-016** | Platform Configuration | `ConfigService` | `platform_settings`, `workspace_settings`, `feature_flags`, `notification_templates`, `registrar_configs` | None |
| **BC-017** | AMFI Scheme Factsheets & Market Data | `FactsheetService` | `amfi_factsheets` | `amfi-nav-worker` |
| **BC-018** | Investor Referral Engine | `ReferralService` | `investor_referrals`, `referral_conversions`, `referral_rewards` | `referral-tracker` |

---

## 3. Core Architectural Layers

### A. Presentation Layer (Flutter Client)
* **Architecture Pattern**: Clean Architecture with BLoC / Provider state management organized into structured features (Data ➔ Domain ➔ Presentation).
* **Core Modules**:
  * *Investor Workspace*: Portfolio view, Buy/Sell/Switch order initiation, Family delegation hub.
  * *MFD Command Hub*: Transaction qualification queue, auto-approval threshold configuration, client onboarding.
  * *PII Guardrails*: UI renders strictly server-authorized masked projections by default. Client-side formatting is supplementary and is never treated as a security boundary.

### B. Security & Identity Layer (Supabase Auth & RLS)
* **Authentication**: Multi-factor Mobile/Email OTP authentication via GoTrue.
* **Authorization & Multi-Tenancy**:
  * Enforced at the database engine level via PostgreSQL Row-Level Security (RLS).
  * User JWT tokens carry `workspace_id`, `role` (mfd, investor, delegate), and `subscription_tier`.
  * **Important**: JWT `workspace_id` indicates active UI context; database authorization for multi-relationship investors is strictly enforced via `workspace_memberships` table queries to prevent access token hijacking.

### C. Serverless Execution & Edge Layer (Deno Edge Functions)
* **Mailbag & Feed Ingestion Worker**:
  * Receives CAMS/KFintech WBR2 & WBR22 DBF feeds and CAS PDF files.
  * Processes files using in-memory RAM stream decoding (zero disk persistence for zero-trust security).
* **Order Auto-Approval Engine**:
  * Evaluates pending investor transaction requests against MFD-configured threshold rules (e.g., SIP amount limits).
  * Automatically advances order statuses (`pending_qualification` ➔ `auto_approved` or `pending_review`).
* **AMFI Market Data Sync Worker**:
  * Scheduled cron worker pulling daily scheme NAVs and riskometer metadata directly from official AMFI data feeds.

---

## 4. Canonical Role Mapping Matrix

The following matrix maps Business Requirements Document (BRD) user personas to underlying database Auth & Membership structures:

| BRD Persona | Auth Role | Membership Role | Notes |
| :--- | :--- | :--- | :--- |
| **Distributor** | `mfd` | `workspace_owner` / `advisor` | Own workspace scope. Full write capabilities within workspace boundaries. |
| **Mapped Investor** | `investor` | `investor` | Active membership required to view details or initiate transactions. |
| **Exploring Investor** | `investor` | `none` | Standalone explore access only; cannot access specific workspace datasets. |
| **Family Guest** | `investor` | `delegate` | Read-only delegated access to portfolios/holdings only. |
| **Platform Admin** | `platform_admin` | `none` | Audited system-wide override access. Bypass check triggers log warnings. |

---

## 5. Core Data Architecture & Domain Model
The database is structured into 5 primary entity domains matching the business capabilities:

| Domain | Key Data Entities | Architectural Purpose |
| :--- | :--- | :--- |
| **Identity & Access** | `workspaces`, `profiles`, `workspace_memberships`, `mfd_profiles`, `mfd_verification_documents`, `mfd_onboarding_reviews`, `advisor_profiles`, `workspace_branding` | Manages multi-tenant workspace boundaries, user profiles, and roles (`platform_admin`, `admin`, `advisor`, `investor`, `operations`). |
| **Portfolio & Holdings** | `portfolios`, `folios`, `scheme_holdings`, `transactions` | Stores unit balances, scheme choices, NAV pricing historical tracks, and raw statement data. |
| **Order Execution** | `order_requests`, `workspace_invitations`, `workspace_audit_logs`, `event_outbox`, `auto_approval_rules` | Manages Buy/Sell/Switch initiation, MFD approval queues, and immutable security audit trails. |
| **Subscriptions & Billing** | `subscription_plans`, `workspace_billing`, `investor_subscriptions`, `payment_events`, `plan_entitlements` | Enforces feature gates and client limit verification triggers for MFD subscription tiers. |
| **Referrals & Delegations** | `investor_referrals`, `referral_conversions`, `referral_rewards`, `family_delegations` | Manages asymmetric read-only sharing controls and viral registration attribution. |

---

## 6. Concrete Row Level Security (RLS) Mechanics
The database layer uses specific PostgreSQL policies to guarantee Workspace Isolation (BR-003) and Role-Based Access Control (BR-007):

### A. RPC-Only Order Qualification & Order RLS (P0-1 / BRD-FR-005)
* Hardened role-segregated RLS policies enforce query access limits:

```sql
-- Investor: View own orders within active workspace
CREATE POLICY order_requests_investor_select ON order_requests FOR SELECT
    USING (investor_profile_id = auth.uid() AND has_active_workspace_membership(workspace_id));

-- Investor: Create own orders (restricted to pending_qualification)
CREATE POLICY order_requests_investor_insert ON order_requests FOR INSERT
    WITH CHECK (
        investor_profile_id = auth.uid() 
        AND has_investor_membership(workspace_id) 
        AND status = 'pending_qualification'
    );

-- Distributor/Advisor: Read workspace orders
CREATE POLICY order_requests_advisor_select ON order_requests FOR SELECT
    TO authenticated
    USING (has_advisor_membership(workspace_id));
```
* **Prohibition (RPC-Only qualification)**: Direct `UPDATE` and `DELETE` queries on `order_requests` by normal users are blocked. Status transitions are executed exclusively via a `SECURITY DEFINER` RPC function `qualify_order(order_id, decision, rejection_reason)` with `search_path = public`.
* **qualify_order RPC internal safeguards**:
  1. Verifies `has_advisor_membership(workspace_id)` or platform admin override.
  2. Enforces strict state machine transitions (`pending_qualification` ➔ `approved`/`rejected`).
  3. Restricts mutations strictly to `status`, `reviewed_by`, `reviewed_at`, and `rejection_reason`.
  4. Inserts an immutable event log into `workspace_audit_logs`.

### B. Explicit Workspace Match in Family Delegation RLS (P0-2 / BRD-BR-009)
* The `family_delegations` schema requires `owner_profile_id`, `delegate_profile_id`, AND `workspace_id`.
* Enforces that family delegation **never** grants cross-workspace visibility. The portfolios RLS policy explicitly matches workspace IDs and handles active expiration limits:

```sql
-- Allows family delegates read-only portfolio access matching specific workspace IDs
CREATE POLICY family_delegate_read_policy ON portfolios FOR SELECT TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM family_delegations fd
        WHERE fd.owner_profile_id = portfolios.client_id
          AND fd.delegate_profile_id = auth.uid()
          AND fd.workspace_id = portfolios.workspace_id
          AND fd.is_active = TRUE
          AND (fd.expires_at IS NULL OR fd.expires_at > now())
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

## 7. Edge Service Architectures & Ingestion Pipelines

### A. In-Memory Zero-Disk Ingestion Pipeline (BC-006 / FR-009 / BC-013 / P1-1)
```text
[IMAP/OAuth Connector] ➔ [Poll Mailbox] ➔ [Validate Sender & Attachment Hash] ➔ [MIME/Magic-Byte Check] ➔ [Malware Scan] ➔ [Encrypted Object Storage] ➔ [Memory Stream Parser] ➔ [Immutable Ingestion Log]
```
To guarantee zero-trust compliance, the parser reads DBF feeds and CAS PDFs directly from the secure encrypted object storage vault into memory buffers. It extracts transaction arrays and updates folio balances without saving temporary files to local disk.
* **Security & Credentials**: Mailbox credentials (OAuth tokens) are encrypted separately at rest.
* **Vaulting Controls**: The encrypted object storage vault enforces file-size limits (<20MB), MIME validation (PDF/DBF), malware screening, SHA-256 content-hash deduplication, and single-use signed URLs expiring in 15 minutes.
* **Retention Policy**: Retention is governed by configurable platform policy and applicable regulatory, contractual, and user-consent requirements. Automatic deletion shall not occur while a document is required for portfolio lineage, audit, active servicing, or legal retention. Temporary processing artefacts may be removed after 30 days, but original vault documents follow a separate compliance retention lifecycle.

### B. Advanced Auto-Approval Rule Engine (BR-006 / P1-2)
1. Mapped Investor submits a Buy/Sell/Switch `order_request`.
2. The database trigger evaluates the request against rules defined in the `auto_approval_rules` table:
   * Fields: `workspace_id`, `transaction_type`, `min_amount`, `max_amount`, `trusted_client_only`, `category_restrictions`, `effective_from`, `is_active`.
3. If qualifying, status is updated to `auto_approved` and the trigger stamps the target `rule_id` and `rule_version` directly onto the `order_requests` row. If not qualifying, it falls back to `pending_qualification`.

---

## 8. Asynchronous Event Bus Topology & Transactional Outbox
Money Bowl features a Transactional Outbox Pattern to guarantee durable event dispatching:

```text
DB Transaction ➔ [Write Business Data + Write event_outbox] ➔ Commit ➔ Postgres Listener / Cron Dispatcher ➔ Deno Edge Workers
```

All domain events are written to the `event_outbox` table within the primary database transaction. A listener or background agent dispatches these to Deno Edge workers with exponential retry policies.

* **`order.created`**: Fired when an investor creates an order request. Triggers the auto-approval engine.
* **`ticket.raised`**: Fired on customer support request. Routes alert notifications to the assigned advisor.
* **`statement.imported`**: Fired upon statement completion. Re-calculates valuation history and updates the analytics dashboard.
* **Mailbox Health Events**: Explicit system notification payloads:
  * `mailbox.authentication_failed`: Triggers when OAuth flow fails.
  * `mailbox.token_expiring`: Warns MFDs 7 days prior to authentication token expiry.
  * `mailbox.poll_failed`: Dispatches upon consecutive polling timeout failures.
  * `mailbox.connection_restored`: Dispatches upon successful auto-reconnection.

---

## 9. Actionable Notification Management (BC-012)
* **Channels**: Email, SMS, WhatsApp, and Push Notifications.
* **Requirements**: Dispatches `FR-014` support notifications, mailbox health exceptions, as well as capability-triggered events (e.g. statement updates, workspace invitations).
* **Rules**: Enforces `BR-009` (family consent notifications) by alerting owners whenever family visibility delegation occurs.
* **Retry Queue Engine**: Failures trigger the dispatcher worker using exponential backoff:
  $$T_{\text{wait}} = 2^{\text{attempt}} \times 60 \text{ seconds}$$
* **Dead Letter Queue (DLQ)**: Tasks failing more than 5 times are routed to `failed_notifications` for administrative review.

---

## 10. Customer Servicing & Ticketing Workflow Engine (BC-008)
Support requests follow a rigid state machine layout:
```text
[raised] ➔ [assigned] ➔ [resolved] ➔ [closed]
```
* **SLA Thresholds**:
  * Default operational SLA targets are set to P0: 4h, P1: 24h, P2: 72h. Contractual SLA values are plan-configurable and do not constitute static contractual commitments. Breaches auto-escalate directly to the workspace owner.

---

## 11. Encrypted Document Vaulting & Signed URL Lineage (BC-011, BC-013 / P0-3)
* **Encryption**: CAS PDF statements are encrypted at the object boundary using AES-256 keys.
* **Access Control**: Users receive signed URLs with an expiry limit of 15 minutes. Decryption happens on-the-fly inside the Edge compute boundary.
* **Denial Invariant**: Family delegates are strictly denied access to `ingested_documents`, original CAS files, or signed document download URLs unless an explicit, separate document-level consent grant exists.

---

## 12. Viral Referral Engine & Fraud Detection Rules (BC-018 / FR-011)
* **Attribution**: Referrals are tracked using SHA-256 hashed invite tokens.
* **Fraud Detection rules**:
  * Self-Referral block: Prevents users from registering with identical emails/phones.
  * Collision block: Rejects referrals matching pre-existing PAN or bank accounts.
* **Rewards**: Referrals award temporary subscription plan extensions (e.g. 30 days) to both parties upon successful conversion.

---

## 13. Dual Subscription & Feature Gating Engine (BC-009 / BR-011)
* **State Machine**: `trialing` ➔ `active` ➔ `past_due` ➔ `suspended` ➔ `cancelled`.
* **Starter limits**: Gated at 25 mapped clients. Upgrades require active checkout session confirmations.
* **Plan Entitlements Model (P1-1)**: Subscription features are gated via `plan_entitlements` records mappings:
  * Keys: `max_active_investors`, `mailbag_ingestion_enabled`, `auto_approval_enabled`, `white_label_enabled`, `crm_enabled`, `multi_advisor_enabled`, `family_hub_enabled`, `capital_gain_projection_enabled`, `priority_support_enabled`, `advanced_analytics_enabled`, `support_sla_policy_id`.
* **Idempotency**: Webhook payment events use unique payment IDs to prevent double-charging or double-crediting.
* **Auto-Approval limits**: Workspace limits are checked at order submission. If the workspace exceeds its monthly allowed auto-approval volume, orders fallback to manual qualification.

---

## 14. Educational AI Assistant Proxy & Guardrail Declination Gate (BC-007, BR-010)
* **Core AI Proxy**: Secured LLM connector with predefined educational prompts.
* **Calculators**: Execution of financial calculators is performed deterministically outside the LLM context.
* **Decline Gate (FR-013)**: The prompt system includes rigid system instructions to detect intent. Queries containing recommendation keywords (e.g., "which fund to buy", "should I switch") are blocked and responded to with the static education declination template.
* **Ticket Handoff (FR-014)**: Users can request AI to log a support ticket, which routes directly into their mapped advisor's queue.
* **Exploring Investor AI routing**: Exploring investors without a mapped advisor route support queries to Platform Admin support or are prompted to establish an MFD relationship before tickets can be assigned.

---

## 15. Universal Search & Searchable Tools Catalog (BC-015 / FR-007 / P1-2)
To meet the `<200ms` latency SLA, the database uses PostgreSQL Generalized Inverted Index (GIN) on scheme names, folios, and client details using the `pg_trgm` extension. Projections include `amfi_factsheets`, `folios`, `transactions`, `ingested_documents`, `support_tickets`, and `searchable_tools` (tool catalog containing deterministic calculators, sheets, and documents metadata), strictly filtered through RLS.

---

## 16. Distributor Analytics Dashboard View (BC-014)
To drive dashboard metric summaries without executing heavy aggregate queries on load, the system projects analytics through the `mfd_dashboard_metrics` view:
* **Fields**: `workspace_id`, `total_aum`, `active_investor_count`, `pending_ticket_count`, `active_sip_count`, `monthly_sip_value`, `last_successful_ingestion_at`, `failed_ingestion_count`, `refreshed_at`.
* **Sources**: `portfolios`, `workspace_memberships`, `support_tickets`, `transactions`, `ingestion_logs`.

---

## 17. Non-Functional Criteria & Security Architecture

### A. Architectural Invariant for BR-004 ("No Consolidation")
Cross-workspace portfolio aggregation, consolidated XIRR calculations, or merged performance APIs across multiple MFD relationships are strictly prohibited at database, view, and API levels.

### B. Global Identity Resolution (BR-001 / P1-3)
Single digital investor records use deterministic SHA-256 HMAC attributes inside profiles (`pan_hmac`, `normalised_phone_hmac`, `normalised_email_hmac`, and `identity_match_status`) to resolve matches.

### C. Comprehensive PII Classification & Encryption List (P0-4)
All sensitive attributes are classified and protected at rest and in transit:
* **Target List**: `Aadhaar number` (and Aadhaar-derived identifiers), `PAN`, `Bank Account Numbers`, `IFSC`, `Phone`, `Email`, `Date of Birth`, `Nominee Details`, `Statement Passwords`, and `Mailbox OAuth Credentials`.
* **Aadhaar Exclusion Rule**: Aadhaar is strictly excluded from general database search indexes or application log payloads, displaying strictly as masked projections.
* **Remediation Policy**: Encrypted using AES-256 keys managed by the Supabase Vault. Reveals trigger step-up MFA/OTP validations, writing immutable audit logs to `pii.revealed` in the central audit queue.

### D. System-Wide Non-Functional Requirements (NFR-001 - NFR-005)
* **`NFR-001` (Data Security & Masking)**: Sensitive PII attributes encrypted at rest & masked by default; step-up MFA reveal.
* **`NFR-002` (Universal Search Latency)**: Search queries complete within 200 milliseconds.
* **`NFR-003` (Order Routing SLA)**: Submitted orders appear in MFD queue within 5 seconds.
* **`NFR-004` (Statement Processing SLA)**: Mailbag CAS attachments processed within 15 minutes.
* **`NFR-005` (Audit Lineage)**: Immutable, timestamped audit trails for all critical actions.

### E. Service Level Objectives (SLOs)
* **`ARCH-SLO-001`**: Security engine key validation overhead latency: `<50ms`.
* **`ARCH-SLO-002`**: Central log queue write confirmation: `<100ms` async acknowledgment.

### F. Immutability Triggers & Explicit Audit Log Scopes
* Every status change on `order_requests`, workspace administrative resets, and billing overrides insert tracking records into `workspace_audit_logs`. The `workspace_audit_logs` and `ingestion_logs` tables enforce immutability via triggers blocking all update and delete queries.
* **Explicit Audit Log Triggers (P0-3)**: The system writes immutable audit events to `workspace_audit_logs` upon:
  * Family delegation grant creation.
  * Consent acceptance for family guest access.
  * Delegation revocation/expiration.
  * Original CAS document download attempts.

---

## 18. Many-to-Many Traceability Matrix

| Business Capability | Mapping Personas | BRD Requirements | BRD Rules | Non-Functional Requirements | Postgres Entities & Component Links |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **BC-001** (Identity) | Platform Admin, Distributor, Mapped Investor, Exploring Investor | `FR-002`, `FR-003`, `FR-004` | `BR-001`, `BR-007`, `BR-008` | `NFR-001` | `profiles`, `workspace_memberships` |
| **BC-002** (Distributor) | Distributor | `FR-001` | N/A | N/A | `mfd_profiles`, `mfd_onboarding_reviews` |
| **BC-003** (Investor) | Investor | `FR-002` | `BR-001` | N/A | `profiles` |
| **BC-004** (Relationship) | Investor, Distributor | `FR-005`, `FR-006` | `BR-002`, `BR-003`, `BR-004` | `NFR-003`, `NFR-005` | `workspace_memberships` |
| **BC-005** (Portfolio) | Investor, Distributor | N/A | `BR-004` | `NFR-003`, `NFR-005` | `portfolios`, `folios`, `scheme_holdings`, `transactions`, Valuation & XIRR views |
| **BC-006** (Ingestion) | Distributor | `FR-009` | `BR-003` (Secondary check) | `NFR-004` | `cams-kfintech-ingestion` Edge function, `transactions`, `folios` |
| **BC-007** (Educational AI) | Distributor, Mapped Investor, Exploring Investor, Family Guest (read-only), Platform Admin (testing) | `FR-012`, `FR-013`, `FR-014` | `BR-010` | N/A | `ai-helper` Edge worker, declination guard gate |
| **BC-008** (Ticketing) | Investor, Distributor | `FR-014` | N/A | N/A | `support_tickets` |
| **BC-009** (Subscriptions) | Distributor, Mapped Investor, Exploring Investor | `FR-010` | `BR-011` | N/A | `subscription_plans`, `workspace_billing`, `payment_events`, `plan_entitlements` |
| **BC-010** (Platform Admin) | Platform Admin | `FR-003` | `BR-007` | `NFR-005` | `platform_admin_override_policy`, `workspace_audit_logs` |
| **BC-011** (Lineage) | None | N/A | Auditability Principle | `NFR-005` | `ingestion_logs` (Immutable) |
| **BC-012** (Notifications) | Investor, Distributor | FR-014 plus BC-triggered events | BR-009 (family consent notifications) | N/A | `notifications`, `notification_retry_queue` |
| **BC-013** (Vaulting) | Investor, Distributor | `FR-009` | `BR-008` | `NFR-001` | `ingested_documents`, AES-256 encrypted object storage vault |
| **BC-014** (Analytics) | Distributor | N/A | `BR-004` (Enforced separation) | N/A | `mfd_dashboard_metrics` view |
| **BC-015** (Search) | Investor, Distributor | `FR-007` | N/A | `NFR-002` | GIN search index projections, `searchable_tools` |
| **BC-016** (Platform Config) | Platform Admin | N/A | BR-006, BR-010, BR-012 | N/A | platform_settings, feature_flags, notification_templates, registrar_configs, ai_guardrail_versions (Design Principle: "Configuration over Customisation") |
| **BC-017** (AMFI Market Data) | Investor, Distributor | `FR-008` | `BR-012` | N/A | `amfi_factsheets` table, `amfi-nav-worker` cron Edge function |
| **BC-018** (Referral Engine) | Investor | `FR-011` | N/A | `NFR-005` | `investor_referrals`, `referral_rewards` |

---

## 19. Product Scope Boundaries (P1-5)

The following areas are explicitly marked as **OUT OF SCOPE** for the Money Bowl platform:
* Direct stock tracking and equity execution.
* Insurance policies, quotes, or tracking integrations.
* Fixed Deposits (FDs) or other non-registrar debt products.
* Cryptocurrency holdings or blockchain asset valuations.
* Automated portfolio rebalancing or model execution.
* Tax filing submissions or legal validation filings.
* Unadvised direct execution options.
