-- Sprint 5.6A.1: a folio request is never handled by a generic verification
-- endpoint.  The dedicated folio RPCs are the only browser-facing lifecycle.
-- Decision lock order is always verification_requests, then the active
-- verification_request_assignments row. Future reassignment code must use the
-- same order before activating or deactivating an assignment.

do $$ begin
  alter type public.folio_review_reason_code add value if not exists 'VERIFIED_SOLE_HOLDER';
  alter type public.folio_review_reason_code add value if not exists 'VERIFIED_JOINT_HOLDER';
  alter type public.folio_review_reason_code add value if not exists 'VERIFIED_GUARDIAN';
  alter type public.folio_review_reason_code add value if not exists 'VERIFIED_AUTHORIZED_RELATIONSHIP';
  alter type public.folio_review_reason_code add value if not exists 'HOLDER_RELATIONSHIP_NOT_PROVEN';
  alter type public.folio_review_reason_code add value if not exists 'DUPLICATE_REQUEST';
  alter type public.folio_review_reason_code add value if not exists 'OTHER_REJECTION';
  alter type public.folio_review_reason_code add value if not exists 'FOLIO_DOCUMENT_REQUIRED';
  alter type public.folio_review_reason_code add value if not exists 'IDENTITY_CLARIFICATION_REQUIRED';
  alter type public.folio_review_reason_code add value if not exists 'ADDITIONAL_INFORMATION_REQUIRED';
exception when duplicate_object then null; end $$;

create or replace function public._reject_generic_folio_request(p_request_id uuid)
returns void as $$
begin
  if exists (
    select 1 from public.verification_requests
    where id = p_request_id and method_code = 'folio'
  ) then
    raise exception using
      errcode = 'PFL01',
      message = 'Use the dedicated folio verification lifecycle';
  end if;
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

-- This helper locks only the assignment. Decision RPCs lock the request first
-- and then call it, establishing the lock order documented above.
create or replace function public._assert_assigned_folio_advisor(p_request_id uuid)
returns void as $$
declare assignment_row public.verification_request_assignments%rowtype;
begin
  if not public.is_admin() then
    raise exception 'Folio review is unavailable';
  end if;
  select assignment.* into assignment_row
  from public.verification_request_assignments assignment
  join public.verification_requests request_row on request_row.id = assignment.request_id
  where assignment.request_id = p_request_id
    and assignment.advisor_account_id = auth.uid()
    and assignment.active
    and request_row.method_code = 'folio'
  for update of assignment;
  if not found then
    raise exception 'Folio review is unavailable';
  end if;
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

create or replace function public.validate_folio_review_reason_code(
  p_action text,
  p_reason text,
  p_relationship public.folio_holder_relationship default null
) returns text as $$
declare reason text := upper(trim(coalesce(p_reason, '')));
begin
  if reason = '' then
    raise exception 'A folio review reason code is required';
  end if;
  perform public.normalize_folio_review_reason_code(reason);
  if p_action = 'approve' then
    if (p_relationship = 'SOLE_HOLDER' and reason <> 'VERIFIED_SOLE_HOLDER')
       or (p_relationship = 'JOINT_HOLDER' and reason <> 'VERIFIED_JOINT_HOLDER')
       or (p_relationship = 'GUARDIAN_FOR_MINOR' and reason not in ('VERIFIED_GUARDIAN', 'VERIFIED_AUTHORIZED_RELATIONSHIP')) then
      raise exception 'Invalid folio approval reason code';
    end if;
  elsif p_action = 'reject' and reason not in (
    'INVALID_FOLIO','NAME_MISMATCH','PAN_MISMATCH','INSUFFICIENT_DOCUMENTS',
    'HOLDER_RELATIONSHIP_NOT_PROVEN','DUPLICATE_REQUEST','OTHER_REJECTION'
  ) then
    raise exception 'Invalid folio rejection reason code';
  elsif p_action = 'more_information' and reason not in (
    'FOLIO_DOCUMENT_REQUIRED','JOINT_HOLDER_PROOF_REQUIRED',
    'GUARDIAN_PROOF_REQUIRED','IDENTITY_CLARIFICATION_REQUIRED',
    'ADDITIONAL_INFORMATION_REQUIRED'
  ) then
    raise exception 'Invalid folio information-request reason code';
  end if;
  return reason;
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

