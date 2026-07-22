-- Sprint 5.6A: folio-review assignment is the authorization boundary for
-- Advisor review. Existing single-Advisor deployments are assigned
-- automatically; multi-Advisor routing requires a future supervisor workflow.

do $$ begin
  create type public.folio_review_reason_code as enum (
    'FOLIO_OWNERSHIP_CONFIRMED',
    'JOINT_HOLDER_CONFIRMED',
    'GUARDIAN_RELATIONSHIP_CONFIRMED',
    'INVALID_FOLIO',
    'NAME_MISMATCH',
    'PAN_MISMATCH',
    'INSUFFICIENT_DOCUMENTS',
    'JOINT_HOLDER_PROOF_REQUIRED',
    'GUARDIAN_PROOF_REQUIRED',
    'OTHER'
  );
exception when duplicate_object then null; end $$;

create table public.verification_request_assignments (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.verification_requests(id) on delete restrict,
  advisor_account_id uuid not null references public.user_accounts(user_id) on delete restrict,
  assigned_by_account_id uuid references public.user_accounts(user_id) on delete restrict,
  assigned_at timestamptz not null default now(),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index idx_verification_request_assignments_active_request
  on public.verification_request_assignments(request_id) where active;
create index idx_verification_request_assignments_active_advisor
  on public.verification_request_assignments(advisor_account_id, assigned_at desc)
  where active;

create or replace function public.validate_folio_request_assignment()
returns trigger as $$
begin
  if not exists (
    select 1 from public.user_accounts account
    where account.user_id = new.advisor_account_id
      and account.account_state = 'advisor'
  ) then
    raise exception 'Folio review assignments require an Advisor account';
  end if;
  if new.assigned_by_account_id is not null and not exists (
    select 1 from public.user_accounts account
    where account.user_id = new.assigned_by_account_id
      and account.account_state = 'advisor'
  ) then
    raise exception 'Folio review assignments require an Advisor assigner';
  end if;
  if not exists (
    select 1 from public.verification_requests request_row
    where request_row.id = new.request_id and request_row.method_code = 'folio'
  ) then
    raise exception 'Only folio verification requests can be assigned';
  end if;
  return new;
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

create trigger validate_folio_request_assignment
  before insert or update on public.verification_request_assignments
  for each row execute procedure public.validate_folio_request_assignment();

create trigger set_verification_request_assignments_updated_at
  before update on public.verification_request_assignments
  for each row execute procedure public.set_identity_updated_at();

alter table public.verification_request_assignments enable row level security;
revoke all on table public.verification_request_assignments from public, anon, authenticated;

create or replace function public._single_active_advisor_account()
returns uuid as $$
declare v_advisor uuid;
begin
  select account.user_id into v_advisor
  from public.user_accounts account
  where account.account_state = 'advisor'
  order by account.user_id
  limit 1;

  if (select count(*) from public.user_accounts where account_state = 'advisor') <> 1 then
    return null;
  end if;
  return v_advisor;
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

create or replace function public._assert_assigned_folio_advisor(p_request_id uuid)
returns void as $$
begin
  if not public.is_admin() or not exists (
    select 1
    from public.verification_request_assignments assignment
    join public.verification_requests request_row on request_row.id = assignment.request_id
    where assignment.request_id = p_request_id
      and assignment.advisor_account_id = auth.uid()
      and assignment.active
      and request_row.method_code = 'folio'
  ) then
    raise exception 'Folio review is unavailable';
  end if;
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

create or replace function public.normalize_folio_review_reason_code(p_reason text)
returns public.folio_review_reason_code as $$
declare v_reason text := upper(trim(coalesce(p_reason, '')));
begin
  if v_reason = '' then
    raise exception 'A folio review reason code is required';
  end if;
  return v_reason::public.folio_review_reason_code;
exception when invalid_text_representation then
  raise exception 'Invalid folio review reason code';
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

alter table public.verification_events drop constraint if exists verification_events_event_type_check;
alter table public.verification_events add constraint verification_events_event_type_check check (event_type in (
  'created','submitted','approved','rejected','cancelled','expired','revoked','more_information_requested','automatic_linked','pan_submitted','pan_match_assessed',
  'folio_submitted','folio_review_started','folio_information_requested','folio_information_resubmitted','folio_approved','folio_rejected','folio_cancelled','folio_expired','folio_superseded','folio_evidence_changed','folio_grant_revoked','folio_review_reassigned',
  'folio_review_assigned'
));
alter table public.verification_events drop constraint if exists verification_events_check;
alter table public.verification_events add constraint verification_events_check check (
  previous_status is distinct from new_status
  or event_type in ('created','pan_match_assessed','folio_review_assigned','folio_review_reassigned')
);

-- Existing single-Advisor installations retain their current operational
-- behavior. Deployments with zero or multiple Advisors remain intentionally
-- unassigned until a supervisor-routing workflow is introduced.
do $$
declare v_advisor uuid := public._single_active_advisor_account();
begin
  if v_advisor is not null then
    insert into public.verification_request_assignments (
      request_id, advisor_account_id, assigned_by_account_id
    )
    select request_row.id, v_advisor, null
    from public.verification_requests request_row
    where request_row.method_code = 'folio'
      and not exists (
        select 1 from public.verification_request_assignments assignment
        where assignment.request_id = request_row.id and assignment.active
      );

    insert into public.verification_events (
      request_id, subject_user_id, actor_user_id, actor_type, event_type,
      previous_status, new_status, reason_code
    )
    select request_row.id, request_row.user_id, null, 'system',
      'folio_review_assigned', request_row.status, request_row.status,
      'SINGLE_ADVISOR_MIGRATION'
    from public.verification_requests request_row
    join public.verification_request_assignments assignment
      on assignment.request_id = request_row.id and assignment.active
    where request_row.method_code = 'folio'
      and not exists (
        select 1 from public.verification_events event_row
        where event_row.request_id = request_row.id
          and event_row.event_type = 'folio_review_assigned'
          and event_row.reason_code = 'SINGLE_ADVISOR_MIGRATION'
      );
  end if;
end $$;

-- Browser clients use safe RPCs rather than direct verification rows. PAN and
-- other existing verification workflows retain their established Advisor read
-- policy; folio requests require an active assignment.
drop policy if exists "Advisors can view verification requests" on public.verification_requests;
create policy "Advisors can view non-folio verification requests"
  on public.verification_requests for select to authenticated
  using (public.is_admin() and method_code <> 'folio');

drop policy if exists "Advisors can view verification events" on public.verification_events;
create policy "Advisors can view non-folio verification events"
  on public.verification_events for select to authenticated
  using (
    public.is_admin()
    and exists (
      select 1 from public.verification_requests request_row
      where request_row.id = verification_events.request_id
        and request_row.method_code <> 'folio'
    )
  );

drop policy if exists "Advisors can view folio grants" on public.folio_grants;
drop policy if exists "Users can view own folio grants" on public.folio_grants;
drop policy if exists "Advisors can view folio evidence" on public.verification_folio_evidence;
drop policy if exists "Users can view own folio evidence" on public.verification_folio_evidence;

create or replace function public._transition_folio_request(
  p_request_id uuid,
  p_expected_version integer,
  p_action text,
  p_reason text default null
) returns table(request_id uuid,status public.verification_request_status,version integer) as $$
declare
  request_row public.verification_requests%rowtype;
  next_status public.verification_request_status;
  actor text;
  event_name text;
  normalized_reason text;
begin
  select * into request_row from public.verification_requests
  where id = p_request_id for update;
  if not found or request_row.method_code <> 'folio'
      or request_row.version <> p_expected_version then
    raise exception 'Folio request changed or unavailable';
  end if;

  actor := case when public.is_admin() then 'advisor' else 'investor' end;
  if actor = 'advisor' then
    perform public._assert_assigned_folio_advisor(request_row.id);
  elsif request_row.user_id <> auth.uid() then
    raise exception 'Folio request unavailable';
  end if;

  if p_action = 'begin_review' and actor = 'advisor'
      and request_row.status = 'pending_advisor_review' then
    next_status := 'under_review'; event_name := 'folio_review_started';
  elsif p_action = 'more_information' and actor = 'advisor'
      and request_row.status = 'under_review' then
    normalized_reason := public.normalize_folio_review_reason_code(p_reason)::text;
    next_status := 'more_information_required'; event_name := 'folio_information_requested';
  elsif p_action = 'resubmit' and actor = 'investor'
      and request_row.status = 'more_information_required' then
    next_status := 'pending_advisor_review'; event_name := 'folio_information_resubmitted';
  elsif p_action = 'reject' and actor = 'advisor'
      and request_row.status = 'under_review' then
    normalized_reason := public.normalize_folio_review_reason_code(p_reason)::text;
    next_status := 'rejected'; event_name := 'folio_rejected';
  elsif p_action = 'cancel' and actor = 'investor'
      and request_row.status in ('draft','pending_advisor_review','more_information_required') then
    next_status := 'cancelled'; event_name := 'folio_cancelled';
  elsif p_action = 'expire' and actor = 'advisor'
      and request_row.status in ('pending_advisor_review','under_review','more_information_required')
      and request_row.expires_at <= now() then
    next_status := 'expired'; event_name := 'folio_expired'; normalized_reason := 'SYSTEM_EXPIRY';
  else
    raise exception 'Invalid folio lifecycle transition';
  end if;

  update public.verification_requests
  set status = next_status,
      resolved_at = case when next_status in ('rejected','cancelled','expired') then now() else null end,
      version = version + 1
  where id = request_row.id and version = p_expected_version;
  if not found then raise exception 'Folio request changed or unavailable'; end if;

  insert into public.verification_events (
    request_id, subject_user_id, actor_user_id, actor_type, event_type,
    previous_status, new_status, reason_code
  ) values (
    request_row.id, request_row.user_id, auth.uid(), actor, event_name,
    request_row.status, next_status, normalized_reason
  );
  return query select request_row.id, next_status, p_expected_version + 1;
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

create or replace function public.approve_folio_verification(
  p_request_id uuid,
  p_expected_version integer,
  p_reason text
) returns table(request_id uuid,status public.verification_request_status,version integer) as $$
declare
  request_row public.verification_requests%rowtype;
  evidence public.verification_folio_evidence%rowtype;
  linked_profile_id uuid;
  normalized_reason text;
begin
  if not public.is_admin() then raise exception 'Folio approval unavailable'; end if;
  select * into request_row from public.verification_requests
  where id = p_request_id for update;
  if not found or request_row.method_code <> 'folio'
      or request_row.status <> 'under_review'
      or request_row.version <> p_expected_version then
    raise exception 'Folio request cannot be approved';
  end if;
  perform public._assert_assigned_folio_advisor(request_row.id);
  normalized_reason := public.normalize_folio_review_reason_code(p_reason)::text;

  select * into evidence from public.verification_folio_evidence
  where request_id = request_row.id;
  select profile_id into linked_profile_id from public.investor_account_links
  where user_id = request_row.user_id and link_status = 'active';
  if linked_profile_id is null then raise exception 'Folio request cannot be approved'; end if;
  if evidence.holder_relationship = 'JOINT_HOLDER'
      and normalized_reason <> 'JOINT_HOLDER_CONFIRMED' then
    raise exception 'Required relationship review is missing';
  end if;
  if evidence.holder_relationship = 'GUARDIAN_FOR_MINOR'
      and normalized_reason <> 'GUARDIAN_RELATIONSHIP_CONFIRMED' then
    raise exception 'Required relationship review is missing';
  end if;

  insert into public.folio_grants (
    request_id,user_id,profile_id,folio_reference_id,holder_relationship,approved_by
  ) values (
    request_row.id,request_row.user_id,linked_profile_id,evidence.folio_reference_id,
    evidence.holder_relationship,auth.uid()
  );
  update public.verification_requests set status = 'approved', resolved_at = now(),
    version = version + 1 where id = request_row.id and version = p_expected_version;
  if not found then raise exception 'Folio request changed or unavailable'; end if;
  insert into public.verification_events (
    request_id,subject_user_id,actor_user_id,actor_type,event_type,
    previous_status,new_status,reason_code
  ) values (
    request_row.id,request_row.user_id,auth.uid(),'advisor','folio_approved',
    'under_review','approved',normalized_reason
  );
  return query select request_row.id,'approved'::public.verification_request_status,
    p_expected_version + 1;
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

create or replace function public.revoke_folio_grant(
  p_grant_id uuid,
  p_expected_version integer,
  p_reason text
) returns public.folio_grant_status as $$
declare grant_row public.folio_grants%rowtype;
begin
  if not public.is_admin() or nullif(trim(p_reason),'') is null then
    raise exception 'Grant revocation unavailable';
  end if;
  select * into grant_row from public.folio_grants where id = p_grant_id for update;
  if not found or grant_row.status <> 'active' then raise exception 'Grant cannot be revoked'; end if;
  perform public._assert_assigned_folio_advisor(grant_row.request_id);
  update public.folio_grants set status = 'revoked', revoked_at = now(),
    revoked_by = auth.uid(), revocation_reason = trim(p_reason)
  where id = grant_row.id and status = 'active';
  update public.verification_requests set status = 'revoked', version = version + 1
  where id = grant_row.request_id and version = p_expected_version;
  if not found then raise exception 'Folio request changed or unavailable'; end if;
  insert into public.verification_events (
    request_id,subject_user_id,actor_user_id,actor_type,event_type,
    previous_status,new_status,reason_code
  ) values (
    grant_row.request_id,grant_row.user_id,auth.uid(),'advisor','folio_grant_revoked',
    'approved','revoked',trim(p_reason)
  );
  return 'revoked';
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

create or replace function public.submit_folio_verification(
  p_folio_token text,
  p_relationship public.folio_holder_relationship,
  p_idempotency_key uuid
) returns table(request_id uuid,status public.verification_request_status,version integer) as $$
declare
  request_row public.verification_requests%rowtype;
  payload jsonb;
  token_row public.folio_submission_tokens%rowtype;
  advisor_id uuid;
begin
  if auth.uid() is null then raise exception 'Folio verification unavailable'; end if;
  begin
    payload := extensions.pgp_sym_decrypt(decode(p_folio_token,'base64'),
      public.verification_candidate_token_secret())::jsonb;
  exception when others then raise exception 'Folio verification unavailable'; end;
  select * into token_row from public.folio_submission_tokens
  where token_id = (payload->>'token_id')::uuid for update;
  if not found or token_row.user_id <> auth.uid()
      or payload->>'user_id' <> auth.uid()::text
      or token_row.consumed_at is not null or token_row.expires_at <= now() then
    raise exception 'Folio verification unavailable';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text || p_idempotency_key::text, 0));
  select * into request_row from public.verification_requests
  where user_id = auth.uid() and method_code = 'folio'
    and status in ('pending_advisor_review','under_review','more_information_required')
  order by created_at desc limit 1;
  if found then
    return query select request_row.id,request_row.status,request_row.version;
    return;
  end if;
  advisor_id := public._single_active_advisor_account();
  if advisor_id is null then raise exception 'Folio verification is unavailable'; end if;
  update public.folio_submission_tokens set consumed_at = now()
  where token_id = token_row.token_id and consumed_at is null;
  insert into public.verification_requests (user_id,method_code,status,submitted_at,expires_at)
  values (auth.uid(),'folio','pending_advisor_review',now(),now()+interval '30 days')
  returning * into request_row;
  insert into public.verification_folio_evidence (
    request_id,folio_reference_id,holder_relationship,evidence_source
  ) values (
    request_row.id,token_row.folio_reference_id,p_relationship,'INVESTOR_DECLARATION'
  );
  insert into public.verification_request_assignments (
    request_id,advisor_account_id,assigned_by_account_id
  ) values (request_row.id,advisor_id,null);
  insert into public.verification_events (
    request_id,subject_user_id,actor_user_id,actor_type,event_type,
    previous_status,new_status,reason_code
  ) values
    (request_row.id,auth.uid(),auth.uid(),'investor','folio_submitted',null,
      'pending_advisor_review',p_idempotency_key::text),
    (request_row.id,auth.uid(),null,'system','folio_review_assigned',
      'pending_advisor_review','pending_advisor_review','SINGLE_ADVISOR_ASSIGNMENT');
  return query select request_row.id,request_row.status,request_row.version;
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

