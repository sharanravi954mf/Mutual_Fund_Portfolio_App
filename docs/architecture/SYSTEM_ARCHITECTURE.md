# Money Bowl — System Architecture Specification
Document Version: v2.1.0-Canonical-Production-Freeze  
Target Repository Path: docs/architecture/SYSTEM_ARCHITECTURE.md  
BRD Baseline: docs/business/BRD.md (v1.3.0)  

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
| v1.8.0 | 2026-07-27 | BAI | Freezed baseline, standardized order status enum state machine lifecycle, implemented qualify_order RPC row locking, enforced accepted consent status checks on family delegations RLS, and standardized JWT claims. |
| v1.9.0 | 2026-07-27 | BAI | Updated auto-approval fallback behavior, qualify_order RPC authorization safeguards, integrated cancel_order RPC function, and standardized family delegations as authoritative access sources. |
| v2.0.0 | 2026-07-27 | BAI | Final permanent production freeze baseline, unified outbox-based auto-approval state flow, blocked direct advisor intervention on pending_qualification orders to prevent race conditions, and updated BC-005 taxonomy. |
| v2.0.1 | 2026-07-27 | BAI | Incremented to address ChatGPT 5.5 review audit points. Corrected canonical order lifecycle, standardized outbox auto-approval workflow, added apply_auto_approval_decision RPC design, corrected qualify_order and cancel_order RPC definitions, expanded audit log coverage, and refined referral token security semantics. Further expanded in final pass to document canonical application-profile resolution, Family Delegation profile-ID corrections, cancellation identity hardening, Platform Admin narrow-RPC restrictions, dual subscription scope details, and referral conversion scope clarifications. |
| v2.1.0 | 2026-07-28 | RAI | Aligned order execution schema and qualify_order permissions with BRD v1.3.0. Captured initiator and reviewer profile parameters allowing same MFD-side profile to both initiate and qualify. Expanded audit fields matrix and dual-subscription details. |

---

## 1. Executive System Topology & Execution Zones
Money Bowl is engineered as a modular, event-driven B2B2C microservices-on-serverless architecture. It provides isolation between Multi-Tenant MFD Workspaces and End-Investors while executing portfolio ingestion, order qualification, and market data synchronization in real-time.

┌─────────────────────────────────────────────────────────────────────────────┐
│                            SYSTEM TOPOLOGY MAP                              │
├─────────────────────────────────────────────────────────────────────────────┤
│  Flutter Client (iOS/Android/Web)                                           │
│         │                                                                   │
│         ├─► Supabase Auth (JWT with app_metadata.workspace_id,              │
│         │                  app_metadata.user_role,                          │
│         │                  and app_metadata.subscription_tier claims)       │
│         ├─► PostgreSQL Database (Row-Level Security / Multi-Tenancy)        │
│         └─► Deno Edge Functions (Ingestion, Auto-Approval Engine, AMFI Sync) │
└─────────────────────────────────────────────────────────────────────────────┘

---

## 2. Master Business Capability Mapping Matrix

| Capability ID | Capability Name | Target Services | Database Tables / Entities / Components | Edge Functions |
| :--- | :--- | :--- | :--- | :--- |
| **BC-001** | Identity & Access Management | `AuthService` | `profiles`, `workspace_memberships` | None |
| **BC-002** | Distributor Lifecycle Management | `WorkspaceService` | `workspaces`, `mfd_profiles`, `mfd_verification_documents`, `mfd_onboarding_reviews` | None |
| **BC-003** | Investor Lifecycle Management | `MembershipService` | `profiles` | None |
| **BC-004** | Relationship Management | `MembershipService` | `workspace_memberships`, `family_delegations` | None |
| **BC-005** | Portfolio & Order Execution | `PortfolioService`, `OrderService` | `portfolios`, `folios`, `scheme_holdings`, `transactions`, `order_requests`, `auto_approval_rules`, `event_outbox`, `qualify_order`, `cancel_order`, `apply_auto_approval_decision` | `order-auto-approval-worker` |
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
  * *MFD Command Hub*: Transaction qualification queue, auto-approval threshold configuration, client onboarding, and Distributor-assisted Buy/Sell/Switch initiation for actively mapped investors.
  * *PII Guardrails*: UI renders strictly server-authorized masked projections by default. Client-side formatting is supplementary and is never treated as a security boundary.

### B. Security & Identity Layer (Supabase Auth & RLS)
* **Authentication**: Multi-factor Mobile/Email OTP authentication via GoTrue.
* **Authorization & Multi-Tenancy**:
  * Enforced at the database engine level via PostgreSQL Row-Level Security (RLS).
  * User JWT tokens carry `app_metadata.workspace_id`, `app_metadata.user_role`, and `app_metadata.subscription_tier` claims.
  * **Important**: JWT `app_metadata.workspace_id` claim indicates active UI context; database authorization for multi-relationship investors is strictly enforced via `workspace_memberships` table queries to prevent access token hijacking.

### C. Serverless Execution & Edge Layer (Deno Edge Functions)
* **Mailbag & Feed Ingestion Worker**:
  * Receives CAMS/KFintech WBR2 & WBR22 DBF feeds. The PDF service/Edge contract
    is established with synthetic characterization layouts; live registrar CAS
    PDF layouts require sanitized fixtures and deterministic tests before enablement.
  * Processes files using in-memory RAM stream decoding (zero disk persistence for zero-trust security).
* **Order Auto-Approval Engine**:
  * Deno serverless worker evaluating submitted client orders against rules to execute automated status transitions.
* **AMFI Market Data Sync Worker**:
  * Scheduled cron worker pulling daily scheme NAVs and riskometer metadata directly from official AMFI data feeds.

---

## 4. Canonical Role Mapping Matrix

The following matrix maps Business Requirements Document (BRD) user personas to underlying database Auth & Membership structures:

