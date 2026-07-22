-- Sprint 4 Workstream 2B: auditable investor-link verification foundation.
-- Requests and events are append-only from the browser's perspective; only
-- narrowly scoped SECURITY DEFINER RPCs may change verification lifecycle or
-- investor-account links.

create type public.verification_request_status as enum (
  'draft',
  'pending_advisor_review',
  'approved',
  'rejected',
  'cancelled',
  'expired'
);

create table public.verification_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.user_accounts(user_id) on delete cascade,
  method_code text not null check (method_code in (
    'verified_email', 'verified_mobile', 'pan', 'folio', 'advisor_assisted',
    'otp', 'document_upload'
  )),
  status public.verification_request_status not null default 'draft',
  candidate_profile_id uuid references public.profiles(id) on delete restrict,
  submitted_at timestamptz,
  resolved_at timestamptz,
  expires_at timestamptz,
  retry_of_request_id uuid references public.verification_requests(id) on delete restrict,
  version integer not null default 1 check (version > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- A person cannot operate multiple open requests concurrently. Candidate
-- identity is never exposed through the investor-facing RPC projection.
create unique index idx_verification_requests_one_open_per_user
  on public.verification_requests(user_id)
  where status in ('draft', 'pending_advisor_review');
create index idx_verification_requests_queue
  on public.verification_requests(status, submitted_at);
create index idx_verification_requests_user
  on public.verification_requests(user_id, created_at desc);

create table public.verification_events (
  id uuid primary key default gen_random_uuid(),
  request_id uuid references public.verification_requests(id) on delete restrict,
  subject_user_id uuid not null references public.user_accounts(user_id) on delete restrict,
  actor_user_id uuid references public.user_accounts(user_id) on delete restrict,
  actor_type text not null check (actor_type in ('investor', 'advisor', 'system', 'service')),
  event_type text not null check (event_type in (
    'created', 'submitted', 'approved', 'rejected', 'cancelled', 'expired',
    'revoked', 'more_information_requested', 'automatic_linked'
  )),
  previous_status public.verification_request_status,
  new_status public.verification_request_status,
  reason_code text,
  created_at timestamptz not null default now(),
  check (previous_status is distinct from new_status or event_type = 'created')
);
create index idx_verification_events_request
  on public.verification_events(request_id, created_at);
create index idx_verification_events_subject
  on public.verification_events(subject_user_id, created_at desc);

create trigger set_verification_requests_updated_at
  before update on public.verification_requests
  for each row execute procedure public.set_identity_updated_at();

alter table public.verification_requests enable row level security;
alter table public.verification_events enable row level security;

-- The existing broad Advisor write policies would allow direct link/account
-- mutation outside the approval audit trail. Advisors retain read access; all
-- privileged writes now use the RPCs below.
drop policy if exists "Advisors have full access to user accounts" on public.user_accounts;
create policy "Advisors can view user accounts"
  on public.user_accounts for select to authenticated
  using (public.is_admin());

drop policy if exists "Advisors have full access to investor links" on public.investor_account_links;
create policy "Advisors can view investor links"
  on public.investor_account_links for select to authenticated
  using (public.is_admin());

create policy "Users can view own verification requests"
  on public.verification_requests for select to authenticated
  using (user_id = auth.uid());
create policy "Advisors can view verification requests"
  on public.verification_requests for select to authenticated
  using (public.is_admin());
create policy "Users can view own verification events"
  on public.verification_events for select to authenticated
  using (subject_user_id = auth.uid());
create policy "Advisors can view verification events"
  on public.verification_events for select to authenticated
  using (public.is_admin());

create or replace function public.create_verification_request(p_method_code text)
returns table (request_id uuid, status public.verification_request_status) as $$
declare
  account public.user_accounts%rowtype;
  created_request public.verification_requests%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication is required';
  end if;
  select * into account from public.user_accounts
  where user_id = auth.uid() for update;
  if not found or account.account_state <> 'link_pending' then
    raise exception 'Verification is not available for this account';
  end if;
  if exists (select 1 from public.investor_account_links
             where user_id = auth.uid() and link_status = 'active') then
    raise exception 'Verification is not available for this account';
  end if;
  if p_method_code not in ('verified_email', 'verified_mobile', 'pan', 'folio',
                           'advisor_assisted', 'otp', 'document_upload') then
    raise exception 'Verification method is not available';
  end if;

  insert into public.verification_requests (user_id, method_code, status, submitted_at)
  values (auth.uid(), p_method_code, 'pending_advisor_review', now())
  returning * into created_request;

  insert into public.verification_events (
    request_id, subject_user_id, actor_user_id, actor_type, event_type,
    previous_status, new_status
  ) values
    (created_request.id, auth.uid(), auth.uid(), 'investor', 'created', null, 'draft'),
    (created_request.id, auth.uid(), auth.uid(), 'investor', 'submitted',
      'draft', 'pending_advisor_review');

  return query select created_request.id, created_request.status;
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

create or replace function public.get_verification_status()
returns table (
  id uuid, method_code text, status public.verification_request_status,
  submitted_at timestamptz, resolved_at timestamptz, expires_at timestamptz,
  created_at timestamptz, updated_at timestamptz, version integer
) as $$
begin
  if auth.uid() is null then raise exception 'Authentication is required'; end if;
  return query
  select request.id, request.method_code, request.status, request.submitted_at,
         request.resolved_at, request.expires_at, request.created_at, request.updated_at, request.version
  from public.verification_requests request
  where request.user_id = auth.uid()
  order by request.created_at desc;
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

create or replace function public.get_verification_events(p_request_id uuid)
returns table (
  id uuid, event_type text, previous_status public.verification_request_status,
  new_status public.verification_request_status, reason_code text, created_at timestamptz
) as $$
begin
  if auth.uid() is null then raise exception 'Authentication is required'; end if;
  if not public.is_admin() and not exists (
    select 1 from public.verification_requests where id = p_request_id and user_id = auth.uid()
  ) then raise exception 'Verification history is not available'; end if;
  return query select event.id, event.event_type, event.previous_status,
    event.new_status, event.reason_code, event.created_at
  from public.verification_events event where event.request_id = p_request_id
  order by event.created_at asc;
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

create or replace function public.list_verification_review_queue()
returns table (
  id uuid, user_id uuid, method_code text, status public.verification_request_status,
  submitted_at timestamptz, created_at timestamptz
) as $$
begin
  if not public.is_admin() then raise exception 'Advisor authorization is required'; end if;
  return query select request.id, request.user_id, request.method_code,
    request.status, request.submitted_at, request.created_at
  from public.verification_requests request
  where request.status = 'pending_advisor_review'
  order by request.submitted_at asc;
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

create or replace function public.approve_verification_request(
  p_request_id uuid, p_profile_id uuid, p_expected_version integer,
  p_reason_code text default null
) returns public.verification_request_status as $$
declare
  request public.verification_requests%rowtype;
begin
  if not public.is_admin() then raise exception 'Advisor authorization is required'; end if;
  select * into request from public.verification_requests where id = p_request_id for update;
  if not found or request.status <> 'pending_advisor_review' or request.version <> p_expected_version then
    raise exception 'Verification request cannot be approved';
  end if;
  if not exists (select 1 from public.profiles where id = p_profile_id and role = 'client') then
    raise exception 'Verification request cannot be approved';
  end if;
  if exists (select 1 from public.investor_account_links
             where (user_id = request.user_id or profile_id = p_profile_id)
               and link_status = 'active') then
    raise exception 'Verification request cannot be approved';
  end if;

  insert into public.investor_account_links (
    user_id, profile_id, verification_method, verified_at, linked_at, link_status
  ) values (request.user_id, p_profile_id, request.method_code, now(), now(), 'active')
  on conflict (user_id, profile_id) do update set
    verification_method = excluded.verification_method,
    verified_at = excluded.verified_at,
    linked_at = excluded.linked_at,
    link_status = 'active';

  update public.user_accounts set account_state = 'linked_investor', onboarding_completed = true
  where user_id = request.user_id;
  update public.verification_requests set status = 'approved', candidate_profile_id = p_profile_id,
    resolved_at = now(), version = version + 1 where id = request.id and version = p_expected_version;
  if not found then raise exception 'Verification request changed; refresh and retry'; end if;
  insert into public.verification_events (
    request_id, subject_user_id, actor_user_id, actor_type, event_type,
    previous_status, new_status, reason_code
  ) values (request.id, request.user_id, auth.uid(), 'advisor', 'approved',
    'pending_advisor_review', 'approved', p_reason_code);
  return 'approved';
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

create or replace function public.reject_verification_request(
  p_request_id uuid, p_expected_version integer, p_reason_code text default null
) returns public.verification_request_status as $$
declare request public.verification_requests%rowtype;
begin
  if not public.is_admin() then raise exception 'Advisor authorization is required'; end if;
  select * into request from public.verification_requests where id = p_request_id for update;
  if not found or request.status <> 'pending_advisor_review' or request.version <> p_expected_version then
    raise exception 'Verification request cannot be rejected'; end if;
  update public.verification_requests set status = 'rejected', resolved_at = now(), version = version + 1
  where id = request.id and version = p_expected_version;
  if not found then raise exception 'Verification request changed; refresh and retry'; end if;
  insert into public.verification_events (request_id, subject_user_id, actor_user_id,
    actor_type, event_type, previous_status, new_status, reason_code)
  values (request.id, request.user_id, auth.uid(), 'advisor', 'rejected',
    'pending_advisor_review', 'rejected', p_reason_code);
  return 'rejected';
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

create or replace function public.cancel_verification_request(p_request_id uuid, p_expected_version integer)
returns public.verification_request_status as $$
declare request public.verification_requests%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication is required'; end if;
  select * into request from public.verification_requests
  where id = p_request_id and user_id = auth.uid() for update;
  if not found or request.status not in ('draft', 'pending_advisor_review') or request.version <> p_expected_version then
    raise exception 'Verification request cannot be cancelled'; end if;
  update public.verification_requests set status = 'cancelled', resolved_at = now(), version = version + 1
  where id = request.id and version = p_expected_version;
  if not found then raise exception 'Verification request changed; refresh and retry'; end if;
  insert into public.verification_events (request_id, subject_user_id, actor_user_id,
    actor_type, event_type, previous_status, new_status)
  values (request.id, request.user_id, auth.uid(), 'investor', 'cancelled',
    request.status, 'cancelled');
  return 'cancelled';
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

-- Revocation is also server-side and immediately restores the Link Pending
-- experience, so existing portfolio RLS rejects further investor reads.
create or replace function public.revoke_investor_link(p_link_id uuid, p_reason_code text)
returns void as $$
declare link public.investor_account_links%rowtype;
begin
  if not public.is_admin() then raise exception 'Advisor authorization is required'; end if;
  select * into link from public.investor_account_links where id = p_link_id for update;
  if not found or link.link_status <> 'active' then raise exception 'Link cannot be revoked'; end if;
  update public.investor_account_links set link_status = 'revoked' where id = link.id;
  update public.user_accounts set account_state = 'link_pending', onboarding_completed = true
  where user_id = link.user_id;
  insert into public.verification_events (subject_user_id, actor_user_id, actor_type,
    event_type, reason_code) values (link.user_id, auth.uid(), 'advisor', 'revoked', p_reason_code);
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

revoke all on function public.create_verification_request(text) from public, anon, service_role;
revoke all on function public.get_verification_status() from public, anon, service_role;
revoke all on function public.get_verification_events(uuid) from public, anon, service_role;
revoke all on function public.list_verification_review_queue() from public, anon, service_role;
revoke all on function public.approve_verification_request(uuid, uuid, integer, text) from public, anon, service_role;
revoke all on function public.reject_verification_request(uuid, integer, text) from public, anon, service_role;
revoke all on function public.cancel_verification_request(uuid, integer) from public, anon, service_role;
revoke all on function public.revoke_investor_link(uuid, text) from public, anon, service_role;
grant execute on function public.create_verification_request(text) to authenticated;
grant execute on function public.get_verification_status() to authenticated;
grant execute on function public.get_verification_events(uuid) to authenticated;
grant execute on function public.list_verification_review_queue() to authenticated;
grant execute on function public.approve_verification_request(uuid, uuid, integer, text) to authenticated;
grant execute on function public.reject_verification_request(uuid, integer, text) to authenticated;
grant execute on function public.cancel_verification_request(uuid, integer) to authenticated;
grant execute on function public.revoke_investor_link(uuid, text) to authenticated;
