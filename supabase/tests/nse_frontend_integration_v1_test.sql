-- Synthetic application-boundary tests; no transport or hosted connection.
\set ON_ERROR_STOP on
BEGIN;
SELECT 1 FROM vault.create_secret(repeat('p',40),'pan_encryption_key','synthetic rollback-only');
SELECT 1 FROM vault.create_secret(repeat('e',40),'integration_payload_encryption_key_v1','synthetic rollback-only');
INSERT INTO auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
SELECT ('aa010000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'authenticated','authenticated',
 'nse-app-'||n||'@moneybowl.invalid','{}','{}',now(),now() FROM generate_series(1,9) n;
UPDATE public.profiles SET role=CASE right(user_id::text,1) WHEN '1' THEN 'admin' WHEN '2' THEN 'advisor' WHEN '3' THEN 'advisor'
 WHEN '6' THEN 'operations' WHEN '7' THEN 'platform_admin' WHEN '8' THEN 'advisor' ELSE 'investor' END
 WHERE user_id::text LIKE 'aa010000-%';
UPDATE public.user_accounts SET account_state='advisor' WHERE user_id::text LIKE 'aa010000-%' AND right(user_id::text,1) NOT IN ('4','5','9');
CREATE FUNCTION pg_temp.profile(n integer) RETURNS uuid LANGUAGE sql AS $$ SELECT id FROM public.profiles WHERE user_id=('aa010000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid $$;
INSERT INTO public.workspaces(id,name,slug,owner_profile_id) VALUES
 ('aa020000-0000-4000-8000-000000000001','Application one','nse-app-one',pg_temp.profile(1)),
 ('aa020000-0000-4000-8000-000000000002','Application two','nse-app-two',pg_temp.profile(3));
INSERT INTO public.workspace_memberships(id,workspace_id,profile_id,role,status)
SELECT ('aa030000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
 CASE WHEN n=5 THEN 'aa020000-0000-4000-8000-000000000002'::uuid ELSE 'aa020000-0000-4000-8000-000000000001'::uuid END,
 pg_temp.profile(n),CASE WHEN n=1 THEN 'admin' WHEN n IN (2,3,8) THEN 'advisor' WHEN n=6 THEN 'operations' ELSE 'investor' END,
 CASE WHEN n=8 THEN 'inactive' ELSE 'active' END FROM generate_series(1,9) n;
INSERT INTO public.advisor_investor_assignments(advisor_id,investor_id) VALUES(pg_temp.profile(2),pg_temp.profile(4));
INSERT INTO public.integration_accounts(id,workspace_id,investor_profile_id,integration_key,integration_environment,external_account_id,state)
SELECT ('aa040000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
 CASE WHEN n=4 THEN 'aa020000-0000-4000-8000-000000000001'::uuid ELSE 'aa020000-0000-4000-8000-000000000002'::uuid END,
 pg_temp.profile(n),'NSE_INVEST','UAT','PRIVATE_UCC_'||n,'REGISTERED' FROM generate_series(4,5) n;
INSERT INTO public.profile_pan_records(id,profile_id,pan_ciphertext,pan_lookup_hmac,masked_pan,source,source_system,status,verified_at)
SELECT ('aa050000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,pg_temp.profile(n),
 extensions.pgp_sym_encrypt('AAAAA0000A',public.pan_encryption_key(),'cipher-algo=aes256, compress-algo=0'),
 extensions.digest('nse-app-'||n,'sha256'),'******000A','INVESTOR','API','VERIFIED',now() FROM generate_series(4,5) n;
UPDATE public.profiles SET canonical_pan_record_id=('aa050000-0000-4000-8000-'||right(user_id::text,12))::uuid
 WHERE user_id::text LIKE 'aa010000-%' AND right(user_id::text,1) IN ('4','5');
CREATE FUNCTION pg_temp.assert_true(ok boolean,label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'assertion_failed:%',label; END IF; END $$;
CREATE FUNCTION pg_temp.identity(n integer) RETURNS void LANGUAGE plpgsql AS $$
BEGIN PERFORM set_config('request.jwt.claim.sub','aa010000-0000-4000-8000-'||lpad(n::text,12,'0'),true);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub','aa010000-0000-4000-8000-'||lpad(n::text,12,'0'),'role','authenticated')::text,true); END $$;

-- Catalog assertions are run as owner, behavior assertions under API roles.
DO $$ DECLARE fn regprocedure; BEGIN
 FOR fn IN SELECT p.oid::regprocedure FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname IN ('list_nse_read_targets_v1','get_nse_read_context_v1','list_nse_settlement_candidates_v1',
 'submit_nse_read_v1','list_nse_read_operations_v1','get_nse_read_operation_v1') LOOP
  PERFORM pg_temp.assert_true(has_function_privilege('authenticated',fn,'EXECUTE') AND NOT has_function_privilege('anon',fn,'EXECUTE')
    AND NOT has_function_privilege('service_role',fn,'EXECUTE'),'facade_exact_grants');
  PERFORM pg_temp.assert_true((SELECT prosecdef AND proconfig @> ARRAY['search_path=""'] FROM pg_proc WHERE oid=fn),'empty_definer_path');
 END LOOP;
 PERFORM pg_temp.assert_true(NOT has_schema_privilege('authenticated','nse_app','USAGE'),'private_schema');
 PERFORM pg_temp.assert_true(NOT has_table_privilege('authenticated','public.integration_operations','SELECT'),'operations_private');
 PERFORM pg_temp.assert_true(NOT has_table_privilege('authenticated','public.integration_api_interactions','SELECT'),'evidence_private');
 PERFORM pg_temp.assert_true(NOT has_function_privilege('authenticated','public.prepare_nse_order_status(uuid,uuid,jsonb,uuid,uuid,integer[],text)','EXECUTE'),'old_prepare_private');
END $$;
SET LOCAL ROLE anon;
DO $$ BEGIN
 BEGIN PERFORM public.list_nse_read_targets_v1(); RAISE EXCEPTION 'anon_allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT pg_temp.identity(2);
SELECT pg_temp.assert_true(jsonb_array_length(public.list_nse_read_targets_v1()->'data'->'items')=1,'assigned_target_only');
SELECT pg_temp.assert_true(public.get_nse_read_context_v1('aa030000-0000-4000-8000-000000000005')->'error'->>'code'='NOT_AUTHORIZED','cross_workspace');
SELECT pg_temp.assert_true(public.submit_nse_read_v1('aa030000-0000-4000-8000-000000000004',gen_random_uuid(),
 '{"kind":"read_order_status","options":{"from":"2026-10-01","to":"2026-10-02"}}')->'error'->>'code'='FEATURE_DISABLED','disabled_default');
DO $$ DECLARE n integer; BEGIN
 FOREACH n IN ARRAY ARRAY[3,4,5,6,7,8,9] LOOP
  PERFORM pg_temp.identity(n);
  PERFORM pg_temp.assert_true(public.get_nse_read_context_v1('aa030000-0000-4000-8000-000000000004')->'error'->>'code'='NOT_AUTHORIZED','denied_persona_'||n);
 END LOOP;
END $$;
SELECT pg_temp.identity(1);
SELECT pg_temp.assert_true(public.get_nse_read_context_v1('aa030000-0000-4000-8000-000000000004')->'data'->>'account_state'='REGISTERED','workspace_owner');
RESET ROLE;
-- Current database identity and membership, not a previously issued JWT, govern access.
UPDATE auth.users SET banned_until=now()+interval '1 hour' WHERE id='aa010000-0000-4000-8000-000000000002';
SET LOCAL ROLE authenticated;
SELECT pg_temp.identity(2);
SELECT pg_temp.assert_true(public.list_nse_read_targets_v1()->'error'->>'code'='NOT_AUTHORIZED','banned_actor');
RESET ROLE;
UPDATE auth.users SET banned_until=NULL,deleted_at=now() WHERE id='aa010000-0000-4000-8000-000000000002';
SET LOCAL ROLE authenticated;
SELECT pg_temp.assert_true(public.list_nse_read_targets_v1()->'error'->>'code'='NOT_AUTHORIZED','deleted_actor');
RESET ROLE;
UPDATE auth.users SET deleted_at=NULL,is_anonymous=true WHERE id='aa010000-0000-4000-8000-000000000002';
SET LOCAL ROLE authenticated;
SELECT pg_temp.assert_true(public.list_nse_read_targets_v1()->'error'->>'code'='NOT_AUTHORIZED','anonymous_actor');
RESET ROLE;
UPDATE auth.users SET is_anonymous=false WHERE id='aa010000-0000-4000-8000-000000000002';
UPDATE public.workspace_memberships SET ended_at=now() WHERE id='aa030000-0000-4000-8000-000000000002';
SET LOCAL ROLE authenticated;
SELECT pg_temp.assert_true(public.get_nse_read_context_v1('aa030000-0000-4000-8000-000000000004')->'error'->>'code'='NOT_AUTHORIZED','ended_advisor_membership');
RESET ROLE;
UPDATE public.workspace_memberships SET ended_at=NULL WHERE id='aa030000-0000-4000-8000-000000000002';
INSERT INTO nse_app.dev_access(workspace_id,enabled,verified_release_sha,verified_at)
VALUES('aa020000-0000-4000-8000-000000000001',true,repeat('a',40),now());

-- Each account command is exercised under authenticated, then rolled back so
-- test isolation does not bypass immutable receipts or rate limits.
SET LOCAL ROLE authenticated;
SELECT pg_temp.identity(2);
DO $$ DECLARE cap jsonb; opts jsonb; result jsonb; cmd jsonb; count integer:=0; BEGIN
 FOR cap IN SELECT value FROM jsonb_array_elements(public.get_nse_read_context_v1('aa030000-0000-4000-8000-000000000004')->'data'->'capabilities') LOOP
  IF cap->>'options_type'='settlement' THEN
   PERFORM pg_temp.assert_true(cap->>'reason'='POSITIVE_OWNED_ORDER_EVIDENCE_REQUIRED','b03_blocked'); CONTINUE;
  END IF;
  opts:=CASE cap->>'options_type' WHEN 'date' THEN '{"date":"2026-10-01"}'::jsonb WHEN 'dates' THEN '{"from":"2026-10-01","to":"2026-10-02"}'::jsonb ELSE '{}'::jsonb END;
  cmd:=jsonb_build_object('kind',cap->>'kind','options',opts);
  BEGIN
   result:=public.submit_nse_read_v1('aa030000-0000-4000-8000-000000000004',gen_random_uuid(),cmd);
   PERFORM pg_temp.assert_true(result->'data'->>'state'='QUEUED','prepare_'||(cap->>'kind')||':'||result::text);
   RAISE SQLSTATE 'Z0001';
  EXCEPTION WHEN SQLSTATE 'Z0001' THEN NULL; END;
  count:=count+1;
 END LOOP;
 PERFORM pg_temp.assert_true(count=21,'all_account_reads');
END $$;
DO $$ DECLARE cmd jsonb; BEGIN
 FOREACH cmd IN ARRAY ARRAY[
  '{"kind":"prepare_nse_ucc_registration","options":{}}'::jsonb,
  '{"kind":"read_order_status","options":{"from":"2026-10-01","to":"2026-10-02","client_code":"PRIVATE_UCC_5"}}'::jsonb,
  '{"kind":"read_order_status","options":{"from":"2026-02-30","to":"2026-03-01"}}'::jsonb,
  '{"kind":"read_order_status","options":{"from":"2026-10-01","to":"2026-10-08"}}'::jsonb,
  '{"kind":"read_fund_age","options":{"date":"2026-10-01","amc_code":"guessed"}}'::jsonb,
  '{"kind":"read_sip_reg_report","options":{"from":"2026-10-01"}}'::jsonb,
  '{"kind":"read_elog_report","options":{},"workspace_id":"forged"}'::jsonb
 ] LOOP
  PERFORM pg_temp.assert_true(public.submit_nse_read_v1('aa030000-0000-4000-8000-000000000004',gen_random_uuid(),cmd)->'error'->>'code'='INVALID_COMMAND','closed_command');
 END LOOP;
END $$;
-- Ten accepted, distinct read kinds consume the actor budget, including when
-- the caller fabricates a fresh UUID for every click. Roll the test back.
DO $$ DECLARE cap jsonb; opts jsonb; result jsonb; n integer:=0; BEGIN
 BEGIN
  FOR cap IN SELECT value FROM jsonb_array_elements(public.get_nse_read_context_v1('aa030000-0000-4000-8000-000000000004')->'data'->'capabilities') LOOP
   IF cap->>'options_type'='settlement' THEN CONTINUE; END IF;
   opts:=CASE cap->>'options_type' WHEN 'date' THEN '{"date":"2026-10-01"}'::jsonb WHEN 'dates' THEN '{"from":"2026-10-01","to":"2026-10-02"}'::jsonb ELSE '{}'::jsonb END;
   result:=public.submit_nse_read_v1('aa030000-0000-4000-8000-000000000004',gen_random_uuid(),jsonb_build_object('kind',cap->>'kind','options',opts));
   n:=n+1;
   IF n<=10 THEN PERFORM pg_temp.assert_true(result->'data'->>'acceptance'='ACCEPTED','rate_budget_accept');
   ELSE PERFORM pg_temp.assert_true(result->'error'->>'code'='RATE_LIMITED','actor_rate_limit'); EXIT; END IF;
  END LOOP;
  PERFORM pg_temp.assert_true(n=11,'rate_exercised');
  RAISE SQLSTATE 'Z0001';
 EXCEPTION WHEN SQLSTATE 'Z0001' THEN NULL; END;
END $$;
SELECT pg_temp.assert_true(public.submit_nse_read_v1('aa030000-0000-4000-8000-000000000004',gen_random_uuid(),
 '{"kind":"read_allotment_statement","options":{"from":"2026-10-01","to":"2026-10-02","source_operation_id":"aa990000-0000-4000-8000-000000000001","row_indices":[0]}}')->'error'->>'code'='BLOCKED_PREREQUISITE','b03_no_event');
RESET ROLE;
CREATE FUNCTION pg_temp.fail_audit() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
 IF NEW.event_type='nse.read_accepted' THEN RAISE EXCEPTION 'PRIVATE_AUDIT_DIAGNOSTIC'; END IF; RETURN NEW;
END $$;
CREATE TRIGGER nse_app_fail_audit BEFORE INSERT ON public.workspace_audit_logs FOR EACH ROW EXECUTE FUNCTION pg_temp.fail_audit();
SET LOCAL ROLE authenticated;
SELECT pg_temp.assert_true(public.submit_nse_read_v1('aa030000-0000-4000-8000-000000000004',gen_random_uuid(),
 '{"kind":"read_elog_report","options":{}}')->'error'->>'code'='TEMPORARILY_UNAVAILABLE','audit_error_sanitized');
RESET ROLE;
DROP TRIGGER nse_app_fail_audit ON public.workspace_audit_logs;
SELECT pg_temp.assert_true((SELECT count(*) FROM nse_app.submission_receipts)=0,'audit_failure_receipt_rollback');
SELECT pg_temp.assert_true((SELECT count(*) FROM public.integration_operations WHERE workspace_id='aa020000-0000-4000-8000-000000000001')=0,'audit_failure_operation_rollback');
SET LOCAL ROLE authenticated;
SELECT set_config('test.nse_response',public.submit_nse_read_v1('aa030000-0000-4000-8000-000000000004','aa060000-0000-4000-8000-000000000001',
 '{"kind":"read_order_status","options":{"from":"2026-10-01","to":"2026-10-02"}}')::text,true);
SELECT pg_temp.assert_true(current_setting('test.nse_response')::jsonb->'data'->>'acceptance'='ACCEPTED','accepted');
SELECT pg_temp.assert_true(public.submit_nse_read_v1('aa030000-0000-4000-8000-000000000004','aa060000-0000-4000-8000-000000000001',
 '{"kind":"read_order_status","options":{"from":"2026-10-01","to":"2026-10-02"}}')->'data'->>'acceptance'='REPLAYED','replayed');
SELECT pg_temp.assert_true(public.submit_nse_read_v1('aa030000-0000-4000-8000-000000000004','aa060000-0000-4000-8000-000000000001',
 '{"kind":"read_order_status","options":{"from":"2026-09-30","to":"2026-10-02"}}')->'error'->>'code'='REQUEST_CONFLICT','request_conflict');
SELECT pg_temp.assert_true(public.submit_nse_read_v1('aa030000-0000-4000-8000-000000000004',gen_random_uuid(),
 '{"kind":"read_order_status","options":{"from":"2026-10-01","to":"2026-10-02"}}')->'error'->>'code'='OPERATION_IN_PROGRESS','double_click_new_uuid');
SELECT pg_temp.assert_true(public.get_nse_read_operation_v1(NULL,'aa060000-0000-4000-8000-000000000001')->'data'->>'display_status'='QUEUED','lost_response_lookup');
SELECT pg_temp.assert_true(jsonb_array_length(public.list_nse_read_operations_v1('aa030000-0000-4000-8000-000000000004')->'data'->'items')=1,'history');
RESET ROLE;
SELECT pg_temp.assert_true((SELECT count(*) FROM nse_app.submission_receipts)=1,'one_receipt');
SELECT pg_temp.assert_true((SELECT count(*) FROM public.workspace_audit_logs WHERE event_type='nse.read_accepted')=1,'one_audit');

-- Complete the real ORDER_STATUS persistence lifecycle with synthetic bytes.
DO $$ DECLARE op uuid; event uuid; claim record; source jsonb; req public.integration_api_interactions; raw text; observation jsonb; BEGIN
 op:=(current_setting('test.nse_response')::jsonb->'data'->>'operation_id')::uuid;
 SELECT id INTO event FROM public.event_outbox WHERE entity_id=op;
 SELECT * INTO claim FROM public.claim_nse_order_status_event(event);
 source:=public.get_nse_order_status_source(op);
 SELECT * INTO req FROM public.start_nse_order_status(event,claim.claim_token,gen_random_uuid(),(source->'request')::text,
   '{"content_type":"application/json","accept":"application/json"}',now());
 raw:='{"response_status":"S","report_data_total":1,"report_data":[{"client_code":"PRIVATE_UCC_4","order_status":"VALID","order_id":"1001","member_unique_id":"PRIVATE_MEMBER","member_id":"123","scheme_code":"PRIVATE_SCHEME","isin":"PRIVATE_ISIN","transaction_type":"P","order_date":"01/10/2026","settlement_id":"123","settlement_type":"L1","folio_no":"PRIVATE_FOLIO","order_type":"NRM","order_sub_type":"NRM"}],"error_remark":"PRIVATE_DIAGNOSTIC"}';
 observation:=public.inspect_nse_order_status_response(raw,source->'request');
 PERFORM public.finish_nse_order_status(event,claim.claim_token,req.call_id,raw,'application/json','{}',200,'S',observation->>'category','SUCCESS',NULL,false,false,now(),1,3);
END $$;
SET LOCAL ROLE authenticated;
SELECT pg_temp.identity(2);
DO $$ DECLARE op uuid; result jsonb; candidates jsonb; BEGIN
 op:=(current_setting('test.nse_response')::jsonb->'data'->>'operation_id')::uuid;
 result:=public.get_nse_read_operation_v1(op);
 PERFORM pg_temp.assert_true(result->'data'->>'display_status'='SUCCESS' AND result->'data'->'summary'->>'record_count'='1','safe_success_summary');
 PERFORM pg_temp.assert_true(result->'data'->>'target_ref'='aa030000-0000-4000-8000-000000000004','operation_target_correlation');
 PERFORM pg_temp.assert_true(result::text NOT LIKE '%PRIVATE_%' AND result::text NOT LIKE '%interaction_id%' AND result::text NOT LIKE '%cipher%','no_provider_leak');
 candidates:=public.list_nse_settlement_candidates_v1('aa030000-0000-4000-8000-000000000004','read_allotment_statement',op);
 PERFORM pg_temp.assert_true(candidates->'data'->'items'->0->>'eligible'='true' AND candidates::text NOT LIKE '%PRIVATE_%','owned_b03_candidate');
 PERFORM pg_temp.assert_true(public.list_nse_settlement_candidates_v1('aa030000-0000-4000-8000-000000000004','read_redemption_statement',op)->'data'->'items'->0->>'eligible'='false','wrong_side');
 result:=public.submit_nse_read_v1('aa030000-0000-4000-8000-000000000004',gen_random_uuid(),jsonb_build_object('kind','read_allotment_statement',
   'options',jsonb_build_object('from','2026-10-01','to','2026-10-02','source_operation_id',op,'row_indices',jsonb_build_array(0))));
 PERFORM pg_temp.assert_true(result->'data'->>'state'='QUEUED','owned_b03_preparation');
 PERFORM pg_temp.identity(3);
 PERFORM pg_temp.assert_true(public.get_nse_read_operation_v1(op)->'error'->>'code'='TARGET_UNAVAILABLE','operation_idor');
 PERFORM pg_temp.assert_true(public.get_nse_read_operation_v1(NULL,'aa060000-0000-4000-8000-000000000001')->'error'->>'code'='TARGET_UNAVAILABLE','receipt_actor_bound');
END $$;
RESET ROLE;
-- Presentation classification must not equate stored BUSINESS_FAILED with a
-- characterized rejection or interpret a pending backend retry as terminal.
DO $$ DECLARE item record; op uuid; response jsonb; BEGIN
 FOR item IN SELECT * FROM (VALUES
   ('SIP_XSIP_REPORTS','SIP_REG_REPORT','BUSINESS_FAILED',false,'sip_xsip_reports_unknown_diagnostic','FAILED_CLOSED'),
   ('ORDER_FUNDING','FUND_AGE','BUSINESS_FAILED',false,'order_funding_amc_code_invalid','BUSINESS_FAILED'),
   ('SIP_XSIP_REPORTS','SIP_REG_REPORT','SUBMISSION_FAILED',true,'PRIVATE_RETRY_DIAGNOSTIC','RETRY_PENDING'),
   ('SIP_XSIP_REPORTS','SIP_REG_REPORT','SUCCESS',false,'sip_xsip_reports_report_received','RESULT_UNAVAILABLE')
 ) AS examples(family,api,state,retry,category,display) LOOP
  INSERT INTO public.integration_operations(workspace_id,integration_account_id,integration_key,integration_environment,category,safety_class,operation_type,api_key,contract_version,state,retry_allowed,business_remark_category)
  VALUES('aa020000-0000-4000-8000-000000000001','aa040000-0000-4000-8000-000000000004','NSE_INVEST','UAT','SYSTEMATIC','READ_ONLY',item.family,item.api,'NNF_1.9.7',item.state,item.retry,item.category)
  RETURNING id INTO op;
  PERFORM pg_temp.identity(2);
  response:=public.get_nse_read_operation_v1(op);
  PERFORM pg_temp.assert_true(response->'data'->>'display_status'=item.display,'presentation_'||item.display);
  PERFORM pg_temp.assert_true((response->'data'->>'terminal')::boolean=NOT item.retry,'terminal_classification');
  PERFORM pg_temp.assert_true(response::text NOT LIKE '%PRIVATE_%' AND NOT (response->'data'->'summary' ? 'record_count'),'no_failure_counts_or_diagnostics');
 END LOOP;
 BEGIN UPDATE nse_app.submission_receipts SET command='{}'; RAISE EXCEPTION 'receipt_changed';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM='receipt_changed' THEN RAISE; END IF; END;
END $$;
UPDATE public.advisor_investor_assignments SET status='ended',ended_at=now() WHERE advisor_id=pg_temp.profile(2);
SET LOCAL ROLE authenticated;
SELECT pg_temp.identity(2);
SELECT pg_temp.assert_true(public.get_nse_read_context_v1('aa030000-0000-4000-8000-000000000004')->'error'->>'code'='NOT_AUTHORIZED','revoked_assignment');
-- Changing editable metadata/profile role does not manufacture a membership or advisor account.
SELECT pg_temp.identity(9);
DO $$ BEGIN
 BEGIN UPDATE public.profiles SET role='advisor' WHERE user_id=auth.uid();
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
SELECT pg_temp.assert_true(public.get_nse_read_context_v1('aa030000-0000-4000-8000-000000000004')->'error'->>'code'='NOT_AUTHORIZED','self_role_is_not_authority');
DO $$ BEGIN
 BEGIN INSERT INTO public.workspace_memberships(workspace_id,profile_id,role) VALUES('aa020000-0000-4000-8000-000000000001',public.current_user_profile_id(),'admin');
 RAISE EXCEPTION 'self_membership_allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
SELECT pg_temp.identity(3);
DO $$ BEGIN
 BEGIN INSERT INTO public.advisor_investor_assignments(advisor_id,investor_id)
 VALUES(public.current_user_profile_id(),(SELECT id FROM public.profiles WHERE user_id='aa010000-0000-4000-8000-000000000004'));
 RAISE EXCEPTION 'self_assignment_allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
ROLLBACK;
