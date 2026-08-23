-- Issue #114: secure first-time Gmail OAuth provisioning.

BEGIN;

CREATE TABLE public.mailbox_oauth_authorization_states (
  id pg_catalog.uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  state_hash pg_catalog.text NOT NULL UNIQUE
    CHECK (state_hash ~ '^[0-9a-f]{64}$'),
  workspace_id pg_catalog.uuid NOT NULL
    REFERENCES public.workspaces(id) ON DELETE CASCADE,
  mailbox_connection_id pg_catalog.uuid NOT NULL
    REFERENCES public.mailbox_connections(id) ON DELETE CASCADE,
  actor_profile_id pg_catalog.uuid NOT NULL
    REFERENCES public.profiles(id) ON DELETE RESTRICT,
  redirect_uri pg_catalog.text NOT NULL CHECK (
    pg_catalog.length(redirect_uri) BETWEEN 12 AND 2048
    AND redirect_uri !~ '[[:space:]]'
  ),
  flow_kind pg_catalog.text NOT NULL
    CHECK (flow_kind IN ('first_time', 'reauthorization')),
  expires_at pg_catalog.timestamptz NOT NULL,
  consumed_at pg_catalog.timestamptz,
  completed_at pg_catalog.timestamptz,
  failed_at pg_catalog.timestamptz,
  failure_code pg_catalog.text,
  created_at pg_catalog.timestamptz NOT NULL DEFAULT pg_catalog.now(),
  CONSTRAINT mailbox_oauth_authorization_state_terminal_check CHECK (
    pg_catalog.num_nonnulls(completed_at, failed_at) <= 1
    AND (completed_at IS NULL OR consumed_at IS NOT NULL)
    AND (failed_at IS NULL OR consumed_at IS NOT NULL)
    AND ((failed_at IS NULL AND failure_code IS NULL)
      OR (failed_at IS NOT NULL AND failure_code IS NOT NULL))
  )
);

COMMENT ON TABLE public.mailbox_oauth_authorization_states IS
  'Short-lived Gmail OAuth continuations. Only a SHA-256 digest of the random state is stored; authorization codes and OAuth tokens are never persisted here.';

CREATE INDEX mailbox_oauth_authorization_states_expiry_idx
  ON public.mailbox_oauth_authorization_states(expires_at);

ALTER TABLE public.mailbox_oauth_authorization_states ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.mailbox_oauth_authorization_states
  FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.begin_mailbox_oauth_authorization(
  p_workspace_id pg_catalog.uuid,
  p_mailbox_connection_id pg_catalog.uuid,
  p_state_hash pg_catalog.text,
  p_redirect_uri pg_catalog.text,
  p_expires_at pg_catalog.timestamptz
)
RETURNS TABLE (
  authorization_id pg_catalog.uuid,
  flow_kind pg_catalog.text
) AS $$
DECLARE
  v_actor_profile_id pg_catalog.uuid;
  v_authorization_id pg_catalog.uuid;
  v_flow_kind pg_catalog.text;
