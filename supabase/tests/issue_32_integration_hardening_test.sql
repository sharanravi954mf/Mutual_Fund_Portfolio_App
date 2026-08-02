-- Test Suite: Issue #32 integration hardening after PR #90 merge.

BEGIN;

INSERT INTO auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES
  ('95200000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'issue32-hardening-advisor@moneybowl.test', '{"user_role":"mfd"}', '{}', now(), now()),
  ('95200000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'issue32-hardening-investor@moneybowl.test', '{"user_role":"investor"}', '{}', now(), now()),
  ('95200000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'issue32-hardening-other-advisor@moneybowl.test', '{"user_role":"mfd"}', '{}', now(), now());

UPDATE public.user_accounts
SET account_state = 'advisor'
WHERE user_id IN (
  '95200000-0000-0000-0000-000000000001',
  '95200000-0000-0000-0000-000000000003'
);

UPDATE public.user_accounts
SET account_state = 'linked_investor'
WHERE user_id = '95200000-0000-0000-0000-000000000002';

UPDATE public.profiles SET id = '95300000-0000-0000-0000-000000000001', role = 'advisor', full_name = 'Issue 32 Hardening Advisor'
WHERE user_id = '95200000-0000-0000-0000-000000000001';
UPDATE public.profiles SET id = '95300000-0000-0000-0000-000000000002', role = 'investor', full_name = 'Issue 32 Hardening Investor'
WHERE user_id = '95200000-0000-0000-0000-000000000002';
UPDATE public.profiles SET id = '95300000-0000-0000-0000-000000000003', role = 'advisor', full_name = 'Issue 32 Hardening Other Advisor'
WHERE user_id = '95200000-0000-0000-0000-000000000003';

INSERT INTO public.workspaces (id, name, slug, owner_profile_id, workspace_status)
VALUES
  ('95400000-0000-0000-0000-000000000001', 'Issue 32 Hardening Active', 'issue-32-hardening-active', '95300000-0000-0000-0000-000000000001', 'active'),
  ('95400000-0000-0000-0000-000000000002', 'Issue 32 Hardening Inactive', 'issue-32-hardening-inactive', '95300000-0000-0000-0000-000000000001', 'suspended'),
  ('95400000-0000-0000-0000-000000000003', 'Issue 32 Hardening Other', 'issue-32-hardening-other', '95300000-0000-0000-0000-000000000003', 'active');

DELETE FROM public.workspace_memberships
WHERE profile_id IN (
  '95300000-0000-0000-0000-000000000001',
  '95300000-0000-0000-0000-000000000002',
  '95300000-0000-0000-0000-000000000003'
);

INSERT INTO public.workspace_memberships (workspace_id, profile_id, role, status)
VALUES
  ('95400000-0000-0000-0000-000000000001', '95300000-0000-0000-0000-000000000001', 'admin', 'active'),
  ('95400000-0000-0000-0000-000000000001', '95300000-0000-0000-0000-000000000002', 'investor', 'active'),
  ('95400000-0000-0000-0000-000000000002', '95300000-0000-0000-0000-000000000001', 'admin', 'active'),
  ('95400000-0000-0000-0000-000000000002', '95300000-0000-0000-0000-000000000002', 'investor', 'active'),
  ('95400000-0000-0000-0000-000000000003', '95300000-0000-0000-0000-000000000003', 'admin', 'active'),
  ('95400000-0000-0000-0000-000000000003', '95300000-0000-0000-0000-000000000002', 'investor', 'active');

INSERT INTO public.investor_account_links (user_id, profile_id, verification_method, verified_at, link_status)
VALUES ('95200000-0000-0000-0000-000000000002', '95300000-0000-0000-0000-000000000002', 'verified_email', now(), 'active');

INSERT INTO public.profile_pan_records (
  id,
  profile_id,
  pan_ciphertext,
  pan_lookup_hmac,
  masked_pan,
  source,
  source_system,
  status,
  verified_at
) VALUES (
  '95310000-0000-0000-0000-000000000001',
  '95300000-0000-0000-0000-000000000002',
  extensions.pgp_sym_encrypt('HDRNG1234A', public.pan_encryption_key(), 'cipher-algo=aes256, compress-algo=0'),
  extensions.hmac('HDRNG1234A', public.pan_lookup_hmac_key(), 'sha256'),
  public.mask_pan('HDRNG1234A'),
  'INVESTOR',
  'MANUAL',
  'VERIFIED',
  now()
);

UPDATE public.profiles
SET canonical_pan_record_id = '95310000-0000-0000-0000-000000000001'
WHERE id = '95300000-0000-0000-0000-000000000002';

INSERT INTO public.mailbox_connections (
  id,
  workspace_id,
  registrar,
  mailbox_address,
  connector_ref,
  oauth_provider,
  status,
  allowed_sender_addresses
) VALUES
  ('95700000-0000-0000-0000-000000000001', '95400000-0000-0000-0000-000000000001', 'CAMS', 'active-hardening@moneybowl.test', 'issue32-hardening-active', 'gmail', 'active', ARRAY['statements@camsonline.com']),
  ('95700000-0000-0000-0000-000000000002', '95400000-0000-0000-0000-000000000002', 'CAMS', 'inactive-hardening@moneybowl.test', 'issue32-hardening-inactive', 'gmail', 'active', ARRAY['statements@camsonline.com']);

SET ROLE service_role;
SELECT set_config('request.jwt.claim.sub', '', true);
SELECT set_config('request.jwt.claims', '{"role":"service_role"}', true);

SELECT public.process_cams_records(
  '[{
    "clientPan":"HDRNG1234A",
    "registrar":"CAMS",
    "investorName":"Issue 32 Hardening Investor",
    "schemeCode":"I32HARD-CANON-A",
    "schemeName":"Issue 32 Canonical Fund A",
    "fundHouse":"House H",
    "category":"Debt",
    "transactionType":"BUY",
    "units":"11.0000",
    "nav":"10.0000",
    "amount":"110.00",
    "foliochk":"HCANON001",
    "inv_name":"Issue 32 Hardening Investor",
    "address1":"",
    "address2":"",
    "address3":"",
    "city":"",
    "pincode":"",
    "product":"HCANONA",
    "sch_name":"Issue 32 Canonical Fund A",
    "clos_bal":"11.0000",
    "rupee_bal":"110.00",
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
    "rep_date":"2026-08-02",
    "date":"2026-08-02"
  }, {
    "clientPan":"HDRNG1234A",
    "registrar":"CAMS",
    "investorName":"Issue 32 Hardening Investor",
    "schemeCode":"I32HARD-CANON-B",
    "schemeName":"Issue 32 Canonical Fund B",
    "fundHouse":"House H",
    "category":"Debt",
    "transactionType":"BUY",
    "units":"13.0000",
    "nav":"10.0000",
    "amount":"130.00",
    "foliochk":"HCANON002",
    "inv_name":"Issue 32 Hardening Investor",
    "address1":"",
    "address2":"",
    "address3":"",
    "city":"",
    "pincode":"",
    "product":"HCANONB",
    "sch_name":"Issue 32 Canonical Fund B",
    "clos_bal":"13.0000",
    "rupee_bal":"130.00",
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
    "rep_date":"2026-08-03",
    "date":"2026-08-03"
  }]'::pg_catalog.jsonb,
  '95400000-0000-0000-0000-000000000001'
);

RESET ROLE;

DO $$
DECLARE
  v_count pg_catalog.int4;
  v_portfolio_count pg_catalog.int4;
BEGIN
  SELECT pg_catalog.count(*)::pg_catalog.int4
  INTO v_portfolio_count
  FROM public.portfolios
  WHERE workspace_id = '95400000-0000-0000-0000-000000000001'
    AND client_id = '95300000-0000-0000-0000-000000000002';

  IF v_portfolio_count <> 1 THEN
    RAISE EXCEPTION 'process_cams_records did not reuse one canonical portfolio: %', v_portfolio_count;
  END IF;

  SELECT pg_catalog.count(*)::pg_catalog.int4
  INTO v_count
  FROM public.portfolio_folio_references AS mapping
  JOIN public.folio_references AS folio
    ON folio.id = mapping.folio_reference_id
  JOIN public.portfolios AS portfolio
    ON portfolio.id = mapping.portfolio_id
  WHERE portfolio.workspace_id = '95400000-0000-0000-0000-000000000001'
    AND portfolio.client_id = '95300000-0000-0000-0000-000000000002'
    AND folio.normalized_folio_number IN ('HCANON001', 'HCANON002');

  IF v_count <> 2 THEN
    RAISE EXCEPTION 'process_cams_records did not map both folios to the canonical portfolio: %', v_count;
  END IF;

  SELECT pg_catalog.count(DISTINCT mapping.portfolio_id)::pg_catalog.int4
  INTO v_count
  FROM public.portfolio_folio_references AS mapping
  JOIN public.folio_references AS folio
    ON folio.id = mapping.folio_reference_id
  WHERE folio.normalized_folio_number IN ('HCANON001', 'HCANON002');

  IF v_count <> 1 THEN
    RAISE EXCEPTION 'process_cams_records split folios across portfolios: %', v_count;
  END IF;

  SELECT pg_catalog.count(*)::pg_catalog.int4
  INTO v_count
  FROM public.transactions AS transaction
  JOIN public.folio_references AS folio
    ON folio.id = transaction.folio_reference_id
  WHERE folio.normalized_folio_number IN ('HCANON001', 'HCANON002');

  IF v_count <> 2 THEN
    RAISE EXCEPTION 'process_cams_records did not persist both transactions: %', v_count;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.portfolio_folio_references AS mapping
    JOIN public.folio_references AS folio
      ON folio.id = mapping.folio_reference_id
    JOIN public.portfolios AS portfolio
      ON portfolio.id = mapping.portfolio_id
    WHERE portfolio.workspace_id = '95400000-0000-0000-0000-000000000003'
      AND folio.normalized_folio_number IN ('HCANON001', 'HCANON002')
  ) THEN
    RAISE EXCEPTION 'process_cams_records created a cross-workspace folio relationship';
  END IF;
