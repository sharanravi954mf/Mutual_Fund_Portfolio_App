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
