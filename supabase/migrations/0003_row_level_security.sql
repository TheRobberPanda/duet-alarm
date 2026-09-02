-- RLS is the entire authorization model: there is no trusted application server
-- in front of this database, only phones holding a user token. Every table gets
-- RLS enabled and an explicit policy, without exception (docs/03).

alter table public.profiles          enable row level security;
alter table public.pairs             enable row level security;
alter table public.pair_members      enable row level security;
alter table public.pair_invites      enable row level security;
alter table public.alarms            enable row level security;
alter table public.alarm_sounds      enable row level security;
alter table public.ring_sessions     enable row level security;
alter table public.ring_participants enable row level security;
alter table public.wake_receipts     enable row level security;

create policy profiles_select_self_or_partner on public.profiles
  for select to authenticated
  using (id = auth.uid() or public.shares_pair_with(id));

create policy profiles_update_self on public.profiles
  for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

create policy pairs_select_member on public.pairs
  for select to authenticated using (public.is_pair_member(id));
-- Pairs are created only through create_pair_invite(); no direct insert.

create policy pair_members_select on public.pair_members
  for select to authenticated using (public.is_pair_member(pair_id));

-- NOTE: there is deliberately NO insert policy. Joining happens only through
-- redeem_pair_invite(), which validates the code. This is what makes an
-- uninvited join impossible even for someone who knows the pair id.
create policy pair_members_delete_self on public.pair_members
  for delete to authenticated using (user_id = auth.uid());

-- A code is a bearer token: it must NOT be selectable by anyone who has not
-- been given it. Only the creator can read their own codes; redemption goes
-- through redeem_pair_invite(), which runs as definer and needs no read grant.
create policy pair_invites_select_own on public.pair_invites
  for select to authenticated using (created_by = auth.uid());

create policy pair_invites_delete_own on public.pair_invites
  for delete to authenticated using (created_by = auth.uid());

create policy alarms_select on public.alarms
  for select to authenticated
  using (owner_id = auth.uid()
         or (pair_id is not null and public.is_pair_member(pair_id)));

create policy alarms_insert on public.alarms
  for insert to authenticated
  with check (owner_id = auth.uid()
              and (pair_id is null or public.is_pair_member(pair_id)));

-- Either partner may edit a shared alarm: they are shared, not owned.
create policy alarms_update on public.alarms
  for update to authenticated
  using (owner_id = auth.uid()
         or (pair_id is not null and public.is_pair_member(pair_id)))
  with check (owner_id = auth.uid()
              or (pair_id is not null and public.is_pair_member(pair_id)));

create policy alarms_delete on public.alarms
  for delete to authenticated
  using (owner_id = auth.uid()
         or (pair_id is not null and public.is_pair_member(pair_id)));

-- You may write the row for EITHER listener: choosing what your partner wakes
-- up to is the point of the feature.
create policy alarm_sounds_select on public.alarm_sounds
  for select to authenticated
  using (listener_id = auth.uid() or public.shares_pair_with(listener_id));

create policy alarm_sounds_write on public.alarm_sounds
  for all to authenticated
  using (set_by = auth.uid()
         and (listener_id = auth.uid() or public.shares_pair_with(listener_id)))
  with check (set_by = auth.uid()
              and (listener_id = auth.uid() or public.shares_pair_with(listener_id)));

create policy ring_sessions_select on public.ring_sessions
  for select to authenticated
  using (pair_id is null or public.is_pair_member(pair_id));

create policy ring_sessions_insert on public.ring_sessions
  for insert to authenticated
  with check (pair_id is null or public.is_pair_member(pair_id));

create policy ring_sessions_update on public.ring_sessions
  for update to authenticated
  using (pair_id is null or public.is_pair_member(pair_id))
  with check (pair_id is null or public.is_pair_member(pair_id));

create policy ring_participants_select on public.ring_participants
  for select to authenticated
  using (user_id = auth.uid() or public.shares_pair_with(user_id));

create policy ring_participants_insert_self on public.ring_participants
  for insert to authenticated with check (user_id = auth.uid());

-- You may only ever update YOUR OWN state directly. Acting on your partner's row
-- goes through act_on_partner(), which checks their allow_partner_dismiss
-- preference. This policy is what makes that check unavoidable rather than
-- advisory -- verified: a direct cross-user UPDATE affects 0 rows.
create policy ring_participants_update_self on public.ring_participants
  for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy wake_receipts_select on public.wake_receipts
  for select to authenticated
  using (pair_id is null or public.is_pair_member(pair_id));

create policy wake_receipts_insert on public.wake_receipts
  for insert to authenticated
  with check (pair_id is null or public.is_pair_member(pair_id));
