-- Local development only: generate a dedicated, non-production token key on
-- every fresh reset when none exists. Hosted environments must provision their
-- own value in Supabase Vault; no production secret belongs in this repository.
do $$
begin
  if not exists (
    select 1
    from vault.secrets
    where name = 'verification_candidate_token_encryption_key'
  ) then
    perform vault.create_secret(
      encode(extensions.gen_random_bytes(32), 'hex'),
      'verification_candidate_token_encryption_key',
      'Local development key for verification candidate tokens'
    );
  end if;
end;
$$;

-- PAN verification uses distinct secrets for encryption at rest and
-- deterministic HMAC lookup. These values are development-only and are
-- created only when a fresh local database does not already contain them.
do $$
begin
  if not exists (select 1 from vault.secrets where name = 'pan_encryption_key') then
    perform vault.create_secret(
      encode(extensions.gen_random_bytes(32), 'hex'),
      'pan_encryption_key',
      'Local development key for PAN encryption'
    );
  end if;
  if not exists (select 1 from vault.secrets where name = 'pan_lookup_hmac_key') then
    perform vault.create_secret(
      encode(extensions.gen_random_bytes(32), 'hex'),
      'pan_lookup_hmac_key',
      'Local development key for PAN HMAC lookups'
    );
  end if;
end;
$$;
