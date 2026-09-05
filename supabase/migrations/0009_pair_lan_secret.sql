-- A shared secret for the local-network fast path (LanSync.kt).
--
-- When both phones are on the same wifi, ring state and "for both of us"
-- actions travel over a signed UDP broadcast instead of a round trip to here:
-- the ringing screen has no Flutter engine and so no Supabase realtime client,
-- and a datagram is far less machinery than a raw websocket would be. The
-- cloud path stays as the always-on fallback -- LAN is strictly an
-- optimisation, never a dependency (ADR-001 still holds: nothing about
-- actually ringing waits on any network).
--
-- Why a dedicated column rather than reusing pair_id as the key: pair_id
-- travels in every LAN datagram as the routing field, so it cannot also be
-- the thing that authenticates them. This one is never transmitted -- only
-- used to sign -- and is readable exactly by the two pair members, under the
-- pairs_select_member policy that already exists.
alter table public.pairs
  add column if not exists lan_secret uuid not null default gen_random_uuid();

-- Existing rows get their default from the DDL above; this is only here to be
-- explicit that no pair is left without one.
update public.pairs set lan_secret = gen_random_uuid() where lan_secret is null;
