# 07 — Store Launch

> Store policies change constantly. Verify every requirement here against the
> current App Store Review Guidelines and Google Play Developer Program Policy
> before submitting.

---

## Google Play — start here

Ship Android first. It is faster, cheaper, and has one delay you must start
*immediately*.

### Account setup

- **$25 one-time** registration fee.
- **Identity verification is mandatory** — government ID, address, phone. Do this
  on day one; it can take days.
- Personal vs. organization account: organization requires a **D-U-N-S number**.
  Personal is faster. Your developer name is publicly displayed either way.

### ⚠️ The 12-tester / 14-day rule — the thing that will delay your launch

Google requires new **personal** developer accounts to run a **closed test with at
least 12 testers who remain opted in continuously for 14 days** before you may
apply for production access. Then the production application itself is reviewed.

Practical impact: **your Android launch is gated by a two-week clock plus twelve
real humans.** Consequences:

1. Start recruiting those 12 testers *now* — friends, family, Discord, Reddit.
   For a couples app, six couples is a perfect closed-test cohort and gives you
   real multiplayer feedback.
2. Get a rough build into closed testing as early as it is stable enough, because
   the clock runs in parallel with your remaining development.
3. Organization accounts are reportedly not subject to the same requirement —
   another point in favor of getting a D-U-N-S number early.

Verify the current form of this rule in Play Console; the details have been
adjusted more than once.

### Play submission checklist

- [ ] App name, short description (80 chars), full description (4000 chars)
- [ ] App icon 512×512, feature graphic 1024×500
- [ ] Phone screenshots (min 2, aim for 6–8), plus 7" and 10" tablet sets
- [ ] Optional but valuable: a 30-second promo video
- [ ] **Privacy Policy URL** (required, publicly reachable)
- [ ] **Data Safety form** — declare every data type collected and why. Must match
      your actual behavior and your privacy policy, or you get rejected.
- [ ] Content rating questionnaire (IARC)
- [ ] Target audience & content — declare **not** targeted at children, to stay
      clear of the Families policy
- [ ] **Permission declarations** — justify `USE_EXACT_ALARM` (core alarm function),
      `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`, `USE_FULL_SCREEN_INTENT`, and
      `RECORD_AUDIO` (voice alarm sounds). Each needs a plain-language reason.
- [ ] Account deletion: an in-app path **and** a publicly reachable web URL
- [ ] Signed AAB, targeting the current required API level
- [ ] Subscriptions configured in Play Console, wired through RevenueCat

---

## Apple App Store

### Submission checklist

- [ ] App name (30 chars), subtitle (30 chars), promotional text, description
- [ ] Keywords field (100 chars, comma-separated, no spaces — this is real ASO;
      don't repeat words already in your title)
- [ ] Screenshots for required device sizes (6.9"/6.5" iPhone at minimum)
- [ ] App icon 1024×1024, no transparency, no rounded corners
- [ ] **Privacy Policy URL** and **Support URL** (both required, both must resolve)
- [ ] **App Privacy "nutrition label"** — every data type, linkage, and tracking use
- [ ] Age rating questionnaire
- [ ] **Sign in with Apple** — required if you offer Google or any third-party login
- [ ] **In-app account deletion** — required, and actively checked by reviewers
- [ ] Subscription products configured, with localized descriptions
- [ ] **Demo account credentials + a paired second account** in App Review notes —
      see below
- [ ] Export compliance (you use HTTPS only → standard exemption applies)
- [ ] Enroll in the **Small Business Program** (15% instead of 30% under $1M/yr)

### The reviewer note that gets you approved

Your app is useless to a reviewer with one account: it requires a partner and an
alarm that fires in the future. Spell it out in the App Review notes:

> This app pairs two accounts. Please sign in with **BOTH** demo accounts on two
> devices (or one after the other):
>   Account A: demo-a@example.com / <password>
>   Account B: demo-b@example.com / <password>
> These accounts are pre-paired. To see the core feature quickly, create an alarm
> for 2 minutes from now on Account A; it will ring on both accounts.
> [30-second demo video URL]

Attach a short screen recording. Reviewers approve what they can understand in
two minutes. This one note is worth more than any other single thing on this page.

### Rejection risks specific to this app

| Guideline | Risk | Mitigation |
|---|---|---|
| 4.2 Minimum Functionality | "It's just an alarm clock" | Lead with the pairing/multiplayer feature in screenshots and description |
| 2.1 App Completeness | Reviewer can't test pairing | The demo-account note above |
| 3.1.1 In-App Purchase | Any external payment path | RevenueCat + IAP only, no external links |
| 5.1.1(v) Account Deletion | Missing in-app deletion | Build it in the first sprint |
| 5.1.1 Data Minimization | Requiring data you don't need | Don't require phone numbers or contacts |
| 4.5.4 Push Notifications | Push required to use the app | Push is enhancement-only in your design — say so |
| Critical Alerts entitlement | Using it without approval | Don't ship it until Apple grants it |

### Timeline

- App Review: typically 24–48 hours, occasionally a week
- Expect **at least one rejection**. It is normal. Fix and resubmit; it is not a
  moral judgement.
- Use **phased release** for updates (Apple ramps 1%→100% over 7 days) so a bad
  alarm bug does not reach everyone overnight. For an alarm clock, this matters
  more than for most apps.

---

## Before either store: the name

"Duet" is a placeholder and is almost certainly taken. Before you build a brand:

1. Search both app stores for the name.
2. Search trademark registries (USPTO TESS, EUIPO eSearch) in your classes.
3. Check `.com` domain and social handles.
4. Avoid names that are simply "Alarm Clock" plus a word — impossible to rank for,
   and both stores frown on keyword-stuffed titles.

Aim for a short, coined, pronounceable name that suggests two people. Register the
domain before you announce it anywhere.

## Legal minimums

- **Privacy Policy** — required by both stores. Must accurately describe what you
  collect (email, display name, timezone, alarm data, device push token, voice
  recordings) and name your processors (Supabase, Sentry, RevenueCat, PostHog).
- **Terms of Service** — required if you have subscriptions.
- **GDPR** — you will have EU users on day one. Lawful basis, data export, deletion,
  and a named controller. Your Supabase region should be in the EU if you are.
- Generators are an acceptable starting point; have a lawyer review before you
  take real money at any scale.

## Launch sequence

1. **Week -6:** Play account + identity verification, Apple enrollment, D-U-N-S if wanted
2. **Week -4:** Android closed test opens with 12 testers (14-day clock starts)
3. **Week -3:** iOS TestFlight external beta
4. **Week -2:** Store listings, screenshots, privacy policy, legal pages
5. **Week -1:** Submit to both stores. Expect a rejection round.
6. **Week 0:** Release. Android phased rollout at 10%, iOS phased release on.
7. **Week 0+:** Watch crash-free rate and — most importantly — the **missed-alarm
   telemetry** from doc 04. That metric is your product's actual health.
