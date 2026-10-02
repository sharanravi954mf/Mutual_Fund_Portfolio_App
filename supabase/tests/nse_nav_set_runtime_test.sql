\set ON_ERROR_STOP on
BEGIN;
SELECT 1 FROM vault.create_secret(repeat('s',40),'integration_payload_encryption_key_v1','B06.4 synthetic rollback-only key');
INSERT INTO auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES
 ('b0640000-0000-4000-8000-000000000001','authenticated','authenticated','b064-one@moneybowl.invalid','{}','{}',now(),now()),
 ('b0640000-0000-4000-8000-000000000002','authenticated','authenticated','b064-two@moneybowl.invalid','{}','{}',now(),now());
INSERT INTO public.workspaces(id,name,slug,owner_profile_id,workspace_status)
SELECT ('b0640000-0000-4000-8001-'||right(user_id::text,12))::uuid,'B06 synthetic','b064-'||right(user_id::text,1),id,'active'
 FROM public.profiles WHERE user_id IN ('b0640000-0000-4000-8000-000000000001','b0640000-0000-4000-8000-000000000002');
INSERT INTO nse_reference.connections(id,workspace_id,environment,member_code,api_base_url,enabled)
VALUES('b0640000-0000-4000-8002-000000000001','b0640000-0000-4000-8001-000000000001','UAT','05418','https://nse.example.test',true);
CREATE TEMP TABLE b064_assertions(label text);
CREATE FUNCTION pg_temp.ok(b boolean,label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF b IS DISTINCT FROM true THEN RAISE EXCEPTION 'assertion_failed:%',label; END IF; INSERT INTO b064_assertions VALUES(label); END $$;
CREATE FUNCTION pg_temp.err(statement text,expected text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 BEGIN EXECUTE statement; EXCEPTION WHEN OTHERS THEN
  IF strpos(SQLERRM,expected)>0 THEN INSERT INTO b064_assertions VALUES('reject:'||expected); RETURN; END IF;
  RAISE EXCEPTION 'wrong_error:% expected:%',SQLERRM,expected;
 END;
 RAISE EXCEPTION 'missing_error:%',expected;
END $$;
CREATE FUNCTION pg_temp.nav_file(body text,kind text DEFAULT 'NAV') RETURNS uuid LANGUAGE plpgsql AS $$
BEGIN RETURN (pg_temp.stage(pg_temp.store_file(kind,convert_to(body,'UTF8')))->>'snapshot_id')::uuid; END $$;
CREATE FUNCTION pg_temp.validate_nav(s uuid) RETURNS jsonb LANGUAGE sql AS $$
 SELECT public.validate_nse_nav_snapshot('b0640000-0000-4000-8001-000000000001',s);
$$;
CREATE FUNCTION pg_temp.bad_nav(body text,code text,line integer DEFAULT 1) RETURNS void LANGUAGE plpgsql AS $$
DECLARE s uuid:=pg_temp.nav_file(body); r jsonb;
BEGIN
 r:=pg_temp.validate_nav(s);
 PERFORM pg_temp.ok(r->>'status'='REJECTED' AND r->>'rejection_code'=code AND r->>'row_count'='0'
   AND (r->>'rejected_line')::integer IS NOT DISTINCT FROM line,'rejected:'||code);
 PERFORM pg_temp.ok(NOT EXISTS(SELECT 1 FROM nse_nav.observations WHERE snapshot_id=s),'reject_is_atomic');
 PERFORM pg_temp.ok(pg_temp.validate_nav(s)=r,'rejection_replay');
 PERFORM pg_temp.err(format('SELECT public.read_nse_nav_observations(%L,%L)',
   'b0640000-0000-4000-8001-000000000001',s),'nse_nav_not_validated');
END $$;
CREATE FUNCTION pg_temp.queue(k text,key uuid DEFAULT gen_random_uuid()) RETURNS uuid LANGUAGE sql AS $$
 SELECT (public.prepare_nse_master_download('b0640000-0000-4000-8001-000000000001','b0640000-0000-4000-8002-000000000001',k,key)->>'event_outbox_id')::uuid;
$$;
CREATE FUNCTION pg_temp.capture(e uuid,t uuid,body text,kind text DEFAULT 'COMPLETE') RETURNS void LANGUAGE plpgsql AS $$
DECLARE b bytea:=convert_to(body,'UTF8'); pos integer:=0; chunk bytea;
BEGIN
 PERFORM public.begin_nse_master_job_capture(e,t,gen_random_uuid(),'UAT','05418','https://nse.example.test');
 WHILE pos<octet_length(b) LOOP
  chunk:=substring(b FROM pos+1 FOR 262144);
  PERFORM public.append_nse_master_job_chunk(e,t,pos/262144,replace(encode(chunk,'base64'),E'\n',''),encode(extensions.digest(chunk,'sha256'),'hex'));
  pos:=pos+262144;
 END LOOP;
 PERFORM public.finish_nse_master_job_capture(e,t,kind,200,'TEXT',octet_length(b),true,true,
  CASE WHEN kind='COMPLETE' THEN encode(extensions.digest(b,'sha256'),'hex') END);
END $$;
CREATE FUNCTION pg_temp.forbid_publication() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'b064_publication_forbidden'; END $$;
CREATE TRIGGER b064_no_funds BEFORE INSERT OR UPDATE OR DELETE ON public.mutual_funds FOR EACH STATEMENT EXECUTE FUNCTION pg_temp.forbid_publication();
CREATE TRIGGER b064_no_crosswalk BEFORE INSERT OR UPDATE OR DELETE ON nse_reference.scheme_crosswalk_candidates FOR EACH STATEMENT EXECUTE FUNCTION pg_temp.forbid_publication();
CREATE TRIGGER b064_no_sch BEFORE INSERT OR UPDATE OR DELETE ON nse_reference.sch_rows FOR EACH STATEMENT EXECUTE FUNCTION pg_temp.forbid_publication();
CREATE TRIGGER b064_no_operations BEFORE INSERT OR UPDATE OR DELETE ON public.integration_operations FOR EACH STATEMENT EXECUTE FUNCTION pg_temp.forbid_publication();
DO $$ DECLARE
 k text; e uuid; t uuid:=gen_random_uuid(); key uuid; c jsonb; r jsonb; summary jsonb; s uuid; prior uuid; bad text; fn regprocedure;
 body text:='2026-09-30|NSE-A|Synthetic Growth|RTA-A|Z|INF000000001|123.4500|CAMS';
BEGIN
 PERFORM pg_temp.ok((SELECT parser_version='NSE_NAV_WEB83_V1' AND function_name='validate_nav_v1' FROM nse_reference.validators WHERE file_type='NAV'),'nav_registration');
 PERFORM pg_temp.ok((SELECT parser_version='NSE_SET_EVIDENCE_V1' AND function_name='validate_set_v1' FROM nse_reference.validators WHERE file_type='SET'),'set_registration');
 FOREACH k IN ARRAY ARRAY['NAV','SET'] LOOP
  key:=gen_random_uuid(); e:=pg_temp.queue(k,key);
  PERFORM pg_temp.ok(pg_temp.queue(k,key)=e,'prepare_replay:'||k);
  PERFORM pg_temp.err(format('SELECT pg_temp.queue(%L,%L)',CASE k WHEN 'NAV' THEN 'SET' ELSE 'NAV' END,key),'idempotency_conflict');
  PERFORM pg_temp.ok((SELECT event_type='integration.nse.master_download_requested' AND entity_type='nse_reference_job' AND payload='{}'::jsonb FROM public.event_outbox WHERE id=e),'shared_event:'||k);
  PERFORM pg_temp.ok((SELECT count(*)=1 FROM public.list_dispatchable_outbox_events(ARRAY['integration.nse.master_download_requested']) WHERE event_outbox_id=e),'shared_dispatch:'||k);
  c:=public.claim_nse_master_download(e,t);
  PERFORM pg_temp.ok(c->>'file_type'=k AND c->>'environment'='UAT','owned_variant:'||k);
  PERFORM pg_temp.capture(e,t,CASE k WHEN 'NAV' THEN body ELSE 'MF|20260000001|30-09-2026|01-10-2026|01-10-2026|01-10-2026|01-10-2026' END);
  -- Sealed capture recovery uses FINALIZE with a fresh lease, never another HTTP send.
  UPDATE public.event_outbox SET claim_expires_at=now()-interval '1 second' WHERE id=e;
  PERFORM pg_temp.err(format('SELECT public.finalize_nse_master_download(%L,%L)',e,t),'claim_not_owned');
  t:=gen_random_uuid();
  PERFORM pg_temp.ok(public.claim_nse_master_download(e,t)->>'action'='FINALIZE','recover_without_recapture:'||k);
  r:=public.finalize_nse_master_download(e,t); s:=(r->>'snapshot_id')::uuid;
  PERFORM pg_temp.ok(r->>'outcome'=CASE k WHEN 'NAV' THEN 'STAGED_VALIDATED' ELSE 'REJECTED' END,'honest_outcome:'||k);
  PERFORM pg_temp.ok(public.finalize_nse_master_download(e,t)=r,'finalize_replay:'||k);
  PERFORM pg_temp.ok(public.claim_nse_master_download(e,gen_random_uuid())->>'action'='DONE','terminal_no_recapture:'||k);
  PERFORM pg_temp.ok((SELECT status='completed' AND claim_token IS NULL FROM public.event_outbox WHERE id=e),'terminal_event:'||k);
  SELECT public.get_nse_master_download_job(workspace_id,id) INTO summary FROM nse_reference.jobs WHERE event_id=e;
  PERFORM pg_temp.ok(summary->>'publication_gate'='BLOCKED' AND summary->>'file_type'=k,'summary_gated:'||k);
  PERFORM pg_temp.ok(summary->>'validation_scope'=CASE k WHEN 'NAV' THEN 'DOCUMENT_BACKED_UNCOMMISSIONED_OBSERVATIONS' ELSE 'EVIDENCE_ONLY_LAYOUT_UNCHARACTERIZED' END,'summary_scope:'||k);
  PERFORM pg_temp.ok(summary->>'category'=CASE k WHEN 'NAV' THEN 'nse_reference_nav_observations_uncommissioned' ELSE 'nse_reference_set_layout_uncharacterized' END,'summary_category:'||k);
  PERFORM pg_temp.ok((SELECT v.source_sha256=x.response_sha256 AND v.publication_gate='BLOCKED' AND v.rejected_rows=0 FROM nse_reference.validations v JOIN nse_reference.snapshots sn ON sn.id=v.snapshot_id JOIN nse_reference.results x ON x.download_id=sn.download_id WHERE sn.id=s),'shared_evidence_digest:'||k);
  PERFORM pg_temp.ok((SELECT stage='STAGED_UNVALIDATED' FROM nse_reference.snapshots WHERE id=s),'foundation_not_rewritten:'||k);
  PERFORM pg_temp.ok((SELECT count(*)=1 FROM public.workspace_audit_logs WHERE entity_id=s AND action='nse.reference.validation'),'shared_audit_once:'||k);
  IF k='NAV' THEN
   prior:=s;
   PERFORM pg_temp.ok((SELECT status='VALIDATED_OBSERVATIONS' AND api_compatibility='UNCOMMISSIONED' AND publication_state='BLOCKED_CROSSWALK_AND_SOURCE_POLICY' FROM nse_nav.validations WHERE snapshot_id=s),'typed_uncommissioned');
   PERFORM pg_temp.ok(public.read_nse_nav_observations('b0640000-0000-4000-8001-000000000001',s)->'observations'->0->>'nav_value'='123.4500','exact_observation');
  ELSE
   PERFORM pg_temp.ok((SELECT status='BLOCKED_LAYOUT_UNCHARACTERIZED' FROM nse_set.assessments WHERE snapshot_id=s),'set_domain_block');
   PERFORM pg_temp.ok(summary->>'row_count'='0' AND summary->>'rejected_rows'='0','set_no_invented_row_count');
   PERFORM pg_temp.ok(NOT EXISTS(SELECT 1 FROM nse_nav.observations WHERE snapshot_id=s),'set_no_nav_rows');
  END IF;
  PERFORM pg_temp.err(format('SELECT nse_reference.validate_snapshot(%L,%L)','b0640000-0000-4000-8001-000000000002',s),'snapshot_unavailable');
  PERFORM pg_temp.err(format('SELECT public.get_nse_master_download_job(%L,%L)','b0640000-0000-4000-8001-000000000002',summary->>'job_id'),'job_unavailable');
  UPDATE nse_reference.connections SET enabled=false;
  PERFORM pg_temp.err(format('SELECT public.finalize_nse_master_download(%L,%L)',e,t),'connection_unavailable');
  PERFORM pg_temp.err(format('SELECT nse_reference.validate_snapshot(%L,%L)','b0640000-0000-4000-8001-000000000001',s),'connection_unavailable');
  UPDATE nse_reference.connections SET enabled=true;
  UPDATE public.workspaces SET workspace_status='suspended' WHERE id='b0640000-0000-4000-8001-000000000001';
  PERFORM pg_temp.err(format('SELECT public.finalize_nse_master_download(%L,%L)',e,t),'workspace_unavailable');
  UPDATE public.workspaces SET workspace_status='active' WHERE id='b0640000-0000-4000-8001-000000000001';
 END LOOP;
 -- Invalid NAV and row overflow are terminal zero-row validation receipts, not worker failures.
 FOREACH bad IN ARRAY ARRAY[body||E'\n'||replace(body,'123.4500','NaN'),repeat(E'a|b\n',100001)] LOOP
  e:=pg_temp.queue('NAV'); PERFORM public.claim_nse_master_download(e,t); PERFORM pg_temp.capture(e,t,bad);
  r:=public.finalize_nse_master_download(e,t); s:=(r->>'snapshot_id')::uuid;
  PERFORM pg_temp.ok(r->>'outcome'='REJECTED','bad_nav_terminal');
  PERFORM pg_temp.ok((SELECT status='REJECTED' AND row_count=0 FROM nse_nav.validations WHERE snapshot_id=s),'bad_nav_domain_receipt');
  PERFORM pg_temp.ok(NOT EXISTS(SELECT 1 FROM nse_nav.observations WHERE snapshot_id=s),'bad_nav_atomic_no_rows');
 END LOOP;
 -- Corrections create a fresh observation version; prior snapshot reads stay pinned.
 e:=pg_temp.queue('NAV'); PERFORM public.claim_nse_master_download(e,t); PERFORM pg_temp.capture(e,t,replace(body,'123.4500','124.4500'));
 r:=public.finalize_nse_master_download(e,t); s:=(r->>'snapshot_id')::uuid;
 PERFORM pg_temp.ok(s<>prior AND (SELECT nav_lexeme='124.4500' FROM nse_nav.observations WHERE snapshot_id=s),'new_capture_correction');
 PERFORM pg_temp.ok(public.read_nse_nav_observations('b0640000-0000-4000-8001-000000000001',prior)->'observations'->0->>'nav_value'='123.4500','old_snapshot_stays_pinned');
 -- SET JSON errors cannot gain a domain assessment. Incomplete NAV/SET cannot stage.
 FOREACH k IN ARRAY ARRAY['NAV','SET'] LOOP
  e:=pg_temp.queue(k); PERFORM public.claim_nse_master_download(e,t); PERFORM pg_temp.capture(e,t,body,'TRUNCATED');
  PERFORM pg_temp.ok(public.finalize_nse_master_download(e,t)='{"outcome":"CAPTURE_FAILED","snapshot_id":null}'::jsonb,'incomplete_capture:'||k);
 END LOOP;
 e:=pg_temp.queue('SET'); PERFORM public.claim_nse_master_download(e,t); PERFORM pg_temp.capture(e,t,'{"error":"a|b"}');
 PERFORM pg_temp.ok(public.finalize_nse_master_download(e,t)='{"outcome":"CAPTURE_FAILED","snapshot_id":null}'::jsonb,'set_error_is_not_file');
 FOR fn IN SELECT p.oid::regprocedure FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='nse_reference' AND p.proname IN ('validate_nav_v1','validate_set_v1') LOOP
  PERFORM pg_temp.ok(NOT has_function_privilege('anon',fn,'EXECUTE') AND NOT has_function_privilege('authenticated',fn,'EXECUTE') AND NOT has_function_privilege('service_role',fn,'EXECUTE'),'private_adapter_acl');
  PERFORM pg_temp.ok((SELECT prosecdef AND proconfig @> ARRAY['search_path=""'] FROM pg_proc WHERE oid=fn),'adapter_empty_path');
  PERFORM pg_temp.ok(NOT EXISTS(SELECT 1 FROM pg_proc p,LATERAL aclexplode(COALESCE(p.proacl,acldefault('f',p.proowner))) a WHERE p.oid=fn AND a.grantee=0 AND a.privilege_type='EXECUTE'),'adapter_no_public_acl');
 END LOOP;
END $$;
-- Completion failure must roll back snapshot, domain/shared receipts, rows and audits.
CREATE FUNCTION pg_temp.reject_completion() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'synthetic_completion_failure'; END $$;
DO $$ DECLARE k text; e uuid; t uuid:=gen_random_uuid(); c jsonb; before_nav bigint; before_set bigint; before_shared bigint; before_audit bigint;
BEGIN
 FOREACH k IN ARRAY ARRAY['NAV','SET'] LOOP
  e:=pg_temp.queue(k); c:=public.claim_nse_master_download(e,t);
  PERFORM pg_temp.capture(e,t,CASE k WHEN 'NAV' THEN '2026-09-30|NSE-A|Synthetic Growth|RTA-A|Z|INF000000001|123.4500|CAMS' ELSE 'unknown|SET|format' END);
  SELECT count(*) INTO before_nav FROM nse_nav.observations;
  SELECT count(*) INTO before_set FROM nse_set.assessments;
  SELECT count(*) INTO before_shared FROM nse_reference.validations;
  SELECT count(*) INTO before_audit FROM public.workspace_audit_logs;
  CREATE TRIGGER b064_no_completion BEFORE INSERT ON nse_reference.completions FOR EACH ROW EXECUTE FUNCTION pg_temp.reject_completion();
  PERFORM pg_temp.err(format('SELECT public.finalize_nse_master_download(%L,%L)',e,t),'synthetic_completion_failure');
  PERFORM pg_temp.ok(NOT EXISTS(SELECT 1 FROM nse_reference.snapshots WHERE download_id=(c->>'download_id')::uuid),'atomic_no_snapshot:'||k);
  PERFORM pg_temp.ok((SELECT count(*)=before_nav FROM nse_nav.observations) AND (SELECT count(*)=before_set FROM nse_set.assessments) AND (SELECT count(*)=before_shared FROM nse_reference.validations) AND (SELECT count(*)=before_audit FROM public.workspace_audit_logs),'atomic_no_projection_or_audit:'||k);
  DROP TRIGGER b064_no_completion ON nse_reference.completions;
  PERFORM pg_temp.ok(public.finalize_nse_master_download(e,t)->>'outcome'=CASE k WHEN 'NAV' THEN 'STAGED_VALIDATED' ELSE 'REJECTED' END,'atomic_retry:'||k);
 END LOOP;
END $$;
-- Real service-role execution, with no broad table grants for fixtures/helpers.
SET LOCAL ROLE service_role;
DO $$ DECLARE k text; e uuid; t uuid:=gen_random_uuid(); r jsonb;
BEGIN
 FOREACH k IN ARRAY ARRAY['NAV','SET'] LOOP
  e:=pg_temp.queue(k); PERFORM public.claim_nse_master_download(e,t);
  PERFORM pg_temp.capture(e,t,CASE k WHEN 'NAV' THEN '2026-09-30|NSE-A|Synthetic Growth|RTA-A|Z|INF000000001|123.4500|CAMS' ELSE 'unknown|SET|format' END);
  r:=public.finalize_nse_master_download(e,t);
  IF r->>'outcome' IS DISTINCT FROM (CASE k WHEN 'NAV' THEN 'STAGED_VALIDATED' ELSE 'REJECTED' END) THEN RAISE EXCEPTION 'service_runtime_outcome_invalid'; END IF;
 END LOOP;
 BEGIN PERFORM nse_reference.validate_nav_v1(NULL); RAISE EXCEPTION 'private_adapter_exposed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM nse_reference.validate_set_v1(NULL); RAISE EXCEPTION 'private_adapter_exposed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
SET LOCAL ROLE authenticated;
DO $$ DECLARE persona text; k text;
BEGIN
 FOREACH persona IN ARRAY ARRAY['platform_admin','family_guest','inactive_member','operations','unrelated_advisor','cross_workspace'] LOOP
  PERFORM set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub','b0640000-0000-4000-8000-000000000002','app_metadata',jsonb_build_object('role',persona))::text,true);
  FOREACH k IN ARRAY ARRAY['NAV','SET'] LOOP
   BEGIN PERFORM pg_temp.queue(k); RAISE EXCEPTION 'browser_prepare_allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  END LOOP;
 END LOOP;
END $$;
RESET ROLE;
SET CONSTRAINTS ALL IMMEDIATE;
SELECT count(*) AS b064_runtime_assertions FROM b064_assertions;
ROLLBACK;
