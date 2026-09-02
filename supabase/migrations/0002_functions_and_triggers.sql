-- All SECURITY DEFINER functions pin an empty search_path and fully qualify
-- every name: a mutable search_path on a definer function is a privilege
-- escalation route, and Supabase's own advisor flags it.

-- updated_at is maintained by the database, never by the client. Sync uses it to
-- decide which write wins (ADR-009); if a client could set it, a client could
-- win every conflict.
create or replace function public.set_updated_at()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end; $$;

create trigger profiles_updated_at before update on public.profiles
  for each row execute function public.set_updated_at();
create trigger pairs_updated_at before update on public.pairs
  for each row execute function public.set_updated_at();
create trigger alarms_updated_at before update on public.alarms
  for each row execute function public.set_updated_at();
create trigger alarm_sounds_updated_at before update on public.alarm_sounds
  for each row execute function public.set_updated_at();
create trigger ring_participants_updated_at before update on public.ring_participants
  for each row execute function public.set_updated_at();

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data->>'display_name', ''))
  on conflict (id) do nothing;
  return new;
end; $$;

create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- SECURITY DEFINER so that RLS policies on pair_members can call it without
-- recursing into the very policy being evaluated.
create or replace function public.is_pair_member(p uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.pair_members
    where pair_id = p and user_id = auth.uid()
  );
$$;

create or replace function public.shares_pair_with(other uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
    from public.pair_members me
    join public.pair_members them on them.pair_id = me.pair_id
    join public.pairs p on p.id = me.pair_id
    where me.user_id = auth.uid()
      and them.user_id = other
      and p.status = 'active'
  );
$$;

-- ADR-005: a user belongs to at most one ACTIVE pair. The advisory lock closes
-- the race between two concurrent redemptions of different codes.
create or replace function public.enforce_one_active_pair()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform pg_advisory_xact_lock(hashtext(new.user_id::text));
  if exists (
    select 1 from public.pair_members pm
    join public.pairs p on p.id = pm.pair_id
    where pm.user_id = new.user_id
      and p.status = 'active'
      and pm.pair_id <> new.pair_id
  ) then
    raise exception 'user is already in an active pair'
      using errcode = 'unique_violation';
  end if;
  return new;
end; $$;

create trigger pair_members_one_active before insert on public.pair_members
  for each row execute function public.enforce_one_active_pair();

create or replace function public.enforce_pair_size()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if (select count(*) from public.pair_members where pair_id = new.pair_id) >= 2 then
    raise exception 'a pair already has two members';
  end if;
  return new;
end; $$;

create trigger pair_members_max_two before insert on public.pair_members
  for each row execute function public.enforce_pair_size();

-- Alphabet excludes 0/O/1/I/L: the code gets read aloud and typed by hand.
-- (Superseded by 0005, which fixes a variable/column name collision.)
create or replace function public.generate_invite_code()
returns text language plpgsql security definer set search_path = '' as $$
declare
  alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  v_code text;
begin
  loop
    v_code := '';
    for i in 1..6 loop
      v_code := v_code || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
    end loop;
    exit when not exists (select 1 from public.pair_invites pi where pi.code = v_code);
  end loop;
  return v_code;
end; $$;

create or replace function public.create_pair_invite()
returns text language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_pair uuid;
  v_code text;
begin
  if v_user is null then raise exception 'not authenticated'; end if;

  select pm.pair_id into v_pair
  from public.pair_members pm
  join public.pairs p on p.id = pm.pair_id
  where pm.user_id = v_user and p.status = 'active'
  limit 1;

  if v_pair is null then
    insert into public.pairs default values returning id into v_pair;
    insert into public.pair_members (pair_id, user_id) values (v_pair, v_user);
  end if;

  if (select count(*) from public.pair_members where pair_id = v_pair) >= 2 then
    raise exception 'this pair is already complete';
  end if;

  v_code := public.generate_invite_code();
  insert into public.pair_invites (code, pair_id, created_by, expires_at)
  values (v_code, v_pair, v_user, now() + interval '24 hours');

  return v_code;
end; $$;

create or replace function public.redeem_pair_invite(p_code text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_invite public.pair_invites;
begin
  if v_user is null then raise exception 'not authenticated'; end if;

  select * into v_invite from public.pair_invites
  where code = upper(trim(p_code)) for update;

  if v_invite is null then raise exception 'no such code'; end if;
  if v_invite.redeemed_at is not null then raise exception 'code already used'; end if;
  if v_invite.expires_at < now() then raise exception 'code has expired'; end if;
  if v_invite.created_by = v_user then raise exception 'that is your own code'; end if;

  insert into public.pair_members (pair_id, user_id) values (v_invite.pair_id, v_user);

  update public.pair_invites
  set redeemed_at = now(), redeemed_by = v_user
  where code = v_invite.code;

  return v_invite.pair_id;
end; $$;

-- The one asymmetric rule in the app. A client must never be able to stop
-- someone else's alarm just by writing their participant row: it has to pass
-- through here, where the target's own preference is checked. See ADR-006.
create or replace function public.act_on_partner(
  p_session uuid, p_target uuid, p_action text
) returns void language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_snooze_minutes smallint;
begin
  if v_user is null then raise exception 'not authenticated'; end if;
  if p_action not in ('snooze','dismiss') then raise exception 'unknown action'; end if;

  if not public.shares_pair_with(p_target) then
    raise exception 'not your partner';
  end if;

  if not exists (
    select 1 from public.profiles where id = p_target and allow_partner_dismiss
  ) then
    raise exception 'partner has turned off remote dismiss';
  end if;

  select a.snooze_minutes into v_snooze_minutes
  from public.ring_sessions s
  join public.alarms a on a.id = s.alarm_id
  where s.id = p_session;

  if p_action = 'dismiss' then
    update public.ring_participants
       set state = 'dismissed', acted_by = v_user, snoozed_until = null
     where session_id = p_session and user_id = p_target;
  else
    update public.ring_participants
       set state = 'snoozed',
           acted_by = v_user,
           snooze_count = snooze_count + 1,
           snoozed_until = now() + make_interval(mins => coalesce(v_snooze_minutes, 9))
     where session_id = p_session and user_id = p_target;
  end if;
end; $$;

-- Required by both stores, and much harder to retrofit than to build now
-- (docs/07 and docs/12 section 2.4). Dissolves the pair so the partner is not
-- left with a half-deleted relationship; the cascade removes everything else.
create or replace function public.delete_my_account()
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'not authenticated'; end if;

  update public.pairs set status = 'dissolved'
  where id in (select pair_id from public.pair_members where user_id = v_user);

  delete from auth.users where id = v_user;
end; $$;
