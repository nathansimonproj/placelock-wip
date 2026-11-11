-- Behavior checks for the migration: row-level security, newest-edit-wins, tombstones,
-- constraints and account deletion. Run by run.sh. Any failed assert stops the run.
\set ON_ERROR_STOP on
\o /dev/null

create schema checks;
-- Runs `stmt` as the current role and asserts it fails with an error containing `expected`.
create function checks.expect_error(stmt text, expected text) returns void
language plpgsql as $$
begin
  execute stmt;
  raise exception 'expected error "%" but it succeeded: %', expected, stmt;
exception when others then
  if sqlerrm not ilike '%' || expected || '%' then
    raise exception 'expected error "%" but got "%" for: %', expected, sqlerrm, stmt;
  end if;
end;
$$;
grant usage on schema checks to anon, authenticated;
grant execute on function checks.expect_error(text, text) to anon, authenticated;

-- Two accounts, created the way Supabase Auth would.
insert into auth.users (id) values
  ('aaaaaaaa-0000-0000-0000-000000000000'),
  ('bbbbbbbb-0000-0000-0000-000000000000');

do $$ begin
  assert (select count(*) from public.profiles) = 2, 'a profile per new account';
  assert (select count(*) from public.preferences) = 2, 'preferences per new account';
end $$;

-- ---------------------------------------------------------------- user A
set role authenticated;
set request.jwt.claim.sub = 'aaaaaaaa-0000-0000-0000-000000000000';

-- Upsert a place the way the outbox will (PostgREST upsert = insert ... on conflict do update).
insert into public.places (id, name, latitude, longitude, radius_m, updated_at)
values ('11111111-0000-0000-0000-000000000000', 'Gym', 47.6537, -122.3012, 150, '2026-11-11 10:00Z')
on conflict (id) do update set name = excluded.name, updated_at = excluded.updated_at;

create temp table synced_before as select synced_at from public.places;

-- An older edit arriving late is skipped.
insert into public.places (id, name, latitude, longitude, radius_m, updated_at)
values ('11111111-0000-0000-0000-000000000000', 'OLD NAME', 47.6537, -122.3012, 150, '2026-11-11 09:00Z')
on conflict (id) do update set name = excluded.name, updated_at = excluded.updated_at;
do $$ begin
  assert (select name from public.places) = 'Gym', 'older edit must not overwrite a newer one';
  assert (select synced_at from public.places) = (select synced_at from synced_before),
    'a skipped edit must not bump synced_at';
end $$;

-- A newer edit applies.
select pg_sleep(0.01);
insert into public.places (id, name, latitude, longitude, radius_m, updated_at)
values ('11111111-0000-0000-0000-000000000000', 'IMA', 47.6537, -122.3012, 150, '2026-11-11 11:00Z')
on conflict (id) do update set name = excluded.name, updated_at = excluded.updated_at;
do $$ begin
  assert (select name from public.places) = 'IMA', 'newer edit applies';
  assert (select synced_at from public.places) > (select synced_at from synced_before), 'applied edit bumps synced_at';
  assert (select user_id from public.places) = 'aaaaaaaa-0000-0000-0000-000000000000', 'user_id defaults to auth.uid()';
end $$;

-- Deletes are tombstones; hard deletes aren't allowed.
select checks.expect_error($q$delete from public.places$q$, 'permission denied');
update public.places set deleted_at = '2026-11-11 12:00Z', updated_at = '2026-11-11 12:00Z';
do $$ begin assert (select deleted_at from public.places) is not null, 'tombstone set'; end $$;

-- Constraints.
select checks.expect_error($q$insert into public.places (id, name, latitude, longitude, radius_m, updated_at)
  values (gen_random_uuid(), 'Tiny', 47, -122, 50, now())$q$, 'places_radius_m_check');
select checks.expect_error($q$insert into public.places (id, name, latitude, longitude, radius_m, pending_radius_m, updated_at)
  values (gen_random_uuid(), 'Half', 47, -122, 150, 200, now())$q$, 'pending_change_complete');
select checks.expect_error($q$update public.profiles set username = 'Bad Name!', updated_at = now()$q$, 'username_check');
select checks.expect_error($q$update public.profiles set synced_at = now()$q$, 'permission denied');
select checks.expect_error($q$update public.profiles set id = 'bbbbbbbb-0000-0000-0000-000000000000'$q$, 'permission denied');

update public.profiles set username = 'nate_s', setup_ends_at = '2026-11-12Z', updated_at = now();
update public.preferences set ghost_mode = true, updated_at = now();

