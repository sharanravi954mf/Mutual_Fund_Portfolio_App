-- Issue #89: Persist complete Sell and Switch order intent
-- Forward-only corrective migration for order_requests folio and destination scheme details.

BEGIN;

-- 1. Preflight Assertions
DO $$
BEGIN
  -- Verify core tables exist
  IF NOT EXISTS (SELECT 1 FROM pg_tables WHERE tablename = 'order_requests' AND schemaname = 'public') THEN
    RAISE EXCEPTION 'preflight_failed: table public.order_requests not found';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_tables WHERE tablename = 'folio_references' AND schemaname = 'public') THEN
    RAISE EXCEPTION 'preflight_failed: table public.folio_references not found';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_tables WHERE tablename = 'portfolio_folio_references' AND schemaname = 'public') THEN
    RAISE EXCEPTION 'preflight_failed: table public.portfolio_folio_references not found';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_tables WHERE tablename = 'transactions' AND schemaname = 'public') THEN
    RAISE EXCEPTION 'preflight_failed: table public.transactions not found';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_tables WHERE tablename = 'mutual_funds' AND schemaname = 'public') THEN
    RAISE EXCEPTION 'preflight_failed: table public.mutual_funds not found';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_tables WHERE tablename = 'workspace_audit_logs' AND schemaname = 'public') THEN
    RAISE EXCEPTION 'preflight_failed: table public.workspace_audit_logs not found';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_tables WHERE tablename = 'event_outbox' AND schemaname = 'public') THEN
    RAISE EXCEPTION 'preflight_failed: table public.event_outbox not found';
  END IF;
END $$;

-- 2. Schema extensions for Sell/Switch details and deterministic transaction folio linkage
ALTER TABLE public.order_requests
  ADD COLUMN IF NOT EXISTS folio_reference_id UUID REFERENCES public.folio_references(id) ON DELETE RESTRICT,
  ADD COLUMN IF NOT EXISTS destination_scheme_code TEXT;

ALTER TABLE public.transactions
  ADD COLUMN IF NOT EXISTS folio_reference_id UUID REFERENCES public.folio_references(id) ON DELETE RESTRICT;

WITH portfolio_folio_counts AS (
  SELECT
    pfr.portfolio_id,
    pg_catalog.count(DISTINCT pfr.folio_reference_id) AS folio_count
  FROM public.portfolio_folio_references AS pfr
  GROUP BY pfr.portfolio_id
),
deterministic_portfolio_folios AS (
  SELECT
    pfr.portfolio_id,
    pfr.folio_reference_id
  FROM public.portfolio_folio_references AS pfr
  JOIN portfolio_folio_counts AS pfc
    ON pfc.portfolio_id = pfr.portfolio_id
  WHERE pfc.folio_count = 1
)
UPDATE public.transactions AS transaction_row
SET folio_reference_id = deterministic_portfolio_folios.folio_reference_id
FROM deterministic_portfolio_folios
WHERE transaction_row.folio_reference_id IS NULL
  AND transaction_row.portfolio_id = deterministic_portfolio_folios.portfolio_id;

DO $$
DECLARE
  v_unmapped_transactions pg_catalog.int8;
  v_inconsistent_transactions pg_catalog.int8;
BEGIN
  SELECT pg_catalog.count(*) INTO v_unmapped_transactions
  FROM public.transactions AS transaction_row
  WHERE transaction_row.folio_reference_id IS NULL;

  IF v_unmapped_transactions > 0 THEN
    RAISE EXCEPTION
      'transaction_folio_reference_backfill_required: % unmapped transaction rows',
      v_unmapped_transactions;
  END IF;

  SELECT pg_catalog.count(*) INTO v_inconsistent_transactions
  FROM public.transactions AS transaction_row
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.portfolio_folio_references AS pfr
    WHERE pfr.portfolio_id = transaction_row.portfolio_id
      AND pfr.folio_reference_id = transaction_row.folio_reference_id
  );

  IF v_inconsistent_transactions > 0 THEN
    RAISE EXCEPTION
      'transaction_folio_reference_mapping_missing: % inconsistent transaction rows',
      v_inconsistent_transactions;
  END IF;
END
$$;

ALTER TABLE public.transactions
  ALTER COLUMN folio_reference_id SET NOT NULL;

CREATE INDEX IF NOT EXISTS idx_transactions_folio_scheme
  ON public.transactions(folio_reference_id, mutual_fund_id);

CREATE OR REPLACE FUNCTION public.validate_transaction_folio_reference_contract()
RETURNS trigger AS $$
BEGIN
  IF NEW.folio_reference_id IS NULL THEN
    RAISE EXCEPTION 'transaction_folio_reference_required';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.portfolio_folio_references AS pfr
    WHERE pfr.portfolio_id = NEW.portfolio_id
      AND pfr.folio_reference_id = NEW.folio_reference_id
  ) THEN
    RAISE EXCEPTION 'transaction_folio_reference_not_mapped_to_portfolio';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

DROP TRIGGER IF EXISTS validate_transaction_folio_reference_contract
  ON public.transactions;
