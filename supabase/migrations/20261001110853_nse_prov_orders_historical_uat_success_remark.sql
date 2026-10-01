-- Existing safe live_uat characterization (2026-08-31), request 20:
-- HTTP 200 / EXECUTED_SUCCESS, response_status:success_like and
-- error_remark:nonempty_diagnostic; report_data is an empty array with string total.
-- This endpoint-specific observation qualifies handbook p79's blank-success remark.
-- Keep diagnostics only in encrypted RESULT evidence. Preserve the existing
-- S/F, required-field, array/count and account/ID checks and ORDER_STATUS behavior.
BEGIN;

CREATE OR REPLACE FUNCTION public.inspect_nse_prov_orders_response(p_payload pg_catalog.text, p_request pg_catalog.jsonb)
RETURNS pg_catalog.jsonb LANGUAGE plpgsql IMMUTABLE SET search_path = '' AS $$
DECLARE v_common pg_catalog.jsonb;
BEGIN
  v_common := public.inspect_nse_order_status_response(p_payload,p_request);
  RETURN v_common || pg_catalog.jsonb_build_object('category',pg_catalog.replace(v_common->>'category','order_status_','prov_orders_'));
END;
$$;

COMMIT;
