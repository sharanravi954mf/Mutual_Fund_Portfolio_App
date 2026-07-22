-- Sprint 5.2 release blockers: raw registrar PAN values must not persist in
-- statements, same-PAN submissions are serialized, and approval only accepts
-- current valid PAN records.

alter table public.cams_statements
  drop column if exists pan_no,
  drop column if exists joint1_pan,
  drop column if exists joint2_pan,
  drop column if exists guard_pan;

create or replace function public.process_cams_records(records jsonb)
returns void as $$
declare
  rec jsonb;
  p_id uuid;
  f_id uuid;
  port_id uuid;
  existing_st_id uuid;
  existing_tx_id uuid;
  normalized_pan text;
  pan_hmac bytea;
  registrar_source text;
begin
  for rec in select * from jsonb_array_elements(records) loop
    select id into existing_st_id from public.cams_statements
    where foliochk = (rec->>'foliochk')
      and product = (rec->>'product')
      and rep_date = (rec->>'rep_date')::date
      and clos_bal = (rec->>'clos_bal')::numeric
      and rupee_bal = (rec->>'rupee_bal')::numeric
    limit 1;

    if existing_st_id is null then
      insert into public.cams_statements (
        foliochk, inv_name, address1, address2, address3, city, pincode,
        product, sch_name, rep_date, clos_bal, rupee_bal, email, mobile_no,
        bank_name, branch, ac_type, ac_no, ifsc_code, nom_name, relation, nom_percen
      ) values (
        rec->>'foliochk', rec->>'inv_name', rec->>'address1', rec->>'address2', rec->>'address3', rec->>'city', rec->>'pincode',
        rec->>'product', rec->>'sch_name', (rec->>'rep_date')::date, (rec->>'clos_bal')::numeric, (rec->>'rupee_bal')::numeric,
        rec->>'email', rec->>'mobile_no', rec->>'bank_name', rec->>'branch', rec->>'ac_type', rec->>'ac_no', rec->>'ifsc_code',
        rec->>'nom_name', rec->>'relation', (rec->>'nom_percen')::numeric
      );
    end if;

    normalized_pan := public.normalize_pan(rec->>'clientPan');
    if normalized_pan is null then
      raise exception 'Imported record contains an invalid PAN';
    end if;
    pan_hmac := extensions.hmac(normalized_pan, public.pan_lookup_hmac_key(), 'sha256');
    perform pg_advisory_xact_lock(hashtextextended(encode(pan_hmac, 'hex'), 0));
    registrar_source := case upper(coalesce(rec->>'registrar', ''))
      when 'KFINTECH' then 'KFINTECH'
      else 'CAMS'
    end;

    select pan_record.profile_id into p_id
    from public.profile_pan_records as pan_record
    where pan_record.pan_lookup_hmac = pan_hmac
      and pan_record.status in ('OBSERVED', 'VERIFIED')
    order by pan_record.created_at asc
    limit 1;

    if p_id is null then
      insert into public.profiles (id, full_name, role)
      values (gen_random_uuid(), rec->>'investorName', 'client')
      returning id into p_id;
    end if;

    insert into public.profile_pan_records (
      profile_id, pan_ciphertext, pan_lookup_hmac, masked_pan, source, source_system, status
    ) values (
      p_id,
      extensions.pgp_sym_encrypt(normalized_pan, public.pan_encryption_key(), 'cipher-algo=aes256, compress-algo=0'),
      pan_hmac, public.mask_pan(normalized_pan), 'IMPORT', registrar_source, 'OBSERVED'
    ) on conflict (profile_id, pan_lookup_hmac) where pan_lookup_hmac is not null do nothing;

    insert into public.mutual_funds (scheme_code, scheme_name, fund_house, category, current_nav, nav_date)
    values (rec->>'schemeCode', rec->>'schemeName', coalesce(rec->>'fundHouse', 'Mutual Fund'),
      coalesce(rec->>'category', 'Mutual Fund'), (rec->>'nav')::numeric, (rec->>'date')::date)
    on conflict (scheme_code) do update set
      scheme_name = excluded.scheme_name, current_nav = excluded.current_nav, nav_date = excluded.nav_date
    returning id into f_id;

    select id into port_id from public.portfolios where client_id = p_id limit 1;
    if port_id is null then
      insert into public.portfolios (client_id, total_invested_value, current_market_value)
      values (p_id, 0.00, 0.00) returning id into port_id;
    end if;
    select id into existing_tx_id from public.transactions
    where portfolio_id = port_id and mutual_fund_id = f_id and transaction_type = (rec->>'transactionType')
      and units = (rec->>'units')::numeric and amount = (rec->>'amount')::numeric
      and execution_date = (rec->>'date')::date limit 1;
    if existing_tx_id is null then
      insert into public.transactions (portfolio_id, mutual_fund_id, transaction_type, units, nav_at_transaction, amount, execution_date)
      values (port_id, f_id, rec->>'transactionType', (rec->>'units')::numeric,
        (rec->>'nav')::numeric, (rec->>'amount')::numeric, (rec->>'date')::date);
      perform public.recalculate_portfolio_value(port_id);
    end if;
  end loop;
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

