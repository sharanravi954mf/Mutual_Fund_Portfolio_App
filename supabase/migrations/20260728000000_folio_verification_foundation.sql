-- Sprint 5.3 Phase 1: folio-scoped investor authorization. Existing identity
-- links remain prerequisites; grants, not links alone, scope investor reads.

do $$ begin
  alter type public.verification_request_status add value if not exists 'under_review';
  alter type public.verification_request_status add value if not exists 'more_information_required';
  alter type public.verification_request_status add value if not exists 'superseded';
  alter type public.verification_request_status add value if not exists 'revoked';
exception when duplicate_object then null; end $$;

do $$ begin create type public.folio_holder_relationship as enum ('SOLE_HOLDER','JOINT_HOLDER','GUARDIAN_FOR_MINOR'); exception when duplicate_object then null; end $$;
do $$ begin create type public.folio_grant_status as enum ('active','revoked','expired','superseded','suspended'); exception when duplicate_object then null; end $$;

create table public.folio_references (
  id uuid primary key default gen_random_uuid(),
  registrar text not null check (registrar in ('CAMS','KFINTECH')),
  normalized_folio_number text not null check (normalized_folio_number = upper(regexp_replace(normalized_folio_number, '[^A-Z0-9]', '', 'g'))),
  amc_identity text not null,
  source_folio_masked text not null,
  predecessor_id uuid references public.folio_references(id) on delete restrict,
  lineage_type text check (lineage_type in ('predecessor','successor','migrated_from','merged_into','split_from','reconciled_equivalent')),
  created_at timestamptz not null default now(),
  constraint folio_references_registrar_normalized_folio_key
    unique (registrar, normalized_folio_number)
);
create index idx_folio_references_lookup on public.folio_references(registrar, normalized_folio_number);

-- The mapping is service-managed: browsers never choose a portfolio or folio.
create table public.portfolio_folio_references (
  portfolio_id uuid primary key references public.portfolios(id) on delete cascade,
  folio_reference_id uuid not null references public.folio_references(id) on delete restrict,
  created_at timestamptz not null default now()
);
create index idx_portfolio_folio_references_folio on public.portfolio_folio_references(folio_reference_id);

create table public.verification_folio_evidence (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null unique references public.verification_requests(id) on delete restrict,
  folio_reference_id uuid not null references public.folio_references(id) on delete restrict,
  holder_relationship public.folio_holder_relationship not null,
  evidence_source text not null check (evidence_source in ('REGISTRAR_IMPORT','REGISTRAR_STATEMENT','INVESTOR_DECLARATION')),
  source_captured_at timestamptz,
  created_at timestamptz not null default now()
);
create table public.folio_grants (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null unique references public.verification_requests(id) on delete restrict,
  user_id uuid not null references public.user_accounts(user_id) on delete restrict,
  profile_id uuid not null references public.profiles(id) on delete restrict,
  folio_reference_id uuid not null references public.folio_references(id) on delete restrict,
  holder_relationship public.folio_holder_relationship not null,
  status public.folio_grant_status not null default 'active',
  approved_by uuid references public.user_accounts(user_id) on delete restrict,
  approved_at timestamptz not null default now(), revoked_at timestamptz, revoked_by uuid references public.user_accounts(user_id) on delete restrict,
  revocation_reason text, created_at timestamptz not null default now(),
  check ((status = 'revoked') = (revoked_at is not null))
);
create unique index idx_folio_grants_active_unique on public.folio_grants(user_id, profile_id, folio_reference_id, holder_relationship) where status = 'active';
create index idx_folio_grants_active_access on public.folio_grants(user_id, profile_id, folio_reference_id) where status = 'active';

create or replace function public.prevent_folio_evidence_mutation() returns trigger as $$ begin raise exception 'Folio verification evidence is immutable'; end; $$ language plpgsql security definer set search_path = public, pg_temp;
create trigger prevent_folio_evidence_mutation before update or delete on public.verification_folio_evidence for each row execute procedure public.prevent_folio_evidence_mutation();
create or replace function public.prevent_verification_event_mutation() returns trigger as $$ begin raise exception 'Verification events are append-only'; end; $$ language plpgsql security definer set search_path = public, pg_temp;
create trigger prevent_verification_event_mutation before update or delete on public.verification_events for each row execute procedure public.prevent_verification_event_mutation();
alter table public.folio_references enable row level security;
alter table public.portfolio_folio_references enable row level security;
alter table public.verification_folio_evidence enable row level security;
alter table public.folio_grants enable row level security;
create policy "Advisors can view folio grants" on public.folio_grants for select to authenticated using (public.is_admin());
create policy "Users can view own folio grants" on public.folio_grants for select to authenticated using (user_id = auth.uid());
create policy "Advisors can view folio evidence" on public.verification_folio_evidence for select to authenticated using (public.is_admin());
create policy "Users can view own folio evidence" on public.verification_folio_evidence for select to authenticated using (exists (select 1 from public.verification_requests r where r.id = request_id and r.user_id = auth.uid()));

