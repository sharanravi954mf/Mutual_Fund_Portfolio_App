-- Sprint 5.3 Phase 1 regression contract. Run after `supabase db reset` in a
-- transaction that seeds authenticated investor/advisor identities.
-- This persistent suite deliberately asserts the security invariants rather
-- than relying on browser UI behavior.
do $$
begin
  if not exists (select 1 from pg_class where relname = 'folio_grants') then
    raise exception 'folio_grants must exist';
  end if;
  if not exists (select 1 from pg_trigger where tgname in ('prevent_folio_evidence_mutation','prevent_verification_event_mutation') group by tgname having count(*) = 1) then
    raise exception 'immutable evidence/event trigger is missing';
  end if;
  if not exists (select 1 from pg_indexes where indexname = 'idx_folio_grants_active_unique') then
    raise exception 'active grant duplicate protection is missing';
  end if;
  if not exists (select 1 from pg_policies where tablename = 'portfolios' and policyname = 'Investors can view granted folio portfolios') then
    raise exception 'folio-scoped portfolio RLS policy is missing';
  end if;
  if not exists (select 1 from pg_policies where tablename = 'transactions' and policyname = 'Investors can view granted folio transactions') then
    raise exception 'folio-scoped transaction RLS policy is missing';
  end if;
  if (select count(*) from pg_proc where proname in ('submit_folio_verification','begin_folio_review','request_folio_more_information','resubmit_folio_verification','approve_folio_verification','reject_folio_verification','cancel_folio_verification','expire_folio_verification','revoke_folio_grant')) <> 9 then
    raise exception 'required folio RPC contract is incomplete';
  end if;
  if has_function_privilege('authenticated', 'public._transition_folio_request(uuid,integer,text,text)'::regprocedure, 'execute')
      or has_function_privilege('authenticated', 'public.issue_folio_submission_token(uuid,uuid)'::regprocedure, 'execute')
      or has_function_privilege('anon', 'public._transition_folio_request(uuid,integer,text,text)'::regprocedure, 'execute')
      or has_function_privilege('anon', 'public.issue_folio_submission_token(uuid,uuid)'::regprocedure, 'execute') then
    raise exception 'private folio helper is browser-executable';
  end if;
  if not has_function_privilege('authenticated', 'public.issue_folio_submission_token(text,text)'::regprocedure, 'execute')
      or has_function_privilege('anon', 'public.issue_folio_submission_token(text,text)'::regprocedure, 'execute') then
    raise exception 'safe folio submission-token RPC privileges are incorrect';
  end if;
  if not exists (
    select 1
    from pg_constraint constraint_row
    join pg_class table_row on table_row.oid = constraint_row.conrelid
    join pg_namespace schema_row on schema_row.oid = table_row.relnamespace
    where schema_row.nspname = 'public'
      and table_row.relname = 'folio_references'
      and constraint_row.contype = 'u'
      and constraint_row.conkey = array[
        (select attnum from pg_attribute where attrelid = table_row.oid and attname = 'registrar' and not attisdropped),
        (select attnum from pg_attribute where attrelid = table_row.oid and attname = 'normalized_folio_number' and not attisdropped)
      ]
  ) then
    raise exception 'registrar-aware canonical uniqueness is missing';
  end if;
  if to_regprocedure('public.issue_folio_submission_token(text,text)') is null
      or to_regprocedure('public.get_folio_request_detail(uuid)') is null
      or to_regprocedure('public.get_folio_grant_summary(uuid)') is null then
    raise exception 'safe folio repository read/token RPC contract is incomplete';
  end if;
  if not exists (select 1 from pg_indexes where indexname='idx_folio_submission_tokens_active') then
    raise exception 'active submission-token replay protection index is missing';
  end if;
  if has_table_privilege('anon', 'public.folio_submission_tokens', 'select')
      or has_table_privilege('authenticated', 'public.folio_submission_tokens', 'select') then
    raise exception 'submission tokens are directly browser-readable';
  end if;
end $$;

