-- Test Suite: Issue #89 Sell and Switch Order Intent Persistency.
-- Tests for constraints, triggers, audit logging, outbox event generation, and RPC validations.

BEGIN;

-- 1. Initialize User Accounts (which automatically creates profiles via trigger)
INSERT INTO auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES
  ('82000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'investor@test.com', '{"user_role":"investor"}', '{}', now(), now()),
  ('82000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'advisor@test.com', '{"user_role":"mfd"}', '{}', now(), now());

-- Update accounts
UPDATE public.user_accounts SET account_state = 'linked_investor' WHERE user_id = '82000000-0000-0000-0000-000000000001';
UPDATE public.user_accounts SET account_state = 'advisor' WHERE user_id = '82000000-0000-0000-0000-000000000002';

-- Run assertion block
DO $$
DECLARE
  v_investor_profile_id uuid;
  v_advisor_profile_id uuid;
  v_err text;
  v_order public.order_requests;
  v_audit public.workspace_audit_logs;
  v_outbox public.event_outbox;
BEGIN
  -- Resolve auto-created profiles
  SELECT id INTO v_investor_profile_id FROM public.profiles WHERE user_id = '82000000-0000-0000-0000-000000000001';
  SELECT id INTO v_advisor_profile_id FROM public.profiles WHERE user_id = '82000000-0000-0000-0000-000000000002';

  UPDATE public.profiles SET full_name = 'Test Investor', role = 'client' WHERE id = v_investor_profile_id;
  UPDATE public.profiles SET full_name = 'Test Advisor', role = 'advisor' WHERE id = v_advisor_profile_id;

  -- Create workspace
  INSERT INTO public.workspaces (id, name, slug, owner_profile_id)
  VALUES ('82200000-0000-0000-0000-000000000001', 'Test Workspace', 'test-workspace', v_advisor_profile_id);

  -- Create memberships
  INSERT INTO public.workspace_memberships (workspace_id, profile_id, role, status)
  VALUES
    ('82200000-0000-0000-0000-000000000001', v_investor_profile_id, 'investor', 'active'),
    ('82200000-0000-0000-0000-000000000001', v_advisor_profile_id, 'advisor', 'active');

  -- Create funds
  INSERT INTO public.mutual_funds (id, scheme_code, scheme_name, fund_house, category, current_nav, nav_date)
  VALUES
    ('82300000-0000-0000-0000-000000000001', 'SCH-SOURCE', 'Source Fund', 'House A', 'Debt', 10.00, '2026-08-01'::date),
    ('82300000-0000-0000-0000-000000000002', 'SCH-DEST', 'Destination Fund', 'House A', 'Equity', 20.00, '2026-08-01'::date);

  -- Create folios
  INSERT INTO public.folio_references (id, registrar, normalized_folio_number, amc_identity, source_folio_masked)
  VALUES
    ('82400000-0000-0000-0000-000000000001', 'CAMS', '123456', 'AMC01', '123***'),
    ('82400000-0000-0000-0000-000000000002', 'CAMS', '789012', 'AMC01', '789***'),
    ('82400000-0000-0000-0000-000000000003', 'CAMS', '345678', 'AMC01', '345***');

  -- Setup folio-scoped portfolios for Test Investor
  INSERT INTO public.portfolios (id, client_id, workspace_id, total_invested_value, current_market_value)
  VALUES
    ('82500000-0000-0000-0000-000000000001', v_investor_profile_id, '82200000-0000-0000-0000-000000000001', 0.00, 0.00),
    ('82500000-0000-0000-0000-000000000002', v_investor_profile_id, '82200000-0000-0000-0000-000000000001', 0.00, 0.00);

  INSERT INTO public.portfolio_folio_references (portfolio_id, folio_reference_id)
  VALUES
    ('82500000-0000-0000-0000-000000000001', '82400000-0000-0000-0000-000000000001'),
    ('82500000-0000-0000-0000-000000000002', '82400000-0000-0000-0000-000000000002');

  -- 2. Constraint Tests: amount XOR units
  BEGIN
    INSERT INTO public.order_requests (id, workspace_id, investor_profile_id, initiated_by_profile_id, initiated_by_role, initiation_channel, scheme_code, type, amount, units, status)
    VALUES ('82600000-0000-0000-0000-000000000001', '82200000-0000-0000-0000-000000000001', v_investor_profile_id, v_investor_profile_id, 'investor', 'investor_portal', 'SCH-SOURCE', 'buy', 100.00, 10.00, 'pending_qualification');
    RAISE EXCEPTION 'XOR constraint failed to reject both fields';
  EXCEPTION WHEN check_violation THEN
    -- Expected check violation
  END;

  BEGIN
    INSERT INTO public.order_requests (id, workspace_id, investor_profile_id, initiated_by_profile_id, initiated_by_role, initiation_channel, scheme_code, type, amount, units, status)
    VALUES ('82600000-0000-0000-0000-000000000001', '82200000-0000-0000-0000-000000000001', v_investor_profile_id, v_investor_profile_id, 'investor', 'investor_portal', 'SCH-SOURCE', 'buy', NULL, NULL, 'pending_qualification');
    RAISE EXCEPTION 'XOR constraint failed to reject null fields';
  EXCEPTION WHEN check_violation THEN
    -- Expected check violation
  END;

  -- 3. Constraint Tests: NaN check
  BEGIN
    INSERT INTO public.order_requests (id, workspace_id, investor_profile_id, initiated_by_profile_id, initiated_by_role, initiation_channel, scheme_code, type, amount, units, status)
    VALUES ('82600000-0000-0000-0000-000000000001', '82200000-0000-0000-0000-000000000001', v_investor_profile_id, v_investor_profile_id, 'investor', 'investor_portal', 'SCH-SOURCE', 'buy', 'NaN'::numeric, NULL, 'pending_qualification');
    RAISE EXCEPTION 'NaN check failed';
  EXCEPTION WHEN check_violation THEN
    -- Expected check violation
  END;

  -- 4. Constraint Tests: type conditional fields
  BEGIN
    INSERT INTO public.order_requests (id, workspace_id, investor_profile_id, initiated_by_profile_id, initiated_by_role, initiation_channel, scheme_code, type, amount, units, folio_reference_id, status)
    VALUES ('82600000-0000-0000-0000-000000000001', '82200000-0000-0000-0000-000000000001', v_investor_profile_id, v_investor_profile_id, 'investor', 'investor_portal', 'SCH-SOURCE', 'buy', 1000.00, NULL, '82400000-0000-0000-0000-000000000001', 'pending_qualification');
    RAISE EXCEPTION 'Buy with folio check failed';
  EXCEPTION WHEN check_violation THEN
    -- Expected check violation
  END;

  BEGIN
    INSERT INTO public.order_requests (id, workspace_id, investor_profile_id, initiated_by_profile_id, initiated_by_role, initiation_channel, scheme_code, type, amount, units, status)
    VALUES ('82600000-0000-0000-0000-000000000001', '82200000-0000-0000-0000-000000000001', v_investor_profile_id, v_investor_profile_id, 'investor', 'investor_portal', 'SCH-SOURCE', 'sell', 1000.00, NULL, 'pending_qualification');
    RAISE EXCEPTION 'Sell without folio check failed';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'folio_reference_required_for_sell_switch' THEN
      RAISE EXCEPTION 'Unexpected error for sell without folio: %', SQLERRM;
    END IF;
  END;

  -- 5. Trigger validations: holdings checks
  BEGIN
    INSERT INTO public.order_requests (id, workspace_id, investor_profile_id, initiated_by_profile_id, initiated_by_role, initiation_channel, scheme_code, type, amount, units, folio_reference_id, status)
    VALUES ('82600000-0000-0000-0000-000000000001', '82200000-0000-0000-0000-000000000001', v_investor_profile_id, v_investor_profile_id, 'investor', 'investor_portal', 'SCH-SOURCE', 'sell', 1000.00, NULL, '82400000-0000-0000-0000-000000000001', 'pending_qualification');
    RAISE EXCEPTION 'Trigger holdings validation did not catch 0 units balance';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'scheme_not_held_in_selected_folio' THEN
      RAISE EXCEPTION 'Unexpected error when checking holdings: %', SQLERRM;
    END IF;
  END;

  -- Transaction ledger entries must carry a deterministic folio reference.
  BEGIN
    INSERT INTO public.transactions (portfolio_id, mutual_fund_id, transaction_type, units, nav_at_transaction, amount, execution_date)
    VALUES ('82500000-0000-0000-0000-000000000001', '82300000-0000-0000-0000-000000000001', 'BUY', 500.0000, 10.0000, 5000.00, '2026-08-01'::date);
    RAISE EXCEPTION 'Transaction insert without folio_reference_id was accepted';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'transaction_folio_reference_required' THEN
      RAISE EXCEPTION 'Unexpected error for transaction without folio_reference_id: %', SQLERRM;
    END IF;
  END;

  -- Establish holding only in source folio 1.
  INSERT INTO public.transactions (portfolio_id, folio_reference_id, mutual_fund_id, transaction_type, units, nav_at_transaction, amount, execution_date)
  VALUES ('82500000-0000-0000-0000-000000000001', '82400000-0000-0000-0000-000000000001', '82300000-0000-0000-0000-000000000001', 'BUY', 500.0000, 10.0000, 5000.00, '2026-08-01'::date);

  -- Folio 2 is owned by the investor, but has no direct source-scheme holding.
  BEGIN
    INSERT INTO public.order_requests (id, workspace_id, investor_profile_id, initiated_by_profile_id, initiated_by_role, initiation_channel, scheme_code, type, amount, units, folio_reference_id, status)
    VALUES ('82600000-0000-0000-0000-000000000001', '82200000-0000-0000-0000-000000000001', v_investor_profile_id, v_investor_profile_id, 'investor', 'investor_portal', 'SCH-SOURCE', 'sell', 1000.00, NULL, '82400000-0000-0000-0000-000000000002', 'pending_qualification');
    RAISE EXCEPTION 'Source-folio holdings validation used portfolio-level approximation';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'scheme_not_held_in_selected_folio' THEN
      RAISE EXCEPTION 'Unexpected error for owned folio without direct scheme holding: %', SQLERRM;
    END IF;
  END;

  -- Trigger validation: non-owned folio check
  BEGIN
    INSERT INTO public.order_requests (id, workspace_id, investor_profile_id, initiated_by_profile_id, initiated_by_role, initiation_channel, scheme_code, type, amount, units, folio_reference_id, status)
    VALUES ('82600000-0000-0000-0000-000000000001', '82200000-0000-0000-0000-000000000001', v_investor_profile_id, v_investor_profile_id, 'investor', 'investor_portal', 'SCH-SOURCE', 'sell', 1000.00, NULL, '82400000-0000-0000-0000-000000000003', 'pending_qualification');
    RAISE EXCEPTION 'Trigger ownership check failed to catch non-owned folio';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'folio_not_owned_by_investor_in_workspace' THEN
      RAISE EXCEPTION 'Unexpected error when checking folio ownership: %', SQLERRM;
    END IF;
  END;

  -- 6. Trigger validation: Valid Sell insert
  INSERT INTO public.order_requests (id, workspace_id, investor_profile_id, initiated_by_profile_id, initiated_by_role, initiation_channel, scheme_code, type, amount, units, folio_reference_id, status)
  VALUES ('82600000-0000-0000-0000-000000000001', '82200000-0000-0000-0000-000000000001', v_investor_profile_id, v_investor_profile_id, 'investor', 'investor_portal', 'SCH-SOURCE', 'sell', 1000.00, NULL, '82400000-0000-0000-0000-000000000001', 'pending_qualification');

  -- 7. Trigger validation: Switch destination code doesn't exist
  BEGIN
    INSERT INTO public.order_requests (id, workspace_id, investor_profile_id, initiated_by_profile_id, initiated_by_role, initiation_channel, scheme_code, type, amount, units, folio_reference_id, destination_scheme_code, status)
    VALUES ('82600000-0000-0000-0000-000000000002', '82200000-0000-0000-0000-000000000001', v_investor_profile_id, v_investor_profile_id, 'investor', 'investor_portal', 'SCH-SOURCE', 'switch', 1000.00, NULL, '82400000-0000-0000-0000-000000000001', 'SCH-UNKNOWN', 'pending_qualification');
    RAISE EXCEPTION 'Destination fund exists check failed';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'destination_scheme_not_found' THEN
      RAISE EXCEPTION 'Unexpected error when checking destination fund existence: %', SQLERRM;
    END IF;
  END;

  -- Valid Switch insert
  INSERT INTO public.order_requests (id, workspace_id, investor_profile_id, initiated_by_profile_id, initiated_by_role, initiation_channel, scheme_code, type, amount, units, folio_reference_id, destination_scheme_code, status)
  VALUES ('82600000-0000-0000-0000-000000000002', '82200000-0000-0000-0000-000000000001', v_investor_profile_id, v_investor_profile_id, 'investor', 'investor_portal', 'SCH-SOURCE', 'switch', 1000.00, NULL, '82400000-0000-0000-0000-000000000001', 'SCH-DEST', 'pending_qualification');

  -- 8. Audit log audit fields check
  SELECT * INTO v_audit FROM public.workspace_audit_logs WHERE target_id = '82600000-0000-0000-0000-000000000002';
  IF v_audit.payload->>'type' <> 'switch'
     OR v_audit.payload->>'folio_reference_id' <> '82400000-0000-0000-0000-000000000001'
     OR v_audit.payload->>'destination_scheme_code' <> 'SCH-DEST' THEN
    RAISE EXCEPTION 'Audit log did not record correct switch payload fields';
  END IF;

  -- 9. Outbox payload details check
  SELECT * INTO v_outbox FROM public.event_outbox WHERE entity_id = '82600000-0000-0000-0000-000000000002';
  IF v_outbox.payload->>'type' <> 'switch'
     OR v_outbox.payload->>'folio_reference_id' <> '82400000-0000-0000-0000-000000000001'
     OR v_outbox.payload->>'destination_scheme_code' <> 'SCH-DEST' THEN
    RAISE EXCEPTION 'Outbox did not record correct switch payload fields';
  END IF;

  -- 10. RPC projections
  -- Perform cancel_order under investor context
  PERFORM set_config('request.jwt.claim.sub', '82000000-0000-0000-0000-000000000001', true);
  PERFORM set_config('request.jwt.claims', '{"sub":"82000000-0000-0000-0000-000000000001","role":"authenticated","app_metadata":{"user_role":"investor"}}', true);

  v_order := public.cancel_order('82600000-0000-0000-0000-000000000001', 'Cancel Sell');
  IF v_order.status <> 'cancelled'
     OR v_order.cancellation_reason <> 'Cancel Sell'
     OR v_order.folio_reference_id <> '82400000-0000-0000-0000-000000000001' THEN
    RAISE EXCEPTION 'cancel_order returned unexpected fields: %', to_jsonb(v_order);
  END IF;

  -- Move Switch order to pending_review to test qualification
  RESET ROLE;
  UPDATE public.order_requests SET status = 'pending_review' WHERE id = '82600000-0000-0000-0000-000000000002';

  -- Perform qualify_order under advisor context
  PERFORM set_config('request.jwt.claim.sub', '82000000-0000-0000-0000-000000000002', true);
  PERFORM set_config('request.jwt.claims', '{"sub":"82000000-0000-0000-0000-000000000002","role":"authenticated","app_metadata":{"user_role":"advisor"}}', true);

  v_order := public.qualify_order('82600000-0000-0000-0000-000000000002', 'approved');
  IF v_order.status <> 'approved'
     OR v_order.destination_scheme_code <> 'SCH-DEST'
     OR v_order.folio_reference_id <> '82400000-0000-0000-0000-000000000001' THEN
    RAISE EXCEPTION 'qualify_order returned unexpected fields: %', to_jsonb(v_order);
  END IF;
END $$;

SELECT set_config('request.jwt.claim.sub', '', true);
SELECT set_config('request.jwt.claims', '{}', true);

CREATE TEMP TABLE issue89_test_profiles (
  label text PRIMARY KEY,
  profile_id uuid NOT NULL
) ON COMMIT DROP;

INSERT INTO issue89_test_profiles (label, profile_id)
SELECT 'investor_a', id FROM public.profiles WHERE user_id = '82000000-0000-0000-0000-000000000001'
UNION ALL
SELECT 'advisor', id FROM public.profiles WHERE user_id = '82000000-0000-0000-0000-000000000002';

GRANT SELECT ON issue89_test_profiles TO authenticated;
GRANT SELECT ON issue89_test_profiles TO service_role;

-- 11. Regression: all non-finite numeric values are rejected while amount XOR units remains enforced.
DO $$
DECLARE
  v_literal text;
  v_investor_profile_id uuid;
BEGIN
  SELECT profile_id INTO v_investor_profile_id
  FROM issue89_test_profiles
  WHERE label = 'investor_a';

  FOREACH v_literal IN ARRAY ARRAY['NaN', 'Infinity', '-Infinity'] LOOP
    BEGIN
      INSERT INTO public.order_requests (
        id,
        workspace_id,
        investor_profile_id,
        initiated_by_profile_id,
        initiated_by_role,
        initiation_channel,
        scheme_code,
        type,
        amount,
        units,
        status
      ) VALUES (
        pg_catalog.gen_random_uuid(),
        '82200000-0000-0000-0000-000000000001',
        v_investor_profile_id,
        v_investor_profile_id,
        'investor',
        'investor_portal',
        'SCH-SOURCE',
        'buy',
        v_literal::pg_catalog.numeric,
        NULL,
        'pending_qualification'
      );
      RAISE EXCEPTION 'non-finite amount was accepted: %', v_literal;
    EXCEPTION WHEN check_violation OR numeric_value_out_of_range THEN
      -- Expected.
    END;

    BEGIN
      INSERT INTO public.order_requests (
        id,
        workspace_id,
        investor_profile_id,
        initiated_by_profile_id,
        initiated_by_role,
        initiation_channel,
        scheme_code,
        type,
        amount,
        units,
        status
      ) VALUES (
        pg_catalog.gen_random_uuid(),
        '82200000-0000-0000-0000-000000000001',
        v_investor_profile_id,
        v_investor_profile_id,
        'investor',
        'investor_portal',
        'SCH-SOURCE',
        'buy',
        NULL,
        v_literal::pg_catalog.numeric,
        'pending_qualification'
      );
      RAISE EXCEPTION 'non-finite units were accepted: %', v_literal;
    EXCEPTION WHEN check_violation OR numeric_value_out_of_range THEN
      -- Expected.
    END;
  END LOOP;
END $$;

-- 12. Additional tenant fixtures for API-role and ingestion isolation checks.
INSERT INTO auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES
  ('82000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'investor-b@test.com', '{"user_role":"investor"}', '{}', now(), now())
ON CONFLICT (id) DO NOTHING;

UPDATE public.user_accounts
SET account_state = 'linked_investor'
WHERE user_id = '82000000-0000-0000-0000-000000000003';

UPDATE public.profiles
SET full_name = 'Test Investor B', role = 'client'
WHERE user_id = '82000000-0000-0000-0000-000000000003';

INSERT INTO issue89_test_profiles (label, profile_id)
SELECT 'investor_b', id FROM public.profiles WHERE user_id = '82000000-0000-0000-0000-000000000003';

INSERT INTO public.workspaces (id, name, slug, owner_profile_id)
VALUES (
  '82200000-0000-0000-0000-000000000002',
  'Test Workspace B',
  'test-workspace-b',
  (SELECT profile_id FROM issue89_test_profiles WHERE label = 'advisor')
);

INSERT INTO public.workspace_memberships (workspace_id, profile_id, role, status)
VALUES
  ('82200000-0000-0000-0000-000000000001', (SELECT profile_id FROM issue89_test_profiles WHERE label = 'investor_b'), 'investor', 'active'),
  ('82200000-0000-0000-0000-000000000002', (SELECT profile_id FROM issue89_test_profiles WHERE label = 'advisor'), 'advisor', 'active'),
  ('82200000-0000-0000-0000-000000000002', (SELECT profile_id FROM issue89_test_profiles WHERE label = 'investor_b'), 'investor', 'active');

INSERT INTO public.folio_references (id, registrar, normalized_folio_number, amc_identity, source_folio_masked)
VALUES
  ('82400000-0000-0000-0000-000000000004', 'CAMS', '456789', 'AMC01', '456***'),
  ('82400000-0000-0000-0000-000000000005', 'CAMS', '567890', 'AMC01', '567***');

INSERT INTO public.portfolios (id, client_id, workspace_id, total_invested_value, current_market_value)
VALUES
  ('82500000-0000-0000-0000-000000000003', (SELECT profile_id FROM issue89_test_profiles WHERE label = 'investor_b'), '82200000-0000-0000-0000-000000000001', 0.00, 0.00),
  ('82500000-0000-0000-0000-000000000004', (SELECT profile_id FROM issue89_test_profiles WHERE label = 'investor_b'), '82200000-0000-0000-0000-000000000002', 0.00, 0.00);

INSERT INTO public.portfolio_folio_references (portfolio_id, folio_reference_id)
VALUES
  ('82500000-0000-0000-0000-000000000003', '82400000-0000-0000-0000-000000000004'),
  ('82500000-0000-0000-0000-000000000004', '82400000-0000-0000-0000-000000000005');

INSERT INTO public.transactions (portfolio_id, folio_reference_id, mutual_fund_id, transaction_type, units, nav_at_transaction, amount, execution_date)
VALUES
  ('82500000-0000-0000-0000-000000000003', '82400000-0000-0000-0000-000000000004', '82300000-0000-0000-0000-000000000001', 'BUY', 100.0000, 10.0000, 1000.00, '2026-08-01'::date),
  ('82500000-0000-0000-0000-000000000004', '82400000-0000-0000-0000-000000000005', '82300000-0000-0000-0000-000000000001', 'BUY', 100.0000, 10.0000, 1000.00, '2026-08-01'::date);

-- 13. Real authenticated role: valid insertion, tenant rejection, and cancellation after holdings become zero.
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '82000000-0000-0000-0000-000000000001', true);
SELECT set_config('request.jwt.claims', '{"sub":"82000000-0000-0000-0000-000000000001","role":"authenticated","workspace_id":"82200000-0000-0000-0000-000000000001","app_metadata":{"user_role":"investor"}}', true);

INSERT INTO public.order_requests (
  id,
  workspace_id,
  investor_profile_id,
  initiated_by_profile_id,
  initiated_by_role,
  initiation_channel,
  scheme_code,
  type,
  units,
  folio_reference_id,
  status
) VALUES (
  '82600000-0000-0000-0000-000000000010',
  '82200000-0000-0000-0000-000000000001',
  public.current_user_profile_id(),
  public.current_user_profile_id(),
  'investor',
  'investor_portal',
  'SCH-SOURCE',
  'sell',
  10.0000,
  '82400000-0000-0000-0000-000000000001',
  'pending_qualification'
);

DO $$
BEGIN
  BEGIN
    INSERT INTO public.order_requests (
      id,
      workspace_id,
      investor_profile_id,
      initiated_by_profile_id,
      initiated_by_role,
      initiation_channel,
      scheme_code,
      type,
      units,
      folio_reference_id,
      status
    ) VALUES (
      '82600000-0000-0000-0000-000000000011',
      '82200000-0000-0000-0000-000000000002',
      public.current_user_profile_id(),
      public.current_user_profile_id(),
      'investor',
      'investor_portal',
      'SCH-SOURCE',
      'sell',
      1.0000,
      '82400000-0000-0000-0000-000000000001',
      'pending_qualification'
    );
    RAISE EXCEPTION 'cross-workspace authenticated order was accepted';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT IN (
      'investor_workspace_relationship_required',
      'new row violates row-level security policy for table "order_requests"'
    ) THEN
      RAISE EXCEPTION 'Unexpected cross-workspace rejection: %', SQLERRM;
    END IF;
  END;

  BEGIN
    INSERT INTO public.order_requests (
      id,
      workspace_id,
      investor_profile_id,
      initiated_by_profile_id,
      initiated_by_role,
      initiation_channel,
      scheme_code,
      type,
      units,
      folio_reference_id,
      status
    ) VALUES (
      '82600000-0000-0000-0000-000000000012',
      '82200000-0000-0000-0000-000000000001',
      (SELECT profile_id FROM issue89_test_profiles WHERE label = 'investor_b'),
      public.current_user_profile_id(),
      'investor',
      'investor_portal',
      'SCH-SOURCE',
      'sell',
      1.0000,
      '82400000-0000-0000-0000-000000000004',
      'pending_qualification'
    );
    RAISE EXCEPTION 'cross-investor authenticated order was accepted';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT IN (
      'investor_initiator_mismatch',
      'order_initiator_not_authorized',
      'new row violates row-level security policy for table "order_requests"'
    ) THEN
      RAISE EXCEPTION 'Unexpected cross-investor rejection: %', SQLERRM;
    END IF;
  END;
END $$;

RESET ROLE;

INSERT INTO public.transactions (portfolio_id, folio_reference_id, mutual_fund_id, transaction_type, units, nav_at_transaction, amount, execution_date)
VALUES ('82500000-0000-0000-0000-000000000001', '82400000-0000-0000-0000-000000000001', '82300000-0000-0000-0000-000000000001', 'SELL', 500.0000, 10.0000, 5000.00, '2026-08-02'::date);

SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '82000000-0000-0000-0000-000000000001', true);
SELECT set_config('request.jwt.claims', '{"sub":"82000000-0000-0000-0000-000000000001","role":"authenticated","workspace_id":"82200000-0000-0000-0000-000000000001","app_metadata":{"user_role":"investor"}}', true);

DO $$
DECLARE
  v_order public.order_requests;
BEGIN
  v_order := public.cancel_order('82600000-0000-0000-0000-000000000010', 'Cancel after holdings depleted');
  IF v_order.status <> 'cancelled' THEN
    RAISE EXCEPTION 'cancel_order did not succeed after source holding reached zero';
  END IF;
END $$;

RESET ROLE;

-- 14. Real service_role: valid workspace-scoped ingestion and rejected cross-workspace PAN reuse.
INSERT INTO public.profiles (id, full_name, role)
VALUES ('82000000-0000-0000-0000-000000000004', 'Workspace B Existing PAN Investor', 'client');

INSERT INTO public.workspace_memberships (workspace_id, profile_id, role, status)
VALUES ('82200000-0000-0000-0000-000000000002', '82000000-0000-0000-0000-000000000004', 'investor', 'active');

INSERT INTO public.profile_pan_records (
  profile_id,
  pan_ciphertext,
  pan_lookup_hmac,
  masked_pan,
  source,
  source_system,
  status
) VALUES (
  '82000000-0000-0000-0000-000000000004',
  extensions.pgp_sym_encrypt(public.normalize_pan('PQRST1234U'), public.pan_encryption_key(), 'cipher-algo=aes256, compress-algo=0'),
  extensions.hmac(public.normalize_pan('PQRST1234U'), public.pan_lookup_hmac_key(), 'sha256'),
  public.mask_pan(public.normalize_pan('PQRST1234U')),
  'IMPORT',
  'CAMS',
  'OBSERVED'
);

SET ROLE service_role;
SELECT set_config('request.jwt.claim.sub', '', true);
SELECT set_config('request.jwt.claims', '{"role":"service_role"}', true);

SELECT public.process_cams_records(
  '[{
    "clientPan":"ABCDE1234F",
    "registrar":"CAMS",
    "investorName":"Service Role Investor",
    "schemeCode":"SCH-SERVICE",
    "schemeName":"Service Fund",
    "fundHouse":"House S",
    "category":"Debt",
    "transactionType":"BUY",
    "units":"25.0000",
    "nav":"10.0000",
    "amount":"250.00",
    "foliochk":"SRV123",
    "inv_name":"Service Role Investor",
    "address1":"",
    "address2":"",
    "address3":"",
    "city":"",
    "pincode":"",
    "product":"SRV",
    "sch_name":"Service Fund",
    "clos_bal":"25.0000",
    "rupee_bal":"250.00",
    "email":"",
    "mobile_no":"",
    "bank_name":"",
    "branch":"",
    "ac_type":"",
    "ac_no":"",
    "ifsc_code":"",
    "nom_name":"",
    "relation":"",
    "nom_percen":"0",
    "rep_date":"2026-08-01",
    "date":"2026-08-01"
  }]'::pg_catalog.jsonb,
  '82200000-0000-0000-0000-000000000001'
);