create or replace function public.submit_pan_verification(p_pan text)
returns table (request_id uuid, status public.verification_request_status, masked_pan text,
  match_result public.verification_match_result, conflict_reason public.verification_conflict_reason) as $$
declare
  v_account public.user_accounts%rowtype;
  v_request public.verification_requests%rowtype;
  v_normalized_pan text;
  v_pan_hmac bytea;
  v_profile_count integer;
  v_conflict public.verification_conflict_reason := 'NONE';
  v_match public.verification_match_result := 'NO_MATCH';
begin
  if auth.uid() is null then raise exception 'Authentication is required'; end if;
  v_normalized_pan := public.normalize_pan(p_pan);
  if v_normalized_pan is null then raise exception 'PAN format is invalid'; end if;
  select * into v_account from public.user_accounts as account where account.user_id = auth.uid() for update;
  if not found or v_account.account_state <> 'link_pending' then raise exception 'PAN verification is not available for this account'; end if;
  if exists (select 1 from public.investor_account_links as link where link.user_id = auth.uid() and link.link_status = 'active') then raise exception 'PAN verification is not available for this account'; end if;
  if exists (select 1 from public.verification_requests as open_request where open_request.user_id = auth.uid() and open_request.status in ('draft', 'pending_advisor_review', 'more_information_required')) then raise exception 'A verification request is already in progress'; end if;
  v_pan_hmac := extensions.hmac(v_normalized_pan, public.pan_lookup_hmac_key(), 'sha256');
  -- A transaction-scoped keyed lock makes duplicate classification deterministic
  -- without exposing or persisting the PAN outside encrypted/HMAC storage.
  perform pg_advisory_xact_lock(hashtextextended(encode(v_pan_hmac, 'hex'), 0));
  select count(distinct pan_record.profile_id) into v_profile_count from public.profile_pan_records as pan_record
  where pan_record.pan_lookup_hmac = v_pan_hmac and pan_record.status in ('OBSERVED', 'VERIFIED');
  v_match := case when v_profile_count = 0 then 'NO_MATCH'::public.verification_match_result when v_profile_count = 1 then 'SINGLE_MATCH'::public.verification_match_result else 'MULTIPLE_MATCH'::public.verification_match_result end;
  if exists (select 1 from public.profile_pan_records as pan_record join public.investor_account_links as active_link on active_link.profile_id = pan_record.profile_id where pan_record.pan_lookup_hmac = v_pan_hmac and pan_record.status in ('OBSERVED', 'VERIFIED') and active_link.link_status = 'active') then
    v_conflict := 'ALREADY_VERIFIED';
  elsif exists (select 1 from public.verification_pan_evidence as evidence join public.verification_requests as pending_request on pending_request.id = evidence.request_id where evidence.pan_lookup_hmac = v_pan_hmac and pending_request.user_id <> auth.uid() and pending_request.status in ('pending_advisor_review', 'more_information_required')) then
    v_conflict := 'PENDING_DUPLICATE';
  end if;
  insert into public.verification_requests (user_id, method_code, status, submitted_at) values (auth.uid(), 'pan', 'pending_advisor_review', now()) returning * into v_request;
  insert into public.verification_pan_evidence (request_id, pan_ciphertext, pan_lookup_hmac, masked_pan, match_result, conflict_reason)
  values (v_request.id, extensions.pgp_sym_encrypt(v_normalized_pan, public.pan_encryption_key(), 'cipher-algo=aes256, compress-algo=0'), v_pan_hmac, public.mask_pan(v_normalized_pan), v_match, v_conflict);
  insert into public.verification_events (request_id, subject_user_id, actor_user_id, actor_type, event_type, previous_status, new_status)
  values (v_request.id, auth.uid(), auth.uid(), 'investor', 'created', null, 'draft'),
    (v_request.id, auth.uid(), auth.uid(), 'investor', 'pan_submitted', 'draft', 'pending_advisor_review'),
    (v_request.id, auth.uid(), null, 'system', 'pan_match_assessed', 'pending_advisor_review', 'pending_advisor_review');
  return query select v_request.id, v_request.status, public.mask_pan(v_normalized_pan), v_match, v_conflict;
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