-- Explicit lifecycle functions own all folio transitions and lock the active
-- assignment after the request row. Generic transition RPCs below reject folio.
create or replace function public._transition_folio_request(
  p_request_id uuid, p_expected_version integer, p_action text, p_reason text default null
) returns table(request_id uuid,status public.verification_request_status,version integer) as $$
declare request_row public.verification_requests%rowtype;
  next_status public.verification_request_status;
  actor text;
  event_name text;
  normalized_reason text;
begin
  select * into request_row from public.verification_requests
  where id = p_request_id for update;
  if not found or request_row.method_code <> 'folio' or request_row.version <> p_expected_version then
    raise exception 'Folio request changed or unavailable';
  end if;
  actor := case when public.is_admin() then 'advisor' else 'investor' end;
  if actor = 'advisor' then
    perform public._assert_assigned_folio_advisor(request_row.id);
  elsif request_row.user_id <> auth.uid() then
    raise exception 'Folio request unavailable';
  end if;
  if p_action = 'begin_review' and actor = 'advisor' and request_row.status = 'pending_advisor_review' then
    next_status := 'under_review'; event_name := 'folio_review_started';
  elsif p_action = 'more_information' and actor = 'advisor' and request_row.status = 'under_review' then
    select public.validate_folio_review_reason_code('more_information', p_reason) into normalized_reason;
    next_status := 'more_information_required'; event_name := 'folio_information_requested';
  elsif p_action = 'resubmit' and actor = 'investor' and request_row.status = 'more_information_required' then
    next_status := 'pending_advisor_review'; event_name := 'folio_information_resubmitted';
  elsif p_action = 'reject' and actor = 'advisor' and request_row.status = 'under_review' then
    select public.validate_folio_review_reason_code('reject', p_reason) into normalized_reason;
    next_status := 'rejected'; event_name := 'folio_rejected';
  elsif p_action = 'cancel' and actor = 'investor' and request_row.status in ('draft','pending_advisor_review','more_information_required') then
    next_status := 'cancelled'; event_name := 'folio_cancelled';
  elsif p_action = 'expire' and actor = 'advisor' and request_row.status in ('pending_advisor_review','under_review','more_information_required') and request_row.expires_at <= now() then
    next_status := 'expired'; event_name := 'folio_expired'; normalized_reason := 'SYSTEM_EXPIRY';
  else
    raise exception 'Invalid folio lifecycle transition';
  end if;
  update public.verification_requests set status = next_status,
    resolved_at = case when next_status in ('rejected','cancelled','expired') then now() else null end,
    version = version + 1 where id = request_row.id and version = p_expected_version;
  if not found then raise exception 'Folio request changed or unavailable'; end if;
  insert into public.verification_events (request_id,subject_user_id,actor_user_id,actor_type,event_type,previous_status,new_status,reason_code)
  values (request_row.id,request_row.user_id,auth.uid(),actor,event_name,request_row.status,next_status,normalized_reason);
  return query select request_row.id,next_status,p_expected_version + 1;
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

create or replace function public.approve_folio_verification(
  p_request_id uuid, p_expected_version integer, p_reason text
) returns table(request_id uuid,status public.verification_request_status,version integer) as $$
declare request_row public.verification_requests%rowtype;
  evidence public.verification_folio_evidence%rowtype;
  linked_profile_id uuid;
  normalized_reason text;
begin
  if not public.is_admin() then raise exception 'Folio approval unavailable'; end if;
  select * into request_row from public.verification_requests where id = p_request_id for update;
  if not found or request_row.method_code <> 'folio' or request_row.status <> 'under_review' or request_row.version <> p_expected_version then
    raise exception 'Folio request cannot be approved';
  end if;
  perform public._assert_assigned_folio_advisor(request_row.id);
  select * into evidence from public.verification_folio_evidence where request_id = request_row.id;
  select public.validate_folio_review_reason_code('approve', p_reason, evidence.holder_relationship) into normalized_reason;
  select profile_id into linked_profile_id from public.investor_account_links
    where user_id = request_row.user_id and link_status = 'active';
  if linked_profile_id is null then raise exception 'Folio request cannot be approved'; end if;
  insert into public.folio_grants (request_id,user_id,profile_id,folio_reference_id,holder_relationship,approved_by)
  values (request_row.id,request_row.user_id,linked_profile_id,evidence.folio_reference_id,evidence.holder_relationship,auth.uid());
  update public.verification_requests set status = 'approved', resolved_at = now(), version = version + 1
    where id = request_row.id and version = p_expected_version;
  if not found then raise exception 'Folio request changed or unavailable'; end if;
  insert into public.verification_events (request_id,subject_user_id,actor_user_id,actor_type,event_type,previous_status,new_status,reason_code)
  values (request_row.id,request_row.user_id,auth.uid(),'advisor','folio_approved','under_review','approved',normalized_reason);
  return query select request_row.id,'approved'::public.verification_request_status,p_expected_version + 1;
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

