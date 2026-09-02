-- pairs has no foreign key to profiles, so deleting the last member (account
-- deletion, or both partners leaving) left the pair row behind forever. Found
-- by tearing down the RLS test fixtures: two member-less pairs survived.
--
-- A pair only exists to join two people. With nobody in it, it is garbage that
-- also keeps its alarms and invite codes alive via cascade.
create or replace function public.reap_empty_pair()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.pair_members where pair_id = old.pair_id) then
    delete from public.pairs where id = old.pair_id;
  end if;
  return old;
end; $$;

revoke all on function public.reap_empty_pair() from public, anon, authenticated;

create trigger pair_members_reap_empty after delete on public.pair_members
  for each row execute function public.reap_empty_pair();

delete from public.pairs p
where not exists (select 1 from public.pair_members pm where pm.pair_id = p.id);
