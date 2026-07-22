# Verification candidate-token Vault setup

The Advisor verification workflow encrypts short-lived candidate tokens with a
dedicated Vault secret. It does not use the Supabase JWT signing secret.

## Required secret

Create exactly one Vault secret named:

`verification_candidate_token_encryption_key`

Use a cryptographically random value of at least 32 characters. Do not put the
value in a migration, source file, Flutter environment file, or Edge Function
payload.

## Hosted staging and production

Before applying `20260726000000_verification_approval_vault_fix.sql`, a project
owner or database administrator must create the secret in that project's
Supabase Vault. For example, run the following only in the target project's
SQL editor after substituting a securely generated value:

```sql
select vault.create_secret(
  '<secure-random-value>',
  'verification_candidate_token_encryption_key',
  'Encryption key for Advisor verification candidate tokens'
);
```

Then apply the migration and run an Advisor approval smoke test. The migration
fails closed with a generic configuration error if the secret is missing or too
short.

## Local development

`supabase/seed.sql` generates a random local-only value when the secret is not
already present. A local reset therefore needs no manually copied production
secret.

## Rotation

Candidate tokens expire after five minutes. Rotate the Vault secret during a
maintenance window, then allow five minutes for issued tokens to expire. Tokens
issued before rotation will fail safely and require the Advisor to search again.