-- Reuse the existing append-only stream, but explicitly admit the folio
-- lifecycle events. Browser roles retain no write policy on these tables.
alter table public.verification_events drop constraint if exists verification_events_event_type_check;
alter table public.verification_events add constraint verification_events_event_type_check check (event_type in (
  'created','submitted','approved','rejected','cancelled','expired','revoked','more_information_requested','automatic_linked','pan_submitted','pan_match_assessed',
  'folio_submitted','folio_review_started','folio_information_requested','folio_information_resubmitted','folio_approved','folio_rejected','folio_cancelled','folio_expired','folio_superseded','folio_evidence_changed','folio_grant_revoked','folio_review_reassigned'
));
alter table public.verification_events drop constraint if exists verification_events_check;
alter table public.verification_events add constraint verification_events_check check (previous_status is distinct from new_status or event_type in ('created','pan_match_assessed'));

create or replace function public.has_active_folio_grant(p_profile_id uuid, p_portfolio_id uuid) returns boolean as $$
begin return exists (
  select 1 from public.user_accounts a join public.investor_account_links l on l.user_id=a.user_id
  join public.portfolio_folio_references pf on pf.portfolio_id=p_portfolio_id
  join public.folio_grants g on g.user_id=a.user_id and g.profile_id=l.profile_id and g.folio_reference_id=pf.folio_reference_id
  where a.user_id=auth.uid() and a.account_state='linked_investor' and l.link_status='active' and l.profile_id=p_profile_id and g.status='active'
); end; $$ language plpgsql security definer set search_path=public,pg_temp;
revoke all on function public.has_active_folio_grant(uuid,uuid) from public, anon;
grant execute on function public.has_active_folio_grant(uuid,uuid) to authenticated;
drop policy if exists "Linked investors can view their linked portfolios" on public.portfolios;
create policy "Investors can view granted folio portfolios" on public.portfolios for select to authenticated using (public.has_active_folio_grant(client_id,id));
drop policy if exists "Linked investors can view transactions for linked portfolios" on public.transactions;
create policy "Investors can view granted folio transactions" on public.transactions for select to authenticated using (exists (select 1 from public.portfolios p where p.id=transactions.portfolio_id and public.has_active_folio_grant(p.client_id,p.id)));

create or replace function public._transition_folio_request(p_request_id uuid,p_expected_version integer,p_action text,p_reason text default null) returns table(request_id uuid,status public.verification_request_status,version integer) as $$
declare r public.verification_requests%rowtype; n public.verification_request_status; actor text; event_name text; begin
  select * into r from public.verification_requests where id=p_request_id for update;
  if not found or r.method_code <> 'folio' or r.version <> p_expected_version then raise exception 'Folio request changed or unavailable'; end if;
  actor:=case when public.is_admin() then 'advisor' else 'investor' end;
  if (actor='investor' and r.user_id<>auth.uid()) then raise exception 'Folio request unavailable'; end if;
  if p_action='begin_review' and actor='advisor' and r.status='pending_advisor_review' then n:='under_review'; event_name:='folio_review_started';
  elsif p_action='more_information' and actor='advisor' and r.status='under_review' and nullif(trim(p_reason),'') is not null then n:='more_information_required'; event_name:='folio_information_requested';
  elsif p_action='resubmit' and actor='investor' and r.status='more_information_required' then n:='pending_advisor_review'; event_name:='folio_information_resubmitted';
  elsif p_action='reject' and actor='advisor' and r.status='under_review' and nullif(trim(p_reason),'') is not null then n:='rejected'; event_name:='folio_rejected';
  elsif p_action='cancel' and actor='investor' and r.status in ('draft','pending_advisor_review','more_information_required') then n:='cancelled'; event_name:='folio_cancelled';
  elsif p_action='expire' and actor='advisor' and r.status in ('pending_advisor_review','under_review','more_information_required') and r.expires_at <= now() then n:='expired'; event_name:='folio_expired';
  else raise exception 'Invalid folio lifecycle transition'; end if;
  update public.verification_requests set status=n,resolved_at=case when n in ('rejected','cancelled','expired') then now() else null end,version=version+1 where id=r.id and version=p_expected_version;
  insert into public.verification_events(request_id,subject_user_id,actor_user_id,actor_type,event_type,previous_status,new_status,reason_code) values(r.id,r.user_id,auth.uid(),actor,event_name,r.status,n,p_reason);
  return query select r.id,n,p_expected_version+1; end; $$ language plpgsql security definer set search_path=public,pg_temp;

