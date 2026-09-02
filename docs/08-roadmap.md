# 08 — Roadmap

Build order is chosen so the **riskiest thing gets proven first**. The risk in this
project is not the UI or the backend; it is whether a shared alarm reliably rings
on two phones. Prove that before building anything pretty.

## Where things actually stand (2026-09-02)

**Done**

- **Milestone 0 — mostly.** The alarm engine works: exact scheduling, foreground
  service, lock-screen ringing, direct-boot survival, snooze with a real
  allowance, notification actions, self-perpetuating repeats, timezone
  recomputation. Six of fourteen device tests pass (1, 2, 3, 9, 10, 11).
- **Milestone 2 — backend built and verified.** Postgres schema, RLS tested
  against a simulated attacker, pairing RPCs, account deletion. Flutter sign-in
  and pairing screens exist but are **gated off** behind `DUET_BACKEND`.
- **Milestone 3 — the local half.** The app is genuinely usable standalone:
  alarm list, editor, device-sound picker, alarm-health screen.
- Twelve-artboard design canvas; private GitHub repo.

**Blocked on the outside world**

- Supabase email template needs `{{ .Token }}`, and custom SMTP before any
  real testers (supabase/README.md). Until then the backend stays gated off.
- Play Console identity verification (address needs correcting), then the
  12-tester / 14-day closed-test clock (docs/12 §1.3).

**Not started**

- Shared alarms over the network, the multiplayer ring session, the
  "for both of us" controls, wake receipts, themes, missions, monetisation,
  store listing.
- **The app still ships Flutter's default launcher icon.** Small job, but it is
  the first thing anyone sees.
- No settings screen in the standalone app (the `allow_partner_dismiss` toggle
  and profile live only in the gated-off pairing build).

**The single most important outstanding item is Milestone 0 test 14** —
overnight, offline, in a drawer. Everything else is building on an assumption
that has not yet been proven for a full night.

## Milestone 0 — Prove the alarm (Android only)

**Goal:** a phone in a drawer, offline, overnight, rings at 07:00.

- Flutter shell, one hardcoded alarm
- Native Kotlin engine: `setAlarmClock`, foreground service, full-screen intent
- Ringing screen with Snooze / Dismiss
- Boot receiver + re-arm
- Overnight soak tests, including on a Xiaomi/Samsung device

No backend. No accounts. No design. **If this milestone fails, the project is
different than you think — find out in week one, not month three.**

## Milestone 1 — Prove the alarm (iOS)

**Goal:** the same, on the iPhone you bought.

- Codemagic pipeline green, build on TestFlight, installed on your device
- Swift AlarmKit engine behind the same channel interface
- Runs every test in doc 04: silent switch, Sleep Focus, Low Power, reboot

This is your highest-uncertainty milestone. Timebox it, and if AlarmKit does not
deliver what doc 04 assumes, **stop and revisit doc 09's iOS decision before
writing more code.**

## Milestone 2 — Accounts and pairing

- Supabase project, schema, RLS from doc 03
- Sign in with Apple / Google / email OTP
- Invite code generation and redemption, QR shortcut
- Pair status visible on Home
- **Account deletion** (build it now — it is a store requirement and it is much
  harder to retrofit)

## Milestone 3 — Shared alarms

- Alarm CRUD synced to Postgres
- The reconciliation loop (doc 02) — arm/disarm from remote definitions
- Silent push on change, plus foreground/boot/periodic reconciliation
- Per-listener sounds (the "pick what they wake up to" feature)
- Timezone modes, with the full DST test matrix

At the end of M3 you have the product's actual premise working. Everything after
is refinement.

## Milestone 4 — The multiplayer ring session

- Deterministic session IDs, idempotent upsert from both phones
- Snooze/dismiss for self and for both
- `allow_partner_dismiss` enforcement server-side
- Live awareness strip ("Sam snoozed — 4:51 left")
- Realtime channel + push fallback, with graceful degradation to a solo alarm

## Milestone 5 — Make it good

- Real visual design pass
- Onboarding with permission priming
- **Permission Health Check screen** — treat as a headline feature, not polish
- Missions (math, shake)
- Wake receipts and streaks
- Sentry + PostHog, with missed-alarm telemetry wired up

## Milestone 6 — Money

- RevenueCat integration, StoreKit 2 + Play Billing
- Paywall (placed per doc 05)
- Pair-wide entitlement via webhook → `pair.plan`
- Voice recording feature (paid hook), Supabase Storage
- Restore purchases, subscription management links

## Milestone 7 — Ship

- Play closed test with 12 testers (start this clock during M5, not M7)
- TestFlight external beta
- Store listings, screenshots, privacy policy, ToS
- Submit, get rejected, fix, resubmit
- Phased rollout on both stores

## Post-launch backlog

- Gift a subscription to your partner
- Groups larger than two (validate the snooze semantics first)
- Widgets and Live Activities / persistent notification
- Wear OS + Apple Watch
- Photo-scan mission (get out of bed and scan the bathroom)
- Long-distance features: "good morning where you are" timezone UI
- Localization — start with the languages your early analytics show

## What to cut if you're running out of energy

In order, cut: themes, photo mission, wake receipts, live-awareness strip, missions
entirely. Do **not** cut: the permission health screen, the reconciliation loop,
account deletion, or any item on the doc 04 test plan. Those are what separate a
working alarm clock from a refund request.
