-- Migration to support Scheme Factsheets and Portfolio Holdings
create table if not exists public.fund_factsheets (
  id uuid primary key default gen_random_uuid(),
  mutual_fund_id uuid not null references public.mutual_funds(id) on delete cascade,
  month_year date not null, -- E.g. '2026-07-01' representing the July 2026 factsheet
  factsheet_url text,       -- URL to monthly factsheet PDF
  portfolio_holdings_url text, -- URL to portfolio holdings page
  managers text[],          -- Array of fund manager names
  top_holdings jsonb,       -- JSONB list: [{"company": "HDFC Bank", "weight": 9.2}, ...]
  created_at timestamptz not null default now(),
  unique (mutual_fund_id, month_year)
);

-- Indexing for fast retrieval
create index if not exists idx_factsheets_fund_month on public.fund_factsheets(mutual_fund_id, month_year);

-- Enable RLS
alter table public.fund_factsheets enable row level security;

-- Policies for public.fund_factsheets
create policy "Admins have full access to factsheets"
  on public.fund_factsheets for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy "Clients can view factsheets"
  on public.fund_factsheets for select to authenticated
  using (true);