create or replace function public.get_my_advisor_folio_requests(
  p_page integer default 0,
  p_page_size integer default 25,
  p_status public.verification_request_status default null
) returns table(
  request_id uuid,
  version integer,
  investor_display_label text,
  registrar_display text,
  masked_folio text,
  holder_relationship public.folio_holder_relationship,
  status public.verification_request_status,
  submitted_at timestamptz,
  updated_at timestamptz
) as $$
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'Advisor authorization is required';
  end if;
  if p_page < 0 or p_page_size < 1 or p_page_size > 100 then
    raise exception 'Invalid pagination';
  end if;
  return query
  select request_row.id,request_row.version,
    'Investor request'::text,
    case when folio.registrar = 'KFINTECH' then 'KFintech' else 'CAMS' end,
    public.mask_canonical_folio(folio.normalized_folio_number),
    evidence.holder_relationship,request_row.status,request_row.submitted_at,
    request_row.updated_at
  from public.verification_request_assignments assignment
  join public.verification_requests request_row on request_row.id = assignment.request_id
  join public.verification_folio_evidence evidence on evidence.request_id = request_row.id
  join public.folio_references folio on folio.id = evidence.folio_reference_id
  where assignment.advisor_account_id = auth.uid() and assignment.active
    and request_row.method_code = 'folio'
    and (p_status is null or request_row.status = p_status)
  order by request_row.submitted_at asc nulls last, request_row.created_at asc, request_row.id asc
  limit p_page_size offset p_page * p_page_size;
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

