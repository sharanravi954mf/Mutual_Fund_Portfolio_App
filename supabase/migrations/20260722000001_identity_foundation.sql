-- Sprint 3 Workstream 2: authentication identity, business identity, and
-- their controlled relationship. This migration is intentionally schema-only:
-- it does not implement onboarding or automatic investor linking.

create type public.user_account_state as enum (
  'explorer',
  'link_pending',
  'linked_investor',
  'advisor'
);

create type public.investor_link_status as enum (
  'active',
  'revoked'
);

-- One row per authenticated application user. Account state belongs here, not
-- on profiles, because business investor records may exist before signup.
create table public.user_accounts (
  user_id uuid primary key references auth.users(id) on delete cascade,
  account_state public.user_account_state not null default 'explorer',
  onboarding_completed boolean not null default false,
  last_login_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Controlled relationship from an authenticated account to a business investor
-- record. Future verification methods may include email, mobile, PAN, folio,
-- and advisor-assisted verification without changing the business profile.
create table public.investor_account_links (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.user_accounts(user_id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete restrict,
  verification_method text not null,
  verified_at timestamptz,
  linked_at timestamptz not null default now(),
  link_status public.investor_link_status not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, profile_id)
);

-- An account and business investor each have at most one active relationship.
create unique index idx_investor_account_links_active_user
  on public.investor_account_links(user_id)
  where link_status = 'active';

create unique index idx_investor_account_links_active_profile
  on public.investor_account_links(profile_id)
  where link_status = 'active';

create index idx_investor_account_links_profile_id
  on public.investor_account_links(profile_id);

create or replace function public.set_identity_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql set search_path = public, pg_temp;

create trigger set_user_accounts_updated_at
  before update on public.user_accounts
  for each row execute procedure public.set_identity_updated_at();

create trigger set_investor_account_links_updated_at
  before update on public.investor_account_links
  for each row execute procedure public.set_identity_updated_at();

-- Preserve the current active Advisor/client access relationships while moving
-- their authentication lifecycle into user_accounts. Imported investors with
-- user_id null remain business-only profiles and receive no account/link row.
insert into public.user_accounts (
  user_id,
  account_state,
  onboarding_completed
)
select
  user_id,
  case when role = 'admin' then 'advisor'::public.user_account_state
       else 'linked_investor'::public.user_account_state
  end,
  true
from public.profiles
where user_id is not null
on conflict (user_id) do nothing;

insert into public.investor_account_links (
  user_id,
  profile_id,
  verification_method,
  verified_at,
  linked_at,
  link_status
)
select
  user_id,
  id,
  'legacy_migration',
  now(),
  now(),
  'active'::public.investor_link_status
from public.profiles
where user_id is not null
  and role = 'client'
on conflict (user_id, profile_id) do nothing;

alter table public.user_accounts enable row level security;
alter table public.investor_account_links enable row level security;

create policy "Users can view their own account state"
  on public.user_accounts for select to authenticated
  using (user_id = auth.uid());

create policy "Advisors have full access to user accounts"
  on public.user_accounts for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy "Users can view their own investor links"
  on public.investor_account_links for select to authenticated
  using (user_id = auth.uid());

create policy "Advisors have full access to investor links"
  on public.investor_account_links for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- New signups create only an authentication-facing Explorer account. A future
-- onboarding workstream will resolve verified contacts and create an investor
-- account link when appropriate.
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.user_accounts (user_id, account_state)
  values (new.id, 'explorer');

  return new;
end;
$$ language plpgsql security definer set search_path = public, pg_temp;