DO $$
BEGIN
  BEGIN
    PERFORM public.process_cams_records(
      '[{
        "clientPan":"PQRST1234U",
        "registrar":"CAMS",
        "investorName":"Workspace B Existing PAN Investor",
        "schemeCode":"SCH-SERVICE-X",
        "schemeName":"Service Cross Fund",
        "fundHouse":"House S",
        "category":"Debt",
        "transactionType":"BUY",
        "units":"10.0000",
        "nav":"10.0000",
        "amount":"100.00",
        "foliochk":"SRVX123",
        "inv_name":"Workspace B Existing PAN Investor",
        "address1":"",
        "address2":"",
        "address3":"",
        "city":"",
        "pincode":"",
        "product":"SRVX",
        "sch_name":"Service Cross Fund",
        "clos_bal":"10.0000",
        "rupee_bal":"100.00",
        "email":"",
        "mobile_no":"",
        "bank_name":"",
        "branch":"",
        "ac_type":"",
        "ac_no":"",
        "ifsc_code":"",
        "nom_name":"",
        "relation":"",
        "nom_percen":"0",
        "rep_date":"2026-08-01",
        "date":"2026-08-01"
      }]'::pg_catalog.jsonb,
      '82200000-0000-0000-0000-000000000001'
    );
    RAISE EXCEPTION 'service_role cross-workspace PAN ingestion was accepted';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'investor_workspace_relationship_required' THEN
      RAISE EXCEPTION 'Unexpected service_role cross-workspace rejection: %', SQLERRM;
    END IF;
  END;
END $$;

RESET ROLE;
ROLLBACK;