create or replace function public.get_my_advisor_folio_request_detail(p_request_id uuid)
returns table(
  request_id uuid,
  version integer,
  investor_display_label text,
  registrar_display text,
  masked_folio text,
  holder_relationship public.folio_holder_relationship,
  status public.verification_request_status,
  submitted_at timestamptz,
  updated_at timestamptz,
  expires_at timestamptz,
  event_summary jsonb
) as $$
begin
  perform public._assert_assigned_folio_advisor(p_request_id);
  return query
  select request_row.id,request_row.version,
    'Investor request'::text,
    case when folio.registrar = 'KFINTECH' then 'KFintech' else 'CAMS' end,
    public.mask_canonical_folio(folio.normalized_folio_number),
    evidence.holder_relationship,request_row.status,request_row.submitted_at,
    request_row.updated_at,request_row.expires_at,
    coalesce((
      select jsonb_agg(jsonb_build_object(
        'event_type',event_row.event_type,
        'previous_status',event_row.previous_status,
        'new_status',event_row.new_status,
        'reason_code',event_row.reason_code,
        'created_at',event_row.created_at
      ) order by event_row.created_at asc)
      from public.verification_events event_row
      where event_row.request_id = request_row.id
    ), '[]'::jsonb)
  from public.verification_requests request_row
  join public.verification_folio_evidence evidence on evidence.request_id = request_row.id
  join public.folio_references folio on folio.id = evidence.folio_reference_id
  where request_row.id = p_request_id and request_row.method_code = 'folio';
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