-- Sprint 5.6A.1: generic verification RPCs are intentionally non-folio. A
-- browser must use the dedicated assignment-aware folio RPCs instead.
do $$
begin
  if to_regprocedure('public.get_folio_verification_events(uuid)') is null
      or not has_function_privilege('authenticated', 'public.get_folio_verification_events(uuid)'::regprocedure, 'execute')
      or has_function_privilege('anon', 'public.get_folio_verification_events(uuid)'::regprocedure, 'execute') then
    raise exception 'dedicated folio history contract is unavailable';
  end if;
  if has_table_privilege('authenticated', 'public.verification_folio_evidence', 'select')
      or has_table_privilege('authenticated', 'public.folio_grants', 'select')
      or has_table_privilege('authenticated', 'public.verification_request_assignments', 'select')
      or has_table_privilege('authenticated', 'public.folio_references', 'select') then
    raise exception 'folio security tables are directly browser-readable';
  end if;
  if has_function_privilege('authenticated', 'public._reject_generic_folio_request(uuid)'::regprocedure, 'execute')
      or has_function_privilege('authenticated', 'public.validate_folio_review_reason_code(text,text,public.folio_holder_relationship)'::regprocedure, 'execute') then
    raise exception 'folio authorization helpers are browser-executable';
  end if;
end $$;

begin;
do $$
declare
  advisor_id uuid := '53000000-0000-0000-0000-000000000201';
  investor_id uuid := '53000000-0000-0000-0000-000000000202';
  generic_investor_id uuid := '53000000-0000-0000-0000-000000000203';
  profile_id uuid := '53000000-0000-0000-0000-000000000204';
  folio_id uuid;
  folio_request_id uuid;
  generic_request_id uuid;
  before_version integer;
  before_events integer;
  rejected boolean := false;
