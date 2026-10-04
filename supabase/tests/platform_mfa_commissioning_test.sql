-- Synthetic fixtures ONLY: called by test_platform_mfa_commissioning.py after
-- proving the parent harness's new network-disabled tmpfs container identity.
CREATE SCHEMA mfa_commissioning_fixture;
CREATE FUNCTION mfa_commissioning_fixture.id(n integer) RETURNS uuid LANGUAGE sql IMMUTABLE
AS $$ SELECT md5('mfa-commissioning-fixture-'||n)::uuid $$;
CREATE FUNCTION mfa_commissioning_fixture.login(n integer, level text DEFAULT 'aal1') RETURNS void LANGUAGE sql
AS $$ SELECT set_config('request.jwt.claims',jsonb_build_object('sub',mfa_commissioning_fixture.id(n),'role','authenticated','aal',level,'session_id',mfa_commissioning_fixture.id(301))::text,false)::void $$;
GRANT USAGE ON SCHEMA mfa_commissioning_fixture TO authenticated;
INSERT INTO auth.users(id,email,email_confirmed_at)
SELECT mfa_commissioning_fixture.id(n),'mfa-synthetic-'||n||'@example.test',now() FROM generate_series(1,3) n;
SELECT platform_authority.grant_authority(mfa_commissioning_fixture.id(1),'platform_admin',mfa_commissioning_fixture.id(101),'local synthetic operator');
SELECT platform_authority.grant_authority(mfa_commissioning_fixture.id(1),'mfd_applications.review',mfa_commissioning_fixture.id(102),'local synthetic review');
INSERT INTO auth.mfa_factors(id,user_id,factor_type,status,created_at,updated_at)
VALUES(mfa_commissioning_fixture.id(201),mfa_commissioning_fixture.id(1),'totp','verified',now(),now());
INSERT INTO auth.sessions(id,user_id,factor_id,aal)
VALUES(mfa_commissioning_fixture.id(301),mfa_commissioning_fixture.id(1),mfa_commissioning_fixture.id(201),'aal2');