| BRD Persona | Auth Role | Membership Role | Notes |
| :--- | :--- | :--- | :--- |
| **Distributor** | `mfd` | `workspace_owner` / `advisor` | Role-authorised servicing and order-initiation capabilities within the Distributor’s own workspace, including initiating orders for actively mapped investors. No unrestricted business-table access. The same authorised MFD-side profile may initiate and later qualify the same order. |
| **Mapped Investor** | `investor` | `investor` | Active membership required to view details or initiate transactions. |
| **Exploring Investor** | `investor` | `none` | Standalone explore access only; cannot access specific workspace datasets. |
| **Family Guest** | `investor` | `none` required | Read-only delegated access driven strictly by an active, accepted family delegations record. |
| **Platform Admin** | `platform_admin` | `none` | Narrow, action-specific support overrides through audited SECURITY DEFINER RPCs. No general business-table bypass. No unrestricted cross-workspace extraction. No order qualification, approval or rejection authority. |

### A. Sub-Role Mappings & Permissions Hierarchy
Within any workspace context, the `workspace_memberships` table defines granular permissions underneath `workspace_owner` / `advisor`:
* **`admin`**: Workspace-internal administrative permission mapping underneath the `workspace_owner`. Can configure custom branding, change auto-approval rules parameters, and manage team memberships.
* **`operations`**: Workspace-internal servicing role mapping underneath `advisor`. Allows statement upload pipeline management and support ticket qualification, but blocks manual billing parameter updates.

---

## 5. Core Data Architecture & Domain Model
The database is structured into 5 primary entity domains matching the business capabilities:

| Domain | Key Data Entities | Architectural Purpose |
| :--- | :--- | :--- |
| **Identity & Access** | `workspaces`, `profiles`, `workspace_memberships`, `mfd_profiles`, `mfd_verification_documents`, `mfd_onboarding_reviews`, `advisor_profiles`, `workspace_branding` | Manages multi-tenant workspace boundaries, user profiles, and roles (`platform_admin`, `admin`, `advisor`, `investor`, `operations`). |
| **Portfolio & Holdings** | `portfolios`, `folios`, `scheme_holdings`, `transactions` | Stores unit balances, scheme choices, NAV pricing historical tracks, and raw statement data. |
| **Order Execution** | `order_requests`, `workspace_invitations`, `workspace_audit_logs`, `event_outbox`, `auto_approval_rules` | Manages Buy/Sell/Switch initiation, MFD approval queues, and immutable security audit trails. |
| **Subscriptions & Billing** | `subscription_plans`, `workspace_billing`, `investor_subscriptions`, `payment_events`, `plan_entitlements` | Enforces feature entitlements, billing ownership, subscription lifecycle states and usage limits for both Distributor and Investor subscription tiers. |
| **Referrals & Delegations** | `investor_referrals`, `referral_conversions`, `referral_rewards`, `family_delegations` | Manages asymmetric read-only sharing controls and viral registration attribution. |

---

## 6. Concrete Row Level Security (RLS) Mechanics & Transaction Contracts
The database layer uses specific PostgreSQL policies to guarantee Workspace Isolation (BR-003) and Role-Based Access Control (BR-007):

### Canonical Application Profile Resolution
* **Core Contract**:
  * Supabase `auth.uid()` identifies the authenticated Auth account UUID.
  * Business-domain foreign keys such as `investor_profile_id`, `owner_profile_id`, and `delegate_profile_id` identify rows in `public.profiles`.
  * Whenever an authorization rule, policy, or RPC compares a business-domain profile foreign key with the current caller, the caller's profile must first be resolved through `public.current_user_profile_id()`.
  * Direct comparison of a `profiles.id`-based foreign key with `auth.uid()` is prohibited unless a specific schema field is explicitly documented as storing the Auth user UUID.
* **Invariant Guardrails for `public.current_user_profile_id()`**:
  - `public.current_user_profile_id()` returns the caller's `public.profiles.id` (UUID).
  - It derives the result from the authenticated caller's `auth.uid()`.
  - It accepts no caller-supplied identity parameters (prevents impersonation).
  - It returns exactly one application profile ID or null.
  - Missing or ambiguous mappings fail closed.
  - Security-sensitive callers, RLS policies, and RPCs must deny access when the helper returns null.
  - The helper must use hardened execution permissions (`SECURITY DEFINER`, fixed search path `SET search_path = ''`, revoking execution from `PUBLIC` except as explicitly authorised).
  - The mapping from Auth account (`auth.users.id`) to application profile (`public.profiles.id`) is enforced as unique in the database schema.

### A. Unified Order Lifecycle
Order requests follow a single, unambiguous lifecycle flow to eliminate race conditions between auto-approval workers and manual MFD qualifications:

```text
Initiator-side draft
  → pending_qualification
      ├── matching active auto-approval rule
      │     → auto_approved
      │         → external execution routing
      │
      ├── no matching auto-approval rule
      │     → pending_review
      │         ├── approved
      │         ├── rejected
      │         └── cancelled
      │
      └── investor or MFD cancellation
            → cancelled
```

* **Constraints & Lifecycle Rules**:
  * `draft` status is managed exclusively in Flutter client state. Orders are never written to the database in `draft` state.
  * A database order record is initialized strictly in the `pending_qualification` status.
  * `auto_approved` represents a terminal qualification state. Bypassing manual reviews, these orders route directly to external execution submission systems.
  * Advisors may qualify ONLY orders with `status = 'pending_review'`. Direct advisor approval or rejection of orders in `pending_qualification` state is blocked.
  * Investors can cancel only their own orders. Cancellation is permitted only while the order is in `pending_qualification` or `pending_review` status.
  * Cancellations are rejected if the order is already in `auto_approved`, `approved`, `rejected`, or `cancelled` statuses.
  * Status transitions between `auto_approved` ➔ `approved`, `auto_approved` ➔ `rejected`, or `pending_review` ➔ `auto_approved` are strictly prohibited.

