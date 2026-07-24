# User Journeys

## Purpose
This document maps step-by-step user interactions across the platform.

## Audience
Product owners, UX engineers, QA testers, and developers.

## Business Context
Mapping workflows ensures that both frontend screen sequences and backend permission gates align to complete business objectives.

---

## Detailed Explanation

### 1. Investor Onboarding Journey

```mermaid
flowchart TD
  Start["1. Investor Sign-up"] --> AuthCheck{"2. Check Email / Mobile"}
  AuthCheck -- Match Found --> LinkAccount["3. Auto-Link Profile"] --> Done["4. Active Linked Investor Dashboard"]
  AuthCheck -- No Match --> OnboardChoice{"5. Already Invest?"}
  OnboardChoice -- No --> Explorer["6. Enter Explorer Dashboard"]
  OnboardChoice -- Yes --> LinkPending["7. Enter Onboarding Verification Page"]
```

- **Steps**:
  1. The user registers with email/password.
  2. The system checks if the email matches an imported contact record.
  3. If unique match is found, creates an active link automatically.
  4. If not, prompts the user to select whether they are an existing investor or exploring.

---

### 2. Portfolio Statement Ingestion Journey

```mermaid
flowchart LR
  Start["1. Email Attachment Recieved"] --> DBF["2. Extract DBF File"]
  DBF --> Parse["3. Parse Records"]
  Parse --> CheckProfile{"4. Profile Exist?"}
  CheckProfile -- No --> CreateUnreg["5. Create Unregistered Profile"] --> InsertLedger["6. Insert Transactions"]
  CheckProfile -- Yes --> InsertLedger
```

- **Steps**:
  1. The RTA mailbox statement arrives.
  2. The database parses transaction records (extracts PAN, folio, investor name).
  3. If no matching profile exists, creates a placeholder unregistered profile.
  4. Inserts holdings and transactions.

---

### 3. Portfolio Verification & Grant Journey

```mermaid
flowchart TD
  Start["1. Claim Folio Number"] --> Search{"2. Resolve Registrar Candidate"}
  Search --> Token["3. Generate Expiring Token"]
  Token --> Request["4. Submit Claim Request"]
  Request --> Assign{"5. Advisor Queue Assignment"}
  Assign --> Review{"6. Advisor Review Details"}
  Review -- Approved --> Grant["7. Create Folio Grant"] --> Active["8. Investor Can View Folio Data"]
```

- **Steps**:
  1. Investor types their folio number.
  2. System verifies candidate matching without revealing internal IDs.
  3. Advisor reviews the claim request within their assigned workspace.
  4. On approval, active grant authorizes access.

---

### 4. PDF Invoice Signer Journey

```mermaid
flowchart LR
  Select["1. Upload ZIP / PDFs"] --> Stamp["2. Configure Offsets"]
  Stamp --> Run["3. Apply in-memory overlays"]
  Run --> Pack["4. Compress back to ZIP"]
  Pack --> Download["5. Download signed archive"]
```

- **Steps**:
  1. Advisor uploads a zip of invoices.
  2. Configures signature coordinates.
  3. System signs files in-memory.
  4. Downloads signed output ZIP.

---

## Future Evolution
- **AI-Assisted Claims**: Future workflows will match statement uploads via optical character recognition (OCR) and auto-approve sole holder claims.
