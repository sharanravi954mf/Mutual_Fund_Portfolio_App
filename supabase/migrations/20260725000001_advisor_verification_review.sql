-- Sprint 5: secure Advisor review experience. Candidate tokens are encrypted,
-- short-lived, and stateless: no profile identifier is returned to Flutter and
-- no candidate-selection table or cleanup job is required.

create extension if not exists pgcrypto with schema extensions;

drop index if exists public.idx_verification_requests_one_open_per_user;
create unique index idx_verification_requests_one_open_per_user
  on public.verification_requests(user_id)
  where status in ('draft', 'pending_advisor_review', 'more_information_required');

create index if not exists idx_verification_requests_review_filters
  on public.verification_requests(status, method_code, submitted_at);

-- This secret is supplied by Supabase's database configuration. It is never
-- returned by a function and normal browser roles have no execute privilege.
create or replace function public.verification_candidate_token_secret()
returns text as $$
declare
  secret text := current_setting('app.settings.jwt_secret', true);
begin
  if secret is null or length(secret) < 32 then
    raise exception 'Verification candidate token configuration is unavailable';
  end if;
  return secret;
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

create or replace function public.mask_verification_email(value text)
returns text as $$
declare
  at_position integer;
begin
  if value is null or value = '' then return null; end if;
  at_position := position('@' in value);
  if at_position <= 1 then return '•••'; end if;
  return left(value, 1) || repeat('•', greatest(at_position - 2, 2)) || substring(value from at_position);
end;
$$ language plpgsql immutable security definer set search_path = public, pg_temp;

create or replace function public.mask_verification_mobile(value text)
returns text as $$
begin
  if value is null or value = '' then return null; end if;
  if length(value) <= 4 then return repeat('•', length(value)); end if;
  return repeat('•', greatest(length(value) - 4, 4)) || right(value, 4);
end;
$$ language plpgsql immutable security definer set search_path = public, pg_temp;

create or replace function public.issue_verification_candidate_token(
  p_request_id uuid,
  p_profile_id uuid,
  p_advisor_user_id uuid
) returns text as $$
declare
  payload text;
begin
  payload := jsonb_build_object(
    'request_id', p_request_id,
    'profile_id', p_profile_id,
    'advisor_user_id', p_advisor_user_id,
    'expires_at', extract(epoch from now() + interval '5 minutes')::bigint
  )::text;
  return encode(
    extensions.pgp_sym_encrypt(payload, public.verification_candidate_token_secret(), 'cipher-algo=aes256, compress-algo=0'),
    'base64'
  );
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

create or replace function public.get_verification_review(p_request_id uuid)
returns table (
  id uuid,
  method_code text,
  status public.verification_request_status,
  created_at timestamptz,
  submitted_at timestamptz,
  resolved_at timestamptz,
  expires_at timestamptz,
  version integer,
  retry_of_request_id uuid,
  requester_masked_email text,
  requester_masked_mobile text
) as $$
begin
  if not public.is_admin() then
    raise exception 'Advisor authorization is required';
  end if;

  return query
  select
    request.id,
    request.method_code,
    request.status,
    request.created_at,
    request.submitted_at,
    request.resolved_at,
    request.expires_at,
    request.version,
    request.retry_of_request_id,
    public.mask_verification_email(auth_user.email),
    public.mask_verification_mobile(auth_user.phone)
  from public.verification_requests request
  left join auth.users auth_user on auth_user.id = request.user_id
  where request.id = p_request_id;
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

create or replace function public.search_verification_candidates(
  p_request_id uuid,
  p_query text
) returns table (
  candidate_token text,
  candidate_name text,
  masked_email text,
  masked_mobile text,
  profile_summary text
) as $$
declare
  normalized_query text := trim(p_query);
begin
  if not public.is_admin() then
    raise exception 'Advisor authorization is required';
  end if;
  if normalized_query is null or length(normalized_query) < 2 then
    raise exception 'Enter at least two characters to search';
  end if;
  if not exists (
    select 1 from public.verification_requests
    where id = p_request_id and status in ('pending_advisor_review', 'more_information_required')
  ) then
    raise exception 'Verification request is unavailable';
  end if;

  return query
  select
    public.issue_verification_candidate_token(p_request_id, profile.id, auth.uid()),
    coalesce(nullif(profile.full_name, ''), 'Imported investor'),
    public.mask_verification_email(profile.verified_email),
    public.mask_verification_mobile(profile.verified_mobile),
    case when exists (select 1 from public.portfolios where client_id = profile.id)
      then 'Portfolio record available' else 'Imported investor record' end
  from public.profiles profile
  where profile.role = 'client'
    and (
      profile.full_name ilike '%' || normalized_query || '%'
      or profile.verified_email ilike '%' || normalized_query || '%'
      or profile.verified_mobile ilike '%' || normalized_query || '%'
    )
  order by profile.full_name nulls last
  limit 20;
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

create or replace function public.approve_verification_candidate(
  p_request_id uuid,
  p_candidate_token text,
  p_expected_version integer,
  p_reason_code text default null
) returns public.verification_request_status as $$
declare
  request public.verification_requests%rowtype;
  token_payload jsonb;
  profile_id uuid;
