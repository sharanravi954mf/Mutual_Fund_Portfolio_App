# Money Bowl — Synthesized System Architecture Specification
Document Version: v1.2.1 Canonical Synthesized Baseline  
Target Repository Path: docs/architecture/SYSTEM_ARCHITECTURE.md  
BRD Alignment: docs/business/BRD.md (v1.2.1)  

## 1. System Topology & Data Flow Boundaries
Money Bowl uses an Event-Driven Serverless Architecture structured into four distinct execution zones:

┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                SYSTEM TOPOLOGY MATRIX                                  │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│ 1. CLIENT ZONE (Flutter Mobile & Web App)                                               │
│    • Clean Architecture (Data ➔ Domain ➔ Presentation via BLoC)                        │
│    • Dynamic Client-Side PII Masking Engine (`FR-011`)                                  │
│                                                                                         │
│ 2. IDENTITY & SECURITY ZONE (Supabase Auth & JWT Engine)                                │
│    • Mobile/Email OTP Auth ➔ Emits JWT with Claims:                                     │
│      { "workspace_id": "UUID", "user_role": "mfd|investor|delegate", "tier": "pro" }    │
│                                                                                         │
│ 3. PERSISTENCE LAYER ZONE (PostgreSQL 15+ with Row Level Security)                       │
│    • Multi-Tenant Data Isolation enforced via RLS Kernel Policies                       │
│    • Foreign Key Constraints, Table Schemes, and State Enums                            │
│                                                                                         │
│ 4. SERVERLESS COMPUTE EDGE ZONE (Deno Edge Functions)                                   │
│    • Mailbag Stream Decoder Engine (`cams-kfintech-ingestion`)                │
│    • Order Qualification Engine (`order-processor`)                           │
│    • Market Data Sync (`amfi-nav-worker`)                                     │
└─────────────────────────────────────────────────────────────────────────────────────────┘

## 2. Synthesized Database Domain Schema & Relationships
The database architecture maps directly to BRD v1.2.1 Entities (BE-001 through BE-012).

### Key Enums & States
* `user_role`: mfd, investor, family_delegate
* `order_type`: buy, sell, switch
* `order_status`: pending_qualification, auto_approved, approved, rejected, submitted_to_exchange
* `ingestion_status`: received, parsing, processed, failed

### Core Tables & Foreign Key Graph

           ┌────────────────┐
           │   workspaces   │ (BE-003) Multi-tenant MFD Practice
           └───────┬────────┘
                   │ 1:N
                   ▼
┌──────────────────┴───────────────┐
│        master_investors          │ (BE-001) Primary Client Profiles
└──────────┬────────────────┬──────┘
           │ 1:N            │ 1:N
           ▼                ▼
┌──────────┴───────┐  ┌─────┴──────────────┐
│  order_requests  │  │ family_delegations │
│     (BE-012)     │  │     (BE-005)       │
└──────────────────┘  └────────────────────┘

### Detailed Table Specifications

#### `workspaces` (BE-003)
Stores MFD practice details, subscription status, and threshold rules:
* **Attributes**: `id` (UUID), `arn_code` (TEXT), `auto_approval_enabled` (BOOL), `auto_approval_max_amount` (NUMERIC), `subscription_tier` (TEXT).

#### `master_investors` (BE-001)
Core investor entity tied to a tenant:
* **Attributes**: `id` (UUID), `workspace_id` (FK), `pan_hash` (TEXT), `full_name` (TEXT), `email` (TEXT), `phone` (TEXT), `bank_details` (JSONB).

#### `order_requests` (BE-012)
Transaction initiation logs:
* **Attributes**: `id` (UUID), `workspace_id` (FK), `investor_id` (FK), `scheme_code` (TEXT), `type` (order_type), `amount` (NUMERIC), `units` (NUMERIC), `status` (order_status), `auto_approved` (BOOL).

#### `family_delegations` (BE-005)
Asymmetric read-only sharing rules:
* **Attributes**: `id` (UUID), `owner_investor_id` (FK), `delegate_investor_id` (FK), `access_level` (TEXT: read_only), `is_active` (BOOL).

## 3. Concrete Row Level Security (RLS) Mechanics
Instead of generic rules, the persistence layer uses specific PostgreSQL policies to guarantee Workspace Isolation (BR-003):

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

## 4. Edge Service Architectures & Pipelines

### A. In-Memory Zero-Disk Mailbag Parser (BC-006)
* **Trigger**: Supabase Storage Event / Mailbag Webhook.
* **Pipeline**:
  1. Stream incoming CAMS/KFintech WBR2 / WBR22 DBF or CAS PDF binary feed into Deno Edge RAM Buffer.
  2. Parse binary records using stream decoders (No disk writes to ensure zero-trust compliance).
  3. Upsert holdings into folios and transactions tables within a single Postgres transaction.

### B. Transaction Qualification & Auto-Approval Engine (BR-006)
* **Trigger**: HTTP POST RPC to `/functions/v1/order-processor` on order creation.
* **Logic Execution Flow**:
```text
   Investor Submits Order Request
                │
                ▼
  [Check Workspace Rules in DB]
                │
   Is auto_approval_enabled == TRUE?
         ├── NO  ──► Set status = 'pending_qualification' (Alert MFD Queue)
         └── YES ──► Is amount <= auto_approval_max_amount?
                        ├── NO  ──► Set status = 'pending_qualification'
                        └── YES ──► Set status = 'auto_approved' & auto_approved = TRUE
```

## 5. Non-Functional Criteria & Security Architecture
* **Performance SLA**: Order qualification evaluation completes under 150ms at the Edge.
* **Data Masking (BR-011)**: Client layer masks PAN (XXXXX1234X) and Mobile numbers (XXXXXX8901) dynamically unless explicit MFD auth context is granted.
* **Auditability**: All order state transitions insert an immutable tracking record into `order_audit_logs`.
