-- Duet core schema. See docs/03-data-model.md.
--
-- Alarms are stored as wall-clock time + repeat rule + timezone, NEVER as a bare
-- UTC instant: a repeating alarm must mean "07:00 wherever you are", which a
-- fixed instant cannot express once the user travels or the clocks change.

create table public.profiles (
  id                    uuid primary key references auth.users(id) on delete cascade,
  display_name          text not null default '',
  avatar_url            text,
  timezone              text not null default 'UTC',
  -- Whether the partner may stop THIS user's alarm. Enforced server-side in
  -- act_on_partner(); never trusted from the client. See ADR-006.
  allow_partner_dismiss boolean not null default true,
  accent                text not null default 'teal',
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

create table public.pairs (
  id         uuid primary key default gen_random_uuid(),
  status     text not null default 'active' check (status in ('active','dissolved')),
  plan       text not null default 'free'   check (plan in ('free','full')),
  plan_payer uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.pair_members (
  pair_id   uuid not null references public.pairs(id) on delete cascade,
  user_id   uuid not null references public.profiles(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (pair_id, user_id)
);

create index pair_members_user_idx on public.pair_members(user_id);
-- "At most one ACTIVE pair per user" (ADR-005) cannot be a partial unique index:
-- Postgres forbids a subquery in an index predicate. It is enforced by trigger
-- in 0002 instead -- in the database either way, because the client is not
-- trustworthy.

create table public.pair_invites (
  code        text primary key,
  pair_id     uuid not null references public.pairs(id) on delete cascade,
  created_by  uuid not null references public.profiles(id) on delete cascade,
  expires_at  timestamptz not null,
  redeemed_at timestamptz,
  redeemed_by uuid references public.profiles(id) on delete set null
);

create index pair_invites_pair_idx on public.pair_invites(pair_id);

create table public.alarms (
  id             uuid primary key default gen_random_uuid(),
  pair_id        uuid references public.pairs(id) on delete cascade,  -- null = solo
  owner_id       uuid not null references public.profiles(id) on delete cascade,
  label          text not null default '',
  enabled        boolean not null default true,

  local_time     time not null,
  repeat_days    smallint not null default 0,   -- bitmask Mon=1<<0 .. Sun=1<<6
  one_shot_date  date,
  tz_mode        text not null default 'local' check (tz_mode in ('local','absolute')),
  anchor_tz      text,

  ring_target    text not null default 'both' check (ring_target in ('both','owner','partner')),

  snooze_minutes smallint not null default 9,
  max_snoozes    smallint not null default 3,
  mission        text not null default 'tap' check (mission in ('tap','math','shake','photo')),

  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  -- Soft delete: a tombstone has to reach the other phone to disarm it. A hard
  -- delete that never syncs is an alarm that rings forever.
  deleted_at     timestamptz,

  constraint anchor_tz_required_for_absolute
    check (tz_mode <> 'absolute' or anchor_tz is not null),
  constraint one_shot_needs_date
    check (repeat_days <> 0 or one_shot_date is not null)
);

create index alarms_pair_updated_idx on public.alarms(pair_id, updated_at);
create index alarms_owner_idx on public.alarms(owner_id);

-- What each person hears. Two rows per shared alarm: "what I hear", "what they
-- hear" -- and you choose theirs. This is the feature people screenshot.
create table public.alarm_sounds (
  alarm_id    uuid not null references public.alarms(id) on delete cascade,
  listener_id uuid not null references public.profiles(id) on delete cascade,
  sound_ref   text not null default 'builtin:sunrise',
  volume      smallint not null default 100 check (volume between 0 and 100),
  vibrate     boolean not null default true,
  set_by      uuid not null references public.profiles(id) on delete cascade,
  updated_at  timestamptz not null default now(),
  primary key (alarm_id, listener_id)
);

-- Both phones fire independently and both try to create the session, so the id
-- is derived from (alarm_id, fired_at) and upserted. A random id would produce
-- two sessions and split the multiplayer layer in half.
create table public.ring_sessions (
  id        uuid primary key,
  alarm_id  uuid not null references public.alarms(id) on delete cascade,
  pair_id   uuid references public.pairs(id) on delete cascade,
  fired_at  timestamptz not null,
  closed_at timestamptz,
  unique (alarm_id, fired_at)
);

create index ring_sessions_pair_idx on public.ring_sessions(pair_id, fired_at desc);

create table public.ring_participants (
  session_id    uuid not null references public.ring_sessions(id) on delete cascade,
  user_id       uuid not null references public.profiles(id) on delete cascade,
  state         text not null default 'ringing'
                check (state in ('ringing','snoozed','dismissed','missed')),
  snooze_count  smallint not null default 0,
  snoozed_until timestamptz,
  acted_by      uuid references public.profiles(id) on delete set null,
  updated_at    timestamptz not null default now(),
  primary key (session_id, user_id)
);

create table public.wake_receipts (
  session_id    uuid primary key references public.ring_sessions(id) on delete cascade,
  pair_id       uuid references public.pairs(id) on delete cascade,
  first_up_user uuid references public.profiles(id) on delete set null,
  total_seconds integer,
  created_at    timestamptz not null default now()
);