begin
  insert into auth.users (id,aud,role,email,raw_app_meta_data,raw_user_meta_data)
  values
    (advisor_id,'authenticated','authenticated','folio-legacy-advisor@example.test','{}'::jsonb,'{}'::jsonb),
    (investor_id,'authenticated','authenticated','folio-legacy-investor@example.test','{}'::jsonb,'{}'::jsonb),
    (generic_investor_id,'authenticated','authenticated','generic-investor@example.test','{}'::jsonb,'{}'::jsonb);
  update public.user_accounts set account_state='advisor' where user_id=advisor_id;
  update public.user_accounts set account_state='linked_investor' where user_id=investor_id;
  update public.user_accounts set account_state='link_pending' where user_id=generic_investor_id;
  insert into public.profiles(id,full_name,role) values(profile_id,'Legacy bypass test','client');
  insert into public.investor_account_links(user_id,profile_id,verification_method,link_status)
  values(investor_id,profile_id,'test','active');
  insert into public.folio_references(registrar,normalized_folio_number,amc_identity,source_folio_masked)
  values('CAMS','LEGACYBYPASS2026','legacy-bypass-amc','••••2026') returning id into folio_id;
  insert into public.verification_requests(user_id,method_code,status,submitted_at,expires_at)
  values(investor_id,'folio','pending_advisor_review',now(),now()+interval '30 days') returning id,version into folio_request_id,before_version;
  insert into public.verification_folio_evidence(request_id,folio_reference_id,holder_relationship,evidence_source)
  values(folio_request_id,folio_id,'SOLE_HOLDER','INVESTOR_DECLARATION');
  insert into public.verification_request_assignments(request_id,advisor_account_id)
  values(folio_request_id,advisor_id);
  select count(*) into before_events from public.verification_events where request_id=folio_request_id;

  perform set_config('request.jwt.claim.sub',advisor_id::text,true);
  if exists(select 1 from public.list_verification_review_queue() where id=folio_request_id)
      or exists(select 1 from public.list_verification_review_queue_filtered(null,null,null) where id=folio_request_id) then
    raise exception 'generic advisor queue exposes a folio request';
  end if;
  begin perform * from public.get_verification_review(folio_request_id); exception when sqlstate 'PFL01' then rejected:=true; end;
  if not rejected then raise exception 'generic review detail accepts a folio request'; end if;
  rejected:=false;
  begin perform public.reject_verification_request(folio_request_id,before_version,'INVALID_FOLIO'); exception when sqlstate 'PFL01' then rejected:=true; end;
  if not rejected then raise exception 'generic rejection accepts a folio request'; end if;
  rejected:=false;
  begin perform public.request_more_verification_information(folio_request_id,before_version,'FOLIO_DOCUMENT_REQUIRED'); exception when sqlstate 'PFL01' then rejected:=true; end;
  if not rejected then raise exception 'generic information request accepts a folio request'; end if;
  rejected:=false;
  begin perform public.approve_verification_request(folio_request_id,profile_id,before_version,'x'); exception when sqlstate 'PFL01' then rejected:=true; end;
  if not rejected then raise exception 'generic approval accepts a folio request'; end if;
  rejected:=false;
  begin perform public.approve_verification_candidate(folio_request_id,'not-a-token',before_version,'x'); exception when sqlstate 'PFL01' then rejected:=true; end;
  if not rejected then raise exception 'generic candidate approval accepts a folio request'; end if;
  rejected:=false;
  begin perform public.search_verification_candidates(folio_request_id,'Le'); exception when sqlstate 'PFL01' then rejected:=true; end;
  if not rejected then raise exception 'generic candidate search accepts a folio request'; end if;
  if (select version from public.verification_requests where id=folio_request_id) <> before_version
      or (select count(*) from public.verification_events where request_id=folio_request_id) <> before_events
      or exists(select 1 from public.folio_grants where request_id=folio_request_id) then
    raise exception 'a rejected generic folio operation mutated state';
  end if;

  perform set_config('request.jwt.claim.sub',investor_id::text,true);
  rejected:=false;
  begin perform public.cancel_verification_request(folio_request_id,before_version); exception when sqlstate 'PFL01' then rejected:=true; end;
  if not rejected then raise exception 'generic cancellation accepts a folio request'; end if;
  rejected:=false;
  begin perform * from public.get_verification_events(folio_request_id); exception when sqlstate 'PFL01' then rejected:=true; end;
  if not rejected then raise exception 'generic history accepts a folio request'; end if;
  if exists(select 1 from public.get_verification_status() where id=folio_request_id) then
    raise exception 'generic investor status exposes a folio request';
  end if;

  perform set_config('request.jwt.claim.sub',generic_investor_id::text,true);
  rejected:=false;
  begin perform * from public.create_verification_request('folio'); exception when sqlstate 'PFL01' then rejected:=true; end;
  if not rejected or exists(select 1 from public.verification_requests where user_id=generic_investor_id and method_code='folio') then
    raise exception 'generic folio creation is not atomic';
  end if;
  select request_id into generic_request_id from public.create_verification_request('advisor_assisted');
  if generic_request_id is null or not exists(select 1 from public.verification_requests where id=generic_request_id and method_code='advisor_assisted') then
    raise exception 'non-folio generic creation is no longer compatible';
  end if;
end $$;
rollback;

-- Sprint 5.6A: Advisor folio review must be assignment-scoped. These checks
-- exercise the browser-facing safe projections and explicit decision RPCs.
do $$
begin
  if to_regclass('public.verification_request_assignments') is null then
    raise exception 'folio review assignment table is missing';
  end if;
  if not exists (
    select 1 from pg_indexes
    where schemaname = 'public'
      and indexname = 'idx_verification_request_assignments_active_request'
  ) then
    raise exception 'one active folio review assignment is not enforced';
  end if;
  if not exists (
    select 1 from pg_trigger
    where tgname = 'validate_folio_request_assignment'
      and tgrelid = 'public.verification_request_assignments'::regclass
  ) then
    raise exception 'folio review assignment advisor validation is missing';
  end if;
  if to_regprocedure('public.get_my_advisor_folio_requests(integer,integer,public.verification_request_status)') is null
      or to_regprocedure('public.get_my_advisor_folio_request_detail(uuid)') is null then
    raise exception 'assignment-safe advisor folio read contract is incomplete';
  end if;
  if has_table_privilege('authenticated', 'public.verification_request_assignments', 'select')
      or has_function_privilege('authenticated', 'public._assert_assigned_folio_advisor(uuid)'::regprocedure, 'execute')
      or has_function_privilege('authenticated', 'public.normalize_folio_review_reason_code(text)'::regprocedure, 'execute') then
    raise exception 'folio review assignment helpers are browser-accessible';
  end if;
  if not has_function_privilege('authenticated', 'public.get_my_advisor_folio_requests(integer,integer,public.verification_request_status)'::regprocedure, 'execute')
      or not has_function_privilege('authenticated', 'public.get_my_advisor_folio_request_detail(uuid)'::regprocedure, 'execute') then
    raise exception 'safe advisor folio read RPC privileges are incorrect';
  end if;