create or replace function public.get_folio_request_detail(p_request_id uuid)
returns table(masked_folio_summary text,status public.verification_request_status,submitted_at timestamptz,resolved_at timestamptz,expires_at timestamptz,holder_relationship public.folio_holder_relationship,version integer,event_count bigint) as $$
begin
  if public.is_admin() then
    perform public._assert_assigned_folio_advisor(p_request_id);
  elsif not exists(select 1 from public.verification_requests where id = p_request_id and user_id = auth.uid()) then
    raise exception 'Folio request is unavailable';
  end if;
  return query
  select public.mask_folio_summary(folio.registrar,folio.source_folio_masked),
    request_row.status,request_row.submitted_at,request_row.resolved_at,
    request_row.expires_at,evidence.holder_relationship,request_row.version,
    (select count(*) from public.verification_events event_row where event_row.request_id = request_row.id)
  from public.verification_requests request_row
  join public.verification_folio_evidence evidence on evidence.request_id = request_row.id
  join public.folio_references folio on folio.id = evidence.folio_reference_id
  where request_row.id = p_request_id and request_row.method_code = 'folio';
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

create or replace function public.get_folio_grant_summary(p_request_id uuid)
returns table(grant_status public.folio_grant_status,approved_at timestamptz,revoked_at timestamptz,masked_folio_summary text,holder_relationship public.folio_holder_relationship) as $$
begin
  if public.is_admin() then
    perform public._assert_assigned_folio_advisor(p_request_id);
  elsif not exists(select 1 from public.verification_requests where id = p_request_id and user_id = auth.uid()) then
    raise exception 'Folio grant is unavailable';
  end if;
  return query
  select grant_row.status,grant_row.approved_at,grant_row.revoked_at,
    public.mask_folio_summary(folio.registrar,folio.source_folio_masked),
    grant_row.holder_relationship
  from public.folio_grants grant_row
  join public.folio_references folio on folio.id = grant_row.folio_reference_id
  where grant_row.request_id = p_request_id;
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