CREATE TRIGGER validate_transaction_folio_reference_contract
  BEFORE INSERT OR UPDATE OF portfolio_id, folio_reference_id
  ON public.transactions
  FOR EACH ROW
  EXECUTE FUNCTION public.validate_transaction_folio_reference_contract();

REVOKE ALL ON FUNCTION public.validate_transaction_folio_reference_contract() FROM PUBLIC;

CREATE OR REPLACE FUNCTION public.process_cams_records(records pg_catalog.jsonb)
RETURNS void AS $$
DECLARE
  rec pg_catalog.jsonb;
  p_id pg_catalog.uuid;
  f_id pg_catalog.uuid;
  port_id pg_catalog.uuid;
  folio_id pg_catalog.uuid;
  existing_st_id pg_catalog.uuid;
  existing_tx_id pg_catalog.uuid;
  normalized_pan pg_catalog.text;
  pan_hmac pg_catalog.bytea;
  registrar_source pg_catalog.text;
  normalized_folio pg_catalog.text;
  source_folio_masked pg_catalog.text;
  v_workspace_id pg_catalog.uuid;
BEGIN
  FOR rec IN SELECT * FROM pg_catalog.jsonb_array_elements(records) LOOP
    SELECT statement.id INTO existing_st_id
    FROM public.cams_statements AS statement
    WHERE statement.foliochk = (rec->>'foliochk')
      AND statement.product = (rec->>'product')
      AND statement.rep_date = (rec->>'rep_date')::pg_catalog.date
      AND statement.clos_bal = (rec->>'clos_bal')::pg_catalog.numeric
      AND statement.rupee_bal = (rec->>'rupee_bal')::pg_catalog.numeric
    LIMIT 1;

    IF existing_st_id IS NULL THEN
      INSERT INTO public.cams_statements (
        foliochk, inv_name, address1, address2, address3, city, pincode,
        product, sch_name, rep_date, clos_bal, rupee_bal, email, mobile_no,
        bank_name, branch, ac_type, ac_no, ifsc_code, nom_name, relation, nom_percen
      ) VALUES (
        rec->>'foliochk', rec->>'inv_name', rec->>'address1', rec->>'address2', rec->>'address3',
        rec->>'city', rec->>'pincode', rec->>'product', rec->>'sch_name',
        (rec->>'rep_date')::pg_catalog.date, (rec->>'clos_bal')::pg_catalog.numeric,
        (rec->>'rupee_bal')::pg_catalog.numeric, rec->>'email', rec->>'mobile_no',
        rec->>'bank_name', rec->>'branch', rec->>'ac_type', rec->>'ac_no',
        rec->>'ifsc_code', rec->>'nom_name', rec->>'relation',
        (rec->>'nom_percen')::pg_catalog.numeric
      );
    END IF;

    normalized_pan := public.normalize_pan(rec->>'clientPan');
    IF normalized_pan IS NULL THEN
      RAISE EXCEPTION 'imported_record_invalid_pan';
    END IF;

    pan_hmac := extensions.hmac(normalized_pan, public.pan_lookup_hmac_key(), 'sha256');
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(pg_catalog.encode(pan_hmac, 'hex'), 0));

    registrar_source := CASE pg_catalog.upper(COALESCE(rec->>'registrar', ''))
      WHEN 'KFINTECH' THEN 'KFINTECH'
      WHEN 'CAMS' THEN 'CAMS'
      ELSE 'CAMS'
    END;

    normalized_folio := pg_catalog.upper(
      pg_catalog.regexp_replace(COALESCE(rec->>'foliochk', ''), '[^A-Za-z0-9]', '', 'g')
    );
    IF normalized_folio = '' THEN
      RAISE EXCEPTION 'transaction_folio_reference_required';
    END IF;

    source_folio_masked := CASE
      WHEN pg_catalog.length(normalized_folio) > 3 THEN pg_catalog.left(normalized_folio, 3) || '***'
      ELSE '***'
    END;

    INSERT INTO public.folio_references (
      registrar,
      normalized_folio_number,
      amc_identity,
      source_folio_masked
    ) VALUES (
      registrar_source,
      normalized_folio,
      COALESCE(NULLIF(rec->>'fundHouse', ''), NULLIF(rec->>'product', ''), 'UNKNOWN'),
      source_folio_masked
    )
    ON CONFLICT (registrar, normalized_folio_number) DO NOTHING;

    SELECT folio.id INTO folio_id
    FROM public.folio_references AS folio
    WHERE folio.registrar = registrar_source
      AND folio.normalized_folio_number = normalized_folio;

    IF folio_id IS NULL THEN
      RAISE EXCEPTION 'transaction_folio_reference_resolution_failed';
    END IF;

    SELECT pan_record.profile_id INTO p_id
    FROM public.profile_pan_records AS pan_record
    WHERE pan_record.pan_lookup_hmac = pan_hmac
      AND pan_record.status IN ('OBSERVED', 'VERIFIED')
    ORDER BY pan_record.created_at ASC
    LIMIT 1;

    IF p_id IS NULL THEN
      INSERT INTO public.profiles (id, full_name, role)
      VALUES (pg_catalog.gen_random_uuid(), rec->>'investorName', 'client')
      RETURNING id INTO p_id;
    END IF;

    INSERT INTO public.profile_pan_records (
      profile_id, pan_ciphertext, pan_lookup_hmac, masked_pan, source, source_system, status
    ) VALUES (
      p_id,
      extensions.pgp_sym_encrypt(normalized_pan, public.pan_encryption_key(), 'cipher-algo=aes256, compress-algo=0'),
      pan_hmac,
      public.mask_pan(normalized_pan),
      'IMPORT',
      registrar_source,
      'OBSERVED'
    ) ON CONFLICT (profile_id, pan_lookup_hmac) WHERE pan_lookup_hmac IS NOT NULL DO NOTHING;

    INSERT INTO public.mutual_funds (
      scheme_code, scheme_name, fund_house, category, current_nav, nav_date
    ) VALUES (
      rec->>'schemeCode',
      rec->>'schemeName',
      COALESCE(rec->>'fundHouse', 'Mutual Fund'),
      COALESCE(rec->>'category', 'Mutual Fund'),
      (rec->>'nav')::pg_catalog.numeric,
      (rec->>'date')::pg_catalog.date
    ) ON CONFLICT (scheme_code) DO UPDATE SET
      scheme_name = excluded.scheme_name,
      current_nav = excluded.current_nav,
      nav_date = excluded.nav_date
    RETURNING id INTO f_id;

    SELECT pfr.portfolio_id INTO port_id
    FROM public.portfolio_folio_references AS pfr
    JOIN public.portfolios AS portfolio
      ON portfolio.id = pfr.portfolio_id
    WHERE portfolio.client_id = p_id
      AND pfr.folio_reference_id = folio_id
    ORDER BY portfolio.last_updated DESC
    LIMIT 1;

    IF port_id IS NULL THEN
      SELECT membership.workspace_id INTO v_workspace_id
      FROM public.workspace_memberships AS membership
      WHERE membership.profile_id = p_id
        AND membership.role = 'investor'
        AND membership.status = 'active'
      ORDER BY membership.created_at ASC
      LIMIT 1;

      INSERT INTO public.portfolios (
        client_id, workspace_id, total_invested_value, current_market_value
      ) VALUES (
        p_id, v_workspace_id, 0.00, 0.00
      )
      RETURNING id INTO port_id;

      INSERT INTO public.portfolio_folio_references (portfolio_id, folio_reference_id)
      VALUES (port_id, folio_id);
    END IF;

    SELECT transaction_row.id INTO existing_tx_id
    FROM public.transactions AS transaction_row
    WHERE transaction_row.portfolio_id = port_id
      AND transaction_row.folio_reference_id = folio_id
      AND transaction_row.mutual_fund_id = f_id
      AND transaction_row.transaction_type = (rec->>'transactionType')
      AND transaction_row.units = (rec->>'units')::pg_catalog.numeric
      AND transaction_row.amount = (rec->>'amount')::pg_catalog.numeric
      AND transaction_row.execution_date = (rec->>'date')::pg_catalog.date
    LIMIT 1;

    IF existing_tx_id IS NULL THEN
      INSERT INTO public.transactions (
        portfolio_id,
        folio_reference_id,
        mutual_fund_id,
        transaction_type,
        units,
        nav_at_transaction,
        amount,
        execution_date
      ) VALUES (
        port_id,
        folio_id,
        f_id,
        rec->>'transactionType',
        (rec->>'units')::pg_catalog.numeric,
        (rec->>'nav')::pg_catalog.numeric,
        (rec->>'amount')::pg_catalog.numeric,
        (rec->>'date')::pg_catalog.date
      );

      PERFORM public.recalculate_portfolio_value(port_id);
    END IF;
  END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

