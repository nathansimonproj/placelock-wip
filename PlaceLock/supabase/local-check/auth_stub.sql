-- Minimal stand-in for the parts of Supabase that the migration uses, so it can be checked
-- against plain Postgres without Docker or the Supabase CLI. Not used in production.
create role anon nologin;
create role authenticated nologin;

create schema auth;
create table auth.users (
  id           uuid primary key,
  is_anonymous boolean not null default true
);

-- Supabase reads the signed-in user's id from the request's JWT; here it's a session setting.
create function auth.uid() returns uuid
language sql stable
as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;

grant usage on schema auth to anon, authenticated;
grant usage on schema public to anon, authenticated;
grant execute on function auth.uid() to anon, authenticated;
