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
| 1 | Rings 30 seconds out with the app open | |
| 2 | Rings 2 minutes out with the phone locked, face down | |
| 3 | Ringing screen appears **over** the lock screen | |
| 4 | Audio plays with media volume at zero (alarm stream) | |
| 5 | Audio plays with Do Not Disturb on | |
| 6 | Rings after 8 hours idle in a drawer (Doze) | |
| 7 | Rings with airplane mode on | |
| 8 | Rings with Battery Saver on | |
| 9 | Survives a reboot — arm, restart the phone, do not open the app | |
| 10 | Survives an app update — arm, `flutter run` again, do not reopen | |
| 11 | Snooze re-rings 9 minutes later | |
| 12 | Two alarms one minute apart both ring | |
| 13 | Timezone change re-arms correctly | |
| 14 | **Overnight, offline, in a drawer, from 23:00 to 06:40** | |

Test 14 is the milestone. The rest are the ways it fails.

Test 9 is the one that will fail first, and Autostart is why.

## What "done" looks like

Test 14 passes three nights running. At that point the riskiest assumption in the
whole project is retired, and Milestone 2 (accounts and pairing) can start.

If tests 6, 7, 9 or 14 keep failing after the OEM settings are correct, stop and
say so — that is a finding about the platform, not a bug to grind on, and it
changes the product.
