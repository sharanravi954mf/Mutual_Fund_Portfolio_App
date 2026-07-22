# PAN verification Vault setup

Sprint 5.2 uses two independent Supabase Vault secrets. Neither is a JWT
secret and neither may be placed in Flutter, an Edge Function environment file,
logs, or source control.

| Vault secret name | Purpose |
| --- | --- |
| `pan_encryption_key` | AES-256 encryption of PAN evidence and business PAN records at rest. |
| `pan_lookup_hmac_key` | SHA-256 HMAC lookup for matching and duplicate detection. |

## Hosted deployment

Before applying `20260727000000_pan_verification.sql` to staging or production,
create both secrets in the target project's Supabase Vault using independent,
random values of at least 32 bytes. The database migration intentionally fails
closed if either secret is unavailable.

Example SQL, executed only in the target project's SQL editor by an authorized
operator:

```sql
select vault.create_secret('<random-32-byte-or-longer-value>', 'pan_encryption_key', 'PAN encryption key');
select vault.create_secret('<different-random-32-byte-or-longer-value>', 'pan_lookup_hmac_key', 'PAN lookup HMAC key');
```

Apply the migration only after both calls have succeeded. Do not rotate either
secret without a planned re-encryption/re-HMAC migration; the current sprint
intentionally has no key-rotation workflow.

## Local development

`supabase/seed.sql` creates non-production random values during a clean local
database reset when they do not already exist. Local values must never be copied
to a hosted environment.

## Access boundary

Only `SECURITY DEFINER` functions retrieve decrypted values from Vault. Browser
roles have no direct privileges on PAN tables or the helper functions. Flutter
receives only a masked PAN and safe match/conflict categories.
