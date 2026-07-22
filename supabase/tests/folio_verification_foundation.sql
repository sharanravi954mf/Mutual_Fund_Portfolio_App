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
