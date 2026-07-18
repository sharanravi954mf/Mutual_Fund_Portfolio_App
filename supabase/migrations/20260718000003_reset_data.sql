-- Reset data for a clean test of the statement ingestion pipeline

-- 1. Truncate transactions and raw CAMS statements
TRUNCATE TABLE public.transactions CASCADE;
TRUNCATE TABLE public.cams_statements CASCADE;

-- 2. Delete all auto-generated unregistered (ghost) client profiles
DELETE FROM public.profiles WHERE user_id IS NULL;

-- 3. Reset portfolio values for the remaining registered profiles
UPDATE public.portfolios SET 
  total_invested_value = 0.00, 
  current_market_value = 0.00;
