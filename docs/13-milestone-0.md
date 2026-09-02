# 13 — Milestone 0: does it actually ring?

The only question this milestone answers: **a phone in a drawer, offline,
overnight, rings at the time it was told to.** No accounts, no backend, no
partner, no design. If this fails, the project is different than you think — and
you want to find that out in week one.

## Environment

The toolchain is installed at:

| Thing | Path |
|---|---|
| Flutter SDK | `~/development/flutter` |
| Android SDK | `~/Android/Sdk` |
| Java | system JDK 21 |

Shell environment does not persist between commands, so the repo carries
`tool/env.sh`. Source it before any Flutter work:

```bash
source tool/env.sh
```

To make it permanent, append the same three lines to `~/.bashrc`.

## Layout

```
app/
├── lib/
│   ├── main.dart          Milestone 0 harness UI
│   ├── alarm_engine.dart  Dart side of the platform channel
│   └── next_fire.dart     Pure scheduling maths — no Flutter, no Android
├── test/
│   └── next_fire_test.dart
└── android/app/src/main/
    ├── AndroidManifest.xml
    └── kotlin/com/duet/alarm/
        ├── MainActivity.kt      the ONLY Flutter↔native bridge
        ├── AlarmScheduler.kt    setAlarmClock, arm/disarm/reconcile
        ├── AlarmStore.kt        device's own record of what should ring
        ├── AlarmReceiver.kt     fires → starts the service, nothing else
        ├── AlarmService.kt      wake lock, audio, vibration, full-screen intent
        ├── RingingActivity.kt   pure native — no Flutter engine involved
        ├── BootReceiver.kt      re-arms after reboot / update / timezone change
        └── PermissionChecks.kt  everything the OS can do to stop the alarm
```

## Design decisions worth knowing before you read the code

**The ringing screen is not Flutter.** Cold-starting the Flutter engine from a
locked screen at 06:00 adds latency and a failure class you cannot debug from
bed — on the one screen that must work. `RingingActivity` is plain Android views
with zero dependencies, so it still works if the Flutter side is broken entirely.

**`setAlarmClock`, not `setExactAndAllowWhileIdle`.** It is the API meant for
user-facing alarm clocks: exempt from Doze, shows the status-bar alarm icon,
highest scheduling priority available.

**`USE_EXACT_ALARM`, not `SCHEDULE_EXACT_ALARM`.** Granted at install with no
prompt. Google Play restricts it to apps whose core function is an alarm clock —
see doc 12 §2.1 on why the store listing must say "Alarm Clock" in the title.

**The native side never calls back into Dart to decide whether to ring.**
`AlarmStore` is the device's own record. Dart pushes definitions in; the OS and
the store are the only things consulted at fire time.

**Every alarm that rings is logged.** `RingLog` is Milestone 0's most important
output — comparing what was armed against what actually rang is how a silently
missed alarm becomes a visible, fixable one instead of a one-star review.

## Running it

```bash
source tool/env.sh && cd app && flutter run
```

Unit tests (fast, no device needed — this is the DST/timezone matrix):

```bash
source tool/env.sh && cd app && flutter test
```

## Enabling your Redmi

1. Settings → About phone → tap **MIUI version** 7 times → Developer options unlocked
2. Settings → Additional settings → Developer options → enable **USB debugging**
3. Also enable **Install via USB** and **USB debugging (Security settings)** — MIUI
   needs these and will otherwise fail silently or refuse the install
4. Plug in, accept the RSA prompt, then `adb devices` should list it

Then, in the app's own health section, fix everything it flags, and separately:

- **Autostart: ON** — without it, no alarm survives a restart. This cannot be read
  programmatically, which is why the app can only warn about it.
- **Battery saver → No restrictions**
- **Lock the app in Recents** (the padlock on the task card)
- Allow **Show on Lock screen** and **Display pop-up windows while running in
  background** — the ringing screen will not appear over the lock screen without them

## The Milestone 0 test plan

Each of these on the real Redmi, screen off, phone locked. Tick them off honestly.

| # | Test | Pass? |
|---|---|---|
| 1 | Rings 30 seconds out with the app open | ✅ 12 ms late |
| 2 | Rings 2 minutes out with the phone locked, face down | ✅ |
| 3 | Ringing screen appears **over** the lock screen | ✅ incl. pre-unlock after reboot |
| 4 | Audio plays with media volume at zero (alarm stream) | |
| 5 | Audio plays with Do Not Disturb on | |
| 6 | Rings after 8 hours idle in a drawer (Doze) | |
| 7 | Rings with airplane mode on | |
| 8 | Rings with Battery Saver on | |
| 9 | Survives a reboot — arm, restart the phone, do not open the app | ✅ 1.45 s late, fired *before* first unlock |
| 10 | Survives an app update — arm, `flutter run` again, do not reopen | ✅ MY_PACKAGE_REPLACED re-arms |
| 11 | Snooze re-rings after the configured delay | ✅ incl. allowance boundary |
| 12 | Two alarms one minute apart both ring | |
| 13 | Timezone change re-arms correctly | ⚠ code in place, **needs a real device timezone change** |
| 14 | **Overnight, offline, in a drawer, from 23:00 to 06:40** | |

Test 14 is the milestone. The rest are the ways it fails.