REVOKE ALL ON FUNCTION public.process_cams_records(pg_catalog.jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.process_cams_records(pg_catalog.jsonb) FROM anon;
REVOKE ALL ON FUNCTION public.process_cams_records(pg_catalog.jsonb) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.process_cams_records(pg_catalog.jsonb) TO service_role;

-- 3. Constraints for Amount/Units and Type-specific fields
ALTER TABLE public.order_requests
  DROP CONSTRAINT IF EXISTS order_requests_amount_or_units;

ALTER TABLE public.order_requests
  ADD CONSTRAINT order_requests_amount_xor_units CHECK (
    ((amount IS NOT NULL AND units IS NULL) OR (amount IS NULL AND units IS NOT NULL))
  );

ALTER TABLE public.order_requests
  ADD CONSTRAINT order_requests_amount_no_nan CHECK (
    amount IS NULL OR (amount > 0 AND amount <> 'NaN'::numeric)
  );

ALTER TABLE public.order_requests
  ADD CONSTRAINT order_requests_units_no_nan CHECK (
    units IS NULL OR (units > 0 AND units <> 'NaN'::numeric)
  );

ALTER TABLE public.order_requests
  ADD CONSTRAINT order_requests_type_conditional_fields CHECK (
    (type = 'buy'::public.order_type AND folio_reference_id IS NULL AND destination_scheme_code IS NULL)
    OR (type = 'sell'::public.order_type AND folio_reference_id IS NOT NULL AND destination_scheme_code IS NULL)
    OR (type = 'switch'::public.order_type AND folio_reference_id IS NOT NULL AND destination_scheme_code IS NOT NULL AND destination_scheme_code <> scheme_code)
  );

-- 4. Redefine validate_order_request_canonical_contract trigger function to add holdings and relationship checks
CREATE OR REPLACE FUNCTION public.validate_order_request_canonical_contract()
RETURNS trigger AS $$
DECLARE
  v_caller_user_id pg_catalog.uuid;
  v_caller_profile_id pg_catalog.uuid;
  v_is_service_role pg_catalog.bool;
  v_is_api_insert pg_catalog.bool;
  v_request_claims pg_catalog.text;
  v_request_role pg_catalog.text;
BEGIN
  v_request_claims := NULLIF(pg_catalog.current_setting('request.jwt.claims', true), '');
  v_request_role := NULLIF(pg_catalog.current_setting('request.jwt.claim.role', true), '');

  IF v_request_role IS NULL AND v_request_claims IS NOT NULL THEN
    v_request_role := NULLIF((v_request_claims::pg_catalog.jsonb ->> 'role'), '');
  END IF;

  v_caller_user_id := auth.uid();
  v_is_service_role := COALESCE(auth.role(), v_request_role, '') = 'service_role';
  v_is_api_insert := TG_OP = 'INSERT'
    AND (
      v_caller_user_id IS NOT NULL
      OR v_request_role IN ('anon', 'authenticated', 'service_role')
      OR v_is_service_role
    );

  IF v_is_api_insert THEN
    IF NEW.status <> 'pending_qualification'::public.order_status THEN
      RAISE EXCEPTION 'invalid_initial_order_status';
    END IF;

    IF NEW.reviewed_by IS NOT NULL
       OR NEW.reviewed_by_profile_id IS NOT NULL
       OR NEW.reviewed_at IS NOT NULL THEN
      RAISE EXCEPTION 'review_metadata_requires_qualification';
    END IF;
  END IF;

  IF NEW.reviewed_by IS NOT NULL
     AND NEW.reviewed_by_profile_id IS NOT NULL
     AND NEW.reviewed_by <> NEW.reviewed_by_profile_id THEN
    IF TG_OP = 'INSERT' THEN
      RAISE EXCEPTION 'reviewer_profile_mismatch';
    ELSIF OLD.reviewed_by IS NULL
          AND OLD.reviewed_by_profile_id IS NULL
          AND OLD.reviewed_at IS NULL THEN
      RAISE EXCEPTION 'reviewer_profile_mismatch';
    END IF;
  END IF;

  IF TG_OP = 'INSERT' THEN
    IF NEW.status = 'draft'::public.order_status THEN
      RETURN NEW;
    END IF;

    IF v_caller_user_id IS NOT NULL THEN
      IF NEW.reviewed_by IS NOT NULL
         OR NEW.reviewed_by_profile_id IS NOT NULL
         OR NEW.reviewed_at IS NOT NULL THEN
        RAISE EXCEPTION 'review_metadata_requires_qualification';
      END IF;

      v_caller_profile_id := public.current_user_profile_id();

      IF v_caller_profile_id IS NULL THEN
        RAISE EXCEPTION 'profile_resolution_failed';
      END IF;

      IF NEW.initiated_by_profile_id IS NULL THEN
        NEW.initiated_by_profile_id := v_caller_profile_id;
      ELSIF NEW.initiated_by_profile_id <> v_caller_profile_id THEN
        RAISE EXCEPTION 'initiator_profile_mismatch';
      END IF;

      IF public.is_platform_admin() THEN
        RAISE EXCEPTION 'not_authorized';
      END IF;

      IF v_caller_profile_id = NEW.investor_profile_id THEN
        IF NEW.initiated_by_role IS NULL THEN
          NEW.initiated_by_role := 'investor';
        ELSIF NEW.initiated_by_role <> 'investor' THEN
          RAISE EXCEPTION 'invalid_order_initiation_metadata';
        END IF;

        IF NEW.initiation_channel IS NULL THEN
          NEW.initiation_channel := 'investor_portal';
        ELSIF NEW.initiation_channel <> 'investor_portal' THEN
          RAISE EXCEPTION 'invalid_order_initiation_metadata';
        END IF;
      ELSIF public.is_order_mfd_profile(NEW.workspace_id, v_caller_profile_id) THEN
        IF NEW.initiated_by_role IS NULL THEN
          NEW.initiated_by_role := 'advisor';
        ELSIF NEW.initiated_by_role <> 'advisor' THEN
          RAISE EXCEPTION 'invalid_order_initiation_metadata';
        END IF;

        IF NEW.initiation_channel IS NULL THEN
          NEW.initiation_channel := 'advisor_portal';
        ELSIF NEW.initiation_channel <> 'advisor_portal' THEN
          RAISE EXCEPTION 'invalid_order_initiation_metadata';
        END IF;
      ELSE
        RAISE EXCEPTION 'order_initiator_not_authorized';
      END IF;
    ELSIF v_is_service_role THEN
      IF NEW.initiated_by_profile_id IS NULL
         OR NEW.initiated_by_role IS NULL
         OR NEW.initiation_channel IS NULL THEN
        RAISE EXCEPTION 'order_request_canonical_metadata_missing';
      END IF;
    ELSIF COALESCE(pg_catalog.current_setting('role', true), '') NOT IN ('anon', 'authenticated', 'service_role') THEN
      IF NEW.initiated_by_profile_id IS NULL
         OR NEW.initiated_by_role IS NULL
         OR NEW.initiation_channel IS NULL THEN
        RAISE EXCEPTION 'order_request_canonical_metadata_missing';
      END IF;

      IF NEW.reviewed_by_profile_id IS NULL AND NEW.reviewed_by IS NOT NULL THEN
        NEW.reviewed_by_profile_id := NEW.reviewed_by;
      ELSIF NEW.reviewed_by IS NULL AND NEW.reviewed_by_profile_id IS NOT NULL THEN
        NEW.reviewed_by := NEW.reviewed_by_profile_id;
      END IF;

      IF NEW.reviewed_by_profile_id IS NOT NULL AND NEW.reviewed_at IS NULL THEN
        RAISE EXCEPTION 'reviewed_at_required';
      ELSIF NEW.reviewed_by_profile_id IS NULL AND NEW.reviewed_at IS NOT NULL THEN
        RAISE EXCEPTION 'reviewer_profile_required';
      END IF;
    ELSE
      RAISE EXCEPTION 'profile_resolution_failed';
    END IF;
  ELSE
    IF NEW.workspace_id IS DISTINCT FROM OLD.workspace_id
       OR NEW.investor_profile_id IS DISTINCT FROM OLD.investor_profile_id
       OR NEW.initiated_by_profile_id IS DISTINCT FROM OLD.initiated_by_profile_id
       OR NEW.initiated_by_role IS DISTINCT FROM OLD.initiated_by_role
       OR NEW.initiation_channel IS DISTINCT FROM OLD.initiation_channel THEN
      RAISE EXCEPTION 'order_initiation_metadata_immutable';
    END IF;

    IF OLD.reviewed_by IS NOT NULL
       OR OLD.reviewed_by_profile_id IS NOT NULL
       OR OLD.reviewed_at IS NOT NULL THEN
      IF NEW.reviewed_by IS DISTINCT FROM OLD.reviewed_by
         OR NEW.reviewed_by_profile_id IS DISTINCT FROM OLD.reviewed_by_profile_id
         OR NEW.reviewed_at IS DISTINCT FROM OLD.reviewed_at THEN
        RAISE EXCEPTION 'review_metadata_immutable';
      END IF;
    ELSIF NEW.reviewed_by IS NOT NULL
          OR NEW.reviewed_by_profile_id IS NOT NULL
          OR NEW.reviewed_at IS NOT NULL THEN
      IF NEW.reviewed_by IS NULL
         OR NEW.reviewed_by_profile_id IS NULL
         OR NEW.reviewed_at IS NULL THEN
        RAISE EXCEPTION 'review_metadata_incomplete';
      END IF;

      IF OLD.status <> 'pending_review'::public.order_status
         OR NEW.status NOT IN ('approved'::public.order_status, 'rejected'::public.order_status) THEN
        RAISE EXCEPTION 'review_metadata_requires_qualification';
      END IF;

      IF v_caller_user_id IS NOT NULL THEN
        v_caller_profile_id := public.current_user_profile_id();

        IF v_caller_profile_id IS NULL THEN
          RAISE EXCEPTION 'profile_resolution_failed';
        END IF;

        IF NEW.reviewed_by_profile_id <> v_caller_profile_id THEN
          RAISE EXCEPTION 'reviewer_profile_mismatch';
        END IF;

        IF public.is_platform_admin() OR NOT public.is_order_mfd_profile(NEW.workspace_id, v_caller_profile_id) THEN
          RAISE EXCEPTION 'not_authorized';
        END IF;
      ELSIF NOT v_is_service_role THEN
        RAISE EXCEPTION 'profile_resolution_failed';
      END IF;
    ELSIF OLD.status = 'pending_review'::public.order_status
          AND NEW.status IN ('approved'::public.order_status, 'rejected'::public.order_status) THEN
      RAISE EXCEPTION 'review_metadata_requires_qualification';
    END IF;
  END IF;

  IF NEW.workspace_id IS NULL
     OR NEW.investor_profile_id IS NULL
     OR NEW.initiated_by_profile_id IS NULL
     OR NEW.initiated_by_role IS NULL
     OR NEW.initiation_channel IS NULL THEN
    RAISE EXCEPTION 'order_request_canonical_metadata_missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.workspace_memberships AS wm
    WHERE wm.workspace_id = NEW.workspace_id
      AND wm.profile_id = NEW.investor_profile_id
      AND wm.role = 'investor'
      AND wm.status = 'active'
  ) THEN
    RAISE EXCEPTION 'investor_workspace_relationship_required';
  END IF;

  IF NEW.initiated_by_role = 'investor' THEN
    IF NEW.initiation_channel <> 'investor_portal' THEN
      RAISE EXCEPTION 'invalid_order_initiation_metadata';
    END IF;

    IF NEW.initiated_by_profile_id <> NEW.investor_profile_id THEN
      RAISE EXCEPTION 'investor_initiator_mismatch';
    END IF;
  ELSIF NEW.initiated_by_role = 'advisor' THEN
    IF NEW.initiation_channel <> 'advisor_portal' THEN
      RAISE EXCEPTION 'invalid_order_initiation_metadata';
    END IF;

    IF NOT public.is_order_mfd_profile(NEW.workspace_id, NEW.initiated_by_profile_id) THEN
      RAISE EXCEPTION 'advisor_workspace_relationship_required';
    END IF;
  ELSE
    RAISE EXCEPTION 'invalid_order_initiation_metadata';
  END IF;

  IF NEW.reviewed_by_profile_id IS NOT NULL THEN
    IF NEW.reviewed_at IS NULL THEN
      RAISE EXCEPTION 'reviewed_at_required';
    END IF;
    IF NOT public.is_order_mfd_profile(NEW.workspace_id, NEW.reviewed_by_profile_id) THEN
      RAISE EXCEPTION 'reviewer_workspace_relationship_required';
    END IF;
  ELSIF NEW.reviewed_at IS NOT NULL THEN
    RAISE EXCEPTION 'reviewer_profile_required';
  END IF;

  -- Type-specific folio and holdings validations for Sell and Switch
  IF NEW.type IN ('sell'::public.order_type, 'switch'::public.order_type) THEN
    IF NEW.folio_reference_id IS NULL THEN
      RAISE EXCEPTION 'folio_reference_required_for_sell_switch';
    END IF;

    -- Verify source-folio ownership by beneficiary investor in exact workspace
    IF NOT EXISTS (
      SELECT 1
      FROM public.portfolio_folio_references pfr
      JOIN public.portfolios p ON p.id = pfr.portfolio_id
      WHERE pfr.folio_reference_id = NEW.folio_reference_id
        AND p.client_id = NEW.investor_profile_id
        AND p.workspace_id = NEW.workspace_id
    ) THEN
      RAISE EXCEPTION 'folio_not_owned_by_investor_in_workspace';
    END IF;

    -- Verify scheme is genuinely held by the exact selected source folio (units > 0)
    IF (
      SELECT COALESCE(SUM(
        CASE
          WHEN t.transaction_type = 'BUY' THEN t.units
          WHEN t.transaction_type = 'SELL' THEN -t.units
          ELSE 0
        END
      ), 0)
      FROM public.transactions t
      WHERE t.folio_reference_id = NEW.folio_reference_id
        AND t.mutual_fund_id = (SELECT id FROM public.mutual_funds WHERE scheme_code = NEW.scheme_code LIMIT 1)
    ) <= 0 THEN
      RAISE EXCEPTION 'scheme_not_held_in_selected_folio';
    END IF;
  END IF;

  IF NEW.destination_scheme_code IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.mutual_funds WHERE scheme_code = NEW.destination_scheme_code
    ) THEN
      RAISE EXCEPTION 'destination_scheme_not_found';
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

