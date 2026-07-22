# Sprint 5.3 Phase 2 — Backend Contract Gaps

## Repository gaps

| Repository method | Status | Missing capability | Recommended RPC / response | Security and blocker status |
|---|---|---|---|---|
| `submit` | Partial | Browser-safe acquisition of an opaque folio submission token. | `find_folio_submission_candidate(query)` returns `{ submission_token, masked_folio_label, expires_at }`. | Require authenticated active link, server-side normalization, no canonical ID/raw folio in response; **blocker for UI wiring**. |
| `getRequestDetail` | Partial | Folio-specific safe detail projection. | `get_folio_verification_request(request_id)` returns a masked request DTO with relationship, timestamps, status, and version. | Investor ownership/Advisor authorization only; **blocker for complete detail UI**. |
| `getAdvisorQueue` | Partial | Folio-only queue filtering and server pagination. | `list_folio_verification_queue(status, page, page_size)` returns masked request DTOs plus page metadata. | Advisor only; no raw evidence; **blocker for scalable Advisor queue**. |
| `getGrantSummary` | Blocked | Safe grant summary projection. | `get_folio_grant_summary(request_id)` returns `{ grant_id, status, holder_relationship, approved_at, revoked_at }`. | Request owner or Advisor only; **blocker for grant-status display**. |
| writes except `submit` | Partial | Correlation ID is absent from existing RPC signatures/events. | Add optional `p_correlation_id uuid` to each command RPC and persist only in immutable event metadata. | Must be caller-supplied, non-business identifier; **not a security blocker, required for stated Phase 2 contract**. |

## Browser-safe submission-token design

1. A linked investor submits a folio-search value to a secured discovery RPC.
2. The server normalizes and resolves registrar data internally; it never returns canonical keys, profile IDs, or raw evidence.
3. On exactly one authorized candidate, it returns an opaque encrypted token, a masked business label, and a five-minute expiry.
4. The token is bound to `auth.uid()`, the intended holder relationship/request context, candidate reference, expiry, and a one-time nonce.
5. Submission validates token binding, expiry, nonce consumption, active account link, and current registrar evidence in one transaction.
6. Expired, reused, malformed, wrong-user, and changed-evidence tokens fail with a safe generic response. No candidate enumeration is exposed.

## Deferred tests

Database-dependent lifecycle, RLS, token-consumption, idempotency, grant-summary, and server-pagination tests remain owned by the Phase 1 SQL suite until the missing safe RPC projections exist.
