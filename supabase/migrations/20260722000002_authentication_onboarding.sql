-- Sprint 3 Workstream 3: secure onboarding and automatic investor linking.
-- Business contact values are only eligible for matching after a trusted
-- ingestion or Advisor workflow has written them to the verified columns.

alter table public.profiles
  add column if not exists verified_email text,
  add column if not exists verified_mobile text;

create index if not exists idx_profiles_verified_email
  on public.profiles (lower(verified_email))
  where role = 'client' and verified_email is not null and verified_email <> '';

create index if not exists idx_profiles_verified_mobile
  on public.profiles (verified_mobile)
  where role = 'client' and verified_mobile is not null and verified_mobile <> '';

-- Resolves the signed-in account without exposing profile, email, mobile, or
-- match-count details to the browser. Email takes precedence over mobile; an
-- ambiguous result is never automatically linked.
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
  matched_profile_user_id uuid;
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
    select 1
    from public.investor_account_links
    where user_id = auth.uid() and link_status = 'active'
  ) into active_link_exists;

  if active_link_exists then
    update public.user_accounts
    set account_state = 'linked_investor', onboarding_completed = true
    where user_id = auth.uid();

    return query select 'linked_investor'::public.user_account_state, true, 'existing_link';
    return;
  end if;

  -- A completed Explorer choice and a pending verification journey must not be
  -- re-evaluated on every session restoration.
  if current_account.onboarding_completed then
    return query select current_account.account_state, true,
      case when current_account.account_state = 'explorer'
        then 'explorer_choice'
        else 'verification_pending'
      end;
    return;
  end if;

  select
    email,
    phone,
    email_confirmed_at is not null,
    phone_confirmed_at is not null
  into auth_email, auth_phone, email_confirmed, phone_confirmed
  from auth.users
  where id = auth.uid();

  if email_confirmed and auth_email is not null and auth_email <> '' then
    select count(*) into matched_count
    from public.profiles
    where role = 'client'
      and verified_email is not null
      and lower(verified_email) = lower(auth_email);
    match_method := 'verified_email';
  else
    matched_count := 0;
  end if;

  if matched_count = 0 and phone_confirmed and auth_phone is not null and auth_phone <> '' then
    select count(*) into matched_count
    from public.profiles
    where role = 'client'
      and verified_mobile is not null
      and verified_mobile = auth_phone;
    match_method := 'verified_mobile';
  end if;

  if matched_count = 1 then
    if match_method = 'verified_email' then
      select id, user_id into matched_profile_id, matched_profile_user_id
      from public.profiles
      where role = 'client'
        and verified_email is not null
        and lower(verified_email) = lower(auth_email);
    else
      select id, user_id into matched_profile_id, matched_profile_user_id
      from public.profiles
      where role = 'client'
        and verified_mobile is not null
        and verified_mobile = auth_phone;
    end if;

    if matched_profile_user_id is null or matched_profile_user_id = auth.uid() then
      begin
      insert into public.investor_account_links (
        user_id,
        profile_id,
        verification_method,
        verified_at,
        linked_at,
        link_status
      ) values (
        auth.uid(),
        matched_profile_id,
        match_method,
        now(),
        now(),
        'active'
      );

      -- Temporary compatibility bridge for the existing Investor Dashboard.
      -- Workstream 4 will resolve ownership solely through the active link.
      update public.profiles
      set user_id = auth.uid()
      where id = matched_profile_id
        and (user_id is null or user_id = auth.uid());

      update public.user_accounts
      set account_state = 'linked_investor', onboarding_completed = true
      where user_id = auth.uid();

      return query select 'linked_investor'::public.user_account_state, true, 'automatic_link';
      return;
      exception when unique_violation then
        -- A concurrent or pre-existing link is not disclosed; it falls into the
        -- same safe pending flow as any other unresolved match.
        null;
      end;
    end if;
  end if;

  update public.user_accounts
  set account_state = 'link_pending', onboarding_completed = false
  where user_id = auth.uid();

  return query select 'link_pending'::public.user_account_state, false,
    case when matched_count > 1 then 'ambiguous_match' else 'no_match' end;
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

revoke all on function public.bootstrap_identity() from public, anon, service_role;
grant execute on function public.bootstrap_identity() to authenticated;

-- Applies the only client-directed onboarding choice. It cannot create a
-- business profile, claim an investor record, or promote an Advisor.
create or replace function public.complete_onboarding_choice(choice text)
returns public.user_account_state as $$
declare
  next_state public.user_account_state;
begin
  if choice = 'explorer' then
    next_state := 'explorer';
  elsif choice = 'link_pending' then
    next_state := 'link_pending';
  else
    raise exception 'Invalid onboarding choice';
  end if;

  update public.user_accounts
  set account_state = next_state, onboarding_completed = true
  where user_id = auth.uid()
    and account_state = 'link_pending';

  if not found then
    raise exception 'Onboarding choice is not available for this account';
  end if;

  return next_state;
end;
$$ language plpgsql security definer set search_path = public, pg_temp;

revoke all on function public.complete_onboarding_choice(text) from public, anon, service_role;
grant execute on function public.complete_onboarding_choice(text) to authenticated;
