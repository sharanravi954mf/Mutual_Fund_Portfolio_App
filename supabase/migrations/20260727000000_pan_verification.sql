-- Sprint 5.2: PAN verification. Raw PAN values are accepted only by secured
-- RPCs, encrypted at rest with a dedicated Vault secret, and never projected
-- to browser clients. PAN evidence is immutable; lifecycle remains on the
-- existing versioned verification request and append-only event stream.

create extension if not exists pgcrypto with schema extensions;

do $$
begin
  create type public.pan_record_source as enum ('IMPORT', 'INVESTOR', 'ADVISOR', 'LEGACY');
exception when duplicate_object then null;
end;
$$;

do $$
begin
  create type public.pan_record_status as enum ('OBSERVED', 'VERIFIED', 'CONFLICT', 'INVALID_LEGACY', 'SUPERSEDED');
exception when duplicate_object then null;
end;
$$;

do $$
begin
  create type public.verification_match_result as enum ('NO_MATCH', 'SINGLE_MATCH', 'MULTIPLE_MATCH');
exception when duplicate_object then null;
end;
$$;

do $$
begin
  create type public.verification_conflict_reason as enum (
    'NONE', 'ALREADY_VERIFIED', 'PENDING_DUPLICATE', 'HISTORICAL_MISMATCH', 'LEGACY_INVALID'
  );
exception when duplicate_object then null;
end;
$$;

-- These helpers are private implementation details. They are revoked below so
-- no browser role can use them to derive, encrypt, or decrypt PAN values.
create or replace function public.pan_encryption_key()
returns text as $$
declare
  encryption_secret text;
begin
  select decrypted_secret into encryption_secret
  from vault.decrypted_secrets
  where name = 'pan_encryption_key'
  limit 1;

  if encryption_secret is null or length(encryption_secret) < 32 then
    raise exception 'PAN encryption configuration is unavailable';
  end if;
  return encryption_secret;
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

create or replace function public.pan_lookup_hmac_key()
returns text as $$
declare
  lookup_secret text;
begin
  select decrypted_secret into lookup_secret
  from vault.decrypted_secrets
  where name = 'pan_lookup_hmac_key'
  limit 1;

  if lookup_secret is null or length(lookup_secret) < 32 then
    raise exception 'PAN lookup configuration is unavailable';
  end if;
  return lookup_secret;
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

create or replace function public.normalize_pan(p_pan text)
returns text as $$
declare
  normalized_pan text := upper(regexp_replace(coalesce(p_pan, ''), '\\s+', '', 'g'));
begin
  if normalized_pan !~ '^[A-Z]{5}[0-9]{4}[A-Z]$' then
    return null;
  end if;
  return normalized_pan;
end;
$$ language plpgsql immutable security definer set search_path = public, pg_temp;

create or replace function public.mask_pan(p_pan text)
returns text as $$
begin
  if p_pan is null or length(p_pan) <> 10 then
    return null;
  end if;
  return '******' || right(p_pan, 4);
end;
$$ language plpgsql immutable security definer set search_path = public, pg_temp;

create table public.profile_pan_records (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete restrict,
  pan_ciphertext bytea,
  pan_lookup_hmac bytea,
  masked_pan text,
  source public.pan_record_source not null,
  source_system text not null check (source_system in ('CAMS', 'KFINTECH', 'MANUAL', 'API', 'LEGACY')),
  status public.pan_record_status not null default 'OBSERVED',
  created_at timestamptz not null default now(),
  verified_at timestamptz,
  check (
    (status = 'INVALID_LEGACY' and pan_ciphertext is null and pan_lookup_hmac is null and masked_pan is null)
    or (status <> 'INVALID_LEGACY' and pan_ciphertext is not null and pan_lookup_hmac is not null and masked_pan is not null)
  )
);

create unique index idx_profile_pan_records_profile_hmac
  on public.profile_pan_records(profile_id, pan_lookup_hmac)
  where pan_lookup_hmac is not null;
create index idx_profile_pan_records_lookup_hmac
  on public.profile_pan_records(pan_lookup_hmac)
  where pan_lookup_hmac is not null;