* **Order Execution Security & Metadata Boundary**:
  - The `order_requests` database table explicitly separates and maps the following identifiers:
    * `workspace_id`: Identifies the target workspace where the order request belongs.
    * `investor_profile_id`: Identifies the investor whose portfolio and mutual fund assets are affected by the order.
    * `initiated_by_profile_id`: Identifies the authenticated profile of the user who created the request.
    * `initiated_by_role`: Captures the role of the initiator (`investor` or `distributor/advisor`).
    * `initiation_channel`: Records the origin/channel of the request (e.g., `investor_portal` or `advisor_portal`).
    * `reviewed_by_profile_id`: Identifies the MFD user profile who qualified the order.
    * `reviewed_at`: Enforces timestamp logging upon qualification outcomes.
  - The platform enforces the following server-side security checks:
    * **Investor Self-Initiation**: Investor-initiated orders must resolve the caller profile using `public.current_user_profile_id()` and bind it to `investor_profile_id` and `initiated_by_profile_id`. The workspace ID must match the investor's active workspace.
    * **Distributor-Assisted Initiation**: Distributor-initiated orders require that the caller has an active `workspace_owner` or `advisor` membership role in the target workspace. The target investor must have an active relationship record in that same workspace.
    * **Same-Profile Initiation & Review Invariant**: `initiated_by_profile_id` and `reviewed_by_profile_id` may contain the same MFD-side profile ID. This is a valid workflow and must not be blocked.
    * **Caller Workspace Boundary**: The caller is prohibited from submitting an order request for any workspace other than the active one.
    * **Platform Admin Block**: Platform Admins are strictly prohibited from initiating or qualifying investor orders.
    * **Family Guest Block**: Family Guests are strictly prohibited from initiating orders for other family members' portfolios.
    * **Audit Trait Persistence**: The initiator's profile, role, and the beneficiary investor's profile must be recorded immutably in the central workspace audit logs.

### B. Decoupled Event-Driven Auto-Approval Workflow
To ensure reliable, race-free operation, rule evaluation is decoupled from the transactional database path:

```text
Investor or authorised Distributor inserts order_request
→ order status = pending_qualification
→ order.created event is written to event_outbox
   in the same database transaction
→ transaction commits
→ Deno order-auto-approval-worker claims the event
→ worker evaluates active auto_approval_rules
→ worker calls a restricted service-only RPC
→ order transitions to:
     auto_approved
     or pending_review
→ rule ID, rule version and decision are audited
```

* **Workflow Mechanics & SLA**:
  * A database trigger writes the `order.created` event into `event_outbox` in the same transaction as the order creation. The trigger must not evaluate business rules.
  * The Deno `order-auto-approval-worker` is the exclusive evaluation engine. It polls the outbox, claims events safely, and processes rules.
  * Worker execution must be idempotent; replaying an outbox event must not produce duplicate approval states or side-effects.
  * Applied `rule_id` and `rule_version` details must be stored directly on the qualified `order_requests` row.
  * Unmatched rules trigger a fallback status transition to `pending_review`.
  * The entire workflow from insertion to state resolution must be completed within 5 seconds to satisfy the `NFR-003` queue availability SLA.

### C. Service-Only Auto-Approval RPC: `apply_auto_approval_decision`
Automated rule decisions are written via a dedicated, secure database interface:

* **Signature**:
  ```sql
  public.apply_auto_approval_decision(
      p_order_id uuid,
      p_decision public.order_status,
      p_rule_id uuid,
      p_rule_version integer,
      p_correlation_id uuid
  ) RETURNS public.order_requests
  ```
