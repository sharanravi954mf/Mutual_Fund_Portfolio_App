-- Add default value gen_random_uuid() to profiles.id column to support unregistered client inserts
ALTER TABLE public.profiles ALTER COLUMN id SET DEFAULT gen_random_uuid();