create table public.verification_pan_evidence (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null unique references public.verification_requests(id) on delete restrict,
  pan_ciphertext bytea not null,
  pan_lookup_hmac bytea not null,
  masked_pan text not null,
  match_result public.verification_match_result not null,
  conflict_reason public.verification_conflict_reason not null default 'NONE',
  created_at timestamptz not null default now()
);

create index idx_verification_pan_evidence_lookup_hmac
  on public.verification_pan_evidence(pan_lookup_hmac);

alter table public.profiles
  add column if not exists canonical_pan_record_id uuid;
alter table public.profiles
  drop constraint if exists profiles_canonical_pan_record_id_fkey;
alter table public.profiles
  add constraint profiles_canonical_pan_record_id_fkey
  foreign key (canonical_pan_record_id) references public.profile_pan_records(id)
  on delete restrict;
create unique index if not exists idx_profiles_canonical_pan_record
  on public.profiles(canonical_pan_record_id)
  where canonical_pan_record_id is not null;

-- Preserve valid legacy values as encrypted, non-canonical imported evidence.
-- Invalid legacy values are retained only as an audit state; the raw value is
-- deliberately discarded before profiles.pan is removed.
insert into public.profile_pan_records (
  profile_id, pan_ciphertext, pan_lookup_hmac, masked_pan, source, source_system, status
)
select
  profile.id,
  extensions.pgp_sym_encrypt(public.normalize_pan(profile.pan), public.pan_encryption_key(), 'cipher-algo=aes256, compress-algo=0'),
  extensions.hmac(public.normalize_pan(profile.pan), public.pan_lookup_hmac_key(), 'sha256'),
  public.mask_pan(public.normalize_pan(profile.pan)),
  'LEGACY', 'LEGACY', 'OBSERVED'
from public.profiles as profile
where public.normalize_pan(profile.pan) is not null
  and not exists (
    select 1 from public.profile_pan_records as pan_record
    where pan_record.profile_id = profile.id
      and pan_record.pan_lookup_hmac = extensions.hmac(public.normalize_pan(profile.pan), public.pan_lookup_hmac_key(), 'sha256')
  );

insert into public.profile_pan_records (profile_id, source, source_system, status)
select profile.id, 'LEGACY', 'LEGACY', 'INVALID_LEGACY'
from public.profiles as profile
where profile.pan is not null
  and btrim(profile.pan) <> ''
  and public.normalize_pan(profile.pan) is null
  and not exists (
    select 1 from public.profile_pan_records as pan_record
    where pan_record.profile_id = profile.id
      and pan_record.status = 'INVALID_LEGACY'
  );

create or replace function public.prevent_verification_pan_evidence_mutation()
returns trigger as $$
begin
  raise exception 'PAN verification evidence is immutable';
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

drop trigger if exists prevent_verification_pan_evidence_mutation on public.verification_pan_evidence;
create trigger prevent_verification_pan_evidence_mutation
  before update or delete on public.verification_pan_evidence
  for each row execute procedure public.prevent_verification_pan_evidence_mutation();

