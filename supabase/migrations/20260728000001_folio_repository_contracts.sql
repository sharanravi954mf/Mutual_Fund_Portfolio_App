-- Sprint 5.3 Phase 2.5: safe repository projections and one-time submission tokens.
create table public.folio_submission_tokens (
  token_id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.user_accounts(user_id) on delete cascade,
  folio_reference_id uuid not null references public.folio_references(id) on delete restrict,
  expires_at timestamptz not null,
  consumed_at timestamptz,
  created_at timestamptz not null default now(),
  check (expires_at > created_at)
);
create index idx_folio_submission_tokens_active on public.folio_submission_tokens(user_id, expires_at) where consumed_at is null;
alter table public.folio_submission_tokens enable row level security;
revoke all on table public.folio_submission_tokens from public, anon, authenticated;

create or replace function public.mask_folio_summary(p_registrar text,p_masked text) returns text as $$ begin return p_registrar || ' folio ' || p_masked; end; $$ language plpgsql immutable security definer set search_path=public,pg_temp;

create or replace function public.issue_folio_submission_token(p_registrar text,p_folio_number text)
returns table(submission_token text,masked_folio_summary text,registrar_display_name text,expires_at timestamptz) as $$
declare v_reference public.folio_references%rowtype; v_token public.folio_submission_tokens%rowtype; v_normalized text;
begin
  if auth.uid() is null then raise exception 'Folio is unavailable'; end if;
  if not exists(select 1 from public.user_accounts a join public.investor_account_links l on l.user_id=a.user_id where a.user_id=auth.uid() and a.account_state='linked_investor' and l.link_status='active') then raise exception 'Folio is unavailable'; end if;
  if upper(p_registrar) not in ('CAMS','KFINTECH') then raise exception 'Folio is unavailable'; end if;
  v_normalized:=upper(regexp_replace(coalesce(p_folio_number,''),'[^A-Za-z0-9]','','g'));
  select * into v_reference from public.folio_references where registrar=upper(p_registrar) and normalized_folio_number=v_normalized;
  if not found then raise exception 'Folio is unavailable'; end if;
  insert into public.folio_submission_tokens(user_id,folio_reference_id,expires_at) values(auth.uid(),v_reference.id,now()+interval '5 minutes') returning * into v_token;
  return query select encode(extensions.pgp_sym_encrypt(jsonb_build_object('token_id',v_token.token_id,'user_id',auth.uid(),'expires_at',extract(epoch from v_token.expires_at)::bigint)::text,public.verification_candidate_token_secret(),'cipher-algo=aes256, compress-algo=0'),'base64'), public.mask_folio_summary(v_reference.registrar,v_reference.source_folio_masked), case when v_reference.registrar='KFINTECH' then 'KFintech' else 'CAMS' end,v_token.expires_at;
end; $$ language plpgsql security definer set search_path=public,pg_temp;

create or replace function public.submit_folio_verification(p_folio_token text,p_relationship public.folio_holder_relationship,p_idempotency_key uuid)
returns table(request_id uuid,status public.verification_request_status,version integer) as $$
declare r public.verification_requests%rowtype; payload jsonb; t public.folio_submission_tokens%rowtype; begin
  if auth.uid() is null then raise exception 'Folio verification unavailable'; end if;
  begin payload:=extensions.pgp_sym_decrypt(decode(p_folio_token,'base64'),public.verification_candidate_token_secret())::jsonb; exception when others then raise exception 'Folio verification unavailable'; end;
  select * into t from public.folio_submission_tokens where token_id=(payload->>'token_id')::uuid for update;
  if not found or t.user_id<>auth.uid() or payload->>'user_id'<>auth.uid()::text or t.consumed_at is not null or t.expires_at<=now() then raise exception 'Folio verification unavailable'; end if;
  perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text||p_idempotency_key::text,0));
  select * into r from public.verification_requests where user_id=auth.uid() and method_code='folio' and status in ('pending_advisor_review','under_review','more_information_required') order by created_at desc limit 1;
  if found then return query select r.id,r.status,r.version; return; end if;
  update public.folio_submission_tokens set consumed_at=now() where token_id=t.token_id and consumed_at is null;
  insert into public.verification_requests(user_id,method_code,status,submitted_at,expires_at) values(auth.uid(),'folio','pending_advisor_review',now(),now()+interval '30 days') returning * into r;
  insert into public.verification_folio_evidence(request_id,folio_reference_id,holder_relationship,evidence_source) values(r.id,t.folio_reference_id,p_relationship,'INVESTOR_DECLARATION');
  insert into public.verification_events(request_id,subject_user_id,actor_user_id,actor_type,event_type,previous_status,new_status,reason_code) values(r.id,auth.uid(),auth.uid(),'investor','folio_submitted',null,'pending_advisor_review',p_idempotency_key::text);
  return query select r.id,r.status,r.version;
end; $$ language plpgsql security definer set search_path=public,pg_temp;

create or replace function public.get_folio_request_detail(p_request_id uuid) returns table(masked_folio_summary text,status public.verification_request_status,submitted_at timestamptz,resolved_at timestamptz,expires_at timestamptz,holder_relationship public.folio_holder_relationship,version integer,event_count bigint) as $$
begin
  if not public.is_admin() and not exists(select 1 from public.verification_requests where id=p_request_id and user_id=auth.uid()) then raise exception 'Folio request is unavailable'; end if;
  return query select public.mask_folio_summary(f.registrar,f.source_folio_masked),r.status,r.submitted_at,r.resolved_at,r.expires_at,e.holder_relationship,r.version,(select count(*) from public.verification_events v where v.request_id=r.id) from public.verification_requests r join public.verification_folio_evidence e on e.request_id=r.id join public.folio_references f on f.id=e.folio_reference_id where r.id=p_request_id and r.method_code='folio';
end; $$ language plpgsql security definer set search_path=public,pg_temp;

create or replace function public.get_folio_grant_summary(p_request_id uuid) returns table(grant_status public.folio_grant_status,approved_at timestamptz,revoked_at timestamptz,masked_folio_summary text,holder_relationship public.folio_holder_relationship) as $$
begin
  if not public.is_admin() and not exists(select 1 from public.verification_requests where id=p_request_id and user_id=auth.uid()) then raise exception 'Folio grant is unavailable'; end if;
  return query select g.status,g.approved_at,g.revoked_at,public.mask_folio_summary(f.registrar,f.source_folio_masked),g.holder_relationship from public.folio_grants g join public.folio_references f on f.id=g.folio_reference_id where g.request_id=p_request_id;
end; $$ language plpgsql security definer set search_path=public,pg_temp;

revoke all on function public.mask_folio_summary(text,text),public.issue_folio_submission_token(text,text),public.get_folio_request_detail(uuid),public.get_folio_grant_summary(uuid) from public,anon,service_role;
grant execute on function public.issue_folio_submission_token(text,text),public.get_folio_request_detail(uuid),public.get_folio_grant_summary(uuid) to authenticated;
