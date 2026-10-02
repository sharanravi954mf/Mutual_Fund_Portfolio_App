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
CREATE FUNCTION pg_temp.begin_download(kind text DEFAULT 'SCH',call_id uuid DEFAULT gen_random_uuid(), token uuid DEFAULT gen_random_uuid()) RETURNS uuid LANGUAGE plpgsql AS $$
BEGIN
 PERFORM public.begin_nse_master_download('b0640000-0000-4000-8001-000000000001','b0640000-0000-4000-8002-000000000001',kind,call_id,'UAT','05418','https://nse.example.test',token);
 RETURN call_id;
END $$;
CREATE FUNCTION pg_temp.append_chunk(d uuid,n integer,b bytea) RETURNS void LANGUAGE sql AS $$
 SELECT public.append_nse_master_chunk('b0640000-0000-4000-8001-000000000001',d,n,replace(encode(b,'base64'),E'\n',''),encode(extensions.digest(b,'sha256'),'hex'));
$$;
CREATE FUNCTION pg_temp.finish(d uuid,b bytea,status integer DEFAULT 200,media text DEFAULT 'TEXT') RETURNS jsonb LANGUAGE sql AS $$
 SELECT public.finish_nse_master_download('b0640000-0000-4000-8001-000000000001',d,'COMPLETE',status,media,octet_length(b),true,true,encode(extensions.digest(b,'sha256'),'hex'));
$$;
CREATE FUNCTION pg_temp.stage(d uuid) RETURNS jsonb LANGUAGE sql AS $$
 SELECT public.stage_nse_reference_snapshot('b0640000-0000-4000-8001-000000000001',d);
$$;
CREATE FUNCTION pg_temp.store_file(kind text,b bytea) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE d uuid:=pg_temp.begin_download(kind); pos integer:=0;
BEGIN
 WHILE pos<octet_length(b) LOOP PERFORM pg_temp.append_chunk(d,pos/262144,substring(b FROM pos+1 FOR 262144)); pos:=pos+262144; END LOOP;
 PERFORM pg_temp.finish(d,b); RETURN d;
END $$;
-- No publication/crosswalk side effects, including identical scheme codes/names.
INSERT INTO public.mutual_funds(scheme_code,scheme_name,fund_house,current_nav,nav_date)
VALUES('NSE-A','Synthetic Growth','Registrar AMC',99.1234,'2026-09-28');
CREATE FUNCTION pg_temp.forbid_nav_mutation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'b064_existing_financial_mutation'; END $$;
CREATE TRIGGER b064_no_funds BEFORE INSERT OR UPDATE OR DELETE ON public.mutual_funds FOR EACH STATEMENT EXECUTE FUNCTION pg_temp.forbid_nav_mutation();
CREATE TRIGGER b064_no_operations BEFORE INSERT OR UPDATE OR DELETE ON public.integration_operations FOR EACH STATEMENT EXECUTE FUNCTION pg_temp.forbid_nav_mutation();
CREATE TRIGGER b064_no_outbox BEFORE INSERT OR UPDATE OR DELETE ON public.event_outbox FOR EACH STATEMENT EXECUTE FUNCTION pg_temp.forbid_nav_mutation();
CREATE TEMP TABLE b064_ids(label text PRIMARY KEY,id uuid);
DO $$ DECLARE
 row1 text:='2026-09-30|NSE-A|Synthetic Growth|RTA-A|Z|INF000000001|123.450000|CAMS';
 row2 text:='2026-09-29|NSE-A|Synthetic Growth|RTA-A|Z|INF000000001|122.100000|CAMS';
 s uuid; s2 uuid; blocked uuid; r jsonb; r2 jsonb; p jsonb; bad text; i integer; t text; fn regprocedure;
