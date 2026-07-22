# Sprint 5.3 Design — Folio Ownership Verification

**Status:** Revised design for architectural approval  
**Baseline:** `v0.7.0-alpha`  
**Scope:** Architecture blueprint only. This does not authorize code, migrations, Flutter changes, or deployment.

## 1. Sprint Objectives

### Business goal

Sprint 5.3 makes folio ownership the authorization boundary for investor portfolio data after identity and PAN verification. An investor may access only portfolio, holding, transaction, valuation, and reporting data derived from folios covered by an active approved grant.

### Success criteria

- Every investor portfolio read requires an active identity link and an active approved grant for the relevant folio.
- Claims, evidence, decisions, grants, revocations, and retries are immutable or append-only as appropriate and auditable.
- Sole, joint, and guardian relationships are handled conservatively.
- Advisor actions are secured, version-checked, atomic, and auditable.
- Existing identity, PAN, RLS, portfolio, and repository boundaries remain intact until a controlled transition is deployed.

## 2. Scope and Out of Scope

### In scope

- Folio claims, secure Advisor review, immutable folio evidence, and active folio grants.
- Folio-scoped portfolio authorization, canonical server-side folio identity, registrar provenance, and lineage.
- `SOLE_HOLDER`, `JOINT_HOLDER`, and `GUARDIAN_FOR_MINOR` relationships.
- Existing verification request/event reuse and secured lifecycle RPCs.

### Out of scope

- PAN correction, approval reversal, and imported-PAN reconciliation implementation.
- OCR, document uploads, email attachment storage, external registrar APIs, OTP, notifications, and automated approval.
- Nominee, family, beneficiary, power-of-attorney, informal-authorization, and deceased-holder-successor direct access.
- A generic workflow engine, parallel request/event framework, document-management system, or broad compliance tooling.

## 3. Approved Architectural Decisions

1. `investor_account_links` establishes the relationship between an authenticated account and a business profile; it is not blanket portfolio authorization.
2. Active approved folio grants are the investor portfolio-access authority. Advisor access follows the existing Advisor authorization model.
3. Canonical folio identity is server-derived from registrar, normalized folio number, and AMC/fund-house identity where needed.
4. Shared and guardian cases are never automatically approved. They require registrar evidence and Advisor review.
5. Existing verification requests and append-only events are reused. Folio-specific immutable evidence and one narrow folio-grant relationship complete the model.
6. All lifecycle mutations use secured server-side RPCs, expected-version validation, and immutable events. Terminal requests are never reopened.
7. PAN remains supporting evidence only; it is not login, automatic identity matching, ownership authority, or browser-visible raw data.

## 4. Identity-Link and Folio-Grant Authority Model

`investor_account_links` answers: **Which authenticated account is linked to which business profile?**

Folio grants answer: **Which folio-derived portfolio data may that linked investor access?**

Neither replaces the other. Investor portfolio access requires both an active account-to-profile link for `auth.uid()` and an active approved folio grant for the canonical folio represented by the requested data. Explorer and Link Pending accounts have no folio-derived access. Advisors retain existing Advisor access and do not require investor folio grants.

### Revocation precedence

- Revoking an account link immediately removes all investor access for that account.
- Revoking one folio grant immediately removes access only to that folio.
- A revoked, expired, superseded, or inactive grant never authorizes a read.
- PAN correction and imported reconciliation do not silently change active grants. Future explicit workflows may mark grants review-required or suspended with an audit reason.
- Approval reversal is a new revocation/reversal decision; it never rewrites the original approval, grant, evidence, or event.

### Transition from current account-level access

The future rollout must establish reviewed grant coverage for current linked investors before folio-scoped authorization is enforced. It must not silently broaden access or unexpectedly remove established access. The migration strategy requires cohort reconciliation, compare-mode monitoring, explicit support exceptions, feature gating, and rollback that disables enforcement without deleting audit history or grants.

## 5. Supported Holder Relationships

| Relationship | Support | Minimum evidence | Advisor standard |
|---|---|---|---|
| `SOLE_HOLDER` | Supported | Registrar-imported holder evidence aligned with the business profile; verified PAN may support but cannot alone approve. | Approve only when current registrar evidence and canonical identity agree. |
| `JOINT_HOLDER` | Supported, manual review | Registrar evidence identifies the claimant as a valid joint holder and preserves relationship/ordering where available. | Mandatory Advisor review; approve each holder independently; escalate conflicts. |
| `GUARDIAN_FOR_MINOR` | Supported, manual review | Registrar evidence identifies both minor holder and guardian relationship. | Mandatory Advisor review; approve only the evidenced relationship. |
| `NOMINEE`, `FAMILY_MEMBER`, `BENEFICIARY`, `POWER_OF_ATTORNEY`, `INFORMAL_AUTHORIZATION`, `DECEASED_HOLDER_SUCCESSION` | Not supported | Not applicable. | Reject as unsupported or escalate outside Sprint 5.3. |

