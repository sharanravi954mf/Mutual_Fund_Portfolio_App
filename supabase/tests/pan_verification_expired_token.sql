-- Persistent local regression test. Run after `supabase db reset` with:
-- docker exec <local-db-container> psql -v ON_ERROR_STOP=1 -U postgres -d postgres -f /tmp/pan_verification_expired_token.sql
-- The transaction rolls back all fixtures.
begin;

insert into auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('41000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'expired-pan-investor@example.test', '{}', '{}', now(), now()),
  ('41000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'expired-pan-advisor@example.test', '{}', '{}', now(), now());
update public.user_accounts set account_state = 'link_pending'
where user_id = '41000000-0000-0000-0000-000000000001';
update public.user_accounts set account_state = 'advisor'
where user_id = '41000000-0000-0000-0000-000000000002';
insert into public.profiles (id, full_name, role)
values ('42000000-0000-0000-0000-000000000001', 'Expired Token Candidate', 'client');
insert into public.profile_pan_records (profile_id, pan_ciphertext, pan_lookup_hmac, masked_pan, source, source_system, status)
select '42000000-0000-0000-0000-000000000001'::uuid,
  extensions.pgp_sym_encrypt('ABCDE1234F', public.pan_encryption_key(), 'cipher-algo=aes256, compress-algo=0'),
  extensions.hmac('ABCDE1234F', public.pan_lookup_hmac_key(), 'sha256'),
  '******1234', 'IMPORT', 'CAMS', 'OBSERVED';

do $$
declare
  v_request_id uuid;
  v_expired_token text;
begin
  perform set_config('request.jwt.claim.sub', '41000000-0000-0000-0000-000000000001', true);
  select request_id into v_request_id from public.submit_pan_verification('ABCDE1234F');

  -- Produce a structurally valid, request-bound, Advisor-bound token whose
  -- expiry is deterministically in the past. This isolates expiry from every
  -- other approval guard.
  perform set_config('request.jwt.claim.sub', '41000000-0000-0000-0000-000000000002', true);
  v_expired_token := encode(extensions.pgp_sym_encrypt(
    jsonb_build_object(
      'request_id', v_request_id,
      'profile_id', '42000000-0000-0000-0000-000000000001',
      'advisor_user_id', auth.uid(),
      'expires_at', extract(epoch from now() - interval '1 minute')::bigint
    )::text,
    public.verification_candidate_token_secret(),
    'cipher-algo=aes256, compress-algo=0'
  ), 'base64');

  begin
    perform public.approve_pan_verification_candidate(v_request_id, v_expired_token, 1);
    raise exception 'expired token was accepted';
  exception when others then
    if sqlerrm = 'expired token was accepted' then raise; end if;
    if sqlerrm <> 'Verification candidate is unavailable' then
      raise exception 'expiry test failed for the wrong reason: %', sqlerrm;
    end if;
  end;

  if exists (select 1 from public.investor_account_links where user_id = '41000000-0000-0000-0000-000000000001' and link_status = 'active') then
    raise exception 'expired token created an investor link';
  end if;
  if not exists (select 1 from public.verification_requests where id = v_request_id and status = 'pending_advisor_review' and version = 1) then
    raise exception 'expired token changed the request state';
  end if;
  if exists (select 1 from public.verification_events where request_id = v_request_id and event_type = 'approved') then
    raise exception 'expired token appended an approval event';
  end if;
  if not exists (select 1 from public.user_accounts where user_id = '41000000-0000-0000-0000-000000000001' and account_state = 'link_pending') then
    raise exception 'expired token changed the account state';
  end if;
end;
$$;

rollback;
