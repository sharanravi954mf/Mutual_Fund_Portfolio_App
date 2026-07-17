-- 1. Add PAN to profiles for RTA identification
alter table public.profiles add column if not exists pan text unique;
create index if not exists idx_profiles_pan on public.profiles(pan);

-- 2. Create Ingestion Logs for Cron tracking
create table public.ingestion_logs (
  id uuid primary key default gen_random_uuid(),
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  status text not null check (status in ('RUNNING', 'SUCCESS', 'FAILED')),
  records_processed integer default 0,
  error_message text,
  log_details jsonb
);

-- 3. Stored Procedure to recalculate Portfolio values
create or replace function public.recalculate_portfolio_value(portfolio_uuid uuid)
returns void as $$
declare
  total_invested numeric(15,2) := 0.00;
  current_market numeric(15,2) := 0.00;
  t_row record;
  units_held numeric(12,4);
  latest_nav numeric(10,4);
begin
  -- Calculate net units and invested amount per mutual fund in this portfolio
  for t_row in (
    select 
      mutual_fund_id,
      sum(case when transaction_type = 'BUY' then units when transaction_type = 'SELL' then -units else 0 end) as net_units,
      sum(case when transaction_type = 'BUY' then amount when transaction_type = 'SELL' then -amount else 0 end) as net_invested
    from public.transactions
    where portfolio_id = portfolio_uuid
    group by mutual_fund_id
  ) loop
    units_held := t_row.net_units;
    
    -- Get latest NAV for this mutual fund
    select current_nav into latest_nav 
    from public.mutual_funds 
    where id = t_row.mutual_fund_id;
    
    total_invested := total_invested + coalesce(t_row.net_invested, 0);
    current_market := current_market + (coalesce(units_held, 0) * coalesce(latest_nav, 0));
  end loop;

  -- Update portfolio record
  update public.portfolios
  set 
    total_invested_value = case when total_invested < 0 then 0.00 else total_invested end,
    current_market_value = case when current_market < 0 then 0.00 else current_market end,
    last_updated = now()
  where id = portfolio_uuid;
end;
$$ language plpgsql security definer;

-- 4. Enable pg_cron and schedule the Edge Function nightly at 00:00 (requires pg_cron on Supabase)
-- Note: Replace '<project-ref>' and 'service-role-key' dynamically.
-- select cron.schedule(
--   'nightly-data-ingestion',
--   '0 0 * * *',
--   $$ select net.http_post(
--        url := 'https://<project-ref>.supabase.co/functions/v1/cams-kfintech-ingestion',
--        headers := jsonb_build_object(
--          'Content-Type', 'application/json',
--          'Authorization', 'Bearer <service-role-key>'
--        )
--      ) $$
-- );
