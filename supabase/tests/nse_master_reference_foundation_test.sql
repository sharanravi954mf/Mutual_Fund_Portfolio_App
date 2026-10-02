\set ON_ERROR_STOP on
BEGIN;
SELECT 1 FROM vault.create_secret(repeat('s',40),'integration_payload_encryption_key_v1','B06.1 synthetic rollback-only key');
INSERT INTO auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES
 ('b0610000-0000-4000-8000-000000000001','authenticated','authenticated','b061-one@moneybowl.invalid','{}','{}',now(),now()),
 ('b0610000-0000-4000-8000-000000000002','authenticated','authenticated','b061-two@moneybowl.invalid','{}','{}',now(),now());
INSERT INTO public.workspaces(id,name,slug,owner_profile_id,workspace_status)
SELECT ('b0610000-0000-4000-8001-'||right(user_id::text,12))::uuid,'B06 synthetic','b061-'||right(user_id::text,1),id,'active'
 FROM public.profiles WHERE user_id IN ('b0610000-0000-4000-8000-000000000001','b0610000-0000-4000-8000-000000000002');
INSERT INTO nse_reference.connections(id,workspace_id,environment,member_code,api_base_url,enabled)
VALUES('b0610000-0000-4000-8002-000000000001','b0610000-0000-4000-8001-000000000001','UAT','05418','https://nse.example.test',true);
CREATE TEMP TABLE b061_assertions(label text);
CREATE FUNCTION pg_temp.ok(b boolean,label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF b IS DISTINCT FROM true THEN RAISE EXCEPTION 'assertion_failed:%',label; END IF; INSERT INTO b061_assertions VALUES(label); END $$;
CREATE FUNCTION pg_temp.err(statement text,expected text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 BEGIN EXECUTE statement; EXCEPTION WHEN OTHERS THEN
  IF strpos(SQLERRM,expected)>0 THEN INSERT INTO b061_assertions VALUES('reject:'||expected); RETURN; END IF;
  RAISE EXCEPTION 'wrong_error:% expected:%',SQLERRM,expected;
 END;
 RAISE EXCEPTION 'missing_error:%',expected;
END $$;
CREATE FUNCTION pg_temp.begin_download(kind text DEFAULT 'SCH',call_id uuid DEFAULT gen_random_uuid(), token uuid DEFAULT gen_random_uuid()) RETURNS uuid LANGUAGE plpgsql AS $$
BEGIN
 PERFORM public.begin_nse_master_download('b0610000-0000-4000-8001-000000000001','b0610000-0000-4000-8002-000000000001',kind,call_id,'UAT','05418','https://nse.example.test',token);
 RETURN call_id;
END $$;
CREATE FUNCTION pg_temp.append_chunk(d uuid,n integer,b bytea) RETURNS void LANGUAGE sql AS $$
 SELECT public.append_nse_master_chunk('b0610000-0000-4000-8001-000000000001',d,n,replace(encode(b,'base64'),E'\n',''),encode(extensions.digest(b,'sha256'),'hex'));
$$;
CREATE FUNCTION pg_temp.finish(d uuid,b bytea,status integer DEFAULT 200,media text DEFAULT 'TEXT') RETURNS jsonb LANGUAGE sql AS $$
 SELECT public.finish_nse_master_download('b0610000-0000-4000-8001-000000000001',d,'COMPLETE',status,media,octet_length(b),true,true,encode(extensions.digest(b,'sha256'),'hex'));
$$;
CREATE FUNCTION pg_temp.stage(d uuid) RETURNS jsonb LANGUAGE sql AS $$
 SELECT public.stage_nse_reference_snapshot('b0610000-0000-4000-8001-000000000001',d);
$$;
CREATE FUNCTION pg_temp.store_file(kind text,b bytea) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE d uuid:=pg_temp.begin_download(kind); pos integer:=0;
BEGIN
 WHILE pos<octet_length(b) LOOP PERFORM pg_temp.append_chunk(d,pos/262144,substring(b FROM pos+1 FOR 262144)); pos:=pos+262144; END LOOP;
 PERFORM pg_temp.finish(d,b); RETURN d;
END $$;
CREATE FUNCTION pg_temp.forbid_reference_mutation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'b061_existing_reference_mutation'; END $$;
CREATE TRIGGER b061_no_funds BEFORE INSERT OR UPDATE OR DELETE ON public.mutual_funds FOR EACH STATEMENT EXECUTE FUNCTION pg_temp.forbid_reference_mutation();
CREATE TRIGGER b061_no_accounts BEFORE INSERT OR UPDATE OR DELETE ON public.integration_accounts FOR EACH STATEMENT EXECUTE FUNCTION pg_temp.forbid_reference_mutation();
CREATE TRIGGER b061_no_operations BEFORE INSERT OR UPDATE OR DELETE ON public.integration_operations FOR EACH STATEMENT EXECUTE FUNCTION pg_temp.forbid_reference_mutation();

DO $$ DECLARE kind text; d uuid; d2 uuid; token uuid:=gen_random_uuid(); b bytea; r jsonb; s jsonb; s2 jsonb; rec record; fn regprocedure; table_name text; n integer;
BEGIN
 PERFORM pg_temp.ok((SELECT count(*)=0 FROM public.integration_accounts WHERE workspace_id='b0610000-0000-4000-8001-000000000001'),'member_scope_needs_no_investor');
 PERFORM pg_temp.ok((SELECT attnotnull FROM pg_attribute WHERE attrelid='public.integration_operations'::regclass AND attname='integration_account_id'),'investor_operation_invariant_preserved');
 PERFORM pg_temp.ok((SELECT attnotnull FROM pg_attribute WHERE attrelid='public.integration_accounts'::regclass AND attname='investor_profile_id'),'investor_account_invariant_preserved');
 PERFORM pg_temp.err($q$INSERT INTO nse_reference.connections(workspace_id,environment,member_code,api_base_url) VALUES('b0610000-0000-4000-8001-000000000001','UAT','99999','https://nse.example.test')$q$,'unique');
 PERFORM pg_temp.err($q$INSERT INTO nse_reference.connections(workspace_id,environment,member_code,api_base_url) VALUES('b0610000-0000-4000-8001-000000000002','UAT','05418','https://nse.example.test')$q$,'unique');
 PERFORM pg_temp.err($q$INSERT INTO nse_reference.connections(workspace_id,environment,member_code,api_base_url) VALUES('b0610000-0000-4000-8001-000000000002','UAT','99999','https://nse.example.test')$q$,'unique');
 PERFORM pg_temp.err($q$INSERT INTO nse_reference.connections(workspace_id,environment,member_code,api_base_url) VALUES('b0610000-0000-4000-8001-000000000002','PRODUCTION','99999','https://user:secret@nse.example.test')$q$,'check constraint');
 PERFORM pg_temp.err($q$UPDATE nse_reference.connections SET workspace_id='b0610000-0000-4000-8001-000000000002'$q$,'identity_immutable');
 PERFORM pg_temp.err($q$UPDATE nse_reference.connections SET member_code='99999'$q$,'identity_immutable');
 PERFORM pg_temp.err($q$DELETE FROM nse_reference.connections$q$,'identity_immutable');
 PERFORM pg_temp.err($q$SELECT public.begin_nse_master_download('b0610000-0000-4000-8001-000000000002','b0610000-0000-4000-8002-000000000001','SCH',gen_random_uuid(),'UAT','05418','https://nse.example.test',gen_random_uuid())$q$,'connection_unavailable');
 PERFORM pg_temp.err($q$SELECT public.begin_nse_master_download('b0610000-0000-4000-8001-000000000001','b0610000-0000-4000-8002-000000000001','SCH',gen_random_uuid(),'UAT','99999','https://nse.example.test',gen_random_uuid())$q$,'runtime_binding_mismatch');
 PERFORM pg_temp.err($q$SELECT public.begin_nse_master_download('b0610000-0000-4000-8001-000000000001','b0610000-0000-4000-8002-000000000001','SCH',gen_random_uuid(),'PRODUCTION','05418','https://nse.example.test',gen_random_uuid())$q$,'runtime_binding_mismatch');
 PERFORM pg_temp.err($q$SELECT public.begin_nse_master_download('b0610000-0000-4000-8001-000000000001','b0610000-0000-4000-8002-000000000001','SCH',gen_random_uuid(),'UAT','05418','https://other.example.test',gen_random_uuid())$q$,'runtime_binding_mismatch');
 UPDATE nse_reference.connections SET enabled=false;
 PERFORM pg_temp.err($q$SELECT pg_temp.begin_download()$q$,'connection_unavailable');
 UPDATE nse_reference.connections SET enabled=true;
 UPDATE public.workspaces SET workspace_status='suspended' WHERE id='b0610000-0000-4000-8001-000000000001';
 PERFORM pg_temp.err($q$SELECT pg_temp.begin_download()$q$,'workspace_unavailable');
 UPDATE public.workspaces SET workspace_status='active' WHERE id='b0610000-0000-4000-8001-000000000001';
 FOREACH kind IN ARRAY ARRAY['sch','SCH ','','UNKNOWN','SCH|NAV','{"file_type":"SCH","Authorization":"secret"}',NULL] LOOP
  PERFORM pg_temp.err(format('SELECT pg_temp.begin_download(%L)',kind),'request_invalid');
 END LOOP;
 FOREACH kind IN ARRAY ARRAY['SCH','SIP','STP','SWP','NAV','SET'] LOOP
  b:=convert_to(E'\ufeffa|₹\r\nb|2\r\n','UTF8'); d:=pg_temp.store_file(kind,b); s:=pg_temp.stage(d);
  PERFORM pg_temp.ok(s->>'stage'='STAGED_UNVALIDATED' AND (s->>'version')::int=1 AND s->>'file_type'=kind,'six_staged_variants_'||kind);
  PERFORM pg_temp.ok(pg_temp.stage(d)=s,'stage_replay_immutable');
  r:=public.get_nse_reference_snapshot('b0610000-0000-4000-8001-000000000001',(s->>'snapshot_id')::uuid);
  PERFORM pg_temp.ok(r->>'download_id'=d::text AND r->>'file_type'=kind AND (r->>'chunk_count')::int=1,'durable_parser_manifest');
  PERFORM pg_temp.err(format('SELECT public.get_nse_reference_snapshot(%L,%L)','b0610000-0000-4000-8001-000000000002',s->>'snapshot_id'),'snapshot_unavailable');
  r:=public.read_nse_master_chunk('b0610000-0000-4000-8001-000000000001',d,0);
  PERFORM pg_temp.ok(decode(r->>'base64','base64')=b AND r->>'sha256'=encode(extensions.digest(b,'sha256'),'hex'),'exact_utf8_bom_crlf_evidence');
  PERFORM pg_temp.ok((SELECT request_body='{"file_type":"'||kind||'"}' AND request_sha256=extensions.digest(request_body,'sha256') FROM nse_reference.downloads WHERE id=d),'exact_credential_free_request');
  PERFORM pg_temp.err(format('INSERT INTO nse_reference.downloads(id,capture_token,workspace_id,connection_id,file_type,request_body) VALUES(gen_random_uuid(),gen_random_uuid(),%L,%L,%L,%L)',
   'b0610000-0000-4000-8001-000000000002','b0610000-0000-4000-8002-000000000001',kind,'{"file_type":"'||kind||'"}'),'foreign key');
  PERFORM pg_temp.err(format('SELECT public.read_nse_master_chunk(%L,%L,0)','b0610000-0000-4000-8001-000000000002',d),'download_unavailable');
  PERFORM pg_temp.err(format('SELECT public.stage_nse_reference_snapshot(%L,%L)','b0610000-0000-4000-8001-000000000002',d),'download_unavailable');
 END LOOP;
 d:=pg_temp.begin_download('SCH',gen_random_uuid(),token);
 PERFORM pg_temp.ok(pg_temp.begin_download('SCH',d,token)=d,'begin_ack_replay');
 PERFORM pg_temp.err(format('SELECT pg_temp.begin_download(%L,%L)', 'SCH',d),'idempotency_conflict');
 PERFORM pg_temp.err(format('SELECT pg_temp.begin_download(%L,%L,%L)', 'NAV',d,token),'idempotency_conflict');
 b:=convert_to(E'a|b\n','UTF8');
 PERFORM pg_temp.err(format('SELECT pg_temp.append_chunk(%L,1,%L::bytea)',d,b),'sequence_invalid');
 PERFORM pg_temp.err(format('SELECT public.append_nse_master_chunk(%L,%L,0,%L,%L)','b0610000-0000-4000-8001-000000000001',d,'!!!!',repeat('0',64)),'chunk_invalid');
 PERFORM pg_temp.err(format('SELECT public.append_nse_master_chunk(%L,%L,0,%L,%L)','b0610000-0000-4000-8001-000000000001',d,encode(b,'base64'),repeat('0',64)),'integrity_mismatch');
 PERFORM pg_temp.err(format('SELECT pg_temp.append_chunk(%L,0,convert_to(repeat(%L,262145),%L))',d,'a','UTF8'),'chunk_invalid');
 PERFORM pg_temp.append_chunk(d,0,b); PERFORM pg_temp.append_chunk(d,0,b);
 PERFORM pg_temp.err(format('SELECT pg_temp.append_chunk(%L,0,%L::bytea)',d,convert_to('changed','UTF8')),'idempotency_conflict');
 PERFORM pg_temp.err(format('SELECT public.append_nse_master_chunk(%L,%L,1,%L,%L)','b0610000-0000-4000-8001-000000000002',d,encode(b,'base64'),encode(extensions.digest(b,'sha256'),'hex')),'download_unavailable');
 PERFORM pg_temp.err(format('INSERT INTO nse_reference.evidence_chunks(download_id,workspace_id,ordinal,byte_count,sha256,ciphertext) VALUES(%L,%L,1,4,extensions.digest(%L,%L),%L::bytea)',d,'b0610000-0000-4000-8001-000000000002','test','sha256',b),'foreign key');
 PERFORM pg_temp.err(format('INSERT INTO nse_reference.results(download_id,workspace_id,capture_kind,media_type,identity_encoding,eof,captured_bytes,captured_sha256) VALUES(%L,%L,%L,%L,false,false,0,extensions.digest(%L,%L))',d,'b0610000-0000-4000-8001-000000000002','TRANSPORT_FAILED','UNKNOWN','','sha256'),'foreign key');
 PERFORM pg_temp.err(format('SELECT public.finish_nse_master_download(%L,%L,%L,200,%L,4,true,true,%L)', 'b0610000-0000-4000-8001-000000000002',d,'COMPLETE','TEXT',encode(extensions.digest(b,'sha256'),'hex')),'download_unavailable');
 PERFORM pg_temp.err(format('SELECT pg_temp.stage(%L)',d),'not_stageable');
 PERFORM pg_temp.err(format('SELECT public.finish_nse_master_download(%L,%L,%L,200,%L,999,true,true,%L)', 'b0610000-0000-4000-8001-000000000001',d,'COMPLETE','TEXT',encode(extensions.digest(b,'sha256'),'hex')),'incomplete_evidence');
 PERFORM pg_temp.err(format('SELECT public.finish_nse_master_download(%L,%L,%L,200,%L,NULL,true,true,%L)', 'b0610000-0000-4000-8001-000000000001',d,'COMPLETE','TEXT',encode(extensions.digest(b,'sha256'),'hex')),'incomplete_evidence');
 PERFORM pg_temp.err(format('SELECT public.finish_nse_master_download(%L,%L,%L,200,%L,4,false,true,%L)', 'b0610000-0000-4000-8001-000000000001',d,'COMPLETE','TEXT',encode(extensions.digest(b,'sha256'),'hex')),'incomplete_evidence');
 PERFORM pg_temp.err(format('SELECT public.finish_nse_master_download(%L,%L,%L,200,%L,4,true,false,%L)', 'b0610000-0000-4000-8001-000000000001',d,'COMPLETE','TEXT',encode(extensions.digest(b,'sha256'),'hex')),'incomplete_evidence');
 PERFORM pg_temp.err(format('SELECT pg_temp.finish(%L,%L::bytea)',d,convert_to('bad!','UTF8')),'incomplete_evidence');
 r:=pg_temp.finish(d,b); PERFORM pg_temp.ok(pg_temp.finish(d,b)=r,'finish_ack_replay'); s:=pg_temp.stage(d);
 PERFORM pg_temp.err(format('INSERT INTO nse_reference.snapshots(workspace_id,connection_id,file_type,version,previous_snapshot_id,download_id) VALUES(%L,%L,%L,3,%L,%L)', 'b0610000-0000-4000-8001-000000000002','b0610000-0000-4000-8002-000000000001','SCH',s->>'snapshot_id',gen_random_uuid()),'foreign key');
 PERFORM pg_temp.ok((s->>'version')::int=2 AND s->>'previous_snapshot_id' IS NOT NULL,'independent_version_lineage');
 PERFORM pg_temp.err(format('SELECT pg_temp.finish(%L,%L::bytea,500)',d,b),'idempotency_conflict');
 PERFORM pg_temp.err(format('SELECT pg_temp.append_chunk(%L,1,%L::bytea)',d,b),'evidence_sealed');
 PERFORM pg_temp.err(format('UPDATE nse_reference.snapshots SET stage=%L WHERE download_id=%L','PUBLISHED',d),'immutable');
 PERFORM pg_temp.err(format('UPDATE nse_reference.snapshots SET version=99 WHERE download_id=%L',d),'immutable');
 FOREACH table_name IN ARRAY ARRAY['downloads','evidence_chunks','results','snapshots'] LOOP
  PERFORM pg_temp.err(format('DELETE FROM nse_reference.%I',table_name),'immutable');
 END LOOP;
 -- Detect persisted corruption, even under a privileged maintenance fixture.
 ALTER TABLE nse_reference.evidence_chunks DISABLE TRIGGER immutable;
 UPDATE nse_reference.evidence_chunks SET sha256=extensions.digest('tampered','sha256') WHERE download_id=d;
 PERFORM pg_temp.err(format('SELECT pg_temp.stage(%L)',d),'integrity_mismatch');
 PERFORM pg_temp.err(format('SELECT public.read_nse_master_chunk(%L,%L,0)','b0610000-0000-4000-8001-000000000001',d),'integrity_mismatch');
 UPDATE nse_reference.evidence_chunks SET sha256=extensions.digest(b,'sha256') WHERE download_id=d;
 ALTER TABLE nse_reference.evidence_chunks ENABLE TRIGGER immutable;
 FOREACH kind IN ARRAY ARRAY['OVERSIZE','TRUNCATED','TRANSPORT_FAILED','UNVERIFIABLE'] LOOP
  d:=pg_temp.begin_download(); PERFORM pg_temp.append_chunk(d,0,b);
  r:=public.finish_nse_master_download('b0610000-0000-4000-8001-000000000001',d,kind,200,'TEXT',999,true,false,NULL);
  PERFORM pg_temp.ok(r->>'response_sha256' IS NULL AND (r->>'captured_bytes')::int=4,'partial_prefix_not_complete');
  PERFORM pg_temp.err(format('SELECT pg_temp.stage(%L)',d),'not_stageable');
 END LOOP;
 FOREACH kind IN ARRAY ARRAY['JSON','HTTP','HTML','INVALID_UTF8','EMPTY','TEXT_JSON','NO_PIPE'] LOOP
  b:=CASE kind WHEN 'INVALID_UTF8' THEN decode('ff7c','hex') WHEN 'EMPTY' THEN ''::bytea
    WHEN 'HTML' THEN convert_to('<html>a|b</html>','UTF8') WHEN 'NO_PIPE' THEN convert_to('error','UTF8')
    ELSE convert_to('{"response_status":"F","remark":"a|b"}','UTF8') END;
  d:=pg_temp.begin_download(); IF octet_length(b)>0 THEN PERFORM pg_temp.append_chunk(d,0,b); END IF;
  PERFORM pg_temp.finish(d,b,CASE WHEN kind='HTTP' THEN 503 ELSE 200 END,CASE WHEN kind='JSON' THEN 'JSON' ELSE 'TEXT' END);
  PERFORM pg_temp.err(format('SELECT pg_temp.stage(%L)',d),'nse_reference_not_');
 END LOOP;
 -- Measured historical SCH size and exact maximum, encrypted and verified in SQL.
 FOREACH n IN ARRAY ARRAY[4057995,16777216] LOOP
  b:=convert_to('a|'||repeat('x',n-2),'UTF8'); d:=pg_temp.store_file('SCH',b); s:=pg_temp.stage(d);
  PERFORM pg_temp.ok((SELECT captured_bytes=n AND response_sha256=extensions.digest(b,'sha256') FROM nse_reference.results WHERE download_id=d),'multi_megabyte_exact_bound_'||n);
 END LOOP;
 -- Exclusive ACL surface: service-only RPCs, no table or private helper access.
 FOREACH table_name IN ARRAY ARRAY['connections','downloads','evidence_chunks','results','snapshots'] LOOP
  PERFORM pg_temp.ok((SELECT relrowsecurity FROM pg_class WHERE oid=('nse_reference.'||table_name)::regclass),'rls_'||table_name);
  PERFORM pg_temp.ok(NOT EXISTS(SELECT 1 FROM pg_policies WHERE schemaname='nse_reference' AND tablename=table_name),'no_permissive_policies_'||table_name);
  FOREACH kind IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
   PERFORM pg_temp.ok(NOT has_table_privilege(kind,'nse_reference.'||table_name,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'),'private_table_'||kind||table_name);
  END LOOP;
 END LOOP;
 FOR fn IN SELECT p.oid::regprocedure FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='nse_reference' LOOP
  PERFORM pg_temp.ok(NOT has_function_privilege('service_role',fn,'EXECUTE') AND NOT has_function_privilege('authenticated',fn,'EXECUTE') AND NOT has_function_privilege('anon',fn,'EXECUTE'),'private_helper_acl');
 END LOOP;
 FOR fn IN SELECT p.oid::regprocedure FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public'
  AND p.proname IN ('begin_nse_master_download','append_nse_master_chunk','finish_nse_master_download','read_nse_master_chunk','stage_nse_reference_snapshot','get_nse_reference_snapshot') LOOP
  PERFORM pg_temp.ok(has_function_privilege('service_role',fn,'EXECUTE') AND NOT has_function_privilege('authenticated',fn,'EXECUTE') AND NOT has_function_privilege('anon',fn,'EXECUTE'),'service_rpc_acl');
  PERFORM pg_temp.ok((SELECT prosecdef AND proconfig @> ARRAY['search_path=""'] FROM pg_proc WHERE oid=fn),'definer_empty_search_path');
  PERFORM pg_temp.ok(NOT EXISTS(SELECT 1 FROM pg_proc p,LATERAL aclexplode(COALESCE(p.proacl,acldefault('f',p.proowner))) a WHERE p.oid=fn AND a.grantee=0 AND a.privilege_type='EXECUTE'),'no_public_execute');
 END LOOP;
 PERFORM pg_temp.ok((SELECT count(*) FROM pg_policies WHERE schemaname='nse_reference')=0,'exact_zero_policy_set');
 PERFORM pg_temp.ok(NOT EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='nse_reference' AND column_name IN ('investor_profile_id','integration_account_id','api_key','api_secret','login_user_id','authorization','password','metadata')),'no_investor_or_credentials_or_arbitrary_metadata');
END $$;
-- Simulate a future broadening migration: runtime cardinality still fails closed.
SAVEPOINT ambiguous_member;
ALTER TABLE nse_reference.connections DROP CONSTRAINT connections_environment_member_code_key;
ALTER TABLE nse_reference.connections DROP CONSTRAINT connections_environment_credential_slot_key;
INSERT INTO nse_reference.connections(workspace_id,environment,member_code,api_base_url,enabled)
 VALUES('b0610000-0000-4000-8001-000000000002','UAT','05418','https://nse.example.test',true);
SELECT pg_temp.err('SELECT pg_temp.begin_download()','member_ambiguous');
ROLLBACK TO ambiguous_member;
SET LOCAL ROLE service_role;
SELECT public.begin_nse_master_download('b0610000-0000-4000-8001-000000000001','b0610000-0000-4000-8002-000000000001','NAV',gen_random_uuid(),'UAT','05418','https://nse.example.test',gen_random_uuid());
DO $$ BEGIN
 BEGIN PERFORM 1 FROM nse_reference.connections; RAISE EXCEPTION 'service_direct_table_allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM public.begin_nse_master_download('b0610000-0000-4000-8001-000000000002','b0610000-0000-4000-8002-000000000001','SCH',gen_random_uuid(),'UAT','05418','https://nse.example.test',gen_random_uuid()); RAISE EXCEPTION 'service_cross_workspace_allowed';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'nse_reference_connection_unavailable' THEN RAISE; END IF; END;
END $$;
RESET ROLE;
SET LOCAL ROLE authenticated;
DO $$ DECLARE persona text; BEGIN
 FOREACH persona IN ARRAY ARRAY['platform_admin','family_guest','inactive_member','operations','unrelated_advisor','cross_workspace'] LOOP
  PERFORM set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub','b0610000-0000-4000-8000-000000000002','app_metadata',jsonb_build_object('role',persona))::text,true);
  BEGIN PERFORM public.begin_nse_master_download(NULL,NULL,'SCH',NULL,'UAT','05418','https://nse.example.test',NULL); RAISE EXCEPTION 'browser_begin_allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM public.read_nse_master_chunk(NULL,NULL,0); RAISE EXCEPTION 'browser_evidence_allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM public.stage_nse_reference_snapshot(NULL,NULL); RAISE EXCEPTION 'browser_stage_allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM 1 FROM nse_reference.snapshots; RAISE EXCEPTION 'browser_table_allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 END LOOP;
END $$;
RESET ROLE;
SET LOCAL ROLE anon;
DO $$ BEGIN
 BEGIN PERFORM public.stage_nse_reference_snapshot(NULL,NULL); RAISE EXCEPTION 'anon_stage_allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM 1 FROM nse_reference.evidence_chunks; RAISE EXCEPTION 'anon_evidence_allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
SELECT count(*) AS b061_assertions FROM b061_assertions;
ROLLBACK;
