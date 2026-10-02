\set ON_ERROR_STOP on
BEGIN;
SELECT 1 FROM vault.create_secret(repeat('s',40),'integration_payload_encryption_key_v1','B06.3 synthetic rollback-only key');
INSERT INTO auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES
 ('b0630000-0000-4000-8000-000000000001','authenticated','authenticated','b063-one@moneybowl.invalid','{}','{}',now(),now()),
 ('b0630000-0000-4000-8000-000000000002','authenticated','authenticated','b063-two@moneybowl.invalid','{}','{}',now(),now());
INSERT INTO public.workspaces(id,name,slug,owner_profile_id,workspace_status)
SELECT ('b0630000-0000-4000-8001-'||right(user_id::text,12))::uuid,'B06 synthetic','b063-'||right(user_id::text,1),id,'active'
 FROM public.profiles WHERE user_id IN ('b0630000-0000-4000-8000-000000000001','b0630000-0000-4000-8000-000000000002');
INSERT INTO nse_reference.connections(id,workspace_id,environment,member_code,api_base_url,enabled)
VALUES('b0630000-0000-4000-8002-000000000001','b0630000-0000-4000-8001-000000000001','UAT','05418','https://nse.example.test',true);
CREATE TEMP TABLE b063_assertions(label text);
CREATE FUNCTION pg_temp.ok(b boolean,label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF b IS DISTINCT FROM true THEN RAISE EXCEPTION 'assertion_failed:%',label; END IF; INSERT INTO b063_assertions VALUES(label); END $$;
CREATE FUNCTION pg_temp.err(statement text,expected text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 BEGIN EXECUTE statement; EXCEPTION WHEN OTHERS THEN
  IF strpos(SQLERRM,expected)>0 THEN INSERT INTO b063_assertions VALUES('reject:'||expected); RETURN; END IF;
  RAISE EXCEPTION 'wrong_error:% expected:%',SQLERRM,expected;
 END;
 RAISE EXCEPTION 'missing_error:%',expected;
END $$;
CREATE FUNCTION pg_temp.begin_download(kind text DEFAULT 'SCH',call_id uuid DEFAULT gen_random_uuid(), token uuid DEFAULT gen_random_uuid()) RETURNS uuid LANGUAGE plpgsql AS $$
BEGIN
 PERFORM public.begin_nse_master_download('b0630000-0000-4000-8001-000000000001','b0630000-0000-4000-8002-000000000001',kind,call_id,'UAT','05418','https://nse.example.test',token);
 RETURN call_id;
END $$;
CREATE FUNCTION pg_temp.append_chunk(d uuid,n integer,b bytea) RETURNS void LANGUAGE sql AS $$
 SELECT public.append_nse_master_chunk('b0630000-0000-4000-8001-000000000001',d,n,replace(encode(b,'base64'),E'\n',''),encode(extensions.digest(b,'sha256'),'hex'));
$$;
CREATE FUNCTION pg_temp.finish(d uuid,b bytea,status integer DEFAULT 200,media text DEFAULT 'TEXT') RETURNS jsonb LANGUAGE sql AS $$
 SELECT public.finish_nse_master_download('b0630000-0000-4000-8001-000000000001',d,'COMPLETE',status,media,octet_length(b),true,true,encode(extensions.digest(b,'sha256'),'hex'));
$$;
CREATE FUNCTION pg_temp.stage(d uuid) RETURNS jsonb LANGUAGE sql AS $$
 SELECT public.stage_nse_reference_snapshot('b0630000-0000-4000-8001-000000000001',d);
$$;
CREATE FUNCTION pg_temp.store_file(kind text,b bytea) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE d uuid:=pg_temp.begin_download(kind); pos integer:=0;
BEGIN
 WHILE pos<octet_length(b) LOOP PERFORM pg_temp.append_chunk(d,pos/262144,substring(b FROM pos+1 FOR 262144)); pos:=pos+262144; END LOOP;
 PERFORM pg_temp.finish(d,b); RETURN d;
END $$;
CREATE FUNCTION pg_temp.file(kind text) RETURNS text LANGUAGE sql AS $$ SELECT CASE kind
 WHEN 'SIP' THEN $file$AMC CODE|AMC NAME|SCHEME CODE|SCHEME NAME|SIP TRANSACTION MODE|SIP FREQUENCY|SIP DATES|SIP MINIMUM GAP|SIP MAXIMUM GAP|SIP INSTALLMENT GAP|SIP STATUS|SIP MINIMUM INSTALLMENT AMOUNT|SIP MAXIMUM INSTALLMENT AMOUNT|SIP MULTIPLIER AMOUNT|SIP MINIMUM INSTALLMENT NUMBERS|SIP MAXIMUM INSTALLMENT NUMBERS|SCHEME ISIN|SCHEME TYPE|PAUSE FLAG|PAUSE MINIMUM INSTALLMENTS|PAUSE MAXIMUM INSTALLMENTS|PAUSE MODIFICATION COUNT|FILLER 1|FILLER 2|FILLER 3|FILLER 4|FILLER 5
SYNTHETIC_AMC|Synthetic AMC|NSE_TEST_001|Synthetic Growth ₹|P|MONTHLY|1,15|1|1|1|1|100.25|100.25|1|1|1|INF000000001|SYNTHETIC|N||||||||
$file$
 WHEN 'STP' THEN $file$AMC CODE|AMC NAME|NSE SCHEME CODE|SCHEME NAME|SCHEME ISIN|SCHEME TYPE|ASTP TRANSACTION MODE|ASTP IN MINIMUM INSTALLMENT AMOUNT|ASTP IN MAXIMUM INSTALLMENT AMOUNT|ASTP IN MULTIPLIER AMOUNT|ASTP OUT MINIMUM INSTALLMENT AMOUNT|ASTP OUT MAXIMUM INSTALLMENT AMOUNT|ASTP OUT MULTIPLIER AMOUNT|ASTP MINIMUM INSTALLMENT UNITS|ASTP MAXIMUM INSTALLMENT UNITS|ASTP MULTIPLIER UNITS|ASTP MINIMUM INSTALLMENT NUMBERS|ASTP MAXIMUM INSTALLMENT NUMBERS|ASTP REG IN|ASTP REG OUT|ASTP FREQUENCY|ASTP DATES|ASTP MINIMUM GAP|ASTP MAXIMUM GAP|ASTP INSTALLMENT GAP|ASTP STATUS
SYNTHETIC_AMC|Synthetic AMC|NSE_TEST_001|Synthetic Growth ₹|INF000000001|SYNTHETIC|P|100.25|100.25|1|100.25|100.25|1|100.25|100.25|1|1|1|1|1|MONTHLY|1,15|1|1|1|1
$file$
 WHEN 'SWP' THEN $file$AMC CODE|AMC NAME|NSE SCHEME CODE|SCHEME NAME|SCHEME ISIN|SCHEME TYPE|SWP TRANSACTION MODE|SWP MINIMUM INSTALLMENT AMOUNT|SWP MAXIMUM INSTALLMENT AMOUNT|SWP MULTIPLIER AMOUNT|SWP MINIMUM INSTALLMENT UNITS|SWP MAXIMUM INSTALLMENT UNITS|SWP MULTIPLIER UNITS|SWP MINIMUM INSTALLMENT NUMBERS|SWP MAXIMUM INSTALLMENT NUMBERS|SWP FREQUENCY|SWP DATES|SWP MINIMUM GAP|SWP MAXIMUM GAP|SWP INSTALLMENT GAP|SWP STATUS
SYNTHETIC_AMC|Synthetic AMC|NSE_TEST_001|Synthetic Growth ₹|INF000000001|SYNTHETIC|P|100.25|100.25|1|100.125|100.125|1|1|1|MONTHLY|1,15|1|1|1|1
$file$
 END $$;
CREATE FUNCTION pg_temp.snapshot(kind text,body text) RETURNS uuid LANGUAGE plpgsql AS $$
BEGIN RETURN (pg_temp.stage(pg_temp.store_file(kind,convert_to(body,'UTF8')))->>'snapshot_id')::uuid; END $$;
CREATE FUNCTION pg_temp.publish(s uuid,prior uuid DEFAULT NULL) RETURNS jsonb LANGUAGE sql AS $$
 SELECT public.publish_nse_systematic_snapshot('b0630000-0000-4000-8001-000000000001',s,prior)
$$;
CREATE FUNCTION pg_temp.current(kind text) RETURNS jsonb LANGUAGE sql AS $$
 SELECT public.get_nse_systematic_current('b0630000-0000-4000-8001-000000000001','b0630000-0000-4000-8002-000000000001',kind)
$$;
CREATE FUNCTION pg_temp.products(s uuid,code text DEFAULT 'NSE_TEST_001',after_line integer DEFAULT 1,max_rows integer DEFAULT 100) RETURNS jsonb LANGUAGE sql AS $$
 SELECT public.get_nse_systematic_products('b0630000-0000-4000-8001-000000000001',s,code,after_line,max_rows)
$$;
CREATE FUNCTION pg_temp.forbid_mutation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'b063_investor_state_mutation'; END $$;
DO $$ DECLARE t text; BEGIN
 FOR t IN SELECT tablename FROM pg_tables WHERE schemaname='public' AND
   (tablename IN ('mutual_funds','integration_accounts','integration_operations','event_outbox','transactions','holdings','order_requests')
    OR tablename LIKE 'nse_sip_%' OR tablename LIKE 'nse_stp_%') LOOP
   EXECUTE format('CREATE TRIGGER b063_no_mutation BEFORE INSERT OR UPDATE OR DELETE ON public.%I FOR EACH STATEMENT EXECUTE FUNCTION pg_temp.forbid_mutation()',t);
 END LOOP;
END $$;
-- FIXTURE_END: concurrency uses the setup above, never the rollback-only assertions.
DO $$ DECLARE kind text; other text; body text; s uuid; s2 uuid; s3 uuid; r jsonb; p jsonb; bad text;
  table_name text; fn regprocedure; c text[]; old_download uuid; field_name text; expected jsonb;
BEGIN
 FOREACH kind IN ARRAY ARRAY['SIP','STP','SWP'] LOOP
  PERFORM pg_temp.ok(pg_temp.current(kind) IS NULL,'initial_no_current_'||kind);
  body:=pg_temp.file(kind); s:=pg_temp.snapshot(kind,chr(65279)||replace(body,E'\n',E'\r\n'));
  PERFORM pg_temp.ok(pg_temp.current(kind) IS NULL,'staging_does_not_publish_'||kind);
  r:=public.validate_nse_systematic_snapshot('b0630000-0000-4000-8001-000000000001',s);
  PERFORM pg_temp.ok(r->>'authority'='REFERENCE_ONLY' AND r->>'row_count'='1' AND r->>'rejected_rows'='0','validated_reference_'||kind);
  PERFORM pg_temp.ok(r->>'source_sha256'=encode(extensions.digest(chr(65279)||replace(body,E'\n',E'\r\n'),'sha256'),'hex'),'exact_source_digest_'||kind);
  PERFORM pg_temp.ok(r=public.validate_nse_systematic_snapshot('b0630000-0000-4000-8001-000000000001',s),'validation_replay_'||kind);
  PERFORM pg_temp.ok(pg_temp.current(kind) IS NULL,'validation_does_not_publish_'||kind);
  PERFORM pg_temp.err(format('SELECT pg_temp.products(%L)',s),'publication_unavailable');
  PERFORM pg_temp.ok((pg_temp.publish(s)->>'is_current')::boolean,'publish_'||kind);
  PERFORM pg_temp.ok((pg_temp.publish(s)->>'is_current')::boolean,'publish_ack_retry_'||kind);
  p:=pg_temp.products(s);
  PERFORM pg_temp.ok(p->>'eligibility'='UNINTERPRETED' AND p->>'scheme_namespace'='NSE','not_investor_eligibility_'||kind);
  PERFORM pg_temp.ok(p->'rows'->0->>'scheme_code'='NSE_TEST_001' AND p->'rows'->0->>'source_line'='2','source_row_lineage_'||kind);
  PERFORM pg_temp.ok(p->'rows'->0->>'source_row_sha256'=encode(extensions.digest(split_part(body,E'\n',2),'sha256'),'hex'),'exact_row_digest_'||kind);
  PERFORM pg_temp.ok(jsonb_array_length(pg_temp.products(s,'unknown')->'rows')=0,'unknown_identity_empty_'||kind);
  PERFORM pg_temp.ok(jsonb_array_length(pg_temp.products(s,'NSE_TEST_001',2)->'rows')=0,'pinned_pagination_'||kind);
  IF kind='SWP' THEN PERFORM pg_temp.ok((p->'rows'->0->>'minimum_installment_units')::numeric=100.125,'swp_three_place_units'); END IF;
  IF kind='STP' THEN PERFORM pg_temp.ok(p->'rows'->0 ? 'in_minimum_installment_amount' AND p->'rows'->0 ? 'out_minimum_installment_amount','stp_separate_directions'); END IF;
  -- Multiple rows can share a scheme; no undocumented row key/deduplication.
  s2:=pg_temp.snapshot(kind,body||replace(split_part(body,E'\n',2),'MONTHLY','WEEKLY')||E'\n');
  s3:=pg_temp.snapshot(kind,body);
  PERFORM pg_temp.err(format('SELECT pg_temp.publish(%L)',s3),'publication_conflict');
  PERFORM pg_temp.ok((pg_temp.publish(s2,s)->>'is_current')::boolean,'cas_success_'||kind);
  PERFORM pg_temp.ok(jsonb_array_length(pg_temp.products(s2)->'rows')=2,'multiple_reference_candidates_'||kind);
  PERFORM pg_temp.ok(jsonb_array_length(pg_temp.products(s2,'NSE_TEST_001',1,1)->'rows')=1,'page_limit_'||kind);
  PERFORM pg_temp.ok(jsonb_array_length(pg_temp.products(s)->'rows')=1,'historical_reader_pinned_'||kind);
  PERFORM pg_temp.err(format('SELECT pg_temp.publish(%L,%L)',s3,s),'publication_conflict');
  PERFORM pg_temp.ok(NOT (pg_temp.publish(s)->>'is_current')::boolean,'historical_ack_cannot_republish_'||kind);
  PERFORM pg_temp.ok((pg_temp.publish(s3,s2)->>'is_current')::boolean,'same_bytes_new_evidence_version_'||kind);
  PERFORM pg_temp.ok((pg_temp.current(kind)->>'snapshot_id')::uuid=s3,'latest_valid_current_'||kind);
  -- Unknown/malformed variant is isolated; preserve all prior published references.
  FOREACH bad IN ARRAY ARRAY[
    body||replace(split_part(body,E'\n',2),'100.25','bad')||E'\n',
    replace(body,'AMC CODE','AMC_CODE'), split_part(body,E'\n',1)||E'\n',
    body||E'\n',body||split_part(body,E'\n',2)||E'\n',
    replace(body,'Synthetic AMC',''), replace(body,'100.25','1e3'),
    replace(body,'100.25','1.001'),replace(body,'100.25','10000000000'),
    replace(body,'NSE_TEST_001',' NSE_TEST_001'),replace(body,'NSE_TEST_001',repeat('x',31)),
    replace(body,E'\n',E'\r'),replace(body,'Synthetic AMC',E'Synthetic\tAMC')
  ] LOOP
    s2:=pg_temp.snapshot(kind,bad);
    PERFORM pg_temp.err(format('SELECT pg_temp.publish(%L,%L)',s2,s3),'nse_systematic_');
    PERFORM pg_temp.ok(NOT EXISTS(SELECT 1 FROM nse_reference.systematic_validations WHERE snapshot_id=s2),'failed_validation_atomic_'||kind);
    PERFORM pg_temp.ok((pg_temp.current(kind)->>'snapshot_id')::uuid=s3,'failed_publish_keeps_current_'||kind);
  END LOOP;
  FOREACH other IN ARRAY ARRAY['SIP','STP','SWP'] LOOP
    IF other<>kind THEN
      s2:=pg_temp.snapshot(kind,pg_temp.file(other));
      PERFORM pg_temp.err(format('SELECT pg_temp.publish(%L,%L)',s2,s3),'layout_unknown');
    END IF;
  END LOOP;
  c:=string_to_array(split_part(body,E'\n',2),'|');
  s2:=pg_temp.snapshot(kind,split_part(body,E'\n',1)||E'\n'||array_to_string(c[1:cardinality(c)-1],'|'));
  PERFORM pg_temp.err(format('SELECT pg_temp.publish(%L,%L)',s2,s3),'column_count');
  s2:=pg_temp.snapshot(kind,split_part(body,E'\n',1)||E'\n'||array_to_string(c,'|')||'|');
  PERFORM pg_temp.err(format('SELECT pg_temp.publish(%L,%L)',s2,s3),'column_count');
  PERFORM pg_temp.err(format('SELECT public.validate_nse_systematic_snapshot(%L,%L)','b0630000-0000-4000-8001-000000000002',s),'snapshot_unavailable');
  PERFORM pg_temp.err(format('SELECT public.publish_nse_systematic_snapshot(%L,%L,NULL)','b0630000-0000-4000-8001-000000000002',s),'snapshot_unavailable');
  PERFORM pg_temp.err(format('SELECT public.get_nse_systematic_products(%L,%L,%L)','b0630000-0000-4000-8001-000000000002',s,'NSE_TEST_001'),'publication_unavailable');
 END LOOP;
 -- No backward promotion even if the expected current is correct.
 s:=pg_temp.snapshot('SIP',pg_temp.file('SIP'));s2:=pg_temp.snapshot('SIP',pg_temp.file('SIP'));
 PERFORM pg_temp.publish(s2,(pg_temp.current('SIP')->>'snapshot_id')::uuid);
 PERFORM pg_temp.err(format('SELECT pg_temp.publish(%L,%L)',s,s2),'version_regression');
 -- Pause values and reserved fields are explicitly uncharacterized outside the profile.
 FOR i IN 19..27 LOOP
  c:=string_to_array(split_part(pg_temp.file('SIP'),E'\n',2),'|');c[i]:='Y';
  s:=pg_temp.snapshot('SIP',split_part(pg_temp.file('SIP'),E'\n',1)||E'\n'||array_to_string(c,'|'));
  PERFORM pg_temp.err(format('SELECT pg_temp.publish(%L,%L)',s,s2),'reserved_field');
 END LOOP;
 s:=pg_temp.snapshot('STP',replace(pg_temp.file('STP'),'100.25','100.125'));
 PERFORM pg_temp.err(format('SELECT public.validate_nse_systematic_snapshot(%L,%L)','b0630000-0000-4000-8001-000000000001',s),'number_invalid');
 -- Captured earlier but staged later must not replace a more recent capture.
 old_download:=pg_temp.store_file('SWP',convert_to(pg_temp.file('SWP'),'UTF8'));
 s:=pg_temp.snapshot('SWP',pg_temp.file('SWP'));
 PERFORM pg_temp.publish(s,(pg_temp.current('SWP')->>'snapshot_id')::uuid);
 s2:=(pg_temp.stage(old_download)->>'snapshot_id')::uuid;
 PERFORM pg_temp.err(format('SELECT pg_temp.publish(%L,%L)',s2,s),'capture_regression');
 -- Same-scope composite lineage also protects privileged migration maintenance.
 PERFORM pg_temp.err($q$UPDATE nse_reference.sip_products SET workspace_id='b0630000-0000-4000-8001-000000000002'$q$,'immutable');
 PERFORM pg_temp.ok((SELECT count(*)=0 FROM nse_reference.systematic_validations v WHERE v.row_count<>(
   SELECT count(*) FROM (SELECT snapshot_id FROM nse_reference.sip_products UNION ALL SELECT snapshot_id FROM nse_reference.stp_products UNION ALL SELECT snapshot_id FROM nse_reference.swp_products) p WHERE p.snapshot_id=v.snapshot_id)), 'receipt_counts_match_all_rows');
 -- Distinct column sentinels prevent accidental cross-wiring of variant rules.
 FOREACH kind IN ARRAY ARRAY['SIP','STP','SWP'] LOOP
  c:=string_to_array(split_part(pg_temp.file(kind),E'\n',2),'|');
  IF kind='SIP' THEN
    c[8]:='2';c[9]:='31';c[10]:='5';c[12]:='10.25';c[13]:='1000.25';c[14]:='25';c[15]:='6';c[16]:='120';
    expected:='{"minimum_gap":2,"maximum_gap":31,"installment_gap":5,"minimum_installment_amount":"10.25","maximum_installment_amount":"1000.25","multiplier_amount":25,"minimum_installments":6,"maximum_installments":120}';
  ELSIF kind='STP' THEN
    c[8]:='100';c[9]:='200';c[10]:='5';c[11]:='50';c[12]:='500';c[13]:='10';c[14]:='0.25';c[15]:='99.25';c[16]:='1';c[17]:='4';c[18]:='40';c[19]:='8';c[20]:='9';
    expected:='{"in_minimum_installment_amount":"100.00","in_maximum_installment_amount":"200.00","in_multiplier_amount":5,"out_minimum_installment_amount":"50.00","out_maximum_installment_amount":"500.00","out_multiplier_amount":10,"minimum_installment_units":"0.25","maximum_installment_units":"99.25","multiplier_units":1,"minimum_installments":4,"maximum_installments":40,"registration_in":8,"registration_out":9}';
  ELSE
    c[8]:='300';c[9]:='1000';c[10]:='100';c[11]:='1.125';c[12]:='9.875';c[13]:='2';c[14]:='8';c[15]:='88';
    expected:='{"minimum_installment_amount":"300.00","maximum_installment_amount":"1000.00","multiplier_amount":100,"minimum_installment_units":"1.125","maximum_installment_units":"9.875","multiplier_units":2,"minimum_installments":8,"maximum_installments":88}';
  END IF;
  s:=pg_temp.snapshot(kind,split_part(pg_temp.file(kind),E'\n',1)||E'\n'||array_to_string(c,'|'));
  PERFORM pg_temp.publish(s,(pg_temp.current(kind)->>'snapshot_id')::uuid);
  p:=pg_temp.products(s)->'rows'->0;
  FOR field_name IN SELECT jsonb_object_keys(expected) LOOP
    PERFORM pg_temp.ok(p->field_name=expected->field_name,'typed_column_'||kind||'_'||field_name);
  END LOOP;
 END LOOP;
 -- Other B06 slices cannot enter this publication path.
 FOREACH kind IN ARRAY ARRAY['SCH','NAV','SET'] LOOP
  s:=pg_temp.snapshot(kind,pg_temp.file('SIP'));
  PERFORM pg_temp.err(format('SELECT pg_temp.publish(%L)',s),'variant_invalid');
 END LOOP;
 PERFORM pg_temp.err($q$SELECT pg_temp.current('UNKNOWN')$q$,'variant_invalid');
 PERFORM pg_temp.err(format('SELECT pg_temp.products(%L,%L,1,501)',pg_temp.current('SIP')->>'snapshot_id','NSE_TEST_001'),'query_invalid');
 UPDATE nse_reference.connections SET enabled=false;
 PERFORM pg_temp.err($q$SELECT pg_temp.current('SIP')$q$,'connection_unavailable');
 PERFORM pg_temp.err(format('SELECT pg_temp.publish(%L,%L)',s,s2),'connection_unavailable');
 UPDATE nse_reference.connections SET enabled=true;
 UPDATE public.workspaces SET workspace_status='suspended' WHERE id='b0630000-0000-4000-8001-000000000001';
 PERFORM pg_temp.err($q$SELECT pg_temp.current('SIP')$q$,'workspace_unavailable');
 UPDATE public.workspaces SET workspace_status='active' WHERE id='b0630000-0000-4000-8001-000000000001';
 -- All service reads/writes are RPC-only; RLS has an exclusive zero-policy surface.
 FOREACH table_name IN ARRAY ARRAY['systematic_validations','sip_products','stp_products','swp_products','systematic_publications'] LOOP
  PERFORM pg_temp.ok((SELECT relrowsecurity FROM pg_class WHERE oid=('nse_reference.'||table_name)::regclass),'rls_'||table_name);
  PERFORM pg_temp.ok(NOT EXISTS(SELECT 1 FROM pg_policies WHERE schemaname='nse_reference' AND tablename=table_name),'no_policies_'||table_name);
  FOREACH kind IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
    PERFORM pg_temp.ok(NOT has_table_privilege(kind,'nse_reference.'||table_name,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'),'table_acl_'||kind||'_'||table_name);
  END LOOP;
  PERFORM pg_temp.err(format('DELETE FROM nse_reference.%I',table_name),'immutable');
  PERFORM pg_temp.err(format('UPDATE nse_reference.%I SET parser_version=parser_version',table_name),'immutable');
 END LOOP;
 FOR fn IN SELECT p.oid::regprocedure FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='nse_reference' AND (p.proname LIKE 'systematic_%' OR p.proname='validate_systematic') LOOP
   PERFORM pg_temp.ok(NOT has_function_privilege('service_role',fn,'EXECUTE') AND NOT has_function_privilege('authenticated',fn,'EXECUTE') AND NOT has_function_privilege('anon',fn,'EXECUTE'),'private_helper_acl');
 END LOOP;
 FOR fn IN SELECT p.oid::regprocedure FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public'
   AND p.proname IN ('validate_nse_systematic_snapshot','publish_nse_systematic_snapshot','get_nse_systematic_current','get_nse_systematic_products') LOOP
   PERFORM pg_temp.ok(has_function_privilege('service_role',fn,'EXECUTE') AND NOT has_function_privilege('authenticated',fn,'EXECUTE') AND NOT has_function_privilege('anon',fn,'EXECUTE'),'service_rpc_acl');
   PERFORM pg_temp.ok((SELECT prosecdef AND proconfig @> ARRAY['search_path=""'] FROM pg_proc WHERE oid=fn),'definer_empty_search_path');
   PERFORM pg_temp.ok(NOT EXISTS(SELECT 1 FROM pg_proc p,LATERAL aclexplode(COALESCE(p.proacl,acldefault('f',p.proowner))) a WHERE p.oid=fn AND a.grantee=0 AND a.privilege_type='EXECUTE'),'no_public_execute');
 END LOOP;
 PERFORM pg_temp.ok((SELECT count(*) FROM public.workspace_audit_logs WHERE action='nse.reference.systematic_publish')=(SELECT count(*) FROM nse_reference.systematic_publications),'one_audit_per_publication');
END $$;
-- An audit failure must roll back validation, rows and current publication together.
CREATE FUNCTION pg_temp.fail_publication_audit() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF NEW.action='nse.reference.systematic_publish' THEN RAISE EXCEPTION 'b063_injected_audit_failure'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER b063_fail_audit BEFORE INSERT ON public.workspace_audit_logs FOR EACH ROW EXECUTE FUNCTION pg_temp.fail_publication_audit();
DO $$ DECLARE prior uuid; candidate uuid; BEGIN
 prior:=(pg_temp.current('SIP')->>'snapshot_id')::uuid;
 candidate:=pg_temp.snapshot('SIP',pg_temp.file('SIP'));
 PERFORM pg_temp.err(format('SELECT pg_temp.publish(%L,%L)',candidate,prior),'b063_injected_audit_failure');
 PERFORM pg_temp.ok(NOT EXISTS(SELECT 1 FROM nse_reference.systematic_validations WHERE snapshot_id=candidate),'audit_failure_rolls_back_validation');
 PERFORM pg_temp.ok(NOT EXISTS(SELECT 1 FROM nse_reference.sip_products WHERE snapshot_id=candidate),'audit_failure_rolls_back_rows');
 PERFORM pg_temp.ok((pg_temp.current('SIP')->>'snapshot_id')::uuid=prior,'audit_failure_preserves_current');
END $$;
DROP TRIGGER b063_fail_audit ON public.workspace_audit_logs;
-- Actual API roles, including browser personas that have no product-master access.
SET LOCAL ROLE service_role;
DO $$ DECLARE s uuid; r jsonb; BEGIN
 r:=public.get_nse_systematic_current('b0630000-0000-4000-8001-000000000001','b0630000-0000-4000-8002-000000000001','SIP');
 s:=(r->>'snapshot_id')::uuid;
 PERFORM public.validate_nse_systematic_snapshot('b0630000-0000-4000-8001-000000000001',s);
 PERFORM public.get_nse_systematic_products('b0630000-0000-4000-8001-000000000001',s,'NSE_TEST_001');
 BEGIN PERFORM 1 FROM nse_reference.sip_products; RAISE EXCEPTION 'service_table_allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM public.get_nse_systematic_current('b0630000-0000-4000-8001-000000000002','b0630000-0000-4000-8002-000000000001','SIP'); RAISE EXCEPTION 'cross_workspace_allowed';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'nse_reference_connection_unavailable' THEN RAISE; END IF; END;
END $$;
RESET ROLE;
SET LOCAL ROLE authenticated;
DO $$ DECLARE persona text; BEGIN
 FOREACH persona IN ARRAY ARRAY['platform_admin','family_guest','inactive_member','operations','unrelated_advisor','cross_workspace'] LOOP
  PERFORM set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub','b0630000-0000-4000-8000-000000000002','app_metadata',jsonb_build_object('role',persona))::text,true);
  BEGIN PERFORM public.validate_nse_systematic_snapshot(NULL,NULL); RAISE EXCEPTION 'browser_validate_allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM public.publish_nse_systematic_snapshot(NULL,NULL,NULL); RAISE EXCEPTION 'browser_publish_allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM public.get_nse_systematic_current(NULL,NULL,'SIP'); RAISE EXCEPTION 'browser_current_allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM public.get_nse_systematic_products(NULL,NULL,'NSE_TEST_001'); RAISE EXCEPTION 'browser_products_allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM 1 FROM nse_reference.systematic_publications; RAISE EXCEPTION 'browser_table_allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 END LOOP;
END $$;
RESET ROLE;
SET LOCAL ROLE anon;
DO $$ BEGIN
 BEGIN PERFORM public.publish_nse_systematic_snapshot(NULL,NULL,NULL); RAISE EXCEPTION 'anon_publish_allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM public.get_nse_systematic_current(NULL,NULL,'SIP'); RAISE EXCEPTION 'anon_current_allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM 1 FROM nse_reference.systematic_validations; RAISE EXCEPTION 'anon_table_allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
-- Integration with B06.2: only its existing metadata-only event may now mutate.
-- Investor/fund/operation mutation guards above remain active.
DROP TRIGGER b063_no_mutation ON public.event_outbox;
CREATE FUNCTION pg_temp.queue_master(kind text,key uuid DEFAULT gen_random_uuid()) RETURNS uuid LANGUAGE sql AS $$
 SELECT (public.prepare_nse_master_download('b0630000-0000-4000-8001-000000000001',
  'b0630000-0000-4000-8002-000000000001',kind,key)->>'event_outbox_id')::uuid
$$;
CREATE FUNCTION pg_temp.capture_master(e uuid,t uuid,body text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE b bytea:=convert_to(body,'UTF8'); BEGIN
 PERFORM public.begin_nse_master_job_capture(e,t,gen_random_uuid(),'UAT','05418','https://nse.example.test');
 PERFORM public.append_nse_master_job_chunk(e,t,0,replace(encode(b,'base64'),E'\n',''),encode(extensions.digest(b,'sha256'),'hex'));
 PERFORM public.finish_nse_master_job_capture(e,t,'COMPLETE',200,'TEXT',octet_length(b),true,true,encode(extensions.digest(b,'sha256'),'hex'));
END $$;
CREATE FUNCTION pg_temp.fail_master_completion() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'b063_injected_completion_failure'; END $$;
DO $$ DECLARE kind text; e uuid; t uuid; key uuid; s uuid; prior uuid; r jsonb; c jsonb; body text; bad text;
 fn regprocedure; role_name text; rec record;
BEGIN
 PERFORM pg_temp.ok((SELECT array_agg(file_type::text ORDER BY file_type::text)=ARRAY['NAV','SCH','SET','SIP','STP','SWP'] FROM nse_reference.validators),'exact_shared_variant_registry');
 FOREACH kind IN ARRAY ARRAY['SIP','STP','SWP'] LOOP
  PERFORM pg_temp.ok((SELECT parser_version='NSE_WEB_'||kind||'_V1' AND function_name='validate_'||lower(kind)||'_v1'
   FROM nse_reference.validators WHERE file_type::text=kind),'registered_profile_'||kind);
  prior:=(pg_temp.current(kind)->>'snapshot_id')::uuid;
  key:=gen_random_uuid(); e:=pg_temp.queue_master(kind,key); t:=gen_random_uuid();
  PERFORM pg_temp.ok(pg_temp.queue_master(kind,key)=e,'shared_prepare_replay_'||kind);
  PERFORM pg_temp.ok((SELECT event_type='integration.nse.master_download_requested' AND entity_type='nse_reference_job' AND payload='{}'::jsonb
   FROM public.event_outbox WHERE id=e),'one_existing_event_contract_'||kind);
  PERFORM pg_temp.ok(EXISTS(SELECT 1 FROM public.list_dispatchable_outbox_events(ARRAY['integration.nse.master_download_requested']) WHERE event_outbox_id=e),'existing_dispatch_feed_'||kind);
  PERFORM pg_temp.err(format('SELECT public.prepare_nse_master_download(%L,%L,%L,%L)',
   'b0630000-0000-4000-8001-000000000002','b0630000-0000-4000-8002-000000000001',kind,key),'connection_unavailable');
  PERFORM pg_temp.err(format('SELECT pg_temp.queue_master(%L,%L)','SCH',key),'idempotency_conflict');
  c:=public.claim_nse_master_download(e,t);
  PERFORM pg_temp.ok(c->>'action'='CAPTURE' AND c->>'file_type'=kind,'sql_owned_variant_'||kind);
  PERFORM pg_temp.ok(public.claim_nse_master_download(e,gen_random_uuid())->>'action'='BUSY','shared_claim_fence_'||kind);
  PERFORM pg_temp.err(format('SELECT public.begin_nse_master_download(%L,%L,%L,%L,%L,%L,%L,gen_random_uuid())',
   c->>'workspace_id',c->>'connection_id','SCH',c->>'download_id','UAT','05418','https://nse.example.test'),'job_download_mismatch');
  PERFORM pg_temp.capture_master(e,t,pg_temp.file(kind));
  -- Recovery resumes SQL only, after the exact sealed capture, never another read.
  UPDATE public.event_outbox SET claim_expires_at=clock_timestamp()-interval '1 second' WHERE id=e;
  PERFORM pg_temp.err(format('SELECT public.finalize_nse_master_download(%L,%L)',e,t),'claim_not_owned');
  t:=gen_random_uuid();
  PERFORM pg_temp.ok(public.claim_nse_master_download(e,t)->>'action'='FINALIZE','sealed_capture_resume_'||kind);
  r:=public.finalize_nse_master_download(e,t); s:=(r->>'snapshot_id')::uuid;
  PERFORM pg_temp.ok(r->>'outcome'='STAGED_VALIDATED','shared_finalization_'||kind);
  PERFORM pg_temp.ok(public.finalize_nse_master_download(e,t)=r,'shared_finalize_replay_'||kind);
  PERFORM pg_temp.ok(public.claim_nse_master_download(e,gen_random_uuid())->>'action'='DONE','no_recapture_'||kind);
  PERFORM pg_temp.ok((pg_temp.current(kind)->>'snapshot_id')::uuid=prior,'worker_never_publishes_'||kind);
  PERFORM pg_temp.ok((SELECT v.row_count=1 AND v.rejected_rows=0 AND v.publication_gate='BLOCKED'
    AND v.validation_scope='STRUCTURE_ONLY_REFERENCE_ONLY' AND v.parser_version='NSE_WEB_'||kind||'_V1'
    AND v.source_sha256=typed.source_sha256 AND typed.file_type=v.file_type
   FROM nse_reference.validations v JOIN nse_reference.systematic_validations typed USING(snapshot_id)
   WHERE v.snapshot_id=s),'shared_and_typed_receipts_'||kind);
  PERFORM pg_temp.ok(nse_reference.validate_snapshot('b0630000-0000-4000-8001-000000000001',s)->>'status'='STAGED_VALIDATED','shared_validation_replay_'||kind);
  SELECT public.get_nse_master_download_job(workspace_id,id) INTO c FROM nse_reference.jobs WHERE event_id=e;
  PERFORM pg_temp.ok(c->>'publication_gate'='BLOCKED' AND c->>'validation_scope'='STRUCTURE_ONLY_REFERENCE_ONLY','summary_stays_blocked_'||kind);
  PERFORM pg_temp.ok(pg_temp.publish(s,prior)->>'authority'='REFERENCE_ONLY','explicit_reference_publication_'||kind);
  PERFORM pg_temp.ok(pg_temp.current(kind)->>'reason'='PRODUCT_SEMANTICS_UNCOMMISSIONED'
    AND pg_temp.products(s)->>'eligibility'='UNINTERPRETED','publication_not_eligibility_'||kind);
  prior:=s;
  -- Unknown header, cross-variant layout, malformed late row and exact duplicates:
  -- parser exceptions become durable rejections after rolling back partial rows.
  body:=pg_temp.file(kind);
  FOREACH bad IN ARRAY ARRAY[replace(body,'AMC CODE','UNKNOWN'),pg_temp.file(CASE WHEN kind='SIP' THEN 'STP' ELSE 'SIP' END),
    body||replace(split_part(body,E'\n',2),'100.25','bad')||E'\n',body||split_part(body,E'\n',2)||E'\n'] LOOP
   e:=pg_temp.queue_master(kind); t:=gen_random_uuid();
   PERFORM public.claim_nse_master_download(e,t);
   PERFORM pg_temp.capture_master(e,t,bad);
   r:=public.finalize_nse_master_download(e,t); s:=(r->>'snapshot_id')::uuid;
   PERFORM pg_temp.ok(r->>'outcome'='REJECTED','durable_parser_rejection_'||kind);
   PERFORM pg_temp.ok(public.finalize_nse_master_download(e,t)=r,'rejected_ack_replay_'||kind);
   PERFORM pg_temp.ok((SELECT row_count=0 AND rejected_rows=0 AND publication_gate='BLOCKED'
    AND category='nse_reference_systematic_layout_invalid' FROM nse_reference.validations WHERE snapshot_id=s),'zero_accepted_rejection_'||kind);
   PERFORM pg_temp.ok(NOT EXISTS(SELECT 1 FROM nse_reference.systematic_validations WHERE snapshot_id=s)
    AND NOT EXISTS(SELECT 1 FROM nse_reference.sip_products WHERE snapshot_id=s)
    AND NOT EXISTS(SELECT 1 FROM nse_reference.stp_products WHERE snapshot_id=s)
    AND NOT EXISTS(SELECT 1 FROM nse_reference.swp_products WHERE snapshot_id=s),'no_partial_typed_data_'||kind);
   PERFORM pg_temp.err(format('SELECT pg_temp.publish(%L,%L)',s,prior),'nse_systematic_');
   PERFORM pg_temp.ok((pg_temp.current(kind)->>'snapshot_id')::uuid=prior,'rejection_preserves_current_'||kind);
  END LOOP;
  -- Infrastructure errors must propagate; no false rejection and no half completion.
  e:=pg_temp.queue_master(kind); t:=gen_random_uuid();
  c:=public.claim_nse_master_download(e,t);
  PERFORM pg_temp.capture_master(e,t,body);
  CREATE TRIGGER b063_fail_completion BEFORE INSERT ON nse_reference.completions FOR EACH ROW EXECUTE FUNCTION pg_temp.fail_master_completion();
  PERFORM pg_temp.err(format('SELECT public.finalize_nse_master_download(%L,%L)',e,t),'b063_injected_completion_failure');
  PERFORM pg_temp.ok(NOT EXISTS(SELECT 1 FROM nse_reference.snapshots WHERE download_id=(c->>'download_id')::uuid)
    AND NOT EXISTS(SELECT 1 FROM nse_reference.completions done JOIN nse_reference.jobs j ON j.id=done.id WHERE j.event_id=e),'completion_failure_rolls_back_staging_'||kind);
  DROP TRIGGER b063_fail_completion ON nse_reference.completions;
  r:=public.finalize_nse_master_download(e,t);
  PERFORM pg_temp.ok(r->>'outcome'='STAGED_VALIDATED','same_capture_recovers_'||kind);
  PERFORM pg_temp.ok((pg_temp.current(kind)->>'snapshot_id')::uuid=prior,'recovery_never_publishes_'||kind);
  -- A private variant entry point cannot process a different owned file type.
  PERFORM pg_temp.err(format('SELECT nse_reference.validate_%s_v1(%L)',CASE WHEN kind='SIP' THEN 'stp' ELSE 'sip' END,r->>'snapshot_id'),'variant_invalid');
 END LOOP;
 FOR fn IN SELECT p.oid::regprocedure FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='nse_reference' AND p.proname IN ('systematic_runtime_validation','validate_sip_v1','validate_stp_v1','validate_swp_v1') LOOP
  PERFORM pg_temp.ok((SELECT prosecdef AND proconfig @> ARRAY['search_path=""'] FROM pg_proc WHERE oid=fn),'plugin_definer_search_path');
  FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
   PERFORM pg_temp.ok(NOT has_function_privilege(role_name,fn,'EXECUTE'),'plugin_private_'||role_name);
  END LOOP;
  PERFORM pg_temp.ok(NOT EXISTS(SELECT 1 FROM pg_proc p,LATERAL aclexplode(COALESCE(p.proacl,acldefault('f',p.proowner))) a
   WHERE p.oid=fn AND a.grantee=0 AND a.privilege_type='EXECUTE'),'plugin_no_public_execute');
 END LOOP;
 PERFORM pg_temp.ok(NOT EXISTS(SELECT 1 FROM nse_reference.sch_rows),'no_sch_projection');
 PERFORM pg_temp.ok((SELECT count(*) FROM public.workspace_audit_logs WHERE action='nse.reference.validation')=
  (SELECT count(*) FROM nse_reference.validations),'one_shared_validation_audit');
END $$;
-- Exercise the entire shared RPC path under the actual production API role.
SET LOCAL ROLE service_role;
DO $$ DECLARE kind text; e uuid; t uuid; r jsonb; BEGIN
 FOREACH kind IN ARRAY ARRAY['SIP','STP','SWP'] LOOP
  e:=pg_temp.queue_master(kind); t:=gen_random_uuid();
  PERFORM public.claim_nse_master_download(e,t);
  PERFORM pg_temp.capture_master(e,t,pg_temp.file(kind));
  r:=public.finalize_nse_master_download(e,t);
  IF r->>'outcome'<>'STAGED_VALIDATED' THEN RAISE EXCEPTION 'b063_service_runtime_failed'; END IF;
  BEGIN PERFORM nse_reference.validate_sip_v1((r->>'snapshot_id')::uuid); RAISE EXCEPTION 'b063_private_plugin_allowed';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 END LOOP;
END $$;
RESET ROLE;

SELECT count(*) AS b063_assertions FROM b063_assertions;
ROLLBACK;