-- The ingestion procedure remains a service-role-only operation. It now uses
-- the opaque HMAC lookup and creates an encrypted import record instead of
-- storing raw PAN on profiles.
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
        product, sch_name, rep_date, clos_bal, rupee_bal, pan_no,
        joint1_pan, joint2_pan, guard_pan, email, mobile_no, bank_name,
        branch, ac_type, ac_no, ifsc_code, nom_name, relation, nom_percen
      ) values (
        rec->>'foliochk', rec->>'inv_name', rec->>'address1', rec->>'address2', rec->>'address3', rec->>'city', rec->>'pincode',
        rec->>'product', rec->>'sch_name', (rec->>'rep_date')::date, (rec->>'clos_bal')::numeric, (rec->>'rupee_bal')::numeric, rec->>'pan_no',
        rec->>'joint1_pan', rec->>'joint2_pan', rec->>'guard_pan', rec->>'email', rec->>'mobile_no', rec->>'bank_name',
        rec->>'branch', rec->>'ac_type', rec->>'ac_no', rec->>'ifsc_code', rec->>'nom_name', rec->>'relation', (rec->>'nom_percen')::numeric
      );
    end if;

    normalized_pan := public.normalize_pan(rec->>'clientPan');
    if normalized_pan is null then
      raise exception 'Imported record contains an invalid PAN';
    end if;
    pan_hmac := extensions.hmac(normalized_pan, public.pan_lookup_hmac_key(), 'sha256');

    select pan_record.profile_id into p_id
    from public.profile_pan_records as pan_record
    where pan_record.pan_lookup_hmac = pan_hmac
      and pan_record.status <> 'INVALID_LEGACY'
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
      pan_hmac,
      public.mask_pan(normalized_pan),
      'IMPORT', 'API', 'OBSERVED'
    ) on conflict (profile_id, pan_lookup_hmac) where pan_lookup_hmac is not null do nothing;

    insert into public.mutual_funds (scheme_code, scheme_name, fund_house, category, current_nav, nav_date)
    values (
      rec->>'schemeCode', rec->>'schemeName', coalesce(rec->>'fundHouse', 'Mutual Fund'),
      coalesce(rec->>'category', 'Mutual Fund'), (rec->>'nav')::numeric, (rec->>'date')::date
    ) on conflict (scheme_code) do update set
      scheme_name = excluded.scheme_name,
      current_nav = excluded.current_nav,
      nav_date = excluded.nav_date
    returning id into f_id;

    select id into port_id from public.portfolios where client_id = p_id limit 1;
    if port_id is null then
      insert into public.portfolios (client_id, total_invested_value, current_market_value)
      values (p_id, 0.00, 0.00)
      returning id into port_id;
    end if;

    select id into existing_tx_id from public.transactions
    where portfolio_id = port_id and mutual_fund_id = f_id
      and transaction_type = (rec->>'transactionType')
      and units = (rec->>'units')::numeric and amount = (rec->>'amount')::numeric
      and execution_date = (rec->>'date')::date
    limit 1;

    if existing_tx_id is null then
      insert into public.transactions (portfolio_id, mutual_fund_id, transaction_type, units, nav_at_transaction, amount, execution_date)
      values (port_id, f_id, rec->>'transactionType', (rec->>'units')::numeric,
        (rec->>'nav')::numeric, (rec->>'amount')::numeric, (rec->>'date')::date);
      perform public.recalculate_portfolio_value(port_id);
    end if;
  end loop;
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

drop index if exists public.idx_profiles_pan;
alter table public.profiles drop column if exists pan;

alter table public.profile_pan_records enable row level security;
alter table public.verification_pan_evidence enable row level security;
revoke all on table public.profile_pan_records, public.verification_pan_evidence from public, anon, authenticated;

-- PAN requests must use the dedicated submission RPC so the generic request
-- endpoint cannot create a PAN lifecycle without encrypted evidence.
create or replace function public.create_verification_request(p_method_code text)
returns table (request_id uuid, status public.verification_request_status) as $$
begin
  if p_method_code = 'pan' then
    raise exception 'Use PAN verification submission';
  end if;
  return query select * from public.create_non_pan_verification_request(p_method_code);
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

-- Preserve the original non-PAN lifecycle implementation under a private
-- helper so the public function can reject PAN without duplicating raw-data logic.
create or replace function public.create_non_pan_verification_request(p_method_code text)
returns table (request_id uuid, status public.verification_request_status) as $$
declare
  account public.user_accounts%rowtype;
  created_request public.verification_requests%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication is required'; end if;
  select * into account from public.user_accounts where user_id = auth.uid() for update;
  if not found or account.account_state <> 'link_pending' then
    raise exception 'Verification is not available for this account';
  end if;
  if exists (select 1 from public.investor_account_links where user_id = auth.uid() and link_status = 'active') then
    raise exception 'Verification is not available for this account';
  end if;
  if p_method_code not in ('verified_email', 'verified_mobile', 'folio', 'advisor_assisted', 'otp', 'document_upload') then
    raise exception 'Verification method is not available';
  end if;
  insert into public.verification_requests (user_id, method_code, status, submitted_at)
  values (auth.uid(), p_method_code, 'pending_advisor_review', now())
  returning * into created_request;
  insert into public.verification_events (request_id, subject_user_id, actor_user_id, actor_type, event_type, previous_status, new_status)
  values
    (created_request.id, auth.uid(), auth.uid(), 'investor', 'created', null, 'draft'),
    (created_request.id, auth.uid(), auth.uid(), 'investor', 'submitted', 'draft', 'pending_advisor_review');
  return query select created_request.id, created_request.status;
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

