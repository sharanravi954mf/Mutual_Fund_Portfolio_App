# Sprint 5.6A — Advisor Folio Authorization Layer

## Purpose

Sprint 5.6A establishes the server-side authorization boundary for future
Advisor folio review. It does not add Advisor or Investor user-interface work.

## Assignment model

`verification_request_assignments` assigns a folio verification request to one
active Advisor account. Assignment history is retained by deactivating a prior
assignment rather than deleting it; lifecycle history remains append-only in
`verification_events`.

Current single-Advisor installations are compatible: existing folio requests
are assigned to the only Advisor during migration, and new requests are
assigned atomically during submission. A deployment with zero or multiple
Advisors is intentionally not auto-routed. A future supervisor-routing
workflow must assign or reassign those requests.

## Authorization model

- An investor retains access only to their existing safe projections.
- An Advisor may list, inspect, begin review, approve, reject, request more
  information, or revoke a folio grant only when the request has an active
  assignment to that Advisor.
- Generic PAN review remains compatible with existing Advisor authorization.
- Browser clients have no direct access to assignments, folio evidence, or
  grants. Safe `SECURITY DEFINER` RPC projections are the browser boundary.
- Generic verification RPCs explicitly reject folio request identifiers. They
  remain available only for non-folio workflows and are never a fallback for
  Advisor folio operations.

## RPC contracts

| RPC | Contract |
|---|---|
| `get_my_advisor_folio_requests` | Assignment-scoped, paginated, status-filtered queue with masked folio data only. |
| `get_my_advisor_folio_request_detail` | Assignment-scoped detail with masked folio data and safe append-only event summary. |
| Existing explicit folio lifecycle RPCs | Retained and extended with active-assignment checks. |

No generic browser-callable transition RPC is introduced.

## Reason policy

`FolioReviewReasonCode` is the typed Dart boundary and
`folio_review_reason_code` is the server boundary. Approval accepts only the
positive confirmation code appropriate to the holder relationship. Rejection
and requests for more information have separate allow-listed code sets, so a
negative decision code cannot approve a folio.

## Request-ID RPC authorization matrix

| Contract | Folio behavior | Authorization |
|---|---|---|
| `get_folio_request_detail`, `get_folio_grant_summary`, `get_folio_verification_events` | Dedicated safe projection | Request owner or assigned Advisor |
| `get_my_advisor_folio_requests`, `get_my_advisor_folio_request_detail` | Dedicated Advisor projection | Assigned Advisor only |
| Explicit folio lifecycle RPCs | Dedicated transition or revocation | Request owner where applicable, otherwise assigned Advisor |
| Generic status, queue, review, history, candidate, and transition RPCs | Exclude or reject folio | Non-folio only |

Decision operations lock `verification_requests` first and then the active
assignment row using `FOR UPDATE`. Any future reassignment RPC must acquire
these locks in the same order.

## Migration notes

The migration is forward-only. It does not rename or delete existing tables,
requests, evidence, grants, events, or lifecycle RPCs. It adds assignment
events for the single-Advisor migration backfill without rewriting history.

## Regression coverage

Persistent SQL tests cover assignment existence, direct browser-table denial,
generic-RPC folio rejection, generic creation atomicity, assigned Advisor reads
and transitions, unassigned Advisor denial, safe masking, stale-version
rejection, and atomic event creation. Dart tests cover typed reason-code
mapping, action compatibility, safe DTO mapping, and assignment-safe repository
invocation.

## Deferred work

- Supervisor role and Advisor reassignment RPCs/UI. Before enabling a second
  Advisor account, this workflow must be deployed: new folio submissions are
  deliberately rejected unless exactly one active Advisor exists. Requests must
  never be randomly assigned or exposed through broad `is_admin()` access.
- Advisor queue/detail presentation, controller, provider, and navigation.
- Request-assignee filters and operational workload metrics.
