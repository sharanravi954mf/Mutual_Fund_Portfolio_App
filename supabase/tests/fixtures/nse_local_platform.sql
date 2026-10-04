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

-- Modern GoTrue helpers accept both PostgREST JWT settings. The bare image
-- otherwise resolves auth.uid() to NULL in tests using request.jwt.claims.
CREATE OR REPLACE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$
 SELECT coalesce(nullif(current_setting('request.jwt.claim.sub',true),''),
   nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'sub')::uuid;
$$;
CREATE OR REPLACE FUNCTION auth.role() RETURNS text LANGUAGE sql STABLE AS $$
 SELECT coalesce(nullif(current_setting('request.jwt.claim.role',true),''),
   nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'role');
$$;

-- GoTrue MFA/session schema required by Platform Authority V1. Definitions read
-- from the local Auth schema; no Auth rows, factors or secrets are imported.
CREATE TYPE auth.factor_type AS ENUM ('totp','webauthn','phone');
CREATE TYPE auth.factor_status AS ENUM ('unverified','verified');
CREATE TYPE auth.aal_level AS ENUM ('aal1','aal2','aal3');
CREATE TABLE auth.mfa_factors (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    friendly_name text,
    factor_type auth.factor_type NOT NULL,
    status auth.factor_status NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    secret text,
    phone text,
    last_challenged_at timestamp with time zone,
    web_authn_credential jsonb,
    web_authn_aaguid uuid,
    last_webauthn_challenge_data jsonb
);
ALTER TABLE auth.mfa_factors ADD PRIMARY KEY(id);
ALTER TABLE auth.mfa_factors ADD FOREIGN KEY(user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
CREATE TABLE auth.sessions (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    factor_id uuid,
    aal auth.aal_level,
    not_after timestamp with time zone,
    refreshed_at timestamp without time zone,
    user_agent text,
    ip inet,
    tag text,
    oauth_client_id uuid,
    refresh_token_hmac_key text,
    refresh_token_counter bigint,
    scopes text,
    CONSTRAINT sessions_scopes_length CHECK ((char_length(scopes) <= 4096))
);
ALTER TABLE auth.sessions ADD PRIMARY KEY(id);
ALTER TABLE auth.sessions ADD FOREIGN KEY(user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
-- Real GoTrue tables grant postgres these privileges; API roles receive none.
GRANT ALL ON auth.sessions,auth.mfa_factors TO postgres;