end $$;

begin;
do $$
declare
  advisor_a uuid := '53000000-0000-0000-0000-000000000101';
  advisor_b uuid := '53000000-0000-0000-0000-000000000102';
  investor_a uuid := '53000000-0000-0000-0000-000000000103';
  profile_a uuid := '53000000-0000-0000-0000-000000000104';
  folio_a uuid;
  request_a uuid;
  queue_row record;
  detail_row record;
  transition_row record;
  denied boolean := false;
begin
  insert into auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data)
  values
    (advisor_a, 'authenticated', 'authenticated', 'advisor-a@example.test', '{}'::jsonb, '{}'::jsonb),
    (advisor_b, 'authenticated', 'authenticated', 'advisor-b@example.test', '{}'::jsonb, '{}'::jsonb),
    (investor_a, 'authenticated', 'authenticated', 'investor-review@example.test', '{}'::jsonb, '{}'::jsonb);
  update public.user_accounts set account_state = 'advisor'
    where user_id in (advisor_a, advisor_b);
  update public.user_accounts set account_state = 'linked_investor'
    where user_id = investor_a;
  insert into public.profiles (id, full_name, role)
  values (profile_a, 'Advisor Review Investor', 'client');
  insert into public.investor_account_links (user_id, profile_id, verification_method, link_status)
  values (investor_a, profile_a, 'test', 'active');
  insert into public.folio_references (
    registrar, normalized_folio_number, amc_identity, source_folio_masked
  ) values ('CAMS', 'ADVISORFOLIO1234', 'advisor-review-amc', '••••1234')
  returning id into folio_a;
  insert into public.verification_requests (
    user_id, method_code, status, submitted_at, expires_at
  ) values (
    investor_a, 'folio', 'pending_advisor_review', now(), now() + interval '30 days'
  ) returning id into request_a;
  insert into public.verification_folio_evidence (
    request_id, folio_reference_id, holder_relationship, evidence_source
  ) values (request_a, folio_a, 'SOLE_HOLDER', 'INVESTOR_DECLARATION');
  insert into public.verification_request_assignments (
    request_id, advisor_account_id
  ) values (request_a, advisor_a);

  perform set_config('request.jwt.claim.sub', advisor_a::text, true);
  select * into queue_row from public.get_my_advisor_folio_requests(0, 25, null);
  if queue_row.request_id <> request_a
      or queue_row.masked_folio <> repeat('•', length('ADVISORFOLIO1234') - 4) || '1234'
      or queue_row.registrar_display <> 'CAMS'
      or queue_row.investor_display_label <> 'Investor request' then
    raise exception 'assigned advisor queue projection is incorrect';
  end if;
  select * into detail_row from public.get_my_advisor_folio_request_detail(request_a);
  if detail_row.request_id <> request_a
      or detail_row.event_summary <> '[]'::jsonb
      or detail_row.masked_folio <> repeat('•', length('ADVISORFOLIO1234') - 4) || '1234' then
    raise exception 'assigned advisor detail projection is incorrect';
  end if;
  select * into transition_row from public.begin_folio_review(request_a, 1);
  if transition_row.status <> 'under_review' or transition_row.version <> 2 then
    raise exception 'assigned advisor cannot begin a valid folio review';
  end if;
  if (select count(*) from public.verification_events
      where request_id = request_a and event_type = 'folio_review_started') <> 1 then
    raise exception 'folio review transition did not append exactly one event';
  end if;
  begin
    perform * from public.begin_folio_review(request_a, 1);
  exception when others then denied := true;
  end;
  if not denied then raise exception 'stale folio review version was accepted'; end if;

  denied := false;
  perform set_config('request.jwt.claim.sub', advisor_b::text, true);
  begin
    perform * from public.get_my_advisor_folio_request_detail(request_a);
  exception when others then denied := true;
  end;
  if not denied then raise exception 'unassigned advisor can read folio review detail'; end if;
  denied := false;
  begin
    perform * from public.reject_folio_verification(request_a, 2, 'INVALID_FOLIO');
  exception when others then denied := true;
  end;
  if not denied then raise exception 'unassigned advisor can decide folio request'; end if;

  denied := false;
  perform set_config('request.jwt.claim.sub', investor_a::text, true);
  begin
    perform * from public.get_my_advisor_folio_requests(0, 25, null);
  exception when others then denied := true;
  end;
  if not denied then raise exception 'investor can access advisor folio queue'; end if;
