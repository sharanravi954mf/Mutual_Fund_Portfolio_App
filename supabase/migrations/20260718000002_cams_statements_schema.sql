CREATE TABLE IF NOT EXISTS public.cams_statements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  foliochk text,
  inv_name text,
  address1 text,
  address2 text,
  address3 text,
  city text,
  pincode text,
  product text,
  sch_name text,
  rep_date date,
  clos_bal numeric(20, 6) DEFAULT 0.000000,
  rupee_bal numeric(20, 6) DEFAULT 0.000000,
  pan_no text,
  joint1_pan text,
  joint2_pan text,
  guard_pan text,
  email text,
  mobile_no text,
  bank_name text,
  branch text,
  ac_type text,
  ac_no text,
  ifsc_code text,
  nom_name text,
  relation text,
  nom_percen numeric(5, 2) DEFAULT 0.00,
  created_at timestamptz DEFAULT now()
);

-- Enable RLS and define access policies
ALTER TABLE public.cams_statements ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins have full access to cams_statements" ON public.cams_statements;
CREATE POLICY "Admins have full access to cams_statements"
  ON public.cams_statements FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());