create or replace function public.submit_pan_verification(p_pan text)
returns table (
  request_id uuid,
  status public.verification_request_status,
  masked_pan text,
  match_result public.verification_match_result,
  conflict_reason public.verification_conflict_reason
) as $$
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

  select * into v_account from public.user_accounts as account
  where account.user_id = auth.uid() for update;
  if not found or v_account.account_state <> 'link_pending' then
    raise exception 'PAN verification is not available for this account';
  end if;
  if exists (select 1 from public.investor_account_links as link where link.user_id = auth.uid() and link.link_status = 'active') then
    raise exception 'PAN verification is not available for this account';
  end if;
  if exists (
    select 1 from public.verification_requests as open_request
    where open_request.user_id = auth.uid()
      and open_request.status in ('draft', 'pending_advisor_review', 'more_information_required')
  ) then
    raise exception 'A verification request is already in progress';
  end if;

  v_pan_hmac := extensions.hmac(v_normalized_pan, public.pan_lookup_hmac_key(), 'sha256');
  select count(distinct pan_record.profile_id) into v_profile_count
  from public.profile_pan_records as pan_record
  where pan_record.pan_lookup_hmac = v_pan_hmac
    and pan_record.status <> 'INVALID_LEGACY';
  v_match := case
    when v_profile_count = 0 then 'NO_MATCH'::public.verification_match_result
    when v_profile_count = 1 then 'SINGLE_MATCH'::public.verification_match_result
    else 'MULTIPLE_MATCH'::public.verification_match_result
  end;

  if exists (
    select 1
    from public.profile_pan_records as pan_record
    join public.investor_account_links as active_link on active_link.profile_id = pan_record.profile_id
    where pan_record.pan_lookup_hmac = v_pan_hmac
      and active_link.link_status = 'active'
  ) then
    v_conflict := 'ALREADY_VERIFIED';
  elsif exists (
    select 1
    from public.verification_pan_evidence as evidence
    join public.verification_requests as pending_request on pending_request.id = evidence.request_id
    where evidence.pan_lookup_hmac = v_pan_hmac
      and pending_request.user_id <> auth.uid()
      and pending_request.status in ('pending_advisor_review', 'more_information_required')
  ) then
    v_conflict := 'PENDING_DUPLICATE';
  end if;

  insert into public.verification_requests (user_id, method_code, status, submitted_at)
  values (auth.uid(), 'pan', 'pending_advisor_review', now())
  returning * into v_request;
  insert into public.verification_pan_evidence (
    request_id, pan_ciphertext, pan_lookup_hmac, masked_pan, match_result, conflict_reason
  ) values (
    v_request.id,
    extensions.pgp_sym_encrypt(v_normalized_pan, public.pan_encryption_key(), 'cipher-algo=aes256, compress-algo=0'),
    v_pan_hmac, public.mask_pan(v_normalized_pan), v_match, v_conflict
  );
  insert into public.verification_events (request_id, subject_user_id, actor_user_id, actor_type, event_type, previous_status, new_status)
  values
    (v_request.id, auth.uid(), auth.uid(), 'investor', 'created', null, 'draft'),
    (v_request.id, auth.uid(), auth.uid(), 'investor', 'pan_submitted', 'draft', 'pending_advisor_review'),
    (v_request.id, auth.uid(), null, 'system', 'pan_match_assessed', 'pending_advisor_review', 'pending_advisor_review');
  return query select v_request.id, v_request.status, public.mask_pan(v_normalized_pan), v_match, v_conflict;
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

