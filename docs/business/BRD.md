# Money Bowl (Codename) — Business Requirements Document (BRD)
Document Version: v1.2.1 (Final Approved Baseline)  
Product Category: AI-Powered Mutual Fund Relationship & Execution Platform  
Target Repository Path: docs/business/BRD.md  
Status: Canonical Bible — Frozen for Technical Architecture & Implementation  

## 1. Product Vision & Executive Summary
Money Bowl (Codename) is an AI-powered Mutual Fund Relationship & Execution Management Platform that enables distributors and investors to manage, understand, service, explore, and transact mutual fund portfolios through intelligent automation, secure collaboration, AMFI scheme intelligence, and educational AI assistance.  

Money Bowl operates on a B2B2C and B2C hybrid platform model:
* **For Mutual Fund Distributors (MFDs/Advisors - B2B)**: It acts as an enterprise digital back-office, CRM, and order qualification engine. It automatically ingests Consolidated Account Statement (CAS) streams from mailbags (CAMS & KFintech), tracks AUM, and provides an approval queue for client Buy/Sell/Switch orders.  
* **For Mapped Investors (B2B2C)**: It provides a zero-touch portal to view isolated portfolios per distributor, initiate transaction requests (subject to distributor approval or auto-approval rules), access scheme factsheets, learn financial concepts via educational AI, and manage consent-backed family visibility.  
* **For Exploring Investors (Standalone B2C)**: It provides a friction-free entry point for standalone investors joining independently to explore schemes via AMFI factsheets, run investment calculators, experience the AI companion, and refer friends before linking with an MFD.  

## 2. Product Design Principles (The Constitution)
Every architectural design, database schema migration, API contract, and AI prompt context must adhere strictly to these 9 non-negotiable principles:  

┌───────────────────────────────────────────────────────────────────────────┐
│                      PRODUCT DESIGN PRINCIPLES                            │
├────────────────────────────┬──────────────────────────────────────────────┤
│ 1. Investor First          │ Investor owns financial data 100%.          │
│ 2. Distributor Empowerment │ Platform exists to help MFDs scale & service.│
│ 3. AI with Responsibility  │ AI educates & calculates; never advises.     │
│ 4. Relationship Isolation  │ Every MFD-investor link is isolated.         │
│ 5. Trust & Transparency    │ Every significant action is auditable.       │
│ 6. Extensible by Design    │ Pluggable integrations (channels/parsers).   │
│ 7. Mobile-First Experience │ Native experience across Web, Android, PWA.  │
│ 8. Configuration > Custom. │ Prefer configurable rules over custom builds.│
│ 9. Business > Technology   │ Value to users drives technical design.      │
└────────────────────────────┴──────────────────────────────────────────────┘

* **Investor First (Data Supremacy)**: The investor is the sole legal owner of their financial asset data. Money Bowl acts purely as a fiduciary custodian and processor.  
* **Distributor Empowerment & Control**: Digitizes client servicing and grants distributors full qualification control over client transactions via manual approval queues or auto-approval rules.  
* **AI with Responsibility**: AI is strictly an educational tool and calculation engine. It must never recommend funds, advise on portfolio changes, or replace licensed advisors.  
* **Relationship Isolation**: Every distributor-investor relationship is isolated. No distributor can ever view, query, or hijack another distributor's client relationships.  
* **Trust & Transparency (Auditability)**: Every order approval, administrative override, family consent grant, and ingestion run generates an immutable audit log.  
* **Extensible by Design**: External touchpoints (communication channels, execution gateways, statement parsers) are built as pluggable modules.  
* **Mobile-First Experience**: Core servicing, viewing, and factsheet navigation must render seamlessly across Web, Android, and iOS PWA clients.  
* **Configuration over Customization**: Platform behaviors (auto-approval thresholds, tier limits, supported registrars) are driven by configurable system settings.  
* **Business Intent Precedes Technology**: Product value and business rules dictate architectural choices, never technical convenience.  

## 3. Monetization Engine: Dual Subscription & Referral Model
Money Bowl implements a multi-tier commercial strategy serving both B2B and B2C segments:

                               ┌─────────────────────────┐
                               │   MONEY BOWL PLATFORM   │
                               └────────────┬────────────┘
                                            │
                ┌───────────────────────────┴───────────────────────────┐
                ▼                                                       ▼
  ┌───────────────────────────┐                           ┌───────────────────────────┐
  │  DISTRIBUTOR SUBSCRIPTION │                           │   INVESTOR SUBSCRIPTION   │
  ├───────────────────────────┤                           ├───────────────────────────┤
  │ • Free Tier (Limited AUM) │                           │ • Free Exploring Tier     │
  │ • Pro MFD Tier            │                           │ • Premium Investor Tier   │
  │ • Enterprise Agency Tier  │                           │   (Family Hub & Analytics)│
  └───────────────────────────┘                           └───────────────────────────┘

