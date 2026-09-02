# 04 — The Alarm Engine

This is the document that decides whether the app succeeds. Everything else is a
CRUD app with nice animations. **Verify every API claim here against current
platform docs before implementing** — this area changes with every OS release.

---

## Android

Android is the easy platform. It has a real alarm API and has had one for fifteen
years.

### Scheduling

```kotlin
val am = context.getSystemService(AlarmManager::class.java)
am.setAlarmClock(
    AlarmManager.AlarmClockInfo(triggerAtMillis, showIntent),
    firePendingIntent
)
```

Use `setAlarmClock()`, not `setExactAndAllowWhileIdle()`. `setAlarmClock` is the
API intended for user-facing alarm clocks: it is exempt from Doze, it shows the
next-alarm icon in the status bar, and it is the highest-priority scheduling class
available. `setExactAndAllowWhileIdle` is the fallback for non-alarm exact timing.

### The permission

Declare **`USE_EXACT_ALARM`** in the manifest:

```xml
<uses-permission android:name="android.permission.USE_EXACT_ALARM" />
```

This is granted at install with no user prompt — but Google Play restricts it to
apps whose *core function* is alarms/timers/calendar. An alarm clock qualifies.
You will declare this on the Play Console form; be ready to justify it in one
sentence.

Do **not** use `SCHEDULE_EXACT_ALARM` — it requires sending the user to a system
settings screen, and it can be revoked by the OS. Wrong tool for this app.

Also declare:
```xml
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" />
<uses-permission android:name="android.permission.WAKE_LOCK" />
<uses-permission android:name="android.permission.VIBRATE" />
<uses-permission android:name="android.permission.USE_FULL_SCREEN_INTENT" />
```

### When it fires

1. `BroadcastReceiver` wakes, immediately starts a **foreground service** (type
   `mediaPlayback`) — you have a very short window to do this, so do nothing else first.
2. Service acquires a partial wake lock, starts audio on the **alarm stream**
   (`AudioAttributes.USAGE_ALARM` — this ignores media volume and, critically,
   plays through Do Not Disturb), starts vibration.
3. Service posts a notification with a **full-screen intent** on a channel with
   `IMPORTANCE_HIGH` and `setBypassDnd(true)`. On a locked screen this launches
   the ringing Activity directly; if the phone is in use it shows as a heads-up.
4. Ringing Activity uses `setShowWhenLocked(true)` / `setTurnScreenOn(true)`.

### Surviving the device

| Threat | Mitigation |
|---|---|
| Reboot | `BOOT_COMPLETED` receiver → run reconciliation → re-arm everything |
| App updated | `MY_PACKAGE_REPLACED` receiver → same |
| Timezone change | `TIMEZONE_CHANGED` receiver → recompute and re-arm |
| Force-stopped by user | Nothing you can do. Alarms are cancelled. Detect on next launch and warn. |
| **OEM battery killers** | The real enemy. See below. |

### OEM battery optimization — the actual #1 support issue

Xiaomi, Huawei, Samsung, OnePlus, Oppo, and Vivo ship aggressive proprietary
task-killers that will murder your alarm regardless of what Android's docs
promise. This causes more one-star alarm-app reviews than every bug combined.

Mitigations, all of which you should ship:
- Request `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` during onboarding (allowed for
  alarm clocks; justify on the Play form).
- Detect the OEM and deep-link into that manufacturer's autostart/protected-apps
  screen with per-brand instructions. `dontkillmyapp.com` documents these intents.
- Ship the **Permission Health Check** screen (spec doc 01) and re-run it weekly,
  nagging if the app has been restricted.
- On every app open, compare "alarms that should have fired since last open"
  against actual fire records. If one was missed, show a loud explainer with a
  fix-it button. Turning a silent failure into a visible, fixable one is the
  difference between a churned user and a fixed one.

---

## iOS

iOS has historically had no third-party alarm API at all. Apps like Alarmy worked
around it with a chain of ~30-second local notifications and background audio —
fragile, and unable to override the silent switch without a special entitlement.

