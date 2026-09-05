# 14 — Handoff

For whoever picks this up next. Docs 01–13 explain what the product is and why;
this one is about working on it without breaking it or relearning what already
cost a day to find out.

Read **02-architecture.md** and **09-decisions.md** before writing code. The rest
of the docs are reference; those two are binding.

---

## The one rule everything else bends around

**An alarm rings from a local `AlarmManager` entry, and nothing about ringing may
depend on the network** (ADR-001). The server carries alarm *definitions* and
*state about a ring in progress*. It never triggers a ring. If a change would
make an alarm's firing conditional on connectivity, sync, auth, or another
device, the change is wrong regardless of how convenient it is.

Corollary that shapes a lot of the code: anything the alarm path needs at fire
time must already be on the device before the alarm fires. That is why so much
gets pushed down into native storage ahead of time rather than fetched.

---

## Two runtimes, one app

| | Flutter (Dart) | Native (Kotlin) |
|---|---|---|
| Owns | all UI except the ringing screen; deciding *what* should be armed | talking to `AlarmManager`; the ringing screen; anything at fire time |
| Entry | `app/lib/` | `app/android/app/src/main/kotlin/com/duet/alarm/` |
| Bridge | `alarm_engine.dart` | `MainActivity.kt` (`com.duet.alarm/engine` channel) |

**The ringing screen (`RingingActivity.kt`) has no Flutter engine.** This is
deliberate (docs/12 §3.2): cold-starting Flutter from a locked screen at 06:00
adds latency and a failure class you cannot debug from bed. The consequence is
constant and easy to forget:

> The ringing screen cannot call Dart, cannot read Dart state, and cannot use
> any Dart package — including the Supabase client. Anything it needs must be
> written to native storage in advance.

