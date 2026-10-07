-- Reviewed, opt-in DEV configuration; deliberately outside automatic migrations
-- and seed.sql. Promotion of source/migrations must NOT activate Production.
-- After separate deployment authorization, independently attest the connection's
-- DEV project in Dashboard, then use psql -X -v ON_ERROR_STOP=1
--   -v project_ref=rskryngwzyuzmiwtriyy -f <this file>
-- project_ref is operator attestation, not authentication or database discovery.
-- LOCAL_DISPOSABLE is reserved for the network-isolated regression harness.
-- No provider call, operation preparation, privilege or schema change occurs here.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL search_path = '';
SET LOCAL lock_timeout = '5s';
SELECT pg_catalog.set_config('moneybowl.ekyc_amc_project_ref', :'project_ref', true);
DO $$
DECLARE
  -- NSE FAQ, updated 31 July 2025, p5, Q1.18. Exact labels, no SCH derivation.
  approved constant jsonb := '{
    "B": "Aditya Birla",
    "K": "Kotak Mahindra",
    "H": "HDFC Mutual Fund",
    "G": "Bandhan Mutual Fund",
    "CR": "Canara Robeco Mutual Fund",
    "O": "HSBC Asset Management",
    "UK": "Union Asset Management"
  }';
  source constant text := 'https://nseinvestuat.nseindia.com/nsemfdesk/resources/upload/apidetails/NSE_INVEST_API_FAQ_310725.pdf#page=5';
BEGIN
  IF coalesce(pg_catalog.current_setting('moneybowl.ekyc_amc_project_ref', true), '')
     NOT IN ('rskryngwzyuzmiwtriyy', 'LOCAL_DISPOSABLE') THEN
    RAISE EXCEPTION 'ekyc_amc_dev_project_attestation_required';
  END IF;

  -- Serialize configuration/preflight with other catalog writers, including a
  -- concurrent deactivation. No row is overwritten or silently reactivated.
  LOCK TABLE moneybowl_onboarding.ekyc_amcs IN SHARE ROW EXCLUSIVE MODE;
  IF EXISTS (
    SELECT 1 FROM moneybowl_onboarding.ekyc_amcs a
    WHERE NOT (approved ? a.code)
       OR a.label IS DISTINCT FROM approved->>a.code
       OR a.source_reference IS DISTINCT FROM source
  ) THEN
    RAISE EXCEPTION 'ekyc_amc_catalog_conflict';
  END IF;

  INSERT INTO moneybowl_onboarding.ekyc_amcs(code, label, source_reference, active)
  SELECT entry.key, entry.value, source, true
  FROM pg_catalog.jsonb_each_text(approved) entry
  ON CONFLICT (code) DO NOTHING;
END $$;
-- Safe configuration receipt only. active is MoneyBowl DEV approval, not proof
-- of current NSE availability or successful provider registration for each AMC.
SELECT code, label, source_reference, active
FROM moneybowl_onboarding.ekyc_amcs ORDER BY label;
COMMIT;