create or replace function public.revoke_folio_grant(
  p_grant_id uuid, p_expected_version integer, p_reason text
) returns public.folio_grant_status as $$
declare grant_row public.folio_grants%rowtype;
  request_row public.verification_requests%rowtype;
begin
  if not public.is_admin() or nullif(trim(p_reason),'') is null then raise exception 'Grant revocation unavailable'; end if;
  select * into grant_row from public.folio_grants where id = p_grant_id;
  if not found or grant_row.status <> 'active' then raise exception 'Grant cannot be revoked'; end if;
  select * into request_row from public.verification_requests where id = grant_row.request_id for update;
  if not found or request_row.version <> p_expected_version then raise exception 'Folio request changed or unavailable'; end if;
  perform public._assert_assigned_folio_advisor(request_row.id);
  select * into grant_row from public.folio_grants where id = p_grant_id for update;
  update public.folio_grants set status = 'revoked', revoked_at = now(), revoked_by = auth.uid(), revocation_reason = trim(p_reason)
    where id = grant_row.id and status = 'active';
  update public.verification_requests set status = 'revoked', version = version + 1 where id = request_row.id and version = p_expected_version;
  if not found then raise exception 'Folio request changed or unavailable'; end if;
  insert into public.verification_events (request_id,subject_user_id,actor_user_id,actor_type,event_type,previous_status,new_status,reason_code)
  values (request_row.id,request_row.user_id,auth.uid(),'advisor','folio_grant_revoked','approved','revoked',trim(p_reason));
  return 'revoked';
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

-- Generic creation can no longer create an evidence-less folio request.
create or replace function public.create_verification_request(p_method_code text)
returns table(request_id uuid,status public.verification_request_status) as $$
begin
  if p_method_code = 'folio' then
    raise exception using errcode = 'PFL01', message = 'Use dedicated folio verification submission';
  end if;
  return query select * from public.create_non_pan_verification_request(p_method_code);
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

-- Generic browse/read contracts are strictly non-folio. Dedicated safe folio
-- projections remain get_my_folio_requests, get_folio_request_detail,
-- get_folio_grant_summary, get_folio_verification_events, and Advisor RPCs.
create or replace function public.get_verification_status()
returns table(id uuid,method_code text,status public.verification_request_status,submitted_at timestamptz,resolved_at timestamptz,expires_at timestamptz,created_at timestamptz,updated_at timestamptz,version integer,masked_pan text,pan_match_result text,pan_conflict_reason text) as $$
begin
  if auth.uid() is null then raise exception 'Authentication is required'; end if;
  return query select request_row.id,request_row.method_code,request_row.status,request_row.submitted_at,request_row.resolved_at,request_row.expires_at,request_row.created_at,request_row.updated_at,request_row.version,evidence.masked_pan,evidence.match_result::text,evidence.conflict_reason::text
  from public.verification_requests request_row
  left join public.verification_pan_evidence evidence on evidence.request_id = request_row.id
  where request_row.user_id = auth.uid() and request_row.method_code <> 'folio'
  order by request_row.created_at desc;
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

create or replace function public.get_verification_events(p_request_id uuid)
returns table(id uuid,event_type text,previous_status public.verification_request_status,new_status public.verification_request_status,reason_code text,created_at timestamptz) as $$
begin
  perform public._reject_generic_folio_request(p_request_id);
  if auth.uid() is null then raise exception 'Authentication is required'; end if;
  if not public.is_admin() and not exists (select 1 from public.verification_requests where id = p_request_id and user_id = auth.uid()) then
    raise exception 'Verification history is not available';
  end if;
  return query select event_row.id,event_row.event_type,event_row.previous_status,event_row.new_status,event_row.reason_code,event_row.created_at
  from public.verification_events event_row where event_row.request_id = p_request_id order by event_row.created_at asc;
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