-- Generic legacy review projections continue to serve PAN review, but cannot
-- become an assignment bypass for folio requests.
create or replace function public.get_verification_events(p_request_id uuid)
returns table(
  id uuid,
  event_type text,
  previous_status public.verification_request_status,
  new_status public.verification_request_status,
  reason_code text,
  created_at timestamptz
) as $$
declare request_method text;
begin
  if auth.uid() is null then raise exception 'Authentication is required'; end if;
  select method_code into request_method from public.verification_requests where id = p_request_id;
  if request_method is null then raise exception 'Verification history is not available'; end if;
  if request_method = 'folio' and public.is_admin() then
    perform public._assert_assigned_folio_advisor(p_request_id);
  elsif not public.is_admin() and not exists (
    select 1 from public.verification_requests where id = p_request_id and user_id = auth.uid()
  ) then
    raise exception 'Verification history is not available';
  end if;
  return query
  select event_row.id,event_row.event_type,event_row.previous_status,
    event_row.new_status,event_row.reason_code,event_row.created_at
  from public.verification_events event_row
  where event_row.request_id = p_request_id
  order by event_row.created_at asc;
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

create or replace function public.get_verification_review(p_request_id uuid)
returns table (
  id uuid, method_code text, status public.verification_request_status,
  created_at timestamptz, submitted_at timestamptz, resolved_at timestamptz,
  expires_at timestamptz, version integer, retry_of_request_id uuid,
  requester_masked_email text, requester_masked_mobile text,
  masked_pan text, pan_match_result text, pan_conflict_reason text
) as $$
declare request_method text;
begin
  if not public.is_admin() then raise exception 'Advisor authorization is required'; end if;
  select method_code into request_method from public.verification_requests where id = p_request_id;
  if request_method is null then return; end if;
  if request_method = 'folio' then perform public._assert_assigned_folio_advisor(p_request_id); end if;
  return query
  select request_row.id,request_row.method_code,request_row.status,
    request_row.created_at,request_row.submitted_at,request_row.resolved_at,
    request_row.expires_at,request_row.version,request_row.retry_of_request_id,
    public.mask_verification_email(auth_user.email),public.mask_verification_mobile(auth_user.phone),
    evidence.masked_pan,evidence.match_result::text,evidence.conflict_reason::text
  from public.verification_requests request_row
  left join auth.users auth_user on auth_user.id = request_row.user_id
  left join public.verification_pan_evidence evidence on evidence.request_id = request_row.id
  where request_row.id = p_request_id;
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

