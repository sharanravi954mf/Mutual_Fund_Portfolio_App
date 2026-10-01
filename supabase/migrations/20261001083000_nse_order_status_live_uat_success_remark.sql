-- NSE UAT can return response_status=S with a non-empty diagnostic error_remark.
-- Keep the diagnostic only in encrypted RESULT evidence; it must not override a structurally valid successful read.
BEGIN;

CREATE OR REPLACE FUNCTION public.inspect_nse_order_status_response(p_payload pg_catalog.text, p_request pg_catalog.jsonb)
RETURNS pg_catalog.jsonb LANGUAGE plpgsql IMMUTABLE SET search_path = '' AS $$
DECLARE v_body pg_catalog.jsonb; v_row pg_catalog.jsonb; v_total pg_catalog.numeric; v_valid pg_catalog.int4 := 0; v_invalid pg_catalog.int4 := 0; v_other pg_catalog.int4 := 0;
  v_observation pg_catalog.jsonb := '{"native_status":null,"category":"order_status_response_invalid","success":false,"record_count":0,"valid_count":0,"invalid_count":0,"other_count":0}';
BEGIN
  BEGIN v_body := p_payload::pg_catalog.jsonb; EXCEPTION WHEN invalid_text_representation OR untranslatable_character OR numeric_value_out_of_range THEN RETURN v_observation; END;
  IF pg_catalog.jsonb_typeof(v_body) IS DISTINCT FROM 'object' THEN RETURN v_observation; END IF;
  IF v_body->>'response_status' IN ('S','F') THEN
    v_observation := v_observation || pg_catalog.jsonb_build_object('native_status',v_body->>'response_status');
  END IF;
  IF pg_catalog.jsonb_typeof(v_body->'report_data_total') NOT IN ('string','number')
    OR v_body->'report_data_total' IS NULL
    OR (pg_catalog.jsonb_typeof(v_body->'report_data_total') = 'string' AND v_body->>'report_data_total' !~ '^[0-9]+$')
    OR pg_catalog.jsonb_typeof(v_body->'error_remark') IS DISTINCT FROM 'string' THEN RETURN v_observation; END IF;
  -- Bound conversion even when a malformed provider count contains megabytes of digits.
  IF pg_catalog.jsonb_typeof(v_body->'report_data_total') = 'string'
    AND pg_catalog.length(pg_catalog.ltrim(v_body->>'report_data_total','0')) > 16 THEN RETURN v_observation; END IF;
  v_total := COALESCE(NULLIF(pg_catalog.ltrim(v_body->>'report_data_total','0'),''),'0')::pg_catalog.numeric;
  IF v_total < 0 OR v_total <> pg_catalog.trunc(v_total) OR v_total > 9007199254740991 THEN RETURN v_observation; END IF;
  IF v_body->>'response_status' = 'F' THEN
    IF v_body->'report_data' = '""'::pg_catalog.jsonb AND v_total = 0 THEN
      v_observation := v_observation || '{"category":"order_status_vendor_rejected"}'::pg_catalog.jsonb;
    END IF;
    RETURN v_observation;
  END IF;
  IF v_body->>'response_status' IS DISTINCT FROM 'S'
    OR pg_catalog.jsonb_typeof(v_body->'report_data') IS DISTINCT FROM 'array' THEN RETURN v_observation; END IF;
  IF pg_catalog.jsonb_array_length(v_body->'report_data') <> v_total THEN RETURN v_observation; END IF;
  FOR v_row IN SELECT value FROM pg_catalog.jsonb_array_elements(v_body->'report_data') LOOP
    IF pg_catalog.jsonb_typeof(v_row) IS DISTINCT FROM 'object'
      OR pg_catalog.jsonb_typeof(v_row->'client_code') IS DISTINCT FROM 'string'
      OR pg_catalog.jsonb_typeof(v_row->'order_id') IS DISTINCT FROM 'string'
      OR NULLIF(pg_catalog.btrim(v_row->>'order_id'),'') IS NULL
      OR pg_catalog.jsonb_typeof(v_row->'order_status') IS DISTINCT FROM 'string'
      OR NULLIF(pg_catalog.btrim(v_row->>'order_status'),'') IS NULL THEN RETURN v_observation; END IF;
    IF v_row->>'client_code' IS DISTINCT FROM p_request->>'client_code'
      OR (COALESCE(p_request->>'order_ids','') <> '' AND NOT (v_row->>'order_id' = ANY(pg_catalog.string_to_array(p_request->>'order_ids',','))))
      OR (COALESCE(p_request->>'order_ids','') = '' AND COALESCE(p_request->>'member_unique_ids','') <> ''
        AND NOT COALESCE(pg_catalog.jsonb_typeof(v_row->'member_unique_id') = 'string'
          AND v_row->>'member_unique_id' = ANY(pg_catalog.string_to_array(p_request->>'member_unique_ids',',')),false)) THEN
      RETURN v_observation || '{"category":"order_status_scope_mismatch"}'::pg_catalog.jsonb;
    END IF;
    IF v_row->>'order_status' = 'VALID' THEN v_valid := v_valid+1;
    ELSIF v_row->>'order_status' = 'INVALID' THEN v_invalid := v_invalid+1;
    ELSE v_other := v_other+1; END IF;
  END LOOP;
  RETURN pg_catalog.jsonb_build_object('native_status','S','success',true,'category',
    CASE WHEN v_total=0 THEN 'order_status_no_records' ELSE 'order_status_report_received' END,
    'record_count',v_total,'valid_count',v_valid,'invalid_count',v_invalid,'other_count',v_other);
END;
$$;

COMMIT;
