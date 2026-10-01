-- The bare Supabase Postgres image omits GoTrue's auth.jwt migration.
-- Same definition as the platform function; test-container bootstrap only.
CREATE OR REPLACE FUNCTION auth.jwt() RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT COALESCE(NULLIF(current_setting('request.jwt.claim', true), ''),
    NULLIF(current_setting('request.jwt.claims', true), ''))::jsonb;
$$;

-- Exact Storage bucket type/table from the local Supabase platform schema.
-- MoneyBowl only inserts its bucket configuration during migrations; no storage API runs.
CREATE TYPE storage.buckettype AS ENUM (
    'STANDARD',
    'ANALYTICS',
    'VECTOR'
);
CREATE TABLE storage.buckets (
    id text NOT NULL,
    name text NOT NULL,
    owner uuid,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    public boolean DEFAULT false,
    avif_autodetection boolean DEFAULT false,
    file_size_limit bigint,
    allowed_mime_types text[],
    owner_id text,
    type storage.buckettype DEFAULT 'STANDARD'::storage.buckettype NOT NULL
);
ALTER TABLE storage.buckets ADD PRIMARY KEY (id);
CREATE UNIQUE INDEX bname ON storage.buckets(name);
ALTER TABLE storage.buckets OWNER TO postgres;

-- GoTrue auth.users upgrades absent from the bare image, copied from the
-- current local Auth schema (no auth records or credentials are imported).
ALTER TABLE auth.users RENAME COLUMN confirmed_at TO email_confirmed_at;
ALTER TABLE auth.users RENAME COLUMN email_change_token TO email_change_token_new;
ALTER TABLE auth.users ADD COLUMN phone text DEFAULT NULL::character varying;
ALTER TABLE auth.users ADD COLUMN phone_confirmed_at timestamp with time zone;
ALTER TABLE auth.users ADD COLUMN phone_change text DEFAULT ''::character varying;
ALTER TABLE auth.users ADD COLUMN phone_change_token character varying(255) DEFAULT ''::character varying;
ALTER TABLE auth.users ADD COLUMN phone_change_sent_at timestamp with time zone;
ALTER TABLE auth.users ADD COLUMN confirmed_at timestamp with time zone GENERATED ALWAYS AS (LEAST(email_confirmed_at, phone_confirmed_at)) STORED;
ALTER TABLE auth.users ADD COLUMN email_change_token_current character varying(255) DEFAULT ''::character varying;
ALTER TABLE auth.users ADD COLUMN email_change_confirm_status smallint DEFAULT 0;
ALTER TABLE auth.users ADD COLUMN banned_until timestamp with time zone;
ALTER TABLE auth.users ADD COLUMN reauthentication_token character varying(255) DEFAULT ''::character varying;
ALTER TABLE auth.users ADD COLUMN reauthentication_sent_at timestamp with time zone;
ALTER TABLE auth.users ADD COLUMN is_sso_user boolean DEFAULT false NOT NULL;
ALTER TABLE auth.users ADD COLUMN deleted_at timestamp with time zone;
ALTER TABLE auth.users ADD COLUMN is_anonymous boolean DEFAULT false NOT NULL;
ALTER TABLE auth.users ADD CONSTRAINT users_email_change_confirm_status_check CHECK (((email_change_confirm_status >= 0) AND (email_change_confirm_status <= 2)));