create or replace function public.issue_folio_submission_token(p_folio_reference_id uuid,p_user_id uuid) returns text as $$
begin
  if not exists (select 1 from public.folio_references where id=p_folio_reference_id) then raise exception 'Folio is unavailable'; end if;
  return encode(extensions.pgp_sym_encrypt(jsonb_build_object('folio_reference_id',p_folio_reference_id,'user_id',p_user_id,'expires_at',extract(epoch from now()+interval '5 minutes')::bigint)::text,public.verification_candidate_token_secret(),'cipher-algo=aes256, compress-algo=0'),'base64');
end; $$ language plpgsql security definer set search_path=public,pg_temp;

create or replace function public.submit_folio_verification(p_folio_token text,p_relationship public.folio_holder_relationship,p_idempotency_key uuid) returns table(request_id uuid,status public.verification_request_status,version integer) as $$
declare r public.verification_requests%rowtype; token_payload jsonb; folio_id uuid; begin
  if auth.uid() is null then raise exception 'Authentication is required'; end if;
  if not exists(select 1 from public.user_accounts a join public.investor_account_links l on l.user_id=a.user_id where a.user_id=auth.uid() and a.account_state='linked_investor' and l.link_status='active') then raise exception 'Folio verification unavailable'; end if;
  begin token_payload:=extensions.pgp_sym_decrypt(decode(p_folio_token,'base64'),public.verification_candidate_token_secret())::jsonb; exception when others then raise exception 'Folio is unavailable'; end;
  if token_payload->>'user_id'<>auth.uid()::text or coalesce((token_payload->>'expires_at')::bigint,0)<extract(epoch from now())::bigint then raise exception 'Folio is unavailable'; end if;
  folio_id:=(token_payload->>'folio_reference_id')::uuid;
  if not exists(select 1 from public.folio_references where id=folio_id) then raise exception 'Folio is unavailable'; end if;
  perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text || p_idempotency_key::text,0));
  select * into r from public.verification_requests where method_code='folio' and user_id=auth.uid() and status in ('draft','pending_advisor_review','under_review','more_information_required') order by created_at desc limit 1;
  if found then return query select r.id,r.status,r.version; return; end if;
  insert into public.verification_requests(user_id,method_code,status,submitted_at,expires_at) values(auth.uid(),'folio','pending_advisor_review',now(),now()+interval '30 days') returning * into r;
  insert into public.verification_folio_evidence(request_id,folio_reference_id,holder_relationship,evidence_source) values(r.id,folio_id,p_relationship,'INVESTOR_DECLARATION');
  insert into public.verification_events(request_id,subject_user_id,actor_user_id,actor_type,event_type,previous_status,new_status,reason_code) values(r.id,auth.uid(),auth.uid(),'investor','folio_submitted',null,'pending_advisor_review',p_idempotency_key::text);
  return query select r.id,r.status,r.version; end; $$ language plpgsql security definer set search_path=public,pg_temp;

create or replace function public.approve_folio_verification(p_request_id uuid,p_expected_version integer,p_reason text) returns table(request_id uuid,status public.verification_request_status,version integer) as $$
declare r public.verification_requests%rowtype; e public.verification_folio_evidence%rowtype; profile uuid; begin
  if not public.is_admin() or nullif(trim(p_reason),'') is null then raise exception 'Folio approval unavailable'; end if;
  select * into r from public.verification_requests where id=p_request_id for update;
  if not found or r.method_code<>'folio' or r.status<>'under_review' or r.version<>p_expected_version then raise exception 'Folio request cannot be approved'; end if;
  select * into e from public.verification_folio_evidence where request_id=r.id;
  select profile_id into profile from public.investor_account_links where user_id=r.user_id and link_status='active';
  if profile is null then raise exception 'Folio request cannot be approved'; end if;
  if e.holder_relationship in ('JOINT_HOLDER','GUARDIAN_FOR_MINOR') and p_reason not in ('JOINT_HOLDER_CONFIRMED','GUARDIAN_RELATIONSHIP_CONFIRMED') then raise exception 'Required relationship review is missing'; end if;
  insert into public.folio_grants(request_id,user_id,profile_id,folio_reference_id,holder_relationship,approved_by) values(r.id,r.user_id,profile,e.folio_reference_id,e.holder_relationship,auth.uid());
  update public.verification_requests set status='approved',resolved_at=now(),version=version+1 where id=r.id and version=p_expected_version;
  if not found then raise exception 'Folio request changed or unavailable'; end if;
  insert into public.verification_events(request_id,subject_user_id,actor_user_id,actor_type,event_type,previous_status,new_status,reason_code) values(r.id,r.user_id,auth.uid(),'advisor','folio_approved','under_review','approved',p_reason);
  return query select r.id,'approved'::public.verification_request_status,p_expected_version+1; end; $$ language plpgsql security definer set search_path=public,pg_temp;

