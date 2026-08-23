-- Issue #114 corrective authorization boundary for Hosted Dev ingestion/OAuth.

BEGIN;

CREATE OR REPLACE FUNCTION public.authorize_cams_kfintech_workspace(
  p_workspace_id pg_catalog.uuid
)
RETURNS pg_catalog.bool AS $$
DECLARE
  v_auth_user_id pg_catalog.uuid;
  v_profile_id pg_catalog.uuid;
  v_profile_count pg_catalog.int8;
  v_membership_count pg_catalog.int8;
BEGIN
  v_auth_user_id := auth.uid();
  IF v_auth_user_id IS NULL OR p_workspace_id IS NULL THEN
    RAISE EXCEPTION 'not_authorized' USING ERRCODE = 'P0001';
  END IF;

  SELECT pg_catalog.count(*)
  INTO v_profile_count
  FROM public.profiles AS profile
  WHERE profile.user_id = v_auth_user_id;

  IF v_profile_count <> 1 THEN
    RAISE EXCEPTION 'not_authorized' USING ERRCODE = 'P0001';
  END IF;

  v_profile_id := public.current_user_profile_id();
  IF v_profile_id IS NULL THEN
    RAISE EXCEPTION 'not_authorized' USING ERRCODE = 'P0001';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.workspaces AS workspace
    WHERE workspace.id = p_workspace_id
      AND workspace.workspace_status = 'active'
  ) THEN
    RAISE EXCEPTION 'not_authorized' USING ERRCODE = 'P0001';
  END IF;

  SELECT pg_catalog.count(*)
  INTO v_membership_count
  FROM public.workspace_memberships AS membership
  WHERE membership.workspace_id = p_workspace_id
    AND membership.profile_id = v_profile_id
    AND membership.role IN ('advisor', 'admin')
    AND membership.status = 'active'
    AND membership.ended_at IS NULL;

  IF v_membership_count <> 1 THEN
    RAISE EXCEPTION 'not_authorized' USING ERRCODE = 'P0001';
  END IF;

  RETURN true;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '';

COMMENT ON FUNCTION public.authorize_cams_kfintech_workspace(pg_catalog.uuid) IS
  'Returns true only when the authenticated caller has exactly one active advisor/admin membership in an active workspace; otherwise raises not_authorized.';

REVOKE ALL ON FUNCTION public.authorize_cams_kfintech_workspace(pg_catalog.uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.authorize_cams_kfintech_workspace(pg_catalog.uuid)
  TO authenticated;

COMMIT;