END;
$$;

SET ROLE service_role;
DO $$
BEGIN
  PERFORM *
  FROM public.claim_cams_kfintech_ingestion_run(
    '95400000-0000-0000-0000-000000000002',
    '95700000-0000-0000-0000-000000000002',
    '95900000-0000-0000-0000-000000000901',
    'CAMS'
  );
  RAISE EXCEPTION 'inactive workspace claim was accepted';
EXCEPTION
  WHEN others THEN
    IF SQLERRM NOT LIKE '%workspace_not_active%' THEN
      RAISE;
    END IF;
END;
$$;
RESET ROLE;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.cams_kfintech_ingestion_runs
    WHERE ingestion_run_id = '95900000-0000-0000-0000-000000000901'
  ) THEN
    RAISE EXCEPTION 'inactive workspace claim created a run side effect';
  END IF;
END;
$$;

INSERT INTO public.cams_kfintech_ingestion_runs (
  ingestion_run_id,
  workspace_id,
  mailbox_connection_id,
  registrar,
  status
) VALUES (
  '95900000-0000-0000-0000-000000000902',
  '95400000-0000-0000-0000-000000000002',
  '95700000-0000-0000-0000-000000000002',
  'CAMS',
  'claimed'
);

SET ROLE service_role;
DO $$
BEGIN
  PERFORM *
  FROM public.persist_cams_kfintech_statement_ingestion(
    '95400000-0000-0000-0000-000000000002',
    '95700000-0000-0000-0000-000000000002',
    '95900000-0000-0000-0000-000000000902',
    '95900000-0000-0000-0000-000000000903',
    'inactive-provider-message',
    'inactive-provider-attachment',
    'inactive-attempt',
    'CAMS',
    repeat('a', 64),
    'ingested-documents',
    'inactive/workspace/object',
    'application/x-dbase',
    'DBF',
    1024,
    '2026-08-02T00:00:00Z',
    pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
      'registrar', 'CAMS',
      'clientPan', 'HDRNG1234A',
      'investorName', 'Inactive Workspace Investor',
      'folioNumber', 'HINACTIVE001',
      'schemeCode', 'I32HARD-INACTIVE',
      'schemeName', 'Issue 32 Inactive Fund',
      'fundHouse', 'House H',
      'category', 'Debt',
      'transactionType', 'BUY',
      'transactionDirection', 'INFLOW',
      'registrarTransactionCode', 'BUY',
      'units', 1,
      'nav', 1,
      'amount', 1,
      'date', '2026-08-02',
      'sourceRowNumber', 1
    ))
  );
  RAISE EXCEPTION 'inactive workspace persist was accepted';