-- Sessions: an unlock that's still running, then ended.
insert into public.sessions (id, place_id, kind, started_at, updated_at)
values ('22222222-0000-0000-0000-000000000000', '11111111-0000-0000-0000-000000000000', 'unlock',
        '2026-11-11 10:05Z', '2026-11-11 10:05Z');
update public.sessions set ended_at = '2026-11-11 11:30Z', end_reason = 'left', updated_at = '2026-11-11 11:30Z';
select checks.expect_error($q$insert into public.sessions (id, kind, started_at, ended_at, end_reason, updated_at)
  values (gen_random_uuid(), 'unlock', now(), now() - interval '1 h', 'left', now())$q$, 'ended_after_start');
select checks.expect_error($q$insert into public.sessions (id, kind, started_at, ended_at, updated_at)
  values (gen_random_uuid(), 'unlock', now(), now(), now())$q$, 'end_reason_iff_ended');
select checks.expect_error($q$insert into public.sessions (id, kind, started_at, verified, updated_at)
  values (gen_random_uuid(), 'unlock', now(), true, now())$q$, 'lock_in_fields');
insert into public.sessions (id, kind, started_at, ended_at, end_reason, verified, shield_attempts, updated_at)
values (gen_random_uuid(), 'lock_in', '2026-11-11 13:00Z', '2026-11-11 15:00Z', 'left', true, 4, now());

-- Internal functions aren't callable.
select checks.expect_error($q$select public.keep_newest_edit()$q$, 'permission denied');

-- ---------------------------------------------------------------- user B
set request.jwt.claim.sub = 'bbbbbbbb-0000-0000-0000-000000000000';

do $$ begin
  assert (select count(*) from public.places) = 0, 'B cannot see A''s places';
  assert (select count(*) from public.sessions) = 0, 'B cannot see A''s sessions';
  assert (select count(*) from public.profiles) = 1, 'B sees only their own profile';
end $$;

update public.places set name = 'hacked', updated_at = '2030-01-01Z';
select checks.expect_error($q$insert into public.places (id, user_id, name, latitude, longitude, radius_m, updated_at)
  values (gen_random_uuid(), 'aaaaaaaa-0000-0000-0000-000000000000', 'Planted', 47, -122, 150, now())$q$,
  'row-level security');
-- Overwriting A's place by reusing its id fails (B can't see the conflicting row).
select checks.expect_error($q$insert into public.places (id, name, latitude, longitude, radius_m, updated_at)
  values ('11111111-0000-0000-0000-000000000000', 'Mine now', 47, -122, 150, '2030-01-01Z')
  on conflict (id) do update set name = excluded.name, updated_at = excluded.updated_at$q$, 'row-level security');
-- A session can't point at someone else's place.
select checks.expect_error($q$insert into public.sessions (id, place_id, kind, started_at, updated_at)
  values (gen_random_uuid(), '11111111-0000-0000-0000-000000000000', 'unlock', now(), now())$q$,
  'session_place_same_owner');

insert into public.places (id, name, latitude, longitude, radius_m, updated_at)
values ('33333333-0000-0000-0000-000000000000', 'Library', 47.656, -122.310, 120, now());

-- ---------------------------------------------------------------- logged out
reset request.jwt.claim.sub;
set role anon;
select checks.expect_error($q$select * from public.places$q$, 'permission denied');
select checks.expect_error($q$select public.delete_my_account()$q$, 'permission denied');

-- ---------------------------------------------------------------- A deletes their account
set role authenticated;
set request.jwt.claim.sub = 'aaaaaaaa-0000-0000-0000-000000000000';
select public.delete_my_account();

reset role;
do $$ begin
  assert (select name from public.places where user_id = 'aaaaaaaa-0000-0000-0000-000000000000') is null,
    'A''s place untouched by B';
  assert not exists (select 1 from auth.users where id = 'aaaaaaaa-0000-0000-0000-000000000000'), 'A deleted';
  assert not exists (select 1 from public.profiles where id = 'aaaaaaaa-0000-0000-0000-000000000000'), 'A profile gone';
  assert not exists (select 1 from public.sessions where user_id = 'aaaaaaaa-0000-0000-0000-000000000000'), 'A sessions gone';
  assert (select count(*) from public.places) = 1, 'only B''s place remains';
  assert exists (select 1 from public.preferences where user_id = 'bbbbbbbb-0000-0000-0000-000000000000'), 'B intact';
end $$;

\echo 'All checks passed.'
