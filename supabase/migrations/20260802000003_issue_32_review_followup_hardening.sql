-- Issue #32 review follow-up: workspace-scoped holdings and folio assignment locks.

BEGIN;

CREATE OR REPLACE FUNCTION public.process_cams_records(
  records pg_catalog.jsonb,
  p_workspace_id pg_catalog.uuid
)
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
  v_profile_count pg_catalog.int8;
  v_portfolio_count pg_catalog.int8;
BEGIN
  PERFORM public.assert_active_cams_kfintech_workspace(p_workspace_id);

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

    SELECT
      pg_catalog.count(DISTINCT pan_record.profile_id),
      (pg_catalog.array_agg(DISTINCT pan_record.profile_id ORDER BY pan_record.profile_id))[1]
    INTO v_profile_count, p_id
    FROM public.profile_pan_records AS pan_record
    JOIN public.workspace_memberships AS membership
      ON membership.profile_id = pan_record.profile_id
     AND membership.workspace_id = p_workspace_id
     AND membership.role = 'investor'
     AND membership.status = 'active'
    WHERE pan_record.pan_lookup_hmac = pan_hmac
      AND pan_record.status IN ('OBSERVED', 'VERIFIED');

    IF v_profile_count > 1 THEN
      RAISE EXCEPTION 'imported_record_ambiguous_investor_workspace';
    ELSIF v_profile_count = 0 THEN
      IF EXISTS (
        SELECT 1
        FROM public.profile_pan_records AS pan_record
        WHERE pan_record.pan_lookup_hmac = pan_hmac
          AND pan_record.status IN ('OBSERVED', 'VERIFIED')
      ) THEN
        RAISE EXCEPTION 'investor_workspace_relationship_required';
      END IF;

      INSERT INTO public.profiles (id, full_name, role)
      VALUES (pg_catalog.gen_random_uuid(), rec->>'investorName', 'client')
      RETURNING id INTO p_id;

      INSERT INTO public.workspace_memberships (workspace_id, profile_id, role, status)
      VALUES (p_workspace_id, p_id, 'investor', 'active');
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

    PERFORM pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(
        p_workspace_id::pg_catalog.text || ':folio:' || registrar_source || ':' || normalized_folio,
        0
      )
    );

    SELECT
      pg_catalog.count(*),
      (pg_catalog.array_agg(portfolio.id ORDER BY portfolio.id))[1]
    INTO v_portfolio_count, port_id
    FROM public.portfolio_folio_references AS pfr
    JOIN public.portfolios AS portfolio
      ON portfolio.id = pfr.portfolio_id
    WHERE portfolio.workspace_id = p_workspace_id
      AND pfr.folio_reference_id = folio_id;

    IF v_portfolio_count > 1 THEN
      RAISE EXCEPTION 'portfolio_folio_workspace_ambiguous';
    ELSIF v_portfolio_count = 1 THEN
      IF NOT EXISTS (
        SELECT 1
        FROM public.portfolios AS portfolio
        WHERE portfolio.id = port_id
          AND portfolio.workspace_id = p_workspace_id
          AND portfolio.client_id = p_id
      ) THEN
        RAISE EXCEPTION 'folio_relationship_conflict';
      END IF;
    ELSE
      SELECT
        pg_catalog.count(*),
        (pg_catalog.array_agg(portfolio.id ORDER BY portfolio.id))[1]
      INTO v_portfolio_count, port_id
      FROM public.portfolios AS portfolio
      WHERE portfolio.client_id = p_id
        AND portfolio.workspace_id = p_workspace_id;

      IF v_portfolio_count > 1 THEN
        RAISE EXCEPTION 'portfolio_mapping_ambiguous';
      ELSIF v_portfolio_count = 0 THEN
        INSERT INTO public.portfolios (
          client_id, workspace_id, total_invested_value, current_market_value
        ) VALUES (
          p_id, p_workspace_id, 0.00, 0.00
        )
        RETURNING id INTO port_id;
      END IF;

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

