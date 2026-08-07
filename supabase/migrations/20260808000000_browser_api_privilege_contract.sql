-- Browser API privilege contract for direct Supabase table access.
-- RLS remains the row-level authorization boundary; these ACLs only allow the
-- authenticated browser role to reach the intended Data API tables.

REVOKE ALL ON TABLE
  public.profiles,
  public.user_accounts,
  public.investor_account_links,
  public.portfolios,
  public.transactions,
  public.mutual_funds,
  public.fund_factsheets,
  public.workspaces,
  public.workspace_memberships,
  public.advisor_investor_assignments,
  public.workspace_invitations
FROM PUBLIC, anon;

GRANT SELECT ON TABLE
  public.profiles,
  public.user_accounts,
  public.investor_account_links,
  public.portfolios,
  public.transactions,
  public.mutual_funds
TO authenticated;

GRANT SELECT, INSERT, UPDATE ON TABLE public.fund_factsheets TO authenticated;

GRANT SELECT, INSERT ON TABLE public.workspaces TO authenticated;

GRANT SELECT, INSERT, UPDATE ON TABLE
  public.workspace_memberships,
  public.advisor_investor_assignments
TO authenticated;

GRANT SELECT, INSERT ON TABLE public.workspace_invitations TO authenticated;

-- These tables remain protected from direct browser access. Future browser
-- use should go through narrowly scoped SECURITY DEFINER projection RPCs.
REVOKE ALL ON TABLE
  public.folio_references,
  public.portfolio_folio_references,
  public.verification_folio_evidence,
  public.folio_grants,
  public.verification_request_assignments,
  public.folio_submission_tokens,
  public.profile_pan_records
FROM PUBLIC, anon, authenticated;
