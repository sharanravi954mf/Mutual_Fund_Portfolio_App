-- Batch Ingestion stored procedure to process raw statements and link profiles efficiently
CREATE OR REPLACE FUNCTION public.process_cams_records(records jsonb)
RETURNS void AS $$
DECLARE
  rec jsonb;
  p_id uuid;
  f_id uuid;
  port_id uuid;
  existing_st_id uuid;
  existing_tx_id uuid;
BEGIN
  FOR rec IN SELECT * FROM jsonb_array_elements(records) LOOP
    -- 1. Check/Insert cams_statements raw record to avoid duplicates
    SELECT id INTO existing_st_id FROM public.cams_statements
    WHERE foliochk = (rec->>'foliochk')
      AND product = (rec->>'product')
      AND rep_date = (rec->>'rep_date')::date
      AND clos_bal = (rec->>'clos_bal')::numeric
      AND rupee_bal = (rec->>'rupee_bal')::numeric
    LIMIT 1;

    IF existing_st_id IS NULL THEN
      INSERT INTO public.cams_statements (
        foliochk, inv_name, address1, address2, address3, city, pincode,
        product, sch_name, rep_date, clos_bal, rupee_bal, pan_no,
        joint1_pan, joint2_pan, guard_pan, email, mobile_no, bank_name,
        branch, ac_type, ac_no, ifsc_code, nom_name, relation, nom_percen
      ) VALUES (
        rec->>'foliochk', rec->>'inv_name', rec->>'address1', rec->>'address2', rec->>'address3', rec->>'city', rec->>'pincode',
        rec->>'product', rec->>'sch_name', (rec->>'rep_date')::date, (rec->>'clos_bal')::numeric, (rec->>'rupee_bal')::numeric, rec->>'pan_no',
        rec->>'joint1_pan', rec->>'joint2_pan', rec->>'guard_pan', rec->>'email', rec->>'mobile_no', rec->>'bank_name',
        rec->>'branch', rec->>'ac_type', rec->>'ac_no', rec->>'ifsc_code', rec->>'nom_name', rec->>'relation', (rec->>'nom_percen')::numeric
      );
    END IF;

    -- 2. Check/Insert profiles
    SELECT id INTO p_id FROM public.profiles WHERE pan = (rec->>'clientPan') LIMIT 1;
    IF p_id IS NULL THEN
      INSERT INTO public.profiles (id, full_name, role, pan)
      VALUES (gen_random_uuid(), rec->>'investorName', 'client', rec->>'clientPan')
      RETURNING id INTO p_id;
    END IF;

    -- 3. Upsert mutual_funds
    INSERT INTO public.mutual_funds (scheme_code, scheme_name, fund_house, category, current_nav, nav_date)
    VALUES (
      rec->>'schemeCode',
      rec->>'schemeName',
      COALESCE(rec->>'fundHouse', 'Mutual Fund'),
      COALESCE(rec->>'category', 'Mutual Fund'),
      (rec->>'nav')::numeric,
      (rec->>'date')::date
    )
    ON CONFLICT (scheme_code) DO UPDATE
    SET 
      scheme_name = EXCLUDED.scheme_name,
      current_nav = EXCLUDED.current_nav,
      nav_date = EXCLUDED.nav_date
    RETURNING id INTO f_id;

    -- 4. Get or Create Portfolio
    SELECT id INTO port_id FROM public.portfolios WHERE client_id = p_id LIMIT 1;
    IF port_id IS NULL THEN
      INSERT INTO public.portfolios (client_id, total_invested_value, current_market_value)
      VALUES (p_id, 0.00, 0.00)
      RETURNING id INTO port_id;
    END IF;

    -- 5. Check/Insert transaction
    SELECT id INTO existing_tx_id FROM public.transactions
    WHERE portfolio_id = port_id
      AND mutual_fund_id = f_id
      AND transaction_type = (rec->>'transactionType')
      AND units = (rec->>'units')::numeric
      AND amount = (rec->>'amount')::numeric
      AND execution_date = (rec->>'date')::date
    LIMIT 1;

    IF existing_tx_id IS NULL THEN
      INSERT INTO public.transactions (portfolio_id, mutual_fund_id, transaction_type, units, nav_at_transaction, amount, execution_date)
      VALUES (
        port_id,
        f_id,
        rec->>'transactionType',
        (rec->>'units')::numeric,
        (rec->>'nav')::numeric,
        (rec->>'amount')::numeric,
        (rec->>'date')::date
      );

      -- Recalculate Portfolio
      PERFORM public.recalculate_portfolio_value(port_id);
    END IF;
  END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;