-- PAN approval retains opaque candidate-token selection but independently
-- verifies the selected business profile against the encrypted evidence.
create or replace function public.approve_pan_verification_candidate(
  p_request_id uuid,
  p_candidate_token text,
  p_expected_version integer,
  p_reason_code text default null
) returns public.verification_request_status as $$
declare
  v_request public.verification_requests%rowtype;
  v_token_payload jsonb;
  v_profile_id uuid;
  v_evidence public.verification_pan_evidence%rowtype;
  v_matching_record_id uuid;
begin
  if not public.is_admin() then raise exception 'Advisor authorization is required'; end if;
  begin
    v_token_payload := extensions.pgp_sym_decrypt(decode(p_candidate_token, 'base64'), public.verification_candidate_token_secret())::jsonb;
  exception when others then
    raise exception 'Verification candidate is unavailable';
  end;
  if v_token_payload ->> 'request_id' <> p_request_id::text
    or v_token_payload ->> 'advisor_user_id' <> auth.uid()::text
    or coalesce((v_token_payload ->> 'expires_at')::bigint, 0) < extract(epoch from now())::bigint then
    raise exception 'Verification candidate is unavailable';
  end if;
  v_profile_id := (v_token_payload ->> 'profile_id')::uuid;

  select request_row.* into v_request from public.verification_requests as request_row
  where request_row.id = p_request_id for update;
  if not found or v_request.method_code <> 'pan'
    or v_request.status <> 'pending_advisor_review'
    or v_request.version <> p_expected_version then
    raise exception 'Verification request cannot be approved';
  end if;
  select evidence.* into v_evidence from public.verification_pan_evidence as evidence
  where evidence.request_id = v_request.id;
  if not found or v_evidence.match_result <> 'SINGLE_MATCH' or v_evidence.conflict_reason <> 'NONE' then
    raise exception 'PAN verification requires manual resolution';
  end if;
  if not exists (select 1 from public.profiles as candidate_profile where candidate_profile.id = v_profile_id and candidate_profile.role = 'client') then
    raise exception 'Verification request cannot be approved';
  end if;
  select pan_record.id into v_matching_record_id from public.profile_pan_records as pan_record
  where pan_record.profile_id = v_profile_id
    and pan_record.pan_lookup_hmac = v_evidence.pan_lookup_hmac
    and pan_record.status <> 'INVALID_LEGACY'
  order by pan_record.created_at asc limit 1;
  if v_matching_record_id is null then
    raise exception 'PAN verification requires manual resolution';
  end if;
  if exists (
    select 1 from public.investor_account_links as active_link
    where (active_link.user_id = v_request.user_id or active_link.profile_id = v_profile_id)
      and active_link.link_status = 'active'
  ) then
    raise exception 'Verification request cannot be approved';
  end if;

  insert into public.investor_account_links (user_id, profile_id, verification_method, verified_at, linked_at, link_status)
  values (v_request.user_id, v_profile_id, 'pan', now(), now(), 'active')
  on conflict (user_id, profile_id) do update set
    verification_method = excluded.verification_method, verified_at = excluded.verified_at,
    linked_at = excluded.linked_at, link_status = 'active';
  update public.profile_pan_records as pan_record set status = 'VERIFIED', verified_at = now()
  where pan_record.id = v_matching_record_id;
  update public.profiles as profile set canonical_pan_record_id = v_matching_record_id
  where profile.id = v_profile_id;
  update public.user_accounts as account set account_state = 'linked_investor', onboarding_completed = true
  where account.user_id = v_request.user_id;
  update public.verification_requests as request_row set status = 'approved', candidate_profile_id = v_profile_id,
    resolved_at = now(), version = request_row.version + 1
  where request_row.id = v_request.id and request_row.version = p_expected_version;
  if not found then raise exception 'Verification request changed; refresh and retry'; end if;
  insert into public.verification_events (request_id, subject_user_id, actor_user_id, actor_type, event_type, previous_status, new_status, reason_code)
  values (v_request.id, v_request.user_id, auth.uid(), 'advisor', 'approved', 'pending_advisor_review', 'approved', p_reason_code);
  return 'approved';
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