EXCEPTION
  WHEN others THEN
    IF SQLERRM NOT LIKE '%workspace_not_active%' THEN
      RAISE;
    END IF;
END;
$$;
RESET ROLE;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.ingested_documents
    WHERE ingestion_run_id = '95900000-0000-0000-0000-000000000902'
       OR correlation_id = '95900000-0000-0000-0000-000000000903'
  ) OR EXISTS (
    SELECT 1 FROM public.ingestion_logs
    WHERE ingestion_run_id = '95900000-0000-0000-0000-000000000902'
  ) OR EXISTS (
    SELECT 1 FROM public.cams_kfintech_ingestion_attempts
    WHERE ingestion_run_id = '95900000-0000-0000-0000-000000000902'
  ) OR EXISTS (
    SELECT 1
    FROM public.event_outbox AS event
    JOIN public.ingested_documents AS document
      ON document.id = event.entity_id
    WHERE document.ingestion_run_id = '95900000-0000-0000-0000-000000000902'
  ) OR EXISTS (
    SELECT 1
    FROM public.transactions AS transaction
    JOIN public.mutual_funds AS fund
      ON fund.id = transaction.mutual_fund_id
    WHERE fund.scheme_code = 'I32HARD-INACTIVE'
  ) THEN
    RAISE EXCEPTION 'inactive workspace persist created side effects';
  END IF;
