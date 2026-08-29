-- Regression contract for parser-normalized CAMS codes accepted by the
-- persistence RPC. This test is intentionally metadata-only: the main Issue
-- #32 ingestion test exercises the RPC with database fixtures and this test
-- locks the exact validation matrix against accidental widening.
BEGIN;

DO $$
DECLARE
  v_definition pg_catalog.text;
BEGIN
  SELECT pg_catalog.pg_get_functiondef(
    'public.persist_cams_kfintech_statement_ingestion(
      uuid, uuid, uuid, uuid, text, text, text, text, text, text, text,
      text, text, integer, timestamp with time zone, jsonb
    )'::pg_catalog.regprocedure
  )
  INTO v_definition;

  IF v_definition NOT LIKE '%''BUY'', ''PURCHASE'', ''PUR'', ''SIP'', ''ADDITIONAL_PURCHASE'', ''ADDITIONAL_PURCHASE_SYSTEMATIC'', ''FRESH_PURCHASE_SYSTEMATIC'', ''NFO_FP''%'
     OR v_definition NOT LIKE '%''SELL'', ''REDEMPTION'', ''RED'', ''FULL_REDEMPTION''%'
     OR v_definition NOT LIKE '%''SWITCHIN'', ''SWITCH_IN''%'
     OR v_definition NOT LIKE '%''SWITCHOUT'', ''SWITCH_OUT'', ''PARTIAL_SWITCH_OUT''%' THEN
    RAISE EXCEPTION 'CAMS persistence parser-contract matrix is incomplete';
  END IF;

  IF v_definition NOT LIKE '%''P'', ''PURCHASE'', ''ADDITIONAL_PURCHASE'', ''SIP''%'
     OR v_definition NOT LIKE '%''R'', ''REDEMPTION'', ''FULL_REDEMPTION''%'
     OR v_definition NOT LIKE '%''SI'', ''SWITCH_IN''%'
     OR v_definition NOT LIKE '%''SO'', ''SWITCH_OUT''%' THEN
    RAISE EXCEPTION 'KFINTECH persistence contract changed';
  END IF;

  IF v_definition NOT LIKE '%AND v_tx ->> ''transactionType'' = ''BUY'' AND v_transaction_direction = ''INFLOW''%'
     OR v_definition NOT LIKE '%AND v_tx ->> ''transactionType'' = ''SELL'' AND v_transaction_direction = ''OUTFLOW''%'
     OR v_definition NOT LIKE '%AND v_tx ->> ''transactionType'' = ''SWITCH'' AND v_transaction_direction = ''INFLOW''%'
     OR v_definition NOT LIKE '%AND v_tx ->> ''transactionType'' = ''SWITCH'' AND v_transaction_direction = ''OUTFLOW''%' THEN
    RAISE EXCEPTION 'CAMS persistence no longer fails closed on transaction type or direction';
  END IF;
END;
$$;

ROLLBACK;
