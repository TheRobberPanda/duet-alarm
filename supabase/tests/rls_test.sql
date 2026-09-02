-- RLS verification. Run against a scratch project or a branch, NEVER production:
-- it creates and deletes users.
--
-- The question this answers is not "do the policies exist" but "can an outsider
-- get in". Four users: Alex and Sam are a pair, Mallory is an attacker, Dave has
-- a half-empty pair (so the pair-size trigger cannot mask a missing RLS policy).

begin;

insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
values
 ('11111111-1111-1111-1111-111111111111','00000000-0000-0000-0000-000000000000','authenticated','authenticated','alex@test.local','x',now(),now(),now(),'{}','{"display_name":"Alex"}'),
 ('22222222-2222-2222-2222-222222222222','00000000-0000-0000-0000-000000000000','authenticated','authenticated','sam@test.local','x',now(),now(),now(),'{}','{"display_name":"Sam"}'),
 ('33333333-3333-3333-3333-333333333333','00000000-0000-0000-0000-000000000000','authenticated','authenticated','mallory@test.local','x',now(),now(),now(),'{}','{"display_name":"Mallory"}'),
 ('44444444-4444-4444-4444-444444444444','00000000-0000-0000-0000-000000000000','authenticated','authenticated','dave@test.local','x',now(),now(),now(),'{}','{"display_name":"Dave"}');

create temp table results(check_name text, outcome text, detail text);
grant all on results to authenticated;

-- Helper: become a given user, exactly as a signed-in phone would appear.
create or replace function pg_temp.become(u uuid) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', u, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
end; $$;

