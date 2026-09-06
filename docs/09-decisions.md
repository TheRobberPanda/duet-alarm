# 09 — Decision Log

Append-only. When a decision changes, add a new entry that supersedes the old one
rather than editing history.

---

### ADR-001 — Both phones ring; alarms are scheduled locally on each device

**Status:** Accepted

**Context.** The product is a *shared* alarm, not a remote wake-up call. A design
where one phone triggers the other over the network fails whenever the network,
push, or server fails — at exactly the moment failure is least acceptable.

**Decision.** Alarm definitions sync ahead of time; each device schedules its own
OS-level alarm. The network is used only for syncing definitions and for
coordinating a ring session that is already in progress.

**Consequences.** The app works offline. Cross-device dismiss becomes best-effort
rather than guaranteed, which is the correct trade: the failure mode is "your
partner's phone keeps ringing," not "nobody's alarm went off." Requires a
reconciliation loop and 48-hour rolling arming.

---

### ADR-002 — Flutter shell with a native alarm engine

**Status:** Accepted

**Context.** One codebase is desirable for a solo developer, but no cross-platform
framework abstracts alarms correctly. Existing Flutter alarm plugins are thin and
unreliable at the edges that matter (Doze, OEM killers, iOS presentation).

**Decision.** Flutter for all UI, state, and sync. A deliberately tiny native
module (Kotlin + Swift) behind a fixed platform-channel interface for scheduling
and ringing.

**Alternatives.** Fully native ×2 — best reliability, roughly double the work, and
the iOS half is the half you can barely debug. React Native — same constraint,
weaker for a Linux-based dev machine. Flutter alarm plugin only — rejected as too
fragile for the core value proposition.

**Consequences.** ~90% of code is shared and testable on Linux/Android. The native
surface must stay small; resist pushing features into it.

---

### ADR-003 — iOS 26 minimum, using AlarmKit

**Status:** Accepted — **provisional, must be validated in Milestone 1**

**Context.** Before iOS 26 there was no third-party alarm API. Workarounds
(chained ≤30s notifications, background audio) are fragile and cannot override the
silent switch without Apple's discretionary Critical Alerts entitlement. iOS 26
introduced AlarmKit, giving third-party apps real alarm-grade alerts.

**Decision.** Require iOS 26+ and build on AlarmKit. Apply for the Critical Alerts
entitlement in parallel as an enhancement, never as a dependency.

**Consequences.** Excludes users on older iOS — acceptable, because an alarm that
might not ring is worse than no app. If Milestone 1 shows AlarmKit does not
deliver, this ADR must be revisited before further investment; the fallback is the
notification-chain approach plus a Critical Alerts application, at significantly
worse reliability.

---

### ADR-004 — Supabase over Firebase

**Status:** Accepted

**Context.** The data is relational (pairs, alarms, per-listener sounds, sessions)
and the authorization rules are row-scoped. Needed: auth, realtime, push fan-out,
file storage.

**Decision.** Supabase. Postgres with RLS as the security model, Realtime for ring
sessions, Edge Functions for push and webhooks, Storage for voice clips.

**Consequences.** RLS becomes safety-critical and must be tested like code. Push
requires wiring FCM/APNs yourself, which Firebase would have given free — a real
but bounded cost. EU data residency is straightforward.

---

### ADR-005 — Pairs are exactly two people

**Status:** Accepted

**Context.** "Multiplayer" invites N-person groups, but snooze/dismiss semantics
become incoherent past two, and the emotional story ("you and your partner")
weakens.

**Decision.** v1 supports pairs of exactly two. Groups are a post-launch experiment.

---

### ADR-006 — Self-action is the default; acting on your partner is deliberate

**Status:** Accepted

**Context.** The worst possible bug in this app is silencing someone else's alarm
by accident.

**Decision.** The primary Snooze and Dismiss buttons affect only the acting user.
"For both" variants require a deliberate secondary gesture. Each user has an
`allow_partner_dismiss` setting, enforced server-side, default on.

---

### ADR-007 — Freemium subscription, one purchase unlocks the whole pair

**Status:** Accepted

**Context.** Every user brings a second user. Charging both halves conversion and
sours a shared-ritual product.

**Decision.** Free tier: pairing + 2 alarms + basic sounds. Paid tier unlocks for
both members of the pair regardless of who paid. RevenueCat for entitlements.
No advertising, ever.

---

### ADR-008 — Android ships first

**Status:** Accepted

**Context.** Android has a mature alarm API, the developer can iterate in seconds
on local hardware, and registration is $25 versus $99/yr. iOS has a 10–25 minute
build loop and no local debugger for this developer.

**Decision.** Android first to Milestone 0, then iOS at Milestone 1 to de-risk
early, then parallel. Public launch on both, but Android's 12-tester/14-day clock
starts well before the iOS submission.

---

