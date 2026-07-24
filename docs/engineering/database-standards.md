# Database Standards

## Purpose
This document defines PostgreSQL schema standards, migration execution constraints, RLS policies, indexing requirements, and Vault integrations.

## Scope
Applies to all database tables, columns, migrations, triggers, security policies, and stored procedures.

---

## Detailed Guidelines

### 1. Schema & Naming Conventions
- **Nomenclature**: Tables, columns, and trigger functions use lowercase with underscores (`verification_requests`, `user_id`).
- **Foreign Keys**: Must have explicit references and index constraints applied to maintain relational integrity.
- **Auditing Columns**: Tables tracking operations must contain `created_at` and `updated_at` timestamps.

### 2. Migration Execution Constraints
- **Forward-Only**: Migrations are append-only. Never rename, delete, or replace an existing migration.
- **Prefixing**: Migrations must use standard UTC timestamps:
  ```text
  supabase/migrations/20260729000002_qualify_folio_lifecycle_updates.sql
  ```
- **Local Validation**: Run local database resets and tests to verify that new migrations compile cleanly with zero errors.

### 3. Row Level Security (RLS) & Policies
- **Mandate**: Enable RLS on all operational database tables:
  ```sql
  ALTER TABLE portfolios ENABLE ROW LEVEL SECURITY;
  ```
- **Owner Verification**: Policies must resolve authenticated callers using `auth.uid()` and cross-reference links (`investor_account_links`).

### 4. Database Cryptography & Secrets
- **Vault Encryptions**: Sensitive columns (like PAN) must use `pg_vault` encryption keys and hash lookups (`SHA-256` HMAC lookup indexes).
- **Security Definer**: Stored procedures executing Vault access must implement `SECURITY DEFINER` and set search paths to public.

---

## References
- [12 — Security Architecture](../architecture/12-security-architecture.md)
- [06 — Infrastructure Architecture](../architecture/06-infrastructure-architecture.md)