BEGIN
 s:=pg_temp.nav_file(chr(65279)||row1||E'\r\n'||row2||E'\r\n');
 INSERT INTO b064_ids VALUES('nav',s);
 r:=pg_temp.validate_nav(s);
 PERFORM pg_temp.ok(r->>'status'='VALIDATED_OBSERVATIONS' AND r->>'row_count'='2','headerless_documented_eight_column_layout');
 PERFORM pg_temp.ok(r->>'parser_version'='NSE_NAV_WEB83_V1' AND r->>'api_compatibility'='UNCOMMISSIONED','documented_not_uat_proven');
 PERFORM pg_temp.ok(r->>'publication_state'='BLOCKED_CROSSWALK_AND_SOURCE_POLICY','source_precedence_and_crosswalk_explicitly_block_publication');
 PERFORM pg_temp.ok(pg_temp.validate_nav(s)=r,'success_replay');
 PERFORM pg_temp.ok((SELECT count(*)=1 FROM public.workspace_audit_logs WHERE target_id=s AND action='nse.nav.assessment'),'single_transactional_audit');
 PERFORM pg_temp.err(format('UPDATE public.workspace_audit_logs SET reason=%L WHERE target_id=%L','changed',s),'Audit logs are immutable');
 PERFORM pg_temp.err(format('DELETE FROM public.workspace_audit_logs WHERE target_id=%L',s),'Audit logs are immutable');
 PERFORM pg_temp.ok((SELECT stage='STAGED_UNVALIDATED' FROM nse_reference.snapshots WHERE id=s),'foundation_immutable_not_promoted');
 PERFORM pg_temp.ok((SELECT count(DISTINCT nav_date)=2 AND min(nav_value)=122.100000 AND max(nav_value)=123.450000 FROM nse_nav.observations WHERE snapshot_id=s),'dated_observations_not_latest_overwrite');
 PERFORM pg_temp.ok((SELECT encode(v.source_sha256,'hex')=r->>'source_sha256' AND v.source_sha256=e.response_sha256
   FROM nse_nav.validations v JOIN nse_reference.snapshots sn ON sn.id=v.snapshot_id JOIN nse_reference.results e ON e.download_id=sn.download_id WHERE sn.id=s),'source_digest_bound_to_exact_evidence');
 p:=public.read_nse_nav_observations('b0640000-0000-4000-8001-000000000001',s,0,1);
 PERFORM pg_temp.ok(p->>'next_after_line'='1' AND p->'observations'->0->>'nav_value'='123.450000','page_retains_decimal_lexeme');
 s2:=pg_temp.nav_file(replace(row1,'123.450000','124.450000'));
 r2:=pg_temp.validate_nav(s2);
 p:=public.read_nse_nav_observations('b0640000-0000-4000-8001-000000000001',s,1,1);
 PERFORM pg_temp.ok(p->>'snapshot_id'=s::text AND p->>'source_sha256'=r->>'source_sha256' AND p->'observations'->0->>'nav_value'='122.100000' AND p->>'next_after_line' IS NULL,'snapshot_pin_survives_new_version');
 PERFORM pg_temp.ok(r2->>'snapshot_version'='2' AND r2->>'source_sha256'<>r->>'source_sha256','correction_is_new_version');
 PERFORM pg_temp.ok((SELECT count(*)=3 FROM nse_nav.observations),'old_values_retained');
 PERFORM pg_temp.ok((SELECT current_nav=99.1234 AND nav_date='2026-09-28' AND fund_house='Registrar AMC'
   FROM public.mutual_funds WHERE scheme_code='NSE-A'),'name_and_code_equality_do_not_crosswalk_or_replace_current_source');
 PERFORM pg_temp.ok((public.read_nse_nav_observations('b0640000-0000-4000-8001-000000000001',s,2,1000)->'observations')='[]'::jsonb,'end_page');
 FOREACH i IN ARRAY ARRAY[-1,3] LOOP
  PERFORM pg_temp.err(format('SELECT public.read_nse_nav_observations(%L,%L,%s,1)','b0640000-0000-4000-8001-000000000001',s,i),'nse_nav_page_invalid');
 END LOOP;
 FOREACH i IN ARRAY ARRAY[0,1001] LOOP
  PERFORM pg_temp.err(format('SELECT public.read_nse_nav_observations(%L,%L,0,%s)','b0640000-0000-4000-8001-000000000001',s,i),'nse_nav_page_invalid');
 END LOOP;
 -- Syntactically complete transport can still contain bad/truncated rows.
 PERFORM pg_temp.bad_nav(row1||'|','nse_nav_column_count');
 PERFORM pg_temp.bad_nav(left(row1,length(row1)-5),'nse_nav_column_count');
 PERFORM pg_temp.bad_nav('NAV Date|SCHEME CODE|SCHEME NAME|RTA SCHEME CODE|DIV FLAG|ISIN|NAV VALUE|RTA CODE','nse_nav_date_invalid');
 PERFORM pg_temp.bad_nav(row1||E'\n'||row1,'nse_nav_duplicate_identity',2);
 PERFORM pg_temp.bad_nav(row1||E'\n'||replace(row1,'123.450000','124.450000'),'nse_nav_duplicate_identity',2);
 PERFORM pg_temp.bad_nav(row1||E'\n'||replace(row1,'|Z|','|Y|'),'nse_nav_duplicate_identity',2);
 PERFORM pg_temp.bad_nav(row1||E'\n'||replace(row2,'122.100000','NaN'),'nse_nav_value_invalid',2);
 PERFORM pg_temp.bad_nav(row1||E'\n\n','nse_nav_framing_invalid',2);
 PERFORM pg_temp.bad_nav(row1||E'\r','nse_nav_framing_invalid',NULL);
 FOREACH bad IN ARRAY ARRAY['2026-02-30','2025-02-29','2026-13-01','2026-00-01','2026-09-31','30-09-2026','2026-9-30','0000-01-01','9999-01-01','infinity'] LOOP
  PERFORM pg_temp.bad_nav(replace(row1,'2026-09-30',bad),'nse_nav_date_invalid');
 END LOOP;
 FOREACH bad IN ARRAY ARRAY['0','0.0000','-1','+1','01.25','1e3','NaN','Infinity','.1','1.','1,234','123456789012345','1234567890.1234'] LOOP
  -- Last value has 15 characters; the documented limit is 14, not a guessed scale.
  PERFORM pg_temp.bad_nav(replace(row1,'123.450000',bad),'nse_nav_value_invalid');
 END LOOP;
 FOREACH bad IN ARRAY ARRAY['',' 1','1 ','1'||chr(9)] LOOP
  PERFORM pg_temp.bad_nav(replace(row1,'123.450000',bad),'nse_nav_field_invalid');
 END LOOP;
 PERFORM pg_temp.bad_nav(replace(row1,'NSE-A',repeat('a',31)),'nse_nav_field_invalid');
 PERFORM pg_temp.bad_nav(replace(row1,'Synthetic Growth',repeat('a',201)),'nse_nav_field_invalid');
 PERFORM pg_temp.bad_nav(replace(row1,'RTA-A',repeat('a',11)),'nse_nav_field_invalid');
 PERFORM pg_temp.bad_nav(replace(row1,'CAMS',repeat('a',11)),'nse_nav_field_invalid');
 PERFORM pg_temp.bad_nav(replace(row1,'INF000000001','not-an-isin'),'nse_nav_field_invalid');
 PERFORM pg_temp.bad_nav(replace(row1,'|Z|','|?|'),'nse_nav_field_invalid');
 PERFORM pg_temp.bad_nav(row1||E'\n'||chr(65279)||row2,'nse_nav_field_invalid',2);
 PERFORM pg_temp.ok(pg_temp.validate_nav(pg_temp.nav_file(replace(row1,'2026-09-30','2024-02-29')))->>'status'='VALIDATED_OBSERVATIONS','real_leap_day');
 PERFORM pg_temp.ok(pg_temp.validate_nav(pg_temp.nav_file(replace(row1,'123.450000','0.000000000001')))->>'status'='VALIDATED_OBSERVATIONS','exact_small_decimal');
 -- A web-report-shaped SET is still not a commissioned API calendar.
 blocked:=pg_temp.nav_file('MF|20260000001|30-09-2026|01-10-2026|01-10-2026|01-10-2026|01-10-2026','SET');
 INSERT INTO b064_ids VALUES('set',blocked);
 r:=public.assess_nse_set_snapshot('b0640000-0000-4000-8001-000000000001',blocked);
 PERFORM pg_temp.ok(r->>'status'='BLOCKED_LAYOUT_UNCHARACTERIZED' AND r->>'reason_code'='WEB77_API_COMPATIBILITY_AND_HEADER_UNCONFIRMED','set_web_report_is_not_api_proof');
 PERFORM pg_temp.ok(public.assess_nse_set_snapshot('b0640000-0000-4000-8001-000000000001',blocked)=r,'set_replay');
 PERFORM pg_temp.ok((SELECT count(*)=1 FROM public.workspace_audit_logs WHERE target_id=blocked AND action='nse.set.assessment'),'set_audit_once');
 PERFORM pg_temp.ok(public.assess_nse_set_snapshot('b0640000-0000-4000-8001-000000000001',pg_temp.nav_file('UNKNOWN|arbitrary|file','SET'))->>'status'='BLOCKED_LAYOUT_UNCHARACTERIZED','unknown_set_is_blocked');
 PERFORM pg_temp.err(format('SELECT pg_temp.validate_nav(%L)',blocked),'nse_nav_snapshot_unavailable');
 PERFORM pg_temp.err(format('SELECT public.assess_nse_set_snapshot(%L,%L)','b0640000-0000-4000-8001-000000000001',s),'nse_set_snapshot_unavailable');
 PERFORM pg_temp.err(format('SELECT pg_temp.validate_nav(%L)',pg_temp.nav_file(row1,'SCH')),'nse_nav_snapshot_unavailable');
 -- Ownership is enforced before returning cached receipts or observations.
 PERFORM pg_temp.err(format('SELECT public.validate_nse_nav_snapshot(%L,%L)','b0640000-0000-4000-8001-000000000002',s),'nse_nav_snapshot_unavailable');
 PERFORM pg_temp.err(format('SELECT public.read_nse_nav_observations(%L,%L)','b0640000-0000-4000-8001-000000000002',s),'nse_nav_snapshot_unavailable');
 PERFORM pg_temp.err(format('SELECT public.assess_nse_set_snapshot(%L,%L)','b0640000-0000-4000-8001-000000000002',blocked),'nse_set_snapshot_unavailable');
 UPDATE nse_reference.connections SET enabled=false;
 PERFORM pg_temp.err(format('SELECT pg_temp.validate_nav(%L)',s),'connection_unavailable');
 PERFORM pg_temp.err(format('SELECT public.read_nse_nav_observations(%L,%L)','b0640000-0000-4000-8001-000000000001',s),'connection_unavailable');
 PERFORM pg_temp.err(format('SELECT public.assess_nse_set_snapshot(%L,%L)','b0640000-0000-4000-8001-000000000001',blocked),'connection_unavailable');
 UPDATE nse_reference.connections SET enabled=true;
 UPDATE public.workspaces SET workspace_status='suspended' WHERE id='b0640000-0000-4000-8001-000000000001';
 PERFORM pg_temp.err(format('SELECT pg_temp.validate_nav(%L)',s),'workspace_unavailable');
 UPDATE public.workspaces SET workspace_status='active' WHERE id='b0640000-0000-4000-8001-000000000001';
 FOREACH t IN ARRAY ARRAY['nse_nav.validations','nse_nav.observations','nse_set.assessments'] LOOP
  PERFORM pg_temp.err('DELETE FROM '||t,'nse_reference_immutable');
  PERFORM pg_temp.err('UPDATE '||t||' SET workspace_id=workspace_id','nse_reference_immutable');
  PERFORM pg_temp.ok((SELECT relrowsecurity FROM pg_class WHERE oid=t::regclass),'rls_enabled:'||t);
  PERFORM pg_temp.ok(NOT has_table_privilege('anon',t,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE')
    AND NOT has_table_privilege('authenticated',t,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE')
    AND NOT has_table_privilege('service_role',t,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE'),'no_direct_acl:'||t);
 END LOOP;
 PERFORM pg_temp.ok((SELECT count(*)=0 FROM pg_policies WHERE schemaname IN ('nse_nav','nse_set')),'exclusive_zero_policy_surface');
 PERFORM pg_temp.ok(NOT EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema IN ('nse_nav','nse_set') AND column_name IN ('fund_id','mutual_fund_id','current_nav','metadata','password','api_key')),'no_implicit_crosswalk_or_secret_columns');
 FOR fn IN SELECT p.oid::regprocedure FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname IN ('validate_nse_nav_snapshot','read_nse_nav_observations','assess_nse_set_snapshot') LOOP
  PERFORM pg_temp.ok(has_function_privilege('service_role',fn,'EXECUTE') AND NOT has_function_privilege('authenticated',fn,'EXECUTE') AND NOT has_function_privilege('anon',fn,'EXECUTE'),'rpc_acl');
  PERFORM pg_temp.ok((SELECT prosecdef AND proconfig @> ARRAY['search_path=""'] FROM pg_proc WHERE oid=fn),'definer_path');
  PERFORM pg_temp.ok(NOT EXISTS(SELECT 1 FROM pg_proc p,LATERAL aclexplode(COALESCE(p.proacl,acldefault('f',p.proowner))) a WHERE p.oid=fn AND a.grantee=0 AND a.privilege_type='EXECUTE'),'no_public_execute');
 END LOOP;
 PERFORM pg_temp.ok(NOT has_function_privilege('service_role','nse_nav.audit_assessment()','EXECUTE'),'private_helper_acl');
END $$;
DO $$ DECLARE body text; s uuid; r jsonb; d uuid; kind text; bytes bytea;
BEGIN
 -- Exercise parsing across encrypted chunk boundaries and bounded page reads.
 SELECT string_agg(format('2026-09-30|NSE-%s|Synthetic Growth|RTA-A|Z|INF000000001|123.450000|CAMS',i),E'\n' ORDER BY i)
 INTO body FROM generate_series(1,4000) i;
 PERFORM pg_temp.ok(octet_length(body)>262144,'multichunk_nav_fixture');
 s:=pg_temp.nav_file(body); r:=pg_temp.validate_nav(s);
 PERFORM pg_temp.ok(r->>'row_count'='4000' AND r->>'status'='VALIDATED_OBSERVATIONS','multichunk_nav_parse');
 PERFORM pg_temp.ok(jsonb_array_length(public.read_nse_nav_observations('b0640000-0000-4000-8001-000000000001',s,0,1000)->'observations')=1000,'large_page_is_bounded');
 -- Typed rows cannot be attached to another owner/variant or a rejected receipt.
 s:=pg_temp.nav_file('a|b');
 PERFORM pg_temp.err(format('INSERT INTO nse_nav.validations(snapshot_id,parser_version,workspace_id,connection_id,source_sha256,status,row_count,rejection_code) VALUES(%L,%L,%L,%L,decode(repeat(%L,64),%L),%L,0,%L)',
  s,'NSE_NAV_WEB83_V1','b0640000-0000-4000-8001-000000000002','b0640000-0000-4000-8002-000000000001','a','hex','REJECTED','nse_nav_column_count'),'foreign key');
 -- Partial transport never gains a parser-eligible snapshot, even with valid-looking rows.
 FOREACH kind IN ARRAY ARRAY['TRUNCATED','UNVERIFIABLE','OVERSIZE','TRANSPORT_FAILED'] LOOP
  d:=pg_temp.begin_download('NAV'); bytes:=convert_to('2026-09-30|NSE-A|Synthetic Growth|RTA-A|Z|INF000000001|123.45|CAMS','UTF8');
  PERFORM pg_temp.append_chunk(d,0,bytes);
  PERFORM public.finish_nse_master_download('b0640000-0000-4000-8001-000000000001',d,kind,200,'TEXT',999,true,false,NULL);
  PERFORM pg_temp.err(format('SELECT pg_temp.stage(%L)',d),'not_stageable');
  PERFORM pg_temp.err(format('SELECT pg_temp.validate_nav(%L)',d),'snapshot_unavailable');
 END LOOP;
END $$;
SET CONSTRAINTS ALL IMMEDIATE;
-- Actual API roles. All browser personas are denied by role ACL regardless of claims.
SET LOCAL ROLE authenticated;
DO $$ DECLARE persona text; BEGIN
 FOREACH persona IN ARRAY ARRAY['platform_admin','family_guest','inactive_member','operations','unrelated_advisor','cross_workspace'] LOOP
  PERFORM set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub','b0640000-0000-4000-8000-000000000002','app_metadata',jsonb_build_object('role',persona))::text,true);
  BEGIN PERFORM public.validate_nse_nav_snapshot(NULL,NULL); RAISE EXCEPTION 'browser_nav_allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM public.read_nse_nav_observations(NULL,NULL); RAISE EXCEPTION 'browser_nav_read_allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM public.assess_nse_set_snapshot(NULL,NULL); RAISE EXCEPTION 'browser_set_allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM 1 FROM nse_nav.observations; RAISE EXCEPTION 'browser_table_allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 END LOOP;
END $$;
RESET ROLE;
SET LOCAL ROLE anon;
DO $$ BEGIN
 BEGIN PERFORM public.validate_nse_nav_snapshot(NULL,NULL); RAISE EXCEPTION 'anon_nav_allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM public.assess_nse_set_snapshot(NULL,NULL); RAISE EXCEPTION 'anon_set_allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
SELECT id AS nav_id FROM b064_ids WHERE label='nav' \gset
SELECT id AS set_id FROM b064_ids WHERE label='set' \gset
SELECT set_config('b064.nav_id',:'nav_id',true);
SET LOCAL ROLE service_role;
SELECT public.validate_nse_nav_snapshot('b0640000-0000-4000-8001-000000000001',:'nav_id');
SELECT public.read_nse_nav_observations('b0640000-0000-4000-8001-000000000001',:'nav_id');
SELECT public.assess_nse_set_snapshot('b0640000-0000-4000-8001-000000000001',:'set_id');
DO $$ BEGIN
 BEGIN PERFORM 1 FROM nse_nav.observations; RAISE EXCEPTION 'service_table_allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN INSERT INTO nse_set.assessments(snapshot_id) VALUES(gen_random_uuid()); RAISE EXCEPTION 'service_direct_insert_allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM public.validate_nse_nav_snapshot('b0640000-0000-4000-8001-000000000002',current_setting('b064.nav_id',true)::uuid); RAISE EXCEPTION 'service_cross_workspace_allowed';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'nse_nav_snapshot_unavailable' THEN RAISE; END IF; END;
END $$;
RESET ROLE;
SELECT count(*) AS b064_assertions FROM b064_assertions;
ROLLBACK;
