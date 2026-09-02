# 01 — Product Spec

## The premise

Two people link their phones into a **Pair**. Alarms belong to the Pair, not to a
person. When an alarm fires, it fires on **both** phones simultaneously. Either
person can act on it, and the other phone reacts.

This is not a "remote wake-up call" app. It is a *shared* alarm clock. That
distinction matters: it means no phone ever depends on the network to ring.

## Who this is for

- Couples on different schedules ("wake me when you leave for your shift")
- Long-distance couples (shared morning ritual across timezones)
- Roommates / carpools / gym partners
- Parent + teenager (a nagging use case that converts well)

Primary launch persona: **couples living together**, ages 20–35. They already
share a Spotify plan and a food-delivery account. They are used to paying for
two-person software.

## Core concepts

### Pair
Exactly two accounts, linked. One invite code, one accept, done. A user is in at
most one Pair at a time (v1). Unpairing is mutual-notify and non-destructive:
alarms go back to being personal.

> Why exactly two, not N? "Multiplayer" scales badly for alarms — the snooze
> semantics get incoherent with 4 people. Two keeps the rules simple and the
> emotional story sharp. Groups are a post-launch experiment, not v1.

### Alarm
An alarm has:
- Time + repeat rule (once, weekdays, custom days)
- **Timezone anchoring mode** — `local` (07:00 wherever each person is) or
  `absolute` (rings at the same instant for both). Default `local`. This is the
  single most-underestimated correctness detail in the app.
- **Owner** — who created it
- **Ring targets** — `both` (default), `me only`, `partner only`
- **Per-person sound** — the sound *I* hear can differ from the sound *they* hear.
  I choose theirs; they choose mine. This is the feature people will screenshot.
- Label ("Gym", "Your flight")
- Snooze policy (duration, max snoozes, or snooze disabled)
- Dismiss policy (tap, or a **mission**: math problem, shake, scan a photo)

### Ring Session
When an alarm fires, a **Ring Session** is created. It is the shared live object
both phones read and write. This is the heart of the multiplayer feel.

Each participant device has a state: `ringing`, `snoozed`, `dismissed`.
The session as a whole is `active` until every participant is `dismissed`.

## Ring semantics — the rules table

These need to be unambiguous before a line of code is written.

| Action | Effect on you | Effect on partner |
|---|---|---|
| **Snooze (self)** | You go quiet, re-ring in N min | Nothing. They keep ringing. |
| **Dismiss (self)** | You go quiet permanently | Nothing. They keep ringing. |
| **Snooze for both** | Both go quiet, both re-ring in N min | Same |
| **Dismiss for both** | Session over on both phones | Same |
| **Partner dismissed for both, but you're asleep** | Your phone stops ringing | — |

**Default button layout on the ringing screen:** big `Snooze` and `Dismiss` act on
**self only**. The "for both" variants live behind a long-press or a secondary
row. Rationale: dismissing your partner's alarm by accident is the single worst
thing this app can do to a user. Make the destructive-to-someone-else action
deliberate.

**Setting: "Let my partner dismiss my alarms."** Per-user, default **on**, but
prominently surfaced during onboarding. Some people will want it off. Respect it —
if off, the partner's "dismiss for both" only dismisses their own side, and their
UI says so honestly rather than silently no-op'ing.

### Live awareness (the delight layer)
While a Ring Session is active, each phone shows what the other is doing:

> *"Sam snoozed — 4:51 left"*
> *"Alex is still ringing"* (with a little pulsing indicator)
> *"Sam is up ☀️"*

This is what makes it feel multiplayer rather than just synchronized. It is
best-effort over the network; if it doesn't arrive, the alarm still works
correctly. **Never let this layer be load-bearing.**

### Wake receipts / streaks
When both dismiss, the session closes and produces a receipt: who woke first, how
many snoozes each, how long it took. Feeds a shared streak counter. Cheap to
build, disproportionately good at retention.

## Screens (v1)

1. **Onboarding** — value prop, sign in, notification/alarm permission priming
2. **Pair setup** — generate code / enter code / QR
3. **Home** — list of alarms, next-to-fire prominent, partner status strip at top
4. **Alarm editor** — time, repeat, targets, *two* sound pickers (mine / theirs), mission, snooze policy
5. **Sound picker** — built-ins, device tones, (paid) voice recordings
6. **Ringing screen** — full-screen, the rules table above made visual
7. **Settings** — profile, pair management, permissions health check, subscription
8. **Permission health check** — a dedicated screen that detects and explains every
   OS setting that could stop the alarm (battery optimization, exact alarm permission,
   DND, notification permission, Focus modes). **This screen prevents your 1-star reviews.**

## Explicit non-goals for v1

- Groups larger than two
- Sleep tracking / smart wake windows
- Music-service integration (Spotify as alarm sound = licensing pain)
- Web app
- Wearables

## The one-line pitch

> *An alarm clock you share with someone. Both phones ring. Either of you can turn it off.*
