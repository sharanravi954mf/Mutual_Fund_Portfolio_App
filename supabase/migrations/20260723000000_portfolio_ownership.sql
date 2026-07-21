-- Sprint 3 Workstream 4: active investor links are the only investor
-- ownership source. profiles.user_id remains legacy data only.

create or replace function public.is_admin()
returns boolean as $$
begin
  return exists (
    select 1
    from public.user_accounts
    where user_id = auth.uid()
      and account_state = 'advisor'
  );
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

create or replace function public.has_active_investor_link(target_profile_id uuid)
returns boolean as $$
begin
  return exists (
    select 1
    from public.user_accounts account
    join public.investor_account_links link on link.user_id = account.user_id
    where account.user_id = auth.uid()
      and account.account_state = 'linked_investor'
      and link.profile_id = target_profile_id
      and link.link_status = 'active'
  );
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

revoke all on function public.has_active_investor_link(uuid) from public, anon;
grant execute on function public.has_active_investor_link(uuid) to authenticated;

-- Replace every investor ownership policy that previously traversed
-- profiles.user_id. Advisors retain full access through is_admin().
drop policy if exists "Clients can view their own profile" on public.profiles;
drop policy if exists "Linked investors can view their linked profile" on public.profiles;
create policy "Linked investors can view their linked profile"
  on public.profiles for select to authenticated
  using (public.has_active_investor_link(id));

drop policy if exists "Clients can view their own portfolios" on public.portfolios;
drop policy if exists "Clients can insert their own portfolios" on public.portfolios;
drop policy if exists "Clients can update their own portfolios" on public.portfolios;
drop policy if exists "Linked investors can view their linked portfolios" on public.portfolios;
create policy "Linked investors can view their linked portfolios"
  on public.portfolios for select to authenticated
  using (public.has_active_investor_link(client_id));

drop policy if exists "Clients can view their own transactions" on public.transactions;
drop policy if exists "Clients can insert their own transactions" on public.transactions;
drop policy if exists "Clients can update their own transactions" on public.transactions;
drop policy if exists "Linked investors can view transactions for linked portfolios" on public.transactions;
create policy "Linked investors can view transactions for linked portfolios"
  on public.transactions for select to authenticated
  using (
    exists (
      select 1
      from public.portfolios portfolio
      where portfolio.id = transactions.portfolio_id
        and public.has_active_investor_link(portfolio.client_id)
    )
  );

-- The Workstream 3 temporary legacy bridge is removed. Automatic linking now
-- creates only the active relationship; it never writes profiles.user_id.
create or replace function public.bootstrap_identity()
returns table (
  account_state public.user_account_state,
  onboarding_completed boolean,
  resolution text
) as $$
declare
  current_account public.user_accounts%rowtype;
  auth_email text;
  auth_phone text;
  email_confirmed boolean;
  phone_confirmed boolean;
  matched_profile_id uuid;
  matched_count integer;
  match_method text;
  active_link_exists boolean;
begin
  insert into public.user_accounts (user_id)
  values (auth.uid())
  on conflict (user_id) do nothing;

  select * into current_account
  from public.user_accounts
  where user_id = auth.uid()
  for update;

  if current_account.account_state = 'advisor' then
    return query select current_account.account_state, current_account.onboarding_completed, 'advisor';
    return;
  end if;

  select exists (
    select 1 from public.investor_account_links
    where user_id = auth.uid() and link_status = 'active'
  ) into active_link_exists;

  if active_link_exists then
    update public.user_accounts
    set account_state = 'linked_investor', onboarding_completed = true
    where user_id = auth.uid();
    return query select 'linked_investor'::public.user_account_state, true, 'existing_link';
    return;
  end if;

  if current_account.onboarding_completed then
    return query select current_account.account_state, true,
      case when current_account.account_state = 'explorer'
        then 'explorer_choice' else 'verification_pending' end;
    return;
  end if;

  select email, phone, email_confirmed_at is not null, phone_confirmed_at is not null
  into auth_email, auth_phone, email_confirmed, phone_confirmed
  from auth.users where id = auth.uid();

  if email_confirmed and auth_email is not null and auth_email <> '' then
    select count(*) into matched_count
    from public.profiles
    where role = 'client' and verified_email is not null
      and lower(verified_email) = lower(auth_email);
    match_method := 'verified_email';
  else
    matched_count := 0;
  end if;

  if matched_count = 0 and phone_confirmed and auth_phone is not null and auth_phone <> '' then
    select count(*) into matched_count
    from public.profiles
    where role = 'client' and verified_mobile is not null
      and verified_mobile = auth_phone;
    match_method := 'verified_mobile';
  end if;

  if matched_count = 1 then
    if match_method = 'verified_email' then
      select id into matched_profile_id from public.profiles
      where role = 'client' and verified_email is not null
        and lower(verified_email) = lower(auth_email);
    else
      select id into matched_profile_id from public.profiles
      where role = 'client' and verified_mobile is not null
        and verified_mobile = auth_phone;
    end if;

    begin
      insert into public.investor_account_links (
        user_id, profile_id, verification_method, verified_at, linked_at, link_status
      ) values (
        auth.uid(), matched_profile_id, match_method, now(), now(), 'active'
      );
      update public.user_accounts
      set account_state = 'linked_investor', onboarding_completed = true
      where user_id = auth.uid();
      return query select 'linked_investor'::public.user_account_state, true, 'automatic_link';
      return;
    exception when unique_violation then
      null;
    end;
  end if;

  update public.user_accounts
  set account_state = 'link_pending', onboarding_completed = false
  where user_id = auth.uid();
  return query select 'link_pending'::public.user_account_state, false,
    case when matched_count > 1 then 'ambiguous_match' else 'no_match' end;
end;
$$ language plpgsql security definer set search_path = public, pg_temp;
