BEGIN;
DO $$
DECLARE r jsonb; result jsonb; e jsonb:='{"response_status":"S","error_remark":"No record(s) found.","report_data_total":"0","report_data":[]}'; bad jsonb;
BEGIN
 FOR r IN SELECT value FROM jsonb_array_elements(public.nse_response_diagnostic_policy_v1()->'rules') LOOP
  result:=public.match_nse_response_diagnostic(r->>'api',r->>'native_status',r->>'diagnostic',0,'[]');
  IF result->>'outcome' IS DISTINCT FROM r->>'outcome' OR result->>'category' IS DISTINCT FROM r->>'category' OR result->>'retry'<>'false' THEN RAISE EXCEPTION 'diagnostic_rule_mismatch'; END IF;
  IF public.match_nse_response_diagnostic(r->>'api',r->>'native_status',(r->>'diagnostic')||' ',0,'[]') IS NOT NULL
    OR public.match_nse_response_diagnostic('NSE_STP_REG_REPORT',r->>'native_status',r->>'diagnostic',0,'[]') IS NOT NULL
    OR public.match_nse_response_diagnostic(r->>'api',r->>'native_status',r->>'diagnostic',1,'[{}]') IS NOT NULL
    OR public.match_nse_response_diagnostic(r->>'api',r->>'native_status',r->>'diagnostic',0,'""') IS NOT NULL THEN RAISE EXCEPTION 'diagnostic_policy_broadened'; END IF;
 END LOOP;
 result:=public.inspect_nse_client_readiness_response('CLIENT_KYC_REPORT',e::text,'{"pan_no":"AAAAA0000A"}','{"client_code":"SYNTHETIC1","pan":"AAAAA0000A"}');
 IF result->>'success'<>'true' OR result->>'record_count'<>'0' OR result->>'category'<>'client_readiness_report_received' OR result::text LIKE '%No record%' THEN RAISE EXCEPTION 'kyc_live_regression'; END IF;
 FOREACH bad IN ARRAY ARRAY[e||'{"error_remark":"No record(s) found"}',e||'{"error_remark":"Success"}',e||'{"error_remark":null}',e||'{"response_status":"F"}',e||'{"report_data_total":1}',e||'{"report_data":[{}]}',e||'{"report_data":""}'] LOOP
  IF (public.inspect_nse_client_readiness_response('CLIENT_KYC_REPORT',bad::text,'{"pan_no":"AAAAA0000A"}','{"client_code":"SYNTHETIC1","pan":"AAAAA0000A"}')->>'success')::bool THEN RAISE EXCEPTION 'kyc_diagnostic_overbroad'; END IF;
 END LOOP;
 IF has_function_privilege('authenticated','public.match_nse_response_diagnostic(text,text,text,numeric,jsonb)','EXECUTE') OR has_function_privilege('service_role','public.nse_response_diagnostic_policy_v1()','EXECUTE') THEN RAISE EXCEPTION 'diagnostic_policy_acl'; END IF;
END $$;
ROLLBACK;