* **Internal Safeguards & Rules**:
  1. Must be declared as `SECURITY DEFINER` and enforce `SET search_path = ''`.
  2. Uses fully qualified object references exclusively (`public.order_requests`, `public.workspace_audit_logs`, `public.event_outbox`, `public.auto_approval_rules`).
  3. Processing and Validation Sequence:
     - **Step 1: Lock the order row and load state**:
       ```sql
       SELECT
           workspace_id,
           investor_profile_id,
           status,
           auto_approval_correlation_id,
           triggered_rule_id,
           triggered_rule_version
       INTO
           v_workspace_id,
           v_investor_profile_id,
           v_status,
           v_existing_correlation_id,
           v_existing_rule_id,
           v_existing_rule_version
       FROM public.order_requests
       WHERE id = p_order_id
       FOR UPDATE;
       ```
     - **Step 2: Idempotent Replay Check (Before Stale-State Validation)**:
       - If `v_existing_correlation_id = p_correlation_id` then:
         - Verify `p_decision` matches `v_status`.
         - Verify `p_rule_id` matches `v_existing_rule_id`.
         - Verify `p_rule_version` matches `v_existing_rule_version`.
         - If all match, return the existing `order_requests` row immediately without mutation or duplicate side effects.
         - If any field differs, raise a SQL exception with code `idempotency_conflict`.
     - **Step 3: Stale State Check**:
       - If `v_status != 'pending_qualification'` then:
         - Raise a SQL exception with code `stale_order_state`.
     - **Step 4: Outbox Event & Correlation Binding Validation**:
       - Retrieve and lock the associated outbox event:
         ```sql
         SELECT
             id,
             entity_id,
             event_type,
             status,
             claimed_at,
             claimed_by
         INTO
             v_event_id,
             v_event_entity_id,
             v_event_type,
             v_event_status,
             v_claimed_at,
             v_claimed_by
         FROM public.event_outbox
         WHERE id = p_correlation_id
         FOR UPDATE;
         ```
       - Reject and raise exceptions if:
         - Event does not exist: `event_not_found`.
         - Event type is not `order.created`: `invalid_event_type`.
         - Event targets a different order (`v_event_entity_id != p_order_id`): `event_order_mismatch`.
         - Event status is `completed`: `event_already_completed`.
         - Event status is not `processing`, or `claimed_at` is null, or `claimed_by` is null: `event_not_claimed`.
     - **Step 5: Conditional Rule Validation**:
       - **IF** `p_decision = 'auto_approved'` **THEN**:
         - Require `p_rule_id` and `p_rule_version` to be non-null (else raise exception).
         - Validate that the rule exists: `rule_not_found`.
         - Validate that the rule belongs to the order's workspace: `rule_workspace_mismatch`.
         - Validate that the rule is active: `rule_inactive`.
         - Validate rule-version equality: `p_rule_version` must exactly match the persisted `auto_approval_rules.rule_version`. Raise `rule_version_mismatch` on mismatch or if the rule was modified after evaluation.
       - **ELSIF** `p_decision = 'pending_review'` **THEN**:
         - Require `p_rule_id IS NULL` and `p_rule_version IS NULL` (else raise exception).
         - Do not perform any rule lookup or load rule parameters.
       - **ELSE**:
         - Raise exception for unsupported decision.
       - **END IF;**
      - **Step 6: Apply state transition**:
        - Update status, save validated rule ID, validated rule version, correlation ID, and timestamps on the `order_requests` row.
        - Update the `event_outbox` row setting `status = 'completed'` and `updated_at = now()`.
      - **Step 7: Record append-only audit log**:
        - Record an immutable audit log payload in `public.workspace_audit_logs` using strictly values loaded from the locked database record (`v_workspace_id`, `v_investor_profile_id`).
  4. Stable Machine-Readable Error Codes:
     - `idempotency_conflict`
     - `stale_order_state`
     - `event_not_found`
     - `event_order_mismatch`
     - `invalid_event_type`
     - `event_not_claimed`
     - `event_already_completed`
     - `rule_not_found`
     - `rule_inactive`
     - `rule_workspace_mismatch`
     - `rule_version_mismatch`
  5. Uniqueness Constraint:
     ```sql
     CREATE UNIQUE INDEX order_requests_auto_approval_correlation_uidx
     ON public.order_requests (auto_approval_correlation_id)
     WHERE auto_approval_correlation_id IS NOT NULL;
     ```
  6. Privilege Contract:
      ```sql
      REVOKE ALL ON FUNCTION public.apply_auto_approval_decision(uuid, public.order_status, uuid, integer, uuid) FROM PUBLIC;
      REVOKE ALL ON FUNCTION public.apply_auto_approval_decision(uuid, public.order_status, uuid, integer, uuid) FROM authenticated;
      GRANT EXECUTE ON FUNCTION public.apply_auto_approval_decision(uuid, public.order_status, uuid, integer, uuid) TO service_role;
      ```
  7. Security Invariants:
      * Only the trusted Deno backend worker (acting as the authorized `service_role`) may invoke this function.
      * Investors, advisors, family guests, and normal authenticated users must be denied execution rights.
      * Normal authenticated users must receive permission denied when invoking `apply_auto_approval_decision` directly.

### D. Hardened Advisor Qualification RPC: `qualify_order`
Manual advisor qualification is routed through a separate, audited routine:

* **Signature**:
  ```sql
  public.qualify_order(
      p_order_id uuid,
      p_decision public.order_status,
      p_rejection_reason text DEFAULT null
  ) RETURNS public.order_requests
  ```
* **Internal Safeguards & Rules**:
  1. Must be declared as `SECURITY DEFINER` and enforce `SET search_path = ''`.
  2. Acquires row lock querying all check fields:
     ```sql
     SELECT workspace_id, investor_profile_id, status
     INTO v_workspace_id, v_investor_profile_id, v_status
     FROM public.order_requests
     WHERE id = p_order_id
     FOR UPDATE;
     ```
  3. Verifies that the caller has an active workspace-owner or advisor membership in the order's workspace (via `public.has_advisor_membership(v_workspace_id)`). Platform Admins must not qualify, approve, or reject order requests; Platform Admin status does not satisfy `qualify_order` authorization.
  4. Blocks execution attempts by Platform Admins, investors, family guest delegates, or unrelated advisors.
  5. Accepts transitions only if the order's locked status is exactly `pending_review`.
  6. Restricts status mutations strictly to `approved` or `rejected`.
  7. Mutates only `status`, `reviewed_by_profile_id`, `reviewed_at`, and `rejection_reason` columns.
  8. Records an immutable log of the old state and new state in `public.workspace_audit_logs`.
  9. Privilege Contract:
     ```sql
     REVOKE ALL ON FUNCTION public.qualify_order(uuid, public.order_status, text) FROM PUBLIC;
     GRANT EXECUTE ON FUNCTION public.qualify_order(uuid, public.order_status, text) TO authenticated;
     ```

### E. Hardened Order Cancellation RPC: `cancel_order`
* **Signature**:
  ```sql
  public.cancel_order(
      p_order_id uuid,
      p_reason text DEFAULT null
  ) RETURNS public.order_requests
  ```