END;
$$;

SET ROLE service_role;
DO $$
BEGIN
  PERFORM *
  FROM public.finalize_cams_kfintech_ingestion_run(
    '95400000-0000-0000-0000-000000000002',
    '95700000-0000-0000-0000-000000000002',
    '95900000-0000-0000-0000-000000000902',
    'CAMS',
    NULL,
    'mailbox_poll_failed',
    0
  );
  RAISE EXCEPTION 'inactive workspace finalization was accepted';
EXCEPTION
  WHEN others THEN
    IF SQLERRM NOT LIKE '%workspace_not_active%' THEN
      RAISE;
    END IF;
END;
$$;
RESET ROLE;

DO $$
DECLARE
  v_status pg_catalog.text;
BEGIN
  SELECT status
  INTO v_status
  FROM public.cams_kfintech_ingestion_runs
  WHERE ingestion_run_id = '95900000-0000-0000-0000-000000000902';

  IF v_status IS DISTINCT FROM 'claimed' THEN
    RAISE EXCEPTION 'inactive workspace finalization changed run status: %', v_status;
  END IF;
END;
$$;

DO $$
DECLARE
  v_folio_id pg_catalog.uuid;
  v_workspace_a_portfolio_id pg_catalog.uuid;
  v_workspace_b_portfolio_id pg_catalog.uuid;
  v_source_fund_id pg_catalog.uuid;
  v_dest_fund_id pg_catalog.uuid;
  v_balance pg_catalog.numeric;