### ADR-009 — Last-write-wins conflict resolution

**Status:** Accepted

**Context.** Two people can edit the same alarm while one is offline. CRDTs or
operational transforms are wildly disproportionate for objects this small.

**Decision.** Last-write-wins by server `updated_at`, per alarm. Log every conflict
to analytics to learn whether the assumption holds.

**Consequences.** Rare lost edits are possible. Deletions are soft so tombstones
propagate and reliably disarm the other device.

---

### ADR-010 — Zero-budget, Android-only until there is revenue

**Status:** Accepted — supersedes ADR-008's parallel-launch assumption and defers ADR-003

**Context.** Available budget is €0. Apple's programme is $99/year plus a device
that must be bought; Google's is a $25 one-time fee. The developer owns a Xiaomi
Redmi Note 14 5G, which runs HyperOS — among the most aggressive alarm-killing
Android skins in circulation.

**Decision.** Build and ship Android only. Every service is used on its free tier
(Supabase, FCM, Crashlytics/Sentry, PostHog, RevenueCat, GitHub Pages). Milestone 1
(iOS) is removed from the near-term plan. The $25 Play fee is paid only once an
APK distributed via GitHub Releases has proven there is demand. iOS is revisited
only when the app generates revenue.

**Consequences.** Forfeits roughly half the category's revenue and its
higher-paying half, and all paid acquisition. In exchange the project costs €0 and
the developer iterates in seconds on real hardware. ADR-002's narrow native-engine
interface is what makes this deferral cheap — **it must be honoured even though
only one platform exists**, or adding iOS later becomes a rewrite. Development on
HyperOS is treated as an advantage: the hardest OEM case is the daily driver, so
the Permission Health Check screen is built against the worst device first.

---

### ADR-011 — Position as a couples app, not a general shared-alarm utility

**Status:** Accepted

**Context.** Galarm already occupies the general shared/group-alarm space with
meaningful adoption. Competing with it on breadth is unattractive for a solo
developer with no budget. Separately, the couples-app category (Paired, Between)
demonstrates established willingness to subscribe.

**Decision.** Target couples specifically. Narrow the audience, sharpen the
positioning, and prioritise features that only make sense for two intimate users:
per-listener sounds, voice recordings, live ring awareness, shared streaks. Reject
features whose value comes from group coordination.

**Consequences.** Caps the addressable market in exchange for much stronger
differentiation and conversion. ASO, screenshots, and copy all target couples
keywords rather than "alarm clock". Reinforces ADR-005 (pairs of exactly two).
Must be validated before Milestone 0 via the free landing-page test in doc 11.

---

### ADR-012 — One-time unlock instead of a subscription

**Status:** Accepted — **supersedes ADR-007**

**Context.** ADR-007 assumed a freemium subscription at $4.99/mo or $24.99/yr.
The objection raised against it is sound: people resist paying monthly, forever,
for an alarm clock. Alarmy sustains a subscription on brand and scale that a
first-time solo developer does not have. Because this app's growth is entirely
organic — no paid acquisition, per ADR-010 — store reviews are the marketing
budget, and subscription resentment is expressed in exactly that place.

The usual counter-argument, recurring infrastructure cost, does not apply at this
scale: Supabase's free tier and then $25/month covers thousands of pairs, and the
only genuinely metered resource is voice-clip storage, which is capped.

**Decision.** Free tier (pairing, 2 alarms, 4 sounds, 3 themes), then **Duet Full
at $9.99 one-time, unlocking for both members of the pair**. Cosmetic **theme
packs at $3.99 one-time** provide repeatable revenue. Both are non-consumable
products via RevenueCat. No subscription at launch. No advertising, ever.

**Consequences.** Conversion is expected to be roughly 2–3× a subscription's, and
the "one purchase, covers both of you, forever" framing is unusually strong for a
paired app. The cost is a materially lower ceiling: one-time revenue is earned per
cohort and scales with new installs rather than accumulating, so if growth stalls,
revenue approaches zero. Accepted deliberately — at this stage adoption and reviews
matter more than ceiling. Restore Purchases becomes safety-critical rather than a
formality, since a user who changes phones and loses the unlock will leave a
one-star review. The pair-wide entitlement is stored as `pair.plan` in the
project's own database, which keeps a future subscription tier possible without a
rewrite.

---

### ADR-013 — Themes are a paid cosmetic, and set both partners' colours

**Status:** Accepted

**Context.** Personalization is a reliable driver of cosmetic purchases, and the
app already has a two-colour visual system (ADR-006's companion, the per-partner
accent). A theme could have been a background swap; instead it can reinforce the
core idea.

**Decision.** A theme defines the **pair of accent colours** plus the background
tone. Each partner selects their own theme independently — it changes what they
see, not what their partner sees. Three themes are free; six ship in a $3.99 pack.