* **Internal Safeguards & Rules**:
  1. Must be declared as `SECURITY DEFINER` and enforce `SET search_path = ''`.
  2. Acquires row lock: `SELECT workspace_id, investor_profile_id, status INTO v_workspace_id, v_investor_profile_id, v_status FROM public.order_requests WHERE id = p_order_id FOR UPDATE;`.
  3. Resolves caller's application profile ID through `public.current_user_profile_id()`. A null resolved profile ID is denied immediately raising `profile_resolution_failed`. The resolved profile ID must not be accepted from caller parameters.
  4. Authorizes the action only if:
     - The locked order `investor_profile_id` equals the resolved current application profile ID; or
     - The caller has active advisor or workspace-owner membership in the order's workspace.
     
     **SQL-equivalent validation contract:**
     ```sql
     v_current_profile_id := public.current_user_profile_id();
     IF v_current_profile_id IS NULL THEN
         RAISE EXCEPTION 'profile_resolution_failed';
     END IF;

     IF v_investor_profile_id = v_current_profile_id THEN
         -- order owner cancellation path
     ELSIF public.has_advisor_membership(v_workspace_id) THEN
         -- advisor cancellation path
     ELSE
         RAISE EXCEPTION 'not_authorized';
     END IF;
     ```
  5. Denies cancellation rights for Family Guests, unrelated advisors, and Platform Admins (Platform Admin status alone does not satisfy cancellation authorization). Unauthorised attempts raise `not_authorized`.
  6. Permits cancellation only if the locked database status is `pending_qualification` or `pending_review`.
  7. Rejects cancellation attempts with `invalid_cancellation_state` if status is `auto_approved`, `approved`, or `rejected`.
  8. Rejects cancellation attempts with `already_cancelled` if status is `cancelled`. Repeated cancellation is strictly denied.
  9. Mutates status to `cancelled`, captures the reason, and writes an immutable audit record in `public.workspace_audit_logs` using database-loaded values inside the same transaction.
      
      *Note: The cancel_order function represents investor-owner cancellation or authorised MFD cancellation, subject to valid pending states and workspace authorization. Platform Admins and Family Guests have no order cancellation rights.*
  10. Privilege Contract:
      ```sql
      REVOKE ALL ON FUNCTION public.cancel_order(uuid, text) FROM PUBLIC;
      GRANT EXECUTE ON FUNCTION public.cancel_order(uuid, text) TO authenticated;
      ```

### F. Workspace-Matched Family Delegation Policy (Section 6.F)
* The accepted `family_delegations` record (with `consent_status = 'accepted'`, `is_active = TRUE`, and unexpired timestamp) is the single authoritative source of truth for family guest read access. No secondary workspace membership is required.
* **Identity Constraints**:
  - `owner_profile_id` references and stores `public.profiles.id` (not `auth.users.id`).
  - `delegate_profile_id` references and stores `public.profiles.id` (not `auth.users.id`).
  - Access is immediately denied if profile resolution returns null.
* **Granular Lifecycle & Mutation Rules**:
  - **Creation**: Allowed only for the portfolio owner or an authorised MFD-assisted workflow with recorded owner authority.
  - **Consent**: Only the proposed delegate may accept or reject a pending delegation.
  - **Revocation**: Allowed for the portfolio owner, the delegate revoking their own access, or an authorised MFD-assisted workflow with recorded owner authority.
  - **Platform Admin Support**: Platform Admins must not silently create or activate Family Access. Platform Admin intervention is allowed only through narrow, audited support RPCs for identity-link resolution, access restoration, or exceptional support cases. Every support action requires step-up authentication, a mandatory reason, a correlation ID, and follows the `override.attempted` to `override.succeeded` / `override.denied` / `override.failed` durable append-only audit lifecycle.
  - **Table Mutation Constraints**: Broad `FOR ALL` policies on `family_delegations` are strictly prohibited. The system must enforce explicit, role-segregated policies or lifecycle RPCs for creation, consent acceptance/rejection, and revocation. Direct table updates must not bypass lifecycle validation.
* **Document Access Boundary**:
  - Family Guest access to portfolio summaries does not grant access to `ingested_documents`, original CAS files, or signed document URLs. Access requires separate, explicit document-level consent.
  - Document-access policies must exclude Family Guests by default unless separate consent is explicitly recorded.
* Portfolios RLS matches workspace constraints:
  ```sql
  CREATE POLICY family_delegate_read_policy ON public.portfolios FOR SELECT TO authenticated
  USING (
      public.current_user_profile_id() IS NOT NULL
      AND EXISTS (
          SELECT 1 FROM public.family_delegations fd
          WHERE fd.owner_profile_id = portfolios.client_id
            AND fd.delegate_profile_id = public.current_user_profile_id()
            AND fd.workspace_id = portfolios.workspace_id
            AND fd.consent_status = 'accepted'
            AND fd.is_active = TRUE
            AND (fd.expires_at IS NULL OR fd.expires_at > now())
      )
  );
  ```

### G. Audited Platform Admin Override Contract (Section 6.G)
Platform Admin actions bypass standard table-level workspace restrictions under a strict, auditable governance model:

* **Identity Verification**:
  Verified using: `(auth.jwt() -> 'app_metadata' ->> 'user_role') = 'platform_admin'`.
* **Governance Safeguards & Audit Fields**:
  * Platform Admin overrides must never be a silent, unrestricted database or API bypass.
  * Every override request requires capturing the following aligned fields exactly:
    * `actor_profile_id` (Acting admin profile ID)
    * `actor_type` (Role/actor type, e.g. `platform_admin`)
    * `workspace_id` (Target workspace ID)
    * `entity_type` (Target entity type)
    * `entity_id` (Target entity ID)
    * `action` (Requested action)
    * `reason` (Mandatory human-entered business reason for override)
    * `correlation_id` (Stable identifier for the complete override attempt)
    * `event_type` (e.g. `override.attempted`, `override.succeeded`, `override.denied`, `override.failed`)
    * `outcome` (`attempted`, `succeeded`, `denied`, or `failed`)
    * `error_code` (Stable machine-readable failure/denial code, null for success)
    * `occurred_at` (Timestamp)
