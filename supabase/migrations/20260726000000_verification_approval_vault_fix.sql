-- Sprint 5.1 release fixes:
-- 1. Use a dedicated Vault secret rather than the removed hosted
--    app.settings.jwt_secret setting.
-- 2. Qualify every approval-RPC reference to avoid PL/pgSQL variable/column
--    ambiguity while preserving optimistic locking and append-only events.

create or replace function public.verification_candidate_token_secret()
returns text as $$
declare
  token_secret text;
begin
  select decrypted_secret into token_secret
  from vault.decrypted_secrets
  where name = 'verification_candidate_token_encryption_key'
  limit 1;

  if token_secret is null or length(token_secret) < 32 then
    raise exception 'Verification candidate token configuration is unavailable';
  end if;
  return token_secret;
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

create or replace function public.approve_verification_candidate(
  p_request_id uuid,
  p_candidate_token text,
  p_expected_version integer,
  p_reason_code text default null
) returns public.verification_request_status as $$
declare
  v_request public.verification_requests%rowtype;
  v_token_payload jsonb;
  v_profile_id uuid;
begin
  if not public.is_admin() then
    raise exception 'Advisor authorization is required';
  end if;

  begin
    v_token_payload := extensions.pgp_sym_decrypt(
      decode(p_candidate_token, 'base64'),
      public.verification_candidate_token_secret()
    )::jsonb;
  exception when others then
    raise exception 'Verification candidate is unavailable';
  end;

  if v_token_payload ->> 'request_id' <> p_request_id::text
      or v_token_payload ->> 'advisor_user_id' <> auth.uid()::text
      or coalesce((v_token_payload ->> 'expires_at')::bigint, 0)
         < extract(epoch from now())::bigint then
    raise exception 'Verification candidate is unavailable';
  end if;

  v_profile_id := (v_token_payload ->> 'profile_id')::uuid;

  select request_row.* into v_request
  from public.verification_requests as request_row
  where request_row.id = p_request_id
  for update;

  if not found
      or v_request.status <> 'pending_advisor_review'
      or v_request.version <> p_expected_version then
    raise exception 'Verification request cannot be approved';
  end if;

  if not exists (
    select 1
    from public.profiles as candidate_profile
    where candidate_profile.id = v_profile_id
      and candidate_profile.role = 'client'
  ) then
    raise exception 'Verification request cannot be approved';
  end if;

  if exists (
    select 1
    from public.investor_account_links as existing_link
    where (existing_link.user_id = v_request.user_id
           or existing_link.profile_id = v_profile_id)
      and existing_link.link_status = 'active'
  ) then
    raise exception 'Verification request cannot be approved';
  end if;

  insert into public.investor_account_links (
    user_id, profile_id, verification_method, verified_at, linked_at, link_status
  ) values (
    v_request.user_id, v_profile_id, v_request.method_code, now(), now(), 'active'
  ) on conflict (user_id, profile_id) do update set
    verification_method = excluded.verification_method,
    verified_at = excluded.verified_at,
    linked_at = excluded.linked_at,
    link_status = 'active';

  update public.user_accounts as account
  set account_state = 'linked_investor', onboarding_completed = true
  where account.user_id = v_request.user_id;

  update public.verification_requests as request_row
  set status = 'approved',
      candidate_profile_id = v_profile_id,
      resolved_at = now(),
      version = request_row.version + 1
  where request_row.id = v_request.id
    and request_row.version = p_expected_version;

  if not found then
    raise exception 'Verification request changed; refresh and retry';
  end if;

  insert into public.verification_events (
    request_id, subject_user_id, actor_user_id, actor_type, event_type,
    previous_status, new_status, reason_code
  ) values (
    v_request.id, v_request.user_id, auth.uid(), 'advisor', 'approved',
    'pending_advisor_review', 'approved', p_reason_code
  );

  return 'approved';
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

revoke all on function public.verification_candidate_token_secret()
  from public, anon, authenticated, service_role;
revoke all on function public.approve_verification_candidate(uuid, text, integer, text)
  from public, anon, service_role;
grant execute on function public.approve_verification_candidate(uuid, text, integer, text)
  to authenticated;
