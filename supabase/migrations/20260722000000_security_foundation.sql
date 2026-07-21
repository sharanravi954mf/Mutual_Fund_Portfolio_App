-- Sprint 3.1 security foundation.
-- Keep business profiles separate from Auth identities and restrict all
-- privileged database operations to trusted server-side callers.

-- The current business profile may have a generated primary key, so resolve
-- administrators through the Auth linkage rather than profiles.id.
create or replace function public.is_admin()
returns boolean as $$
begin
  return exists (
    select 1
    from public.profiles
    where user_id = auth.uid()
      and role = 'admin'
  );
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to authenticated, service_role;

-- Auth-created profiles always receive the non-privileged client role. The
-- trigger preserves the pre-existing email/mobile association behavior until
-- the dedicated verified-contact linking workflow is introduced.
create or replace function public.handle_new_user()
returns trigger as $$
declare
  existing_id uuid;
begin
  select id into existing_id
  from public.profiles
  where (email = new.email and email is not null and email <> '')
     or (phone_number = new.phone and phone_number is not null and phone_number <> '')
  limit 1;

  if existing_id is not null then
    update public.profiles
    set
      user_id = new.id,
      full_name = case
        when full_name is null or full_name = ''
          then coalesce(new.raw_user_meta_data ->> 'full_name', '')
        else full_name
      end,
      phone_number = coalesce(new.phone, phone_number),
      email = coalesce(new.email, email)
    where id = existing_id;
  else
    insert into public.profiles (
      id,
      user_id,
      full_name,
      role,
      phone_number,
      email,
      created_at
    )
    values (
      gen_random_uuid(),
      new.id,
      coalesce(new.raw_user_meta_data ->> 'full_name', ''),
      'client',
      new.phone,
      new.email,
      now()
    );
  end if;

  return new;
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

-- Only trusted server-side workflows may create or mutate business profiles.
-- Client preferences will move to a dedicated preferences model in a later
-- workstream; clients must not update role, PAN, contact, or linkage fields.
drop policy if exists "Clients can insert their own profile" on public.profiles;
drop policy if exists "Clients can update their own profile" on public.profiles;

-- Investors are read-only consumers of registrar-originated investment data.
drop policy if exists "Clients can insert their own portfolios" on public.portfolios;
drop policy if exists "Clients can update their own portfolios" on public.portfolios;
drop policy if exists "Clients can insert their own transactions" on public.transactions;
drop policy if exists "Clients can update their own transactions" on public.transactions;

-- Operational logs are Advisor-only. Service-role ingestion retains access
-- because it bypasses RLS.
alter table public.ingestion_logs enable row level security;

drop policy if exists "Admins have full access to ingestion_logs" on public.ingestion_logs;
create policy "Admins have full access to ingestion_logs"
  on public.ingestion_logs for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- SECURITY DEFINER procedures are not browser RPCs. Only the service role used
-- by secured Edge Functions may execute the procedures that write investment
-- data or recompute portfolio values.
revoke all on function public.process_cams_records(jsonb) from public, anon, authenticated;
grant execute on function public.process_cams_records(jsonb) to service_role;

revoke all on function public.recalculate_portfolio_value(uuid) from public, anon, authenticated;
grant execute on function public.recalculate_portfolio_value(uuid) to service_role;