create or replace function public.get_folio_verification_events(p_request_id uuid)
returns table(id uuid,event_type text,previous_status public.verification_request_status,new_status public.verification_request_status,reason_code text,created_at timestamptz) as $$
begin
  if auth.uid() is null then raise exception 'Authentication is required'; end if;
  if public.is_admin() then
    perform public._assert_assigned_folio_advisor(p_request_id);
  elsif not exists (select 1 from public.verification_requests where id = p_request_id and method_code = 'folio' and user_id = auth.uid()) then
    raise exception 'Folio verification history is not available';
  end if;
  return query select event_row.id,event_row.event_type,event_row.previous_status,event_row.new_status,event_row.reason_code,event_row.created_at
  from public.verification_events event_row where event_row.request_id = p_request_id order by event_row.created_at asc;
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

create or replace function public.list_verification_review_queue()
returns table(id uuid,user_id uuid,method_code text,status public.verification_request_status,submitted_at timestamptz,created_at timestamptz) as $$
begin
  if not public.is_admin() then raise exception 'Advisor authorization is required'; end if;
  return query select request_row.id,request_row.user_id,request_row.method_code,request_row.status,request_row.submitted_at,request_row.created_at
  from public.verification_requests request_row
  where request_row.status = 'pending_advisor_review' and request_row.method_code <> 'folio'
  order by request_row.submitted_at asc;
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

create or replace function public.list_verification_review_queue_filtered(
  p_request_id_query text default null,p_status text default null,p_method_code text default null
) returns table(id uuid,method_code text,status public.verification_request_status,submitted_at timestamptz,created_at timestamptz,version integer,masked_pan text,pan_match_result text,pan_conflict_reason text) as $$
begin
  if not public.is_admin() then raise exception 'Advisor authorization is required'; end if;
  return query select request_row.id,request_row.method_code,request_row.status,request_row.submitted_at,request_row.created_at,request_row.version,evidence.masked_pan,evidence.match_result::text,evidence.conflict_reason::text
  from public.verification_requests request_row
  left join public.verification_pan_evidence evidence on evidence.request_id = request_row.id
  where request_row.method_code <> 'folio'
    and (nullif(trim(p_request_id_query),'') is null or request_row.id::text ilike '%' || trim(p_request_id_query) || '%')
    and (nullif(trim(p_status),'') is null or request_row.status::text = trim(p_status))
    and (nullif(trim(p_method_code),'') is null or request_row.method_code = trim(p_method_code))
  order by request_row.submitted_at asc nulls last,request_row.created_at asc;
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

create or replace function public.get_verification_review(p_request_id uuid)
returns table(id uuid,method_code text,status public.verification_request_status,created_at timestamptz,submitted_at timestamptz,resolved_at timestamptz,expires_at timestamptz,version integer,retry_of_request_id uuid,requester_masked_email text,requester_masked_mobile text,masked_pan text,pan_match_result text,pan_conflict_reason text) as $$
begin
  if not public.is_admin() then raise exception 'Advisor authorization is required'; end if;
  perform public._reject_generic_folio_request(p_request_id);
  return query select request_row.id,request_row.method_code,request_row.status,request_row.created_at,request_row.submitted_at,request_row.resolved_at,request_row.expires_at,request_row.version,request_row.retry_of_request_id,public.mask_verification_email(auth_user.email),public.mask_verification_mobile(auth_user.phone),evidence.masked_pan,evidence.match_result::text,evidence.conflict_reason::text
  from public.verification_requests request_row left join auth.users auth_user on auth_user.id = request_row.user_id
  left join public.verification_pan_evidence evidence on evidence.request_id = request_row.id
  where request_row.id = p_request_id and request_row.method_code <> 'folio';
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