**Consequences.** Themes strengthen rather than dilute the two-tone signature.
Per-person application means a theme is a personal expression, which is what makes
it worth paying for. Marketing must present this as personalization for everyone —
gendering the feature in store copy would narrow the audience for no gain.

---

### ADR-014 — The UI identity is bundled: Hanken Grotesk, Instrument Serif, and the Plum Velvet component pass

**Status:** Accepted

**Context.** UI text previously rendered in whatever sans the device ships
(MiSans / Roboto / One UI Sans), so Duet looked like a different app on every
phone, and several screens still carried stock Material surfaces (the platform
time picker and AlertDialog, raw SnackBars, bare spinners) that broke the
deliberate plum world the moment they opened. The design canvases specify a
full visual language the shipped screens only half-used.

**Decision.** Bundle three typefaces with distinct jobs — Hanken Grotesk as
"Duet UI" for everything, Montserrat ExtraBold kept as the time-only display
face ("Duet Display"), Instrument Serif as the single celebratory voice (wake
receipt) — and finish the component pass: gradient-filled cards, halo glows
behind hero elements, dashed "not yet" arcs, glass pills, press-and-hold
destructive actions, skeletons instead of spinners, and bespoke dialogs and
snackbars. The ringing screen mirrors the same palette constants by hand
(they cannot read Dart state) and its typeface is loaded from flutter_assets
with a hard fallback to the system light sans.

**Consequences.** The app is ~440 KB of TTFs heavier and mobile_scanner pulls
ML Kit into the APK (see ADR-015). Palette changes now have two copies to
keep in sync — the mirrored constants in RingingActivity.kt are annotated with
the DuetColors token they shadow. Stock platform pickers/dialogs are gone, so
future Flutter theme changes apply everywhere at once.

---

### ADR-015 — QR pairing via qr_flutter + mobile_scanner

**Status:** Accepted

**Context.** Pairing is the growth engine (docs/11) and the canvases specify a
QR option; typing six characters across a table is friction the camera can
remove.

**Decision.** Render the invite code as a QR (qr_flutter, pure Dart) on the
invite card, and scan the partner's with mobile_scanner (which brings ML Kit
and camera permission with it). A scanned code feeds straight into the same
`redeem_pair_invite` path as typed entry, so all authorization stays server-side.

**Consequences.** mobile_scanner is the app's first heavyweight native
dependency; if it ever breaks a build, the documented fallback is QR display +
manual entry, which is the pre-2026-09 state and loses nothing but convenience.
The camera flow adds a permission prompt only on the scan path, not at install
or on the alarm path (ADR-001 is untouched: pairing was already network-bound).

---

### ADR-016 — Themes are whole worlds: palette, mascot, and native cosmetics

**Status:** Accepted

**Context.** Themes changed two accent colors; the app around them stayed plum.
The home dial had no personality, and after dismissing a shared ring the screen
simply vanished -- the one multiplayer moment with no multiplayer feeling in it.

**Decision.** Each theme now carries a full palette (background gradient,
surface tones, hairline) and a mascot glyph. Picking a theme re-dresses the
entire app -- backgrounds included -- and the home dial gains the mascot
standing faintly behind the ring, plus an interior half-fill (right quarter
yours, left quarter theirs, only when each of you has the alarm on). The
native ringing screen receives the theme's background and the partner's
display name via `AuthStore` (same push path as skin colors), and on DISMISS
-- never snooze -- shows a ~1.5s farewell: check-pop, floating hearts, and,
only when the partner poll supports it, "You woke up before {name}" /
"{name} beat you to it". Uncertain state says nothing rather than a wrong
name.

**Consequences.** Every `DuetColors.surface/bg` call site became
skin-palette-driven, so adding a theme = adding one `SkinPalette` entry.
Backgrounds are always YOUR theme; partner skins stay on their half of the
ring. The ringing screen's farewell depends on polled partner state (up to
~4s stale) -- hence the "only when certain" copy rule. Home nags once for a
display name (persistent card until saved), because an unnamed partner ships
as "Partner" forever.

---

### ADR-017 — Daily installs are arm64-only debug slices

**Status:** Accepted

**Context.** The universal debug APK shipped four ABIs at ~180 MB and grew
with every dependency; iteration on the one test device paid for all of them.

**Decision.** `tool/install.sh` builds `--split-per-abi` and installs the
arm64-v8a slice only (~1/3 the size). Still DEBUG: release builds carry
versionCode 2001+, and a later debug build is rejected as a downgrade whose
only fix is an uninstall that wipes the Supabase session (docs/14 gotcha 3).
Release builds remain available explicitly for distribution.

**Consequences.** Non-arm64 devices can no longer be installed by the script
without editing it -- acceptable; the project has exactly one device. The
universal APK still exists in `build/app/outputs/flutter-apk/` for whenever
it is needed.