end $$;
rollback;

-- Exercise the RPC as two distinct authenticated identities. The transaction
-- is rolled back so the regression suite never changes seeded application data.
begin;
do $$
declare
  investor_a uuid := '53000000-0000-0000-0000-000000000001';
  investor_b uuid := '53000000-0000-0000-0000-000000000002';
  profile_a uuid := '53000000-0000-0000-0000-000000000011';
  profile_b uuid := '53000000-0000-0000-0000-000000000012';
  folio_a uuid;
  folio_b uuid;
  request_a_older uuid;
  request_a_newer uuid;
  request_b uuid;
  first_row record;
  second_page_row record;
  forbidden_error boolean := false;
begin
  insert into auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data)
  values
    (investor_a, 'authenticated', 'authenticated', 'folio-a@example.test', '{}'::jsonb, '{}'::jsonb),
    (investor_b, 'authenticated', 'authenticated', 'folio-b@example.test', '{}'::jsonb, '{}'::jsonb);

  update public.user_accounts
  set account_state = 'linked_investor'
  where user_id in (investor_a, investor_b);
  insert into public.profiles (id, full_name, role)
  values (profile_a, 'Folio Test A', 'client'), (profile_b, 'Folio Test B', 'client');
  insert into public.investor_account_links (user_id, profile_id, verification_method, link_status)
  values
    (investor_a, profile_a, 'test', 'active'),
    (investor_b, profile_b, 'test', 'active');

  insert into public.folio_references (registrar, normalized_folio_number, amc_identity, source_folio_masked)
  values ('CAMS', 'FOLIOA12345', 'test-amc-a', '••••2345')
  returning id into folio_a;
  insert into public.folio_references (registrar, normalized_folio_number, amc_identity, source_folio_masked)
  values ('KFINTECH', 'FOLIOB67890', 'test-amc-b', '••••7890')
  returning id into folio_b;

  insert into public.verification_requests (user_id, method_code, status, submitted_at, created_at)
  values (investor_a, 'folio', 'approved', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
  returning id into request_a_older;
  insert into public.verification_folio_evidence (request_id, folio_reference_id, holder_relationship, evidence_source)
  values (request_a_older, folio_a, 'SOLE_HOLDER', 'INVESTOR_DECLARATION');

  insert into public.verification_requests (user_id, method_code, status, submitted_at, created_at)
  values (investor_a, 'folio', 'pending_advisor_review', '2026-01-02T00:00:00Z', '2026-01-02T00:00:00Z')
  returning id into request_a_newer;
  insert into public.verification_folio_evidence (request_id, folio_reference_id, holder_relationship, evidence_source)
  values (request_a_newer, folio_a, 'SOLE_HOLDER', 'INVESTOR_DECLARATION');

  insert into public.verification_requests (user_id, method_code, status, submitted_at, created_at)
  values (investor_b, 'folio', 'pending_advisor_review', '2026-01-03T00:00:00Z', '2026-01-03T00:00:00Z')
  returning id into request_b;
  insert into public.verification_folio_evidence (request_id, folio_reference_id, holder_relationship, evidence_source)
  values (request_b, folio_b, 'SOLE_HOLDER', 'INVESTOR_DECLARATION');

  perform set_config('request.jwt.claim.sub', investor_a::text, true);
  select * into first_row from public.get_my_folio_requests(0, 1);
  if first_row.request_id <> request_a_newer
      or first_row.masked_folio <> '•••••••2345'
      or first_row.registrar_display <> 'CAMS' then
    raise exception 'safe folio list does not return the deterministic masked investor projection';
  end if;
  select * into second_page_row from public.get_my_folio_requests(1, 1);
  if second_page_row.request_id <> request_a_older then
    raise exception 'safe folio list pagination is not deterministic';
  end if;
  if exists (select 1 from public.get_my_folio_requests(0, 100) where request_id = request_b) then
    raise exception 'safe folio list leaks another investor request';
  end if;
  begin
    perform * from public.get_my_folio_requests(-1, 1);
  exception when others then
    forbidden_error := true;
  end;
  if not forbidden_error then
    raise exception 'safe folio list accepts invalid pagination';
  end if;

  perform set_config('request.jwt.claim.sub', investor_b::text, true);
  if exists (select 1 from public.get_my_folio_requests(0, 100) where request_id in (request_a_older, request_a_newer)) then
    raise exception 'safe folio list cross-investor isolation is incomplete';
  end if;
end $$;
rollback;

-- Sprint 5.3.7 safe-list contract. These assertions validate the browser
-- boundary without requiring any client-visible canonical folio fixture.
do $$
declare
  result_contract text;
  function_definition text;
  compact_definition text;
begin
  if has_function_privilege('anon', 'public.get_my_folio_requests(integer,integer)'::regprocedure, 'execute')
      or not has_function_privilege('authenticated', 'public.get_my_folio_requests(integer,integer)'::regprocedure, 'execute') then
    raise exception 'safe folio list authentication boundary is incorrect';
  end if;

  if has_function_privilege('anon', 'public.mask_canonical_folio(text)'::regprocedure, 'execute')
      or has_function_privilege('authenticated', 'public.mask_canonical_folio(text)'::regprocedure, 'execute') then
    raise exception 'safe folio list helper is browser-executable';
  end if;

  if not exists (
    select 1
    from pg_proc procedure_row
    where procedure_row.oid = 'public.get_my_folio_requests(integer,integer)'::regprocedure
      and procedure_row.prosecdef
  ) then
    raise exception 'safe folio list RPC must remain security definer';
  end if;

  select lower(pg_get_function_result('public.get_my_folio_requests(integer,integer)'::regprocedure))
  into result_contract;
  if result_contract not like '%request_id uuid%'
      or result_contract not like '%version integer%'
      or result_contract not like '%registrar_display text%'
      or result_contract not like '%masked_folio text%'
      or result_contract !~ 'status[[:space:]]+(public\.)?verification_request_status'
      or result_contract not like '%submitted_at timestamp with time zone%'
      or result_contract like '%folio_reference_id%'
      or result_contract like '%normalized_folio%'
      or result_contract like '%profile_id%'
      or result_contract like '%account_link%'
      or result_contract like '%submission_token%'
      or result_contract like '%pan%' then
    raise exception 'safe folio list projection exposes an invalid response shape';
  end if;

  select lower(pg_get_functiondef('public.get_my_folio_requests(integer,integer)'::regprocedure))
  into function_definition;
  compact_definition := regexp_replace(function_definition, '[[:space:]]+', '', 'g');
  if compact_definition not like '%wherer.user_id=auth.uid()andr.method_code=''folio''%'
      or compact_definition not like '%orderbyr.submitted_atdescnullslast,r.created_atdesc,r.iddesc%'
      or compact_definition not like '%limitp_page_sizeoffsetp_page*p_page_size%'
      or compact_definition not like '%p_page<0%'
      or compact_definition not like '%p_page_size>100%' then
    raise exception 'safe folio list ownership, ordering, or pagination contract is incomplete';
  end if;

  if public.mask_canonical_folio('ABC') <> '•••'
      or public.mask_canonical_folio('ABCDE') <> '•BCDE' then
    raise exception 'safe folio list masking contract is incorrect';
  end if;

  if not exists (
    select 1
    from pg_constraint constraint_row
    join pg_class table_row on table_row.oid = constraint_row.conrelid
    where table_row.relname = 'verification_folio_evidence'
      and constraint_row.contype = 'u'
      and constraint_row.conkey = array[
        (select attnum from pg_attribute where attrelid = table_row.oid and attname = 'request_id' and not attisdropped)
      ]
  ) then
    raise exception 'safe folio list could duplicate request rows';
  end if;
end $$;
