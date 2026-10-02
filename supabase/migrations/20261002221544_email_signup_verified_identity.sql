-- Public signup creates an auth identity, never self-declared business authority.
BEGIN;

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  INSERT INTO public.user_accounts(user_id, account_state)
  VALUES (new.id, 'explorer') ON CONFLICT (user_id) DO NOTHING;
  RETURN new;
END;
$$;
REVOKE ALL ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated, service_role;

-- Invitations are server-issued authority, and only their verified recipient
-- may redeem them. Never match or overwrite a business profile by contact data.
CREATE OR REPLACE FUNCTION public.accept_workspace_invitation(p_plaintext_token text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  u auth.users%rowtype;
  invitation public.workspace_invitations%rowtype;
  profile_id uuid;
BEGIN
  SELECT * INTO u FROM auth.users WHERE id = auth.uid();
  IF u.id IS NULL OR u.email_confirmed_at IS NULL OR nullif(u.email, '') IS NULL THEN
    RAISE EXCEPTION 'invitation_unavailable';
  END IF;
  PERFORM 1 FROM public.user_accounts WHERE user_id = u.id FOR UPDATE;
  SELECT i.* INTO invitation FROM public.workspace_invitations i
  JOIN public.workspaces w ON w.id = i.workspace_id AND w.workspace_status = 'active'
  WHERE i.token_hash = pg_catalog.encode(extensions.digest(p_plaintext_token, 'sha256'), 'hex')
    AND i.status = 'pending' AND i.expires_at > now()
    AND lower(btrim(i.email)) = lower(btrim(u.email))
    AND EXISTS (
      SELECT 1 FROM public.profiles inviter WHERE inviter.id = i.invited_by
      AND inviter.account_status = 'active'
      AND (inviter.role = 'platform_admin' OR EXISTS (
        SELECT 1 FROM public.workspace_memberships m WHERE m.profile_id = inviter.id
        AND m.workspace_id = i.workspace_id AND m.role = 'admin'
        AND m.status = 'active' AND m.ended_at IS NULL)))
  FOR UPDATE OF i;
  IF invitation.id IS NULL THEN RAISE EXCEPTION 'invitation_unavailable'; END IF;
  SELECT p.id INTO profile_id FROM public.profiles p WHERE p.user_id = u.id FOR UPDATE;
  IF profile_id IS NULL THEN
    -- This is a deliberate business invitation, not public signup provisioning.
    INSERT INTO public.profiles(user_id, role, email, full_name, account_status)
    VALUES (u.id, invitation.role, u.email, '', 'active') RETURNING id INTO profile_id;
  ELSIF NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = profile_id AND p.account_status = 'active') THEN
    RAISE EXCEPTION 'invitation_unavailable';
  END IF;
  -- An existing membership is never silently promoted or reactivated.
  INSERT INTO public.workspace_memberships(workspace_id, profile_id, role, status, invited_by)
  VALUES (invitation.workspace_id, profile_id, invitation.role, 'active', invitation.invited_by);
  UPDATE public.workspace_invitations SET status = 'accepted', updated_at = now() WHERE id = invitation.id;
  INSERT INTO public.workspace_audit_logs(workspace_id, actor_id, action, target_type, target_id, payload)
  VALUES (invitation.workspace_id, profile_id, 'invitation_accepted', 'profile', profile_id,
    jsonb_build_object('invitation_id', invitation.id));
  RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION public.accept_workspace_invitation(text) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.accept_workspace_invitation(text) TO authenticated;

