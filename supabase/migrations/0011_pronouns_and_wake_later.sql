-- Two small additions, both driven by the set-alarm screen.
--
-- 1. Pronouns. The app talks about your partner constantly ("wake them up",
--    "just them") and "them" reads oddly when you know it is her or him. Each
--    person picks their own; the partner's phone reads it to phrase things.
--    'they' is the default, so nobody is guessed at.
alter table public.profiles
  add column if not exists pronouns text not null default 'they'
    check (pronouns in ('she', 'he', 'they'));

-- 2. "Wake them 15 minutes later". A shared alarm stays one row with one
--    time; this names the listener whose phone rings 15 minutes after it.
--    A listener id rather than a flag on the owner, because owner_id is
--    rewritten by whoever last saved the alarm -- "the partner" would flip
--    meaning every time the other one edited it. Null means both ring at the
--    same time.
alter table public.alarms
  add column if not exists wake_later_id uuid
    references public.profiles(id) on delete set null;

comment on column public.alarms.wake_later_id is
  'The listener whose copy of this alarm rings 15 minutes after local_time. Null = no stagger.';