CREATE OR REPLACE FUNCTION public.validate_order_request_canonical_contract()
RETURNS trigger AS $$
DECLARE
  v_caller_user_id pg_catalog.uuid;
  v_caller_profile_id pg_catalog.uuid;
  v_is_service_role pg_catalog.bool;
  v_is_api_insert pg_catalog.bool;
  v_request_claims pg_catalog.text;
  v_request_role pg_catalog.text;
  v_validate_submission_intent pg_catalog.bool;
  v_source_fund_id pg_catalog.uuid;
  v_source_portfolio_id pg_catalog.uuid;
  v_source_portfolio_count pg_catalog.int8;
  v_available_units pg_catalog.numeric;
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
  v_validate_submission_intent := TG_OP = 'INSERT'
    OR (
      TG_OP = 'UPDATE'
      AND (
        NEW.type IS DISTINCT FROM OLD.type
        OR NEW.scheme_code IS DISTINCT FROM OLD.scheme_code
        OR NEW.folio_reference_id IS DISTINCT FROM OLD.folio_reference_id
        OR NEW.destination_scheme_code IS DISTINCT FROM OLD.destination_scheme_code
      )
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

  IF v_validate_submission_intent THEN
    IF NEW.type IN ('sell'::public.order_type, 'switch'::public.order_type) THEN
      IF NEW.folio_reference_id IS NULL THEN
        RAISE EXCEPTION 'folio_reference_required_for_sell_switch';
      END IF;

      SELECT
        pg_catalog.count(DISTINCT p.id),
        (pg_catalog.array_agg(DISTINCT p.id ORDER BY p.id))[1]
      INTO v_source_portfolio_count, v_source_portfolio_id
      FROM public.portfolio_folio_references AS pfr
      JOIN public.portfolios AS p
        ON p.id = pfr.portfolio_id
      WHERE pfr.folio_reference_id = NEW.folio_reference_id
        AND p.client_id = NEW.investor_profile_id
        AND p.workspace_id = NEW.workspace_id;

      IF v_source_portfolio_count = 0 THEN
        RAISE EXCEPTION 'folio_not_owned_by_investor_in_workspace';
      ELSIF v_source_portfolio_count > 1 THEN
        RAISE EXCEPTION 'folio_portfolio_workspace_ambiguous';
      END IF;

      SELECT mf.id
      INTO v_source_fund_id
      FROM public.mutual_funds AS mf
      WHERE mf.scheme_code = NEW.scheme_code
      LIMIT 1;

      IF v_source_fund_id IS NULL THEN
        RAISE EXCEPTION 'scheme_not_held_in_selected_folio';
      END IF;

      IF EXISTS (
        SELECT 1
        FROM public.transactions AS t
        WHERE t.portfolio_id = v_source_portfolio_id
          AND t.folio_reference_id = NEW.folio_reference_id
          AND t.mutual_fund_id = v_source_fund_id
          AND t.transaction_type = 'SWITCH'
          AND t.source_folio_reference_id IS NOT NULL
          AND (
            t.transaction_direction IS NULL
            OR t.transaction_direction NOT IN ('INFLOW', 'OUTFLOW')
          )
      ) THEN
        RAISE EXCEPTION 'unsupported_transaction_direction';
      END IF;

      SELECT COALESCE(SUM(
        CASE
          WHEN t.transaction_type = 'BUY' THEN t.units
          WHEN t.transaction_type = 'SELL' THEN -t.units
          WHEN t.transaction_type = 'SWITCH' AND t.transaction_direction = 'INFLOW' THEN t.units
          WHEN t.transaction_type = 'SWITCH' AND t.transaction_direction = 'OUTFLOW' THEN -t.units
          ELSE 0
        END
      ), 0)
      INTO v_available_units
      FROM public.transactions AS t
      WHERE t.portfolio_id = v_source_portfolio_id
        AND t.folio_reference_id = NEW.folio_reference_id
        AND t.mutual_fund_id = v_source_fund_id;

      IF v_available_units <= 0 THEN
        RAISE EXCEPTION 'scheme_not_held_in_selected_folio';
      END IF;
    END IF;

    IF NEW.destination_scheme_code IS NOT NULL THEN
      IF NOT EXISTS (
        SELECT 1
        FROM public.mutual_funds AS mf
        WHERE mf.scheme_code = NEW.destination_scheme_code
      ) THEN
        RAISE EXCEPTION 'destination_scheme_not_found';
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

REVOKE ALL ON FUNCTION public.process_cams_records(pg_catalog.jsonb, pg_catalog.uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.process_cams_records(pg_catalog.jsonb, pg_catalog.uuid) FROM anon;
REVOKE ALL ON FUNCTION public.process_cams_records(pg_catalog.jsonb, pg_catalog.uuid) FROM authenticated;
REVOKE ALL ON FUNCTION public.process_cams_records(pg_catalog.jsonb, pg_catalog.uuid) FROM service_role;
GRANT EXECUTE ON FUNCTION public.process_cams_records(pg_catalog.jsonb, pg_catalog.uuid) TO service_role;

REVOKE ALL ON FUNCTION public.validate_order_request_canonical_contract() FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
