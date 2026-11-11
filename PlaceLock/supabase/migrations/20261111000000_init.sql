-- PlaceLock backend, v1.
--
-- The phone decides blocking. It keeps a local copy of everything enforcement needs and works
-- fully offline. This database owns identity, history and (later) social: it stores profiles,
-- preferences, places and sessions, and restores them on a new phone.
--
-- Sync model (see Plan.md, "Backend"):
--   * Rows are created on the phone with client-generated UUIDs (Place.id is already a UUID).
--   * The phone queues changes in a local outbox and upserts them when online.
--   * Newest edit wins: every synced row carries `updated_at`, the time of the edit on the phone.
--     An upsert older than the stored row is silently skipped (trigger `keep_newest_edit`).
--   * Deletes are tombstones (`deleted_at`), so they sync like any other edit.
--   * `synced_at` is server time, set on every write. A phone pulls "rows with synced_at > my last
--     pull" to catch up.
--
-- Never stored here: the blocked-app selection (Apple's tokens only work on the device that
-- made them), place embeddings, and live enforcement state (active unlock, paused places).
--
-- Accounts: the app signs in anonymously on first launch (no UI), and the user can link
-- Sign in with Apple later, which keeps the same auth.users id. Every row below hangs off that id.

-- ---------------------------------------------------------------------------------------------
-- Shared trigger functions
-- ---------------------------------------------------------------------------------------------

-- Server clock for incremental pulls.
create function public.stamp_synced_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.synced_at := now();
  return new;
end;
$$;

-- Newest edit wins. Equal timestamps apply, so a retried upsert is harmless.
create function public.keep_newest_edit()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.updated_at < old.updated_at then
    return null; -- skip this row's update; the stored edit is newer
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------------------------
-- profiles: one per account (anonymous or linked)
-- ---------------------------------------------------------------------------------------------

create table public.profiles (
  id            uuid primary key references auth.users (id) on delete cascade,
  -- Set when the user opts into social features. Null until then.
  username      text unique
                check (username ~ '^[a-z0-9_]{3,20}$'),
  display_name  text check (char_length(display_name) <= 40),
  avatar_url    text,
  school        text check (char_length(school) <= 80),
  -- End of the first-24 h setup window (AppModel.setupEndsAt). Kept here so reinstalling the
  -- app doesn't grant a fresh window with no delays.
  setup_ends_at timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  synced_at     timestamptz not null default now()
);

-- ---------------------------------------------------------------------------------------------
-- preferences: one per account
-- ---------------------------------------------------------------------------------------------

create table public.preferences (
  user_id            uuid primary key references public.profiles (id) on delete cascade,
  notify_on_lock     boolean not null default true,  -- "Left Gym, apps locked" banners
  -- For later social and share-card features. Stored now so they restore with everything else.
  ghost_mode         boolean not null default false, -- hide me from friends' "locked in now"
  show_spot_on_cards boolean not null default true,
  card_style         text    not null default 'classic' check (char_length(card_style) <= 20),
  updated_at         timestamptz not null default now(),
  synced_at          timestamptz not null default now()
);

-- ---------------------------------------------------------------------------------------------
-- places: mirrors Models/Place.swift
-- ---------------------------------------------------------------------------------------------

create table public.places (
  id          uuid primary key,                       -- Place.id, generated on the phone
  user_id     uuid not null default auth.uid()
              references public.profiles (id) on delete cascade,
  name        text not null check (char_length(name) between 1 and 60),
  address     text check (char_length(address) <= 200),
  kind        text not null default 'unlock' check (kind in ('unlock', 'study')),
  latitude    double precision not null check (latitude between -90 and 90),
  longitude   double precision not null check (longitude between -180 and 180),
  radius_m    double precision not null check (radius_m between 100 and 500),
  -- Place.activeAfter: a new place only unblocks from this time on. Null = active.
  active_after timestamptz,
  -- Place.pendingChange: a move or enlargement waiting out its 24 h. All four set, or none.
  pending_latitude   double precision check (pending_latitude between -90 and 90),
  pending_longitude  double precision check (pending_longitude between -180 and 180),
  pending_radius_m   double precision check (pending_radius_m between 100 and 500),
  pending_applies_at timestamptz,
  constraint pending_change_complete check (
    num_nulls(pending_latitude, pending_longitude, pending_radius_m, pending_applies_at) in (0, 4)
  ),
  deleted_at  timestamptz,                            -- tombstone
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null,                   -- phone's edit time (newest wins)
  synced_at   timestamptz not null default now(),     -- server time (incremental pull)
  unique (id, user_id)                                -- target for sessions' same-owner FK
);

create index places_user_synced on public.places (user_id, synced_at);

-- ---------------------------------------------------------------------------------------------
-- sessions: history of unlocks (built) and lock-ins (stretch goal)
-- ---------------------------------------------------------------------------------------------