A canonical folio may have multiple active grants only where registrar evidence supports a valid joint-holder or guardian relationship. Nominee or family status alone never grants access. Each grant is independently revocable without affecting other valid grants.

Conflicting holder data, suspected fraud, succession/deceased-holder cases, unsupported legal relationships, and manual identity overrides are escalated and remain unapproved in ordinary Sprint 5.3 processing.

## 6. Canonical Folio Identity

```text
canonical_folio_key = registrar identity + registrar-normalized folio number + AMC/fund-house identity when required
```

The server derives the key. Flutter never constructs, submits, or receives it as a raw identifier. Normalization removes non-semantic spaces, hyphens, case differences, and registrar presentation variation while retaining source representation as provenance.

- CAMS and KFintech folios with the same visible number remain distinct unless an explicit reconciliation record or approved migration rule establishes equivalence.
- Provenance is retained for each imported reference and evidence projection.
- Reissued, migrated, merged, split, renumbered, or transferred folios retain lineage rather than replacing history.
- Conceptual lineage relationships are `predecessor`, `successor`, `migrated_from`, `merged_into`, `split_from`, and `reconciled_equivalent`.
- Duplicate active grants are forbidden for the same account, profile, canonical folio, and holder relationship. Valid different joint holders remain permitted.

## 7. Business Workflow

```mermaid
sequenceDiagram
  participant Investor
  participant App as Flutter application
  participant RPC as Secured verification RPCs
  participant Registrar as Imported registrar evidence
  participant Advisor
  Investor->>App: Create folio claim and declaration
  App->>RPC: Submit claim with idempotency key
  RPC->>Registrar: Resolve canonical folio and safe evidence
  RPC->>RPC: Create request, immutable evidence, and event atomically
  Advisor->>RPC: Begin review using expected version
  Advisor->>RPC: Approve, reject, or request information
  RPC->>Registrar: Revalidate current evidence at decision time
  alt valid approval
    RPC->>RPC: Create active grant and approval event atomically
  else invalid or changed evidence
    RPC->>RPC: Do not approve; emit only permitted lifecycle event
  end
```

The Investor submits allowed evidence and a declaration. The Advisor reviews masked evidence, holder relationship, conflict category, lineage, and history. The server resolves registrar records and decides authorization; neither UI does so.

## 8. Formal Request State Machine

States are `DRAFT`, `SUBMITTED`, `UNDER_REVIEW`, `MORE_INFORMATION_REQUIRED`, `APPROVED`, `REJECTED`, `CANCELLED`, `EXPIRED`, `SUPERSEDED`, and `REVOKED`. `REVOKED` applies to the previously approved request/grant relationship and disables the grant without deleting history.

| Source | Action / actor | Target | Required reason or evidence | Expected version | Event | New request later? |
|---|---|---|---|---|---|---|
| `DRAFT` | Submit / Investor | `SUBMITTED` | Allowed evidence, declaration, idempotency key | Required | `FOLIO_REQUEST_SUBMITTED` | No |
| `SUBMITTED` | Begin review / Advisor | `UNDER_REVIEW` | Acting Advisor | Required | `FOLIO_REVIEW_STARTED` | No |
| `UNDER_REVIEW` | Request information / Advisor | `MORE_INFORMATION_REQUIRED` | Structured reason and requested category | Required | `FOLIO_INFORMATION_REQUESTED` | No |
| `MORE_INFORMATION_REQUIRED` | Resubmit / Investor | `SUBMITTED` | Additional permitted evidence/declaration | Required | `FOLIO_INFORMATION_RESUBMITTED` | No |
| `UNDER_REVIEW` | Approve / Advisor | `APPROVED` | Supported relationship, approval code, rationale, evidence reference, decision-time revalidation | Required | `FOLIO_APPROVED` | No |
| `UNDER_REVIEW` | Reject / Advisor | `REJECTED` | Structured rejection code and rationale | Required | `FOLIO_REJECTED` | Yes |
| `DRAFT`, `SUBMITTED`, `MORE_INFORMATION_REQUIRED` | Cancel / Investor | `CANCELLED` | Cancellation reason where supplied | Required | `FOLIO_CANCELLED` | Yes |
| `SUBMITTED`, `UNDER_REVIEW`, `MORE_INFORMATION_REQUIRED` | Expire / server | `EXPIRED` | Configured expiry reached | Required when processed | `FOLIO_EXPIRED` | Yes |
| Active older attempt | Supersede / authorized server process | `SUPERSEDED` | Replacement attempt and rationale | Required | `FOLIO_SUPERSEDED` | Replacement exists |
| `APPROVED` | Revoke grant / authorized Advisor or future controlled process | `REVOKED` | Revocation code, rationale, actor | Required | `FOLIO_GRANT_REVOKED` | Yes |