BEGIN
  v_actor_profile_id := public.current_user_profile_id();
  IF auth.uid() IS NULL OR v_actor_profile_id IS NULL THEN
    RAISE EXCEPTION 'not_authorized' USING ERRCODE = 'P0001';
  END IF;

  IF p_state_hash IS NULL OR p_state_hash !~ '^[0-9a-f]{64}$'
     OR p_redirect_uri IS NULL OR pg_catalog.length(p_redirect_uri) NOT BETWEEN 12 AND 2048
     OR p_redirect_uri ~ '[[:space:]]'
     OR p_expires_at <= pg_catalog.now()
     OR p_expires_at > pg_catalog.now() + pg_catalog.interval '10 minutes' THEN
    RAISE EXCEPTION 'oauth_request_invalid' USING ERRCODE = 'P0001';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.workspaces AS workspace
    JOIN public.workspace_memberships AS membership
      ON membership.workspace_id = workspace.id
    WHERE workspace.id = p_workspace_id
      AND workspace.workspace_status = 'active'
      AND membership.profile_id = v_actor_profile_id
      AND membership.role IN ('advisor', 'admin')
      AND membership.status = 'active'
      AND membership.ended_at IS NULL
  ) THEN
    RAISE EXCEPTION 'not_authorized' USING ERRCODE = 'P0001';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.mailbox_connections AS mailbox
    WHERE mailbox.id = p_mailbox_connection_id
      AND mailbox.workspace_id = p_workspace_id
      AND pg_catalog.lower(mailbox.oauth_provider) = 'gmail'
      AND mailbox.status IN ('active', 'reauthorization_required')
  ) THEN
    RAISE EXCEPTION 'mailbox_connection_not_found' USING ERRCODE = 'P0001';
  END IF;

  v_flow_kind := CASE WHEN EXISTS (
    SELECT 1 FROM public.mailbox_oauth_credentials AS credentials
    WHERE credentials.workspace_id = p_workspace_id
      AND credentials.mailbox_connection_id = p_mailbox_connection_id
  ) THEN 'reauthorization' ELSE 'first_time' END;

  INSERT INTO public.mailbox_oauth_authorization_states (
    state_hash, workspace_id, mailbox_connection_id, actor_profile_id,
    redirect_uri, flow_kind, expires_at
  ) VALUES (
    p_state_hash, p_workspace_id, p_mailbox_connection_id, v_actor_profile_id,
    p_redirect_uri, v_flow_kind, p_expires_at
  ) RETURNING id INTO v_authorization_id;

  INSERT INTO public.workspace_audit_logs (
    workspace_id, actor_id, action, target_type, target_id, payload,
    actor_profile_id, actor_type, entity_type, entity_id, event_type,
    outcome, occurred_at
  ) VALUES (
    p_workspace_id, v_actor_profile_id, 'mailbox.oauth.authorization_started',
    'mailbox_connection', p_mailbox_connection_id,
    pg_catalog.jsonb_build_object('flow_kind', v_flow_kind),
    v_actor_profile_id, 'workspace_user', 'mailbox_connection',
    p_mailbox_connection_id, 'mailbox.oauth.authorization_started',
    'attempted', pg_catalog.now()
  );

  RETURN QUERY SELECT v_authorization_id, v_flow_kind;
END;
$$ LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '';

CREATE OR REPLACE FUNCTION public.consume_mailbox_oauth_authorization(
  p_state_hash pg_catalog.text,
  p_redirect_uri pg_catalog.text
)
RETURNS TABLE (
  authorization_id pg_catalog.uuid,
  workspace_id pg_catalog.uuid,
  mailbox_connection_id pg_catalog.uuid,
  flow_kind pg_catalog.text
) AS $$
DECLARE
  v_state public.mailbox_oauth_authorization_states;
BEGIN
  SELECT * INTO v_state
  FROM public.mailbox_oauth_authorization_states AS state
  WHERE state.state_hash = p_state_hash
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'oauth_state_invalid' USING ERRCODE = 'P0001';
  END IF;
  IF v_state.redirect_uri <> p_redirect_uri THEN
    RAISE EXCEPTION 'oauth_redirect_uri_mismatch' USING ERRCODE = 'P0001';
  END IF;
  IF v_state.expires_at <= pg_catalog.now() THEN
    RAISE EXCEPTION 'oauth_state_expired' USING ERRCODE = 'P0001';
  END IF;
  IF v_state.consumed_at IS NOT NULL THEN
    RAISE EXCEPTION 'oauth_state_replayed' USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.mailbox_oauth_authorization_states AS state
  SET consumed_at = pg_catalog.now()
  WHERE state.id = v_state.id;

  RETURN QUERY SELECT v_state.id, v_state.workspace_id,
    v_state.mailbox_connection_id, v_state.flow_kind;
END;
$$ LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '';

CREATE OR REPLACE FUNCTION public.fail_mailbox_oauth_authorization(
  p_authorization_id pg_catalog.uuid,
  p_failure_code pg_catalog.text
)
RETURNS pg_catalog.void AS $$
DECLARE
  v_state public.mailbox_oauth_authorization_states;
BEGIN
  IF p_failure_code IS NULL OR p_failure_code !~ '^oauth_[a-z0-9_]{1,80}$' THEN
    RAISE EXCEPTION 'oauth_request_invalid' USING ERRCODE = 'P0001';
  END IF;
  SELECT * INTO v_state FROM public.mailbox_oauth_authorization_states AS state
  WHERE state.id = p_authorization_id FOR UPDATE;
  IF NOT FOUND OR v_state.consumed_at IS NULL OR v_state.completed_at IS NOT NULL
     OR v_state.failed_at IS NOT NULL THEN
    RAISE EXCEPTION 'oauth_state_replayed' USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.mailbox_oauth_authorization_states AS state
  SET failed_at = pg_catalog.now(), failure_code = p_failure_code
  WHERE state.id = p_authorization_id;

  INSERT INTO public.workspace_audit_logs (
    workspace_id, actor_id, action, target_type, target_id, payload,
    actor_profile_id, actor_type, entity_type, entity_id, event_type,
    outcome, error_code, occurred_at
  ) VALUES (
    v_state.workspace_id, v_state.actor_profile_id,
    'mailbox.oauth.authorization_failed', 'mailbox_connection',
    v_state.mailbox_connection_id,
    pg_catalog.jsonb_build_object('flow_kind', v_state.flow_kind),
    v_state.actor_profile_id, 'workspace_user', 'mailbox_connection',
    v_state.mailbox_connection_id, 'mailbox.oauth.authorization_failed',
    'failed', p_failure_code, pg_catalog.now()
  );