* **Append-Only Platform Admin Override Auditing**:
  * To guarantee that all attempts are audit-logged and cannot be bypassed via rollbacks, auditing uses a strictly append-only sequence (no records are ever updated or deleted):
    1. Verify Platform Admin role
    2. Verify step-up authentication
    3. Validate action-specific permission
    4. Validate mandatory reason
    5. Validate correlation ID
    6. Commit override.attempted in a separate transaction
    7. Invoke narrow mutation RPC
    8. Append override.succeeded, override.denied or override.failed
    9. Keep attempted event even if mutation rolls back
* **Prohibition of Broad Mutation Bypass**:
  * Generic Platform Admin `FOR ALL` policies on protected business tables are strictly prohibited.
  * Silent direct `UPDATE` or `DELETE` mutation access is prohibited.
  * Unrestricted cross-workspace extraction is prohibited.
  * Direct order approval, rejection, or qualification by Platform Admins is strictly prohibited.
  * Platform Admins must not qualify, approve, or reject order requests; Platform Admin status does not satisfy `qualify_order` authorization.
  * Audit-table mutations are prohibited.
  * Overrides are implemented strictly via narrow read-only policies where operationally necessary, and hardened `SECURITY DEFINER` RPCs (enforcing `SET search_path = ''` and fully qualified references) for mutations with explicit action-specific authorization, mandatory reason, correlation ID, step-up verification, and durable auditing.
* **Permitted Override Use Cases**:
  - Account unlock
  - Access reset
  - MFD onboarding assistance
  - Identity-link resolution
  - Emergency support intervention
  * Any future override action must be separately documented and auditable.

---

## 7. Edge Service Architectures & Ingestion Pipelines

### A. In-Memory Zero-Disk Ingestion Pipeline (BC-006 / FR-009 / BC-013 / P1-1)
```text
[IMAP/OAuth Connector] ➔ [Poll Mailbox] ➔ [Validate Sender & Attachment Hash] ➔ [MIME/Magic-Byte Check] ➔ [Malware Scan] ➔ [Encrypted Object Storage] ➔ [Memory Stream Parser] ➔ [Immutable Ingestion Log]
```
To guarantee zero-trust compliance, parser inputs are read from the secure encrypted object storage vault into memory buffers without local-disk persistence. DBF normalization is implemented in the Edge parser. The current PDF path validates only the synthetic characterization contract; live registrar statement normalization remains disabled pending sanitized fixtures and deterministic tests.
* **External Support Stack**: `services/ingestion-support/` supplies one containerized API plus an internal-only ClamAV daemon. The unchanged Edge worker calls separate authenticated mailbox, PDF extraction, and malware endpoints. Mailbox configuration is a base URL; PDF and malware configuration use full endpoint URLs.
* **Security & Credentials**: Mailbox credentials (OAuth tokens) are encrypted separately at rest. The support stack requires three distinct service bearer tokens, fixed HTTPS provider origins, bounded requests/responses/timeouts, a host allowlist, and sanitized errors. It accepts no direct IMAP password and logs no statement content or credentials.
* **Mailbox Backlog Bounds**: Gmail polling filters for PDF/DBF attachments, follows at most 4 pages and inspects at most 100 candidates by default, rejects malformed/repeated page tokens, and page-fairly returns at most 25 messages. Sender allowlist validation remains in the Edge worker.
* **PDF Extraction**: The service provides bounded in-memory extraction infrastructure plus deterministic CAMS/KFintech synthetic characterization layouts. These prove the Edge/service contract but do not enable live registrar CAS statement layouts. Each actual layout requires a sanitized non-production fixture and deterministic tests. Unknown, encrypted, image-only/OCR, malformed, or excessive layouts fail closed. DBF parsing remains in the Edge parser.
* **Malware Boundary**: The support API verifies the Edge-supplied SHA-256 before sending raw bytes to ClamAV with `INSTREAM`. The daemon port is not publicly exposed and readiness fails if the daemon/signature database is unavailable.
* **Deployment Boundary**: Local HTTP is restricted to loopback. Any hosted Dev deployment must use HTTPS and external secret management. Issue #109 makes no hosted Dev or Production changes.
* **Vaulting Controls**: The encrypted object storage vault enforces file-size limits (<20MB), MIME validation (PDF/DBF), malware screening, SHA-256 content-hash deduplication, and single-use signed URLs expiring in 15 minutes.
* **Retention Policy**: Retention is governed by configurable platform policy and applicable regulatory, contractual, and user-consent requirements. Automatic deletion shall not occur while a document is required for portfolio lineage, audit, active servicing, or legal retention. Temporary processing artefacts may be removed after 30 days, but original vault documents follow a separate compliance retention lifecycle.

---

## 8. Asynchronous Event Bus Topology & Transactional Outbox
Money Bowl features a Transactional Outbox Pattern to guarantee durable event dispatching:

```text
DB Transaction ➔ [Write Business Data + Write event_outbox] ➔ Commit ➔ Postgres Listener / Cron Dispatcher ➔ Deno Edge Workers
```

All domain events are written to the `event_outbox` table within the primary database transaction. A listener or background agent dispatches these to Deno Edge workers with exponential retry policies.

* **`order.created`**: Fired when a mapped investor or authorised Distributor creates an order request. Triggers the auto-approval engine.
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

## 11. Encrypted Document Vaulting & Signed URL Lineage (BC-011, BC-013)
* **Encryption**: CAS PDF statements are encrypted at the object boundary using AES-256 keys.
* **Access Control**: Users receive signed URLs with an expiry limit of 15 minutes. Decryption happens on-the-fly inside the Edge compute boundary.
* **Denial Invariant**: Family delegates are strictly denied access to `ingested_documents`, original CAS files, or signed document download URLs unless an explicit, separate document-level consent grant exists.

---

