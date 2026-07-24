# API Standards

## Purpose
This document defines standard API architectures, error responses, authentication verifications, and pagination conventions.

## Scope
Applies to all external API integrations, internal REST calls, and Edge Function endpoints.

---

## Detailed Guidelines

### 1. REST & Routing Conventions
- Route parameters must use lowercase with hyphens (e.g. `/v1/sign-stamp-invoice`).
- Requests carrying payload parameters must use JSON formats.

### 2. Authentication & API Security
- Every client request must pass a verified JWT token in the Authorization header.
- Edge Functions validate tokens prior to executing DTO conversions:
  ```typescript
  const authHeader = req.headers.get("Authorization");
  // Validate token payload via Supabase client library
  ```

### 3. Status Codes & Error Mapping
The API maps operational outcomes to standard HTTP response codes:

| HTTP Status | Meaning | Application Outcome |
| :--- | :--- | :--- |
| **200 OK** | Success | Request completes successfully. |
| **400 Bad Request** | Validation Failure | Invalid payloads or structural format errors. |
| **401 Unauthorized** | Session Expired | Stale or missing JWT signatures. |
| **403 Forbidden** | RLS Denied | Insufficient permissions for targeted resources. |
| **404 Not Found** | Record Absent | Target object or route does not exist. |
| **500 Internal Error** | Execution Fault | System exceptions or database timeouts. |

### 4. Pagination & Filtering
- Retrieval endpoints returning lists must implement page limits (default limit 20, max limit 100) and cursor-based pagination parameters.
- Filtering is performed using standard query parameters (e.g. `status=pending`).

---

## References
- [11 — CI/CD Pipeline Architecture](../architecture/11-cicd-architecture.md)
- [12 — Security Architecture](../architecture/12-security-architecture.md)
