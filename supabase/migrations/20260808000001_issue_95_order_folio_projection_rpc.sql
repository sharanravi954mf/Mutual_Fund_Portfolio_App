-- Issue #95: safe order-flow folio projection RPCs.

BEGIN;

CREATE OR REPLACE FUNCTION public.list_order_folios(
  p_investor_profile_id pg_catalog.uuid,
  p_workspace_id pg_catalog.uuid
)
RETURNS TABLE(
  folio_reference_id pg_catalog.uuid,
  portfolio_id pg_catalog.uuid,
  registrar pg_catalog.text,
  masked_folio pg_catalog.text
) AS $$
DECLARE
  v_caller_profile_id pg_catalog.uuid;
BEGIN
  v_caller_profile_id := public.current_user_profile_id();

  IF auth.uid() IS NULL
     OR v_caller_profile_id IS NULL
     OR public.is_platform_admin() THEN
    RETURN;
  END IF;

  IF v_caller_profile_id <> p_investor_profile_id
     AND NOT public.is_order_mfd_profile(p_workspace_id, v_caller_profile_id) THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT DISTINCT
    folio.id AS folio_reference_id,
    portfolio.id AS portfolio_id,
    folio.registrar,
    folio.source_folio_masked AS masked_folio
  FROM public.portfolios AS portfolio
  JOIN public.workspace_memberships AS investor_membership
    ON investor_membership.workspace_id = portfolio.workspace_id
   AND investor_membership.profile_id = portfolio.client_id
   AND investor_membership.role = 'investor'
   AND investor_membership.status = 'active'
   AND investor_membership.ended_at IS NULL
  JOIN public.profiles AS investor_profile
    ON investor_profile.id = portfolio.client_id
   AND investor_profile.account_status = 'active'
  JOIN public.portfolio_folio_references AS portfolio_folio
    ON portfolio_folio.portfolio_id = portfolio.id
  JOIN public.folio_grants AS folio_grant
    ON folio_grant.profile_id = portfolio.client_id
   AND folio_grant.folio_reference_id = portfolio_folio.folio_reference_id
   AND folio_grant.status = 'active'
  JOIN public.investor_account_links AS investor_link
    ON investor_link.user_id = folio_grant.user_id
   AND investor_link.profile_id = folio_grant.profile_id
   AND investor_link.link_status = 'active'
  JOIN public.user_accounts AS investor_account
    ON investor_account.user_id = investor_link.user_id
   AND investor_account.account_state = 'linked_investor'
  JOIN public.folio_references AS folio
    ON folio.id = portfolio_folio.folio_reference_id
  WHERE portfolio.client_id = p_investor_profile_id
    AND portfolio.workspace_id = p_workspace_id
    AND (
      v_caller_profile_id <> p_investor_profile_id
      OR investor_link.user_id = auth.uid()
    )
  ORDER BY folio.registrar, folio.source_folio_masked, folio.id;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '';

REVOKE ALL ON FUNCTION public.list_order_folios(pg_catalog.uuid, pg_catalog.uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.list_order_folios(pg_catalog.uuid, pg_catalog.uuid) FROM anon;
REVOKE ALL ON FUNCTION public.list_order_folios(pg_catalog.uuid, pg_catalog.uuid) FROM authenticated;
REVOKE ALL ON FUNCTION public.list_order_folios(pg_catalog.uuid, pg_catalog.uuid) FROM service_role;
GRANT EXECUTE ON FUNCTION public.list_order_folios(pg_catalog.uuid, pg_catalog.uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.resolve_order_folio_portfolio(
  p_investor_profile_id pg_catalog.uuid,
  p_workspace_id pg_catalog.uuid,
  p_folio_reference_id pg_catalog.uuid
)
RETURNS TABLE(
  portfolio_id pg_catalog.uuid
) AS $$
DECLARE
  v_caller_profile_id pg_catalog.uuid;
BEGIN
  v_caller_profile_id := public.current_user_profile_id();

  IF auth.uid() IS NULL
     OR v_caller_profile_id IS NULL
     OR public.is_platform_admin() THEN
    RETURN;
  END IF;

  IF v_caller_profile_id <> p_investor_profile_id
     AND NOT public.is_order_mfd_profile(p_workspace_id, v_caller_profile_id) THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT portfolio.id AS portfolio_id
  FROM public.portfolios AS portfolio
  JOIN public.workspace_memberships AS investor_membership
    ON investor_membership.workspace_id = portfolio.workspace_id
   AND investor_membership.profile_id = portfolio.client_id
   AND investor_membership.role = 'investor'
   AND investor_membership.status = 'active'
   AND investor_membership.ended_at IS NULL
  JOIN public.profiles AS investor_profile
    ON investor_profile.id = portfolio.client_id
   AND investor_profile.account_status = 'active'
  JOIN public.portfolio_folio_references AS portfolio_folio
    ON portfolio_folio.portfolio_id = portfolio.id
   AND portfolio_folio.folio_reference_id = p_folio_reference_id
  JOIN public.folio_grants AS folio_grant
    ON folio_grant.profile_id = portfolio.client_id
   AND folio_grant.folio_reference_id = portfolio_folio.folio_reference_id
   AND folio_grant.status = 'active'
  JOIN public.investor_account_links AS investor_link
    ON investor_link.user_id = folio_grant.user_id
   AND investor_link.profile_id = folio_grant.profile_id
   AND investor_link.link_status = 'active'
  JOIN public.user_accounts AS investor_account
    ON investor_account.user_id = investor_link.user_id
   AND investor_account.account_state = 'linked_investor'
  WHERE portfolio.client_id = p_investor_profile_id
    AND portfolio.workspace_id = p_workspace_id
    AND (
      v_caller_profile_id <> p_investor_profile_id
      OR investor_link.user_id = auth.uid()
    )
  ORDER BY portfolio.id
  LIMIT 1;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '';

REVOKE ALL ON FUNCTION public.resolve_order_folio_portfolio(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.resolve_order_folio_portfolio(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid) FROM anon;
REVOKE ALL ON FUNCTION public.resolve_order_folio_portfolio(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid) FROM authenticated;
REVOKE ALL ON FUNCTION public.resolve_order_folio_portfolio(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid) FROM service_role;
GRANT EXECUTE ON FUNCTION public.resolve_order_folio_portfolio(pg_catalog.uuid, pg_catalog.uuid, pg_catalog.uuid) TO authenticated;

REVOKE ALL ON TABLE
  public.folio_references,
  public.portfolio_folio_references,
  public.verification_folio_evidence,
  public.folio_grants,
  public.verification_request_assignments,
  public.folio_submission_tokens,
  public.profile_pan_records
FROM PUBLIC, anon, authenticated;

COMMIT;