create table public.sessions (
  id              uuid primary key,                   -- generated on the phone
  user_id         uuid not null default auth.uid()
                  references public.profiles (id) on delete cascade,
  place_id        uuid,
  kind            text not null check (kind in ('unlock', 'lock_in')),
  started_at      timestamptz not null,
  ended_at        timestamptz,                        -- null while the session is running
  -- Why it ended. Matches AppModel's lock reasons.
  end_reason      text check (end_reason in (
                    'left', 'moved', 'lock_until_leave', 'place_deleted',
                    'lost_always', 'recheck_failed', 'manual', 'launch_check')),
  -- Lock-ins only (stretch goal). Computed on the phone, so trust it like any client claim.
  verified        boolean,
  shield_attempts integer check (shield_attempts >= 0),
  -- A session can only point at one of its own user's places.
  constraint session_place_same_owner foreign key (place_id, user_id)
    references public.places (id, user_id) on delete set null (place_id),
  constraint ended_after_start check (ended_at is null or ended_at >= started_at),
  constraint end_reason_iff_ended check ((ended_at is null) = (end_reason is null)),
  constraint lock_in_fields check (kind = 'lock_in' or (verified is null and shield_attempts is null)),
  deleted_at      timestamptz,                        -- tombstone (user cleared history)
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null,
  synced_at       timestamptz not null default now()
);

create index sessions_user_synced  on public.sessions (user_id, synced_at);
create index sessions_user_started on public.sessions (user_id, started_at desc);

-- ---------------------------------------------------------------------------------------------
-- Triggers
-- ---------------------------------------------------------------------------------------------

create trigger keep_newest_edit before update on public.profiles
  for each row execute function public.keep_newest_edit();
create trigger keep_newest_edit before update on public.preferences
  for each row execute function public.keep_newest_edit();
create trigger keep_newest_edit before update on public.places
  for each row execute function public.keep_newest_edit();
create trigger keep_newest_edit before update on public.sessions
  for each row execute function public.keep_newest_edit();

-- Runs after keep_newest_edit (triggers fire in name order), so a skipped edit doesn't bump it.
create trigger stamp_synced_at before insert or update on public.profiles
  for each row execute function public.stamp_synced_at();
create trigger stamp_synced_at before insert or update on public.preferences
  for each row execute function public.stamp_synced_at();
create trigger stamp_synced_at before insert or update on public.places
  for each row execute function public.stamp_synced_at();
create trigger stamp_synced_at before insert or update on public.sessions
  for each row execute function public.stamp_synced_at();

-- A profile and default preferences for every new account, including anonymous ones.
create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id) values (new.id);
  insert into public.preferences (user_id) values (new.id);
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------------------------
-- Row-level security: each user sees and writes only their own rows.
-- (select auth.uid()) is evaluated once per statement instead of once per row.
-- ---------------------------------------------------------------------------------------------

alter table public.profiles    enable row level security;
alter table public.preferences enable row level security;
alter table public.places      enable row level security;
alter table public.sessions    enable row level security;

-- Profiles and preferences are created by handle_new_user and removed with the account,
-- so users can only read and update them.
create policy "own profile: read" on public.profiles
  for select to authenticated using (id = (select auth.uid()));
create policy "own profile: update" on public.profiles
  for update to authenticated using (id = (select auth.uid())) with check (id = (select auth.uid()));

create policy "own preferences: read" on public.preferences
  for select to authenticated using (user_id = (select auth.uid()));
create policy "own preferences: update" on public.preferences
  for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- Places and sessions: full access to your own rows. Hard deletes aren't granted; the app
-- tombstones instead so deletes sync to other devices.
create policy "own places: read" on public.places
  for select to authenticated using (user_id = (select auth.uid()));
create policy "own places: insert" on public.places
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy "own places: update" on public.places
  for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

create policy "own sessions: read" on public.sessions
  for select to authenticated using (user_id = (select auth.uid()));
create policy "own sessions: insert" on public.sessions
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy "own sessions: update" on public.sessions
  for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- Logged-out clients (the `anon` role) get nothing. Signed-in clients get only what the
-- policies above allow; no table grants delete.
revoke all on public.profiles, public.preferences, public.places, public.sessions from anon, authenticated;
grant select, update (username, display_name, avatar_url, school, setup_ends_at, updated_at)
  on public.profiles to authenticated;
grant select, update (notify_on_lock, ghost_mode, show_spot_on_cards, card_style, updated_at)
  on public.preferences to authenticated;
grant select, insert, update on public.places, public.sessions to authenticated;

-- ---------------------------------------------------------------------------------------------
-- Account deletion (required by App Store guideline 5.1.1(v) once accounts exist).
-- Deleting the auth user cascades to every row above.
-- ---------------------------------------------------------------------------------------------

create function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'not signed in';
  end if;
  delete from auth.users where id = auth.uid();
end;
$$;

revoke execute on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;

-- Internal trigger functions aren't callable over the API.
revoke execute on function public.handle_new_user(), public.keep_newest_edit(), public.stamp_synced_at()
  from public, anon, authenticated;