-- Generic candidate approval is deliberately unavailable for PAN requests.
create or replace function public.approve_verification_candidate(
  p_request_id uuid, p_candidate_token text, p_expected_version integer, p_reason_code text default null
) returns public.verification_request_status as $$
declare
  v_request public.verification_requests%rowtype;
  v_token_payload jsonb;
  v_profile_id uuid;
begin
  if not public.is_admin() then raise exception 'Advisor authorization is required'; end if;
  begin
    v_token_payload := extensions.pgp_sym_decrypt(
      decode(p_candidate_token, 'base64'), public.verification_candidate_token_secret()
    )::jsonb;
  exception when others then
    raise exception 'Verification candidate is unavailable';
  end;
  if v_token_payload ->> 'request_id' <> p_request_id::text
    or v_token_payload ->> 'advisor_user_id' <> auth.uid()::text
    or coalesce((v_token_payload ->> 'expires_at')::bigint, 0) < extract(epoch from now())::bigint then
    raise exception 'Verification candidate is unavailable';
  end if;
  v_profile_id := (v_token_payload ->> 'profile_id')::uuid;
  select request_row.* into v_request from public.verification_requests as request_row
  where request_row.id = p_request_id for update;
  if not found or v_request.method_code = 'pan'
    or v_request.status <> 'pending_advisor_review'
    or v_request.version <> p_expected_version then
    raise exception 'Verification request cannot be approved';
  end if;
  if not exists (select 1 from public.profiles as candidate_profile
                 where candidate_profile.id = v_profile_id and candidate_profile.role = 'client') then
    raise exception 'Verification request cannot be approved';
  end if;
  if exists (select 1 from public.investor_account_links as active_link
             where (active_link.user_id = v_request.user_id or active_link.profile_id = v_profile_id)
               and active_link.link_status = 'active') then
    raise exception 'Verification request cannot be approved';
  end if;
  insert into public.investor_account_links (user_id, profile_id, verification_method, verified_at, linked_at, link_status)
  values (v_request.user_id, v_profile_id, v_request.method_code, now(), now(), 'active')
  on conflict (user_id, profile_id) do update set
    verification_method = excluded.verification_method, verified_at = excluded.verified_at,
    linked_at = excluded.linked_at, link_status = 'active';
  update public.user_accounts as account set account_state = 'linked_investor', onboarding_completed = true
  where account.user_id = v_request.user_id;
  update public.verification_requests as request_row set status = 'approved', candidate_profile_id = v_profile_id,
    resolved_at = now(), version = request_row.version + 1
  where request_row.id = v_request.id and request_row.version = p_expected_version;
  if not found then raise exception 'Verification request changed; refresh and retry'; end if;
  insert into public.verification_events (request_id, subject_user_id, actor_user_id, actor_type, event_type, previous_status, new_status, reason_code)
  values (v_request.id, v_request.user_id, auth.uid(), 'advisor', 'approved',
    'pending_advisor_review', 'approved', p_reason_code);
  return 'approved';
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

-- Safe status/review projections contain only a mask and non-sensitive outcome.
drop function if exists public.get_verification_status();
create function public.get_verification_status()
returns table (
  id uuid, method_code text, status public.verification_request_status,
  submitted_at timestamptz, resolved_at timestamptz, expires_at timestamptz,
  created_at timestamptz, updated_at timestamptz, version integer,
  masked_pan text, pan_match_result text, pan_conflict_reason text
) as $$
begin
  if auth.uid() is null then raise exception 'Authentication is required'; end if;
  return query select request_row.id, request_row.method_code, request_row.status,
    request_row.submitted_at, request_row.resolved_at, request_row.expires_at,
    request_row.created_at, request_row.updated_at, request_row.version,
    evidence.masked_pan, evidence.match_result::text, evidence.conflict_reason::text
  from public.verification_requests as request_row
  left join public.verification_pan_evidence as evidence on evidence.request_id = request_row.id
  where request_row.user_id = auth.uid()
  order by request_row.created_at desc;
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

