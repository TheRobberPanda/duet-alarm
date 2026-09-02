# 03 — Data Model

Postgres, on Supabase. Row Level Security is the authorization model — there is no
trusted application server in front of the database, so **every table has RLS
enabled and a policy, without exception.**

## Schema

```sql
-- ─── People ────────────────────────────────────────────────────────────────
create table profiles (
  id            uuid primary key references auth.users(id) on delete cascade,
  display_name  text not null,
  avatar_url    text,
  timezone      text not null default 'UTC',   -- IANA, e.g. 'Europe/Oslo'
  allow_partner_dismiss boolean not null default true,
  created_at    timestamptz not null default now()
);

-- ─── Pairing ───────────────────────────────────────────────────────────────
create table pairs (
  id          uuid primary key default gen_random_uuid(),
  created_at  timestamptz not null default now(),
  status      text not null default 'active'   -- active | dissolved
              check (status in ('active','dissolved'))
);

create table pair_members (
  pair_id   uuid not null references pairs(id) on delete cascade,
  user_id   uuid not null references profiles(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (pair_id, user_id)
);
-- Enforce "at most one active pair per user" with a partial unique index
-- against a view of active pairs, or a trigger. Do NOT rely on client checks.

create table pair_invites (
  code        text primary key,               -- 6 chars, unambiguous alphabet
  pair_id     uuid not null references pairs(id) on delete cascade,
  created_by  uuid not null references profiles(id),
  expires_at  timestamptz not null,
  redeemed_at timestamptz,
  redeemed_by uuid references profiles(id)
);

-- ─── Alarms ────────────────────────────────────────────────────────────────
create table alarms (
  id            uuid primary key default gen_random_uuid(),
  pair_id       uuid references pairs(id) on delete cascade,  -- null = solo alarm
  owner_id      uuid not null references profiles(id),
  label         text not null default '',
  enabled       boolean not null default true,

  -- Wall-clock scheduling. NEVER store a bare UTC instant for a repeating alarm.
  local_time    time not null,                -- 07:00
  repeat_days   smallint not null default 0,  -- bitmask, Mon=1<<0 … Sun=1<<6; 0 = one-shot
  one_shot_date date,                         -- set when repeat_days = 0
  tz_mode       text not null default 'local' -- local | absolute
                check (tz_mode in ('local','absolute')),
  anchor_tz     text,                         -- IANA; required when tz_mode='absolute'

  ring_target   text not null default 'both'
                check (ring_target in ('both','owner','partner')),

  snooze_minutes  smallint not null default 9,
  max_snoozes     smallint not null default 3,   -- 0 = snooze disabled
  mission         text not null default 'tap'
                  check (mission in ('tap','math','shake','photo')),

  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz                     -- soft delete; tombstones must sync
);

-- Per-listener sound. Two rows per alarm in a pair: "what I hear", "what they hear".
create table alarm_sounds (
  alarm_id   uuid not null references alarms(id) on delete cascade,
  listener_id uuid not null references profiles(id) on delete cascade,
  sound_ref  text not null,      -- 'builtin:sunrise' | 'device:<uri>' | 'clip:<storage_id>'
  volume     smallint not null default 100,
  vibrate    boolean not null default true,
  set_by     uuid not null references profiles(id),
  updated_at timestamptz not null default now(),
  primary key (alarm_id, listener_id)
);

-- ─── Ring sessions (the multiplayer layer) ─────────────────────────────────
create table ring_sessions (
  id          uuid primary key default gen_random_uuid(),
  alarm_id    uuid not null references alarms(id) on delete cascade,
  pair_id     uuid references pairs(id) on delete cascade,
  fired_at    timestamptz not null,
  closed_at   timestamptz,
  -- Deterministic id so both phones create/join the SAME session with no
  -- coordination: uuid_v5(alarm_id, fired_at_iso). Critical — see note below.
  unique (alarm_id, fired_at)
);

create table ring_participants (
  session_id  uuid not null references ring_sessions(id) on delete cascade,
  user_id     uuid not null references profiles(id) on delete cascade,
  state       text not null default 'ringing'
              check (state in ('ringing','snoozed','dismissed','missed')),
  snooze_count smallint not null default 0,
  snoozed_until timestamptz,
  acted_by    uuid references profiles(id),   -- who performed the last action
  updated_at  timestamptz not null default now(),
  primary key (session_id, user_id)
);

-- ─── Stats ─────────────────────────────────────────────────────────────────
create table wake_receipts (
  session_id    uuid primary key references ring_sessions(id) on delete cascade,
  pair_id       uuid references pairs(id) on delete cascade,
  first_up_user uuid references profiles(id),
  total_seconds integer,
  created_at    timestamptz not null default now()
);
```

### Note on deterministic session IDs

Both phones fire independently and both will try to create the ring session. If
the ID is random you get two sessions and the multiplayer layer silently splits in
half. Derive it: `uuid_v5(namespace, alarm_id || ':' || fired_at_utc_iso)`, and
have both clients do an idempotent upsert. Round `fired_at` to the scheduled
instant, not `now()` — the two phones' clocks differ by seconds.

## Row Level Security

The core predicate, used everywhere:

```sql
create or replace function is_pair_member(p uuid) returns boolean
language sql stable security definer as $$
  select exists (
    select 1 from pair_members
    where pair_id = p and user_id = auth.uid()
  );
$$;
```

```sql
alter table alarms enable row level security;

create policy "read own or pair alarms" on alarms for select
  using (owner_id = auth.uid() or (pair_id is not null and is_pair_member(pair_id)));

create policy "insert into own pair" on alarms for insert
  with check (owner_id = auth.uid()
              and (pair_id is null or is_pair_member(pair_id)));

create policy "pair members may edit" on alarms for update
  using (owner_id = auth.uid() or (pair_id is not null and is_pair_member(pair_id)));
```

Apply the same shape to `alarm_sounds`, `ring_sessions`, `ring_participants`,
`wake_receipts`.

**The one asymmetric rule:** writing another user's `ring_participants` row (i.e.
"dismiss for both") must additionally check that target user's
`allow_partner_dismiss` flag. Enforce this in a `security definer` function called
by an RPC, not in client code:

```sql
create or replace function act_on_partner(
  p_session uuid, p_target uuid, p_action text
) returns void language plpgsql security definer as $$
begin
  if not exists (select 1 from profiles
                 where id = p_target and allow_partner_dismiss) then
    raise exception 'partner has disabled remote dismiss';
  end if;
  -- … verify caller shares a pair with p_target, then apply the action
end; $$;
```

## Sync protocol

- Client keeps `last_synced_at`. Pull = `select … where updated_at > last_synced_at`
  including soft-deleted rows so tombstones propagate.
- `updated_at` maintained by a trigger, never by the client.
- Push = optimistic local write, queued mutation, retried with backoff.
- Conflict = last-write-wins on server `updated_at`. Log every conflict to
  analytics so you learn whether that assumption held.

## Data you must be able to delete

Both stores now require in-app account deletion. Deleting a profile must cascade
cleanly and must dissolve the pair without orphaning the partner's alarms. Test
this path early — it is a review rejection reason, not a nice-to-have.
