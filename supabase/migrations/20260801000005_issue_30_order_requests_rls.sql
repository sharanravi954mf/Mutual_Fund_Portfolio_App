-- Issue #30: Workspace-isolated RLS for canonical order requests.

BEGIN;

CREATE OR REPLACE FUNCTION public.can_select_order_request(
  p_workspace_id pg_catalog.uuid,
  p_investor_profile_id pg_catalog.uuid
)
RETURNS pg_catalog.bool AS $$
DECLARE
  v_profile_id pg_catalog.uuid;
BEGIN
  v_profile_id := public.current_user_profile_id();

  IF v_profile_id IS NULL OR public.is_platform_admin() THEN
    RETURN false;
  END IF;

  IF p_investor_profile_id = v_profile_id THEN
    RETURN EXISTS (
      SELECT 1
      FROM public.workspace_memberships AS investor_membership
      WHERE investor_membership.workspace_id = p_workspace_id
        AND investor_membership.profile_id = v_profile_id
        AND investor_membership.role = 'investor'
        AND investor_membership.status = 'active'
    );
  END IF;

  RETURN public.is_order_mfd_profile(p_workspace_id, v_profile_id)
    AND EXISTS (
      SELECT 1
      FROM public.workspace_memberships AS beneficiary_membership
      WHERE beneficiary_membership.workspace_id = p_workspace_id
        AND beneficiary_membership.profile_id = p_investor_profile_id
        AND beneficiary_membership.role = 'investor'
        AND beneficiary_membership.status = 'active'
    );
END;
$$ LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '';

