-- Included by onboarding_kyc_test.sql after its linked synthetic case has valid
-- protected contacts and a characterized empty KYC result. No new PII fixture.
-- The parent harness has applied the real DEV configuration locally, with no
-- network and no worker. Roll back every scenario before the parent continues.
SAVEPOINT ekyc_amc_selector;
RESET ROLE;
-- Hide the parent's separate synthetic selector just for these assertions.
UPDATE moneybowl_onboarding.ekyc_amcs SET active=false WHERE code='TEST';
DO $$ DECLARE api_role text; permission text; BEGIN
  PERFORM pg_temp.assert((SELECT relrowsecurity FROM pg_class
    WHERE oid='moneybowl_onboarding.ekyc_amcs'::regclass), 'AMC RLS remains enabled');
  PERFORM pg_temp.assert(NOT EXISTS(SELECT 1 FROM pg_policies
    WHERE schemaname='moneybowl_onboarding' AND tablename='ekyc_amcs'), 'AMC policies remain empty');
  FOREACH api_role IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
    PERFORM pg_temp.assert(NOT has_schema_privilege(api_role,'moneybowl_onboarding','USAGE'), 'AMC private schema');
    FOREACH permission IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP
      PERFORM pg_temp.assert(NOT has_table_privilege(api_role,'moneybowl_onboarding.ekyc_amcs',permission), 'AMC API table privileges denied');
    END LOOP;
  END LOOP;
  PERFORM pg_temp.assert(NOT EXISTS(SELECT 1 FROM pg_proc
    WHERE oid IN ('public.get_onboarding_kyc(uuid)'::regprocedure,
      'public.request_onboarding_kyc(uuid,uuid,text,text,text,text)'::regprocedure)
    AND pg_get_functiondef(oid) ILIKE '%nse_reference%'), 'selector does not read SCH');
END $$;
SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb; code text; BEGIN
  r:=public.get_onboarding_kyc('ab400000-0000-0000-0000-000000000090');
  PERFORM pg_temp.assert(r->>'status'='KYC_NOT_AVAILABLE', 'mapper preserves KYC state');
  PERFORM pg_temp.assert(r->'amcs'='[
    {"code":"B","label":"Aditya Birla"},
    {"code":"G","label":"Bandhan Mutual Fund"},
    {"code":"CR","label":"Canara Robeco Mutual Fund"},
    {"code":"H","label":"HDFC Mutual Fund"},
    {"code":"O","label":"HSBC Asset Management"},
    {"code":"K","label":"Kotak Mahindra"},
    {"code":"UK","label":"Union Asset Management"}
  ]'::jsonb, 'authorized dropdown receives exactly active FAQ entries in label order');
  FOREACH code IN ARRAY ARRAY['AXF','T','UNKNOWN','BANDHANMUTUALFUND_MF','CAMS','11','g',' G'] LOOP
    BEGIN
      PERFORM public.request_onboarding_kyc('ab400000-0000-0000-0000-000000000090',gen_random_uuid(),'EKYC',NULL,NULL,code);
      RAISE EXCEPTION 'unapproved AMC accepted';
    EXCEPTION WHEN raise_exception THEN
      IF SQLERRM<>'ekyc_details_required' THEN RAISE; END IF;
    END;
  END LOOP;
  BEGIN
    INSERT INTO moneybowl_onboarding.ekyc_amcs VALUES('INJECTED','Unapproved','browser',true);
    RAISE EXCEPTION 'browser inserted AMC';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    UPDATE moneybowl_onboarding.ekyc_amcs SET active=true;
    RAISE EXCEPTION 'browser updated AMC';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    DELETE FROM moneybowl_onboarding.ekyc_amcs;
    RAISE EXCEPTION 'browser deleted AMC';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    PERFORM 1 FROM moneybowl_onboarding.ekyc_amcs;
    RAISE EXCEPTION 'browser read private catalog';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  PERFORM set_config('request.jwt.claim.sub','ab000000-0000-0000-0000-000000000002',true);
  BEGIN
    PERFORM public.get_onboarding_kyc('ab400000-0000-0000-0000-000000000090');
    RAISE EXCEPTION 'unrelated MFD read selector';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  PERFORM set_config('request.jwt.claim.sub','ab000000-0000-0000-0000-000000000001',true);
END $$;
RESET ROLE;
SAVEPOINT inactive_amc;
UPDATE moneybowl_onboarding.ekyc_amcs SET active=false WHERE code='G';
SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb; BEGIN
  r:=public.get_onboarding_kyc('ab400000-0000-0000-0000-000000000090');
  PERFORM pg_temp.assert(jsonb_array_length(r->'amcs')=6 AND NOT (r->'amcs' @> '[{"code":"G"}]'), 'inactive AMC hidden');
  BEGIN
    PERFORM public.request_onboarding_kyc('ab400000-0000-0000-0000-000000000090',gen_random_uuid(),'EKYC',NULL,NULL,'G');
    RAISE EXCEPTION 'inactive AMC accepted';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM<>'ekyc_details_required' THEN RAISE; END IF;
  END;
END $$;
ROLLBACK TO inactive_amc;
SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb; request_id uuid:=gen_random_uuid(); BEGIN
  r:=public.request_onboarding_kyc('ab400000-0000-0000-0000-000000000090',request_id,'EKYC',NULL,NULL,'G');
  PERFORM pg_temp.assert(r->>'status'='EKYC_INITIATION_PENDING' AND r->'amcs'='[]'::jsonb, 'approved code prepares once and hides selector');
  PERFORM public.request_onboarding_kyc('ab400000-0000-0000-0000-000000000090',request_id,'EKYC',NULL,NULL,'G');
  PERFORM public.request_onboarding_kyc('ab400000-0000-0000-0000-000000000090',gen_random_uuid(),'EKYC',NULL,NULL,'G');
END $$;
RESET ROLE;
DO $$ DECLARE body jsonb; BEGIN
  PERFORM pg_temp.assert((SELECT count(*)=1 FROM moneybowl_onboarding.kyc_operations
    WHERE case_id='ab400000-0000-0000-0000-000000000090' AND api='EKYCREG'), 'one fresh operation per case');
  SELECT extensions.pgp_sym_decrypt(request_ciphertext,
    public.integration_payload_encryption_key('integration_payload_encryption_key_v1'))::jsonb
    INTO body FROM moneybowl_onboarding.kyc_operations
    WHERE case_id='ab400000-0000-0000-0000-000000000090' AND api='EKYCREG';
  PERFORM pg_temp.assert(body->>'amcCode'='G' AND body-ARRAY['amcCode','panNo','invEmail','mobileNo']='{}'::jsonb
    AND body ?& ARRAY['amcCode','panNo','invEmail','mobileNo'], 'Bandhan exact four-field request');
  PERFORM pg_temp.assert(NOT EXISTS(SELECT 1 FROM public.integration_api_interactions i
    JOIN moneybowl_onboarding.kyc_operations o ON o.id=i.onboarding_operation_id
    WHERE o.case_id='ab400000-0000-0000-0000-000000000090' AND o.api='EKYCREG'), 'no eKYC send or fabricated result');
END $$;
ROLLBACK TO ekyc_amc_selector;
RELEASE SAVEPOINT ekyc_amc_selector;
SET LOCAL ROLE authenticated;
\echo eKYC AMC selector: authorization, active list, exclusions, exact request and no send PASS