### 3.1 Dual Subscription Structure
**Distributor (MFD) Tiers**:
* *Free / Starter Tier*: Free onboarding up to 25 active investors / limited AUM processing.
* *Pro MFD Tier*: Unlimited mailbag statement ingestion, automated order approval engine, white-label UI branding, and advanced client CRM.
* *Enterprise / Firm Tier*: Multi-advisor EUIN management, advanced analytics, and custom support SLAs.

**Investor Tiers**:
* *Free Exploring Tier*: Single distributor portfolio view, public scheme search & factsheet navigation, basic AI companion access, and referral privileges.
* *Premium Investor Tier*: Multi-advisor portfolio flipping, consent-backed Family Portfolio aggregation, advanced capital gains/tax projections, and priority support routing.

### 3.2 Referral & Viral Growth Engine
* **Investor Referral System**: Every registered investor receives a unique referral code/link.
* **Viral Onboarding**: Exploring investors can share referral links via WhatsApp/SMS/Email to invite friends and family to join Money Bowl for portfolio tracking and scheme exploration.
* **Incentive Model**: Successful referrals grant temporary access to Premium Investor features (e.g., free 30-day Family Hub trial) for both the referrer and referee.

## 4. Master Roles & Permissions Matrix
| Platform Action / Capability | Platform Admin | Distributor (MFD) | Mapped Investor | Exploring Investor | Family Guest |
| :--- | :--- | :--- | :--- | :--- | :--- |
| Approve / Reject MFD Onboarding | ✅ Yes | ❌ No | ❌ No | ❌ No | ❌ No |
| Supersede / Override Account Access | ✅ Yes | ❌ No | ❌ No | ❌ No | ❌ No |
| Manage Subscription Plans & Billing | ✅ Yes | ✅ Own Plan | ✅ Own Plan | ✅ Upgrade | ❌ No |
| Configure Mailbag Connection (IMAP) | ❌ No | ✅ Own Mailbox | ❌ No | ❌ No | ❌ No |
| View MFD Dashboard & Order Queue | ❌ No | ✅ Own Book | ❌ No | ❌ No | ❌ No |
| View Mapped Client Portfolios | ❌ No | ✅ Own Clients | ✅ Own View | ❌ No | ✅ Delegated |
| Initiate Buy / Sell / Switch Orders | ❌ No | ✅ Yes — for own actively mapped investors | ✅ Yes — within active mapped relationship | ❌ No | ❌ No |
| Approve / Qualify Order Requests | ❌ No | ✅ Assigned | ❌ No | ❌ No | ❌ No |
| Configure Auto-Approval Rules | ❌ No | ✅ Own Workspace | ❌ No | ❌ No | ❌ No |
| Navigate Scheme Factsheets (AMFI) | ✅ Yes | ✅ Yes | ✅ Yes | ✅ Yes | ✅ Yes |
| Global App Search & Discovery Bar | ✅ Yes | ✅ Yes | ✅ Yes | ✅ Yes | ✅ Yes |
| Generate & Share Referral Links | ❌ No | ❌ No | ✅ Yes | ✅ Yes | ❌ No |
| Grant / Revoke Family Access | ✅ Audited support intervention only | ✅ Assisted | ✅ Owner | ❌ No | ❌ No |
| Interact with Educational AI | ✅ Testing | ✅ Yes | ✅ Yes | ✅ Yes | ✅ Read-Only |