create or replace function public.list_verification_review_queue_filtered(
  p_request_id_query text default null,
  p_status text default null,
  p_method_code text default null
) returns table (
  id uuid, method_code text, status public.verification_request_status,
  submitted_at timestamptz, created_at timestamptz, version integer,
  masked_pan text, pan_match_result text, pan_conflict_reason text
) as $$
begin
  if not public.is_admin() then raise exception 'Advisor authorization is required'; end if;
  return query
  select request_row.id,request_row.method_code,request_row.status,
    request_row.submitted_at,request_row.created_at,request_row.version,
    evidence.masked_pan,evidence.match_result::text,evidence.conflict_reason::text
  from public.verification_requests request_row
  left join public.verification_pan_evidence evidence on evidence.request_id = request_row.id
  where (nullif(trim(p_request_id_query), '') is null or request_row.id::text ilike '%' || trim(p_request_id_query) || '%')
    and (nullif(trim(p_status), '') is null or request_row.status::text = trim(p_status))
    and (nullif(trim(p_method_code), '') is null or request_row.method_code = trim(p_method_code))
    and (
      request_row.method_code <> 'folio'
      or exists (
        select 1 from public.verification_request_assignments assignment
        where assignment.request_id = request_row.id
          and assignment.advisor_account_id = auth.uid()
          and assignment.active
      )
    )
  order by request_row.submitted_at asc nulls last,request_row.created_at asc;
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

revoke all on function public._single_active_advisor_account(),
  public._assert_assigned_folio_advisor(uuid),
  public.normalize_folio_review_reason_code(text),
  public.validate_folio_request_assignment() from public, anon, authenticated, service_role;
revoke all on function public.get_my_advisor_folio_requests(integer,integer,public.verification_request_status),
  public.get_my_advisor_folio_request_detail(uuid) from public, anon, service_role;
grant execute on function public.get_my_advisor_folio_requests(integer,integer,public.verification_request_status),
  public.get_my_advisor_folio_request_detail(uuid) to authenticated;