END;
$$ LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '';

CREATE OR REPLACE FUNCTION public.complete_mailbox_oauth_authorization(
  p_authorization_id pg_catalog.uuid,
  p_credential_ciphertext pg_catalog.text,
  p_credential_nonce pg_catalog.text,
  p_key_version pg_catalog.int4,
  p_expires_at pg_catalog.timestamptz
)
RETURNS pg_catalog.text AS $$
DECLARE
  v_state public.mailbox_oauth_authorization_states;
BEGIN
  IF p_key_version <> 1 OR p_credential_ciphertext IS NULL
     OR p_credential_ciphertext = '' THEN
    RAISE EXCEPTION 'oauth_credentials_unavailable' USING ERRCODE = 'P0001';
  END IF;
  BEGIN
    IF p_credential_nonce IS NULL
       OR pg_catalog.octet_length(pg_catalog.decode(p_credential_nonce, 'base64')) <> 12 THEN
      RAISE EXCEPTION 'oauth_credentials_unavailable';
    END IF;
    PERFORM pg_catalog.decode(p_credential_ciphertext, 'base64');
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'oauth_credentials_unavailable' USING ERRCODE = 'P0001';
  END;

  SELECT * INTO v_state FROM public.mailbox_oauth_authorization_states AS state
  WHERE state.id = p_authorization_id FOR UPDATE;
  IF NOT FOUND OR v_state.consumed_at IS NULL OR v_state.completed_at IS NOT NULL
     OR v_state.failed_at IS NOT NULL
     OR pg_catalog.now() > v_state.expires_at + pg_catalog.interval '2 minutes' THEN
    RAISE EXCEPTION 'oauth_state_replayed' USING ERRCODE = 'P0001';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.workspaces AS workspace
    JOIN public.workspace_memberships AS membership
      ON membership.workspace_id = workspace.id
    JOIN public.mailbox_connections AS mailbox
      ON mailbox.workspace_id = workspace.id
    WHERE workspace.id = v_state.workspace_id
      AND workspace.workspace_status = 'active'
      AND membership.profile_id = v_state.actor_profile_id
      AND membership.role IN ('advisor', 'admin')
      AND membership.status = 'active'
      AND membership.ended_at IS NULL
      AND mailbox.id = v_state.mailbox_connection_id
      AND pg_catalog.lower(mailbox.oauth_provider) = 'gmail'
      AND mailbox.status IN ('active', 'reauthorization_required')
  ) THEN
    RAISE EXCEPTION 'not_authorized' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.mailbox_oauth_credentials (
    mailbox_connection_id, workspace_id, credential_ciphertext,
    credential_nonce, key_version, expires_at, refreshed_at
  ) VALUES (
    v_state.mailbox_connection_id, v_state.workspace_id,
    p_credential_ciphertext, p_credential_nonce, p_key_version,
    p_expires_at, pg_catalog.now()
  ) ON CONFLICT (mailbox_connection_id) DO UPDATE
    SET credential_ciphertext = EXCLUDED.credential_ciphertext,
        credential_nonce = EXCLUDED.credential_nonce,
        key_version = EXCLUDED.key_version,
        expires_at = EXCLUDED.expires_at,
        refreshed_at = pg_catalog.now(),
        updated_at = pg_catalog.now()
    WHERE public.mailbox_oauth_credentials.workspace_id = v_state.workspace_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'oauth_credentials_unavailable' USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.mailbox_connections AS mailbox
  SET status = 'active', updated_at = pg_catalog.now()
  WHERE mailbox.id = v_state.mailbox_connection_id
    AND mailbox.workspace_id = v_state.workspace_id;

  UPDATE public.mailbox_oauth_authorization_states AS state
  SET completed_at = pg_catalog.now()
  WHERE state.id = v_state.id;

  INSERT INTO public.workspace_audit_logs (
    workspace_id, actor_id, action, target_type, target_id, payload,
    actor_profile_id, actor_type, entity_type, entity_id, event_type,
    outcome, occurred_at
  ) VALUES (
    v_state.workspace_id, v_state.actor_profile_id,
    'mailbox.oauth.authorization_completed', 'mailbox_connection',
    v_state.mailbox_connection_id,
    pg_catalog.jsonb_build_object('flow_kind', v_state.flow_kind),
    v_state.actor_profile_id, 'workspace_user', 'mailbox_connection',
    v_state.mailbox_connection_id, 'mailbox.oauth.authorization_completed',
    'succeeded', pg_catalog.now()
  );
  RETURN v_state.flow_kind;
