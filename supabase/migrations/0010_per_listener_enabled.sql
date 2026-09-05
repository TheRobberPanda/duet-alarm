-- Whether an alarm is switched on is a PER-PERSON choice, not a property of
-- the shared alarm.
--
-- The two of you share one alarm row -- same time, same days -- but either of
-- you may want it silent tonight without touching the other's morning. That is
-- what the ring is meant to show at a glance: your half lit in your skin if
-- you have it on, their half in theirs if they do.
--
-- alarm_sounds is already the per-listener table (one row per alarm per
-- listener, which is what makes "you pick what they hear" work), so this
-- belongs here rather than in a new table. The shared alarms.enabled column
-- stays as it was and is still written: it remains the fallback for a row that
-- has no per-listener entry yet, so nothing that predates this migration
-- suddenly reads as switched off.
alter table public.alarm_sounds
  add column if not exists enabled boolean not null default true;

comment on column public.alarm_sounds.enabled is
  'Whether THIS listener has the alarm switched on. Falls back to alarms.enabled when no row exists.';