-- 5. Redefine log_order_request_initiation_audit trigger function to include complete order intent in the payload
CREATE OR REPLACE FUNCTION public.log_order_request_initiation_audit()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.workspace_audit_logs (
    workspace_id,
    actor_id,
    actor_profile_id,
    actor_type,
    action,
    event_type,
    target_type,
    entity_type,
    target_id,
    entity_id,
    new_state,
    payload
  ) VALUES (
    NEW.workspace_id,
    NEW.initiated_by_profile_id,
    NEW.initiated_by_profile_id,
    NEW.initiated_by_role,
    'order.initiated',
    'order.initiated',
    'order_requests',
    'order_requests',
    NEW.id,
    NEW.id,
    NEW.status::pg_catalog.text,
    pg_catalog.jsonb_build_object(
      'order_id', NEW.id,
      'workspace_id', NEW.workspace_id,
      'investor_profile_id', NEW.investor_profile_id,
      'type', NEW.type,
      'scheme_code', NEW.scheme_code,
      'folio_reference_id', NEW.folio_reference_id,
      'destination_scheme_code', NEW.destination_scheme_code,
      'amount', NEW.amount,
      'units', NEW.units,
      'initiated_by_profile_id', NEW.initiated_by_profile_id,
      'initiated_by_role', NEW.initiated_by_role,
      'initiation_channel', NEW.initiation_channel,
      'status', NEW.status
    )
  );

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

