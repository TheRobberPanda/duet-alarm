# 10 — The Zero-Budget Path

> Supersedes the cost assumptions in doc 06 and the launch sequence in doc 07 for
> as long as the budget is €0. Doc 06 remains the reference for *when* money exists.

## The headline

**Everything can be built and tested for €0. Android-only.**
The only unavoidable cost to reach the Play Store is the **$25 one-time** Google
registration fee — and you don't pay it until you have something worth publishing.

iOS is deferred entirely. It costs $99/year plus a device, and it is the half of
the project you cannot debug anyway. Doc 02's architecture already keeps the
platform-specific surface tiny, so adding iOS later is bounded work, not a rewrite.

## Free stack

| Need | Free option | Limit that matters |
|---|---|---|
| Dev machine | Your Linux box | — |
| Framework | Flutter + Android SDK | — |
| IDE | Android Studio / VS Code | — |
| **Test device** | **Your Redmi Note 14 5G** | The best-case worst-case device. See below. |
| Second test device | Android emulator, or a friend's phone | Emulator can't test OEM killers — fine for the *other* side of a pair |
| Backend | Supabase free tier | ~500MB DB, ~50k monthly active auth users, ~1GB storage. Free projects pause after ~a week of inactivity — irrelevant while you're developing daily. |
| Push | Firebase Cloud Messaging | Free, effectively unlimited |
| Crash reporting | Sentry free tier or Firebase Crashlytics | Crashlytics is unlimited and free |
| Analytics | PostHog free tier | ~1M events/month — far beyond your needs |
| Payments | RevenueCat | Free under ~$2.5k/month revenue |
| Privacy policy / ToS | Free generators | — |
| Hosting for those pages | GitHub Pages | Free, and gives you the public URL both stores require |
| CI | Not needed | Build Android locally with `flutter build apk` |
| Source control | GitHub free private repo | — |
| Design assets | Figma free tier, Google Fonts, Lucide/Phosphor icons | — |
| Sound assets | Freesound (check licences), or record your own | Verify every licence permits commercial use |

Total: **€0** to a fully working, installed, daily-driven app.

## Your Redmi is an asset, not a limitation

Xiaomi HyperOS/MIUI is the most aggressive battery manager in wide circulation. Most
alarm-app developers build on a Pixel, ship, and then discover their alarm silently
dies on a third of their users' phones.

You get to discover that on day one, on your own device, for free.

Specifically, test and handle on this phone:
- **Autostart** — MIUI blocks apps from starting on boot unless explicitly allowed.
  Your alarm will not survive a reboot until the user enables this.
- **Battery saver → No restrictions** for your app
- **Lock the app in Recents** (the padlock on the task card) — MIUI's own guidance
- **"Show on Lock screen" / "Display pop-up windows while running in background"** —
  required for your full-screen intent to actually show the ringing screen
- **MIUI Optimization** in developer options changes behavior — test both ways

Every one of those becomes a step in the Permission Health Check screen (doc 01),
with a MIUI-specific deep link. Building that screen against the hardest device
first means it will be easy for everyone else.

`dontkillmyapp.com` documents the exact intents per manufacturer. This is the most
valuable free resource in the project.

## Getting a second device for pair testing, for free

You need two phones to test the multiplayer layer properly. Options, cheapest first:

1. **Android emulator as the partner.** It can run the app, sign in, edit alarms,
   and receive push. It cannot meaningfully test *ringing* under Doze — but you
   only need one real device ringing to validate that. Good enough for 90% of dev.
2. **An old phone in a drawer** — yours or a family member's. Even a 6-year-old
   Android running API 26+ works.
3. **A friend or partner's phone** for real-world overnight tests. You need this
   eventually regardless; a couples app must be tested by an actual couple.

## Publishing for €0 (before you can afford the $25)

You do not need Google Play to get real users and real feedback:

| Route | Cost | Notes |
|---|---|---|
| **Direct APK** via GitHub Releases | Free | Perfect for your first testers. Users must allow "install unknown apps." |
| **Amazon Appstore** | **Free developer account** | Genuinely zero-cost real store distribution. Small audience, but real. |
| **Samsung Galaxy Store** | **Free developer account** | Preinstalled on every Samsung — a large audience for €0. |
| **Huawei AppGallery** | Free | No Google services, so FCM won't work — significant porting work. Skip for now. |
| **F-Droid** | Free | Requires open-sourcing the app. A real strategic choice, not a casual one. |
| **itch.io** | Free | Unusual for apps but works for distributing an APK with a landing page. |

**Suggested sequence:** GitHub Releases APK → recruit testers → prove people want it
→ then spend the $25 on Play. If you can't get 20 people to install a free APK, the
$25 wasn't the bottleneck.

Note that Samsung and Amazon accounts also let you list a paid app, so there is a
theoretical path to earning your Play fee before paying it.

## What the €0 constraint actually costs you

Be clear-eyed:

- **No iOS.** Roughly half the revenue in this category, and the half that pays
  more per user. You are deferring, not abandoning.
- **No paid user acquisition.** You are entirely dependent on organic growth — which
  for this app is genuinely plausible, since every user must recruit a partner to
  use it at all. See the market notes below.
- **Slower feedback.** No paid testing services, no device farms.
- **Your time is the investment.** Milestones 0 and 2–6 in doc 08 are perhaps
  3–6 months of solid evening work for one person. That is the real price tag.

## Revised launch sequence (zero-budget)

1. Milestone 0 — alarm rings reliably on the Redmi (free)
2. Milestones 2–4 — accounts, shared alarms, ring sessions on Supabase free tier (free)
3. Distribute APK via GitHub to 10–20 testers (free)
4. If it has traction: pay the **$25**, start the Play 12-tester/14-day clock
5. Launch Android-only, free tier + subscription via RevenueCat
6. **Only once there is revenue:** buy a used iPhone + the $99 Apple membership,
   and execute doc 06

Skip Milestone 1 (iOS) entirely for now. Keep the native engine interface from
doc 02 intact so that when the money exists, iOS is an addition rather than a rewrite.