drop function if exists public.get_verification_review(uuid);
create function public.get_verification_review(p_request_id uuid)
returns table (
  id uuid, method_code text, status public.verification_request_status,
  created_at timestamptz, submitted_at timestamptz, resolved_at timestamptz,
  expires_at timestamptz, version integer, retry_of_request_id uuid,
  requester_masked_email text, requester_masked_mobile text,
  masked_pan text, pan_match_result text, pan_conflict_reason text
) as $$
begin
  if not public.is_admin() then raise exception 'Advisor authorization is required'; end if;
  return query select request_row.id, request_row.method_code, request_row.status,
    request_row.created_at, request_row.submitted_at, request_row.resolved_at,
    request_row.expires_at, request_row.version, request_row.retry_of_request_id,
    public.mask_verification_email(auth_user.email), public.mask_verification_mobile(auth_user.phone),
    evidence.masked_pan, evidence.match_result::text, evidence.conflict_reason::text
  from public.verification_requests as request_row
  left join auth.users as auth_user on auth_user.id = request_row.user_id
  left join public.verification_pan_evidence as evidence on evidence.request_id = request_row.id
  where request_row.id = p_request_id;
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

drop function if exists public.list_verification_review_queue_filtered(text, text, text);
create function public.list_verification_review_queue_filtered(
  p_request_id_query text default null, p_status text default null, p_method_code text default null
) returns table (
  id uuid, method_code text, status public.verification_request_status,
  submitted_at timestamptz, created_at timestamptz, version integer,
  masked_pan text, pan_match_result text, pan_conflict_reason text
) as $$
begin
  if not public.is_admin() then raise exception 'Advisor authorization is required'; end if;
  return query select request_row.id, request_row.method_code, request_row.status,
    request_row.submitted_at, request_row.created_at, request_row.version,
    evidence.masked_pan, evidence.match_result::text, evidence.conflict_reason::text
  from public.verification_requests as request_row
  left join public.verification_pan_evidence as evidence on evidence.request_id = request_row.id
  where (nullif(trim(p_request_id_query), '') is null or request_row.id::text ilike '%' || trim(p_request_id_query) || '%')
    and (nullif(trim(p_status), '') is null or request_row.status::text = trim(p_status))
    and (nullif(trim(p_method_code), '') is null or request_row.method_code = trim(p_method_code))
  order by request_row.submitted_at asc nulls last, request_row.created_at asc;
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

alter table public.verification_events drop constraint if exists verification_events_event_type_check;
alter table public.verification_events add constraint verification_events_event_type_check check (event_type in (
  'created', 'submitted', 'approved', 'rejected', 'cancelled', 'expired', 'revoked',
  'more_information_requested', 'automatic_linked', 'pan_submitted', 'pan_match_assessed'
));
alter table public.verification_events drop constraint if exists verification_events_check;
alter table public.verification_events add constraint verification_events_check
  check (previous_status is distinct from new_status or event_type in ('created', 'pan_match_assessed'));

revoke all on function public.pan_encryption_key(), public.pan_lookup_hmac_key(), public.normalize_pan(text), public.mask_pan(text), public.prevent_verification_pan_evidence_mutation() from public, anon, authenticated, service_role;
revoke all on function public.create_non_pan_verification_request(text) from public, anon, authenticated, service_role;
revoke all on function public.submit_pan_verification(text) from public, anon, service_role;
revoke all on function public.approve_pan_verification_candidate(uuid, text, integer, text) from public, anon, service_role;
revoke all on function public.get_verification_status() from public, anon, service_role;
revoke all on function public.get_verification_review(uuid) from public, anon, service_role;
revoke all on function public.list_verification_review_queue_filtered(text, text, text) from public, anon, service_role;
grant execute on function public.submit_pan_verification(text) to authenticated;
grant execute on function public.approve_pan_verification_candidate(uuid, text, integer, text) to authenticated;
grant execute on function public.get_verification_status() to authenticated;
grant execute on function public.get_verification_review(uuid) to authenticated;
grant execute on function public.list_verification_review_queue_filtered(text, text, text) to authenticated;
grant execute on function public.create_verification_request(text) to authenticated;
grant execute on function public.process_cams_records(jsonb) to service_role;