CREATE OR REPLACE FUNCTION public.bootstrap_identity()
RETURNS TABLE(account_state public.user_account_state, onboarding_completed boolean, resolution text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  u auth.users%rowtype;
  a public.user_accounts%rowtype;
  p public.profiles%rowtype;
  own_profile uuid;
  linked_profile uuid;
  candidates uuid[];
BEGIN
  SELECT * INTO u FROM auth.users WHERE id = auth.uid();
  IF u.id IS NULL THEN RAISE EXCEPTION 'authentication_required'; END IF;
  INSERT INTO public.user_accounts(user_id) VALUES (u.id) ON CONFLICT (user_id) DO NOTHING;
  SELECT * INTO a FROM public.user_accounts WHERE user_id = u.id FOR UPDATE;

  -- Retain old invitation links, but only redeem after confirmed email ownership.
  IF u.email_confirmed_at IS NOT NULL AND nullif(u.raw_user_meta_data->>'invited_token', '') IS NOT NULL THEN
    BEGIN
      PERFORM public.accept_workspace_invitation(u.raw_user_meta_data->>'invited_token');
    EXCEPTION WHEN raise_exception OR unique_violation THEN
      NULL; -- Invalid/replayed invitation never changes public-facing identity results.
    END;
  END IF;

  SELECT p0.id INTO own_profile FROM public.profiles p0 WHERE p0.user_id = u.id;
  IF own_profile IS NOT NULL THEN
    SELECT * INTO p FROM public.profiles WHERE id = own_profile FOR UPDATE;
    IF p.account_status <> 'active' THEN RAISE EXCEPTION 'account_unavailable'; END IF;
    IF p.role IN ('advisor', 'admin', 'operations', 'platform_admin') THEN
      UPDATE public.user_accounts SET account_state = 'advisor', onboarding_completed = true WHERE user_id = u.id;
      RETURN QUERY SELECT 'advisor'::public.user_account_state, true, 'advisor'::text;
      RETURN;
    END IF;
  END IF;

  SELECT l.profile_id INTO linked_profile FROM public.investor_account_links l
  WHERE l.user_id = u.id AND l.link_status = 'active';
  IF linked_profile IS NOT NULL THEN
    SELECT * INTO p FROM public.profiles WHERE id = linked_profile FOR UPDATE;
    IF p.id IS NULL OR p.account_status <> 'active' OR p.role NOT IN ('investor', 'client')
      OR (p.user_id IS NOT NULL AND p.user_id <> u.id)
      OR (own_profile IS NOT NULL AND own_profile <> p.id) THEN
      RAISE EXCEPTION 'account_unavailable';
    END IF;
    UPDATE public.profiles SET user_id = u.id WHERE id = p.id AND user_id IS NULL;
    UPDATE public.user_accounts SET account_state = 'linked_investor', onboarding_completed = true WHERE user_id = u.id;
    RETURN QUERY SELECT 'linked_investor'::public.user_account_state, true, 'existing_link'::text;
    RETURN;
  END IF;

  IF u.email_confirmed_at IS NULL OR nullif(u.email, '') IS NULL THEN
    RAISE EXCEPTION 'email_verification_required';
  END IF;

  -- Count all active trusted contact matches BEFORE ownership filtering. A
  -- conflicting match must not make an ambiguous email appear unique.
  SELECT array_agg(p0.id) INTO candidates FROM public.profiles p0
  WHERE p0.role IN ('investor', 'client') AND p0.account_status = 'active'
    AND lower(btrim(p0.verified_email)) = lower(btrim(u.email));
  IF cardinality(candidates) = 1 THEN
    SELECT * INTO p FROM public.profiles WHERE id = candidates[1] FOR UPDATE;
    IF p.account_status = 'active' AND p.role IN ('investor', 'client')
      AND lower(btrim(p.verified_email)) = lower(btrim(u.email))
      AND (p.user_id IS NULL OR p.user_id = u.id)
      AND (own_profile IS NULL OR own_profile = p.id)
      AND NOT EXISTS (SELECT 1 FROM public.investor_account_links l
        WHERE (l.profile_id = p.id AND l.link_status = 'active')
          OR (l.profile_id = p.id AND l.user_id = u.id)) THEN
      BEGIN
        INSERT INTO public.investor_account_links(user_id, profile_id, verification_method, verified_at)
        VALUES (u.id, p.id, 'verified_email', now());
        UPDATE public.profiles SET user_id = u.id WHERE id = p.id AND user_id IS NULL;
        UPDATE public.user_accounts SET account_state = 'linked_investor', onboarding_completed = true WHERE user_id = u.id;
        RETURN QUERY SELECT 'linked_investor'::public.user_account_state, true, 'automatic_link'::text;
        RETURN;
      EXCEPTION WHEN unique_violation THEN NULL;
      END;
    END IF;
  END IF;
  -- Preserve an explicit portfolio-linking choice. No-match and conflicts have
  -- identical results; neither reveals whether another investor exists.
  UPDATE public.user_accounts SET account_state = CASE
    WHEN a.account_state = 'link_pending' AND a.onboarding_completed THEN 'link_pending'::public.user_account_state
    ELSE 'explorer'::public.user_account_state END, onboarding_completed = true WHERE user_id = u.id
  RETURNING * INTO a;
  RETURN QUERY SELECT a.account_state, true,
    CASE WHEN a.account_state = 'link_pending' THEN 'verification_pending' ELSE 'no_match' END;
END;
$$;
REVOKE ALL ON FUNCTION public.bootstrap_identity() FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.bootstrap_identity() TO authenticated;

CREATE OR REPLACE FUNCTION public.complete_onboarding_choice(choice text)
RETURNS public.user_account_state LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE next_state public.user_account_state;
BEGIN
  IF auth.uid() IS NULL OR NOT EXISTS (SELECT 1 FROM auth.users WHERE id = auth.uid() AND email_confirmed_at IS NOT NULL) THEN
    RAISE EXCEPTION 'email_verification_required';
  END IF;
  IF choice NOT IN ('explorer', 'link_pending') OR choice IS NULL THEN RAISE EXCEPTION 'invalid_onboarding_choice'; END IF;
  UPDATE public.user_accounts SET account_state = choice::public.user_account_state, onboarding_completed = true
  WHERE user_id = auth.uid() AND account_state IN ('explorer', 'link_pending')
    AND NOT EXISTS (SELECT 1 FROM public.investor_account_links WHERE user_id = auth.uid() AND link_status = 'active')
  RETURNING account_state INTO next_state;
  IF NOT FOUND THEN RAISE EXCEPTION 'onboarding_unavailable'; END IF;
  RETURN next_state;
END;
$$;
REVOKE ALL ON FUNCTION public.complete_onboarding_choice(text) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.complete_onboarding_choice(text) TO authenticated;

-- Identity state and links are RPC-controlled. Existing RLS remains in force
-- for reads; no authenticated browser (including an advisor) can mutate them.
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.profiles, public.user_accounts, public.investor_account_links FROM PUBLIC, anon, authenticated;
-- Staff can load their own trusted profile even without a workspace; this
-- grants no cross-profile or mutation authority.
CREATE POLICY profiles_self_select ON public.profiles FOR SELECT TO authenticated
USING (user_id = auth.uid());
COMMIT;
