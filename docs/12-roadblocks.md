# 12 — Roadblocks

Ordered by **when they bite**, not by severity. The bureaucratic ones at the top
have lead times measured in weeks and do not care how fast you write code — start
them in parallel with Milestone 0.

Each entry: what it is, why it hurts, what to do **now**.

---

## Tier 1 — Long lead time. Start these before you write code.

### 1.1 Play Console identity verification

Google requires government ID and a verified address before your account is usable,
and this can take days to weeks. It gates everything else, including the 14-day
tester clock.

**Prepare now:** have a passport/ID scan and a proof-of-address document ready.
Use your real legal name and a permanent address — mismatches trigger manual review
and add weeks.

### 1.2 You need a payment method and, eventually, a bank account

The $25 fee requires a **card**. If you don't have one, that is a hard blocker to
solve early, not at submission time. Separately, to ever *receive* subscription
money you need a Google payments profile with a **bank account and tax information**
(and possibly a tax residency form).

**Prepare now:** confirm you have, or can get, a card that works with Google. Check
what tax registration your country requires for app income — some require you to
register as a sole trader before earning. Find this out before you have revenue,
not after.

### 1.3 Recruiting 12 testers who stay opted in for 14 days

This is the roadblock people underestimate most. Not the two-week clock — the
**twelve real humans** who must install and stay opted in continuously. With no
existing audience this is genuinely hard.

**Prepare now:** start a list today. For a couples app, six couples is the ideal
cohort and gives you real multiplayer feedback. Sources: friends and family,
`r/AndroidApps`, `r/TestMyApp`, `r/betatests`, Discord servers, tester-swap
communities where devs test each other's apps. Ask people *before* you need them.
Getting a "yes" is easier than getting an install two months later.

### 1.4 The app name

Affects your domain, your ASO, your store listing, and your trademark exposure.
Changing it after launch destroys the little ranking you have.

**Prepare now:** search both stores, check EUIPO/USPTO, check the `.com`. Pick
something short, coined, and suggestive of two people. See doc 07.

---

## Tier 2 — Will block your Play submission if unprepared

### 2.1 ⚠️ The positioning-versus-permissions tension

**This is the sharpest non-obvious risk in the project.**

Your alarm needs `USE_EXACT_ALARM` and `USE_FULL_SCREEN_INTENT`. Google grants both
only to apps whose **core function** is an alarm clock, calendar, or calling app —
and they audit this against your actual store listing.

But ADR-011 says to position the app as a *couples* app, because that's where the
differentiation and the paying audience are.

If your listing reads as a relationship/lifestyle app, a reviewer can reasonably
conclude that alarms are not your core function and **strip the permissions your
product depends on.**

**Resolution — decide this now, not at submission:** the app title and the first
line of the description must state plainly that it is an alarm clock. Lead with the
category, differentiate with the audience:

> **"Duet — Shared Alarm Clock for Couples"**

Alarm-clock first in the title, couples-first in the screenshots and the emotional
copy below the fold. This satisfies the reviewer and the customer simultaneously.
Write your permission declarations in the same language: *"The app's core function
is a shared alarm clock; exact alarms are required for it to ring at the set time."*

### 2.2 Full-screen intent restrictions (Android 14+)

`USE_FULL_SCREEN_INTENT` is no longer granted freely. Alarm and calling apps are
supposed to get it by default; everything else must send the user to a system
settings screen via `ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT`.

**Prepare now:** never assume you have it. At runtime, check
`NotificationManager.canUseFullScreenIntent()`, and if it's false, degrade to a
high-importance heads-up notification with a loud sound **and** surface it in the
Permission Health Check screen. Build the degraded path from day one — retrofitting
it after a rejection is miserable.

### 2.3 Permission declaration forms

Each of these needs a written justification on the Play Console form, and a
mismatch with your listing gets you rejected:
`USE_EXACT_ALARM`, `USE_FULL_SCREEN_INTENT`,
`REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`, `RECORD_AUDIO` (voice sounds),
`POST_NOTIFICATIONS`, foreground service type `mediaPlayback`.

**Prepare now:** write the one-sentence justification for each **as you add the
permission**, into a file in the repo. Do not reconstruct them under submission
pressure.

### 2.4 Account deletion — in-app *and* a public web URL

Both are required. The web URL is easy to forget and it must be reachable without
installing the app.

