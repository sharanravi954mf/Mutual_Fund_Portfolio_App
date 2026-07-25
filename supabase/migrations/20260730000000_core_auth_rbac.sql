-- Core Authentication and Role-Based Access Control (RBAC) Foundation
-- Adds canonical roles support, account status lifecycle, and triggers.

-- 1. Alter public.profiles table check constraints and columns
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_role_check;
ALTER TABLE public.profiles ADD CONSTRAINT profiles_role_check CHECK (role IN ('investor', 'advisor', 'admin', 'operations', 'client'));

-- Add account_status column
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS account_status text NOT NULL DEFAULT 'active' CHECK (account_status IN ('active', 'inactive', 'suspended'));

-- Add updated_at column
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

-- Update existing client profiles to canonical investor role
UPDATE public.profiles SET role = 'investor' WHERE role = 'client';

-- 2. Update handle_new_user() trigger function to use 'investor' role on signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
DECLARE
  existing_id uuid;
BEGIN
  -- First, insert the user account state
  INSERT INTO public.user_accounts (user_id, account_state)
  VALUES (new.id, 'explorer')
  ON CONFLICT (user_id) DO NOTHING;

  -- Check if there is an existing unregistered client profile matching email/phone
  SELECT id INTO existing_id
  FROM public.profiles
  WHERE (email = new.email AND email IS NOT NULL AND email <> '')
     OR (phone_number = new.phone AND phone_number IS NOT NULL AND phone_number <> '')
  LIMIT 1;

  IF existing_id IS NOT NULL THEN
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
    WHERE id = existing_id;
  ELSE
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
      gen_random_uuid(),
      new.id,
      coalesce(new.raw_user_meta_data ->> 'full_name', ''),
      'investor',
      new.phone,
      new.email,
      'active',
      now(),
      now()
    );
  END IF;

  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

-- 3. Recreate public.is_admin() to check for active admin/advisor/operations roles
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1
    from public.user_accounts account
    join public.profiles profile on profile.user_id = account.user_id
    where account.user_id = auth.uid()
      and (account.account_state = 'advisor' or profile.role in ('advisor', 'admin', 'operations'))
      and profile.account_status = 'active'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

-- 4. Recreate public.has_active_investor_link() to enforce active account status
CREATE OR REPLACE FUNCTION public.has_active_investor_link(target_profile_id uuid)
RETURNS boolean AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1
    FROM public.user_accounts account
    JOIN public.investor_account_links link ON link.user_id = account.user_id
    JOIN public.profiles profile ON profile.id = link.profile_id
    WHERE account.user_id = auth.uid()
      AND account.account_state = 'linked_investor'
      AND link.profile_id = target_profile_id
      AND link.link_status = 'active'
      AND profile.account_status = 'active'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;
