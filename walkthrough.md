# Verification & Progress Walkthrough

## 1. Accomplished Features & Updates

### 1.1 Autocomplete Search for Mutual Funds
* **Search & Suggestions**: Added an autocomplete search bar on the Client Dashboard allowing clients to type fund names or scheme codes.
* **Factsheet Dialog**: Clicking a search suggestion displays the full interactive factsheet modal.

### 1.2 Personalised Time-of-Day Greetings
* **AppBar Title Display**: Shows greetings (e.g., `"Good Morning, Hariom"`) directly in the AppBar.
* **No Subtitles**: Completely removed `"Client Console"` and any subtitles from the header body.
* **Greeting Rules**:
  * `03:00 - 11:59`: Good Morning
  * `12:00 - 15:59`: Good Afternoon
  * `16:00 - 23:59`: Good Evening
  * `00:00 - 02:59`: Good Night

### 1.3 Rupee Rain Background (Visual Accent)
* **Performance Particle System**: Implemented a falling Rupee (`₹`) animation using high-performance Flutter CustomPainter.
* **getSubtle Accents**: Soft orange themed particles drift downward, adding visual delight.

### 1.4 Password-Protected ZIP & DBF Ingestion Pipeline
* **Decryption support**: Leverages Deno `npm:@zip.js/zip.js` library to extract password-protected zip archives using the password specified in `RTA_DECRYPTION_PASSWORD` or fallback `"cams123"`.
* **Binary DBF Reader**: Decodes standard dBASE III database files (`.dbf`) into structured JavaScript objects.
* **Schema Validation**: Unified validator checks columns (PAN, Folio, Units, Amount, Date, etc.) for database constraints.

### 1.5 Unregistered Client Ingestion & Auto-Linking
* **Unregistered Ingestion**: Automatically creates profile records in the `profiles` table using the name and PAN from the statement.
* **Auto-Linking Trigger**: Updated the `handle_new_user()` trigger. When a new user registers on the app via email/mobile/PAN, it auto-links their profile, instantly populating their portfolio.
### 1.7 In-Memory Batch ZIP Invoice Signer
* **Dual Format Support**: The Invoice Signer tab handles both single `.pdf` files and zipped `.zip` file archives containing multiple PDFs.
* **In-Memory ZIP Processing**: Extends Deno Edge Function to dynamically extract PDF entries from ZIP archives in-memory, sign/stamp them with configurable placement offsets, compress them back to a new ZIP archive, and return the zipped binary.
* **Auto Cache-Busting**: Added cache unregistration to `index.html` to prevent Safari and Chrome from serving cached Service Worker builds.

### 1.8 CAMS Invoice Signer Processing Boundary
* **Shared processing**: ZIP decryption, PDF signing/stamping, repackaging,
  naming, and downloads are coordinated by the Invoice Signer job controller.
* **CAMS-only registrar implementation**: CAMS metadata extraction and tracker
  updates are isolated without changing dashboard controls, Edge Function
  payloads, or output behavior.
* **Fixture gate**: Real redacted CAMS tracker/PDF fixtures are required before
  characterization assertions can be enabled.

### 1.9 CAMS Excel 97-2003 and Open XML Trackers
* **Format-preserving web updates**: CAMS tracker updates now retain the
  selected workbook format: `.xls` writes BIFF8 and `.xlsx` writes Open XML.
* **Unchanged CAMS matching**: The existing `CAMS INVOICE NUMBER` to PDF file
  name matching, duplicate ordering, unmatched handling, and `FILE NAME`
  updates share one SheetJS processing loop for both formats.

---

## 2. Database Migration Deployment Instructions

To apply the schema changes and update RLS policies, execute the SQL migration scripts in order:

### Migration 1: Unregistered Clients & Auto-Linking
1. Copy the SQL commands from **[20260718000001_unregistered_clients.sql](file:///Users/lalahariomsharan/Documents/Mutual_Fund_Portfolio_App/supabase/migrations/20260718000001_unregistered_clients.sql)**.
2. Run them in your **[Supabase Dashboard SQL Editor](https://supabase.com/dashboard/project/auxbbotbcvrgzvynyrgg/sql/new)**.

### Migration 2: CAMS WBR9 Staging Table
1. Copy the SQL commands from **[20260718000002_cams_statements_schema.sql](file:///Users/lalahariomsharan/Documents/Mutual_Fund_Portfolio_App/supabase/migrations/20260718000002_cams_statements_schema.sql)**.
2. Run them in your **[Supabase Dashboard SQL Editor](https://supabase.com/dashboard/project/auxbbotbcvrgzvynyrgg/sql/new)**.

---

## 3. Verification Logs

### Deno Ingestion & Parser Tests
Deno tests verify unzipping and binary DBF parsing functionality:

```bash
deno test --allow-all supabase/functions/cams-kfintech-ingestion/parser_test.ts
```

**Output**:
```text
Check supabase/functions/cams-kfintech-ingestion/parser_test.ts
running 1 test from ./supabase/functions/cams-kfintech-ingestion/parser_test.ts
RTA Ingestion Ingests Password-Protected ZIP containing DBF Statement ...
------- output -------
Unzipping password-protected archive: 17072026065215_208650458R9.zip
Extracting file: 17072026065215_208650458R9.dbf
Parsing DBF database structure: 17072026065215_208650458R9.dbf
Successfully extracted 1 records from DBF.
----- output end -----
RTA Ingestion Ingests Password-Protected ZIP containing DBF Statement ... ok (25ms)

ok | 1 passed | 0 failed (28ms)
```

---

## 4. Deployment Status

Edge functions successfully deployed to Supabase project `auxbbotbcvrgzvynyrgg`:
```json
{
  "project_ref": "auxbbotbcvrgzvynyrgg",
  "functions": ["cams-kfintech-ingestion", "sign-stamp-invoice"],
  "dashboard_url": "https://supabase.com/dashboard/project/auxbbotbcvrgzvynyrgg/functions",
  "message": "Deployed Functions."
}
```

---

## 5. Phase 2 Documentation Modernization (2026-07-25)

Successfully completed the Phase 2 documentation modernization program. Replaced root default files, updated roadmap, consolidated changelog entries, standardized ADRs, resolved architectural duplications, and cleaned up AI guidelines.

* **README.md**: Transformed from default Flutter project description to a professional enterprise repository landing page.
* **CHANGELOG.md**: Consolidated release history through v1.1.0-alpha inside the main CHANGELOG.md file.
* **ROADMAP.md**: Updated release milestones to v1.1.0-alpha, highlighting recent and future sprint targets.
* **docs/AI_HANDOFF.md**: Removed coding standard duplications and added setup, validation, and handoff checklists.
* **docs/decisions/README.md**: Updated ADR-006 status to Accepted and indexed the in-memory ZIP processing ADR.
## 7. Sprint 6.1 Hardening & Compliance Pass (2026-07-27)

Successfully resolved all database and contract validation gaps for Sprint 6.1 through the corrective database migration `20260801000001_sprint_6_1_canonical_hardening.sql`. Verified all components using local unit and widget test suites.

### 7.1 Key Database Changes & Hardening
* **Helper Correction**: Hardened `has_active_workspace_membership`, `has_advisor_membership`, and `has_investor_membership` to map to `public.current_user_profile_id()` instead of `auth.uid()`, with security definer search-path isolation.
* **Billing Trigger Safety**: Fixed the `sync_billing_workspace_limit` trigger function to handle `DELETE` operations cleanly (avoiding null pointer exceptions on `NEW` variable access by using `TG_OP` conditionals) and query for the canonical `'investor'` role instead of `'client'`.
* **Idempotency Correlation**: Added `auto_approval_correlation_id uuid` column to `public.order_requests` with a unique partial index to guarantee event-bound idempotency mapping.
* **Auto-Approval Service RPC**: Implemented the canonical `apply_auto_approval_decision(p_order_id, p_decision, p_rule_id, p_rule_version, p_correlation_id)` with step-by-step row locking, replay checks, stale-state checks, outbox event matching, and conditional rule validation.
* **Order Qualification RPC**: Aligned `qualify_order` with the strict advisor-only validation rules, denying Platform Admin overrides, and restricting manual decisions strictly to pending review states.
* **Order Cancellation RPC**: Aligned `cancel_order` with profile-resolved caller validation, restricting status checks, and preventing duplicate cancellations via explicit `already_cancelled` exceptions.
* **Outbox Mapping**: Extended the `event_outbox` table with `entity_id`, `entity_type`, `claimed_at`, and `claimed_by` columns. Aligned the triggers to populate these fields and prevent duplicate `order.created` outbox events.
* **Dual Billing Model**: Added `investor_subscriptions` plan mapping and implemented the `payment_events_billing_owner_xor` constraint to support exactly one billing owner.
* **Family Access consenting**: Created `delegate_consent_accept`, `delegate_consent_reject`, and `delegate_consent_revoke` RPCs supporting consent transition logging and audit entries.
* **Platform Admin Override RPCs**: Added action-specific `override_account_unlock` and `override_access_reset` RPCs with append-only succeeded overrides audit logging.

### 7.2 Verification Logs
* **Database Hardening Test Suite**: Created a regression test suite `supabase/tests/sprint_6_1_hardening_test.sql` to verify profile mappings, cancel validations, qualification constraints, auto-approval replays, family delegations, billing XOR checks, referrals, and audit immutability.
* **Flutter Test Suite Results**: Resolved the widget-test time-dependent failures in `test/user_management_workspace_models_test.dart` and RenderFlex layout overflows in `test/portfolio/client_dashboard_test.dart`.
```text
00:03 +126: /Users/lalahariomsharan/Documents/Mutual_Fund_Portfolio_App/test/authentication/route_guard_test.dart: RouteGuard Tests resolves to AccountAccessErrorScreen if investor tries to access advisor dashboard
00:03 +127: /Users/lalahariomsharan/Documents/Mutual_Fund_Portfolio_App/test/investor_verification_models_test.dart: only open verification states can be cancelled
00:03 +128: All tests passed!
```

---

## 6. Phase 3 Product Documentation (2026-07-25)

Successfully completed the Phase 3 product documentation program. Created comprehensive business-centric documentation inside `docs/product/` without modifying code or schema files.

* **docs/product/README.md**: Serves as the landing page indexing the product documentation library.
* **product-vision.md**: Articulates mission, core problem statements, target audiences, and success goals.
* **personas.md**: Profiles Investor, Advisor, Admin/Ops, and future Compliance/RM user personas.
* **domain-model.md**: Maps out entity representations (AMC, Scheme, Folio, Transactions, Holdings) with a Mermaid class diagram.
* **business-capabilities.md**: Breaks down functional capabilities (Auth, Portfolios, Signer, Ingestion).
* **user-journeys.md**: Visualizes business workflows (Onboarding, Ingestion, Folio Claims, Signer) using Mermaid flow charts.
* **glossary.md**: Defines key terms like XIRR, AUM, NAV, RTA Mailbacks, CAMS, and KFintech.
* **feature-catalog.md**: Inventories implemented, in-progress, planned, and future product capabilities.
* **non-functional-requirements.md**: Specifies core performance, security compliance, availability, and scale targets.


