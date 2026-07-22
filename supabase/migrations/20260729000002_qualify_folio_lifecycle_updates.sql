-- Sprint 5.6A runtime correction. Table aliases keep output-column names from
-- RETURNS TABLE (notably status and version) distinct from table columns.

create or replace function public._transition_folio_request(
  p_request_id uuid,
  p_expected_version integer,
  p_action text,
  p_reason text default null
) returns table(
  request_id uuid,
  status public.verification_request_status,
  version integer
) as $$
declare
  request_row public.verification_requests%rowtype;
  next_status public.verification_request_status;
  actor text;
  event_name text;
  normalized_reason text;
begin
  select request_record.* into request_row
  from public.verification_requests as request_record
  where request_record.id = p_request_id
  for update;
  if not found
      or request_row.method_code <> 'folio'
      or request_row.version <> p_expected_version then
    raise exception 'Folio request changed or unavailable';
  end if;

  actor := case when public.is_admin() then 'advisor' else 'investor' end;
  if actor = 'advisor' then
    -- The request is locked before the active assignment row.
    perform public._assert_assigned_folio_advisor(request_row.id);
  elsif request_row.user_id <> auth.uid() then
    raise exception 'Folio request unavailable';
  end if;

  if p_action = 'begin_review' and actor = 'advisor'
      and request_row.status = 'pending_advisor_review' then
    next_status := 'under_review';
    event_name := 'folio_review_started';
  elsif p_action = 'more_information' and actor = 'advisor'
      and request_row.status = 'under_review' then
    select public.validate_folio_review_reason_code('more_information', p_reason)
      into normalized_reason;
    next_status := 'more_information_required';
    event_name := 'folio_information_requested';
  elsif p_action = 'resubmit' and actor = 'investor'
      and request_row.status = 'more_information_required' then
    next_status := 'pending_advisor_review';
    event_name := 'folio_information_resubmitted';
  elsif p_action = 'reject' and actor = 'advisor'
      and request_row.status = 'under_review' then
    select public.validate_folio_review_reason_code('reject', p_reason)
      into normalized_reason;
    next_status := 'rejected';
    event_name := 'folio_rejected';
  elsif p_action = 'cancel' and actor = 'investor'
      and request_row.status in ('draft', 'pending_advisor_review', 'more_information_required') then
    next_status := 'cancelled';
    event_name := 'folio_cancelled';
  elsif p_action = 'expire' and actor = 'advisor'
      and request_row.status in ('pending_advisor_review', 'under_review', 'more_information_required')
      and request_row.expires_at <= now() then
    next_status := 'expired';
    event_name := 'folio_expired';
    normalized_reason := 'SYSTEM_EXPIRY';
  else
    raise exception 'Invalid folio lifecycle transition';
  end if;

  update public.verification_requests as request_record
  set status = next_status,
      resolved_at = case
        when next_status in ('rejected', 'cancelled', 'expired') then now()
        else null
      end,
      version = request_record.version + 1
  where request_record.id = request_row.id
    and request_record.version = p_expected_version;
  if not found then
    raise exception 'Folio request changed or unavailable';
  end if;

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
) returns table(
  request_id uuid,
  status public.verification_request_status,
  version integer
) as $$
declare
  request_row public.verification_requests%rowtype;
  evidence_row public.verification_folio_evidence%rowtype;
  linked_profile_id uuid;
  normalized_reason text;
begin
  if not public.is_admin() then
    raise exception 'Folio approval unavailable';
  end if;
  select request_record.* into request_row
  from public.verification_requests as request_record
  where request_record.id = p_request_id
  for update;
  if not found
      or request_row.method_code <> 'folio'
      or request_row.status <> 'under_review'
      or request_row.version <> p_expected_version then
    raise exception 'Folio request cannot be approved';
  end if;
  perform public._assert_assigned_folio_advisor(request_row.id);
  select evidence_record.* into evidence_row
  from public.verification_folio_evidence as evidence_record
  where evidence_record.request_id = request_row.id;
  select public.validate_folio_review_reason_code(
    'approve', p_reason, evidence_row.holder_relationship
  ) into normalized_reason;
  select link_record.profile_id into linked_profile_id
  from public.investor_account_links as link_record
  where link_record.user_id = request_row.user_id
    and link_record.link_status = 'active';
  if linked_profile_id is null then
    raise exception 'Folio request cannot be approved';
  end if;

  insert into public.folio_grants (
    request_id, user_id, profile_id, folio_reference_id,
    holder_relationship, approved_by
  ) values (
    request_row.id, request_row.user_id, linked_profile_id,
    evidence_row.folio_reference_id, evidence_row.holder_relationship, auth.uid()
  );
  update public.verification_requests as request_record
  set status = 'approved',
      resolved_at = now(),
      version = request_record.version + 1
  where request_record.id = request_row.id
    and request_record.version = p_expected_version;
  if not found then
    raise exception 'Folio request changed or unavailable';
  end if;
  insert into public.verification_events (
    request_id, subject_user_id, actor_user_id, actor_type, event_type,
    previous_status, new_status, reason_code
  ) values (
    request_row.id, request_row.user_id, auth.uid(), 'advisor',
    'folio_approved', 'under_review', 'approved', normalized_reason
  );
  return query select request_row.id,
    'approved'::public.verification_request_status,
    p_expected_version + 1;
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

create or replace function public.revoke_folio_grant(
  p_grant_id uuid,
  p_expected_version integer,
  p_reason text
) returns public.folio_grant_status as $$
declare
  grant_row public.folio_grants%rowtype;
  request_row public.verification_requests%rowtype;
begin
  if not public.is_admin() or nullif(trim(p_reason), '') is null then
    raise exception 'Grant revocation unavailable';
  end if;
  select grant_record.* into grant_row
  from public.folio_grants as grant_record
  where grant_record.id = p_grant_id;
  if not found or grant_row.status <> 'active' then
    raise exception 'Grant cannot be revoked';
  end if;
  select request_record.* into request_row
  from public.verification_requests as request_record
  where request_record.id = grant_row.request_id
  for update;
  if not found or request_row.version <> p_expected_version then
    raise exception 'Folio request changed or unavailable';
  end if;
  perform public._assert_assigned_folio_advisor(request_row.id);
  select grant_record.* into grant_row
  from public.folio_grants as grant_record
  where grant_record.id = p_grant_id
  for update;
  update public.folio_grants as grant_record
  set status = 'revoked',
      revoked_at = now(),
      revoked_by = auth.uid(),
      revocation_reason = trim(p_reason)
  where grant_record.id = grant_row.id
    and grant_record.status = 'active';
  update public.verification_requests as request_record
  set status = 'revoked',
      version = request_record.version + 1
  where request_record.id = request_row.id
    and request_record.version = p_expected_version;
  if not found then
    raise exception 'Folio request changed or unavailable';
  end if;
  insert into public.verification_events (
    request_id, subject_user_id, actor_user_id, actor_type, event_type,
    previous_status, new_status, reason_code
  ) values (
    request_row.id, request_row.user_id, auth.uid(), 'advisor',
    'folio_grant_revoked', 'approved', 'revoked', trim(p_reason)
  );
  return 'revoked';
end;
$$ language plpgsql security definer set search_path = public, pg_temp;
