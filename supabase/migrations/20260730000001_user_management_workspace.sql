-- Migration: User Management & Workspace Foundation
-- Suffix: 20260730000001_user_management_workspace.sql

BEGIN;

-- 1. Create Workspaces table
CREATE TABLE public.workspaces (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text not null unique,
  owner_profile_id uuid, -- foreign key constraint added after profiles constraint definition
  workspace_status text not null check (workspace_status in ('active', 'suspended', 'archived')) default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 2. Create Workspace Memberships table
CREATE TABLE public.workspace_memberships (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade on update cascade,
  role text not null check (role in ('investor', 'advisor', 'admin', 'operations', 'client')),
  status text not null check (status in ('active', 'inactive', 'suspended')) default 'active',
  joined_at timestamptz not null default now(),
  ended_at timestamptz,
  invited_by uuid references public.profiles(id) on delete restrict on update cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Index for unique active memberships
CREATE UNIQUE INDEX unique_active_membership 
ON public.workspace_memberships (workspace_id, profile_id) 
WHERE (ended_at IS NULL);

-- 3. Create Advisor-Investor Assignments table
CREATE TABLE public.advisor_investor_assignments (
  id uuid primary key default gen_random_uuid(),
  advisor_id uuid not null references public.profiles(id) on delete restrict on update cascade,
  investor_id uuid not null references public.profiles(id) on delete restrict on update cascade,
  assigned_by uuid references public.profiles(id) on delete restrict on update cascade,
  assigned_at timestamptz not null default now(),
  ended_by uuid references public.profiles(id) on delete restrict on update cascade,
  ended_at timestamptz,
  status text check (status in ('active', 'ended')) default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint advisor_investor_different check (advisor_id <> investor_id)
);

-- Index for unique active assignments
CREATE UNIQUE INDEX unique_active_advisor_investor_assignment 
ON public.advisor_investor_assignments (advisor_id, investor_id) 
WHERE (ended_at IS NULL);

-- 4. Create Workspace Invitations table
CREATE TABLE public.workspace_invitations (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  email text not null,
  role text not null check (role in ('investor', 'advisor', 'admin', 'operations')),
  invited_by uuid not null references public.profiles(id) on delete restrict on update cascade,
  token_hash text not null unique,
  status text not null check (status in ('pending', 'accepted', 'expired', 'revoked')) default 'pending',
  expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 5. Create Workspace Audit Logs table
CREATE TABLE public.workspace_audit_logs (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  actor_id uuid references public.profiles(id) on delete restrict on update cascade,
  action text not null,
  event_version integer not null default 1,
  target_type text not null,
  target_id uuid,
  payload jsonb,
  created_at timestamptz not null default now()
);

-- Immutability enforcement trigger for audit logs
CREATE OR REPLACE FUNCTION public.prevent_audit_log_modification()
RETURNS trigger AS $$
BEGIN
  RAISE EXCEPTION 'Audit logs are immutable and cannot be updated or deleted';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER enforce_audit_log_immutability
  BEFORE UPDATE OR DELETE ON public.workspace_audit_logs
  FOR EACH ROW EXECUTE FUNCTION public.prevent_audit_log_modification();

-- 6. Add foreign key from workspaces to profiles
ALTER TABLE public.workspaces
  ADD CONSTRAINT workspaces_owner_profile_id_fkey
  FOREIGN KEY (owner_profile_id) REFERENCES public.profiles(id) ON DELETE RESTRICT ON UPDATE CASCADE;

-- Add platform admin check constraint to profiles role
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_role_check;
ALTER TABLE public.profiles ADD CONSTRAINT profiles_role_check CHECK (role IN ('platform_admin', 'user', 'investor', 'advisor', 'admin', 'operations', 'client'));

-- 7. Deterministic slug generation helper
CREATE OR REPLACE FUNCTION public.generate_unique_workspace_slug(p_name text)
RETURNS text AS $$
DECLARE
  v_slug text;
  v_counter integer := 0;
  v_final_slug text;
BEGIN
  -- Lowercase and replace non-alphanumerics with a hyphen
  v_slug := lower(regexp_replace(p_name, '[^a-zA-Z0-9]+', '-', 'g'));
  -- Trim leading/trailing hyphens
  v_slug := regexp_replace(v_slug, '^-+|-+$', '', 'g');
  
  IF v_slug = '' OR v_slug IS NULL THEN
    v_slug := 'workspace';
  END IF;
  
  v_final_slug := v_slug;
  
  -- Collision safety loop
  WHILE exists(SELECT 1 FROM public.workspaces WHERE slug = v_final_slug) LOOP
    v_counter := v_counter + 1;
    v_final_slug := v_slug || '-' || v_counter;
  END LOOP;
  
  RETURN v_final_slug;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

-- 8. Backfill legacy users into Personal Workspaces
DO $$
DECLARE
  v_profile RECORD;
  v_workspace_id uuid;
  v_workspace_name text;
  v_workspace_slug text;
  v_membership_role text;
BEGIN
  FOR v_profile IN SELECT * FROM public.profiles LOOP
    -- Determine naming
    v_workspace_name := coalesce(v_profile.full_name, 'Workspace') || ' Personal Workspace';
    v_workspace_id := gen_random_uuid();
    v_workspace_slug := public.generate_unique_workspace_slug(v_workspace_name);

    -- Insert workspace
    INSERT INTO public.workspaces (id, name, slug, owner_profile_id, workspace_status)
    VALUES (v_workspace_id, v_workspace_name, v_workspace_slug, v_profile.id, 'active');

    -- Determine membership role
    IF v_profile.role IN ('admin', 'advisor') THEN
      v_membership_role := 'admin';
    ELSIF v_profile.role = 'operations' THEN
      v_membership_role := 'operations';
    ELSE
      v_membership_role := 'investor';
    END IF;

    -- Create membership
    INSERT INTO public.workspace_memberships (workspace_id, profile_id, role, status)
    VALUES (v_workspace_id, v_profile.id, v_membership_role, 'active');
  END LOOP;
END;
$$;

-- 9. Security Definer Helpers for RLS
CREATE OR REPLACE FUNCTION public.current_user_profile_id()
RETURNS uuid AS $$
DECLARE
  v_profile_id uuid;
BEGIN
  SELECT id INTO v_profile_id FROM public.profiles WHERE user_id = auth.uid();
  RETURN v_profile_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

CREATE OR REPLACE FUNCTION public.is_platform_admin()
RETURNS boolean AS $$
BEGIN
  RETURN exists (
    SELECT 1 
    FROM public.profiles 
    WHERE user_id = auth.uid() 
      AND role = 'platform_admin' 
      AND account_status = 'active'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

CREATE OR REPLACE FUNCTION public.current_user_workspace_ids()
RETURNS TABLE(workspace_id uuid) AS $$
BEGIN
  RETURN QUERY
  SELECT m.workspace_id 
  FROM public.workspace_memberships m
  WHERE m.profile_id = public.current_user_profile_id() 
    AND m.status = 'active';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

CREATE OR REPLACE FUNCTION public.is_workspace_admin(p_workspace_id uuid)
RETURNS boolean AS $$
BEGIN
  RETURN exists (
    SELECT 1 
    FROM public.workspace_memberships 
    WHERE workspace_id = p_workspace_id
      AND profile_id = public.current_user_profile_id() 
      AND role = 'admin' 
      AND status = 'active'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

CREATE OR REPLACE FUNCTION public.is_workspace_admin_or_ops(p_workspace_id uuid)
RETURNS boolean AS $$
BEGIN
  RETURN exists (
    SELECT 1 
    FROM public.workspace_memberships 
    WHERE workspace_id = p_workspace_id
      AND profile_id = public.current_user_profile_id() 
      AND role in ('admin', 'operations') 
      AND status = 'active'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

CREATE OR REPLACE FUNCTION public.can_manage_assignment(p_advisor_id uuid)
RETURNS boolean AS $$
BEGIN
  RETURN exists (
    SELECT 1 
    FROM public.workspace_memberships m
    WHERE m.profile_id = public.current_user_profile_id() 
      AND m.status = 'active' 
      AND m.role = 'admin'
      AND m.workspace_id IN (
        SELECT workspace_id 
        FROM public.workspace_memberships 
        WHERE profile_id = p_advisor_id
      )
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

CREATE OR REPLACE FUNCTION public.can_access_profile(p_profile_id uuid)
RETURNS boolean AS $$
BEGIN
  RETURN public.is_platform_admin() OR exists (
    SELECT 1 
    FROM public.workspace_memberships m1
    JOIN public.workspace_memberships m2 ON m1.workspace_id = m2.workspace_id
    WHERE m1.profile_id = public.current_user_profile_id() 
      AND m1.status = 'active'
      AND m2.profile_id = p_profile_id 
      AND m2.status = 'active'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

CREATE OR REPLACE FUNCTION public.can_access_investor(p_investor_profile_id uuid)
RETURNS boolean AS $$
BEGIN
  RETURN public.is_platform_admin() OR exists (
    SELECT 1
    FROM public.workspace_memberships m1
    JOIN public.workspace_memberships m2 ON m1.workspace_id = m2.workspace_id
    WHERE m1.profile_id = public.current_user_profile_id()
      AND m1.status = 'active'
      AND m1.role in ('advisor', 'admin', 'operations')
      AND m2.profile_id = p_investor_profile_id
      AND m2.status = 'active'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

-- 10. Update handle_new_user trigger function
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
DECLARE
  v_profile_id uuid;
  v_role text;
  v_workspace_id uuid;
  v_workspace_name text;
  v_workspace_slug text;
  v_membership_role text;
  v_invited_token text;
  v_invitation RECORD;
BEGIN
  -- First, insert the user account state
  INSERT INTO public.user_accounts (user_id, account_state)
  VALUES (new.id, 'explorer')
  ON CONFLICT (user_id) DO NOTHING;

  -- Check if there is an existing unregistered client profile matching email/phone
  SELECT id INTO v_profile_id
  FROM public.profiles
  WHERE (email = new.email AND email IS NOT NULL AND email <> '')
     OR (phone_number = new.phone AND phone_number IS NOT NULL AND phone_number <> '')
  LIMIT 1;

  -- Determine role
  v_role := coalesce(new.raw_user_meta_data->>'role', 'investor');

  IF v_profile_id IS NOT NULL THEN
    UPDATE public.profiles
    SET
      user_id = new.id,
      full_name = CASE
        WHEN full_name IS NULL OR full_name = ''
          THEN coalesce(new.raw_user_meta_data ->> 'full_name', '')
        ELSE full_name
      END,
      phone_number = coalesce(new.phone, phone_number),
      email = coalesce(new.email, email),
      updated_at = now()
    WHERE id = v_profile_id;
  ELSE
    v_profile_id := gen_random_uuid();
    INSERT INTO public.profiles (
      id,
      user_id,
      full_name,
      role,
      phone_number,
      email,
      account_status,
      created_at,
      updated_at
    )
    VALUES (
      v_profile_id,
      new.id,
      coalesce(new.raw_user_meta_data ->> 'full_name', ''),
      v_role,
      new.phone,
      new.email,
      'active',
      now(),
      now()
    );
  END IF;

  -- Handle Workspace affiliation
  v_invited_token := new.raw_user_meta_data->>'invited_token';
  IF v_invited_token IS NOT NULL THEN
    -- Find and accept invitation
    SELECT * INTO v_invitation 
    FROM public.workspace_invitations
    WHERE token_hash = encode(extensions.digest(v_invited_token, 'sha256'), 'hex')
      AND status = 'pending'
      AND expires_at > now()
    LIMIT 1;

    IF v_invitation.id IS NOT NULL THEN
      -- Create membership
      INSERT INTO public.workspace_memberships (workspace_id, profile_id, role, status)
      VALUES (v_invitation.workspace_id, v_profile_id, v_invitation.role, 'active');

      -- Update invitation
      UPDATE public.workspace_invitations
      SET status = 'accepted', updated_at = now()
      WHERE id = v_invitation.id;
    END IF;
  ELSE
    -- Direct signup: Create a Personal Workspace for the user
    v_workspace_id := gen_random_uuid();
    v_workspace_name := coalesce(new.raw_user_meta_data->>'full_name', 'Personal') || ' Workspace';
    v_workspace_slug := public.generate_unique_workspace_slug(v_workspace_name);

    INSERT INTO public.workspaces (id, name, slug, owner_profile_id, workspace_status)
    VALUES (v_workspace_id, v_workspace_name, v_workspace_slug, v_profile_id, 'active');

    -- Create membership
    IF v_role = 'platform_admin' THEN
      v_membership_role := 'admin';
    ELSE
      v_membership_role := coalesce(new.raw_user_meta_data->>'membership_role', 'investor');
    END IF;

    INSERT INTO public.workspace_memberships (workspace_id, profile_id, role, status)
    VALUES (v_workspace_id, v_profile_id, v_membership_role, 'active');
  END IF;

  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

-- 11. Trigger for Advisor-Investor assignment validation
CREATE OR REPLACE FUNCTION public.verify_advisor_investor_assignment()
RETURNS trigger AS $$
DECLARE
  v_advisor_role text;
  v_investor_role text;
  v_advisor_active_workspaces uuid[];
  v_investor_active_workspaces uuid[];
BEGIN
  -- Get advisor details
  SELECT role INTO v_advisor_role FROM public.profiles WHERE id = new.advisor_id;
  IF v_advisor_role NOT IN ('advisor', 'admin', 'platform_admin') THEN
    RAISE EXCEPTION 'Assigned advisor must have an advisor or admin role';
  END IF;

  -- Get investor details
  SELECT role INTO v_investor_role FROM public.profiles WHERE id = new.investor_id;
  IF v_investor_role NOT IN ('investor', 'client') THEN
    RAISE EXCEPTION 'Assigned investor must have an investor or client role';
  END IF;

  -- Enforce same workspace constraint
  SELECT array_agg(workspace_id) INTO v_advisor_active_workspaces FROM public.workspace_memberships WHERE profile_id = new.advisor_id AND status = 'active';
  SELECT array_agg(workspace_id) INTO v_investor_active_workspaces FROM public.workspace_memberships WHERE profile_id = new.investor_id AND status = 'active';
  
  IF NOT (v_advisor_active_workspaces && v_investor_active_workspaces) THEN
    RAISE EXCEPTION 'Advisor and Investor must belong to at least one shared active workspace';
  END IF;

  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

CREATE TRIGGER verify_assignment_integrity
  BEFORE INSERT OR UPDATE ON public.advisor_investor_assignments
  FOR EACH ROW EXECUTE FUNCTION public.verify_advisor_investor_assignment();

-- 12. Safe Acceptance RPC function for invitations
CREATE OR REPLACE FUNCTION public.accept_workspace_invitation(p_plaintext_token text)
RETURNS boolean AS $$
DECLARE
  v_token_hash text;
  v_invitation RECORD;
  v_profile_id uuid;
BEGIN
  v_token_hash := encode(extensions.digest(p_plaintext_token, 'sha256'), 'hex');
  v_profile_id := public.current_user_profile_id();
  
  -- Find the invitation
  SELECT * INTO v_invitation 
  FROM public.workspace_invitations
  WHERE token_hash = v_token_hash
    AND status = 'pending'
    AND expires_at > now()
  FOR UPDATE;

  IF v_invitation.id IS NULL THEN
    RAISE EXCEPTION 'Invitation token is invalid or has expired';
  END IF;

  -- Create membership for current user
  INSERT INTO public.workspace_memberships (workspace_id, profile_id, role, status)
  VALUES (v_invitation.workspace_id, v_profile_id, v_invitation.role, 'active');

  -- Mark invitation accepted
  UPDATE public.workspace_invitations
  SET status = 'accepted', updated_at = now()
  WHERE id = v_invitation.id;

  -- Log audit trail
  INSERT INTO public.workspace_audit_logs (workspace_id, actor_id, action, target_type, target_id, payload)
  VALUES (v_invitation.workspace_id, v_profile_id, 'invitation_accepted', 'profile', v_profile_id, jsonb_build_object('invitation_id', v_invitation.id));

  RETURN true;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

-- 13. Enable RLS and create new workspace-aware policies
ALTER TABLE public.workspaces ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workspace_memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.advisor_investor_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workspace_invitations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workspace_audit_logs ENABLE ROW LEVEL SECURITY;

-- Workspaces Policies
CREATE POLICY "Users can view workspaces they are members of"
  ON public.workspaces FOR SELECT TO authenticated
  USING (public.is_platform_admin() OR id IN (SELECT public.current_user_workspace_ids()));

CREATE POLICY "Platform admins manage workspaces"
  ON public.workspaces FOR ALL TO authenticated
  USING (public.is_platform_admin()) WITH CHECK (public.is_platform_admin());

-- Workspace Memberships Policies
CREATE POLICY "Users can view memberships in their workspaces"
  ON public.workspace_memberships FOR SELECT TO authenticated
  USING (public.is_platform_admin() OR workspace_id IN (SELECT public.current_user_workspace_ids()));

CREATE POLICY "Admins can manage memberships in their workspaces"
  ON public.workspace_memberships FOR ALL TO authenticated
  USING (
    public.is_platform_admin() OR public.is_workspace_admin(workspace_id)
  );

-- Advisor Investor Assignments Policies
CREATE POLICY "Users can view assignments in their workspaces"
  ON public.advisor_investor_assignments FOR SELECT TO authenticated
  USING (
    public.is_platform_admin() OR 
    advisor_id = public.current_user_profile_id() OR 
    investor_id = public.current_user_profile_id() OR
    exists (
      SELECT 1 
      FROM public.workspace_memberships m1
      JOIN public.workspace_memberships m2 ON m1.workspace_id = m2.workspace_id
      WHERE m1.profile_id = public.current_user_profile_id() 
        AND m1.status = 'active'
        AND m1.role IN ('admin', 'operations')
        AND (m2.profile_id = advisor_id OR m2.profile_id = investor_id)
        AND m2.status = 'active'
    )
  );

CREATE POLICY "Admins can manage assignments in their workspaces"
  ON public.advisor_investor_assignments FOR ALL TO authenticated
  USING (
    public.is_platform_admin() OR public.can_manage_assignment(advisor_id)
  );

-- Workspace Invitations Policies
CREATE POLICY "Admins can view invitations in their workspaces"
  ON public.workspace_invitations FOR SELECT TO authenticated
  USING (
    public.is_platform_admin() OR public.is_workspace_admin_or_ops(workspace_id)
  );

CREATE POLICY "Admins can manage invitations in their workspaces"
  ON public.workspace_invitations FOR ALL TO authenticated
  USING (
    public.is_platform_admin() OR public.is_workspace_admin(workspace_id)
  );

-- Workspace Audit Logs Policies
CREATE POLICY "Admins can view audit logs in their workspaces"
  ON public.workspace_audit_logs FOR SELECT TO authenticated
  USING (
    public.is_platform_admin() OR public.is_workspace_admin_or_ops(workspace_id)
  );

-- 14. Refine profiles, portfolios, transactions RLS policies
DROP POLICY IF EXISTS "Admins have full access to profiles" ON public.profiles;
CREATE POLICY "Admins have full access to profiles"
  ON public.profiles FOR ALL TO authenticated
  USING (public.is_platform_admin() OR public.can_access_profile(id))
  WITH CHECK (public.is_platform_admin() OR public.can_access_profile(id));

DROP POLICY IF EXISTS "Admins have full access to portfolios" ON public.portfolios;
CREATE POLICY "Admins have full access to portfolios"
  ON public.portfolios FOR ALL TO authenticated
  USING (public.is_platform_admin() OR public.can_access_investor(client_id))
  WITH CHECK (public.is_platform_admin() OR public.can_access_investor(client_id));

DROP POLICY IF EXISTS "Admins have full access to transactions" ON public.transactions;
CREATE POLICY "Admins have full access to transactions"
  ON public.transactions FOR ALL TO authenticated
  USING (
    public.is_platform_admin() OR exists (
      SELECT 1 
      FROM public.portfolios portfolio 
      WHERE portfolio.id = transactions.portfolio_id 
        AND public.can_access_investor(portfolio.client_id)
    )
  )
  WITH CHECK (
    public.is_platform_admin() OR exists (
      SELECT 1 
      FROM public.portfolios portfolio 
      WHERE portfolio.id = transactions.portfolio_id 
        AND public.can_access_investor(portfolio.client_id)
    )
  );

DROP POLICY IF EXISTS "Admins have full access to mutual_funds" ON public.mutual_funds;
CREATE POLICY "Platform admins can manage mutual_funds"
  ON public.mutual_funds FOR ALL TO authenticated
  USING (public.is_platform_admin())
  WITH CHECK (public.is_platform_admin());

CREATE POLICY "All authenticated users can view mutual_funds"
  ON public.mutual_funds FOR SELECT TO authenticated
  USING (true);

COMMIT;