REVOKE ALL ON FUNCTION public.can_select_order_request(pg_catalog.uuid, pg_catalog.uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.can_select_order_request(pg_catalog.uuid, pg_catalog.uuid) FROM anon;
REVOKE ALL ON FUNCTION public.can_select_order_request(pg_catalog.uuid, pg_catalog.uuid) FROM authenticated;
REVOKE ALL ON FUNCTION public.can_select_order_request(pg_catalog.uuid, pg_catalog.uuid) FROM service_role;
GRANT EXECUTE ON FUNCTION public.can_select_order_request(pg_catalog.uuid, pg_catalog.uuid) TO authenticated;

DROP POLICY IF EXISTS order_requests_investor_insert ON public.order_requests;
DROP FUNCTION IF EXISTS public.can_insert_order_request(pg_catalog.uuid, pg_catalog.uuid, public.order_status);

CREATE OR REPLACE FUNCTION public.can_insert_order_request(
  p_workspace_id pg_catalog.uuid,
  p_investor_profile_id pg_catalog.uuid,
  p_initiated_by_profile_id pg_catalog.uuid,
  p_initiated_by_role pg_catalog.text,
  p_initiation_channel pg_catalog.text,
  p_status public.order_status,
  p_reviewed_by pg_catalog.uuid,
  p_reviewed_by_profile_id pg_catalog.uuid,
  p_reviewed_at pg_catalog.timestamptz
)
RETURNS pg_catalog.bool AS $$
DECLARE
  v_profile_id pg_catalog.uuid;
BEGIN
  IF p_status <> 'pending_qualification'::public.order_status THEN
    RAISE EXCEPTION 'invalid_initial_order_status';
  END IF;

  IF p_reviewed_by IS NOT NULL
     OR p_reviewed_by_profile_id IS NOT NULL
     OR p_reviewed_at IS NOT NULL THEN
    RAISE EXCEPTION 'review_metadata_requires_qualification';
  END IF;

  v_profile_id := public.current_user_profile_id();

  IF v_profile_id IS NULL
     OR public.is_platform_admin()
     OR p_initiated_by_profile_id IS DISTINCT FROM v_profile_id THEN
    RETURN false;
  END IF;

  IF p_initiated_by_role = 'investor'
     AND p_initiation_channel = 'investor_portal' THEN
    RETURN p_investor_profile_id = v_profile_id
      AND EXISTS (
        SELECT 1
        FROM public.workspace_memberships AS investor_membership
        WHERE investor_membership.workspace_id = p_workspace_id
          AND investor_membership.profile_id = v_profile_id
          AND investor_membership.role = 'investor'
          AND investor_membership.status = 'active'
      );
  END IF;

  IF p_initiated_by_role = 'advisor'
     AND p_initiation_channel = 'advisor_portal' THEN
    RETURN public.is_order_mfd_profile(p_workspace_id, v_profile_id)
      AND EXISTS (
        SELECT 1
        FROM public.workspace_memberships AS beneficiary_membership
        WHERE beneficiary_membership.workspace_id = p_workspace_id
          AND beneficiary_membership.profile_id = p_investor_profile_id
          AND beneficiary_membership.role = 'investor'
          AND beneficiary_membership.status = 'active'
      );
  END IF;

  RETURN false;
END;
$$ LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '';

REVOKE ALL ON FUNCTION public.can_insert_order_request(
  pg_catalog.uuid,
  pg_catalog.uuid,
  pg_catalog.uuid,
  pg_catalog.text,
  pg_catalog.text,
  public.order_status,
  pg_catalog.uuid,
  pg_catalog.uuid,
  pg_catalog.timestamptz
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.can_insert_order_request(
  pg_catalog.uuid,
  pg_catalog.uuid,
  pg_catalog.uuid,
  pg_catalog.text,
  pg_catalog.text,
  public.order_status,
  pg_catalog.uuid,
  pg_catalog.uuid,
  pg_catalog.timestamptz
) FROM anon;
REVOKE ALL ON FUNCTION public.can_insert_order_request(
  pg_catalog.uuid,
  pg_catalog.uuid,
  pg_catalog.uuid,
  pg_catalog.text,
  pg_catalog.text,
  public.order_status,
  pg_catalog.uuid,
  pg_catalog.uuid,
  pg_catalog.timestamptz
) FROM authenticated;
REVOKE ALL ON FUNCTION public.can_insert_order_request(
  pg_catalog.uuid,
  pg_catalog.uuid,
  pg_catalog.uuid,
  pg_catalog.text,
  pg_catalog.text,
  public.order_status,
  pg_catalog.uuid,
  pg_catalog.uuid,
  pg_catalog.timestamptz
) FROM service_role;
GRANT EXECUTE ON FUNCTION public.can_insert_order_request(
  pg_catalog.uuid,
  pg_catalog.uuid,
  pg_catalog.uuid,
  pg_catalog.text,
  pg_catalog.text,
  public.order_status,
  pg_catalog.uuid,
  pg_catalog.uuid,
  pg_catalog.timestamptz
) TO authenticated;

ALTER TABLE public.order_requests ENABLE ROW LEVEL SECURITY;

DO $$
DECLARE
  v_policy pg_catalog.record;
BEGIN
  FOR v_policy IN
    SELECT policies.policyname
    FROM pg_catalog.pg_policies AS policies
    WHERE policies.schemaname = 'public'
      AND policies.tablename = 'order_requests'
  LOOP
    EXECUTE pg_catalog.format(
      'DROP POLICY IF EXISTS %I ON %I.%I',
      v_policy.policyname,
      'public',
      'order_requests'
    );
  END LOOP;
END;
$$;

CREATE POLICY order_requests_select_workspace_isolation ON public.order_requests
  FOR SELECT
  TO authenticated
  USING (
    public.can_select_order_request(workspace_id, investor_profile_id)
  );

CREATE POLICY order_requests_insert_workspace_isolation ON public.order_requests
  FOR INSERT
  TO authenticated
  WITH CHECK (
    public.can_insert_order_request(
      workspace_id,
      investor_profile_id,
      initiated_by_profile_id,
      initiated_by_role,
      initiation_channel,
      status,
      reviewed_by,
      reviewed_by_profile_id,
      reviewed_at
    )
  );

REVOKE ALL ON TABLE public.order_requests FROM PUBLIC;
REVOKE ALL ON TABLE public.order_requests FROM anon;
REVOKE UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON TABLE public.order_requests FROM authenticated;
REVOKE UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON TABLE public.order_requests FROM service_role;
GRANT SELECT, INSERT ON TABLE public.order_requests TO authenticated;
GRANT SELECT, INSERT ON TABLE public.order_requests TO service_role;

COMMIT;