`AuthStore.kt` is that storage: access token, user id, pair id, LAN secret,
`allow_partner_dismiss`, and the two skin colors. Dart pushes each of these via
the channel whenever they change (`main.dart`'s `PairGate._reload`,
`settings_screen.dart`'s `_setAccent`). If you add something the ringing screen
needs, it goes through the same path — there is no shortcut.

`AlarmStore.kt` holds the armed alarms themselves, in **device-protected
storage**, so a phone that reboots at 03:00 can re-arm before first unlock.
Never move alarm state to normal storage; that bug already happened once and
the alarm silently did not ring.

### Reconciliation

`alarm_repository.dart`'s `reconcile()` is the single place that decides what
the OS should be holding. It diffs desired fire instants against what the device
actually has armed, and it **re-arms every desired entry unconditionally**. Do
not reintroduce a "skip if already armed" optimisation: the id alone does not
capture the definition, so a field-only change (a new `pairId`, a changed sound)
would never reach native. That exact bug shipped and took a while to find.

---

## Data model, briefly

Full detail in **03-data-model.md**. What trips people up:

- **`alarms`** is the shared row — one per alarm, visible to both pair members
  through RLS.
- **`alarm_sounds`** is the *per-listener* table, keyed `(alarm_id, listener_id)`.
  It holds what **you** hear (`sound_ref`) and whether **you** have it switched
  on (`enabled`, migration 0010). "You pick what they wake up to" lives here.
- `alarms.enabled` still exists and is still written. It is the fallback for
  rows with no per-listener entry. Read `enabled` from the per-listener row when
  present, and fall back — `alarm_sync.dart` shows the pattern.
- **RLS is the entire authorization model.** There is no trusted app server. The
  publishable key in `supabase_config.dart` is *meant* to be public; every row it
  can reach is guarded by policy. `service_role` must never enter this repo.
- Migrations are append-only and numbered. `supabase/tests/rls_test.sql` verifies
  policy against a simulated attacker and rolls back — run it after touching
  policy, and keep its "half-empty pair" case, which catches a missing policy the
  pair-size trigger would otherwise mask.

---

## The environment

Everything needs `source tool/env.sh` first — the system Java is a JRE with no
compiler, so Gradle needs the pinned JDK.

```bash
source tool/env.sh
cd app
flutter test                                            # unit tests
flutter analyze lib/
./tool/install.sh debug --dart-define=DUET_BACKEND=true  # build + install + launch
```

### Four device gotchas that will cost you an hour each

1. **`--dart-define=DUET_BACKEND=true` matters.** Without it you get the
   standalone build: no sign-in, no pairing, no sync, and a `Settings` icon that
   does not appear. Building without the flag and then installing is an easy way
   to spend twenty minutes debugging a feature that was never compiled in.
2. **`adb install` does not work on this HyperOS phone.** It fails
   `INSTALL_FAILED_USER_RESTRICTED` even with every developer toggle on. Push to
   `/data/local/tmp` and `pm install -r -t` on the device instead —
   `tool/install.sh` already does this. `/sdcard` does not work (SELinux).
3. **Do not mix release and debug builds on one device.** Release APKs built with
   `--split-per-abi` get versionCode 2001+, so a later debug build (versionCode 1)
   is rejected as a downgrade, and the only fix is an uninstall — which wipes the
   Supabase session and forces a fresh email OTP sign-in. Stay on debug while
   iterating.
4. **Screenshot coordinates are scaled.** The device is 1080×2400; screenshots
   are usually rendered at 900 wide, so multiply by 1.2 before `input tap`. Also,
   `uiautomator dump` goes stale the moment layout shifts (the rotating tip
   banner changes height between two and three lines and moves every row below
   it). Dump and tap in the *same* on-device shell invocation, or read
   coordinates off a screenshot you just took.

---

## What is actually verified, and what is not

This matters more than usual here, because a lot was built in long sessions and
the honest frontier is not obvious from the code.

**Verified on real hardware:**

- Alarm fires on time (observed 12-326 ms late across runs), survives reboot,
  and rings before first unlock (direct boot). Snooze and dismiss both work from
  the full-screen screen and from the notification; repeating alarms re-arm
  themselves. Six of the fourteen device tests in docs/13 pass (1, 2, 3, 9, 10,
  11).
- Two real phones, two real accounts, real invite-code pairing.
- Alarm definitions round-trip to Postgres with correct field mapping.
- A ring session appears in `ring_sessions` the instant an alarm fires, and
  `ring_participants.state` flips to `dismissed` on dismiss.
- Skins: picking one repaints the app live, including the native ringing screen.

**Built but NOT verified end to end:**

- **The LAN fast path (`LanSync.kt`).** Never run with two phones on one network.
  Its signing, replay window, and self-echo rejection are untested against a real
  peer. Assume it is broken until proven otherwise; it is designed to fail
  silently, so it will *look* fine either way.
- **"Dismiss for both" across devices.** The single-device path runs without
  crashing; the RPC has never actually stopped a second phone's alarm.
- **The partner awareness strip** ("They snoozed") during a real shared ring.
- **Timezone recomputation** (`AlarmScheduler.rezone()`) on a real timezone
  change — `adb` cannot send the protected `TIMEZONE_CHANGED` broadcast, so this
  needs a manual Settings change.
- **Milestone 0 test 14 — overnight, offline, phone in a drawer.** Still the
  single most important outstanding item. Everything else rests on an assumption
  that has never been held for a full night.

---

## The bug pattern that keeps recurring

Four separate bugs this project has already shipped and fixed share one shape:
**state that is correct locally but never reaches where it is consumed.**

- `reconcile()` skipped re-arming, so a stamped `pairId` never reached native.
- `alarm_sync`'s pair-stamp updated the merged map but not the push queue, so the
  server received the stale unstamped copy.
- `redeem_pair_invite` was blocked because opening the invite screen silently
  enrolled the redeemer in their own solo pair first.
- `SkinColors.setSkins(partner: null)` meant "reset to default" where the caller
  meant "leave alone", wiping the partner's color.

When something looks right in the UI, that is not evidence it reached the
database or the native side. Check the destination — `execute_sql` against
Postgres, or `adb shell run-as com.duet.alarm cat
/data/user_de/0/com.duet.alarm/shared_prefs/duet_alarm_store.xml` for what the
device actually holds. Note `/data/user_de/`, not `/data/data/` — alarm state is
in device-protected storage, and reading the wrong path once made a working
build look broken.

---

## Conventions

- **Comments explain why, not what.** The codebase leans heavily on this; several
  comments encode a bug that already happened. Do not strip them.
- **09-decisions.md is an append-only ADR log.** Add to it when you make a
  decision someone could reasonably reverse later; do not rewrite old entries.
- **Failures are surfaced, never swallowed silently.** A failed sync sets a flag
  the UI shows ("Not synced"); a missed alarm is recorded to `MissedLog` and
  displayed. An alarm clock that fails quietly is the worst outcome in this
  product — see the alarm-health screen (`diagnostics_screen.dart`), which is a
  shipping feature, not a debug tool.
- **Never commit personal files.** ID photos were once committed and had to be
  purged from history; `.gitignore` now covers `ID docs/` and loose image types.

---

## Where to pick up

Priority order, with the reasoning:

1. **Milestone 0 test 14** (overnight, offline, in a drawer). The bar docs/13
   sets is three consecutive nights. Blocks trusting everything else.
2. **Verify the LAN path with two phones on one wifi.** It is a whole subsystem
   with zero real-world evidence, and it fails silently by design.
3. **Realtime instead of polling** for ring state. The Flutter side can use
   Supabase realtime directly; the ringing screen cannot (no Flutter engine),
   which is why the LAN path exists at all.
4. **Per-skin motion on the ringing screen.** Skins currently change its colors
   but not its animation.
5. Wake receipts, missions, monetisation, store listing — all untouched, see
   **08-roadmap.md**.

Blocked on the human, not on code: Play Console identity verification, and the
12-tester / 14-day closed-test clock (docs/12 §1.3).
