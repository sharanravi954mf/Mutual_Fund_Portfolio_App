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