END;
$$ LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '';

CREATE OR REPLACE FUNCTION public.revoke_mailbox_oauth_credential(
  p_workspace_id pg_catalog.uuid,
  p_mailbox_connection_id pg_catalog.uuid,
  p_expected_credential_nonce pg_catalog.text
)
RETURNS pg_catalog.void AS $$
DECLARE
  v_actor_profile_id pg_catalog.uuid;
BEGIN
  v_actor_profile_id := public.current_user_profile_id();
  IF auth.uid() IS NULL OR v_actor_profile_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.workspace_memberships AS membership
    WHERE membership.workspace_id = p_workspace_id
      AND membership.profile_id = v_actor_profile_id
      AND membership.role IN ('advisor', 'admin')
      AND membership.status = 'active'
      AND membership.ended_at IS NULL
  ) THEN
    RAISE EXCEPTION 'not_authorized' USING ERRCODE = 'P0001';
  END IF;

  DELETE FROM public.mailbox_oauth_credentials AS credentials
  WHERE credentials.workspace_id = p_workspace_id
    AND credentials.mailbox_connection_id = p_mailbox_connection_id
    AND credentials.credential_nonce = p_expected_credential_nonce;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'oauth_credentials_unavailable' USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.mailbox_connections AS mailbox
  SET status = 'reauthorization_required', updated_at = pg_catalog.now()
  WHERE mailbox.id = p_mailbox_connection_id
    AND mailbox.workspace_id = p_workspace_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'mailbox_connection_not_found' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.workspace_audit_logs (
    workspace_id, actor_id, action, target_type, target_id,
    actor_profile_id, actor_type, entity_type, entity_id, event_type,
    outcome, occurred_at
  ) VALUES (
    p_workspace_id, v_actor_profile_id, 'mailbox.oauth.revoked',
    'mailbox_connection', p_mailbox_connection_id,
    v_actor_profile_id, 'workspace_user', 'mailbox_connection',
    p_mailbox_connection_id, 'mailbox.oauth.revoked', 'succeeded',
    pg_catalog.now()
  );
END;
$$ LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '';

REVOKE ALL ON FUNCTION public.begin_mailbox_oauth_authorization(
  pg_catalog.uuid, pg_catalog.uuid, pg_catalog.text, pg_catalog.text,
  pg_catalog.timestamptz
) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.consume_mailbox_oauth_authorization(
  pg_catalog.text, pg_catalog.text
) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.fail_mailbox_oauth_authorization(
  pg_catalog.uuid, pg_catalog.text
) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.complete_mailbox_oauth_authorization(
  pg_catalog.uuid, pg_catalog.text, pg_catalog.text, pg_catalog.int4,
  pg_catalog.timestamptz
) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.revoke_mailbox_oauth_credential(
  pg_catalog.uuid, pg_catalog.uuid, pg_catalog.text
) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.begin_mailbox_oauth_authorization(
  pg_catalog.uuid, pg_catalog.uuid, pg_catalog.text, pg_catalog.text,
  pg_catalog.timestamptz
) TO authenticated;
GRANT EXECUTE ON FUNCTION public.consume_mailbox_oauth_authorization(
  pg_catalog.text, pg_catalog.text
) TO service_role;
GRANT EXECUTE ON FUNCTION public.fail_mailbox_oauth_authorization(
  pg_catalog.uuid, pg_catalog.text
) TO service_role;
GRANT EXECUTE ON FUNCTION public.complete_mailbox_oauth_authorization(
  pg_catalog.uuid, pg_catalog.text, pg_catalog.text, pg_catalog.int4,
  pg_catalog.timestamptz
) TO service_role;
GRANT EXECUTE ON FUNCTION public.revoke_mailbox_oauth_credential(
  pg_catalog.uuid, pg_catalog.uuid, pg_catalog.text
) TO authenticated;

COMMIT;