-- 6. Redefine trigger_order_outbox_event trigger function to include complete order intent in the event_outbox payload
CREATE OR REPLACE FUNCTION public.trigger_order_outbox_event()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.event_outbox (event_type, entity_id, entity_type, payload, status)
  VALUES (
    'order.created',
    NEW.id,
    'order_request',
    pg_catalog.jsonb_build_object(
      'order_id', NEW.id,
      'workspace_id', NEW.workspace_id,
      'investor_profile_id', NEW.investor_profile_id,
      'type', NEW.type,
      'scheme_code', NEW.scheme_code,
      'folio_reference_id', NEW.folio_reference_id,
      'destination_scheme_code', NEW.destination_scheme_code,
      'amount', NEW.amount,
      'units', NEW.units,
      'initiated_by_profile_id', NEW.initiated_by_profile_id,
      'initiated_by_role', NEW.initiated_by_role,
      'initiation_channel', NEW.initiation_channel,
      'status', NEW.status
    ),
    'pending'
  )
  ON CONFLICT (entity_type, entity_id, event_type) WHERE event_type = 'order.created' DO NOTHING;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

-- 7. Redefine cancel_order RPC with explicit column projection in RETURNING (no SELECT *)
CREATE OR REPLACE FUNCTION public.cancel_order(
  p_order_id pg_catalog.uuid,
  p_reason pg_catalog.text DEFAULT null
)
RETURNS public.order_requests AS $$
DECLARE
  v_workspace_id pg_catalog.uuid;
  v_investor_profile_id pg_catalog.uuid;
  v_current_status public.order_status;
  v_current_profile_id pg_catalog.uuid;
  v_cancellation_reason pg_catalog.text;
  v_is_workspace_owner pg_catalog.bool;
  v_is_active_advisor pg_catalog.bool;
  v_order public.order_requests;
