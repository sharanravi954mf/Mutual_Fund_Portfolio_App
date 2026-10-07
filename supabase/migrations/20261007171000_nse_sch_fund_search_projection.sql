-- Browser-safe projection of the latest validated NSE SCH reference snapshot.
-- Raw nse_reference tables remain private. This is reference/catalogue data only:
-- it does not assert transaction eligibility, registrar crosswalk approval or NAV authority.
BEGIN;

CREATE FUNCTION public.search_nse_schemes(
  p_query text,
  p_limit integer DEFAULT 25
) RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  q text;
  requested_limit integer;
  v_snapshot_id uuid;
  v_snapshot_version bigint;
  v_snapshot_created_at timestamptz;
  result_items jsonb;
BEGIN
  IF NOT moneybowl_authz.account_active(auth.uid()) THEN
    RAISE EXCEPTION 'Authentication is required' USING ERRCODE='42501';
  END IF;

  q:=pg_catalog.lower(pg_catalog.btrim(coalesce(p_query,'')));
  requested_limit:=coalesce(p_limit,25);
  IF pg_catalog.length(q)<2 OR pg_catalog.length(q)>100
     OR requested_limit<1 OR requested_limit>50 THEN
    RAISE EXCEPTION 'fund_search_request_invalid';
  END IF;

  SELECT s.id,s.version,s.created_at
    INTO v_snapshot_id,v_snapshot_version,v_snapshot_created_at
  FROM nse_reference.snapshots s
  JOIN nse_reference.validations v ON v.snapshot_id=s.id
  JOIN nse_reference.connections c
    ON c.id=s.connection_id AND c.workspace_id=s.workspace_id
  JOIN public.workspaces w ON w.id=s.workspace_id
  WHERE s.file_type='SCH'
    AND v.status='STAGED_VALIDATED'
    AND v.parser_version='SCH_OBSERVED_44_V1'
    AND c.environment='UAT'
    AND c.enabled
    AND w.workspace_status='active'
  ORDER BY s.version DESC,s.created_at DESC,s.id DESC
  LIMIT 1;

  IF v_snapshot_id IS NULL THEN
    RETURN pg_catalog.jsonb_build_object(
      'source','NSE_INVEST_SCH',
      'available',false,
      'items','[]'::pg_catalog.jsonb
    );
  END IF;

  WITH candidates AS (
    SELECT
      i.scheme_code,
      r.scheme_name,
      r.amc_code,
      r.rta_agent_code,
      r.rta_scheme_code,
      r.amc_scheme_code,
      r.isin,
      r.scheme_type,
      r.plan_type,
      r.native_fields[27] AS amc_active_flag,
      CASE
        WHEN pg_catalog.lower(i.scheme_code)=q THEN 0
        WHEN pg_catalog.lower(r.scheme_name)=q THEN 1
        WHEN pg_catalog.strpos(pg_catalog.lower(r.scheme_name),q)=1 THEN 2
        WHEN pg_catalog.lower(r.isin)=q THEN 3
        WHEN pg_catalog.lower(r.amc_code)=q THEN 4
        ELSE 5
      END AS rank
    FROM nse_reference.sch_rows r
    JOIN nse_reference.scheme_identities i
      ON i.id=r.scheme_identity_id
     AND i.workspace_id=r.workspace_id
     AND i.connection_id=r.connection_id
    WHERE r.snapshot_id=v_snapshot_id
      AND (
        pg_catalog.strpos(pg_catalog.lower(i.scheme_code),q)>0
        OR pg_catalog.strpos(pg_catalog.lower(r.scheme_name),q)>0
        OR pg_catalog.strpos(pg_catalog.lower(r.amc_code),q)>0
        OR pg_catalog.strpos(pg_catalog.lower(r.rta_agent_code),q)>0
        OR pg_catalog.strpos(pg_catalog.lower(r.rta_scheme_code),q)>0
        OR pg_catalog.strpos(pg_catalog.lower(r.amc_scheme_code),q)>0
        OR pg_catalog.strpos(pg_catalog.lower(r.isin),q)>0
      )
    ORDER BY rank,r.scheme_name,i.scheme_code
    LIMIT requested_limit
  )
  SELECT coalesce(
    pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'scheme_code',scheme_code,
        'scheme_name',scheme_name,
        'amc_code',amc_code,
        'rta_agent_code',rta_agent_code,
        'rta_scheme_code',rta_scheme_code,
        'amc_scheme_code',amc_scheme_code,
        'isin',isin,
        'scheme_type',scheme_type,
        'plan_type',plan_type,
        'amc_active_flag',amc_active_flag
      )
      ORDER BY rank,scheme_name,scheme_code
    ),
    '[]'::pg_catalog.jsonb
  ) INTO result_items
  FROM candidates;

  RETURN pg_catalog.jsonb_build_object(
    'source','NSE_INVEST_SCH',
    'available',true,
    'snapshot_version',v_snapshot_version,
    'snapshot_created_at',v_snapshot_created_at,
    'items',result_items
  );
END
$$;

REVOKE ALL ON FUNCTION public.search_nse_schemes(text,integer)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.search_nse_schemes(text,integer)
  TO authenticated;

COMMIT;