BEGIN
  INSERT INTO public.folio_references (
    registrar,
    normalized_folio_number,
    amc_identity,
    source_folio_masked
  ) VALUES (
    'CAMS',
    'HISO001',
    'House H',
    'HIS***'
  )
  ON CONFLICT (registrar, normalized_folio_number) DO UPDATE
  SET amc_identity = EXCLUDED.amc_identity
  RETURNING id INTO v_folio_id;

  SELECT portfolio.id
  INTO v_workspace_a_portfolio_id
  FROM public.portfolios AS portfolio
  WHERE portfolio.workspace_id = '95400000-0000-0000-0000-000000000001'
    AND portfolio.client_id = '95300000-0000-0000-0000-000000000002';

  IF v_workspace_a_portfolio_id IS NULL THEN
    INSERT INTO public.portfolios (
      workspace_id,
      client_id,
      total_invested_value,
      current_market_value
    ) VALUES (
      '95400000-0000-0000-0000-000000000001',
      '95300000-0000-0000-0000-000000000002',
      0,
      0
    )
    RETURNING id INTO v_workspace_a_portfolio_id;
  END IF;

  SELECT portfolio.id
  INTO v_workspace_b_portfolio_id
  FROM public.portfolios AS portfolio
  WHERE portfolio.workspace_id = '95400000-0000-0000-0000-000000000003'
    AND portfolio.client_id = '95300000-0000-0000-0000-000000000002';

  IF v_workspace_b_portfolio_id IS NULL THEN
    INSERT INTO public.portfolios (
      workspace_id,
      client_id,
      total_invested_value,
      current_market_value
    ) VALUES (
      '95400000-0000-0000-0000-000000000003',
      '95300000-0000-0000-0000-000000000002',
      0,
      0
    )
    RETURNING id INTO v_workspace_b_portfolio_id;
  END IF;

  INSERT INTO public.portfolio_folio_references (portfolio_id, folio_reference_id)
  VALUES
    (v_workspace_a_portfolio_id, v_folio_id),
    (v_workspace_b_portfolio_id, v_folio_id)
  ON CONFLICT (portfolio_id, folio_reference_id) DO NOTHING;

  INSERT INTO public.mutual_funds (scheme_code, scheme_name, fund_house, category, current_nav, nav_date)
  VALUES
    ('I32HARD-ISO', 'Issue 32 Isolation Fund', 'House H', 'Debt', 10, '2026-08-02'),
    ('I32HARD-ISO-DEST', 'Issue 32 Isolation Destination Fund', 'House H', 'Debt', 10, '2026-08-02')
  ON CONFLICT (scheme_code) DO UPDATE
  SET scheme_name = EXCLUDED.scheme_name;

  SELECT id INTO v_source_fund_id FROM public.mutual_funds WHERE scheme_code = 'I32HARD-ISO';
  SELECT id INTO v_dest_fund_id FROM public.mutual_funds WHERE scheme_code = 'I32HARD-ISO-DEST';

  INSERT INTO public.transactions (
    portfolio_id,
    folio_reference_id,
    mutual_fund_id,
    transaction_type,
    units,
    nav_at_transaction,
    amount,
    execution_date,
    registrar,
    source_row_number,
    source_attachment_sha256,
    registrar_transaction_id,
    registrar_transaction_code,
    transaction_direction
  ) VALUES (
    v_workspace_b_portfolio_id,
    v_folio_id,
    v_source_fund_id,
    'BUY',
    25,
    10,
    250,
    '2026-08-02',
    'CAMS',
    1,
    repeat('e', 64),
    'HISO-B-BUY-1',
    'BUY',
    'INFLOW'
  );

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
      folio_reference_id,
      status
    ) VALUES (
      '95600000-0000-0000-0000-000000000010',
      '95400000-0000-0000-0000-000000000001',
      '95300000-0000-0000-0000-000000000002',
      '95300000-0000-0000-0000-000000000002',
      'investor',
      'investor_portal',
      'I32HARD-ISO',
      'sell',
      10,
      v_folio_id,
      'pending_qualification'
    );
    RAISE EXCEPTION 'workspace B BUY authorized workspace A sell';
  EXCEPTION
    WHEN others THEN
      IF SQLERRM NOT LIKE '%scheme_not_held_in_selected_folio%' THEN
        RAISE;
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
      destination_scheme_code,
      type,
      amount,
      folio_reference_id,
      status
    ) VALUES (
      '95600000-0000-0000-0000-000000000011',
      '95400000-0000-0000-0000-000000000001',
      '95300000-0000-0000-0000-000000000002',
      '95300000-0000-0000-0000-000000000002',
      'investor',
      'investor_portal',
      'I32HARD-ISO',
      'I32HARD-ISO-DEST',
      'switch',
      10,
      v_folio_id,
      'pending_qualification'
    );
    RAISE EXCEPTION 'workspace B BUY authorized workspace A switch';
  EXCEPTION
    WHEN others THEN
      IF SQLERRM NOT LIKE '%scheme_not_held_in_selected_folio%' THEN
        RAISE;
      END IF;
  END;

  INSERT INTO public.transactions (
    portfolio_id,
    folio_reference_id,
    mutual_fund_id,
    transaction_type,
    units,
    nav_at_transaction,
    amount,
    execution_date,
    registrar,
    source_row_number,
    source_attachment_sha256,
    registrar_transaction_id,
    registrar_transaction_code,
    source_folio_reference_id
  ) VALUES (
    v_workspace_b_portfolio_id,
    v_folio_id,
    v_source_fund_id,
    'SWITCH',
    1,
    10,
    10,
    '2026-08-03',
    'CAMS',
    2,
    repeat('f', 64),
    'HISO-B-BAD-SWITCH',
    'SWITCHOUT',
    v_folio_id
  );

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
      folio_reference_id,
      status
    ) VALUES (
      '95600000-0000-0000-0000-000000000012',
      '95400000-0000-0000-0000-000000000001',
      '95300000-0000-0000-0000-000000000002',
      '95300000-0000-0000-0000-000000000002',
      'investor',
      'investor_portal',
      'I32HARD-ISO',
      'sell',
      10,
      v_folio_id,
      'pending_qualification'
    );
    RAISE EXCEPTION 'workspace B malformed switch blocked workspace A with the wrong result';
  EXCEPTION
    WHEN others THEN
      IF SQLERRM NOT LIKE '%scheme_not_held_in_selected_folio%' THEN
        RAISE;
      END IF;
  END;

  INSERT INTO public.transactions (
    portfolio_id,
    folio_reference_id,
    mutual_fund_id,
    transaction_type,
    units,
    nav_at_transaction,
    amount,
    execution_date,
    registrar,
    source_row_number,
    source_attachment_sha256,
    registrar_transaction_id,
    registrar_transaction_code,
    transaction_direction,
    source_folio_reference_id
  ) VALUES
    (v_workspace_a_portfolio_id, v_folio_id, v_source_fund_id, 'BUY', 10, 10, 100, '2026-08-04', 'CAMS', 3, repeat('a', 64), 'HISO-A-BUY-1', 'BUY', 'INFLOW', NULL),
    (v_workspace_a_portfolio_id, v_folio_id, v_source_fund_id, 'SELL', 2, 10, 20, '2026-08-05', 'CAMS', 4, repeat('b', 64), 'HISO-A-SELL-1', 'SELL', 'OUTFLOW', NULL),
    (v_workspace_a_portfolio_id, v_folio_id, v_source_fund_id, 'SWITCH', 3, 10, 30, '2026-08-06', 'CAMS', 5, repeat('c', 64), 'HISO-A-SWITCH-IN-1', 'SWITCHIN', 'INFLOW', v_folio_id),
    (v_workspace_a_portfolio_id, v_folio_id, v_source_fund_id, 'SWITCH', 4, 10, 40, '2026-08-07', 'CAMS', 6, repeat('d', 64), 'HISO-A-SWITCH-OUT-1', 'SWITCHOUT', 'OUTFLOW', v_folio_id);

  SELECT COALESCE(SUM(
    CASE
      WHEN transaction.transaction_type = 'BUY' THEN transaction.units
      WHEN transaction.transaction_type = 'SELL' THEN -transaction.units
      WHEN transaction.transaction_type = 'SWITCH' AND transaction.transaction_direction = 'INFLOW' THEN transaction.units
      WHEN transaction.transaction_type = 'SWITCH' AND transaction.transaction_direction = 'OUTFLOW' THEN -transaction.units
      ELSE 0
    END
  ), 0)
  INTO v_balance
  FROM public.transactions AS transaction
  WHERE transaction.portfolio_id = v_workspace_a_portfolio_id
    AND transaction.folio_reference_id = v_folio_id
    AND transaction.mutual_fund_id = v_source_fund_id;

  IF v_balance <> 7 THEN
    RAISE EXCEPTION 'workspace A isolated balance is wrong: %', v_balance;
  END IF;

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
    folio_reference_id,
    status
  ) VALUES (
    '95600000-0000-0000-0000-000000000013',
    '95400000-0000-0000-0000-000000000001',
    '95300000-0000-0000-0000-000000000002',
    '95300000-0000-0000-0000-000000000002',
    'investor',
    'investor_portal',
    'I32HARD-ISO',
    'sell',
    10,
    v_folio_id,
    'pending_qualification'
  );

  INSERT INTO public.order_requests (
    id,
    workspace_id,
    investor_profile_id,
    initiated_by_profile_id,
    initiated_by_role,
    initiation_channel,
    scheme_code,
    destination_scheme_code,
    type,
    amount,
    folio_reference_id,
    status
  ) VALUES (
    '95600000-0000-0000-0000-000000000014',
    '95400000-0000-0000-0000-000000000001',
    '95300000-0000-0000-0000-000000000002',
    '95300000-0000-0000-0000-000000000002',
    'investor',
    'investor_portal',
    'I32HARD-ISO',
    'I32HARD-ISO-DEST',
    'switch',
    10,
    v_folio_id,
    'pending_qualification'
  );