## 5. Business Capabilities Taxonomy (BC-001 – BC-018)
* **BC-001 Identity & Access Management**: Secure multi-role authentication (Admin, Advisor, Investor), session management, and password recovery.  
* **BC-002 Distributor Lifecycle Management**: MFD self-registration, ARN/certificate upload, Admin review, approval/rejection, and subscription activation.  
* **BC-003 Investor Lifecycle Management**: Single logical digital identity management for mapped and exploring standalone investors.  
* **BC-004 Relationship Management**: Binding investors to distributors, enforcing relationship isolation, and enabling relationship context switching.  
* **BC-005 Portfolio Management**: Presenting scheme holdings, transactions, current NAV, returns (XIRR, absolute gains), and capital gains per relationship.  
* **BC-006 Registrar Data Ingestion**: Background IMAP mailbag polling, PDF/CAS statement extraction, and parser normalization (CAMS / KFintech).  
* **BC-007 Educational AI Assistance**: AI companion providing financial jargon decoding, portfolio mechanics explanations, static calculators, and ticket handoff.  
* **BC-008 Customer Servicing (Ticketing)**: Servicing desk allowing investors to raise queries routed directly to their assigned distributor's queue.  
* **BC-009 Dual Subscription & Billing**: Commercial tier management for both Distributors and Investors, feature gating, and usage limit enforcement.  
* **BC-010 Platform Governance & Administration**: Operational controls for user approvals, global system settings, security logging, and administrative overrides.  
* **BC-011 Document Management (Lineage)**: Managing file storage, processing status, error logs, and audit lineage from raw imported statements.  
* **BC-012 Actionable Notification Management**: Delivering high-value event alerts (ticket updates, family access requests, mailbox health) across channels.  
* **BC-013 Document Storage & Vaulting**: Secure PDF/CAS statement vault allowing mapped investors and MFDs to view and download original files.  
* **BC-014 Distributor Analytics Dashboard**: MFD command center rendering Total AUM, active clients, pending tickets, SIP summaries, and ingestion health.  
* **BC-015 Universal Search & Discovery Engine**: Top global search component allowing fast query navigation across schemes, folios, transactions, documents, tools, and tickets.  
* **BC-016 Platform Configuration**: System-wide configuration for supported registrars, AI guardrails, notification templates, and feature flags.  
* **BC-017 AMFI Scheme Factsheets & Market Data**: Detailed mutual fund factsheet module backed by PostgreSQL tables and free public APIs from AMFI.
* **BC-018 Investor Referral Engine**: Viral invitation system allowing investors to invite peers via unique links, tracking referral conversions and awarding plan benefits.  

## 6. Business Entities (BE-001 – BE-017)
* **BE-001 Platform Administrator**: Internal user governing MFD approvals and system overrides.  
* **BE-002 Distributor (Advisor / MFD)**: B2B customer identified by an AMFI ARN number.  
* **BE-003 Investor**: End-user holding mutual fund assets or exploring the platform; maintains one master identity record.  
* **BE-004 Distributor Relationship**: Core business boundary connecting one Investor to one Distributor.  
* **BE-005 Family Access Delegation**: Consent-backed, read-only, non-reciprocal link granting one investor visibility into another's portfolio.  
* **BE-006 Portfolio**: Aggregated holdings, valuation, and performance metrics belonging to an investor within a specific distributor relationship.  
* **BE-007 Folio**: Registrar-issued account identifier grouping investments under an AMC.  
* **BE-008 Scheme Holding**: Investor position in a specific scheme within a Folio.  
* **BE-009 Transaction**: Immutable historical financial event recorded within a Folio.  
* **BE-010 Registrar Statement**: Source document (PDF, CAS) received from registrars.  
* **BE-011 Registrar**: External organization (CAMS, KFintech) maintaining official mutual fund records.  
* **BE-012 Subscription Plan**: Commercial agreement dictating feature access and limits for MFDs or Investors.  
* **BE-013 Support Ticket**: Tracked service request raised by an investor and routed to their mapped distributor.  
* **BE-014 AI Assistant**: Educational digital companion providing jargon decoding, mechanics explanations, and calculators.  
* **BE-015 AMFI Scheme Factsheet**: Official scheme profile stored locally in PostgreSQL tables and synchronized via free AMFI APIs.  
* **BE-016 Referral Link / Code**: Unique tracking token assigned to an investor to invite prospective users.  
* **BE-017 Communication Channel**: External delivery integration (WhatsApp, Email, SMS, Push).  

## 7. Master Business Rules Catalog
* **BR-001 Identity**: An Investor is a single logical entity globally identified by unique attributes (PAN + Contact Details).  
* **BR-002 Multi-Tenancy**: An Investor can have N distributor relationships attached to their single master profile under isolated views.  
* **BR-003 Isolation**: A Distributor can never view or query investor holdings executed under another distributor's ARN.  
* **BR-004 No Consolidation**: Money Bowl shall not present a merged return view across different distributors to prevent concealing advisor performance.  
* **BR-005 Transactions**: Buy, Sell and Switch order requests may be initiated by a mapped investor or by an authorised Distributor acting for an actively mapped investor within the Distributor’s workspace. All transaction requests require Distributor approval or active Auto-Approval rules.  
* **BR-006 Auto-Approval**: Distributors can configure Auto-Approval rules for specific transaction types, amounts, or trusted clients.  
* **BR-007 Admin Override**: Platform Admins possess supersede access rights to unlock accounts, assist uneducated users, and perform access resets.  
* **BR-008 Data Masking**: PII data (PAN, Bank Accounts) must be masked by default across all portal views.  
* **BR-009 Family Access**: Family access is read-only, consent-backed, and can be managed directly by investors or assisted by their MFD.  
* **BR-010 AI Guardrails**: AI Assistant must never recommend funds, SIP amounts, fund switches, or provide personal investment advice.  
* **BR-011 Dual Subscriptions**: Premium features for both MFDs (CRM, Auto-Approval) and Investors (Family Hub) are gated behind subscription plans.  
* **BR-012 AMFI Factsheet Sync**: Factsheet metadata must be updated via free AMFI APIs and stored locally in the database schema foundation.  