create or replace function public.approve_pan_verification_candidate(
  p_request_id uuid, p_candidate_token text, p_expected_version integer, p_reason_code text default null
) returns public.verification_request_status as $$
declare
  v_request public.verification_requests%rowtype;
  v_token_payload jsonb;
  v_profile_id uuid;
  v_evidence public.verification_pan_evidence%rowtype;
  v_matching_record_id uuid;
begin
  if not public.is_admin() then raise exception 'Advisor authorization is required'; end if;
  begin v_token_payload := extensions.pgp_sym_decrypt(decode(p_candidate_token, 'base64'), public.verification_candidate_token_secret())::jsonb;
  exception when others then raise exception 'Verification candidate is unavailable'; end;
  if v_token_payload ->> 'request_id' <> p_request_id::text or v_token_payload ->> 'advisor_user_id' <> auth.uid()::text or coalesce((v_token_payload ->> 'expires_at')::bigint, 0) < extract(epoch from now())::bigint then raise exception 'Verification candidate is unavailable'; end if;
  v_profile_id := (v_token_payload ->> 'profile_id')::uuid;
  select request_row.* into v_request from public.verification_requests as request_row where request_row.id = p_request_id for update;
  if not found or v_request.method_code <> 'pan' or v_request.status <> 'pending_advisor_review' or v_request.version <> p_expected_version then raise exception 'Verification request cannot be approved'; end if;
  select evidence.* into v_evidence from public.verification_pan_evidence as evidence where evidence.request_id = v_request.id;
  if not found or v_evidence.match_result <> 'SINGLE_MATCH' or v_evidence.conflict_reason <> 'NONE' then raise exception 'PAN verification requires manual resolution'; end if;
  select pan_record.id into v_matching_record_id from public.profile_pan_records as pan_record
  join public.profiles as candidate_profile on candidate_profile.id = pan_record.profile_id and candidate_profile.role = 'client'
  where pan_record.profile_id = v_profile_id and pan_record.pan_lookup_hmac = v_evidence.pan_lookup_hmac
    and pan_record.status in ('OBSERVED', 'VERIFIED')
  order by pan_record.created_at asc limit 1;
  if v_matching_record_id is null then raise exception 'PAN verification requires manual resolution'; end if;
  if exists (select 1 from public.investor_account_links as active_link where (active_link.user_id = v_request.user_id or active_link.profile_id = v_profile_id) and active_link.link_status = 'active') then raise exception 'Verification request cannot be approved'; end if;
  insert into public.investor_account_links (user_id, profile_id, verification_method, verified_at, linked_at, link_status)
  values (v_request.user_id, v_profile_id, 'pan', now(), now(), 'active') on conflict (user_id, profile_id) do update set verification_method = excluded.verification_method, verified_at = excluded.verified_at, linked_at = excluded.linked_at, link_status = 'active';
  update public.profile_pan_records as pan_record set status = 'VERIFIED', verified_at = now() where pan_record.id = v_matching_record_id;
  update public.profiles as profile set canonical_pan_record_id = v_matching_record_id where profile.id = v_profile_id;
  update public.user_accounts as account set account_state = 'linked_investor', onboarding_completed = true where account.user_id = v_request.user_id;
  update public.verification_requests as request_row set status = 'approved', candidate_profile_id = v_profile_id, resolved_at = now(), version = request_row.version + 1 where request_row.id = v_request.id and request_row.version = p_expected_version;
  if not found then raise exception 'Verification request changed; refresh and retry'; end if;
  insert into public.verification_events (request_id, subject_user_id, actor_user_id, actor_type, event_type, previous_status, new_status, reason_code)
  values (v_request.id, v_request.user_id, auth.uid(), 'advisor', 'approved', 'pending_advisor_review', 'approved', p_reason_code);
  return 'approved';
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

revoke all on function public.submit_pan_verification(text) from public, anon, service_role;
revoke all on function public.approve_pan_verification_candidate(uuid, text, integer, text) from public, anon, service_role;
grant execute on function public.submit_pan_verification(text) to authenticated;
grant execute on function public.approve_pan_verification_candidate(uuid, text, integer, text) to authenticated;
grant execute on function public.process_cams_records(jsonb) to service_role;