BEGIN
  SELECT
    o.workspace_id,
    o.investor_profile_id,
    o.status
  INTO
    v_workspace_id,
    v_investor_profile_id,
    v_current_status
  FROM public.order_requests AS o
  WHERE o.id = p_order_id
  FOR UPDATE;

  IF v_workspace_id IS NULL THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  v_current_profile_id := public.current_user_profile_id();
  IF v_current_profile_id IS NULL THEN
    RAISE EXCEPTION 'profile_resolution_failed';
  END IF;

  IF public.is_platform_admin() THEN
    RAISE EXCEPTION 'not_authorized';
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.workspaces AS w
    JOIN public.workspace_memberships AS wm
      ON wm.workspace_id = w.id
     AND wm.profile_id = v_current_profile_id
     AND wm.role = 'admin'
     AND wm.status = 'active'
    WHERE w.id = v_workspace_id
      AND w.owner_profile_id = v_current_profile_id
  ) INTO v_is_workspace_owner;

  SELECT EXISTS (
    SELECT 1
    FROM public.workspace_memberships AS wm
    WHERE wm.workspace_id = v_workspace_id
      AND wm.profile_id = v_current_profile_id
      AND wm.role = 'advisor'
      AND wm.status = 'active'
  ) INTO v_is_active_advisor;

  IF v_investor_profile_id = v_current_profile_id THEN
    -- Investor-owner cancellation path.
  ELSIF v_is_workspace_owner OR v_is_active_advisor THEN
    -- Authorised MFD-side cancellation path.
  ELSE
    RAISE EXCEPTION 'not_authorized';
  END IF;

  IF v_current_status = 'cancelled' THEN
    RAISE EXCEPTION 'already_cancelled';
  END IF;

  IF v_current_status NOT IN ('pending_qualification', 'pending_review') THEN
    RAISE EXCEPTION 'invalid_cancellation_state';
  END IF;

  v_cancellation_reason := COALESCE(p_reason, 'Cancelled by user');

  UPDATE public.order_requests AS o
  SET status = 'cancelled',
      cancellation_reason = v_cancellation_reason,
      cancelled_at = pg_catalog.now(),
      updated_at = pg_catalog.now()
  WHERE o.id = p_order_id
  RETURNING
    id,
    workspace_id,
    investor_profile_id,
    scheme_code,
    type,
    amount,
    units,
    status,
    auto_approved,
    triggered_rule_id,
    triggered_rule_version,
    reviewed_by,
    reviewed_at,
    rejection_reason,
    created_at,
    updated_at,
    auto_approval_correlation_id,
    cancellation_reason,
    cancelled_at,
    initiated_by_profile_id,
    initiated_by_role,
    initiation_channel,
    reviewed_by_profile_id,
    folio_reference_id,
    destination_scheme_code
  INTO v_order;

  INSERT INTO public.workspace_audit_logs (
    workspace_id,
    actor_id,
    actor_profile_id,
    actor_type,
    action,
    target_type,
    entity_type,
    target_id,
    entity_id,
    reason,
    previous_state,
    new_state,
    payload
  ) VALUES (
    v_workspace_id,
    v_current_profile_id,
    v_current_profile_id,
    CASE
      WHEN v_investor_profile_id = v_current_profile_id THEN 'investor'
      ELSE 'advisor'
    END,
    'order.cancelled',
    'order_requests',
    'order_requests',
    p_order_id,
    p_order_id,
    v_cancellation_reason,
    v_current_status::pg_catalog.text,
    'cancelled',
    pg_catalog.jsonb_build_object(
      'reason', v_cancellation_reason,
      'previous_status', v_current_status,
      'new_status', 'cancelled',
      'investor_profile_id', v_investor_profile_id
    )
  );

  RETURN v_order;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

