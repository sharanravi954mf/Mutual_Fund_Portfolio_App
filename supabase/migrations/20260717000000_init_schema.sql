-- Enable UUID extension
create extension if not exists "uuid-ossp";

-- 1. Create Tables
create table public.profiles (
  id uuid references auth.users(id) on delete cascade primary key,
  full_name text,
  role text not null check (role in ('admin', 'client')),
  phone_number text unique,
  created_at timestamptz not null default now()
);

create table public.mutual_funds (
  id uuid primary key default gen_random_uuid(),
  scheme_code text not null unique,
  scheme_name text not null,
  fund_house text,
  category text,
  current_nav numeric(10, 4) not null check (current_nav >= 0),
  nav_date date not null
);

create table public.portfolios (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.profiles(id) on delete cascade,
  total_invested_value numeric(15, 2) not null default 0.00 check (total_invested_value >= 0),
  current_market_value numeric(15, 2) not null default 0.00 check (current_market_value >= 0),
  last_updated timestamptz not null default now()
);

create table public.transactions (
  id uuid primary key default gen_random_uuid(),
  portfolio_id uuid not null references public.portfolios(id) on delete cascade,
  mutual_fund_id uuid not null references public.mutual_funds(id) on delete restrict,
  transaction_type text not null check (transaction_type in ('BUY', 'SELL', 'SWITCH')),
  units numeric(12, 4) not null check (units > 0),
  nav_at_transaction numeric(10, 4) not null check (nav_at_transaction >= 0),
  amount numeric(15, 2) not null check (amount >= 0),
  execution_date date not null
);

create table public.distributor_details (
  id integer primary key,
  arn_code text not null,
  name text not null,
  email text,
  phone text,
  referral_link_prefix text
);

-- 2. Performance Indexes
create index if not exists idx_profiles_role on public.profiles(role);
create index if not exists idx_portfolios_client_id on public.portfolios(client_id);
create index if not exists idx_transactions_portfolio_id on public.transactions(portfolio_id);
create index if not exists idx_transactions_mutual_fund_id on public.transactions(mutual_fund_id);

-- 3. Row-Level Security (RLS) Configuration
alter table public.profiles enable row level security;
alter table public.mutual_funds enable row level security;
alter table public.portfolios enable row level security;
alter table public.transactions enable row level security;
alter table public.distributor_details enable row level security;

-- 4. Helper Security Definer for RLS Admin Lookup (avoids recursion)
create or replace function public.is_admin()
returns boolean as $$
begin
  return (
    coalesce(auth.jwt() ->> 'role', '') = 'admin'
    or exists (
      select 1 from public.profiles
      where id = auth.uid() and role = 'admin'
    )
  );
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

-- 5. Define Policies

-- PROFILES
create policy "Admins have full access to profiles"
  on public.profiles for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy "Clients can view their own profile"
  on public.profiles for select to authenticated
  using (id = auth.uid());

create policy "Clients can insert their own profile"
  on public.profiles for insert to authenticated
  with check (id = auth.uid());

create policy "Clients can update their own profile"
  on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

-- MUTUAL FUNDS
create policy "Admins have full access to mutual_funds"
  on public.mutual_funds for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy "Authenticated users can view mutual_funds"
  on public.mutual_funds for select to authenticated
  using (true);

-- PORTFOLIOS
create policy "Admins have full access to portfolios"
  on public.portfolios for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy "Clients can view their own portfolios"
  on public.portfolios for select to authenticated
  using (client_id = auth.uid());

create policy "Clients can insert their own portfolios"
  on public.portfolios for insert to authenticated
  with check (client_id = auth.uid());

create policy "Clients can update their own portfolios"
  on public.portfolios for update to authenticated
  using (client_id = auth.uid()) with check (client_id = auth.uid());

-- TRANSACTIONS
create policy "Admins have full access to transactions"
  on public.transactions for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy "Clients can view their own transactions"
  on public.transactions for select to authenticated
  using (
    exists (
      select 1 from public.portfolios p
      where p.id = transactions.portfolio_id and p.client_id = auth.uid()
    )
  );

create policy "Clients can insert their own transactions"
  on public.transactions for insert to authenticated
  with check (
    exists (
      select 1 from public.portfolios p
      where p.id = portfolio_id and p.client_id = auth.uid()
    )
  );

create policy "Clients can update their own transactions"
  on public.transactions for update to authenticated
  using (
    exists (
      select 1 from public.portfolios p
      where p.id = transactions.portfolio_id and p.client_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.portfolios p
      where p.id = portfolio_id and p.client_id = auth.uid()
    )
  );

-- DISTRIBUTOR DETAILS
create policy "Admins have full access to distributor_details"
  on public.distributor_details for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy "Authenticated users can view distributor_details"
  on public.distributor_details for select to authenticated
  using (true);

-- 6. Trigger to automatically link Auth Users to Profiles
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, full_name, role, phone_number, created_at)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    coalesce(new.raw_user_meta_data ->> 'role', 'client'),
    new.phone,
    now()
  );
  return new;
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

create or replace trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- 7. SQL Helper Functions for Calculations
create or replace function public.calculate_absolute_return(
  total_invested numeric,
  current_value numeric
)
returns numeric as $$
begin
  if total_invested is null or total_invested = 0 then
    return 0;
  end if;
  return round(((current_value - total_invested) / total_invested) * 100, 2);
end;
$$ language plpgsql stable;