-- Generic lifecycle endpoints preserve their legacy non-folio behavior but
-- fail before any mutable work when a folio request identifier is supplied.
create or replace function public.approve_verification_request(p_request_id uuid,p_profile_id uuid,p_expected_version integer,p_reason_code text default null)
returns public.verification_request_status as $$
declare request_row public.verification_requests%rowtype;
begin
  if not public.is_admin() then raise exception 'Advisor authorization is required'; end if;
  select * into request_row from public.verification_requests where id = p_request_id for update;
  if not found then raise exception 'Verification request cannot be approved'; end if;
  if request_row.method_code = 'folio' then raise exception using errcode='PFL01',message='Use the dedicated folio verification lifecycle'; end if;
  if request_row.status <> 'pending_advisor_review' or request_row.version <> p_expected_version then raise exception 'Verification request cannot be approved'; end if;
  if not exists (select 1 from public.profiles where id = p_profile_id and role = 'client') or exists (select 1 from public.investor_account_links where (user_id = request_row.user_id or profile_id = p_profile_id) and link_status = 'active') then raise exception 'Verification request cannot be approved'; end if;
  insert into public.investor_account_links (user_id,profile_id,verification_method,verified_at,linked_at,link_status) values (request_row.user_id,p_profile_id,request_row.method_code,now(),now(),'active') on conflict (user_id,profile_id) do update set verification_method=excluded.verification_method,verified_at=excluded.verified_at,linked_at=excluded.linked_at,link_status='active';
  update public.user_accounts set account_state='linked_investor',onboarding_completed=true where user_id=request_row.user_id;
  update public.verification_requests set status='approved',candidate_profile_id=p_profile_id,resolved_at=now(),version=version+1 where id=request_row.id and version=p_expected_version;
  insert into public.verification_events (request_id,subject_user_id,actor_user_id,actor_type,event_type,previous_status,new_status,reason_code) values (request_row.id,request_row.user_id,auth.uid(),'advisor','approved','pending_advisor_review','approved',p_reason_code);
  return 'approved';
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

create or replace function public.reject_verification_request(p_request_id uuid,p_expected_version integer,p_reason_code text default null)
returns public.verification_request_status as $$
declare request_row public.verification_requests%rowtype;
begin
  if not public.is_admin() then raise exception 'Advisor authorization is required'; end if;
  select * into request_row from public.verification_requests where id=p_request_id for update;
  if not found then raise exception 'Verification request cannot be rejected'; end if;
  if request_row.method_code='folio' then raise exception using errcode='PFL01',message='Use the dedicated folio verification lifecycle'; end if;
  if request_row.status <> 'pending_advisor_review' or request_row.version <> p_expected_version then raise exception 'Verification request cannot be rejected'; end if;
  update public.verification_requests set status='rejected',resolved_at=now(),version=version+1 where id=request_row.id and version=p_expected_version;
  insert into public.verification_events (request_id,subject_user_id,actor_user_id,actor_type,event_type,previous_status,new_status,reason_code) values(request_row.id,request_row.user_id,auth.uid(),'advisor','rejected','pending_advisor_review','rejected',p_reason_code);
  return 'rejected';
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

create or replace function public.cancel_verification_request(p_request_id uuid,p_expected_version integer)
returns public.verification_request_status as $$
declare request_row public.verification_requests%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication is required'; end if;
  select * into request_row from public.verification_requests where id=p_request_id and user_id=auth.uid() for update;
  if not found then raise exception 'Verification request cannot be cancelled'; end if;
  if request_row.method_code='folio' then raise exception using errcode='PFL01',message='Use the dedicated folio verification lifecycle'; end if;
  if request_row.status not in ('draft','pending_advisor_review') or request_row.version <> p_expected_version then raise exception 'Verification request cannot be cancelled'; end if;
  update public.verification_requests set status='cancelled',resolved_at=now(),version=version+1 where id=request_row.id and version=p_expected_version;
  insert into public.verification_events (request_id,subject_user_id,actor_user_id,actor_type,event_type,previous_status,new_status) values(request_row.id,request_row.user_id,auth.uid(),'investor','cancelled',request_row.status,'cancelled');
  return 'cancelled';
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

create or replace function public.request_more_verification_information(p_request_id uuid,p_expected_version integer,p_reason_code text)
returns public.verification_request_status as $$
declare request_row public.verification_requests%rowtype;
begin
  if not public.is_admin() then raise exception 'Advisor authorization is required'; end if;
  select * into request_row from public.verification_requests where id=p_request_id for update;
  if not found then raise exception 'Verification request cannot be updated'; end if;
  if request_row.method_code='folio' then raise exception using errcode='PFL01',message='Use the dedicated folio verification lifecycle'; end if;
  if nullif(trim(p_reason_code),'') is null or request_row.status <> 'pending_advisor_review' or request_row.version <> p_expected_version then raise exception 'Verification request cannot be updated'; end if;
  update public.verification_requests set status='more_information_required',version=version+1 where id=request_row.id and version=p_expected_version;
  insert into public.verification_events (request_id,subject_user_id,actor_user_id,actor_type,event_type,previous_status,new_status,reason_code) values(request_row.id,request_row.user_id,auth.uid(),'advisor','more_information_requested','pending_advisor_review','more_information_required',trim(p_reason_code));
  return 'more_information_required';
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