**iOS 26 introduced `AlarmKit`**, a first-party framework that gives third-party
apps genuine alarm-grade alerts: they break through silent mode and Focus, present
a full-screen alert on the Lock Screen, and offer system-provided snooze. This is
the reason doc 09 sets an iOS 26 minimum.

> ⚠️ Confirm the current AlarmKit API surface, capabilities, and any entitlement
> requirement in Apple's developer documentation before building. Treat everything
> in this section as a design sketch to be validated, not as a copy-paste spec.

### Shape of the integration

- Declare the alarm usage description in `Info.plist` (an `NSAlarmKitUsageDescription`-style key) and request authorization at onboarding.
- Schedule via AlarmKit with a schedule (fixed date or relative), a presentation
  (title, buttons), and your custom sound.
- Handle the user's snooze/dismiss through the framework's callbacks, then mirror
  that action into your Ring Session over the network.
- Alarms scheduled through AlarmKit are owned by the system, so they survive app
  termination and reboot — a large improvement over the old workarounds.

### Fallback layer (build it anyway)

Even on iOS 26, keep a belt-and-braces layer:
- A `UNNotificationRequest` scheduled for the same instant with
  `interruptionLevel = .critical` **if** you obtain the critical-alert entitlement,
  otherwise `.timeSensitive`.
- A custom sound file: **CAF/AIFF/WAV, ≤30 seconds**, bundled in the app. Longer
  files are silently rejected and you get the default tone. To ring longer than
  30s the classic trick is a chain of consecutive notifications — noisy and
  imperfect, hence AlarmKit.

### Critical alerts entitlement

If you want guaranteed silent-switch/DND override outside AlarmKit, you must
request the **Critical Alerts** entitlement from Apple with a written
justification. Alarm apps are a plausible case but approval is discretionary and
slow. Plan for it as an *enhancement*, never as a dependency. Apply early, ship
without it.

### Things that will bite you

- **Focus modes / Sleep Focus** — the very users who need your alarm most are the
  ones with Sleep Focus on. Verify behavior on a real device.
- **Low Power Mode** — throttles background work. Your reconciliation may not run;
  the OS-owned alarm should still fire. Verify.
- **Silent switch** — verify, with the switch physically flipped, on hardware.
- **Simulator is useless here.** It does not model DND, the ringer switch, Focus,
  lock-screen presentation, or real audio routing. See doc 06 — **you must buy a
  physical iPhone.**

---

## Shared engine contract

Both platforms implement the same channel interface (doc 02). Additional rules:

- **Arm a rolling 48-hour window**, not just the next occurrence. If the app never
  runs again, two days of alarms still fire. Android limits how many exact alarms
  you may hold; stay well under it.
- **Idempotent arming.** `arm()` with the same `(alarmId, fireAt)` twice is a no-op.
- **Report armed state honestly.** `armedAlarms()` must read actual OS state where
  possible, not a local mirror, or the health screen lies.
- **Never block the UI on the network** during a ring. Local silence first, sync second.

## Test plan (non-negotiable before launch)

Run each on **real hardware**, both platforms, phone locked, screen off:

1. Alarm fires with the phone in airplane mode
2. Alarm fires after 8 hours idle in a drawer (Doze / iOS deep sleep)
3. Alarm fires after a reboot with no app launch in between
4. Alarm fires with DND / Sleep Focus enabled
5. Alarm fires with iOS silent switch on
6. Alarm fires with Low Power / Battery Saver on
7. Partner edits alarm → your phone re-arms within 60s (and: with push blocked)
8. "Dismiss for both" silences the partner within 3s over WiFi and over LTE
9. "Dismiss for both" while partner is offline → their phone rings, then reconciles
10. DST spring-forward: an alarm set for a time that does not exist that day
11. DST fall-back: an alarm in the duplicated hour fires exactly once
12. Traveller: fly across timezones, `local` mode vs `absolute` mode both correct
13. Two alarms one minute apart, overlapping ring sessions
14. Both users snooze simultaneously (race on `ring_participants`)
15. Battery-killer OEMs: Xiaomi, Samsung, Huawei — overnight soak test

**Buy or borrow at least one Xiaomi/Samsung device.** Emulators will not reproduce
the failure mode that generates most of your bad reviews.
