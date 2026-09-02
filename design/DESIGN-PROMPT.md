# Prompt for Claude Design

Paste everything below the line into Claude Design (or run `/design` in Claude Code
with this as the brief).

---

Design a mobile app called **Duet — Shared Alarm Clock for Couples**. Android
first, Material 3, but don't let it look like stock Material.

**The product:** two people link their phones into a pair. Alarms are shared. When
one goes off, *both* phones ring. Either person can snooze or dismiss — for
themselves, or for both. Each person chooses the sound the *other* one wakes up to.

**Design direction:** this is an intimate object, not a productivity tool. It lives
on a bedside table and is seen by a half-asleep person in a dark room. Warm, soft,
calm — closer to a sleep app than a utility. Dark theme is the primary design; a
light theme exists but is secondary. Avoid the generic purple-gradient SaaS look,
avoid hard pure-white-on-pure-black, avoid clinical.

**The one visual idea that should run through everything:** there are two people.
Each person has their own accent colour, assigned at pairing (e.g. a warm amber and
a cool teal). Every shared element shows both — a two-tone ring, paired avatars, a
split indicator. A user should be able to glance at any screen and instantly tell
which parts are "me" and which are "them". Make this the signature, not a
decoration.

**Typography:** one humanist sans for UI. Time displays are the hero element —
large, light weight, generously tracked, tabular figures. The clock should feel
serene, not digital-alarm-clock aggressive.

Design these artboards, iPhone/Android phone size, in this order:

1. **Onboarding — value prop.** One screen selling the premise. Two phones, both
   ringing. The one-liner: "An alarm you share. Both phones ring. Either of you can
   turn it off."

2. **Pair setup.** A 6-character invite code, big and legible, with a QR option and
   a "enter partner's code" path. This flow is the app's entire growth engine —
   make it feel like an invitation, not a form.

3. **Home.** List of shared alarms. Next alarm to fire is prominent at the top with
   a countdown. A partner status strip along the top: partner's avatar, their local
   time (they may be in another timezone), and whether their next alarm matches
   yours. Each alarm row shows the two-tone "both ring" indicator, its label, and a
   toggle.

4. **Alarm editor.** Time picker, repeat days, label. Then the distinctive part:
   **two sound rows side by side** — "You'll hear ___" and "They'll hear ___" — making
   it obvious that you're choosing your partner's wake-up sound. Plus snooze policy
   and a "who rings" selector (both / just me / just them).

5. **Sound picker.** Built-in sounds list with waveform previews, device tones, and
   a locked premium row: **"Record your voice"** — with a mic affordance. Show the
   locked/premium state clearly but without being obnoxious.

6. **Ringing screen — the most important artboard.** Full-screen, dark, gentle.
   Large time, alarm label. Two primary actions — **Snooze** and **Dismiss** — which
   act on *you only*. Below them, visually secondary and clearly more deliberate,
   the "…for both of us" variants. Getting this hierarchy right matters: dismissing
   your partner's alarm by accident is the worst thing this app can do.

7. **Ringing screen — live awareness state.** Same screen, but showing what the
   partner is doing right now: "Sam snoozed — 4:51 left" with a soft countdown, or
   "Alex is still ringing" with a pulsing indicator. This is the moment the app
   feels multiplayer — make it feel warm and alive, not like a status log.

8. **Wake receipt.** Post-alarm summary: who woke first, snooze counts for each,
   a shared streak counter. Small, celebratory, quick to dismiss.

9. **Permission health check.** A diagnostic screen listing OS settings that could
   stop the alarm (autostart, battery optimisation, notifications, lock-screen
   display), each with a status and a one-tap fix button. Must feel reassuring and
   plain-language, not like a scary error list — this screen is what prevents
   missed alarms.

10. **Paywall.** Free vs. Duet Plus. Annual plan highlighted at ~$24.99/yr with a
    7-day trial, monthly at $4.99, lifetime at $59.99. Lead with the emotional
    feature: waking up to your partner's recorded voice. One subscription covers
    both people — say so explicitly, it's a selling point.

11. **Settings.** Profile, pair management (with a clear but non-scary unpair),
    the "let my partner dismiss my alarms" toggle, subscription status, and account
    deletion.

Show realistic content throughout — real names (Sam and Alex), real times, real
alarm labels like "Gym", "Your flight", "Wake Sam gently". No lorem ipsum, no
placeholder greys.
