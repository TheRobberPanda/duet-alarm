-- Bug found via real two-device testing: PairScreen calls create_pair_invite()
-- in initState so there is always a code on screen, regardless of which side
-- the user ends up using. That silently enrolls every visitor in their own
-- solo "active" pair. When they then redeem someone else's code,
-- enforce_one_active_pair (0002) correctly-but-uselessly blocks it with "user
-- is already in an active pair" -- a bookkeeping artifact of having opened the
-- screen, not a real commitment to that pair.
--
-- Fix: redeeming a code first drops the caller out of a pair that is (a)
-- active, (b) not the one they are joining, and (c) still solo -- i.e. nobody
-- else ever redeemed into it. A pair that already has a second member is left
-- alone; the one-active-pair trigger still correctly blocks that case.
create or replace function public.redeem_pair_invite(p_code text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_invite public.pair_invites;
  v_old_pair uuid;
begin
  if v_user is null then raise exception 'not authenticated'; end if;

  select * into v_invite from public.pair_invites
  where code = upper(trim(p_code)) for update;

  if v_invite is null then raise exception 'no such code'; end if;
  if v_invite.redeemed_at is not null then raise exception 'code already used'; end if;
  if v_invite.expires_at < now() then raise exception 'code has expired'; end if;
  if v_invite.created_by = v_user then raise exception 'that is your own code'; end if;

  select pm.pair_id into v_old_pair
  from public.pair_members pm
  join public.pairs p on p.id = pm.pair_id
  where pm.user_id = v_user
    and p.status = 'active'
    and pm.pair_id <> v_invite.pair_id
  limit 1;

  if v_old_pair is not null
     and (select count(*) from public.pair_members where pair_id = v_old_pair) = 1
  then
    delete from public.pair_members where pair_id = v_old_pair and user_id = v_user;
  end if;

  insert into public.pair_members (pair_id, user_id) values (v_invite.pair_id, v_user);

  update public.pair_invites
  set redeemed_at = now(), redeemed_by = v_user
  where code = v_invite.code;

  return v_invite.pair_id;
end; $$;