## 12. Secure Referral Security Contract
To protect user privacy and prevent tracking vulnerabilities, referrers are resolved under a strict security schema:
* Referral codes are random, high-entropy, cryptographically secure tokens.
* Plaintext token keys are visible only when required for sharing purposes.
* Hashed token values (`token_hash`) are stored on the database to verify matches.
* Pre-authentication onboarding uses server-issued 256-bit opaque claim tokens stored as SHA-256 hashes (`claim_token_hash`) with a server-enforced 24-hour security TTL (`expires_at`).
* Claim binding and conversion RPCs deterministically reject expired unconsumed claims with `referral_claim_expired`.
* Expired unconsumed claims are purged via a service-role-only batch cleanup RPC (`cleanup_expired_referral_onboarding_claims`) backed by a partial cleanup index `(expires_at) WHERE consumed_at IS NULL`; consumed conversion and reward provenance rows are strictly preserved for audit integrity.
* Deployment Prerequisite: Ingress rate-limiting / bot protection at the API gateway / Edge layer (e.g. Supabase Edge / Cloudflare WAF on `/rest/v1/rpc/create_referral_onboarding_claim`) is required to throttle anonymous claim creation.
* Referral attribution must never capture or store raw PAN or bank-account details.
* Fraud collision validation checks use deterministic SHA-256 HMAC lookups against unique client identifiers.
* Referral conversion and reward issuance workflows must be idempotent.
* Reward creation, reversals, and expirations write immutable audit tracks.

---

## 13. Dual Subscription & Feature Gating Engine (BC-009 / BR-011)
* **Tiers & State Machine**:
  - State Machine: `trialing` ➔ `active` ➔ `past_due` ➔ `suspended` ➔ `cancelled`.
  - Enforces feature entitlements, billing ownership, subscription lifecycle, and usage limits for both Distributor and Investor subscription tiers.
* **Distributor Starter limits**: Gated at 25 mapped clients. Upgrades require active checkout session confirmations.
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
* **Exploring Investor AI routing (BC-007)**: Exploring investors without a mapped MFD relationship route support queries to Platform Admin support or are prompted to establish an MFD relationship before tickets can be assigned.

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
Specifically, the platform enforces consent-backed Family Portfolio viewing with separate portfolio context switching; no merged holdings, returns or XIRR across Distributor relationships. The architecture strictly prohibits cross-workspace portfolio merging, consolidated XIRR across Distributors, merged return views, and concealment of individual Distributor performance, in strict preservation of BR-004.

### B. Global Identity Resolution (BR-001 / P1-3)
Single digital investor records use deterministic SHA-256 HMAC attributes inside profiles (`pan_hmac`, `normalised_phone_hmac`, `normalised_email_hmac`, and `identity_match_status`) to resolve matches.

### C. Comprehensive PII Classification & Encryption List (PII Security)
All sensitive attributes are classified and protected at rest and in transit:
* **Target List**: `Aadhaar number` (and Aadhaar-derived identifiers), `PAN`, `Bank Account Numbers`, `IFSC`, `Phone`, `Email`, `Date of Birth`, `Nominee Details`, `Statement Passwords`, and `Mailbox OAuth Credentials`.
* **Aadhaar Exclusion Rule**: Aadhaar is strictly excluded from general database search indexes or application log payloads, displaying strictly as masked projections.
* **Remediation Policy**: Encrypted using AES-256 keys managed by the Supabase Vault. Returns strictly server-authorized masked projections by default. Revealing sensitive information requires explicit step-up authentication and immutable audit logging to `pii.revealed` in the central audit queue.

### D. System-Wide Non-Functional Requirements (NFR-001 - NFR-005)
* **`NFR-001` (Data Security & Masking)**: Sensitive PII attributes encrypted at rest & masked by default; step-up MFA reveal.
* **`NFR-002` (Universal Search Latency)**: Search queries complete within 200 milliseconds.
* **`NFR-003` (Order Routing SLA)**: Submitted orders appear in MFD queue within 5 seconds.
* **`NFR-004` (Statement Processing SLA)**: Mailbag CAS attachments processed within 15 minutes.
* **`NFR-005` (Audit Lineage)**: Immutable, timestamped audit trails for all critical actions.

### E. Service Level Objectives (SLOs)
* **`ARCH-SLO-001`**: Security engine key validation overhead latency: `<50ms`.
* **`ARCH-SLO-002`**: Central log queue write confirmation: `<100ms` async acknowledgment.

### F. Expanded Audit Logging Architecture
The platform records immutable audit logs inside `public.workspace_audit_logs` (and `public.ingestion_logs` where relevant). Triggers block updates and deletions on audit tables.

* **Audit Scopes & Events Table**:

