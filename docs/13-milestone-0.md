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
| 11 | Snooze re-rings 9 minutes later | |
| 12 | Two alarms one minute apart both ring | |
| 13 | Timezone change re-arms correctly | |
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

## What "done" looks like

Test 14 passes three nights running. At that point the riskiest assumption in the
whole project is retired, and Milestone 2 (accounts and pairing) can start.

If tests 6, 7, 9 or 14 keep failing after the OEM settings are correct, stop and
say so — that is a finding about the platform, not a bug to grind on, and it
changes the product.
