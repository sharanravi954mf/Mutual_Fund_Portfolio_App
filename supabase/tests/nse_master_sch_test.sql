\set ON_ERROR_STOP on
BEGIN;
SELECT 1 FROM vault.create_secret(repeat('s',40),'integration_payload_encryption_key_v1','B06.2 synthetic rollback-only key');
INSERT INTO auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES
 ('b0610000-0000-4000-8000-000000000001','authenticated','authenticated','b061-one@moneybowl.invalid','{}','{}',now(),now()),
 ('b0610000-0000-4000-8000-000000000002','authenticated','authenticated','b061-two@moneybowl.invalid','{}','{}',now(),now());
INSERT INTO public.workspaces(id,name,slug,owner_profile_id,workspace_status)
SELECT ('b0610000-0000-4000-8001-'||right(user_id::text,12))::uuid,'B06 synthetic','b061-'||right(user_id::text,1),id,'active'
 FROM public.profiles WHERE user_id IN ('b0610000-0000-4000-8000-000000000001','b0610000-0000-4000-8000-000000000002');
INSERT INTO nse_reference.connections(id,workspace_id,environment,member_code,api_base_url,enabled)
VALUES('b0610000-0000-4000-8002-000000000001','b0610000-0000-4000-8001-000000000001','UAT','05418','https://nse.example.test',true);
CREATE TEMP TABLE b062_assertions(label text);
CREATE FUNCTION pg_temp.ok(b boolean,label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF b IS DISTINCT FROM true THEN RAISE EXCEPTION 'assertion_failed:%',label; END IF; INSERT INTO b062_assertions VALUES(label); END $$;
CREATE FUNCTION pg_temp.err(statement text,expected text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 BEGIN EXECUTE statement; EXCEPTION WHEN OTHERS THEN
  IF strpos(SQLERRM,expected)>0 THEN INSERT INTO b062_assertions VALUES('reject:'||expected); RETURN; END IF;
  RAISE EXCEPTION 'wrong_error:% expected:%',SQLERRM,expected;
 END;
 RAISE EXCEPTION 'missing_error:%',expected;
END $$;
CREATE FUNCTION pg_temp.sch_row(code text DEFAULT 'NSE-A',serial text DEFAULT '1') RETURNS text LANGUAGE sql AS $$
 SELECT array_to_string(ARRAY[serial,code,'RTA-A','AMC-A','INF000000001','AMC-ONE','NATIVE-TYPE','NATIVE-PLAN','Synthetic Scheme',
 'unknown','unknown','','','','','','unknown','','','','','','','','','UNRESOLVED-AGENT','unknown','unknown','unknown','unknown','unknown','unknown','','','','','','','','','','','','unknown'],'|');
$$;
CREATE FUNCTION pg_temp.sch_file() RETURNS text LANGUAGE sql AS $$
 SELECT nse_reference.sch_header_v1()||E'\n'||pg_temp.sch_row()||E'\n';
$$;
CREATE FUNCTION pg_temp.queue(key uuid DEFAULT gen_random_uuid()) RETURNS uuid LANGUAGE sql AS $$
 SELECT (public.prepare_nse_master_download('b0610000-0000-4000-8001-000000000001','b0610000-0000-4000-8002-000000000001','SCH',key)->>'event_outbox_id')::uuid;
$$;
CREATE FUNCTION pg_temp.capture(e uuid,token uuid,b bytea,status integer DEFAULT 200,media text DEFAULT 'TEXT',kind text DEFAULT 'COMPLETE') RETURNS void LANGUAGE plpgsql AS $$
DECLARE pos integer:=0;
BEGIN
 PERFORM public.begin_nse_master_job_capture(e,token,gen_random_uuid(),'UAT','05418','https://nse.example.test');
 WHILE pos<octet_length(b) LOOP
  PERFORM public.append_nse_master_job_chunk(e,token,pos/262144,replace(encode(substring(b FROM pos+1 FOR 262144),'base64'),E'\n',''),encode(extensions.digest(substring(b FROM pos+1 FOR 262144),'sha256'),'hex'));
  pos:=pos+262144;
 END LOOP;
 PERFORM public.finish_nse_master_job_capture(e,token,kind,status,media,octet_length(b),true,true,
  CASE WHEN kind='COMPLETE' THEN encode(extensions.digest(b,'sha256'),'hex') END);
END $$;
CREATE FUNCTION pg_temp.run_file(body text,status integer DEFAULT 200,media text DEFAULT 'TEXT',kind text DEFAULT 'COMPLETE') RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE e uuid:=pg_temp.queue(); token uuid:=gen_random_uuid();
BEGIN
 PERFORM public.claim_nse_master_download(e,token);
 PERFORM pg_temp.capture(e,token,convert_to(body,'UTF8'),status,media,kind);
 RETURN public.finalize_nse_master_download(e,token);
END $$;
CREATE FUNCTION pg_temp.forbid_mutation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'b062_publication_forbidden'; END $$;
INSERT INTO public.mutual_funds(id,scheme_code,scheme_name,fund_house,current_nav,nav_date) VALUES('b0620000-0000-4000-8000-000000000001','NSE-A','Registrar fund with coincidental code','DIFFERENT AMC',99,'2026-10-01');
CREATE TRIGGER b062_no_funds BEFORE INSERT OR UPDATE OR DELETE ON public.mutual_funds FOR EACH STATEMENT EXECUTE FUNCTION pg_temp.forbid_mutation();
CREATE TRIGGER b062_no_accounts BEFORE INSERT OR UPDATE OR DELETE ON public.integration_accounts FOR EACH STATEMENT EXECUTE FUNCTION pg_temp.forbid_mutation();
CREATE TRIGGER b062_no_operations BEFORE INSERT OR UPDATE OR DELETE ON public.integration_operations FOR EACH STATEMENT EXECUTE FUNCTION pg_temp.forbid_mutation();
DO $$ DECLARE e uuid; t uuid:=gen_random_uuid(); key uuid:=gen_random_uuid(); c jsonb; r jsonb; s uuid; prior uuid; body text; bad text;
 before_rows bigint; rec record; role_name text; persona text; fn regprocedure; fields text[];
BEGIN
 PERFORM pg_temp.ok(nse_reference.sch_header_v1()='UNIQUE SR NO|SCHEME CODE|RTA SCHEME CODE|AMC SCHEME CODE|ISIN|AMC CODE|SCHEME TYPE|PLAN TYPE|SCHEME NAME|PURCHASE ALLOWED|PURCHASE TRANSACTION MODE|NEW PURCHASE MIN AMOUNT|ADDITIONAL PURCHASE MIN AMOUNT|ADDITIONAL PURCHASE MAX AMOUNT|PURCHASE AMOUNT MULTIPLIER|PURCHASE CUTOFF TIME|REDEMPTION ALLOWED|REDEMPTION TRANSACTION MODE|REDEMPTION MIN QTY|REDEMPTION QTY MULTIPLIER|REDEMPTION MAX QTY|REDEMPTION MIN AMOUNT|REDEMPTION MAX AMOUNT|REDEMPTION AMOUNT MULTIPLIER|REDEMPTION CUTOFF TIME|RTA AGENT CODE|AMC ACTIVE FLAG|DIV REINVEST FLAG|SIP ALLOWED|STP ENABLED|SWP ENABLED|SWITCH ALLOWED|SETTLEMENT TYPE|AMC IND|FACE VALUE|SCHEME START DATE|MATURITY DATE|EXIT LOAD FLAG|EXIT LOAD|LOCK IN PERIOD_FLAG|LOCK IN PERIOD|CHANNEL PARTNER CODE|REOPENING DATE|OPEN/CLOSE ENDED SCHEME','source_pinned_44_column_header');
 e:=pg_temp.queue(key);
 PERFORM pg_temp.ok(pg_temp.queue(key)=e,'prepare_ack_idempotent');
 PERFORM pg_temp.ok((SELECT count(*)=1 FROM nse_reference.jobs),'one_job');
 PERFORM pg_temp.ok((SELECT count(*)=1 FROM public.list_dispatchable_outbox_events(ARRAY['integration.nse.master_download_requested'])),'member_dispatch_feed');
 PERFORM pg_temp.ok((SELECT payload='{}'::jsonb FROM public.event_outbox WHERE id=e),'no_member_payload');
 PERFORM pg_temp.err($q$SELECT public.prepare_nse_master_download('b0610000-0000-4000-8001-000000000002','b0610000-0000-4000-8002-000000000001','SCH',gen_random_uuid())$q$,'connection_unavailable');
 FOREACH bad IN ARRAY ARRAY['sch','SCH ','sip','stp','swp','nav','set','UNKNOWN',NULL] LOOP
  PERFORM pg_temp.err(format('SELECT public.prepare_nse_master_download(%L,%L,%L,gen_random_uuid())','b0610000-0000-4000-8001-000000000001','b0610000-0000-4000-8002-000000000001',bad),'variant_disabled');
 END LOOP;
 PERFORM pg_temp.err(format('UPDATE public.event_outbox SET payload=%L WHERE id=%L','{"file_type":"NAV"}',e),'event_immutable');
 PERFORM pg_temp.err(format('DELETE FROM public.event_outbox WHERE id=%L',e),'event_immutable');
 PERFORM pg_temp.err($q$INSERT INTO public.event_outbox(event_type,entity_type,entity_id,payload) VALUES('integration.nse.master_download_requested','nse_reference_job',gen_random_uuid(),'{}')$q$,'event_invalid');
 c:=public.claim_nse_master_download(e,t);
 PERFORM pg_temp.ok(c->>'action'='CAPTURE','claim_capture');
 PERFORM pg_temp.err(format('SELECT public.begin_nse_master_download(%L,%L,%L,%L,%L,%L,%L,gen_random_uuid())',
 c->>'workspace_id',c->>'connection_id','NAV',c->>'download_id','UAT','05418','https://nse.example.test'),'job_download_mismatch');
 PERFORM pg_temp.ok(public.claim_nse_master_download(e,t)=c,'claim_ack_retry');
 PERFORM pg_temp.ok(public.claim_nse_master_download(e,gen_random_uuid())->>'action'='BUSY','competing_claim');
 PERFORM pg_temp.ok((SELECT count(*)=0 FROM public.list_dispatchable_outbox_events(ARRAY['integration.nse.master_download_requested'])),'active_lease_not_dispatchable');
 PERFORM pg_temp.err(format('SELECT public.begin_nse_master_job_capture(%L,%L,gen_random_uuid(),%L,%L,%L)',e,t,'UAT','FOREIGN','https://nse.example.test'),'runtime_binding_mismatch');
 PERFORM pg_temp.err(format('SELECT public.begin_nse_master_job_capture(%L,gen_random_uuid(),gen_random_uuid(),%L,%L,%L)',e,'UAT','05418','https://nse.example.test'),'claim_not_owned');
 PERFORM pg_temp.err(format('SELECT public.finalize_nse_master_download(%L,%L)',e,t),'capture_unsealed');
 PERFORM pg_temp.capture(e,t,convert_to(pg_temp.sch_file(),'UTF8'));
 r:=public.finalize_nse_master_download(e,t); s:=(r->>'snapshot_id')::uuid; prior:=s;
 PERFORM pg_temp.ok(r->>'outcome'='STAGED_VALIDATED','complete_sch_staged');
 PERFORM pg_temp.ok(public.finalize_nse_master_download(e,t)=r,'finalize_ack_retry');
 SELECT public.get_nse_master_download_job(workspace_id,id) INTO c FROM nse_reference.jobs WHERE event_id=e;
 PERFORM pg_temp.ok(c->>'validation_scope'='STRUCTURE_AND_IDENTITY_ONLY' AND c->>'publication_gate'='BLOCKED' AND c->>'row_count'='1','honest_service_summary');
 PERFORM pg_temp.err(format('SELECT public.get_nse_master_download_job(%L,%L)','b0610000-0000-4000-8001-000000000002',c->>'job_id'),'job_unavailable');
 PERFORM pg_temp.ok(public.claim_nse_master_download(e,gen_random_uuid())->>'action'='DONE','completed_never_sends');
 PERFORM pg_temp.ok((SELECT count(*)=1 FROM nse_reference.sch_rows WHERE snapshot_id=s),'typed_row');
 PERFORM pg_temp.ok((SELECT rta_scheme_code='RTA-A' AND amc_scheme_code='AMC-A' AND plan_type='NATIVE-PLAN' AND dividend_reinvestment_flag='unknown' FROM nse_reference.sch_rows WHERE snapshot_id=s),'codes_separate_flags_native');
 PERFORM pg_temp.ok((SELECT source_namespace='NSE_SCH' AND scheme_code='NSE-A' FROM nse_reference.scheme_identities),'explicit_nse_identity');
 PERFORM pg_temp.ok((SELECT publication_gate='BLOCKED' AND row_count=1 AND rejected_rows=0 AND parser_version='SCH_OBSERVED_44_V1' FROM nse_reference.validations WHERE snapshot_id=s),'receipt_not_publication');
 PERFORM pg_temp.ok((SELECT v.source_sha256=r.response_sha256 FROM nse_reference.validations v JOIN nse_reference.snapshots s ON s.id=v.snapshot_id JOIN nse_reference.results r ON r.download_id=s.download_id WHERE v.snapshot_id=prior),'source_digest_lineage');
 PERFORM pg_temp.ok((SELECT count(*)=0 FROM nse_reference.scheme_crosswalk_candidates),'no_invented_crosswalk');
 PERFORM pg_temp.ok((SELECT current_nav=99 AND fund_house='DIFFERENT AMC' FROM public.mutual_funds WHERE scheme_code='NSE-A'),'coincidental_code_never_overwrites');
 PERFORM pg_temp.err(format('INSERT INTO nse_reference.scheme_crosswalk_candidates(workspace_id,snapshot_id,scheme_identity_id,candidate_fund_id,target_namespace,review_outcome,provenance_reference) SELECT workspace_id,snapshot_id,scheme_identity_id,%L,%L,%L,%L FROM nse_reference.sch_rows WHERE snapshot_id=%L',
 'b0620000-0000-4000-8000-000000000001','CAMS','APPROVED','synthetic-review',s),'check constraint');
 INSERT INTO nse_reference.scheme_crosswalk_candidates(workspace_id,snapshot_id,scheme_identity_id,candidate_fund_id,target_namespace,review_outcome,provenance_reference)
 SELECT workspace_id,snapshot_id,scheme_identity_id,'b0620000-0000-4000-8000-000000000001','UNRESOLVED','AMBIGUOUS','synthetic-review'
 FROM nse_reference.sch_rows WHERE snapshot_id=s;
 PERFORM pg_temp.err('UPDATE nse_reference.scheme_crosswalk_candidates SET review_outcome=''PROPOSED''','immutable');
 PERFORM pg_temp.err('DELETE FROM nse_reference.scheme_crosswalk_candidates','immutable');
 PERFORM pg_temp.err(format('INSERT INTO nse_reference.scheme_crosswalk_candidates(workspace_id,snapshot_id,scheme_identity_id,candidate_fund_id,target_namespace,review_outcome,provenance_reference) SELECT %L,snapshot_id,scheme_identity_id,%L,%L,%L,%L FROM nse_reference.sch_rows WHERE snapshot_id=%L',
 'b0610000-0000-4000-8001-000000000002','b0620000-0000-4000-8000-000000000001','CAMS','PROPOSED','synthetic-review',s),'foreign key');
 PERFORM pg_temp.ok((SELECT stage='STAGED_UNVALIDATED' FROM nse_reference.snapshots WHERE id=s),'foundation_history_unchanged');
 r:=pg_temp.run_file(chr(65279)||replace(pg_temp.sch_file(),E'\n',E'\r\n'));
 PERFORM pg_temp.ok(r->>'outcome'='STAGED_VALIDATED','bom_crlf');
 PERFORM pg_temp.ok((SELECT count(*)=1 FROM nse_reference.scheme_identities),'same_source_code_identity');
 PERFORM pg_temp.ok((SELECT previous_snapshot_id=prior AND version=2 FROM nse_reference.snapshots WHERE id=(r->>'snapshot_id')::uuid),'immutable_versions');
 body:=pg_temp.sch_file();
 FOREACH bad IN ARRAY ARRAY[
  replace(body,'UNIQUE SR NO','UNIQUE NO'),replace(body,'SCHEME CODE|RTA SCHEME CODE','RTA SCHEME CODE|SCHEME CODE'),
  replace(body,'OPEN/CLOSE ENDED SCHEME','UNKNOWN'),
  nse_reference.sch_header_v1()||E'\n',
  left(body,length(body)-1),body||E'\n',body||'partial',
  body||pg_temp.sch_row()||E'\n',body||pg_temp.sch_row('NSE-B','1')||E'\n',body||pg_temp.sch_row('NSE-A','2')||E'\n',
  replace(body,'NSE-A',''),replace(body,'NSE-A',' NSE-A'),replace(body,'AMC-ONE',''),
  replace(body,'INF000000001','bad-isin'),replace(body,'Synthetic Scheme',''),
  replace(body,'Synthetic Scheme','line'||E'\n'||'break'),replace(body,'Synthetic Scheme','quote"name'),
  replace(body,'Synthetic Scheme',E'tab\tname'),replace(body,'Synthetic Scheme',chr(65279)||'name'),
  replace(body,'Synthetic Scheme',repeat('x',2049)),
  body||E'\r\n',
  replace(body,E'\n'||pg_temp.sch_row(),E'\r\n'||pg_temp.sch_row()),
  body||E'broken|line\n',replace(body,'RTA-A|AMC-A','RTA-A'),replace(body,'RTA-A|AMC-A','RTA-A|EXTRA|AMC-A')
 ] LOOP
  SELECT count(*) INTO before_rows FROM nse_reference.sch_rows;
  r:=pg_temp.run_file(bad);
  PERFORM pg_temp.ok(r->>'outcome'='REJECTED','reject_schema_or_rows');
  PERFORM pg_temp.ok((SELECT count(*)=before_rows FROM nse_reference.sch_rows),'no_partial_rows');
  PERFORM pg_temp.ok((SELECT row_count=0 AND publication_gate='BLOCKED' FROM nse_reference.validations WHERE snapshot_id=(r->>'snapshot_id')::uuid),'rejected_receipt_blocked');
 END LOOP;
 FOREACH bad IN ARRAY ARRAY['TRUNCATED','OVERSIZE','UNVERIFIABLE','TRANSPORT_FAILED'] LOOP
  PERFORM pg_temp.ok(pg_temp.run_file(body,200,'TEXT',bad)->>'outcome'='CAPTURE_FAILED','capture_fail_closed_'||bad);
 END LOOP;
 PERFORM pg_temp.ok(pg_temp.run_file(body,500)->>'outcome'='CAPTURE_FAILED','http_failure');
 PERFORM pg_temp.ok(pg_temp.run_file(body,200,'JSON')->>'outcome'='CAPTURE_FAILED','json_media');
 PERFORM pg_temp.ok(pg_temp.run_file('{"response_status":"F"}',200)->>'outcome'='CAPTURE_FAILED','json_in_text');
 PERFORM pg_temp.ok(pg_temp.run_file('<html>a|b</html>',200)->>'outcome'='CAPTURE_FAILED','html_in_text');
 PERFORM pg_temp.ok(pg_temp.run_file('',200)->>'outcome'='CAPTURE_FAILED','empty_body');
 -- Expired pre-send claim is recoverable; stale tokens are fenced.
 e:=pg_temp.queue(); c:=public.claim_nse_master_download(e,t);
 UPDATE public.event_outbox SET claim_expires_at=now()-interval '1 second' WHERE id=e;
 key:=gen_random_uuid(); PERFORM pg_temp.ok(public.claim_nse_master_download(e,key)->>'action'='CAPTURE','expired_before_begin');
 PERFORM pg_temp.err(format('SELECT public.begin_nse_master_job_capture(%L,%L,gen_random_uuid(),%L,%L,%L)',e,t,'UAT','05418','https://nse.example.test'),'claim_not_owned');
 -- Expired begun call is never recaptured; bytes stay unsealed and unusable.
 PERFORM public.begin_nse_master_job_capture(e,key,gen_random_uuid(),'UAT','05418','https://nse.example.test');
 UPDATE public.event_outbox SET claim_expires_at=now()-interval '1 second' WHERE id=e;
 PERFORM pg_temp.ok(public.claim_nse_master_download(e,t)->>'action'='DONE','expired_started_no_resend');
 PERFORM pg_temp.ok((SELECT c.outcome='ABANDONED' FROM nse_reference.completions c JOIN nse_reference.jobs j ON j.id=c.id WHERE j.event_id=e),'abandoned_receipt');
 PERFORM pg_temp.err(format('SELECT public.append_nse_master_job_chunk(%L,%L,0,%L,%L)',e,key,'YQ==',repeat('0',64)),'claim_not_owned');
 -- Sealed evidence survives worker death: new lease only finalizes it.
 e:=pg_temp.queue(); PERFORM public.claim_nse_master_download(e,t); PERFORM pg_temp.capture(e,t,convert_to(body,'UTF8'));
 UPDATE public.event_outbox SET claim_expires_at=now()-interval '1 second' WHERE id=e;
 key:=gen_random_uuid();PERFORM pg_temp.ok(public.claim_nse_master_download(e,key)->>'action'='FINALIZE','sealed_resume');
 PERFORM pg_temp.err(format('SELECT public.finalize_nse_master_download(%L,%L)',e,t),'claim_not_owned');
 PERFORM pg_temp.ok(public.finalize_nse_master_download(e,key)->>'outcome'='STAGED_VALIDATED','sealed_resume_validated');
 -- Third pre-send claim still supports acknowledgement replay; a fourth expires terminally.
 e:=pg_temp.queue();
 FOR before_rows IN 1..3 LOOP
  t:=gen_random_uuid(); c:=public.claim_nse_master_download(e,t);
  PERFORM pg_temp.ok(c->>'action'='CAPTURE' AND public.claim_nse_master_download(e,t)=c,'bounded_claim_ack_replay');
  UPDATE public.event_outbox SET claim_expires_at=now()-interval '1 second' WHERE id=e;
 END LOOP;
 PERFORM pg_temp.ok(public.claim_nse_master_download(e,gen_random_uuid())->>'action'='DONE','pre_send_claim_budget');
 -- Current ownership is rechecked after preparation and after capture.
 e:=pg_temp.queue(); PERFORM public.claim_nse_master_download(e,t); PERFORM pg_temp.capture(e,t,convert_to(body,'UTF8'));
 UPDATE nse_reference.connections SET enabled=false;
 PERFORM pg_temp.err(format('SELECT public.finalize_nse_master_download(%L,%L)',e,t),'connection_unavailable');
 UPDATE nse_reference.connections SET enabled=true;
 UPDATE public.workspaces SET workspace_status='suspended' WHERE id='b0610000-0000-4000-8001-000000000001';
 PERFORM pg_temp.err(format('SELECT public.finalize_nse_master_download(%L,%L)',e,t),'workspace_unavailable');
 UPDATE public.workspaces SET workspace_status='active' WHERE id='b0610000-0000-4000-8001-000000000001';
 PERFORM public.finalize_nse_master_download(e,t);
 FOR rec IN SELECT tablename FROM pg_tables WHERE schemaname='nse_reference' LOOP
  PERFORM pg_temp.ok((SELECT relrowsecurity FROM pg_class WHERE oid=('nse_reference.'||rec.tablename)::regclass),'rls_'||rec.tablename);
  FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
   PERFORM pg_temp.ok(NOT has_table_privilege(role_name,'nse_reference.'||rec.tablename,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'),'private_'||rec.tablename||role_name);
  END LOOP;
 END LOOP;
 PERFORM pg_temp.ok((SELECT count(*)=0 FROM pg_policies WHERE schemaname='nse_reference'),'no_policies');
 FOREACH bad IN ARRAY ARRAY['jobs','validations','completions','scheme_identities','sch_rows'] LOOP
  PERFORM pg_temp.err(format('DELETE FROM nse_reference.%I',bad),'immutable');
 END LOOP;
 FOR fn IN SELECT p.oid::regprocedure FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname IN ('prepare_nse_master_download','claim_nse_master_download','begin_nse_master_job_capture','append_nse_master_job_chunk','finish_nse_master_job_capture','finalize_nse_master_download','get_nse_master_download_job') LOOP
  PERFORM pg_temp.ok(has_function_privilege('service_role',fn,'EXECUTE'),'service_rpc');
  PERFORM pg_temp.ok(NOT has_function_privilege('authenticated',fn,'EXECUTE') AND NOT has_function_privilege('anon',fn,'EXECUTE'),'browser_rpc_denied');
  PERFORM pg_temp.ok((SELECT prosecdef AND proconfig @> ARRAY['search_path=""'] FROM pg_proc WHERE oid=fn),'definer_search_path');
  PERFORM pg_temp.ok(NOT EXISTS(SELECT 1 FROM pg_proc p,LATERAL aclexplode(COALESCE(p.proacl,acldefault('f',p.proowner))) a WHERE p.oid=fn AND a.grantee=0 AND a.privilege_type='EXECUTE'),'public_execute_denied');
 END LOOP;
END $$;
-- Full staging transaction rolls back if completion/audit persistence fails.
CREATE FUNCTION pg_temp.reject_completion() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'synthetic_completion_failure'; END $$;
CREATE TRIGGER b062_atomic_failure BEFORE INSERT ON nse_reference.completions FOR EACH ROW EXECUTE FUNCTION pg_temp.reject_completion();
DO $$ DECLARE e uuid:=pg_temp.queue(); t uuid:=gen_random_uuid(); c jsonb; BEGIN
 c:=public.claim_nse_master_download(e,t); PERFORM pg_temp.capture(e,t,convert_to(pg_temp.sch_file(),'UTF8'));
 PERFORM pg_temp.err(format('SELECT public.finalize_nse_master_download(%L,%L)',e,t),'synthetic_completion_failure');
 PERFORM pg_temp.ok(NOT EXISTS(SELECT 1 FROM nse_reference.snapshots WHERE download_id=(c->>'download_id')::uuid),'atomic_no_partial_snapshot');
 PERFORM pg_temp.ok((SELECT status='processing' FROM public.event_outbox WHERE id=e),'atomic_event_still_recoverable');
 DROP TRIGGER b062_atomic_failure ON nse_reference.completions;
 PERFORM pg_temp.ok(public.finalize_nse_master_download(e,t)->>'outcome'='STAGED_VALIDATED','atomic_retry');
END $$;
-- Synthetic multi-megabyte SCH validates all rows, including the final record.
DO $$ DECLARE body text; r jsonb; BEGIN
 SELECT nse_reference.sch_header_v1()||E'\n'||string_agg(pg_temp.sch_row('LARGE-'||n,n::text),E'\n' ORDER BY n)||E'\n' INTO body FROM generate_series(1,15243) n;
 PERFORM pg_temp.ok(octet_length(body)>3000000,'large_fixture_measured');
 r:=pg_temp.run_file(body);
 PERFORM pg_temp.ok(r->>'outcome'='STAGED_VALIDATED','large_file_valid');
 PERFORM pg_temp.ok((SELECT count(*)=15243 AND max(row_number)=15243 FROM nse_reference.sch_rows WHERE snapshot_id=(r->>'snapshot_id')::uuid),'large_file_no_prefix_success');
END $$;
-- A bounded file with too many rows is rejected before any identity projection.
DO $$ DECLARE fields text[]:=array_fill(''::text,ARRAY[44]); body text; r jsonb; BEGIN
 fields[1]:='1';fields[2]:='N';fields[6]:='A';fields[9]:='B';
 body:=nse_reference.sch_header_v1()||E'\n'||repeat(array_to_string(fields,'|')||E'\n',100001);
 r:=pg_temp.run_file(body);
 PERFORM pg_temp.ok(r->>'outcome'='REJECTED','row_limit_closed');
 PERFORM pg_temp.ok(NOT EXISTS(SELECT 1 FROM nse_reference.sch_rows WHERE snapshot_id=(r->>'snapshot_id')::uuid),'row_limit_no_projection');
END $$;
CREATE FUNCTION pg_temp.service_flow(b64 text,sha text,bytes integer) RETURNS void LANGUAGE plpgsql AS $$
DECLARE job jsonb; e uuid; t uuid:=gen_random_uuid(); result jsonb;
BEGIN
 job:=public.prepare_nse_master_download('b0610000-0000-4000-8001-000000000001','b0610000-0000-4000-8002-000000000001','SCH',gen_random_uuid());
 e:=(job->>'event_outbox_id')::uuid;
 PERFORM public.claim_nse_master_download(e,t);
 PERFORM public.begin_nse_master_job_capture(e,t,gen_random_uuid(),'UAT','05418','https://nse.example.test');
 PERFORM public.append_nse_master_job_chunk(e,t,0,b64,sha);
 PERFORM public.finish_nse_master_job_capture(e,t,'COMPLETE',200,'TEXT',bytes,true,true,sha);
 result:=public.finalize_nse_master_download(e,t);
 IF result->>'outcome'<>'STAGED_VALIDATED' OR public.get_nse_master_download_job('b0610000-0000-4000-8001-000000000001',(job->>'job_id')::uuid)->>'publication_gate'<>'BLOCKED' THEN
  RAISE EXCEPTION 'service_workflow_failed'; END IF;
END $$;
SELECT replace(encode(convert_to(pg_temp.sch_file(),'UTF8'),'base64'),E'\n','') AS body64,
 encode(extensions.digest(pg_temp.sch_file(),'sha256'),'hex') AS bodysha,octet_length(pg_temp.sch_file()) AS bodybytes \gset
-- Exercise actual API roles without granting table privileges to make tests pass.
SET LOCAL ROLE service_role;
SELECT pg_temp.service_flow(:'body64',:'bodysha',:bodybytes);
SELECT public.prepare_nse_master_download('b0610000-0000-4000-8001-000000000001','b0610000-0000-4000-8002-000000000001','SCH',gen_random_uuid());
DO $$ BEGIN
 BEGIN PERFORM 1 FROM nse_reference.sch_rows; RAISE EXCEPTION 'service_table_allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
SET LOCAL ROLE authenticated;
DO $$ DECLARE persona text; BEGIN
 FOREACH persona IN ARRAY ARRAY['platform_admin','family_guest','inactive_member','operations','unrelated_advisor','cross_workspace'] LOOP
  PERFORM set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub','b0610000-0000-4000-8000-000000000002','app_metadata',jsonb_build_object('role',persona))::text,true);
  BEGIN PERFORM public.prepare_nse_master_download(NULL,NULL,'SCH',NULL); RAISE EXCEPTION 'browser_prepare_allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM public.claim_nse_master_download(NULL,NULL); RAISE EXCEPTION 'browser_claim_allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM public.finalize_nse_master_download(NULL,NULL); RAISE EXCEPTION 'browser_finalize_allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM 1 FROM nse_reference.scheme_crosswalk_candidates; RAISE EXCEPTION 'browser_crosswalk_allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 END LOOP;
END $$;
RESET ROLE;
SELECT count(*) AS b062_assertions FROM b062_assertions;
ROLLBACK;