REVOKE ALL ON FUNCTION public.cancel_order(pg_catalog.uuid, pg_catalog.text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.cancel_order(pg_catalog.uuid, pg_catalog.text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_order(pg_catalog.uuid, pg_catalog.text) TO authenticated;

-- 8. Redefine qualify_order RPC with explicit column projection in RETURNING (no SELECT *)
CREATE OR REPLACE FUNCTION public.qualify_order(
  p_order_id pg_catalog.uuid,
  p_decision public.order_status,
  p_rejection_reason pg_catalog.text DEFAULT null
)
RETURNS public.order_requests AS $$
DECLARE
  v_workspace_id pg_catalog.uuid;
  v_investor_profile_id pg_catalog.uuid;
  v_initiated_by_profile_id pg_catalog.uuid;
  v_current_status public.order_status;
  v_current_profile_id pg_catalog.uuid;
  v_order public.order_requests;
BEGIN
  SELECT
    o.workspace_id,
    o.investor_profile_id,
    o.initiated_by_profile_id,
    o.status
  INTO
    v_workspace_id,
    v_investor_profile_id,
    v_initiated_by_profile_id,
    v_current_status
  FROM public.order_requests AS o
  WHERE o.id = p_order_id
  FOR UPDATE;

  IF v_workspace_id IS NULL THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  IF v_current_status <> 'pending_review' THEN
    RAISE EXCEPTION 'invalid_qualification_state';
  END IF;

  IF p_decision NOT IN ('approved', 'rejected') THEN
    RAISE EXCEPTION 'invalid_qualification_decision';
  END IF;

  v_current_profile_id := public.current_user_profile_id();
  IF v_current_profile_id IS NULL THEN
    RAISE EXCEPTION 'profile_resolution_failed';
  END IF;

  IF public.is_platform_admin() OR NOT public.is_order_mfd_profile(v_workspace_id, v_current_profile_id) THEN
    RAISE EXCEPTION 'not_authorized';
  END IF;

  UPDATE public.order_requests AS o
  SET status = p_decision,
      reviewed_by = v_current_profile_id,
      reviewed_by_profile_id = v_current_profile_id,
      reviewed_at = pg_catalog.now(),
      rejection_reason = p_rejection_reason,
      updated_at = pg_catalog.now()
  WHERE o.id = p_order_id
  RETURNING
    id,
    workspace_id,
    investor_profile_id,
    scheme_code,
    type,
    amount,
    units,
    status,
    auto_approved,
    triggered_rule_id,
    triggered_rule_version,
    reviewed_by,
    reviewed_at,
    rejection_reason,
    created_at,
    updated_at,
    auto_approval_correlation_id,
    cancellation_reason,
    cancelled_at,
    initiated_by_profile_id,
    initiated_by_role,
    initiation_channel,
    reviewed_by_profile_id,
    folio_reference_id,
    destination_scheme_code
  INTO v_order;

  INSERT INTO public.workspace_audit_logs (
    workspace_id,
    actor_id,
    actor_profile_id,
    actor_type,
    action,
    event_type,
    target_type,
    entity_type,
    target_id,
    entity_id,
    previous_state,
    new_state,
    payload
  ) VALUES (
    v_workspace_id,
    v_current_profile_id,
    v_current_profile_id,
    'advisor',
    'order.qualified',
    'order.manual_qualification',
    'order_requests',
    'order_requests',
    p_order_id,
    p_order_id,
    v_current_status::pg_catalog.text,
    p_decision::pg_catalog.text,
    pg_catalog.jsonb_build_object(
      'decision', p_decision,
      'rejection_reason', p_rejection_reason,
      'investor_profile_id', v_investor_profile_id,
      'initiated_by_profile_id', v_initiated_by_profile_id,
      'reviewed_by_profile_id', v_current_profile_id
    )
  );

  INSERT INTO public.workspace_audit_logs (
    workspace_id,
    actor_id,
    actor_profile_id,
    actor_type,
    action,
    event_type,
    target_type,
    entity_type,
    target_id,
    entity_id,
    reason,
    previous_state,
    new_state,
    payload
  ) VALUES (
    v_workspace_id,
    v_current_profile_id,
    v_current_profile_id,
    'advisor',
    CASE WHEN p_decision = 'approved' THEN 'order.approved' ELSE 'order.rejected' END,
    CASE WHEN p_decision = 'approved' THEN 'order.approved' ELSE 'order.rejected' END,
    'order_requests',
    'order_requests',
    p_order_id,
    p_order_id,
    p_rejection_reason,
    v_current_status::pg_catalog.text,
    p_decision::pg_catalog.text,
    pg_catalog.jsonb_build_object(
      'decision', p_decision,
      'reason', p_rejection_reason,
      'investor_profile_id', v_investor_profile_id,
      'initiated_by_profile_id', v_initiated_by_profile_id,
      'reviewed_by_profile_id', v_current_profile_id
    )
  );

  RETURN v_order;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

REVOKE ALL ON FUNCTION public.qualify_order(pg_catalog.uuid, public.order_status, pg_catalog.text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.qualify_order(pg_catalog.uuid, public.order_status, pg_catalog.text) FROM anon;
REVOKE ALL ON FUNCTION public.qualify_order(pg_catalog.uuid, public.order_status, pg_catalog.text) FROM authenticated;
REVOKE ALL ON FUNCTION public.qualify_order(pg_catalog.uuid, public.order_status, pg_catalog.text) FROM service_role;
GRANT EXECUTE ON FUNCTION public.qualify_order(pg_catalog.uuid, public.order_status, pg_catalog.text) TO authenticated;

COMMIT;