END;
$$;

SET ROLE service_role;
SELECT public.claim_cams_kfintech_ingestion_run(
  '95400000-0000-0000-0000-000000000001',
  '95700000-0000-0000-0000-000000000001',
  '95900000-0000-0000-0000-000000000910',
  'CAMS'
);

SELECT public.persist_cams_kfintech_statement_ingestion(
  '95400000-0000-0000-0000-000000000001',
  '95700000-0000-0000-0000-000000000001',
  '95900000-0000-0000-0000-000000000910',
  '95900000-0000-0000-0000-000000000911',
  'switch-provider-message',
  'switch-provider-attachment',
  'switch-attempt',
  'CAMS',
  repeat('b', 64),
  'ingested-documents',
  'active/workspace/switch-object',
  'application/x-dbase',
  'DBF',
  2048,
  '2026-08-02T00:00:00Z',
  pg_catalog.jsonb_build_array(
    pg_catalog.jsonb_build_object(
      'registrar', 'CAMS',
      'clientPan', 'HDRNG1234A',
      'investorName', 'Issue 32 Hardening Investor',
      'folioNumber', 'HSWITCH001',
      'schemeCode', 'I32HARD-SRC',
      'schemeName', 'Issue 32 Source Fund',
      'fundHouse', 'House H',
      'category', 'Debt',
      'transactionType', 'BUY',
      'transactionDirection', 'INFLOW',
      'registrarTransactionCode', 'BUY',
      'registrarTransactionId', 'HSWITCH-BUY-1',
      'units', 10,
      'nav', 10,
      'amount', 100,
      'date', '2026-08-02',
      'sourceRowNumber', 1
    ),
    pg_catalog.jsonb_build_object(
      'registrar', 'CAMS',
      'clientPan', 'HDRNG1234A',
      'investorName', 'Issue 32 Hardening Investor',
      'folioNumber', 'HSWITCH001',
      'schemeCode', 'I32HARD-SRC',
      'schemeName', 'Issue 32 Source Fund',
      'fundHouse', 'House H',
      'category', 'Debt',
      'transactionType', 'SWITCH',
      'transactionDirection', 'OUTFLOW',
      'registrarTransactionCode', 'SWITCHOUT',
      'registrarTransactionId', 'HSWITCH-OUT-1',
      'units', 4,
      'nav', 10,
      'amount', 40,
      'date', '2026-08-02',
      'sourceRowNumber', 2
    ),
    pg_catalog.jsonb_build_object(
      'registrar', 'CAMS',
      'clientPan', 'HDRNG1234A',
      'investorName', 'Issue 32 Hardening Investor',
      'folioNumber', 'HSWITCH001',
      'schemeCode', 'I32HARD-DEST',
      'schemeName', 'Issue 32 Destination Fund',
      'fundHouse', 'House H',
      'category', 'Debt',
      'transactionType', 'SWITCH',
      'transactionDirection', 'INFLOW',
      'registrarTransactionCode', 'SWITCHIN',
      'registrarTransactionId', 'HSWITCH-IN-1',
      'units', 4,
      'nav', 10,
      'amount', 40,
      'date', '2026-08-02',
      'sourceRowNumber', 3
    )
  )
);
RESET ROLE;