begin
  if not public.is_admin() then
    raise exception 'Advisor authorization is required';
  end if;

  begin
    token_payload := extensions.pgp_sym_decrypt(
      decode(p_candidate_token, 'base64'),
      public.verification_candidate_token_secret()
    )::jsonb;
  exception when others then
    raise exception 'Verification candidate is unavailable';
  end;

  if token_payload ->> 'request_id' <> p_request_id::text
      or token_payload ->> 'advisor_user_id' <> auth.uid()::text
      or coalesce((token_payload ->> 'expires_at')::bigint, 0) < extract(epoch from now())::bigint then
    raise exception 'Verification candidate is unavailable';
  end if;

  profile_id := (token_payload ->> 'profile_id')::uuid;
  select * into request
  from public.verification_requests
  where id = p_request_id
  for update;

  if not found
      or request.status <> 'pending_advisor_review'
      or request.version <> p_expected_version then
    raise exception 'Verification request cannot be approved';
  end if;
  if not exists (select 1 from public.profiles where id = profile_id and role = 'client') then
    raise exception 'Verification request cannot be approved';
  end if;
  if exists (
    select 1 from public.investor_account_links
    where (user_id = request.user_id or profile_id = profile_id)
      and link_status = 'active'
  ) then
    raise exception 'Verification request cannot be approved';
  end if;

  insert into public.investor_account_links (
    user_id, profile_id, verification_method, verified_at, linked_at, link_status
  ) values (request.user_id, profile_id, request.method_code, now(), now(), 'active')
  on conflict (user_id, profile_id) do update set
    verification_method = excluded.verification_method,
    verified_at = excluded.verified_at,
    linked_at = excluded.linked_at,
    link_status = 'active';

  update public.user_accounts
  set account_state = 'linked_investor', onboarding_completed = true
  where user_id = request.user_id;

  update public.verification_requests
  set status = 'approved', candidate_profile_id = profile_id,
      resolved_at = now(), version = version + 1
  where id = request.id and version = p_expected_version;
  if not found then
    raise exception 'Verification request changed; refresh and retry';
  end if;

  insert into public.verification_events (
    request_id, subject_user_id, actor_user_id, actor_type, event_type,
    previous_status, new_status, reason_code
  ) values (
    request.id, request.user_id, auth.uid(), 'advisor', 'approved',
    'pending_advisor_review', 'approved', p_reason_code
  );
  return 'approved';
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

create or replace function public.request_more_verification_information(
  p_request_id uuid,
  p_expected_version integer,
  p_reason_code text
) returns public.verification_request_status as $$
declare
  request public.verification_requests%rowtype;
begin
  if not public.is_admin() then
    raise exception 'Advisor authorization is required';
  end if;
  if nullif(trim(p_reason_code), '') is null then
    raise exception 'A reason code is required';
  end if;

  select * into request
  from public.verification_requests
  where id = p_request_id
  for update;
  if not found
      or request.status <> 'pending_advisor_review'
      or request.version <> p_expected_version then
    raise exception 'Verification request cannot be updated';
  end if;

  update public.verification_requests
  set status = 'more_information_required', version = version + 1
  where id = request.id and version = p_expected_version;
  if not found then
    raise exception 'Verification request changed; refresh and retry';
  end if;

  insert into public.verification_events (
    request_id, subject_user_id, actor_user_id, actor_type, event_type,
    previous_status, new_status, reason_code
  ) values (
    request.id, request.user_id, auth.uid(), 'advisor', 'more_information_requested',
    'pending_advisor_review', 'more_information_required', trim(p_reason_code)
  );
  return 'more_information_required';
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

create or replace function public.list_verification_review_queue_filtered(
  p_request_id_query text default null,
  p_status text default null,
  p_method_code text default null
) returns table (
  id uuid,
  method_code text,
  status public.verification_request_status,
  submitted_at timestamptz,
  created_at timestamptz,
  version integer
) as $$
begin
  if not public.is_admin() then
    raise exception 'Advisor authorization is required';
  end if;
  return query
  select request.id, request.method_code, request.status,
         request.submitted_at, request.created_at, request.version
  from public.verification_requests request
  where (nullif(trim(p_request_id_query), '') is null
         or request.id::text ilike '%' || trim(p_request_id_query) || '%')
    and (nullif(trim(p_status), '') is null or request.status::text = trim(p_status))
    and (nullif(trim(p_method_code), '') is null or request.method_code = trim(p_method_code))
  order by request.submitted_at asc nulls last, request.created_at asc;
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

-- Kept for compatibility during Sprint 5. Flutter must use
-- approve_verification_candidate() instead, so profile UUIDs never reach the
-- Advisor UI. This legacy RPC will be removed after the candidate-token flow
-- has proven stable.
comment on function public.approve_verification_request(uuid, uuid, integer, text)
  is 'Deprecated: use approve_verification_candidate with an opaque candidate token.';

revoke all on function public.verification_candidate_token_secret() from public, anon, authenticated, service_role;
revoke all on function public.issue_verification_candidate_token(uuid, uuid, uuid) from public, anon, authenticated, service_role;
revoke all on function public.mask_verification_email(text) from public, anon, authenticated, service_role;
revoke all on function public.mask_verification_mobile(text) from public, anon, authenticated, service_role;
revoke all on function public.get_verification_review(uuid) from public, anon, service_role;
revoke all on function public.search_verification_candidates(uuid, text) from public, anon, service_role;
revoke all on function public.approve_verification_candidate(uuid, text, integer, text) from public, anon, service_role;
revoke all on function public.request_more_verification_information(uuid, integer, text) from public, anon, service_role;
revoke all on function public.list_verification_review_queue_filtered(text, text, text) from public, anon, service_role;

grant execute on function public.get_verification_review(uuid) to authenticated;
grant execute on function public.search_verification_candidates(uuid, text) to authenticated;
grant execute on function public.approve_verification_candidate(uuid, text, integer, text) to authenticated;
grant execute on function public.request_more_verification_information(uuid, integer, text) to authenticated;
grant execute on function public.list_verification_review_queue_filtered(text, text, text) to authenticated;