create or replace function public.search_verification_candidates(p_request_id uuid,p_query text)
returns table(candidate_token text,candidate_name text,masked_email text,masked_mobile text,profile_summary text) as $$
declare normalized_query text := trim(p_query);
begin
  if not public.is_admin() then raise exception 'Advisor authorization is required'; end if;
  perform public._reject_generic_folio_request(p_request_id);
  if normalized_query is null or length(normalized_query)<2 then raise exception 'Enter at least two characters to search'; end if;
  if not exists(select 1 from public.verification_requests where id=p_request_id and method_code<>'folio' and status in ('pending_advisor_review','more_information_required')) then raise exception 'Verification request is unavailable'; end if;
  return query select public.issue_verification_candidate_token(p_request_id,profile.id,auth.uid()),coalesce(nullif(profile.full_name,''),'Imported investor'),public.mask_verification_email(profile.verified_email),public.mask_verification_mobile(profile.verified_mobile),case when exists(select 1 from public.portfolios where client_id=profile.id) then 'Portfolio record available' else 'Imported investor record' end
  from public.profiles profile where profile.role='client' and (profile.full_name ilike '%'||normalized_query||'%' or profile.verified_email ilike '%'||normalized_query||'%' or profile.verified_mobile ilike '%'||normalized_query||'%') order by profile.full_name nulls last limit 20;
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

-- Candidate tokens are for non-folio identity linking only. The original body
-- is retained for compatibility after the early method guard.
create or replace function public.approve_verification_candidate(p_request_id uuid,p_candidate_token text,p_expected_version integer,p_reason_code text default null)
returns public.verification_request_status as $$
declare request_row public.verification_requests%rowtype; token_payload jsonb; profile_id uuid;
begin
  if not public.is_admin() then raise exception 'Advisor authorization is required'; end if;
  select * into request_row from public.verification_requests where id=p_request_id for update;
  if not found then raise exception 'Verification request cannot be approved'; end if;
  if request_row.method_code='folio' then raise exception using errcode='PFL01',message='Use the dedicated folio verification lifecycle'; end if;
  begin token_payload:=extensions.pgp_sym_decrypt(decode(p_candidate_token,'base64'),public.verification_candidate_token_secret())::jsonb; exception when others then raise exception 'Verification candidate is unavailable'; end;
  if token_payload->>'request_id'<>p_request_id::text or token_payload->>'advisor_user_id'<>auth.uid()::text or coalesce((token_payload->>'expires_at')::bigint,0)<extract(epoch from now())::bigint then raise exception 'Verification candidate is unavailable'; end if;
  profile_id:=(token_payload->>'profile_id')::uuid;
  if request_row.status <> 'pending_advisor_review' or request_row.version <> p_expected_version or not exists(select 1 from public.profiles where id=profile_id and role='client') or exists(select 1 from public.investor_account_links where (user_id=request_row.user_id or profile_id=profile_id) and link_status='active') then raise exception 'Verification request cannot be approved'; end if;
  insert into public.investor_account_links(user_id,profile_id,verification_method,verified_at,linked_at,link_status) values(request_row.user_id,profile_id,request_row.method_code,now(),now(),'active') on conflict(user_id,profile_id) do update set verification_method=excluded.verification_method,verified_at=excluded.verified_at,linked_at=excluded.linked_at,link_status='active';
  update public.user_accounts set account_state='linked_investor',onboarding_completed=true where user_id=request_row.user_id;
  update public.verification_requests set status='approved',candidate_profile_id=profile_id,resolved_at=now(),version=version+1 where id=request_row.id and version=p_expected_version;
  insert into public.verification_events(request_id,subject_user_id,actor_user_id,actor_type,event_type,previous_status,new_status,reason_code) values(request_row.id,request_row.user_id,auth.uid(),'advisor','approved','pending_advisor_review','approved',p_reason_code);
  return 'approved';
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

revoke all on function public._reject_generic_folio_request(uuid),
  public.validate_folio_review_reason_code(text,text,public.folio_holder_relationship),
  public._assert_assigned_folio_advisor(uuid) from public, anon, authenticated, service_role;
revoke all on function public.create_non_pan_verification_request(text) from public, anon, authenticated, service_role;
revoke all on table public.verification_folio_evidence, public.folio_grants,
  public.verification_request_assignments, public.folio_references from public, anon, authenticated;
revoke all on function public.get_folio_verification_events(uuid) from public, anon, service_role;
grant execute on function public.get_folio_verification_events(uuid) to authenticated;