create or replace function public.revoke_folio_grant(p_grant_id uuid,p_expected_version integer,p_reason text) returns public.folio_grant_status as $$
declare g public.folio_grants%rowtype; begin if not public.is_admin() or nullif(trim(p_reason),'') is null then raise exception 'Grant revocation unavailable'; end if; select * into g from public.folio_grants where id=p_grant_id for update; if not found or g.status<>'active' then raise exception 'Grant cannot be revoked'; end if;
  update public.folio_grants set status='revoked',revoked_at=now(),revoked_by=auth.uid(),revocation_reason=p_reason where id=g.id and status='active';
  update public.verification_requests set status='revoked',version=version+1 where id=g.request_id and version=p_expected_version; if not found then raise exception 'Folio request changed or unavailable'; end if;
  insert into public.verification_events(request_id,subject_user_id,actor_user_id,actor_type,event_type,previous_status,new_status,reason_code) values(g.request_id,g.user_id,auth.uid(),'advisor','folio_grant_revoked','approved','revoked',p_reason); return 'revoked'; end; $$ language plpgsql security definer set search_path=public,pg_temp;

create or replace function public.begin_folio_review(p_request_id uuid,p_expected_version integer) returns table(request_id uuid,status public.verification_request_status,version integer) as $$ begin return query select * from public._transition_folio_request(p_request_id,p_expected_version,'begin_review'); end; $$ language plpgsql security definer set search_path=public,pg_temp;
create or replace function public.request_folio_more_information(p_request_id uuid,p_expected_version integer,p_reason text) returns table(request_id uuid,status public.verification_request_status,version integer) as $$ begin return query select * from public._transition_folio_request(p_request_id,p_expected_version,'more_information',p_reason); end; $$ language plpgsql security definer set search_path=public,pg_temp;
create or replace function public.resubmit_folio_verification(p_request_id uuid,p_expected_version integer) returns table(request_id uuid,status public.verification_request_status,version integer) as $$ begin return query select * from public._transition_folio_request(p_request_id,p_expected_version,'resubmit'); end; $$ language plpgsql security definer set search_path=public,pg_temp;
create or replace function public.reject_folio_verification(p_request_id uuid,p_expected_version integer,p_reason text) returns table(request_id uuid,status public.verification_request_status,version integer) as $$ begin return query select * from public._transition_folio_request(p_request_id,p_expected_version,'reject',p_reason); end; $$ language plpgsql security definer set search_path=public,pg_temp;
create or replace function public.cancel_folio_verification(p_request_id uuid,p_expected_version integer) returns table(request_id uuid,status public.verification_request_status,version integer) as $$ begin return query select * from public._transition_folio_request(p_request_id,p_expected_version,'cancel'); end; $$ language plpgsql security definer set search_path=public,pg_temp;
create or replace function public.expire_folio_verification(p_request_id uuid,p_expected_version integer) returns table(request_id uuid,status public.verification_request_status,version integer) as $$ begin return query select * from public._transition_folio_request(p_request_id,p_expected_version,'expire','SYSTEM_EXPIRY'); end; $$ language plpgsql security definer set search_path=public,pg_temp;

revoke all on function public._transition_folio_request(uuid,integer,text,text) from public,anon,authenticated,service_role;
revoke all on function public.issue_folio_submission_token(uuid,uuid) from public,anon,authenticated,service_role;
revoke all on function public.submit_folio_verification(text,public.folio_holder_relationship,uuid) from public,anon,service_role;
revoke all on function public.approve_folio_verification(uuid,integer,text) from public,anon,service_role;
revoke all on function public.revoke_folio_grant(uuid,integer,text) from public,anon,service_role;
grant execute on function public.submit_folio_verification(text,public.folio_holder_relationship,uuid) to authenticated;
grant execute on function public.begin_folio_review(uuid,integer), public.request_folio_more_information(uuid,integer,text), public.resubmit_folio_verification(uuid,integer), public.reject_folio_verification(uuid,integer,text), public.cancel_folio_verification(uuid,integer), public.expire_folio_verification(uuid,integer) to authenticated;
grant execute on function public.approve_folio_verification(uuid,integer,text) to authenticated;
grant execute on function public.revoke_folio_grant(uuid,integer,text) to authenticated;
