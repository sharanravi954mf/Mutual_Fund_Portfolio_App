-- 1. Drop the foreign key constraint on profiles.id
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_id_fkey;

-- 2. Add user_id column referencing auth.users(id) and email column to profiles
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE UNIQUE;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS email text;

-- 3. Migrate existing profiles to link user_id = id
UPDATE public.profiles SET user_id = id WHERE user_id IS NULL;

-- 4. Set email values for existing test profiles
UPDATE public.profiles SET email = 'admin.sharanfincorp@gmail.com' WHERE role = 'admin' AND email IS NULL;
UPDATE public.profiles SET email = 'client.sharanfincorp@gmail.com' WHERE role = 'client' AND phone_number IS NULL AND email IS NULL;

-- 5. Drop old RLS policies for profiles
DROP POLICY IF EXISTS "Admins have full access to profiles" ON public.profiles;
DROP POLICY IF EXISTS "Clients can view their own profile" ON public.profiles;
DROP POLICY IF EXISTS "Clients can insert their own profile" ON public.profiles;
DROP POLICY IF EXISTS "Clients can update their own profile" ON public.profiles;

-- 6. Create updated RLS policies for profiles checking user_id instead of id
CREATE POLICY "Admins have full access to profiles"
  ON public.profiles FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());
  
CREATE POLICY "Clients can view their own profile"
  ON public.profiles FOR SELECT TO authenticated
  USING (user_id = auth.uid());
  
CREATE POLICY "Clients can insert their own profile"
  ON public.profiles FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());
  
CREATE POLICY "Clients can update their own profile"
  ON public.profiles FOR UPDATE TO authenticated
  USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

-- 7. Drop and recreate portfolios RLS policies
DROP POLICY IF EXISTS "Clients can view their own portfolios" ON public.portfolios;
DROP POLICY IF EXISTS "Clients can insert their own portfolios" ON public.portfolios;
DROP POLICY IF EXISTS "Clients can update their own portfolios" ON public.portfolios;

CREATE POLICY "Clients can view their own portfolios"
  ON public.portfolios FOR SELECT TO authenticated
  USING (client_id IN (SELECT id FROM public.profiles WHERE user_id = auth.uid()));
  
CREATE POLICY "Clients can insert their own portfolios"
  ON public.portfolios FOR INSERT TO authenticated
  WITH CHECK (client_id IN (SELECT id FROM public.profiles WHERE user_id = auth.uid()));
  
CREATE POLICY "Clients can update their own portfolios"
  ON public.portfolios FOR UPDATE TO authenticated
  USING (client_id IN (SELECT id FROM public.profiles WHERE user_id = auth.uid()))
  WITH CHECK (client_id IN (SELECT id FROM public.profiles WHERE user_id = auth.uid()));

-- 8. Drop and recreate transactions RLS policies
DROP POLICY IF EXISTS "Clients can view their own transactions" ON public.transactions;
DROP POLICY IF EXISTS "Clients can insert their own transactions" ON public.transactions;
DROP POLICY IF EXISTS "Clients can update their own transactions" ON public.transactions;

CREATE POLICY "Clients can view their own transactions"
  ON public.transactions FOR SELECT TO authenticated
  USING (
    exists (
      select 1 from public.portfolios p
      join public.profiles pr on p.client_id = pr.id
      where p.id = transactions.portfolio_id and pr.user_id = auth.uid()
    )
  );
  
CREATE POLICY "Clients can insert their own transactions"
  ON public.transactions FOR INSERT TO authenticated
  WITH CHECK (
    exists (
      select 1 from public.portfolios p
      join public.profiles pr on p.client_id = pr.id
      where p.id = portfolio_id and pr.user_id = auth.uid()
    )
  );
  
CREATE POLICY "Clients can update their own transactions"
  ON public.transactions FOR UPDATE TO authenticated
  USING (
    exists (
      select 1 from public.portfolios p
      join public.profiles pr on p.client_id = pr.id
      where p.id = transactions.portfolio_id and pr.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.portfolios p
      join public.profiles pr on p.client_id = pr.id
      where p.id = portfolio_id and pr.user_id = auth.uid()
    )
  );

-- 9. Update handle_new_user trigger to claim/link profiles on signup
create or replace function public.handle_new_user()
returns trigger as $$
declare
  existing_id uuid;
begin
  -- Search for existing profile by email, phone, or PAN
  select id into existing_id from public.profiles
  where (email = new.email and email is not null and email <> '')
     or (phone_number = new.phone and phone_number is not null and phone_number <> '')
     or (pan = coalesce(new.raw_user_meta_data ->> 'pan', '') and pan is not null and pan <> '')
  limit 1;
  
  if existing_id is not null then
    -- Link existing profile to the new auth user
    update public.profiles
    set 
      user_id = new.id,
      full_name = case when (full_name is null or full_name = '') then coalesce(new.raw_user_meta_data ->> 'full_name', '') else full_name end,
      phone_number = coalesce(new.phone, phone_number),
      email = coalesce(new.email, email)
    where id = existing_id;
  else
    -- Create brand new profile
    insert into public.profiles (id, user_id, full_name, role, phone_number, email, created_at)
    values (
      gen_random_uuid(),
      new.id,
      coalesce(new.raw_user_meta_data ->> 'full_name', ''),
      coalesce(new.raw_user_meta_data ->> 'role', 'client'),
      new.phone,
      new.email,
      now()
    );
  end if;
  
  return new;
end;
$$ language plpgsql security definer set search_path = public, pg_temp;
