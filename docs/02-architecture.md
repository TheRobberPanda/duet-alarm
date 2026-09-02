# 02 — Architecture

## The governing constraint

> **A phone must ring correctly with no network, no server, and no push.**

Every architectural decision below falls out of that sentence. An alarm clock that
depends on connectivity at ring time is not an alarm clock; it is a notification
app that will get one-star reviews from people who missed a flight.

Therefore:

- **Alarm definitions** sync over the network, ahead of time.
- **Alarm triggers** are scheduled by the OS, on-device, per phone.
- **Ring-session coordination** (snooze/dismiss for both, live awareness) uses the
  network — and degrades gracefully to "just a normal alarm on each phone" when
  the network isn't there.

## Layer diagram

```
┌─────────────────────────────────────────────────────────────┐
│  Flutter UI  (Dart)                                          │
│  screens · state (Riverpod) · local DB (Drift/SQLite)        │
└───────────────┬──────────────────────────┬──────────────────┘
                │ MethodChannel/EventChannel│ HTTPS + WS
┌───────────────▼──────────────┐  ┌────────▼──────────────────┐
│  NATIVE ALARM ENGINE          │  │  Backend (Supabase)       │
│  ── Android (Kotlin) ──       │  │  Postgres + RLS           │
│  AlarmManager exact           │  │  Realtime (WebSocket)     │
│  ForegroundService            │  │  Auth                     │
│  full-screen intent           │  │  Edge Functions           │
│  BOOT_COMPLETED receiver      │  │  Storage (voice clips)    │
│  ── iOS (Swift) ──            │  └────────┬──────────────────┘
│  AlarmKit                     │           │
│  UNUserNotificationCenter     │  ┌────────▼──────────────────┐
│  AVAudioSession               │  │  FCM / APNs (silent push) │
└───────────────────────────────┘  └───────────────────────────┘
```

## Component responsibilities

### Flutter layer
Everything the user sees, plus the local source of truth (SQLite via Drift). It
never schedules an alarm itself — it hands a desired schedule to the native engine
and asks "what is currently armed?" to reconcile.

### Native alarm engine
A small, boring, extremely well-tested module with one job: *given a set of alarm
definitions, make the OS ring at the right moments, and report back what happened.*

Its API surface (identical on both platforms):

```
arm(alarmId, fireAtUtc, soundRef, label, missionType) -> void
disarm(alarmId) -> void
armedAlarms() -> List<ArmedAlarm>       // for reconciliation
snoozeActive(alarmId, untilUtc) -> void
stopActive(alarmId) -> void
events: onFired | onSnoozed | onDismissed | onMissed
```

Keep it this small. Every feature you push into the native layer doubles in cost
and halves in testability.

### Backend (Supabase)
- **Auth** — Sign in with Apple (mandatory on iOS if you offer any social login), Google, email OTP
- **Postgres + RLS** — pairs, alarms, ring sessions. RLS is the entire security model; see doc 03.
- **Realtime** — the live-awareness channel and cross-device snooze/dismiss propagation while a session is hot
- **Edge Functions** — invite-code redemption, push fan-out, subscription webhook receiver
- **Storage** — user-recorded voice alarm sounds

> Chosen over Firebase because Postgres + RLS gives you a real relational model
> with declarative authorization, and you avoid Firestore's awkward
> query-shaped-data problem for a schema this relational. Cost at small scale is
> comparable. See doc 09.

### Push
Silent/data pushes only, for two purposes:
1. **"Your alarms changed, re-sync and re-arm."** Fires when a partner edits an alarm.
2. **"Session state changed."** Fires during an active ring session as a backup to the WebSocket.

Push is **never** the ring trigger. Say it out loud once more.

## The three critical flows

### Flow A — Partner edits an alarm

```
Partner's app  ──write──▶  Postgres
                              │
                              ├─ Realtime event ─▶ your app (if foregrounded)
                              └─ trigger ─▶ Edge Fn ─▶ FCM/APNs silent push
                                                          │
                                                          ▼
                                         your app wakes ─▶ pull changes
                                                       ─▶ native.arm()/disarm()
```

If the push never lands, the app reconciles on next foreground, on a periodic
background refresh, and on device boot. Worst case, you get the old alarm — which
is a **degraded but safe** failure. Design every path so the failure mode is
"rings anyway" rather than "silently doesn't ring."

### Flow B — Alarm fires

Both phones fire independently from their own OS-level schedule. No coordination
required, no network required. Each phone then *tries* to open/join the Ring
Session over the network for the multiplayer layer. Failure to join = a normal
solo alarm. Correct, just less magical.

### Flow C — "Dismiss for both"

```
You tap ──▶ native.stopActive()  (immediate, local, never blocked on network)
        └──▶ POST session action ──▶ Postgres ──▶ Realtime ──▶ partner's phone
                                              └──▶ high-priority push (fallback)
                                                        │
                                       partner's native.stopActive()
```

Your own phone stops **instantly and unconditionally**. The network part is a
best-effort request to also stop theirs. Ordering matters: never await the server
before silencing the phone in the user's hand.

## Offline & conflict rules

- Local writes are optimistic and queued.
- Conflict resolution: **last-write-wins per alarm, by server timestamp.** Alarms
  are small and rarely edited concurrently; anything cleverer is unjustified
  complexity. Log conflicts so you can find out if you were wrong.
- Deletions are soft (`deleted_at`) so a tombstone can propagate and disarm the
  other phone. A hard-deleted alarm that never told the other phone is an alarm
  that rings forever.

## Reconciliation loop

The single most important background job in the app. Runs on: app start, app
foreground, push receipt, device boot, timezone change, and every ~6h via
WorkManager / BGTaskScheduler.

```
1. Pull remote alarm definitions (if network)
2. Merge into local DB
3. Compute desired armed set for the next 48h
4. Diff against native.armedAlarms()
5. arm() / disarm() the differences
6. Report armed-state health to the UI (drives the permission health screen)
```

Write this once, test it exhaustively, and never let a feature bypass it.

## Timezone handling

Store alarms as **wall-clock time + IANA timezone + repeat rule**, never as a
UTC instant. Compute the next fire instant at arm time. Re-arm on
`TIMEZONE_CHANGED` broadcast / `NSSystemTimeZoneDidChange`.

For `absolute` mode (long-distance couples), store the owner's timezone and
resolve both devices against it.

Test matrix must include: DST spring-forward gap (07:00 that doesn't exist), DST
fall-back duplicate hour, traveller crossing the date line, and a device whose
clock is manually wrong.

## Tech stack summary

| Concern | Choice |
|---|---|
| App shell | Flutter 3.x |
| State | Riverpod |
| Local DB | Drift (SQLite) |
| Alarm engine | Native Kotlin + Swift via platform channels |
| Backend | Supabase (Postgres, Auth, Realtime, Edge Functions, Storage) |
| Push | FCM (Android) + APNs (iOS), via Supabase Edge Function |
| Payments | RevenueCat over StoreKit 2 + Play Billing |
| Crash/analytics | Sentry + PostHog |
| CI/CD & iOS builds | Codemagic (see doc 06) |