do $$
declare v_code text; v_pair uuid; v_alarm uuid; v_daves_pair uuid; n int;
begin
  -- ── Pairing ──────────────────────────────────────────────────────────────
  perform pg_temp.become('11111111-1111-1111-1111-111111111111');
  v_code := public.create_pair_invite();
  insert into results values ('alex_creates_invite', 'PASS', v_code);

  perform pg_temp.become('22222222-2222-2222-2222-222222222222');
  v_pair := public.redeem_pair_invite(v_code);
  insert into results values ('sam_redeems_invite', 'PASS', v_pair::text);

  -- ── Sharing ──────────────────────────────────────────────────────────────
  perform pg_temp.become('11111111-1111-1111-1111-111111111111');
  insert into public.alarms (pair_id, owner_id, label, local_time, repeat_days)
  values (v_pair, '11111111-1111-1111-1111-111111111111', 'Gym', '06:40', 31)
  returning id into v_alarm;

  perform pg_temp.become('22222222-2222-2222-2222-222222222222');
  select count(*) into n from public.alarms;
  insert into results values ('partner_sees_shared_alarm',
    case when n = 1 then 'PASS' else 'FAIL' end, n || ' alarm(s)');

  select count(*) into n from public.pair_invites;
  insert into results values ('partner_cannot_read_invite_codes',
    case when n = 0 then 'PASS' else 'FAIL' end, n || ' code(s) — codes are bearer tokens');

  -- ── Outsider visibility ──────────────────────────────────────────────────
  perform pg_temp.become('33333333-3333-3333-3333-333333333333');
  select (select count(*) from public.alarms) + (select count(*) from public.pairs)
       + (select count(*) from public.pair_members) + (select count(*) from public.pair_invites)
       + (select count(*) from public.alarm_sounds) into n;
  insert into results values ('outsider_sees_nothing',
    case when n = 0 then 'PASS' else 'FAIL' end, n || ' row(s) visible');

  select count(*) into n from public.profiles;
  insert into results values ('outsider_sees_only_own_profile',
    case when n = 1 then 'PASS' else 'FAIL' end, n || ' profile(s)');

  -- ── Outsider writes ──────────────────────────────────────────────────────
  begin
    insert into public.alarms (pair_id, owner_id, label, local_time, repeat_days)
    values (v_pair, '33333333-3333-3333-3333-333333333333', 'evil', '03:00', 127);
    insert into results values ('outsider_cannot_inject_alarm','FAIL — inserted','');
  exception when others then
    insert into results values ('outsider_cannot_inject_alarm','PASS', sqlerrm);
  end;

  begin
    insert into public.alarms (pair_id, owner_id, label, local_time, repeat_days)
    values (v_pair, '11111111-1111-1111-1111-111111111111', 'spoof', '03:00', 127);
    insert into results values ('outsider_cannot_spoof_owner','FAIL — inserted','');
  exception when others then
    insert into results values ('outsider_cannot_spoof_owner','PASS', sqlerrm);
  end;

  update public.profiles set allow_partner_dismiss = false
  where id = '11111111-1111-1111-1111-111111111111';
  insert into results values ('outsider_cannot_edit_others_prefs',
    case when found then 'FAIL — updated' else 'PASS' end, 'RLS filtered');

  begin
    perform public.redeem_pair_invite(v_code);
    insert into results values ('reused_code_refused','FAIL — accepted','');
  exception when others then
    insert into results values ('reused_code_refused','PASS', sqlerrm);
  end;

  begin
    perform public.redeem_pair_invite('ZZZZZZ');
    insert into results values ('unknown_code_refused','FAIL — accepted','');
  exception when others then
    insert into results values ('unknown_code_refused','PASS', sqlerrm);
  end;

  -- ── Uninvited join into a HALF-EMPTY pair ────────────────────────────────
  -- Critical: against a full pair the size trigger fires first and can mask a
  -- missing RLS policy. Dave's pair has room, so only RLS can stop this.
  perform pg_temp.become('44444444-4444-4444-4444-444444444444');
  perform public.create_pair_invite();
  reset role;
  select pm.pair_id into v_daves_pair from public.pair_members pm
  where pm.user_id = '44444444-4444-4444-4444-444444444444' limit 1;

  perform pg_temp.become('33333333-3333-3333-3333-333333333333');
  begin
    execute format('insert into public.pair_members (pair_id, user_id) values (%L, %L)',
                   v_daves_pair, '33333333-3333-3333-3333-333333333333');
    insert into results values ('uninvited_join_blocked','FAIL — joined','');
  exception when others then
    insert into results values ('uninvited_join_blocked','PASS', sqlerrm);
  end;

  -- ── The asymmetric rule ──────────────────────────────────────────────────
  reset role;
  insert into public.ring_sessions (id, alarm_id, pair_id, fired_at)
  values ('aaaaaaaa-0000-0000-0000-000000000001', v_alarm, v_pair, now());
  insert into public.ring_participants (session_id, user_id) values
    ('aaaaaaaa-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111'),
    ('aaaaaaaa-0000-0000-0000-000000000001','22222222-2222-2222-2222-222222222222');
  update public.profiles set allow_partner_dismiss = true
  where id = '11111111-1111-1111-1111-111111111111';

  -- Sam writing Alex's row directly must be a no-op.
  perform pg_temp.become('22222222-2222-2222-2222-222222222222');
  update public.ring_participants set state = 'dismissed'
  where session_id = 'aaaaaaaa-0000-0000-0000-000000000001'
    and user_id = '11111111-1111-1111-1111-111111111111';
  insert into results values ('direct_cross_user_write_blocked',
    case when found then 'FAIL — updated' else 'PASS' end, 'must go through act_on_partner');

  -- The legitimate route works while the preference allows it.
  perform public.act_on_partner('aaaaaaaa-0000-0000-0000-000000000001',
                                '11111111-1111-1111-1111-111111111111', 'dismiss');
  select count(*) into n from public.ring_participants
  where user_id = '11111111-1111-1111-1111-111111111111' and state = 'dismissed';
  insert into results values ('act_on_partner_allowed',
    case when n = 1 then 'PASS' else 'FAIL' end, '');

  -- And is refused once the target opts out.
  reset role;
  update public.profiles set allow_partner_dismiss = false
  where id = '11111111-1111-1111-1111-111111111111';
  perform pg_temp.become('22222222-2222-2222-2222-222222222222');
  begin
    perform public.act_on_partner('aaaaaaaa-0000-0000-0000-000000000001',
                                  '11111111-1111-1111-1111-111111111111', 'dismiss');
    insert into results values ('act_on_partner_respects_optout','FAIL — allowed','');
  exception when others then
    insert into results values ('act_on_partner_respects_optout','PASS', sqlerrm);
  end;

  -- A stranger cannot use it at all.
  perform pg_temp.become('33333333-3333-3333-3333-333333333333');
  begin
    perform public.act_on_partner('aaaaaaaa-0000-0000-0000-000000000001',
                                  '11111111-1111-1111-1111-111111111111', 'dismiss');
    insert into results values ('stranger_cannot_act_on_partner','FAIL — allowed','');
  exception when others then
    insert into results values ('stranger_cannot_act_on_partner','PASS', sqlerrm);
  end;

  reset role;
end $$;

select check_name,
       outcome,
       left(detail, 60) as detail
from results order by check_name;

-- Any FAIL row means the security model is broken. Do not ship.
select count(*) filter (where outcome like 'FAIL%') as failures from results;

rollback;  -- leaves no fixtures behind