## 8. Functional Requirements Catalog

### 8.1 Identity, Access & Exploring Onboarding (BC-001 – BC-003)
* **FR-001**: Platform shall support Distributor self-registration with ARN, firm details, and document upload.  
* **FR-002**: Platform shall support standalone Exploring Investor registration without requiring an initial distributor mapping.  
* **FR-003**: Platform shall provide Platform Admins with supersede access tools to perform account recovery, unlock user accounts, and reset access controls.  
* **FR-004**: Platform shall strictly mask sensitive PII (PAN, Bank details) by default across UI screens (e.g., XXXXX1234F).  

### 8.2 Order Execution, AMFI Factsheets & Universal Search (BC-004, BC-005, BC-015, BC-017)
* **FR-005**: Platform shall enable Mapped Investors to initiate Buy, Sell, and Switch order requests within their assigned distributor relationship view, and enable authorised Distributors to initiate Buy, Sell, and Switch order requests on behalf of actively mapped investors within their own workspace and relationship boundary.  
* **FR-006**: Platform shall route order requests directly to the mapped Distributor's Transaction Approval Queue.  
* **FR-007**: Platform shall provide a Universal Search & Discovery Bar in the top navigation bar to query schemes, folios, transactions, documents, and support tickets.  
* **FR-008**: Platform shall render detailed Scheme Factsheets (backed by local PostgreSQL tables and updated via free AMFI public APIs) displaying AMC details, category, NAV history, expense ratio, riskometer, and top holdings.  

### 8.3 Data Ingestion, Vaulting & Subscriptions (BC-006, BC-009, BC-011, BC-013, BC-018)
* **FR-009**: Platform shall connect to Distributor mailbags via IMAP/OAuth to extract and parse CAMS/KFintech CAS statements.  
* **FR-010**: Platform shall manage commercial subscription plans for both Distributors (MFDs) and Investors, enforcing feature gating and client limits.  
* **FR-011**: Platform shall enable Investors to generate unique referral links to invite prospective users, tracking successful sign-ups and applying trial rewards.  

### 8.4 Educational AI & Support Servicing (BC-007, BC-008)
* **FR-012**: Platform shall provide an Educational AI Assistant to decode jargon, explain factsheets, and run static financial calculators.  
* **FR-013**: Platform AI shall decline prompts requesting scheme recommendations, fund switches, or personal financial advice.  
* **FR-014**: Platform shall enable Investors to raise support tickets directly or via AI Assistant handoff to their Distributor's queue.  

## 9. Product Scope Boundaries (v1.2 Baseline)
* **In Scope**: Mutual Fund Portfolio Management, Investor Order Requests (Buy/Sell/Switch), MFD Transaction Approval Queue, Dual Subscription Engine, AMFI Scheme Factsheets (Free API Sync), Universal Search & Discovery Bar, Investor Referral System, Exploring Standalone Investor Flow, Admin Supersede & Override, Mandatory PII Security & Masking.
* **Out of Scope**: Direct Unassisted / Unadvised Order Execution (Without MFD), Direct Stock/Equity Tracking, Insurance, FDs, or Crypto, Personalized AI Investment Advice / Scheme Routing, Automated Portfolio Rebalancing, Tax Filing & IT Returns.

## 10. Non-Functional Requirements & Business SLAs
* **NFR-001 Data Security & Masking**: All sensitive user attributes (PAN, Aadhaar, Bank Account Numbers) must be encrypted at rest and masked by default in user-facing views. Revealing sensitive information requires explicit step-up authentication and immutable audit logging.
* **NFR-002 Universal Search Latency**: Universal search queries across schemes, folios, and documents must return filtered results within 200 milliseconds.
* **NFR-003 Order Routing SLA**: Submitted Buy/Sell/Switch order requests must appear in the Distributor's approval queue in under 5 seconds.
* **NFR-004 Statement Processing SLA**: Ingested mailbag CAS attachments must be processed into updated portfolio records within 15 minutes.  
* **NFR-005 Audit Lineage**: All transaction approvals, auto-approval triggers, administrative overrides, and access resets must create immutable, timestamped audit logs.