Retries after rejection, expiry, cancellation, or supersession create a new linked `DRAFT`; terminal requests are never reopened. Advisor-role removal reassigns or clears the assignee through a secured process, emits `FOLIO_REVIEW_REASSIGNED`, and leaves state unchanged unless it expires. Material imported-data change blocks approval, supersedes the attempt with `FOLIO_EVIDENCE_CHANGED`, and requires a new request. Invalid transitions fail atomically with no event.

## 9. Grant Lifecycle

Approval atomically creates one active grant linked to the approved request, canonical folio, business profile, account, and holder relationship. A grant authorizes access only while it, the request, and the account link remain active and the account state permits investor access.

Grant status is separate from request state so revocation can remove access without rewriting approval history. An inactive grant cannot reactivate; renewed access requires a new approved request.

## 10. Evidence Policy

Allowed Sprint 5.3 evidence is limited to:

- registrar-imported holder evidence;
- securely ingested registrar statement metadata;
- the verified PAN relationship as supporting evidence only;
- Advisor-entered structured reason codes; and
- Investor confirmation/declaration as supplementary evidence only.

Excluded evidence includes document uploads, unstructured free text as the sole basis, stored email attachments, OCR approval, PAN-only automated approval, and raw PAN/folio exposure in the browser.

Evidence is immutable and retains provenance, capture time, source-system time when available, masked projection, and supersession relationship. It follows the platform verification/audit retention policy. Decision-time revalidation is mandatory.

## 11. Advisor Decision Policy

Every decision requires acting Advisor, timestamp, expected version, rationale, evidence reference, and an escalation flag when relevant.

| Decision | Structured codes |
|---|---|
| Approval | `SOLE_HOLDER_CONFIRMED`, `JOINT_HOLDER_CONFIRMED`, `GUARDIAN_RELATIONSHIP_CONFIRMED`, `REGISTRAR_EVIDENCE_CONFIRMED` |
| Rejection | `HOLDER_MISMATCH`, `INSUFFICIENT_EVIDENCE`, `FOLIO_NOT_FOUND`, `UNSUPPORTED_RELATIONSHIP`, `DUPLICATE_CLAIM`, `CONFLICTING_REGISTRAR_DATA`, `SUSPECTED_FRAUD` |
| Revocation | `APPROVED_IN_ERROR`, `ACCOUNT_LINK_REVOKED`, `REGISTRAR_CORRECTION`, `FRAUD_CONFIRMED`, `LEGAL_OR_COMPLIANCE_HOLD` |

Ordinary claims do not require two-person approval. Senior/compliance escalation is mandatory only for conflicting holder data, suspected fraud, succession/deceased-holder cases, unsupported legal relationships, and manual identity overrides; these remain outside ordinary approval scope.

## 12. Security and Authorization Model

- Investors create and read only their own safe request/status projections. They cannot approve, alter immutable evidence, create grants, or inspect unrelated folios.
- Advisors decide only via secured RPCs. RLS must not allow direct grant, decision, or immutable-evidence mutation.
- Advisor projections are least-privilege and never expose raw PAN, raw canonical folio keys, unrelated profile identifiers, or unrelated investor data.
- Submission requires an idempotency key. A replay returns the original safe result or fails without duplicate rows/events.
- Every decision/mutation requires expected-version validation.
- Candidate selection, if necessary, uses one-time expiring request-bound and Advisor-bound opaque tokens. Expired, modified, wrong-request, wrong-Advisor, stale-version, consumed, and replayed tokens are rejected.
- Investor RLS evaluates active link plus active grant at folio scope; existing Advisor authorization stays intact.

## 13. Conceptual Data Model

Reuse existing verification requests and immutable events, adding only:

- folio-specific immutable evidence with provenance, timestamps, masking, and request association;
- a registrar-aware canonical folio identity/reference with lineage/reconciliation references;
- a narrow folio grant among account, business profile, canonical folio, holder relationship, approved request, decision actor, and lifecycle status; and
- request lineage for retries and supersession.

The uniqueness rule prevents duplicate active grants for the same account, profile, canonical folio, and holder relationship while allowing evidence-backed grants for different valid joint holders. Historical grants/events are retained.