| Event / Action | Target Audit Fields | Location |
| :--- | :--- | :--- |
| **Order submission** | `actor_profile_id`, `investor_profile_id`, `initiated_by_role`, `initiation_channel`, `workspace_id`, `entity_id`, `occurred_at` | `workspace_audit_logs` |
| **Outbox event generation** | `entity_id`, `event_type`, `payload`, `occurred_at` | `event_outbox` |
| **Auto-approval evaluation** | `rule_id`, `rule_version`, `entity_id`, `correlation_id` | `workspace_audit_logs` |
| **Auto-approval match** | `rule_id`, `rule_version`, `entity_id`, `new_state` | `workspace_audit_logs` |
| **Auto-approval fallback** | `entity_id`, `rule_id`, `rule_version`, `new_state` | `workspace_audit_logs` |
| **Manual approval** | `actor_profile_id`, `investor_profile_id`, `initiated_by_profile_id`, `reviewed_by_profile_id`, `previous_state`, `new_state`, `occurred_at` | `workspace_audit_logs` |
| **Manual rejection** | `actor_profile_id`, `investor_profile_id`, `initiated_by_profile_id`, `reviewed_by_profile_id`, `previous_state`, `new_state`, `reason`, `occurred_at` | `workspace_audit_logs` |
| **Order cancellation** | `actor_profile_id`, `entity_id`, `previous_state`, `new_state`, `reason` | `workspace_audit_logs` |
| **Auto-approval rule creation** | `actor_profile_id`, `entity_id` (`rule_id`), `new_state` | `workspace_audit_logs` |
| **Auto-approval rule modification** | `actor_profile_id`, `entity_id` (`rule_id`), `previous_state`, `new_state` | `workspace_audit_logs` |
| **Family delegation creation** | `actor_profile_id`, `entity_id`, `new_state` | `workspace_audit_logs` |
| **Family consent acceptance** | `actor_profile_id`, `entity_id`, `previous_state`, `new_state` | `workspace_audit_logs` |
| **Family delegation revocation** | `actor_profile_id`, `entity_id`, `previous_state`, `new_state` | `workspace_audit_logs` |
| **Family delegation expiration** | `entity_id`, `previous_state`, `new_state` | `workspace_audit_logs` |
| **Platform Admin override** | `actor_profile_id`, `actor_type`, `workspace_id`, `entity_type`, `entity_id`, `action`, `reason`, `correlation_id`, `event_type`, `outcome`, `error_code`, `occurred_at` | `workspace_audit_logs` |
| **Access reset** | `actor_profile_id`, `workspace_id`, `action` | `workspace_audit_logs` |
| **Original CAS access** | `actor_profile_id`, `entity_id` (document), `action` | `workspace_audit_logs` |
| **Original CAS download** | `actor_profile_id`, `entity_id` (document), `action` | `workspace_audit_logs` |
| **Ingestion start** | `workspace_id`, `entity_id` (log), `action` | `ingestion_logs` |
| **Ingestion completion** | `workspace_id`, `entity_id` (log), `action` | `ingestion_logs` |
| **Ingestion failure** | `workspace_id`, `entity_id` (log), `action`, `reason` | `ingestion_logs` |

*Note: initiated_by_profile_id and reviewed_by_profile_id may be equal for an authorised MFD-side workflow.*

---

## 18. Many-to-Many Traceability Matrix

| Business Capability | Mapping Personas | BRD Requirements | BRD Rules | Non-Functional Requirements | Postgres Entities & Component Links |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **BC-001** (Identity) | Platform Admin, Distributor, Mapped Investor, Exploring Investor | `FR-002`, `FR-003`, `FR-004` | `BR-001`, `BR-007`, `BR-008` | `NFR-001` | `profiles`, `workspace_memberships` |
| **BC-002** (Distributor) | Distributor | `FR-001` | N/A | N/A | `mfd_profiles`, `mfd_onboarding_reviews` |
| **BC-003** (Investor) | Investor | `FR-002` | `BR-001` | N/A | `profiles` |
| **BC-004** (Relationship) | Investor, Distributor | `FR-005`, `FR-006` | `BR-002`, `BR-003`, `BR-004`, `BR-009` | `NFR-003` | `workspace_memberships`, `family_delegations` |
| **BC-005** (Portfolio & Order Execution) | Investor, Distributor | `FR-005`, `FR-006` | `BR-004`, `BR-005`, `BR-006` | `NFR-003`, `NFR-005` | `portfolios`, `folios`, `scheme_holdings`, `transactions`, `order_requests`, `auto_approval_rules`, `qualify_order`, `cancel_order`, `apply_auto_approval_decision`, `event_outbox` |
| **BC-006** (Ingestion) | Distributor | `FR-009` | `BR-003` (Secondary check) | `NFR-004` | `cams-kfintech-ingestion` Edge function, `transactions`, `folios` |
| **BC-007** (Educational AI) | Distributor, Mapped Investor, Exploring Investor, Family Guest (read-only), Platform Admin (testing) | `FR-012`, `FR-013`, `FR-014` | `BR-010` | N/A | `ai-helper` Edge worker, declination guard gate |
| **BC-008** (Ticketing) | Investor, Distributor | `FR-014` | N/A | N/A | `support_tickets` |
| **BC-009** (Subscriptions) | Distributor, Mapped Investor, Exploring Investor | `FR-010` | `BR-011` | N/A | `subscription_plans`, `workspace_billing`, `investor_subscriptions`, `payment_events`, `plan_entitlements` |
| **BC-010** (Platform Admin) | Platform Admin | `FR-003` | `BR-007` | `NFR-005` | `platform_admin_read_policies`, `platform_admin_override_rpcs`, `workspace_audit_logs` |
| **BC-011** (Lineage) | None | N/A | Auditability Principle | `NFR-005` | `ingestion_logs` (Immutable) |
| **BC-012** (Notifications) | Investor, Distributor | FR-014 plus BC-triggered events | BR-009 (family consent notifications) | N/A | `notifications`, `notification_retry_queue` |
| **BC-013** (Vaulting) | Investor, Distributor | `FR-009` | `BR-008` | `NFR-001` | `ingested_documents`, AES-256 encrypted object storage vault |
| **BC-014** (Analytics) | Distributor | N/A | `BR-004` (Enforced separation) | N/A | `mfd_dashboard_metrics` view |
| **BC-015** (Search) | Investor, Distributor | `FR-007` | N/A | `NFR-002` | GIN search index projections, `searchable_tools` |
| **BC-016** (Platform Config) | Platform Admin | N/A | BR-006, BR-010, BR-012 | N/A | platform_settings, feature_flags, notification_templates, registrar_configs, ai_guardrail_versions (Design Principle: "Configuration over Customisation") |
| **BC-017** (AMFI Scheme Factsheets & Market Data) | Investor, Distributor | `FR-008` | `BR-012` | N/A | `amfi_factsheets` table, `amfi-nav-worker` cron Edge function |
| **BC-018** (Referral Engine) | Investor | `FR-011` | Product Design Principle #5 | N/A | `investor_referrals`, `referral_conversions`, `referral_rewards` |

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