### What the first reboot test actually taught us

Test 9 did fail first — but Autostart was not the reason, and the guess was
wrong. Two real defects surfaced instead:

1. Alarm state was in credential-encrypted storage, so the boot receiver threw
   `IllegalStateException` at `LOCKED_BOOT_COMPLETED` and no alarm was re-armed.
   Alarm state now lives in **device-protected storage**. For an alarm clock this
   is the correct design, not a workaround: a phone that reboots at 03:00 stays
   at the lock screen until someone unlocks it, so the alarm has to be readable
   before first unlock in order to ring at all.

2. MIUI delivered `BOOT_COMPLETED` **three and a half minutes** after boot. By
   then the alarm was overdue, and `prune()` deleted it silently while logging a
   cheerful "reconciled 0 alarm(s)". Overdue alarms are now recorded to
   `MissedLog`, logged at warn, and shown in the app.

After the fix the alarm re-armed during direct boot and fired 1.45 s late,
*before* `BOOT_COMPLETED` arrived — i.e. before first unlock.

The screen appeared, but that first run could not prove *when*: the alarm fired
0.7 s before `BOOT_COMPLETED`, so the phone was unlocked about a second into
ringing. `RingingActivity` was then also marked `directBootAware` and the test
repeated, leaving the phone untouched:

```
17:43:29.977  LOCKED_BOOT_COMPLETED → re-armed 1 alarm    (direct boot)
17:44:34.746  FIRED                                        (326 ms late)
17:44:47.010  RingingActivity on screen
17:45:07.567  BOOT_COMPLETED                               (first unlock)
```

The ringing screen was up **20 seconds before first unlock**. Audio, screen and
dismissal all work before the device has ever been unlocked — the overnight
reboot case is genuinely covered, not covered by luck.

All four components in the ring path (`AlarmReceiver`, `AlarmService`,
`BootReceiver`, `RingingActivity`) are `directBootAware`, and all alarm state is
in device-protected storage. Nothing in the chain depends on an unlock.

### An unlocked phone gets a notification, not the full-screen screen

Android only launches a full-screen intent when the screen is off or locked.
With the phone unlocked and in use it shows a heads-up notification instead —
correct platform behaviour, but our notification had no actions, so the only way
to stop the alarm was to tap through to the ringing screen first.

Snooze and Dismiss are now notification actions, sharing `AlarmActions` with the
ringing screen so the two cannot drift apart. Acting from either closes the
other via an internal `RING_ENDED` broadcast.

Verified on device, with a 1-minute snooze and an allowance of 2:

```
21:21:10  snoozed notiftest for 1 min (1/2)
21:22:13  snoozed snooze:notiftest for 1 min (2/2)
3rd ring  actions=1, [0] "Dismiss"     — Snooze correctly withdrawn
21:23:32  dismissed snooze:notiftest
```

### A repeating alarm must schedule its own next occurrence

Dart arms a rolling 48-hour window, but only when the app runs. A Monday-only
alarm that fired on Monday was removed as spent, and the next occurrence — seven
days away, outside the window — was never armed. If the user did not happen to
open the app before the following Monday, **the alarm simply never rang again**,
and nothing reported it: it was never armed, so it could not be "missed".

`AlarmService` now arms the next occurrence at the moment an alarm fires, using
the wall clock that travels with the definition. Repeating alarms therefore
perpetuate themselves with no app run at all.

The companion change matters just as much: Dart's reconcile no longer disarms
anything beyond its own horizon. Without that it would have deleted the
natively-armed occurrence on the very next app launch and reintroduced the gap.

Verified on device:

```
21:11:00.029  FIRED weeklytest#1788376260000   (29 ms late)
21:11:00.295  armed weeklytest#1788981060000   (exactly 7 days later)
```

and the 7-day-out alarm then survived a force-stop and full reconcile.

### Timezone changes need recomputation, not re-arming

The store holds absolute instants, because that is what `AlarmManager` takes.
But "07:00" means seven o'clock *wherever you are*. Re-arming the stored instant
after a flight from Oslo to Lisbon makes the alarm ring at 06:00, and nothing
corrects it until the app next runs — which for a traveller may be after it has
already gone off at the wrong time.

`AlarmDef` therefore also carries the wall clock (`wallHour`, `wallMinute`,
`repeatDays`, `tzMode`), and `AlarmScheduler.rezone()` recomputes the instants on
`TIMEZONE_CHANGED` / `TIME_SET` using `NextFire.kt`. Dart's reconcile stays
authoritative and overwrites whatever this produced on its next run; the Kotlin
copy only has to keep things right in the meantime. **Do not let it grow into a
second scheduler** — two schedulers that disagree is worse than one that is
occasionally stale.

**This cannot be tested from a host machine:** `TIMEZONE_CHANGED` is a protected
broadcast that `adb shell` may not send, so it must be exercised by actually
changing the device's timezone in Settings and checking that a repeating alarm's
next-fire time moves with it.

## What "done" looks like

Test 14 passes three nights running. At that point the riskiest assumption in the
whole project is retired, and Milestone 2 (accounts and pairing) can start.

If tests 6, 7, 9 or 14 keep failing after the OEM settings are correct, stop and
say so — that is a finding about the platform, not a bug to grind on, and it
changes the product.