## 14. RPC Responsibilities

Future secured RPCs perform submission, review start/reassignment, information request/resubmission, decision, cancellation, expiry, and revocation. Each authenticates caller and role, normalizes evidence server-side, resolves canonical folio without enumeration, validates state/version/idempotency/tokens, revalidates current registrar evidence, commits all effects atomically, returns only safe projections, and rolls back entirely on error.

## 15. RLS Implications

Investor policies for portfolio, holdings, transactions, valuations, and reporting must require both a matching active account link and active approved grant at canonical folio scope. Safe verification projections are limited to the requester or authorized Advisor. Browser roles cannot write grants, decisions, or immutable evidence. Link/grant inactivity must take effect during the next access check, including in existing sessions.

## 16. Flutter and Repository Responsibilities

Flutter supplies constrained evidence input and safe status/review experiences. Widgets never access Supabase directly, construct canonical identities, resolve candidates, or decide authorization. Repositories expose typed, masked DTOs; services/coordinators own lifecycle and navigation.

Investor screens show business-friendly state and retry paths. Advisor queues filter by status, age, risk, and assignee. Details show masked evidence, holder relationship, conflict category, lineage, timeline, and permitted actions only. Navigation preserves filters and avoids internal identifiers.

## 17. Failure Recovery

- Pending requests expire after a configurable server-side period and append an expiry event.
- Reassignment preserves evidence and history.
- Cancellation is allowed only from approved nonterminal states and is permanent.
- Retry creates a new linked request; it never reopens history.
- Concurrent duplicates are controlled by idempotency and server-side duplicate validation.
- Material imported-data changes supersede the pending request and block approval.
- Advisor-role removal blocks further decisions until secured reassignment or expiry.
- Temporary failures are safe and retryable; atomic transactions forbid partial grants, events, or decisions.
- Revocation immediately removes relevant access and preserves rationale/history.

## 18. Edge Cases

- Repeated or concurrent submission by the same Investor.
- Multiple Investors claiming one canonical folio.
- Joint, guardian, nominee, family, beneficiary, and succession scenarios.
- Closed, dormant, absent, transferred, migrated, merged, split, or renumbered folios.
- CAMS/KFintech visible-number collisions without reconciliation.
- PAN/registrar correction after approval.
- Multiple Advisors, reassignment, role removal, stale decisions, and invalid tokens.
- Account-link revocation during or after review.
- Incomplete legacy metadata and later-arriving importer data.

## 19. Scale and Performance Assumptions

The design targets thousands of investors, tens of thousands of folios, and larger transaction/event volumes. Advisor queues must filter by status, age, risk, and assignee without full-history scans.

Implementation must provide query support for active grants by account/profile, canonical folio lookup, duplicate active claims, pending Advisor queue filters, request version/lineage, grant status, and registrar provenance. Decision transactions should lock only the affected request/grant/canonical-folio scope.

## 20. Validation Plan

- Forward-only migration, rollout, and local reset review.
- SQL tests for every valid/invalid state transition, atomic rollback, idempotency/replay, stale version, wrong Advisor/request, expired/consumed token, duplicate claim, valid joint/guardian claim, and unsupported holder.
- RLS tests proving active link plus active grant is required and revoked links/grants immediately lose access.
- Repository, service, and widget tests for loading, empty, error, cancellation, retry, reassignment, decision, and navigation.
- Regression testing for account linking, PAN verification, ownership, ingestion, Invoice Signer, and Advisor workflows.
- Flutter test, analysis, debug web build, diff check, security review, manual smoke tests, and staged access compare-mode validation.

## 21. Migration and Rollout Considerations

Future migrations are forward-only and must not change historical identity, PAN, portfolio, or transaction foreign keys. Folio authorization is introduced behind a feature gate. Existing portfolio records receive candidate coverage only from trusted registrar data; unmappable records become support exceptions, not broad grants or silent denials. Compare-mode monitoring precedes enforcement. Rollback disables enforcement without deleting claims, grants, evidence, or history.

## 22. Deferred Features

- PAN correction and explicit review-required/suspension workflow.
- Approval reversal workflow beyond the defined revocation model.
- Imported-PAN reconciliation tooling.
- Documents, OCR, attachments, notifications, OTP, automated/external registrar verification.
- Unsupported legal relationship types.

## 23. Remaining Open Questions

These are non-blocking implementation details:

1. What configurable pending-request duration best fits Advisor operations?
2. Which safe labels and risk categories should appear in the Advisor queue?
3. What retention duration applies to each masked evidence projection?
4. Which operational role performs Advisor reassignment?
5. Which rollout cohort is first for compare-mode monitoring?