DO $$
DECLARE
  v_folio_id pg_catalog.uuid;
  v_portfolio_id pg_catalog.uuid;
  v_source_fund_id pg_catalog.uuid;
  v_dest_fund_id pg_catalog.uuid;
  v_balance pg_catalog.numeric;
BEGIN
  SELECT id INTO v_folio_id
  FROM public.folio_references
  WHERE registrar = 'CAMS'
    AND normalized_folio_number = 'HSWITCH001';

  SELECT id INTO v_source_fund_id FROM public.mutual_funds WHERE scheme_code = 'I32HARD-SRC';
  SELECT id INTO v_dest_fund_id FROM public.mutual_funds WHERE scheme_code = 'I32HARD-DEST';

  SELECT portfolio.id INTO v_portfolio_id
  FROM public.portfolio_folio_references AS mapping
  JOIN public.portfolios AS portfolio
    ON portfolio.id = mapping.portfolio_id
  WHERE mapping.folio_reference_id = v_folio_id
    AND portfolio.workspace_id = '95400000-0000-0000-0000-000000000001'
    AND portfolio.client_id = '95300000-0000-0000-0000-000000000002';

  SELECT COALESCE(SUM(
    CASE
      WHEN transaction.transaction_type = 'BUY' THEN transaction.units
      WHEN transaction.transaction_type = 'SELL' THEN -transaction.units
      WHEN transaction.transaction_type = 'SWITCH' AND transaction.transaction_direction = 'INFLOW' THEN transaction.units
      WHEN transaction.transaction_type = 'SWITCH' AND transaction.transaction_direction = 'OUTFLOW' THEN -transaction.units
      ELSE 0
    END
  ), 0)
  INTO v_balance
  FROM public.transactions AS transaction
  WHERE transaction.folio_reference_id = v_folio_id
    AND transaction.mutual_fund_id = v_source_fund_id;

  IF v_balance <> 6 THEN
    RAISE EXCEPTION 'source switch balance is wrong: %', v_balance;
  END IF;

  SELECT COALESCE(SUM(
    CASE
      WHEN transaction.transaction_type = 'BUY' THEN transaction.units
      WHEN transaction.transaction_type = 'SELL' THEN -transaction.units
      WHEN transaction.transaction_type = 'SWITCH' AND transaction.transaction_direction = 'INFLOW' THEN transaction.units
      WHEN transaction.transaction_type = 'SWITCH' AND transaction.transaction_direction = 'OUTFLOW' THEN -transaction.units
      ELSE 0
    END
  ), 0)
  INTO v_balance
  FROM public.transactions AS transaction
  WHERE transaction.folio_reference_id = v_folio_id
    AND transaction.mutual_fund_id = v_dest_fund_id;

  IF v_balance <> 4 THEN
    RAISE EXCEPTION 'destination switch balance is wrong: %', v_balance;
  END IF;

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
    folio_reference_id,
    status
  ) VALUES (
    '95600000-0000-0000-0000-000000000001',
    '95400000-0000-0000-0000-000000000001',
    '95300000-0000-0000-0000-000000000002',
    '95300000-0000-0000-0000-000000000002',
    'investor',
    'investor_portal',
    'I32HARD-SRC',
    'sell',
    10,
    v_folio_id,
    'pending_qualification'
  );

  INSERT INTO public.transactions (
    portfolio_id,
    folio_reference_id,
    mutual_fund_id,
    transaction_type,
    units,
    nav_at_transaction,
    amount,
    execution_date,
    registrar,
    source_row_number,
    source_attachment_sha256,
    registrar_transaction_id,
    registrar_transaction_code,
    transaction_direction,
    source_folio_reference_id
  ) VALUES (
    v_portfolio_id,
    v_folio_id,
    v_source_fund_id,
    'SWITCH',
    6,
    10,
    60,
    '2026-08-03',
    'CAMS',
    4,
    repeat('c', 64),
    'HSWITCH-OUT-2',
    'SWITCHOUT',
    'OUTFLOW',
    v_folio_id
  );

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
      folio_reference_id,
      status
    ) VALUES (
      '95600000-0000-0000-0000-000000000002',
      '95400000-0000-0000-0000-000000000001',
      '95300000-0000-0000-0000-000000000002',
      '95300000-0000-0000-0000-000000000002',
      'investor',
      'investor_portal',
      'I32HARD-SRC',
      'sell',
      10,
      v_folio_id,
      'pending_qualification'
    );
    RAISE EXCEPTION 'zero-balance over-sell was accepted';
  EXCEPTION
    WHEN others THEN
      IF SQLERRM NOT LIKE '%scheme_not_held_in_selected_folio%' THEN
        RAISE;
      END IF;
  END;

  INSERT INTO public.mutual_funds (scheme_code, scheme_name, fund_house, category, current_nav, nav_date)
  VALUES ('I32HARD-BAD-DIR', 'Issue 32 Bad Direction Fund', 'House H', 'Debt', 10, '2026-08-02')
  ON CONFLICT (scheme_code) DO NOTHING
  RETURNING id INTO v_source_fund_id;

  IF v_source_fund_id IS NULL THEN
    SELECT id INTO v_source_fund_id FROM public.mutual_funds WHERE scheme_code = 'I32HARD-BAD-DIR';
  END IF;

  INSERT INTO public.transactions (
    portfolio_id,
    folio_reference_id,
    mutual_fund_id,
    transaction_type,
    units,
    nav_at_transaction,
    amount,
    execution_date,
    registrar,
    source_row_number,
    source_attachment_sha256,
    registrar_transaction_id,
    registrar_transaction_code,
    source_folio_reference_id
  ) VALUES (
    v_portfolio_id,
    v_folio_id,
    v_source_fund_id,
    'SWITCH',
    1,
    10,
    10,
    '2026-08-04',
    'CAMS',
    5,
    repeat('d', 64),
    'HSWITCH-BAD-DIR',
    'SWITCHOUT',
    v_folio_id
  );

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
      folio_reference_id,
      status
    ) VALUES (
      '95600000-0000-0000-0000-000000000003',
      '95400000-0000-0000-0000-000000000001',
      '95300000-0000-0000-0000-000000000002',
      '95300000-0000-0000-0000-000000000002',
      'investor',
      'investor_portal',
      'I32HARD-BAD-DIR',
      'sell',
      10,
      v_folio_id,
      'pending_qualification'
    );
    RAISE EXCEPTION 'source-lineage switch without direction was accepted';
  EXCEPTION
    WHEN others THEN
      IF SQLERRM NOT LIKE '%unsupported_transaction_direction%' THEN
        RAISE;
      END IF;
  END;
END;
$$;

ROLLBACK;