**Prepare now:** GitHub Pages page, free, alongside your privacy policy. Build the
in-app path in Milestone 2 as doc 08 says — retrofitting deletion through a schema
with pairs and cascades is genuinely unpleasant.

### 2.5 Data Safety form must match reality

You declare every data type you collect. If it contradicts your privacy policy or
your actual network traffic, you're rejected.

**Prepare now:** keep a running list in the repo of every field you collect and
why, updated as you build. Yours will include: email, display name, timezone,
alarm data, device push token, voice recordings, crash and analytics data.

---

## Tier 3 — Technical walls you can pre-empt

### 3.1 Your Redmi will kill the alarm, and it is the normal case

HyperOS autostart is off by default. Without it, **no alarm survives a reboot.**
Also: battery restrictions, "show on lock screen" / background pop-up permission
(required for the ringing screen to actually appear), and locking the app in
Recents.

**Prepare now:** read `dontkillmyapp.com`'s Xiaomi page before writing the engine.
Treat the Permission Health Check screen as a Milestone 0 deliverable rather than
Milestone 5 polish — you'll need it to make your own testing sane.

### 3.2 Don't launch Flutter from the full-screen intent

Cold-starting the Flutter engine from a locked screen at 06:00 adds latency and a
class of failure you cannot debug from bed. The one screen that absolutely must
work is the one most at risk.

**Prepare now:** write the **ringing screen as a pure native Activity** (Kotlin +
Compose), with no Flutter dependency. It reads the alarm from local storage,
plays audio, and shows two buttons. Everything else in the app stays Flutter. This
also means the ringing path keeps working if the Flutter side crashes.

### 3.3 FCM will not wake a Doze'd or Xiaomi'd phone reliably

Data messages get throttled; Xiaomi throttles them harder than most. This is
already handled by ADR-001 (push never triggers a ring), but it *does* affect
"dismiss for both" latency and alarm-change propagation.

**Prepare now:** use high-priority messages for ring-session actions, and make
every sync path idempotent and reconcilable, so a dropped push is invisible rather
than incorrect.

### 3.4 Supabase free tier pauses after ~a week of inactivity

Harmless while you develop daily. Dangerous the week your beta testers are the only
users and you take a holiday.

**Prepare now:** a free uptime pinger (UptimeRobot free tier) hitting a health
endpoint keeps it warm and tells you when it's down.

### 3.5 Google Sign-In SHA-1 fingerprints

Each build variant (debug, release, **and Play App Signing's re-signed key**) has a
different fingerprint and each must be registered. Symptom is a silent sign-in
failure that only appears in the Play build — a classic day-waster.

**Prepare now:** register debug, release, and the Play App Signing SHA-1 as soon as
you first upload. Consider email OTP as the primary auth method to sidestep this
entirely early on.

### 3.6 DST and timezone bugs surface twice a year

Your test matrix (doc 04) covers them, but they're invisible in normal use and
brutal when they hit.

**Prepare now:** make the alarm scheduler a pure function — `(alarm, now, tz) →
next fire instant` — with no Android dependencies, so the whole matrix is covered
by fast unit tests on Linux, no device needed.

### 3.7 Alarm sound licensing

Freesound and similar have a mix of licences, some non-commercial, some requiring
attribution.

**Prepare now:** record the licence and source URL for every asset in a
`ASSETS.md` file **as you add it**. Retroactively auditing sound files is
horrible, and shipping a non-commercial sound in a paid app is a real legal issue.

---

## Tier 4 — The ones that actually kill projects

### 4.1 Scope creep into a rewrite

Every feature that touches the native engine costs 5× what it looks like.

**Prepare now:** the engine interface in doc 02 is fixed. Anything that wants to
change it goes to the decision log first.

### 4.2 Solo-developer attrition

Three to six months of evenings is the real price. Most projects at this scale die
around month two, when the novelty is gone and the store paperwork starts.

**Prepare now:** ship Milestone 0 within two weeks and **use the app yourself
every single morning from that point on**. A tool you personally depend on is far
harder to abandon than one you're building on faith. Get the second device into a
real person's hands early for the same reason.

### 4.3 Building for months before validating

The most expensive mistake available to you, and it costs nothing to avoid.

**Prepare now:** run the free landing-page test in doc 11 **this week**, before
Milestone 0.
